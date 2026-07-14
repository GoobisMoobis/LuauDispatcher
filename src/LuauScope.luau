--[=[
	@class Scope
	@private
	The Scope class is used internally by LuauDispatcher during execution of ASTs to manage variables.
	It cannot be directly accessed unless you specifically require it, which I don't know why you'd ever do but you do you
]=]
local Scope = {}
Scope.__index = Scope

function Scope.new(parent)
	return setmetatable({
		parent = parent,
		variables = {},
	}, Scope)
end

export type Scope = typeof(Scope.new(nil))

--[=[
	Declares a new local variable in a scope.
	Even if a var exists with the same name elsewhere it will be re-declared.

	@param name string
	@param value any
]=]
function Scope:declare(name: string, value: any)
	self.variables[name] = { value = value }
end

--[=[
	Searches for a given variable and returns it's value, and also searches all elevated scopes.
	If no variable of that name exists, returns nil and found=false

	@param name string
	@return (value: any, found: boolean)
]=]
function Scope:get(name: string): (any, boolean)
	local scope = self
	while scope do
		local entry = scope.variables[name]
		if entry then
			return entry.value, true
		end
		scope = scope.parent
	end
	return nil, false
end

--[=[
	Sets a given variable to a new value.
	Returns false if the variable doesn't exist.

	@param name string
	@param value any
	@return success boolean
]=]
function Scope:set(name: string, value: any): boolean
	local scope = self
	while scope do
		local entry = scope.variables[name]
		if entry then
			entry.value = value
			return true
		end
		scope = scope.parent
	end
	return false
end

return Scope
