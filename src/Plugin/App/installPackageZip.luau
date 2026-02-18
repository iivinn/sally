local HttpService = game:GetService("HttpService")

local zzlib = require(script.Parent.Parent.Parent.Packages.Zzlib)

export type ResolvedDependency = {
	Scope: string,
	Name: string,
	Version: string,
	IndexKey: string,
}

export type InstallPackageOptions = {
	PackagesRoot: Instance,
	Name: string,
	Scope: string?,
	Version: string?,
	Dependencies: { [string]: ResolvedDependency }?,
	ExposeAlias: boolean?,
	AliasName: string?,
}

type ZipEntry = {
	Name: string,
	Offset: number,
	Size: number,
	Packed: boolean,
	CRC: number,
}

type InitDirectory = {
	ClassName: string,
	Source: string,
}

local function splitPath(path: string)
	local parts = {}
	for part in string.gmatch(path, "[^/]+") do
		table.insert(parts, part)
	end
	return parts
end

local function ensureContainerPath(root: Instance, parts: { string }, initDirectories: { [string]: InitDirectory })
	local current = root
	local traversedPathParts = {}
	for _, part in ipairs(parts) do
		table.insert(traversedPathParts, part)
		local traversedPath = table.concat(traversedPathParts, "/")
		local initDirectory = initDirectories[traversedPath]
		local child = current:FindFirstChild(part)
		if initDirectory then
			if child and child.ClassName ~= initDirectory.ClassName then
				child:Destroy()
				child = nil
			end
			if not child then
				child = Instance.new(initDirectory.ClassName)
				child.Name = part
				child.Parent = current
			end
			(child :: LuaSourceContainer).Source = initDirectory.Source
		else
			if child and not child:IsA("Folder") then
				child:Destroy()
				child = nil
			end
			if not child then
				child = Instance.new("Folder")
				child.Name = part
				child.Parent = current
			end
		end
		current = child
	end
	return current
end

local function getOrCreateFolder(parent: Instance, name: string)
	local child = parent:FindFirstChild(name)
	if child and not child:IsA("Folder") then
		child:Destroy()
		child = nil
	end
	if not child then
		child = Instance.new("Folder")
		child.Name = name
		child.Parent = parent
	end
	return child
end

local function extractFile(zipData: string, _name: string, offset: number, size: number, packed: boolean, crc: number)
	if packed then
		return zzlib.unzip(zipData, offset, crc)
	end
	return zipData:sub(offset, offset + size - 1)
end

local function toPascalCase(value: string)
	local parts = {}
	for part in string.gmatch(value, "[%w]+") do
		local first = part:sub(1, 1):upper()
		local rest = part:sub(2):lower()
		table.insert(parts, first .. rest)
	end
	return table.concat(parts, "")
end

local function writeLuaModule(parent: Instance, moduleName: string, source: string)
	local module = parent:FindFirstChild(moduleName)
	if module and not module:IsA("ModuleScript") then
		module:Destroy()
		module = nil
	end
	if not module then
		module = Instance.new("ModuleScript")
		module.Name = moduleName
		module.Parent = parent
	end
	module.Source = source
end

local function parseScriptFileName(fileName: string)
	local baseName = fileName:match("^(.*)%.lua[u]?$")
	if not baseName then
		return nil, nil, false
	end

	local serverBaseName = baseName:match("^(.*)%.server$")
	if serverBaseName then
		return "Script", serverBaseName, false
	end

	local clientBaseName = baseName:match("^(.*)%.client$")
	if clientBaseName then
		return "LocalScript", clientBaseName, false
	end

	return "ModuleScript", baseName, true
end

local function writeScriptInstance(parent: Instance, className: string, scriptName: string, source: string)
	local instance = parent:FindFirstChild(scriptName)
	if instance and instance.ClassName ~= className then
		instance:Destroy()
		instance = nil
	end
	if not instance then
		instance = Instance.new(className)
		instance.Name = scriptName
		instance.Parent = parent
	end
	(instance :: LuaSourceContainer).Source = source
end

local function isLuaFile(path: string)
	return path:match("%.lua[u]?$") ~= nil
end

local function normalizeModuleName(value: string)
	return string.lower(value:gsub("[^%w]", ""))
end

local function stripPrefix(path: string, prefix: string)
	if prefix == "" then
		return path
	end
	return path:sub(#prefix + 1)
end

local function normalizeProjectPath(path: string)
	local normalized = path:gsub("\\", "/"):gsub("^%./", ""):gsub("/+$", "")
	if normalized == "." or normalized == "" then
		return ""
	end
	return normalized .. "/"
end

local function prefixContainsLua(entries: { ZipEntry }, prefix: string)
	for _, entry in ipairs(entries) do
		local name = entry.Name
		if (prefix == "" or name:sub(1, #prefix) == prefix) and name:sub(-1) ~= "/" then
			local relative = stripPrefix(name, prefix)
			if relative ~= "" and isLuaFile(relative) then
				return true
			end
		end
	end
	return false
end

local function readDefaultProjectPrefix(entries: { ZipEntry }, zipData: string)
	for _, entry in ipairs(entries) do
		if entry.Name == "default.project.json" then
			local content = extractFile(zipData, entry.Name, entry.Offset, entry.Size, entry.Packed, entry.CRC)
			local ok, project = pcall(HttpService.JSONDecode, HttpService, content)
			if ok and type(project) == "table" then
				local tree = project.tree
				if type(tree) == "table" and type(tree["$path"]) == "string" then
					return normalizeProjectPath(tree["$path"])
				end
			end
			break
		end
	end
	return nil
end

local function chooseSourcePrefixWithHint(entries: { ZipEntry }, packageName: string, preferredPrefix: string?)
	if preferredPrefix and prefixContainsLua(entries, preferredPrefix) then
		return preferredPrefix
	end

	local normalizedPackageName = normalizeModuleName(packageName)
	local bestPrefix = ""
	local bestScore = -1

	for _, prefix in ipairs({ "src/", "lib/", "" }) do
		local luaCount = 0
		local topLevelLuaCount = 0
		local hasInit = false
		local hasPackageModule = false

		for _, entry in ipairs(entries) do
			local name = entry.Name
			if prefix == "" or name:sub(1, #prefix) == prefix then
				local relative = stripPrefix(name, prefix)
				if relative ~= "" and relative:sub(-1) ~= "/" and isLuaFile(relative) then
					luaCount += 1
					if not relative:find("/", 1, true) then
						topLevelLuaCount += 1
						if relative == "init.lua" or relative == "init.luau" then
							hasInit = true
						end
						local moduleName = relative:gsub("%.lua[u]?$", "")
						if normalizeModuleName(moduleName) == normalizedPackageName then
							hasPackageModule = true
						end
					end
				end
			end
		end

		local score = luaCount + topLevelLuaCount * 10
		if hasPackageModule then
			score += 500
		end
		if hasInit then
			score += 1000
		end

		if score > bestScore then
			bestScore = score
			bestPrefix = prefix
		end
	end

	return bestPrefix
end

local function collectZipEntries(zipData: string): { ZipEntry }
	local entries = {}
	for _, name, offset, size, packed, crc in zzlib.files(zipData) do
		table.insert(entries, {
			Name = name,
			Offset = offset,
			Size = size,
			Packed = packed,
			CRC = crc,
		})
	end
	return entries
end

local function chooseRootModule(entries: { ZipEntry }, zipData: string, sourcePrefix: string, packageName: string)
	local normalizedPackageName = normalizeModuleName(packageName)
	local packageCandidateSource = nil
	local packageCandidateRelative = nil
	local firstTopLevelModuleSource = nil
	local firstTopLevelModuleRelative = nil

	for _, entry in ipairs(entries) do
		local name = entry.Name
		if sourcePrefix == "" or name:sub(1, #sourcePrefix) == sourcePrefix then
			local relative = stripPrefix(name, sourcePrefix)
			if relative ~= "" and not relative:find("/", 1, true) and isLuaFile(relative) then
				local _, scriptName, isModuleScript = parseScriptFileName(relative)
				if isModuleScript and scriptName then
					local source = extractFile(zipData, name, entry.Offset, entry.Size, entry.Packed, entry.CRC)
					if relative == "init.lua" or relative == "init.luau" then
						return source, relative
					end
					if normalizeModuleName(scriptName) == normalizedPackageName then
						packageCandidateSource = source
						packageCandidateRelative = relative
					elseif not firstTopLevelModuleSource then
						firstTopLevelModuleSource = source
						firstTopLevelModuleRelative = relative
					end
				end
			end
		end
	end

	if packageCandidateSource then
		return packageCandidateSource, packageCandidateRelative
	end
	if firstTopLevelModuleSource then
		return firstTopLevelModuleSource, firstTopLevelModuleRelative
	end
	return "return {}", nil
end

local function collectInitDirectories(entries: { ZipEntry }, zipData: string, sourcePrefix: string)
	local initDirectories: { [string]: InitDirectory } = {}

	for _, entry in ipairs(entries) do
		local name = entry.Name
		if sourcePrefix == "" or name:sub(1, #sourcePrefix) == sourcePrefix then
			local relative = stripPrefix(name, sourcePrefix)
			if relative ~= "" and relative:sub(-1) ~= "/" and isLuaFile(relative) then
				local parts = splitPath(relative)
				local fileName = table.remove(parts)
				local className, scriptName = parseScriptFileName(fileName)
				if className and scriptName == "init" and #parts > 0 then
					local directoryPath = table.concat(parts, "/")
					local source = extractFile(zipData, name, entry.Offset, entry.Size, entry.Packed, entry.CRC)
					initDirectories[directoryPath] = {
						ClassName = className,
						Source = source,
					}
				end
			end
		end
	end

	return initDirectories
end

local function materializeInitDirectories(root: Instance, initDirectories: { [string]: InitDirectory })
	local directoryPaths = {}
	for directoryPath in pairs(initDirectories) do
		table.insert(directoryPaths, directoryPath)
	end

	table.sort(directoryPaths, function(left, right)
		if #left ~= #right then
			return #left < #right
		end
		return left < right
	end)

	for _, directoryPath in ipairs(directoryPaths) do
		ensureContainerPath(root, splitPath(directoryPath), initDirectories)
	end
end

local function writeEntry(
	root: Instance,
	initDirectories: { [string]: InitDirectory },
	zipData: string,
	name: string,
	offset: number,
	size: number,
	packed: boolean,
	crc: number
)
	if name:sub(-1) == "/" then
		return
	end

	local parts = splitPath(name)
	local fileName = table.remove(parts)
	local className, scriptName = parseScriptFileName(fileName)
	if not className or not scriptName then
		return
	end
	if scriptName == "init" then
		return
	end

	local dir = ensureContainerPath(root, parts, initDirectories)
	local content = extractFile(zipData, name, offset, size, packed, crc)
	writeScriptInstance(dir, className, scriptName, content)
end

local function buildIndexKey(scope: string?, packageName: string, version: string?)
	if scope and version then
		return string.format("%s_%s@%s", scope, packageName, version)
	elseif version then
		return string.format("%s@%s", packageName, version)
	end
	return packageName
end

local function writeDependencyThunk(indexPackageFolder: Instance, dependencyAlias: string, dependencyIndexKey: string, dependencyName: string)
	local source = string.format(
		"return require(script.Parent.Parent[%q][%q])",
		dependencyIndexKey,
		dependencyName
	)
	writeLuaModule(indexPackageFolder, dependencyAlias, source)
end

local function getOrCreateModule(parent: Instance, moduleName: string)
	local module = parent:FindFirstChild(moduleName)
	if module and not module:IsA("ModuleScript") then
		module:Destroy()
		module = nil
	end
	if not module then
		module = Instance.new("ModuleScript")
		module.Name = moduleName
		module.Parent = parent
	end
	return module :: ModuleScript
end

local function installPackageZip(zipData: string, options: InstallPackageOptions)
	local packagesRoot = options.PackagesRoot
	local packageName = options.Name
	local scope = options.Scope
	local version = options.Version
	local dependencies = options.Dependencies or {}
	local exposeAlias = options.ExposeAlias ~= false

	local indexKey = buildIndexKey(scope, packageName, version)
	local indexRoot = getOrCreateFolder(packagesRoot, "_Index")
	local indexPackageFolder = getOrCreateFolder(indexRoot, indexKey)

	for _, child in ipairs(indexPackageFolder:GetChildren()) do
		child:Destroy()
	end

	local entries = collectZipEntries(zipData)
	local defaultProjectPrefix = readDefaultProjectPrefix(entries, zipData)
	local sourcePrefix = chooseSourcePrefixWithHint(entries, packageName, defaultProjectPrefix)
	local rootSource, rootRelativePath = chooseRootModule(entries, zipData, sourcePrefix, packageName)
	local initDirectories = collectInitDirectories(entries, zipData, sourcePrefix)

	local packageModule = getOrCreateModule(indexPackageFolder, packageName)
	for _, child in ipairs(packageModule:GetChildren()) do
		child:Destroy()
	end
	packageModule.Source = rootSource
	materializeInitDirectories(packageModule, initDirectories)

	for _, entry in ipairs(entries) do
		local name = entry.Name
		if sourcePrefix == "" or name:sub(1, #sourcePrefix) == sourcePrefix then
			local relative = stripPrefix(name, sourcePrefix)
			if relative ~= "" and relative ~= rootRelativePath and isLuaFile(relative) then
				writeEntry(
					packageModule,
					initDirectories,
					zipData,
					relative,
					entry.Offset,
					entry.Size,
					entry.Packed,
					entry.CRC
				)
			end
		end
	end

	local dependencyAliases = {}
	for dependencyAlias in pairs(dependencies) do
		table.insert(dependencyAliases, dependencyAlias)
	end
	table.sort(dependencyAliases)

	for _, dependencyAlias in ipairs(dependencyAliases) do
		local dependency = dependencies[dependencyAlias]
		if dependency and dependency.IndexKey and dependency.Name then
			writeDependencyThunk(indexPackageFolder, dependencyAlias, dependency.IndexKey, dependency.Name)
		end
	end

	if exposeAlias then
		local aliasName = options.AliasName or toPascalCase(packageName)
		local source = string.format(
			"return require(script.Parent._Index[%q][%q])",
			indexKey,
			packageName
		)
		writeLuaModule(packagesRoot, aliasName, source)
	end

	return indexKey
end

return installPackageZip
