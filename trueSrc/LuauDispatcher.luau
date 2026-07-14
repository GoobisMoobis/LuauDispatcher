--!optimize 2

--[[
	LuauDispatcher - By GoobisMoobis2
	Built for LuauParser v0.728
	Version 1.0.0
	Takes in a LuauParser AST/CST and executes the associated Luau.
]]

--[=[
	@class LuauDispatcher

	Executes a Luau AST produced by [LuauParser](https://vantoanvh.github.io/LuauParser/).

	On average it is 10% faster than [vLuau](https://github.com/kosuke14/vLuau) and 108x slower than the native roblox engine.
	You can see better benchmark results on the [GitHub page](https://github.com/GoobisMoobis/LuauDispatcher)

	Example usage:
	```lua
	local Parser = require(path.to.LuauParser)
	local Dispatcher = require(path.to.LuauDispatcher)

	local parseOptions = {
		-- any options you want to pass to Parser.parse
		-- ex.
		allowDeclarationSyntax = true,
		noErrorLimit = true
	}
	local runtimeOptions = {
		-- any options you want to pass to Dispatcher.run
		-- if you do not pass in any options, the default options will be used
		-- defaults:
		allowEnvironmentModifications = true,
		rawGlobalEnabled = true, -- this might be the one you consider disabling
		overrideCertainGlobalsAtRuntime = true,
		instructionLimit = 10000000,
		noEnv = false,
		allowConsoleOutput = true,
	}
	local code = [[
		print("Hello, world!")
	]]

	local success, tree = Parser.parse(code, parseOptions)
	local completion = Dispatcher.run(tree, runtimeOptions)
	if completion.kind == "Normal" then
		print("Success!")
	end
	```

	A benefit of LuauDispatcher is, in my opinion, it is a lot easier to interface with than something like vLuau.
	You can add new functions in [LuauDispatcher.globals] if you want the execution environment to have more methods to work with.
	Example:
	
	```lua
	Dispatcher.globals.foo = function()
		print("foo")
	end
	
	local parseOptions = {
		...
	}
	local runtimeOptions = {
		...
	}
	local success, tree = Parser.parse("foo()", parseOptions)
	Dispatcher.run(tree, runtimeOptions)
	```

	Scripts also get access to `rawglobal(name, value)` which will add a global to the environment that will persist across all scripts.
	This can cause issues if you are not careful, so it can be disabled in the runtime options.

	Example:
	
	```lua
	local parseOptions = {
		...
	}
	local runtimeOptions = {
		...
	}
	local success, tree = Parser.parse('rawglobal("foo", function() print("Hello, world!") end)', parseOptions)
	Dispatcher.run(tree, runtimeOptions)

	success, tree = Parser.parse("foo()", parseOptions)
	Dispatcher.run(tree, runtimeOptions)
	```

	Error messages are also heavily customized to be easily readable so you can track the issue better.
	```lua
	local success, tree = Parser.parse("print(1 + 1", parseOptions)
	Dispatcher.run(tree, runtimeOptions)

	--[[
		Output:
		LuauDispatcher:1163: 
		-----ERROR FOUND-----

		Error 1/1
		Expected ')' (to close '(' at column 6), got end of script/file
		Location: line 1, column 12

		-  Server - LuauError:40
		Stack Begin  -  Studio
		Script 'ServerStorage.LuauDispatcher.LuauError', Line 40 - function error  -  Studio - LuauError:40
		Script 'ServerStorage.LuauDispatcher', Line 1163 - function run  -  Studio - LuauDispatcher:1163
		Script 'ServerScriptService.AST', Line 3  -  Studio - AST:3
		Stack End  -  Studio
	]]
	```

	:::note
	This library uses [FastSignal](https://devforum.roblox.com/t/fastsignal-a-consistent-signal-library/1360042) for connections.
	If you see the type ScriptSignal in these docs, think of a it the same as an RbxScriptSignal.
]=]
local Dispatcher = {}

-- Packages
local Configuration = {
	FastSignal = script.Packages.FastSignal,
}
local FastSignalPartials = require(script.Packages.FastSignalPartials)
local Signal = require(Configuration.FastSignal) :: FastSignalPartials.FastSignalStatic
local Scope = require(script.LuauScope)
local LuauError = require(script.LuauError)

-- state/signals

--[=[
	@prop RunningCount number
	@within LuauDispatcher
	@readonly

	The number of ASTs currently executing inside [LuauDispatcher.run].
]=]
Dispatcher.RunningCount = 0

--[=[
	@prop RunningStatusChanged ScriptSignal<boolean>
	@within LuauDispatcher

	```lua
	Dispatcher.RunningStatusChanged:Connect(function(isRunning)
		print(isRunning and "started" or "stopped")
	end)
	```
	Becomes true when running count reaches 0, and false when it goes above 0.
]=]
Dispatcher.RunningStatusChanged = Signal.new() :: FastSignalPartials.ScriptSignal<boolean>

--[=[
	@prop LuauRan ScriptSignal<boolean, { any }>
	@within LuauDispatcher

	Fires after [LuauDispatcher.run] AST execution.
	```lua
	Dispatcher.LuauRan:Connect(function(success, result)
		if success then
			print("success")
		else
			print("failed")
		end
	end)
	```

	`result` is the AST that was executed, or was attempted to be executed.
]=]
Dispatcher.LuauRan = Signal.new() :: FastSignalPartials.ScriptSignal<boolean, any>

--[=[
	@prop UnhandledReturn ScriptSignal<...any>
	@within LuauDispatcher

	Fires when a script returns at the top level (essentially returning a value to nothing)

	```lua
	Dispatcher.UnhandledReturn:Connect(function(...)
		print("returned", select("#", ...), "value(s):", ...)
	end)
	local options = { ... }
	local success, tree = LuauParser.parse("return 1", options)
	Dispatcher.run(tree)
	
	-- Output: returned 1 value(s): 1
	```
]=]
Dispatcher.UnhandledReturn = Signal.new() :: FastSignalPartials.ScriptSignal<...any>

--[=[
	@prop Errored ScriptSignal<any>
	@within LuauDispatcher

	Fires whenever a script throws an error.
	It is recommended to disable allowConsoleOutput in [RuntimeOptions] when using this connection.
	The function that gets connected will receive the error message
]=]
Dispatcher.Errored = Signal.new() :: FastSignalPartials.ScriptSignal<any>

--[=[
	@prop Output ScriptSignal<...any>
	@within LuauDispatcher

	Fires whenever a script calls print.
	The function that gets connected will receive any argument passed to the print function

	```lua
	Dispatcher.Output:Connect(function(...)
		print(...) -- This code would actually be redundant, but it demonstrates the functionality
	end)
	```
]=]
Dispatcher.Output = Signal.new() :: FastSignalPartials.ScriptSignal<...any>

--[=[
	@prop Warned ScriptSignal<...any>
	@within LuauDispatcher

	Like [LuauDispatcher.Output], but for warn.
]=]
Dispatcher.Warned = Signal.new() :: FastSignalPartials.ScriptSignal<...any>

--[=[
	@prop LuauError LuauError
	@within LuauDispatcher

	The error-formatting module the Dispatcher uses.
	You can call Dispatcher.LuauError.isErrors() on an AST to check if it has any issues.
]=]
Dispatcher.LuauError = LuauError

--[=[
	@prop globals {[string]: any}
	@within LuauDispatcher

	Add your own globals here (before running) to give them to scripts:

	```lua
	Dispatcher.globals.MyApi = MyApi
	```

	You can also replace any globals, if you want to do that for some reason.
	This will not work if trying to replace a console-printing function, such as warn, print, error, etc.
	You should instead connect to [LuauDispatcher.Output], [LuauDispatcher.Warned], or [LuauDispatcher.Errored].
	
	A script can also call the `rawglobal(name, value)` function to set a global that will stay in this table.
	This can be disabled when running Dispatcher.run() by passing in an options table.
]=]
Dispatcher.globals = {
	game = game,
	print = print,
	assert = assert, -- overridden
	tostring = tostring,
	type = type,
	typeof = typeof,
	table = table,
	math = math,
	task = task,
	Enum = Enum,
	UDim = UDim,
	UDim2 = UDim2,
	Rect = Rect,
	Color3 = Color3,
	Vector2 = Vector2,
	Vector3 = Vector3,
	BrickColor = BrickColor,
	NumberSequence = NumberSequence,
	ColorSequence = ColorSequence,
	NumberRange = NumberRange,
	PhysicalProperties = PhysicalProperties,
	Ray = Ray,
	CFrame = CFrame,
	Region3 = Region3,
	Region3int16 = Region3int16,
	RaycastParams = RaycastParams,
	OverlapParams = OverlapParams,
	ColorSequenceKeypoint = ColorSequenceKeypoint,
	NumberSequenceKeypoint = NumberSequenceKeypoint,
	FloatCurveKey = FloatCurveKey,
	RotationCurveKey = RotationCurveKey,
	rawequal = rawequal,
	setfenv = setfenv,
	tick = tick,
	time = time,
	wait = wait,
	delay = delay,
	spawn = spawn,
	settings = settings,
	UserSettings = UserSettings,
	stats = stats,
	version = version,
	_G = _G,
	shared = shared,
	_VERSION = _VERSION,
	script = script,
	Faces = Faces,
	Axes = Axes,
	SharedTable = SharedTable,
	Secret = Secret,
	Font = Font,
	Random = Random,
	DateTime = DateTime,
	TweenInfo = TweenInfo,
	PathWaypoint = PathWaypoint,
	Instance = Instance,
	string = string,
	os = os,
	coroutine = coroutine,
	workspace = workspace,
	unpack = unpack,
	newproxy = newproxy,
	next = next,
	pairs = pairs,
	ipairs = ipairs,
	tonumber = tonumber,
	error = error, -- overridden
	warn = warn, -- overridden
	select = select,
	getfenv = getfenv,
	getmetatable = getmetatable,
	setmetatable = setmetatable,
	rawget = rawget,
	rawset = rawset,
	rawlen = rawlen,
	pcall = pcall,
	xpcall = xpcall,
	gcinfo = gcinfo,
	buffer = buffer,
	bit32 = bit32,
	utf8 = utf8,
	debug = debug,
	vector = vector,
	require = require,
	-- Overridden
	rawglobal = function(name, value)
		Dispatcher.globals[name] = value
	end,
}

--[=[
	@interface Completion
	@within LuauDispatcher
	@field kind "Normal" | "Return" | "Break" | "Continue"
	@field values { any }? -- only present if kind == "Return"

	Describes how a statement or a whole [LuauDispatcher.run] call finished.
]=]
export type Completion = {
	kind: "Normal" | "Return" | "Break" | "Continue",
	values: { any }?,
}

local NORMAL: Completion = { kind = "Normal" }
local BREAK: Completion = { kind = "Break" }
local CONTINUE: Completion = { kind = "Continue" }
Dispatcher.NORMAL, Dispatcher.BREAK, Dispatcher.CONTINUE = NORMAL, BREAK, CONTINUE

local binaryOps = {
	[0] = function(a: any, b: any)
		return a + b
	end,
	[1] = function(a: any, b: any)
		return a - b
	end,
	[2] = function(a: any, b: any)
		return a * b
	end,
	[3] = function(a, b)
		return a / b
	end,
	[4] = function(a, b)
		return a // b
	end,
	[5] = function(a, b)
		return a % b
	end,
	[6] = function(a, b)
		return a ^ b
	end,
	[7] = function(a, b)
		return a .. b
	end,
	[8] = function(a, b)
		return a ~= b
	end,
	[9] = function(a, b)
		return a == b
	end,
	[10] = function(a: any, b: any)
		return a < b
	end,
	[11] = function(a: any, b: any)
		return a <= b
	end,
	[12] = function(a: any, b: any)
		return a > b
	end,
	[13] = function(a: any, b: any)
		return a >= b
	end,
}
Dispatcher.binaryOps = binaryOps

-- Runtime

--[=[
	@class Runtime
	@private

	The Runtime class is used internally by LuauDispatcher to execute ASTs.
	It can be directly interacted with via Dispatcher.Runtime.

	There is really no reason to ever manually use this class, however the option is open if you want to do so.
]=]
local Runtime = {}
Runtime.__index = Runtime
Dispatcher.Runtime = Runtime

function Runtime.new(options: RuntimeOptions)
	local self = setmetatable({
		globals = {},
		currentLocation = nil,
		options = options,
		instructionCount = 0,
	}, Runtime)

	if not self.options.noEnv then
		for key, value in pairs(Dispatcher.globals) do
			self.globals[key] = value
		end
	end

	if self.options.rawGlobalEnabled and not self.options.noEnv and self.options.overrideCertainGlobalsAtRuntime then
		self.globals.rawglobal = function(name, value)
			self.globals[name] = value
			Dispatcher.globals[name] = value
		end
	elseif self.options.overrideCertainGlobalsAtRuntime or self.options.noEnv then
		self.globals.rawglobal = nil
	end

	if not self.options.noEnv and self.options.overrideCertainGlobalsAtRuntime then
		self.globals.error = function(message)
			Dispatcher.Errored:Fire(message)
			self:raise(tostring(message))
		end

		self.globals.assert = function(value, message, ...)
			if not value then
				local msg = tostring(message or "assertion failed!")
				Dispatcher.Errored:Fire(msg)
				self:raise(msg)
			end
			return value, message, ...
		end

		self.globals.warn = function(...)
			Dispatcher.Warned:Fire(...)
			if self.options.allowConsoleOutput then
				local parts = {}
				for i = 1, select("#", ...) do
					parts[i] = tostring((select(i, ...)))
				end
				warn(
					tostring(
						LuauError.CustomError(
							{ { message = table.concat(parts, " "), location = self.currentLocation } },
							"Warning"
						)
					)
				)
			end
		end

		self.globals.print = function(...)
			Dispatcher.Output:Fire(...)
			if self.options.allowConsoleOutput then
				print(...)
			end
		end

		local realTestService = game:GetService("TestService")
		local fakeTestService = setmetatable({}, {
			__index = function(_, key)
				if key == "Message" or key == "Checkpoint" then
					return function(_, text, source, line)
						Dispatcher.Output:Fire(text)
						if self.options.allowConsoleOutput then
							realTestService[key](realTestService, text, source, line)
						end
					end
				elseif key == "Check" or key == "Warn" then
					return function(_, condition, description, source, line)
						if not condition then
							Dispatcher.Warned:Fire(description)
						end
						if self.options.allowConsoleOutput then
							realTestService[key](realTestService, condition, description, source, line)
						end
					end
				elseif key == "Error" or key == "Fail" then
					return function(_, description, source, line)
						Dispatcher.Errored:Fire(description)
						if self.options.allowConsoleOutput then
							realTestService[key](realTestService, description, source, line)
						end
					end
				elseif key == "Require" then
					return function(_, condition, description, source, line)
						if not condition then
							Dispatcher.Errored:Fire("Require failed. Test ended: " .. description)
							if self.options.allowConsoleOutput then
								realTestService:Require(condition, description, source, line)
							end
							self:raise(tostring(description))
						else
							Dispatcher.Output:Fire("Require passed: " .. description)
							if self.options.allowConsoleOutput then
								realTestService:Require(condition, description, source, line)
							end
						end
					end
				elseif key == "Done" then
					return function(_)
						Dispatcher.Output:Fire("Testing Done")
						if self.options.allowConsoleOutput then
							realTestService:Done()
						end
					end
				else
					local val = realTestService[key]
					if type(val) == "function" then
						return function(_, ...)
							return val(realTestService, ...)
						end
					end
					return val
				end
			end,
			__newindex = function(_, key, value)
				realTestService[key] = value
			end,
			__tostring = function()
				return "Instance"
			end,
		})

		local realGame = self.globals.game
		if realGame then
			local fakeGame = setmetatable({}, {
				__index = function(_, key)
					if key == "GetService" or key == "service" then
						return function(_, serviceName)
							if serviceName == "TestService" then
								return fakeTestService
							end
							return realGame:GetService(serviceName)
						end
					end

					local val = realGame[key]
					if type(val) == "function" then
						return function(_, ...)
							return val(realGame, ...)
						end
					end
					return val
				end,
				__newindex = function(_, key, value)
					realGame[key] = value
				end,
				__tostring = function()
					return "Instance"
				end,
			})
			self.globals.game = fakeGame
		end
	elseif not self.options.noEnv and not self.options.overrideCertainGlobalsAtRuntime then
		if not self.options.allowConsoleOutput then
			self.globals.print = function() end
			self.globals.warn = function() end
		end
	end

	return self
end

--[=[
	@within Runtime
	@param message string -- the error text
	@param location Location? -- defaults to the node currently being evaluated
]=]
function Runtime:raise(message: string, location)
	error(tostring(LuauError.CustomError({
		{ message = message, location = location or self.currentLocation },
	})))
end

local function commaValue(amount)
	local formatted = amount
	while true do
		local k
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		if k == 0 then
			break
		end
	end
	return formatted
end

--[=[
	@within Runtime
	@param node any
	@param scope Scope
	@return ...any
]=]
function Runtime:evalExpr(node, scope)
	self.instructionCount += 1
	if self.instructionCount > self.options.instructionLimit then
		self:raise("Instruction limit exceeded (" .. commaValue(self.options.instructionLimit) .. ")", node.location)
	end

	local handler = Dispatcher.exprs[node.kind]
	if not handler then
		self:raise(
			string.format("Dispatcher: no expression handler for node.kind = %s", tostring(node.kind)),
			node.location
		)
	end
	self.currentLocation = node.location
	return handler(self, node, scope)
end

--[=[
	@within Runtime
	@param node any
	@param scope Scope
	@return Completion
]=]
function Runtime:execStat(node, scope): Completion
	self.instructionCount += 1
	if self.instructionCount > self.options.instructionLimit then
		self:raise("Instruction limit exceeded (" .. commaValue(self.options.instructionLimit) .. ")", node.location)
	end

	local handler = Dispatcher.stats[node.kind]
	if not handler then
		self:raise(
			string.format("Dispatcher: no statement handler for node.kind = %s", tostring(node.kind)),
			node.location
		)
	end
	self.currentLocation = node.location
	return handler(self, node, scope) or NORMAL
end

--[=[
	@within Runtime
	@param nodes { any }
	@param scope Scope
	@return { any } -- an array (.n)
]=]
function Runtime:evalExprList(nodes, scope)
	local out = { n = 0 }
	local count = #nodes
	if count == 0 then
		return out
	end
	for i = 1, count - 1 do
		out[i] = (self:evalExpr(nodes[i], scope))
	end
	local last = table.pack(self:evalExpr(nodes[count], scope))
	for j = 1, last.n do
		out[count - 1 + j] = last[j]
	end
	out.n = count - 1 + last.n
	return out
end

--[=[
	@within Runtime
	@param target any -- an ExprLocal/ExprGlobal/ExprIndexName/ExprIndexExpr node
	@param value any -- the value to store
	@param scope Scope
]=]
function Runtime:assign(target, value, scope)
	local kind = target.kind
	if kind == "ExprLocal" then
		if not scope:set(target["local"].name, value) then
			self:raise(
				`Assignment to undeclared local "{target["local"].name}"\nThis is most likely an issue with LuauDispatcher and should be reported.`,
				target.location
			)
		end
	elseif kind == "ExprGlobal" then
		if not self.options.allowEnvironmentModifications and Dispatcher.globals[target.name] ~= nil then
			self:raise("Attempt to modify environment global '" .. target.name .. "'.", target.location)
		end
		self.globals[target.name] = value
	elseif kind == "ExprIndexName" then
		local base = self:evalExpr(target.expr, scope)
		if type(base) ~= "table" and type(base) ~= "userdata" then
			self:raise("attempt to index a " .. type(base) .. " value", target.location)
		end
		base[target.index] = value
	elseif kind == "ExprIndexExpr" then
		local base = self:evalExpr(target.expr, scope)
		if type(base) ~= "table" and type(base) ~= "userdata" then
			self:raise("attempt to index a " .. type(base) .. " value", target.location)
		end
		base[self:evalExpr(target.index, scope)] = value
	else
		self:raise("Cannot assign to " .. tostring(kind), target.location)
	end
end

--[=[
	@within Runtime
	@param funcNode any -- an AstExprFunction node
	@param defScope Scope -- the lexical scope the closure captures
	@return (...any) -> ...any

	Build a closure from an AstExprFunction
]=]
function Runtime:makeClosure(funcNode, defScope)
	return function(...)
		local callScope = Scope.new(defScope)
		local passed = table.pack(...)
		local offset = 0
		if funcNode.self then
			callScope:declare(funcNode.self.name, passed[1])
			offset = 1
		end
		for i, argDef in funcNode.args do
			callScope:declare(argDef.name, passed[i + offset])
		end
		if funcNode.vararg then
			local varargs = { n = 0 }
			local firstVararg = #funcNode.args + offset + 1
			local written = 0
			for i = firstVararg, passed.n do
				written += 1
				varargs[written] = passed[i]
			end
			varargs.n = written
			callScope.varargs = varargs
		end
		local completion = self:execStat(funcNode.body, callScope)
		if completion.kind == "Return" then
			local values = completion.values
			return table.unpack(values, 1, values.n)
		end
	end
end

-- Expression handlers

--[=[
	@prop exprs {[string]: (self: Runtime, node: any, scope: Scope) -> ...any}
	@within LuauDispatcher

	Registry of expression handlers.
	If you'd like to play with these, change them, or add more, you might want to better understand the [Scope] library.
]=]
local exprs = {}
Dispatcher.exprs = exprs

exprs.ExprConstantNil = function()
	return nil
end
exprs.ExprConstantBool = function(_, node)
	return node.value
end
exprs.ExprConstantNumber = function(_, node)
	return node.value
end
exprs.ExprConstantString = function(_, node)
	return node.value
end
exprs.ExprConstantInteger = function(self, node)
	return node.high * 4294967296 + node.low
end

exprs.ExprTable = function(self, node, scope)
	local tbl = {}
	local arrayIdx = 1

	local itemCount = #node.items
	for i, item in ipairs(node.items) do
		if item.kind == "List" then
			if i == itemCount then
				local results = table.pack(self:evalExpr(item.value, scope))
				for j = 1, results.n do
					tbl[arrayIdx] = results[j]
					arrayIdx += 1
				end
			else
				tbl[arrayIdx] = (self:evalExpr(item.value, scope))
				arrayIdx += 1
			end
		else
			tbl[(self:evalExpr(item.key, scope))] = (self:evalExpr(item.value, scope))
		end
	end

	return tbl
end

exprs.ExprGroup = function(self, node, scope)
	return (self:evalExpr(node.expr, scope))
end

exprs.ExprBinary = function(self, node, scope)
	local op = node.op
	if op == 14 then -- and
		local left = self:evalExpr(node.left, scope)
		if not left then
			return left
		end
		return (self:evalExpr(node.right, scope))
	elseif op == 15 then -- or
		local left = self:evalExpr(node.left, scope)
		if left then
			return left
		end
		return (self:evalExpr(node.right, scope))
	end
	local left = self:evalExpr(node.left, scope)
	local right = self:evalExpr(node.right, scope)
	return binaryOps[op](left, right)
end

exprs.ExprUnary = function(self, node, scope)
	local value = self:evalExpr(node.expr, scope)
	local op = node.op
	if op == 0 then -- not
		return not value
	elseif op == 1 then -- negate
		return -value
	elseif op == 2 then -- length
		return #value
	end
	return nil
end

exprs.ExprLocal = function(self, node, scope)
	local value, found = scope:get(node["local"].name)
	if not found then
		self:raise(`Local "{node["local"].name}" was referenced before being declared.`, node.location)
	end
	return value
end

exprs.ExprGlobal = function(self, node)
	return self.globals[node.name]
end

exprs.ExprIndexName = function(self, node, scope)
	local base = self:evalExpr(node.expr, scope)
	if type(base) ~= "table" and type(base) ~= "userdata" then
		self:raise("attempt to index a " .. type(base) .. " value", node.location)
	end
	return base[node.index]
end

exprs.ExprIndexExpr = function(self, node, scope)
	local base = self:evalExpr(node.expr, scope)
	if type(base) ~= "table" and type(base) ~= "userdata" then
		self:raise("attempt to index a " .. type(base) .. " value", node.location)
	end
	return base[self:evalExpr(node.index, scope)]
end

exprs.ExprCall = function(self, node, scope)
	local fn, selfArg
	if node.self then
		local base = self:evalExpr(node.func.expr, scope)
		if type(base) ~= "table" and type(base) ~= "userdata" then
			self:raise("attempt to index a " .. type(base) .. " value", node.func.location)
		end
		fn, selfArg = base[node.func.index], base
	else
		fn = self:evalExpr(node.func, scope)
	end

	if type(fn) ~= "function" then
		local mt = getmetatable(fn)
		if not (mt and mt.__call) then
			self:raise("attempt to call a " .. type(fn) .. " value", node.location)
		end
	end

	local args = self:evalExprList(node.args, scope)
	if selfArg ~= nil then
		local shifted = { selfArg, n = args.n + 1 }
		for i = 1, args.n do
			shifted[i + 1] = args[i]
		end
		args = shifted
	end

	self.currentLocation = node.location
	return fn(table.unpack(args, 1, args.n))
end

exprs.ExprFunction = function(self, node, scope)
	return self:makeClosure(node, scope)
end

exprs.ExprInterpString = function(self, node, scope)
	local out = {}
	local strings = node.strings
	local expressions = node.expressions
	local written = 0
	for i = 1, #strings do
		written += 1
		out[written] = strings[i]
		local expr = expressions[i]
		if expr ~= nil then
			written += 1
			out[written] = tostring((self:evalExpr(expr, scope)))
		end
	end
	return table.concat(out)
end

exprs.ExprVarargs = function(self, node, scope)
	local s = scope
	while s do
		local varargs = s.varargs
		if varargs then
			return table.unpack(varargs, 1, varargs.n)
		end
		s = s.parent
	end
	self:raise("cannot use '...' outside a vararg function", node.location)
end

exprs.ExprIfElse = function(self, node, scope)
	if self:evalExpr(node.condition, scope) then
		return (self:evalExpr(node.trueExpr, scope))
	else
		return (self:evalExpr(node.falseExpr, scope))
	end
end

exprs.ExprTypeAssertion = function(self, node, scope)
	return (self:evalExpr(node.expr, scope))
end

exprs.ExprInstantiate = function(self, node, scope)
	return self:evalExpr(node.expr, scope)
end

exprs.ExprError = function(self, node)
	self:raise(
		"cannot evaluate: Node type ExprError somehow passed error checking.\nThis is most likely an issue with LuauDispatcher and should be reported.",
		node.location
	)
end

-- Statement handlers

--[=[
	@prop stats {[string]: (self: Runtime, node: any, scope: Scope) -> Completion}
	@within LuauDispatcher

	Registry of statement handlers
]=]
local stats = {}
Dispatcher.stats = stats

stats.StatBlock = function(self, node, scope): Completion
	local blockScope = Scope.new(scope)
	for _, statement in node.body do
		local completion = self:execStat(statement, blockScope)
		if completion.kind ~= "Normal" then
			return completion
		end
	end
	return NORMAL
end

stats.StatExpr = function(self, node, scope): Completion
	self:evalExpr(node.expr, scope)
	return NORMAL
end

stats.StatReturn = function(self, node, scope): Completion
	return { kind = "Return", values = self:evalExprList(node.list, scope) }
end

stats.StatBreak = function(self, node, scope): Completion
	return BREAK
end

stats.StatContinue = function(self, node, scope): Completion
	return CONTINUE
end

stats.StatLocal = function(self, node, scope): Completion
	local values = self:evalExprList(node.values, scope)
	for index, var in node.vars do
		scope:declare(var.name, values[index])
	end
	return NORMAL
end

stats.StatAssign = function(self, node, scope): Completion
	local values = self:evalExprList(node.values, scope)
	for index, target in node.vars do
		self:assign(target, values[index], scope)
	end
	return NORMAL
end

stats.StatCompoundAssign = function(self, node, scope): Completion
	local target = node.var
	local kind = target.kind
	local op = Dispatcher.binaryOps[node.op]

	if kind == "ExprLocal" or kind == "ExprGlobal" then
		if
			kind == "ExprGlobal"
			and not self.options.allowEnvironmentModifications
			and Dispatcher.globals[target.name] ~= nil
		then
			self:raise("Attempt to modify environment global '" .. target.name .. "'.", target.location)
		end

		local lhs = self:evalExpr(target, scope)
		local rhs = self:evalExpr(node.value, scope)
		self:assign(target, op(lhs, rhs), scope)
	elseif kind == "ExprIndexName" then
		local base = self:evalExpr(target.expr, scope)
		if type(base) ~= "table" and type(base) ~= "userdata" then
			self:raise("attempt to index a " .. type(base) .. " value", target.location)
		end
		local key = target.index
		local rhs = self:evalExpr(node.value, scope)
		base[key] = op(base[key], rhs)
	elseif kind == "ExprIndexExpr" then
		local base = self:evalExpr(target.expr, scope)
		if type(base) ~= "table" and type(base) ~= "userdata" then
			self:raise("attempt to index a " .. type(base) .. " value", target.location)
		end
		local key = self:evalExpr(target.index, scope)
		local rhs = self:evalExpr(node.value, scope)
		base[key] = op(base[key], rhs)
	else
		self:raise("cannot compound-assign to " .. tostring(kind), target.location)
	end

	return NORMAL
end

stats.StatLocalFunction = function(self, node, scope): Completion
	scope:declare(node.name.name, nil)
	scope:set(node.name.name, self:makeClosure(node.func, scope))
	return NORMAL
end

stats.StatFunction = function(self, node, scope): Completion
	self:assign(node.name, self:makeClosure(node.func, scope), scope)
	return NORMAL
end

stats.StatFor = function(self, node, scope): Completion
	local newVar = node.var.name

	local from = self:evalExpr(node.from, scope)
	if type(from) ~= "number" then
		self:raise("for initial value must be a number", node.from.location)
	end

	local to = self:evalExpr(node.to, scope)
	if type(to) ~= "number" then
		self:raise("for to value must be a number", node.to.location)
	end

	local step = 1

	if node.step then
		step = self:evalExpr(node.step, scope)
		if type(step) ~= "number" then
			self:raise("for step value must be a number", node.step.location)
		elseif step == 0 then
			self:raise("for step value must not be 0", node.step.location)
		end
	end

	for i = from, to, step do
		local iterScope = Scope.new(scope)
		iterScope:declare(newVar, i)
		local completion = self:execStat(node.body, iterScope)
		if completion.kind == "Break" then
			break
		elseif completion.kind == "Continue" then
			continue
		elseif completion.kind == "Return" then
			return completion
		end
	end

	return NORMAL
end

stats.StatForIn = function(self, node, scope): Completion
	local values = self:evalExprList(node.values, scope)
	local iterator = values[1]
	local state = values[2]
	local control = values[3]

	if type(iterator) == "table" then
		local mt = getmetatable(iterator)
		if mt and mt.__iter then
			local it = table.pack(mt.__iter(iterator))
			iterator, state, control = it[1], it[2], it[3]
		else
			iterator, state, control = next, iterator, nil
		end
	elseif type(iterator) ~= "function" then
		local mt = getmetatable(iterator)
		if not (mt and mt.__call) then
			self:raise("attempt to iterate over a " .. type(iterator) .. " value", node.location)
		end
	end

	while true do
		local results = table.pack(iterator(state, control))
		if results[1] == nil then
			break
		end
		control = results[1]

		local loopScope = Scope.new(scope)
		for i, var in node.vars do
			loopScope:declare(var.name, results[i])
		end

		local completion = self:execStat(node.body, loopScope)
		if completion.kind == "Break" then
			break
		elseif completion.kind == "Continue" then
			continue
		elseif completion.kind == "Return" then
			return completion
		end
	end

	return NORMAL
end

stats.StatRepeat = function(self, node, scope): Completion
	while true do
		local iterScope = Scope.new(scope)
		local completion = NORMAL
		for _, statement in node.body.body do
			completion = self:execStat(statement, iterScope)
			if completion.kind ~= "Normal" then
				break
			end
		end

		if completion.kind == "Break" then
			break
		elseif completion.kind == "Return" then
			return completion
		end
		if self:evalExpr(node.condition, iterScope) then
			break
		end
	end

	return NORMAL
end

stats.StatIf = function(self, node, scope): Completion
	local newScope = Scope.new(scope)
	local condition = self:evalExpr(node.condition, scope)
	if condition then
		if not node.thenbody then
			self:raise("if block is empty", node.location)
		end
		return self:execStat(node.thenbody, newScope)
	else
		if node.elsebody then
			return self:execStat(node.elsebody, newScope)
		end
	end
	return NORMAL
end

stats.StatWhile = function(self, node, scope): Completion
	while self:evalExpr(node.condition, scope) do
		local iterScope = Scope.new(scope)
		local completion = self:execStat(node.body, iterScope)
		if completion.kind == "Break" then
			break
		elseif completion.kind == "Continue" then
			continue
		elseif completion.kind == "Return" then
			return completion
		end
	end
	return NORMAL
end

stats.StatClass = function(self, node, scope): Completion
	return NORMAL
end

stats.StatTypeAlias = function(self, node, scope): Completion
	return NORMAL
end

stats.StatTypeFunction = function(self, node, scope): Completion
	return NORMAL
end

stats.StatDeclareGlobal = function(self, node, scope): Completion
	return NORMAL
end

stats.StatDeclareFunction = function(self, node, scope): Completion
	return NORMAL
end

stats.StatDeclareExternType = function(self, node, scope): Completion
	return NORMAL
end

stats.StatError = function(self, node)
	self:raise(
		"cannot evaluate: Node type StatError somehow passed error checking.\nThis is most likely an issue with LuauDispatcher and should be reported.",
		node.location
	)
end

-- Public API

--[=[
	@interface RuntimeOptions
	@within LuauDispatcher
	@field rawGlobalEnabled boolean? -- Allows scripts to use the `rawglobal(name, value)` function.
	@field overrideCertainGlobalsAtRuntime boolean? -- Overrides `error`, `assert`, `warn`, `print`, and various methods from `game:GetService("TestService")`
	@field noEnv boolean? -- Runs the script without libs and functions from Dispatcher.globals
	@field instructionLimit number? -- The maximum number of expressions/statements evaluated before stopping script execution (default 10,000,000).
	@field allowEnvironmentModifications boolean? -- Allows scripts to overwrite globals in the environment.
	@field allowConsoleOutput boolean? -- If true, output functions will be able to print to the Roblox console.
]=]
export type RuntimeOptions = {
	rawGlobalEnabled: boolean?,
	overrideCertainGlobalsAtRuntime: boolean?,
	noEnv: boolean?,
	instructionLimit: number?,
	allowEnvironmentModifications: boolean?,
	allowConsoleOutput: boolean?,
}

--[=[
	@within LuauDispatcher
	@param tree any -- a parsed tree from LuauParser
	@param options RuntimeOptions?
	@param ... any -- Varargs passed to the script
	@return Completion

	Executes a tree produced by LuauParser.

	Returns a [Completion] describing how the script finished: `kind` is
	`"Normal"` for a script that just ran, or `"Return"` if the script returned.
	Alternatively you can specifically monitor for returns by connecting to [LuauDispatcher.UnhandledReturn].
	
	Optionally, you can pass in an options table of type [RuntimeOptions] to enable or disable specific parser features.
	Default options:
	```lua
	local runtimeOptions = {
		allowEnvironmentModifications = true,
		rawGlobalEnabled = true, -- this might be the one you consider disabling
		overrideCertainGlobalsAtRuntime = true,
		instructionLimit = 10000000,
		noEnv = false,
		allowConsoleOutput = true,
	}
	```
	
	You may also pass in arguments to the script by passing them in after the options table.
	Ex.
	
	```lua
	local success, tree = LuauParser.parse([[
		local msg1, msg2 = ...
		print(msg1.." "..msg2)
	]])
	local completion = Dispatcher.run(tree, {}, "Hello", "World")
	```
]=]
function Dispatcher.run(tree, options: RuntimeOptions?, ...): Completion
	local opts: RuntimeOptions = {
		noEnv = options and options.noEnv == true,
		allowEnvironmentModifications = not options or options.allowEnvironmentModifications ~= false,
		rawGlobalEnabled = not options or options.rawGlobalEnabled ~= false,
		overrideCertainGlobalsAtRuntime = not options or options.overrideCertainGlobalsAtRuntime ~= false,
		allowConsoleOutput = not options or options.allowConsoleOutput ~= false,
		instructionLimit = (options and options.instructionLimit) or 10000000,
	}

	if Dispatcher.LuauError.isErrors(tree) then
		Dispatcher.LuauRan:Fire(false, tree)
		Dispatcher.LuauError.error(tree)
		return NORMAL
	end

	local runtime = Runtime.new(opts)

	local wasRunning = Dispatcher.RunningCount > 0
	Dispatcher.RunningCount += 1
	if not wasRunning then
		Dispatcher.RunningStatusChanged:Fire(true)
	end

	local rootScope = Scope.new(nil)
	local passed = table.pack(...)
	if passed.n > 0 then
		rootScope.varargs = passed
	end

	local ok, result = pcall(runtime.execStat, runtime, tree.root, rootScope)

	Dispatcher.RunningCount -= 1
	if Dispatcher.RunningCount == 0 then
		Dispatcher.RunningStatusChanged:Fire(false)
	end

	if not ok then
		Dispatcher.Errored:Fire(result)
		Dispatcher.LuauRan:Fire(false, tree)
		if not opts.allowConsoleOutput then
			return
		end
		error(
			tostring(Dispatcher.LuauError.CustomError({
				{
					message = result,
					location = {
						notKnown = true,
					},
				},
			})),
			2
		)
	end

	local completion = result
	Dispatcher.LuauRan:Fire(true, tree)
	if completion.kind == "Return" then
		Dispatcher.UnhandledReturn:Fire(table.unpack(completion.values, 1, completion.values.n))
	end
	return completion
end

--[=[
	@within LuauDispatcher
	@param node AstNode -- any single AST node
	@param scope Scope? -- an optional scope to evaluate within
	@param options RuntimeOptions?
	@return Completion | ...any

	Evaluates a **single** node.
	
	:::caution
	Prefer [LuauDispatcher.run] whenever possible.
	Unlike [LuauDispatcher.run], this does **not** automatically check the tree for parse errors,
	wrap execution in a `pcall`, update [LuauDispatcher.RunningCount], or fire
	`RunningStatusChanged`, `LuauRan`, or `UnhandledReturn`
]=]
function Dispatcher.evaluateNode(node, scope: Scope.Scope?, options: RuntimeOptions?)
	local opts: RuntimeOptions = {
		noEnv = options and options.noEnv == true,
		allowEnvironmentModifications = not options or options.allowEnvironmentModifications ~= false,
		rawGlobalEnabled = not options or options.rawGlobalEnabled ~= false,
		overrideCertainGlobalsAtRuntime = not options or options.overrideCertainGlobalsAtRuntime ~= false,
		allowConsoleOutput = not options or options.allowConsoleOutput ~= false,
		instructionLimit = (options and options.instructionLimit) or 10000000,
	}

	local runtime = Runtime.new(opts)
	scope = scope or Scope.new(nil)
	if Dispatcher.stats[node.kind] then
		return runtime:execStat(node, scope)
	end
	return runtime:evalExpr(node, scope)
end

return Dispatcher
