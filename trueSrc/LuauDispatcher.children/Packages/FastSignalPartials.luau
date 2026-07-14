--!strict
-- Partial types for FastSignal
-- Made this before I saw the docs module
-- By GoobisMoobis2

-- DO NOT REMOVE!
local ret = {}

export type ScriptConnection = {
	Disconnect: (self: ScriptConnection) -> (),
	Connected: boolean,
}

export type ScriptSignal<T...> = {
	IsActive: (self: ScriptSignal<T...>) -> boolean,
	Fire: (self: ScriptSignal<T...>, T...) -> (),
	Connect: (self: ScriptSignal<T...>, callback: (T...) -> ()) -> ScriptConnection,
	Once: (self: ScriptSignal<T...>, callback: (T...) -> ()) -> ScriptConnection,
	DisconnectAll: (self: ScriptSignal<T...>) -> (),
	Destroy: (self: ScriptSignal<T...>) -> (),
	Wait: (self: ScriptSignal<T...>) -> T...,
}

export type Class = ScriptSignal<...any>

export type Handler<T...> = (T...) -> ()

export type FastSignalStatic = {
	new: <T...>() -> ScriptSignal<T...>,
	Is: (object: any) -> boolean,
}

return ret
