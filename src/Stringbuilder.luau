--[=[
	@class Stringbuilder

	A class I made for myself because I hate fun and love C#.

	Thought I would use it for more than I ended up using it for, but it was worth it anyway.

	Theoretically it should be faster than concatenating strings, but I don't know if it actually is, and if it is it's a minimal improvement.
]=]
local Stringbuilder = {}
Stringbuilder.__index = Stringbuilder
Stringbuilder.__tostring = function(self)
	return self:tostring()
end

--[=[
	@function new
	@within Stringbuilder
	@return Stringbuilder

	Returns a new Stringbuilder.
	Based on the C# implementation.
]=]
function Stringbuilder.new()
	local self = setmetatable({}, Stringbuilder)
	self.parts = {}
	self.n = 0
	return self
end

--[=[
	@type Stringbuilder typeof(Stringbuilder.new())
	@within Stringbuilder

	The instance type returned by Stringbuilder.new().
]=]

export type Stringbuilder = typeof(Stringbuilder.new())

--[=[
	@function returnString
	@within Stringbuilder
	@return string

	Returns the string built by the Stringbuilder.
	Same as calling tostring() on the Stringbuilder object.
]=]
function Stringbuilder:returnString(): string
	return self:tostring()
end

--[=[
	@function tostring
	@within Stringbuilder
	@return string

	Returns the string built by the Stringbuilder.
	Same as calling tostring() on the Stringbuilder object.
]=]
function Stringbuilder:tostring(): string
	return table.concat(self.parts, "", 1, self.n)
end

--[=[
	@function append
	@within Stringbuilder
	@param str string

	Appends a string to the end of the current Stringbuilder's string.
]=]
function Stringbuilder:append(str: string)
	self.n += 1
	self.parts[self.n] = str
end

--[=[
	@function appendLn
	@within Stringbuilder
	@param str string

	Appends a string to the end of the current Stringbuilder's string, with a newline at the end.
]=]
function Stringbuilder:appendLn(str: string)
	self:append(str)
	self:append("\n")
end

--[=[
	@function appendLnBefore
	@within Stringbuilder
	@param str string

	Appends a string to the end of the current Stringbuilder's string on a new line.
]=]
function Stringbuilder:appendLnBefore(str: string)
	self:append("\n")
	self:append(str)
end

--[=[
	@function appendNewLine
	@within Stringbuilder

	Appends a newline to the end of the current Stringbuilder's string.
]=]
function Stringbuilder:appendNewLine()
	self:append("\n")
end

--[=[
	@function appendNewLines
	@within Stringbuilder
	@param n number

	Appends the specified amount of newlines to the current Stringbuilder's string.
]=]
function Stringbuilder:appendNewLines(n)
	for i = 1, n do
		self:appendNewLine()
	end
end

--[=[
	@function clear
	@within Stringbuilder

	Delete's the current Stringbuilder's stored string.
	You can use :returnString() or :tostring() to get the string before clearing it.
]=]
function Stringbuilder:clear()
	self.parts = {}
	self.n = 0
end

return Stringbuilder
