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

local function writeEntry(root: Instance, zipData: string, name: string, offset: number, size: number, packed: boolean, crc: number)
	if name:sub(-1) == "/" then
		return
	end

	local parts = splitPath(name)
	local fileName = table.remove(parts)
	local dir = ensureFolder(root, parts)

	local content = extractFile(zipData, name, offset, size, packed, crc)

	if fileName:match("%.lua[u]?$") then
		local moduleName = fileName:gsub("%.lua[u]?$", "")
		writeLuaModule(dir, moduleName, content)
	else
		local value = Instance.new("StringValue")
		value.Name = fileName
		value.Value = content
		value.Parent = dir
	end
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

	local rootModuleWritten = false
	local fallbackModuleSource = nil
	for _, name, offset, size, packed, crc in zzlib.files(zipData) do
		if name:sub(1, 4) == "src/" then
			local relative = name:sub(5)
			if relative == "init.lua" or relative == "init.luau" then
				local content = extractFile(zipData, name, offset, size, packed, crc)
				writeLuaModule(indexPackageFolder, packageName, content)
				rootModuleWritten = true
			elseif relative == packageName .. ".lua" or relative == packageName .. ".luau" then
				fallbackModuleSource = extractFile(zipData, name, offset, size, packed, crc)
				writeEntry(indexPackageFolder, zipData, relative, offset, size, packed, crc)
			elseif relative ~= "" then
				writeEntry(indexPackageFolder, zipData, relative, offset, size, packed, crc)
			end
		end
	end
	if not rootModuleWritten then
		if fallbackModuleSource then
			writeLuaModule(indexPackageFolder, packageName, fallbackModuleSource)
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
