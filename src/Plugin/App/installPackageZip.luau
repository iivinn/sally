local zzlib = require(script.Parent.Parent.Parent.Packages.Zzlib)

local function splitPath(path: string)
	local parts = {}
	for part in string.gmatch(path, "[^/]+") do
		table.insert(parts, part)
	end
	return parts
end

local function ensureFolder(root: Instance, parts: { string })
	local current = root
	for _, part in ipairs(parts) do
		local child = current:FindFirstChild(part)
		if not child then
			child = Instance.new("Folder")
			child.Name = part
			child.Parent = current
		end
		current = child
	end
	return current
end

local function getOrCreateFolder(parent: Instance, name: string)
	local child = parent:FindFirstChild(name)
	if not child then
		child = Instance.new("Folder")
		child.Name = name
		child.Parent = parent
	end
	return child
end

local function extractFile(zipData: string, name: string, offset: number, size: number, packed: boolean, crc: number)
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

local function writeEntry(root: Instance, zipData: string, name: string, offset: number, size: number, packed: boolean, crc: number)
	if name:sub(-1) == "/" then
		return
	end

	local parts = splitPath(name)
	local fileName = table.remove(parts)
	local className, scriptName = parseScriptFileName(fileName)
	if not className or not scriptName then
		return
	end

	local dir = ensureFolder(root, parts)
	local content = extractFile(zipData, name, offset, size, packed, crc)
	writeScriptInstance(dir, className, scriptName, content)
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

local function chooseSourcePrefix(entries, packageName: string)
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

local function installPackageZip(zipData: string, packageFolder: Instance)
	local packagesRoot = packageFolder.Parent
	if not packagesRoot then
		return
	end

	local packageName = packageFolder.Name
	local aliasName = toPascalCase(packageName)
	local scope = packageFolder:GetAttribute("Scope")
	local version = packageFolder:GetAttribute("Version")

	local indexKey
	if scope and version then
		indexKey = string.format("%s_%s@%s", scope, packageName, version)
	elseif version then
		indexKey = string.format("%s@%s", packageName, version)
	else
		indexKey = packageName
	end

	local indexRoot = getOrCreateFolder(packagesRoot, "_Index")
	local indexPackageFolder = getOrCreateFolder(indexRoot, indexKey)

	for _, child in ipairs(indexPackageFolder:GetChildren()) do
		child:Destroy()
	end

	packageFolder:Destroy()

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

	local sourcePrefix = chooseSourcePrefix(entries, packageName)
	local normalizedPackageName = normalizeModuleName(packageName)
	local rootModuleWritten = false
	local fallbackModuleSource = nil
	local firstTopLevelModuleSource = nil
	for _, entry in ipairs(entries) do
		local name = entry.Name
		if sourcePrefix == "" or name:sub(1, #sourcePrefix) == sourcePrefix then
			local relative = stripPrefix(name, sourcePrefix)
			if relative == "init.lua" or relative == "init.luau" then
				local content = extractFile(zipData, name, entry.Offset, entry.Size, entry.Packed, entry.CRC)
				writeLuaModule(indexPackageFolder, packageName, content)
				rootModuleWritten = true
			elseif relative ~= "" then
				if isLuaFile(relative) and not relative:find("/", 1, true) then
					local moduleName = relative:gsub("%.lua[u]?$", "")
					local _, _, isModuleScript = parseScriptFileName(relative)
					if isModuleScript then
						local source = extractFile(zipData, name, entry.Offset, entry.Size, entry.Packed, entry.CRC)
						if normalizeModuleName(moduleName) == normalizedPackageName then
							fallbackModuleSource = source
						elseif not firstTopLevelModuleSource then
							firstTopLevelModuleSource = source
						end
					end
				end

				writeEntry(indexPackageFolder, zipData, relative, entry.Offset, entry.Size, entry.Packed, entry.CRC)
			end
		end
	end
	if not rootModuleWritten then
		if fallbackModuleSource then
			writeLuaModule(indexPackageFolder, packageName, fallbackModuleSource)
		elseif firstTopLevelModuleSource then
			writeLuaModule(indexPackageFolder, packageName, firstTopLevelModuleSource)
		else
			writeLuaModule(indexPackageFolder, packageName, "return {}")
		end
	end

	local entryModule = packagesRoot:FindFirstChild(aliasName)
	if entryModule and not entryModule:IsA("ModuleScript") then
		entryModule:Destroy()
		entryModule = nil
	end
	if not entryModule then
		entryModule = Instance.new("ModuleScript")
		entryModule.Name = aliasName
		entryModule.Parent = packagesRoot
	end

	entryModule.Source = string.format(
		'return require(script.Parent._Index["%s"]["%s"])',
		indexKey,
		packageName
	)
end

return installPackageZip
