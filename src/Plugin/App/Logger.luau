local Logger = {}
Logger.DEBUG = 1
Logger.INFO = 2
Logger.WARN = 3
Logger.ERROR = 4

local currentLevel = Logger.INFO

local function shouldLog(level: number)
	return level >= currentLevel
end

function Logger:SetLevel(level: number)
	currentLevel = math.clamp(level, Logger.DEBUG, Logger.ERROR)
end

function Logger:Debug(message: string)
	if shouldLog(Logger.DEBUG) then
		print("[DEBUG]: " .. message)
	end
end

function Logger:Info(message: string)
	if shouldLog(Logger.INFO) then
		print("[INFO]: " .. message)
	end
end

function Logger:Warn(message: string)
	if shouldLog(Logger.WARN) then
		warn("[WARN]: " .. message)
	end
end

function Logger:Error(message: string)
	if shouldLog(Logger.ERROR) then
		warn("[ERROR]: " .. message)
	end
end

return Logger
