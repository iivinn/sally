local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Logger = require(script.Parent.Parent.Logger)
local React = require(script.Parent.Parent.Parent.Parent.Packages.React)
local StudioComponents = require(script.Parent.Parent.Parent.Parent.Packages.StudioComponents)
local Wally = require(script.Parent.Parent.Wally)
local installPackageZip = require(script.Parent.Parent.installPackageZip)

local packagesRoot = ReplicatedStorage:FindFirstChild("Packages")
if not packagesRoot then
    packagesRoot = Instance.new("Folder")
    packagesRoot.Name = "Packages"
    packagesRoot.Parent = ReplicatedStorage
end

local e = React.createElement

function SearchResult(props: { Scope: string, Name: string, Versions: {} })
	local selected, setSelected = React.useState(props.Versions and props.Versions[1] or nil)

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
			Items = props.Versions or {},
			SelectedItem = selected,
			DefaultText = "Select version...",
			OnItemSelected = setSelected,
		}),
		e(StudioComponents.MainButton, {
			LayoutOrder = 3,
			Text = "Install",
			AutomaticSize = Enum.AutomaticSize.XY,
			OnActivated = function()
    			local zipData = Wally:GetPackageContents(props.Scope, props.Name, selected)
                if zipData then
                    local packageFolder = Instance.new("Folder")
                    packageFolder.Name = props.Name
                    packageFolder:SetAttribute("Scope", props.Scope)
                    packageFolder:SetAttribute("Version", selected)
                    packageFolder.Parent = packagesRoot
                    installPackageZip(zipData, packageFolder)
                    Logger:Info(`Installed {props.Scope}/{props.Name}@{selected}`)
                else
                    Logger:Error(`Failed to fetch package contents for {props.Scope}/{props.Name}@{selected}`)
                end
			end,
		})
	)
end

return SearchResult
