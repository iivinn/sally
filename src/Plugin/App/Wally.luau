local HttpService = game:GetService("HttpService")

local Logger = require(script.Parent.Logger)

local PACKAGE_CONTENTS_URL = "https://api.wally.run/v1/package-contents/%s/%s/%s"
local PACKAGE_METADATA_URL = "https://api.wally.run/v1/package-metadata/%s/%s"
local PACKAGE_SEARCH_URL = "https://api.wally.run/v1/package-search?query=%s"
local WALLY_VERSION = "0.3.2"

local Wally = {}

function Wally:RequestAsync(url: string)
	local success, response = pcall(HttpService.RequestAsync, HttpService, {
		Method = "GET",
		Url = url,
		Headers = {
			["Wally-Version"] = WALLY_VERSION,
		},
	})

	if success then
		return response.Body
	else
		Logger:Warn(`HTTP {response.StatusCode}: {response.StatusMessage}`)
		return
	end
end

function Wally:GetPackageContents(scope: string, name: string, version: string)
	return self:RequestAsync(PACKAGE_CONTENTS_URL:format(scope, name, version))
end

function Wally:GetPackageMetadata(scope: string, name: string)
	return self:RequestAsync(PACKAGE_METADATA_URL:format(scope, name))
end

function Wally:SearchPackages(query: string)
	return self:RequestAsync(PACKAGE_SEARCH_URL:format(query))
end

return Wally
