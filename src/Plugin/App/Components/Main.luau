local React = require(script.Parent.Parent.Parent.Parent.Packages.React)
local StudioComponents = require(script.Parent.Parent.Parent.Parent.Packages.StudioComponents)
local Wally = require(script.Parent.Parent.Parent.Wally)

local e = React.createElement

local function Main()
	return e(StudioComponents.Button, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Text = "Click me!",
		AutomaticSize = Enum.AutomaticSize.XY,
		OnActivated = function()
			-- Wally:getVersionMetadataAsync("littensy", "charm", "0.10.0")
		end,
	})
end

return Main
