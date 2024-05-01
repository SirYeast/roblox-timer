--!strict
--------------------------------------------------------------------------------
--               Batched Yield-Safe Signal Implementation                     --
-- This is a Signal class which has effectively identical behavior to a       --
-- normal RBXScriptSignal, with the only difference being a couple extra      --
-- stack frames at the bottom of the stack trace when an error is thrown.     --
-- This implementation caches runner coroutines, so the ability to yield in   --
-- the signal handlers comes at minimal extra cost over a naive signal        --
-- implementation that either always or never spawns a thread.                --
--                                                                            --
-- API:                                                                       --
--   local Signal = require(THIS MODULE)                                      --
--   local sig = Signal.new()                                                 --
--   local connection = sig:Connect(function(arg1, arg2, ...) ... end)        --
--   sig:Fire(arg1, arg2, ...)                                                --
--   connection:Disconnect()                                                  --
--   sig:DisconnectAll()                                                      --
--   local arg1, arg2, ... = sig:Wait()                                       --
--                                                                            --
-- Licence:                                                                   --
--   Licenced under the MIT licence.                                          --
--                                                                            --
-- Authors:                                                                   --
--   stravant - July 31st, 2021 - Created the file.                           --
--	 SirYeast - April 30, 2024 - Implemented types.
--------------------------------------------------------------------------------

type SignalImpl = {
	__index: SignalImpl,
	new: ()->Signal,
	Connect: (self: Signal, fn: (...any)->())->Connection,
	Fire: (self: Signal, ...any)->(),
	Wait: (self: Signal)->thread,
	Once: (self: Signal, fn: (...any)->())->Connection,
	DisconnectAll: (self: Signal)->()
}

export type Signal = typeof(setmetatable({}::{
	_handlerListHead: Connection?
}, {}::SignalImpl))

type ConnectionImpl = {
	__index: ConnectionImpl,
	new: (signal: Signal, fn: (...any)->())->Connection,
	Disconnect: (self: Connection)->()
}

export type Connection = typeof(setmetatable({}::{
	_connected: boolean,
	_signal: Signal,
	_fn: (...any)->(),
	_next: Connection?
}, {}::ConnectionImpl))

local freeRunnerThread: thread?

local function acquireRunnerThreadAndCallEventHandler(fn: (...any)->(), ...)
	local acquiredRunnerThread = freeRunnerThread
	freeRunnerThread = nil
	fn(...)
	-- The handler finished running, this runner thread is free again.
	freeRunnerThread = acquiredRunnerThread
end

local function runEventHandlerInFreeThread()
	-- Note: We cannot use the initial set of arguments passed to
	-- runEventHandlerInFreeThread for a call to the handler, because those
	-- arguments would stay on the stack for the duration of the thread's
	-- existence, temporarily leaking references. Without access to raw bytecode
	-- there's no way for us to clear the "..." references from the stack.
	while true do
		acquireRunnerThreadAndCallEventHandler(coroutine.yield())
	end
end

local Connection: ConnectionImpl = {}::ConnectionImpl
Connection.__index = Connection

function Connection.new(signal, fn)
	return setmetatable({
		_connected = true,
		_signal = signal,
		_fn = fn
	}, Connection)
end

function Connection:Disconnect()
	self._connected = false

	-- Unhook the node, but DON'T clear it. That way any fire calls that are
	-- currently sitting on this node will be able to iterate forwards off of
	-- it, but any subsequent fire calls will not hit it, and it will be GCed
	-- when no more fire calls are sitting on it.
	if self._signal._handlerListHead == self then
		self._signal._handlerListHead = self._next
	else
		local prev = self._signal._handlerListHead
		while prev and prev._next ~= self do
			prev = prev._next
		end
		if prev then
			prev._next = self._next
		end
	end
end

local Signal: SignalImpl = {}::SignalImpl
Signal.__index = Signal

function Signal.new()
	return setmetatable({}, Signal)
end

function Signal:Connect(fn)
	local connection = Connection.new(self, fn)
	if self._handlerListHead then
		connection._next = self._handlerListHead
	end
	self._handlerListHead = connection
	return connection
end

function Signal:DisconnectAll()
	self._handlerListHead = nil
end

function Signal:Fire(...)
	local item = self._handlerListHead
	while item do
		if item._connected then
			--this variable was added to prevent type check warning
			local freeThread = freeRunnerThread or coroutine.create(runEventHandlerInFreeThread)
			if not freeRunnerThread then
				freeRunnerThread = freeThread
				-- Get the freeRunnerThread to the first yield
				coroutine.resume(freeThread)
			end
			task.spawn(freeThread, item._fn, ...)
		end
		item = item._next
	end
end

function Signal:Wait()
	local waitingCoroutine = coroutine.running()
	local cn;
	cn = self:Connect(function(...)
		cn:Disconnect()
		task.spawn(waitingCoroutine, ...)
	end)
	return coroutine.yield()
end

function Signal:Once(fn)
	local cn;
	cn = self:Connect(function(...)
		if cn._connected then
			cn:Disconnect()
		end
		fn(...)
	end)
	return cn
end

return Signal