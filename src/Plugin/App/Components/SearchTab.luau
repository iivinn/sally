local HttpService = game:GetService("HttpService")

local React = require(script.Parent.Parent.Parent.Parent.Packages.React)
local StudioComponents = require(script.Parent.Parent.Parent.Parent.Packages.StudioComponents)
local Wally = require(script.Parent.Parent.Wally)
local SearchResult = require(script.Parent.SearchResult)

local e = React.createElement

function SearchTab()
	local text, setText = React.useState("")
	local searchResults, setSearchResults = React.useState({})

	local memoizedChildren = React.useMemo(function()
			local children = {}
			-- use ipairs to iterate numeric array results in order
			for i, v in ipairs(searchResults) do
				-- provide a stable Key for reconciliation
				-- local key = (v.scope or "") .. "/" .. (v.name or "") .. ":" .. tostring(i)
				children[i] = e(SearchResult, { Scope = v.scope, Name = v.name, Versions = v.versions })
			end
			return children
		end, { searchResults })

	return e(
		React.Fragment,
		nil,
			e("UIListLayout", {
				Padding = UDim.new(0, 4),
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			e(StudioComponents.TextInput, {
				LayoutOrder = 1,
				Text = text,
				PlaceholderText = "Search packages...",
				ClearTextOnFocus = true,
				OnChanged = setText,
				OnFocusLost = function(text: string, enterPressed: boolean)
					if not enterPressed then
						return
					end

					setSearchResults({})

					local body = Wally:SearchPackages(text)
					if not body then
						return
					end

					local success, result = pcall(HttpService.JSONDecode, HttpService, body)
					if success and type(result) == "table" then
						setSearchResults(result)
					end
				end,
			}),
		e(StudioComponents.ScrollFrame, {
			LayoutOrder = 2,
			Layout = {
				ClassName = "UIListLayout",
				Padding = UDim.new(0, 12),
				FillDirection = Enum.FillDirection.Vertical,
			},
			PaddingBottom = UDim.new(0, 32),
		}, memoizedChildren)
	)
end

return SearchTab
