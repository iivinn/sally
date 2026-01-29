local TabContainer = require(script.Parent.Parent.Components.TabContainer)
local React = require(script.Parent.Parent.Parent.Parent.Packages.React)
local ReactRoblox = require(script.Parent.Parent.Parent.Parent.Packages.ReactRoblox)

local controls = {}

local story = {
	react = React,
	reactRoblox = ReactRoblox,
	controls = controls,
	story = function()
		return React.createElement(TabContainer, {})
	end,
}

return story
