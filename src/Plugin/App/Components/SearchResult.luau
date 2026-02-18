local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Logger = require(script.Parent.Parent.Logger)
local React = require(script.Parent.Parent.Parent.Parent.Packages.React)
local StudioComponents = require(script.Parent.Parent.Parent.Parent.Packages.StudioComponents)
local Wally = require(script.Parent.Parent.Wally)
local installPackage = require(script.Parent.Parent.installPackage)

local e = React.createElement

local function isPrereleaseVersion(version: string)
	return version:find("-", 1, true) ~= nil
end

local function pickDefaultVersion(versionList: { string })
	for _, version in ipairs(versionList) do
		if not isPrereleaseVersion(version) then
			return version
		end
	end
	return versionList[1]
end

function SearchResult(props: { Scope: string, Name: string, Versions: {} })
	local versions, setVersions = React.useState(props.Versions or {})
	local selected, setSelected = React.useState(props.Versions and pickDefaultVersion(props.Versions) or nil)

	React.useEffect(function()
		setVersions(props.Versions or {})
		setSelected(props.Versions and pickDefaultVersion(props.Versions) or nil)

		local body = Wally:GetPackageMetadata(props.Scope, props.Name)
		if not body then
			return
		end

		local decodeSuccess, metadata = pcall(HttpService.JSONDecode, HttpService, body)
		if not decodeSuccess or type(metadata) ~= "table" or type(metadata.versions) ~= "table" then
			return
		end

		local allVersions = {}
		local seen = {}
		for _, versionEntry in ipairs(metadata.versions) do
			local version = versionEntry and versionEntry.package and versionEntry.package.version
			if type(version) == "string" and not seen[version] then
				seen[version] = true
				table.insert(allVersions, version)
			end
		end

		if #allVersions == 0 then
			for _, versionEntry in pairs(metadata.versions) do
				local version = versionEntry and versionEntry.package and versionEntry.package.version
				if type(version) == "string" and not seen[version] then
					seen[version] = true
					table.insert(allVersions, version)
				end
			end
		end

		if #allVersions > 0 then
			setVersions(allVersions)
			if not table.find(allVersions, selected) then
				setSelected(pickDefaultVersion(allVersions))
			end
		end
	end, { props.Scope, props.Name })

	local displayText = React.useMemo(function()
		return string.format("%s/%s@%s", props.Scope, props.Name, selected)
	end, { selected })

	return e(
		StudioComponents.DropShadowFrame,
		{ Size = UDim2.new(1, 0, 0, 128) },
		e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 16),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
			e(StudioComponents.Label, {
				LayoutOrder = 1,
				Text = displayText or "",
				Size = UDim2.new(1, 0, 0, 0),
			}),
			e(StudioComponents.Dropdown, {
				LayoutOrder = 2,
				Size = UDim2.new(0, 128, 0, 32),
				Items = versions or {},
				SelectedItem = selected,
				DefaultText = "Select version...",
				OnItemSelected = setSelected,
			}),
			e(StudioComponents.MainButton, {
				LayoutOrder = 3,
				Text = "Install",
				AutomaticSize = Enum.AutomaticSize.XY,
				OnActivated = function()
					if not selected then
						Logger:Warn(`No version selected for {props.Scope}/{props.Name}`)
						return
					end

					local packagesRoot = ReplicatedStorage:FindFirstChild("Packages")
					if not packagesRoot then
						packagesRoot = Instance.new("Folder")
						packagesRoot.Name = "Packages"
						packagesRoot.Parent = ReplicatedStorage
					end

					local ok, success, errorMessage = pcall(installPackage, props.Scope, props.Name, selected, packagesRoot)
					if not ok then
						Logger:Error(`Unexpected install crash for {props.Scope}/{props.Name}@{selected}: {tostring(success)}`)
						return
					end

					if success then
						Logger:Info(`Installed {props.Scope}/{props.Name}@{selected}`)
					else
						Logger:Error(
							`Failed to install {props.Scope}/{props.Name}@{selected}: {errorMessage or "Unknown error"}`
						)
					end
				end,
			})
	)
end

return SearchResult
