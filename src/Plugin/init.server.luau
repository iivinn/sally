local React = require(script.Parent.Packages.React)
local ReactRoblox = require(script.Parent.Packages.ReactRoblox)
local ReactRobloxStudioPlugin = require(script.Parent.Packages.ReactRobloxStudioPlugin)

local RobloxPlugin = ReactRobloxStudioPlugin.RobloxPlugin
local App = require(script.App)

local container = Instance.new("Folder")
container.Name = "Sally"
local root = ReactRoblox.createRoot(container)

local app = React.createElement(RobloxPlugin, {
	plugin = plugin,
}, React.createElement(App))

root:render(app, container)
