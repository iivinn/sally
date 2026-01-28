local React = require(script.Parent.Parent.Parent.Parent.Packages.React)
local ReactRoblox = require(script.Parent.Parent.Parent.Parent.Packages.ReactRoblox)
local UiLabs = require(script.Parent.Parent.Parent.Parent.Packages.UiLabs)

local CreateReactStory = UiLabs.CreateReactStory
local Main = require(script.Parent.Parent.Components.Main)

local story = CreateReactStory({
	react = React,
	reactRoblox = ReactRoblox,
	controls = {},
}, function(props)
	local component = React.createElement(Main, {})
	return component
end)

return story
