local React = require(script.Parent.Parent.Parent.Parent.Packages.React)
local TabContainer = require(script.Parent.TabContainer)

local e = React.createElement

local function Main()
	return e(TabContainer, {})
end

return Main
