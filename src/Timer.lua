--!strict
local RunService = game:GetService("RunService")

local Signal = require(script.Parent.Signal)

type TimerImpl = {
	__index: TimerImpl,
	__lt: (t1: Timer, t2: Timer)->boolean,
	__le: (t1: Timer, t2: Timer)->boolean,
	new: (duration: number, looped: boolean, name: string?)->Timer,
	getActiveTimers: ()->{Timer},
	GetElapsed: (self: Timer)->(number, boolean),
	Start: (self: Timer)->(),
	Stop: (self: Timer, preventExecute: boolean?)->(), --preventExecute = false by default
	Destroy: (self: Timer, preventExecute: boolean?)->()
}

export type Timer = typeof(setmetatable({}::{
	_next: Timer?,
	_isLocked: boolean,
	_duration: number,
	_startTime: number,
	_elapsed: number,
	Name: string,
	Looped: boolean,
	Executed: Signal.Signal
}, {}::TimerImpl))

local heartbeat: RBXScriptConnection? = nil
local head: Timer? = nil

local function updateTimers()
	local timer = head
	while timer do
		if timer._isLocked then
			timer._elapsed = time() - timer._startTime
			if timer._elapsed >= timer._duration then
				if timer.Looped then
					timer._startTime = time()
					timer._elapsed = 0
					timer.Executed:Fire()
				else
					timer:Stop()
				end
			end
		end
		timer = timer._next
	end
end

local Timer: TimerImpl = {}::TimerImpl
Timer.__index = Timer

function Timer.__lt(t1, t2)
	return t1._duration - t1._elapsed < t2._duration - t2._elapsed
end

function Timer.__le(t1, t2)
	return t1._duration - t1._elapsed <= t2._duration - t2._elapsed
end

function Timer.new(duration, looped, name)
	if duration <= 0 then error("Timer duration must be greater than 0.") end

	if name and string.len(name) == 0 then error("Timer name must be at least 1 character.") end

	return setmetatable({
		_isLocked = false,
		_duration = duration,
		_startTime = 0,
		_elapsed = 0,
		Name = name or "Timer"..duration,
		Looped = looped,
		Executed = Signal.new()
	}, Timer)
end

function Timer.getActiveTimers()
	local timers = {}
	local timer = head
	while timer do
		if timer._isLocked then
			table.insert(timers, timer)
		end
		timer = timer._next
	end
	return timers
end

function Timer:GetElapsed()
	return self._elapsed, self._elapsed >= self._duration
end

function Timer:Start()
	if self._isLocked then return end
	self._isLocked = true
	self._startTime = time()
	self._elapsed = 0

	if not head then
		head = self
	elseif head > self then
		self._next = head
		head = self
	else
		local prevTimer
		local nextTimer: Timer? = head
		while nextTimer and nextTimer <= self do
			prevTimer = nextTimer
			nextTimer = nextTimer._next
		end
		self._next = nextTimer
		prevTimer._next = self
	end

	if not heartbeat then
		heartbeat = RunService.Heartbeat:Connect(updateTimers)
	end
end

function Timer:Stop(preventExecute)
	if not self._isLocked then return end
	self._isLocked = false

	if not preventExecute then
		self.Executed:Fire()
	end

	if head == self then
		head = self._next
	else
		local timer = head
		while timer do
			if self == timer._next then
				timer._next = self._next
				break
			end
			timer = timer._next
		end
	end

	if not head and heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
end

function Timer:Destroy(preventExecute)
	self:Stop(preventExecute)
	setmetatable(self::any, nil)
end

return Timer