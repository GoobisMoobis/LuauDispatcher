--[=[
	@class LuauError
	
	This is the module used for error handling in [LuauDispatcher].
	It can also be used if you want to make a wrapper around LuauDispatcher and LuauParser, sort of like how I did with my own module LuauExecutor.
	You can also use .isErrors for error detection on an AST (however LuauParser already returns a success value)
	You can access this module via Dispatcher.LuauError, or require it directly if you want to.
]=]
local LuauError = {}
local Stringbuilder = require(script.Parent.Stringbuilder)

--[=[
	@function isErrors
	@within LuauError
	@param tree { any }
	@return boolean

	Checks if a given AST has errors.
]=]
function LuauError.isErrors(tree): boolean
	return if tree and #tree.errors == 0 then false else true
end

--[=[
	@function error
	@within LuauError
	@param tree { any }

	Throws an error with a formatted message if the given AST has errors.
]=]
function LuauError.error(tree)
	local isErrors = LuauError.isErrors(tree)
	if not isErrors then
		error("No errors found in tree", 2)
		return
	end

	local consoleMsg = Stringbuilder.new()
	consoleMsg:appendlnbefore(`-----ERROR{#tree.errors ~= 1 and "S" or ""} FOUND-----`)
	consoleMsg:appendNewLines(2)
	for index, err in ipairs(tree.errors) do
		local msg = err.message :: string
		msg = msg:gsub("<eof>", "end of script/file")

		local location = err.location
		local start = location.begin
		local finish = location.end_

		local linesDifferent = start.line ~= finish.line
		local columnsDifferent = start.column ~= finish.column
		consoleMsg:appendLn(`Error {index}/{#tree.errors}`)
		consoleMsg:appendLn(msg)
		consoleMsg:appendLn(
			string.format(
				"Location: line%s %d%s, column%s %d%s",
				linesDifferent and "s" or "",
				start.line + 1,
				linesDifferent and ("-" .. finish.line + 1) or "",
				columnsDifferent and "s" or "",
				start.column + 1,
				columnsDifferent and ("-" .. finish.column + 1) or ""
			)
		)
		consoleMsg:appendNewLine()
	end
	error(tostring(consoleMsg), 2)
end

--[=[
	@interface SpecificLocation
	@within LuauError
	@field line number
	@field column number
]=]
export type SpecificLocation = {
	line: number,
	column: number,
}

--[=[
	@interface BroadLocation
	@within LuauError
	@field notKnown boolean?
	@field begin SpecificLocation
	@field end_ SpecificLocation
]=]
export type BroadLocation = {
	notKnown: boolean?,
	begin: SpecificLocation?,
	end_: SpecificLocation?,
}

--[=[
	@interface ErrorTable
	@within LuauError
	@field message string
	@field location BroadLocation
]=]
export type ErrorTable = {
	message: string,
	location: BroadLocation,
}

--[=[
	@function CustomError
	@within LuauError
	@param errs { ErrorTable }
	@param msg string?
	@return typeof(Stringbuilder.new())

	Allows you to create a custom error message with a custom label, and also allows you to pass in multiple errors to be displayed in the same message.
]=]
function LuauError.CustomError(errs: { ErrorTable }, msg: string?): typeof(Stringbuilder.new())
	local label = msg or "Error"
	local consoleMsg = Stringbuilder.new()
	consoleMsg:appendLnBefore(`-----{string.upper(label)}{#errs ~= 1 and "S" or ""} FOUND-----`)
	consoleMsg:appendNewLines(2)

	for index, err in ipairs(errs) do
		local location = err.location

		consoleMsg:appendLn(`{label} {index}/{#errs}`)
		consoleMsg:appendLn(err.message)

		if location.notKnown then
			consoleMsg:appendLn("Location: Unknown! (Check the Roblox traceback)")
		else
			local start = location.begin
			local finish = location.end_

			local linesDifferent = start.line ~= finish.line
			local columnsDifferent = start.column ~= finish.column

			consoleMsg:appendLn(
				string.format(
					"Location: line%s %d%s, column%s %d%s",
					linesDifferent and "s" or "",
					start.line + 1,
					linesDifferent and ("-" .. finish.line + 1) or "",
					columnsDifferent and "s" or "",
					start.column + 1,
					columnsDifferent and ("-" .. finish.column + 1) or ""
				)
			)
		end

		consoleMsg:appendNewLine()
	end

	return consoleMsg
end

return LuauError
