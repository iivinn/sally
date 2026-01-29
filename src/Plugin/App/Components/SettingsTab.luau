local React = require(script.Parent.Parent.Parent.Parent.Packages.React)
local StudioComponents = require(script.Parent.Parent.Parent.Parent.Packages.StudioComponents)

local e = React.createElement

function SettingsTab()
	return e("Frame", {})
end

return SettingsTab
