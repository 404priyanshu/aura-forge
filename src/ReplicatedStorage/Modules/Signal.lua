--!strict
--[[
	Signal — tiny script signal shared by services and controllers.

	  local s = Signal.new()
	  local conn = s:Connect(function(a, b) end)
	  s:Fire(1, 2)          -- handlers run in connect order, each in its own thread
	  s:Once(fn)            -- auto-disconnects after the first fire
	  local a, b = s:Wait() -- yields until the next fire
	  conn:Disconnect()
]]

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal = {
	Connect: (self: Signal, fn: (...any) -> ()) -> Connection,
	Once: (self: Signal, fn: (...any) -> ()) -> Connection,
	Fire: (self: Signal, ...any) -> (),
	Wait: (self: Signal) -> ...any,
	DisconnectAll: (self: Signal) -> (),
}

type ConnectionImpl = {
	Connected: boolean,
	Disconnect: (self: ConnectionImpl) -> (),
	_fn: (...any) -> (),
	_list: { ConnectionImpl },
}

local function disconnect(self: ConnectionImpl)
	if not self.Connected then
		return
	end
	self.Connected = false
	local index = table.find(self._list, self)
	if index then
		table.remove(self._list, index)
	end
end

local Signal = {}

function Signal.new(): Signal
	local list: { ConnectionImpl } = {}
	local self = {}

	function self.Connect(_: any, fn: (...any) -> ()): Connection
		local connection: ConnectionImpl = {
			Connected = true,
			Disconnect = disconnect,
			_fn = fn,
			_list = list,
		}
		table.insert(list, connection)
		return connection :: any
	end

	function self.Once(this: Signal, fn: (...any) -> ()): Connection
		local connection: Connection
		connection = this:Connect(function(...)
			connection:Disconnect()
			fn(...)
		end)
		return connection
	end

	function self.Fire(_: any, ...: any)
		for _, connection in table.clone(list) do
			if connection.Connected then
				task.spawn(connection._fn, ...)
			end
		end
	end

	function self.Wait(this: Signal): ...any
		local thread = coroutine.running()
		this:Once(function(...)
			task.spawn(thread, ...)
		end)
		return coroutine.yield()
	end

	function self.DisconnectAll(_: any)
		for _, connection in list do
			connection.Connected = false
		end
		table.clear(list)
	end

	return self :: any
end

return Signal
