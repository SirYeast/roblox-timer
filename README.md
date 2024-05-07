# Roblox Timer
A fast OOP timer module. Expect almost completely accurate results even with a 100 timers running (why would you need that many anyway). Don't worry about memory leaks as no instances like bindable events are used and timers can be destroyed at any time.

The module uses a single `RunService.Heartbeat` connection to update every active timer and automatically disconnects when nothing remains. Due to the constant insertions and removals that can come with managing timers, they are not stored in a table and are instead linked to each other from least to greatest time remaining—essentially a [Linked list](https://en.wikipedia.org/wiki/Linked_list). Because of this, no sorting is necessary, just some simple relinking which is a lot more efficient especially when you have many timers running.

## API
```Lua
function Timer.new(duration: number, looped: boolean?, name: string?) -> Timer
```
Returns a new timer. `duration` must be greater than 0, decimals are allowed. `looped` is optional and defaults to nil (same as false). `name` is optional and defaults to "Timer`duration`". If provided, must be at least 1 character.

---
```Lua
function Timer.getActiveTimers() -> {Timer}
```
Returns a table of all active timers in order (least to greatest). Avoid heavy usage, but feel free to benchmark in your game.

---
```Lua
function Timer:GetElapsed() -> (number, boolean)
```
Returns how long the timer has been running and if it's finished. If looping, the elapsed time will reset after every loop.

---
```Lua
function Timer:Start()
```
Starts timer if it isn't running.

---
```Lua
function Timer:Stop(preventExecute: boolean?)
```
Stops timer if it's running. `preventExecute` is optional and defaults to nil (same as false), it prevents the `Executed` signal from firing.

---
```Lua
function Timer:Destroy(preventExecute: boolean?)
```
Same as `:Stop` method, but also removes the timer's metatable and freezes the timer. Method calls after destruction will error. To check if a timer is destroyed, use [table.isfrozen()](https://create.roblox.com/docs/reference/engine/libraries/table#isfrozen).

## Example
```Lua
local Timer = require(...)

local atmosphere = Instance.new("Atmosphere")
atmosphere.Density = 0.6
atmosphere.Haze = 3
atmosphere.Parent = game:GetService("Lighting")

--Create a timer named "Disco" that loops every 3 seconds
local discoTimer = Timer.new(3, true, "Disco")
discoTimer.Executed:Connect(function()
    atmosphere.Color = Color3.fromRGB(math.random(0, 255), math.random(0, 255), math.random(0, 255))
end)
discoTimer:Start()

--Should print a table with only the timer above in it
print(Timer.getActiveTimers())
```

## Resources
- https://github.com/stravant/goodsignal. All credit to stravant for the Signal.lua file in this repo, I simply implemented types.