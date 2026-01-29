local SearchResult = require(script.Parent.Parent.Components.SearchResult)
local React = require(script.Parent.Parent.Parent.Parent.Packages.React)
local ReactRoblox = require(script.Parent.Parent.Parent.Parent.Packages.ReactRoblox)

local controls = {}

local story = {
	react = React,
	reactRoblox = ReactRoblox,
	controls = controls,
	story = function()
		return React.createElement(SearchResult, {})
	end,
}

return story
