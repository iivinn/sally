local HttpService = game:GetService("HttpService")

local Logger = require(script.Parent.Logger)
local Wally = require(script.Parent.Wally)
local installPackageZip = require(script.Parent.installPackageZip)

type Semver = {
	Major: number,
	Minor: number,
	Patch: number,
	Prerelease: { string },
}

type ResolvedDependency = {
	Scope: string,
	Name: string,
	Version: string,
	IndexKey: string,
}

type ResolvedPackage = {
	Scope: string,
	Name: string,
	Version: string,
	IndexKey: string,
	Dependencies: { [string]: ResolvedDependency },
}

type ResolverState = {
	Resolved: { [string]: ResolvedPackage },
	Resolving: { [string]: boolean },
	MetadataCache: { [string]: any },
	InstallOrder: { string },
}

local function trim(value: string)
	return value:match("^%s*(.-)%s*$") or ""
end

local function splitLiteral(value: string, delimiter: string)
	local out = {}
	local start = 1
	while true do
		local i, j = string.find(value, delimiter, start, true)
		if not i then
			table.insert(out, value:sub(start))
			break
		end
		table.insert(out, value:sub(start, i - 1))
		start = j + 1
	end
	return out
end

local function parseSemver(version: string): Semver?
	local normalized = trim(version)
	normalized = normalized:gsub("^[vV]", "")
	if normalized == "" then
		return nil
	end

	local withoutBuild = normalized:match("^([^+]+)") or normalized
	local core = withoutBuild
	local prereleaseRaw = nil
	local separator = string.find(withoutBuild, "-", 1, true)
	if separator then
		core = withoutBuild:sub(1, separator - 1)
		prereleaseRaw = withoutBuild:sub(separator + 1)
	end

	local pieces = splitLiteral(core, ".")
	if #pieces < 1 or #pieces > 3 then
		return nil
	end

	local major = tonumber(pieces[1])
	local minor = tonumber(pieces[2] or "0")
	local patch = tonumber(pieces[3] or "0")

	if not major or not minor or not patch then
		return nil
	end

	local prerelease = {}
	if prereleaseRaw and prereleaseRaw ~= "" then
		for _, prereleasePart in ipairs(splitLiteral(prereleaseRaw, ".")) do
			table.insert(prerelease, prereleasePart)
		end
	end

	return {
		Major = major,
		Minor = minor,
		Patch = patch,
		Prerelease = prerelease,
	}
end

local function compareSemver(a: Semver, b: Semver): number
	if a.Major ~= b.Major then
		return a.Major < b.Major and -1 or 1
	end
	if a.Minor ~= b.Minor then
		return a.Minor < b.Minor and -1 or 1
	end
	if a.Patch ~= b.Patch then
		return a.Patch < b.Patch and -1 or 1
	end

	local aPre = a.Prerelease
	local bPre = b.Prerelease
	if #aPre == 0 and #bPre == 0 then
		return 0
	end
	if #aPre == 0 then
		return 1
	end
	if #bPre == 0 then
		return -1
	end

	local maxLength = math.max(#aPre, #bPre)
	for i = 1, maxLength do
		local aPart = aPre[i]
		local bPart = bPre[i]
		if aPart == nil then
			return -1
		end
		if bPart == nil then
			return 1
		end
		if aPart ~= bPart then
			local aNum = tonumber(aPart)
			local bNum = tonumber(bPart)
			if aNum and bNum then
				return aNum < bNum and -1 or 1
			elseif aNum and not bNum then
				return -1
			elseif not aNum and bNum then
				return 1
			else
				return aPart < bPart and -1 or 1
			end
		end
	end

	return 0
end

local function buildSemver(major: number, minor: number, patch: number): Semver
	return {
		Major = major,
		Minor = minor,
		Patch = patch,
		Prerelease = {},
	}
end

local function satisfiesComparator(version: Semver, operator: string, target: Semver): boolean
	local comparison = compareSemver(version, target)
	if operator == "=" then
		return comparison == 0
	elseif operator == ">" then
		return comparison > 0
	elseif operator == ">=" then
		return comparison >= 0
	elseif operator == "<" then
		return comparison < 0
	elseif operator == "<=" then
		return comparison <= 0
	end
	return false
end

local function parseClauseTargetVersion(clauseRaw: string): (string?, Semver?)
	local clause = trim(clauseRaw)
	if clause == "" or clause == "*" then
		return nil, nil
	end

	local prefix = clause:sub(1, 1)
	if prefix == "^" or prefix == "~" then
		local value = trim(clause:sub(2))
		return value, parseSemver(value)
	end

	local operator = "="
	local targetVersion = clause
	local firstTwo = clause:sub(1, 2)
	local firstOne = clause:sub(1, 1)
	if firstTwo == ">=" or firstTwo == "<=" then
		operator = firstTwo
		targetVersion = trim(clause:sub(3))
	elseif firstOne == ">" or firstOne == "<" or firstOne == "=" then
		operator = firstOne
		targetVersion = trim(clause:sub(2))
	end

	if targetVersion == "" then
		return nil, nil
	end

	return targetVersion, parseSemver(targetVersion)
end

local function requirementAllowsPrerelease(requirementRaw: string?, candidateVersion: string): boolean
	local requirement = trim(requirementRaw or "")
	if requirement == "" or requirement == "*" then
		return false
	end

	local exactRequirement = requirement
	if exactRequirement:sub(1, 1) == "=" then
		exactRequirement = trim(exactRequirement:sub(2))
	end
	if exactRequirement == candidateVersion then
		return true
	end

	for _, disjunctionRaw in ipairs(splitLiteral(requirement, "||")) do
		for _, clauseRaw in ipairs(splitLiteral(disjunctionRaw, ",")) do
			local _, target = parseClauseTargetVersion(clauseRaw)
			if target and #target.Prerelease > 0 then
				return true
			end
		end
	end

	return false
end

local function satisfiesClause(version: Semver, clauseRaw: string): boolean
	local clause = trim(clauseRaw)
	if clause == "" or clause == "*" then
		return true
	end

	local prefix = clause:sub(1, 1)
	if prefix == "^" then
		local base = parseSemver(clause:sub(2))
		if not base then
			return false
		end
		local upperBound
		if base.Major > 0 then
			upperBound = buildSemver(base.Major + 1, 0, 0)
		elseif base.Minor > 0 then
			upperBound = buildSemver(0, base.Minor + 1, 0)
		else
			upperBound = buildSemver(0, 0, base.Patch + 1)
		end
		return satisfiesComparator(version, ">=", base) and satisfiesComparator(version, "<", upperBound)
	elseif prefix == "~" then
		local base = parseSemver(clause:sub(2))
		if not base then
			return false
		end
		local upperBound = buildSemver(base.Major, base.Minor + 1, 0)
		return satisfiesComparator(version, ">=", base) and satisfiesComparator(version, "<", upperBound)
	end

	local operator = "="
	local targetVersion = clause
	local firstTwo = clause:sub(1, 2)
	local firstOne = clause:sub(1, 1)
	if firstTwo == ">=" or firstTwo == "<=" then
		operator = firstTwo
		targetVersion = trim(clause:sub(3))
	elseif firstOne == ">" or firstOne == "<" or firstOne == "=" then
		operator = firstOne
		targetVersion = trim(clause:sub(2))
	end

	if targetVersion == "" then
		return false
	end

	local target = parseSemver(targetVersion)
	if not target then
		return false
	end

	return satisfiesComparator(version, operator, target)
end

local function satisfiesRequirement(versionString: string, requirementRaw: string?): boolean
	local requirement = trim(requirementRaw or "")
	if requirement == "" or requirement == "*" then
		return true
	end

	local version = parseSemver(versionString)
	if not version then
		return false
	end
	if #version.Prerelease > 0 and not requirementAllowsPrerelease(requirement, versionString) then
		return false
	end

	for _, disjunctionRaw in ipairs(splitLiteral(requirement, "||")) do
		local disjunction = trim(disjunctionRaw)
		if disjunction ~= "" then
			local allSatisfied = true
			for _, clauseRaw in ipairs(splitLiteral(disjunction, ",")) do
				if not satisfiesClause(version, clauseRaw) then
					allSatisfied = false
					break
				end
			end
			if allSatisfied then
				return true
			end
		end
	end

	return false
end

local function parsePackageSpec(specRaw: string)
	local spec = trim(specRaw)
	local scope, name, requirement = spec:match("^([^/]+)/([^@]+)@(.+)$")
	if scope and name and requirement then
		return scope, name, trim(requirement)
	end

	local noVersionScope, noVersionName = spec:match("^([^/]+)/([^@]+)$")
	if noVersionScope and noVersionName then
		return noVersionScope, noVersionName, "*"
	end

	return nil, nil, nil
end

local function buildPackageId(scope: string, name: string)
	return string.format("%s/%s", scope, name)
end

local function buildIndexKey(scope: string, name: string, version: string)
	return string.format("%s_%s@%s", scope, name, version)
end

local function getCachedMetadata(state: ResolverState, scope: string, name: string)
	local packageId = buildPackageId(scope, name)
	local cached = state.MetadataCache[packageId]
	if cached then
		return cached
	end

	local body = Wally:GetPackageMetadata(scope, name)
	if not body then
		return nil
	end

	local decodeSuccess, decoded = pcall(HttpService.JSONDecode, HttpService, body)
	if not decodeSuccess or type(decoded) ~= "table" then
		return nil
	end

	state.MetadataCache[packageId] = decoded
	return decoded
end

local function collectVersionEntries(metadata: any)
	local versions = {}
	if type(metadata) ~= "table" or type(metadata.versions) ~= "table" then
		return versions
	end

	for _, versionEntry in pairs(metadata.versions) do
		if versionEntry and versionEntry.package and versionEntry.package.version then
			table.insert(versions, versionEntry)
		end
	end

	return versions
end

local function chooseVersionEntry(metadata: any, requirement: string?)
	local versions = collectVersionEntries(metadata)

	local trimmedRequirement = trim(requirement or "")
	local exactRequirement = trimmedRequirement
	if exactRequirement:sub(1, 1) == "=" then
		exactRequirement = trim(exactRequirement:sub(2))
	end
	if exactRequirement ~= ""
		and not exactRequirement:find("[<>~^|*,]", 1, false)
	then
		for _, versionEntry in ipairs(versions) do
			if tostring(versionEntry.package.version) == exactRequirement then
				return versionEntry
			end
		end
	end

	table.sort(versions, function(a, b)
		local aVersion = parseSemver(a.package.version)
		local bVersion = parseSemver(b.package.version)
		if aVersion and bVersion then
			return compareSemver(aVersion, bVersion) > 0
		end
		return tostring(a.package.version) > tostring(b.package.version)
	end)

	for _, versionEntry in ipairs(versions) do
		local version = versionEntry.package.version
		if satisfiesRequirement(version, requirement) then
			return versionEntry
		end
	end

	return nil
end

local function resolvePackage(state: ResolverState, scope: string, name: string, requirement: string?): (ResolvedPackage?, string?)
	local packageId = buildPackageId(scope, name)

	local existing = state.Resolved[packageId]
	if existing then
		if requirement and not satisfiesRequirement(existing.Version, requirement) then
			return nil, string.format(
				"Dependency conflict for %s: resolved %s does not satisfy %s",
				packageId,
				existing.Version,
				requirement
			)
		end
		return existing, nil
	end

	if state.Resolving[packageId] then
		return nil, string.format("Cyclic dependency detected while resolving %s", packageId)
	end
	state.Resolving[packageId] = true

	local metadata = getCachedMetadata(state, scope, name)
	if not metadata then
		state.Resolving[packageId] = nil
		return nil, string.format("Failed to fetch metadata for %s", packageId)
	end

	local versionEntry = chooseVersionEntry(metadata, requirement)
	if not versionEntry then
		local availableVersions = {}
		for _, candidate in ipairs(collectVersionEntries(metadata)) do
			table.insert(availableVersions, tostring(candidate.package.version))
		end
		local availableSample = table.concat(availableVersions, ", ")
		state.Resolving[packageId] = nil
		return nil, string.format(
			"No version of %s satisfies %s (available: %s)",
			packageId,
			requirement or "*",
			availableSample ~= "" and availableSample or "none"
		)
	end

	local version = versionEntry.package.version
	local mergedDependencies = {}

	for dependencyAlias, dependencySpec in pairs(versionEntry.dependencies or {}) do
		mergedDependencies[dependencyAlias] = dependencySpec
	end
	for dependencyAlias, dependencySpec in pairs(versionEntry["server-dependencies"] or {}) do
		mergedDependencies[dependencyAlias] = dependencySpec
	end

	local dependencyAliases = {}
	for dependencyAlias in pairs(mergedDependencies) do
		table.insert(dependencyAliases, dependencyAlias)
	end
	table.sort(dependencyAliases)

	local resolvedDependencies = {}
	for _, dependencyAlias in ipairs(dependencyAliases) do
		local dependencySpec = mergedDependencies[dependencyAlias]
		local dependencyScope, dependencyName, dependencyRequirement = parsePackageSpec(dependencySpec)
		if not dependencyScope or not dependencyName then
			state.Resolving[packageId] = nil
			return nil, string.format("Invalid dependency spec %q in %s", tostring(dependencySpec), packageId)
		end

		local resolvedDependency, dependencyError = resolvePackage(state, dependencyScope, dependencyName, dependencyRequirement)
		if not resolvedDependency then
			state.Resolving[packageId] = nil
			return nil, dependencyError
		end

		resolvedDependencies[dependencyAlias] = {
			Scope = resolvedDependency.Scope,
			Name = resolvedDependency.Name,
			Version = resolvedDependency.Version,
			IndexKey = resolvedDependency.IndexKey,
		}
	end

	local resolved: ResolvedPackage = {
		Scope = scope,
		Name = name,
		Version = version,
		IndexKey = buildIndexKey(scope, name, version),
		Dependencies = resolvedDependencies,
	}

	state.Resolving[packageId] = nil
	state.Resolved[packageId] = resolved
	table.insert(state.InstallOrder, packageId)

	return resolved, nil
end

local function installPackage(scope: string, name: string, version: string, packagesRoot: Instance)
	local state: ResolverState = {
		Resolved = {},
		Resolving = {},
		MetadataCache = {},
		InstallOrder = {},
	}

	local rootRequirement = version
	local rootPackage, resolveError = resolvePackage(state, scope, name, rootRequirement)
	if not rootPackage then
		return false, resolveError
	end

	local rootId = buildPackageId(scope, name)
	for _, packageId in ipairs(state.InstallOrder) do
		local resolvedPackage = state.Resolved[packageId]
		if not resolvedPackage then
			return false, string.format("Missing resolved package for %s", packageId)
		end

		local zipData = Wally:GetPackageContents(resolvedPackage.Scope, resolvedPackage.Name, resolvedPackage.Version)
		if not zipData then
			return false, string.format(
				"Failed to fetch package contents for %s@%s",
				buildPackageId(resolvedPackage.Scope, resolvedPackage.Name),
				resolvedPackage.Version
			)
		end

		local ok, installError = pcall(installPackageZip, zipData, {
			PackagesRoot = packagesRoot,
			Scope = resolvedPackage.Scope,
			Name = resolvedPackage.Name,
			Version = resolvedPackage.Version,
			Dependencies = resolvedPackage.Dependencies,
			ExposeAlias = packageId == rootId,
		})
		if not ok then
			return false, string.format("Failed to install %s: %s", packageId, tostring(installError))
		end
	end

	Logger:Info(string.format("Installed %d packages for %s@%s", #state.InstallOrder, buildPackageId(scope, name), version))
	return true
end

return installPackage
