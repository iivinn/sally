local currentLevel = 1

local Logger = {}
Logger.DEBUG = 1
Logger.INFO = 2
Logger.WARN = 3
Logger.ERROR = 4

-- TODO : Show where the log was called from

function Logger:Debug(message: string): boolean | string?
	return currentLevel == Logger.DEBUG and print("[DEBUG]: " .. message)
end

function Logger:Info(message: string): boolean | string?
	return currentLevel >= Logger.INFO and print("[INFO]: " .. message)
end

function Logger:Warn(message: string): boolean | string?
	return currentLevel >= Logger.WARN and warn("[WARN]: " .. message)
end

function Logger:Error(message: string): boolean | string?
	return currentLevel >= Logger.ERROR and error("[ERROR]: " .. message)
end

return Logger
