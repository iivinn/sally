local Main = require(script.Components.Main)
local React = require(script.Parent.Parent.Packages.React)
local ReactRobloxStudioPlugin = require(script.Parent.Parent.Packages.ReactRobloxStudioPlugin)

local Toolbar = ReactRobloxStudioPlugin.Toolbar
local ToolbarButton = ReactRobloxStudioPlugin.ToolbarButton
local Widget = ReactRobloxStudioPlugin.Widget

local useToggle = require(script.Hooks.useToggle)

local e = React.createElement

local function App()
	local widgetEnabled, setWidgetState = useToggle(false)

	return e(
		React.Fragment,
		nil,
		e(
			Toolbar,
			{
				name = "Sally",
			},
			e(ToolbarButton, {
				id = "toggle-widget",
				text = "Sally",
				onClick = setWidgetState.toggle,
			})
		),
		e(Widget, {
			id = "sally-widget",
			title = "Sally",
			enabled = widgetEnabled,
			minSize = Vector2.new(320, 240),
			initialDockState = Enum.InitialDockState.Float,
			initialFloatSize = Vector2.new(320, 240),
			onClose = setWidgetState.off,
		}, e(Main, {}))
	)
end

return App
