local React = require(script.Parent.Parent.Parent.Parent.Packages.React)
local StudioComponents = require(script.Parent.Parent.Parent.Parent.Packages.StudioComponents)
local SearchTab = require(script.Parent.SearchTab)
local SettingsTab = require(script.Parent.SettingsTab)

local e = React.createElement

local function NavBar()
	local selectedTab, setSelectedTab = React.useState("Search")

	return e(StudioComponents.TabContainer, {
		SelectedTab = selectedTab,
		OnTabSelected = setSelectedTab,
	}, {
		["Search"] = {
			LayoutOrder = 1,
			Content = e(SearchTab, {}),
		},
		["Settings"] = {
			LayoutOrder = 2,
			Content = e(SettingsTab, {}),
		},
	})
end

return NavBar
