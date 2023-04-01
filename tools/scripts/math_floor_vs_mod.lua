
local upvalue_math_floor = math.floor

local currentTime = os.clock

if ccemux then
	currentTime = function() return ccemux.nanoTime() / 1000000000 end
end

local count = 1000000000

local t0 = currentTime()
for _ = 1, count do
	local math_floor = upvalue_math_floor

	local n = 1.3

	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)

	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)

	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)

	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)

	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)

	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)

	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)

	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)

	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)

	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)

	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)

	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)
	n = math_floor(n)
end
local tf = currentTime() - t0

local t1 = currentTime()
for _ = 1, count do
	local n = 1.3

	n = n - n % 3
	n = n - n % 3
	n = n - n % 3
	n = n - n % 3
	n = n - n % 3

	n = n - n % 3
	n = n - n % 3
	n = n - n % 3
	n = n - n % 3
	n = n - n % 3

	n = n - n % 3
	n = n - n % 3
	n = n - n % 3
	n = n - n % 3
	n = n - n % 3

	n = n - n % 3
	n = n - n % 3
	n = n - n % 3
	n = n - n % 3
	n = n - n % 3

	n = n - n % 3
	n = n - n % 3
	n = n - n % 3
	n = n - n % 3
	n = n - n % 3

	n = n - n % 3
	n = n - n % 3
	n = n - n % 3
	n = n - n % 3
	n = n - n % 3

	n = n - n % 3
	n = n - n % 3
	n = n - n % 3
	n = n - n % 3
	n = n - n % 3

	n = n - n % 3
	n = n - n % 3
	n = n - n % 3
	n = n - n % 3
	n = n - n % 3

	n = n - n % 3
	n = n - n % 3
	n = n - n % 3
	n = n - n % 3
	n = n - n % 3

	n = n - n % 3
	n = n - n % 3
	n = n - n % 3
	n = n - n % 3
	n = n - n % 3

	n = n - n % 3
	n = n - n % 3
	n = n - n % 3
	n = n - n % 3
	n = n - n % 3

	n = n - n % 3
	n = n - n % 3
	n = n - n % 3
	n = n - n % 3
	n = n - n % 3
end
local tm = currentTime() - t1

local t2 = currentTime()
for _ = 1, count do
	local n = 1.3
end
local tn = currentTime() - t2

print(string.format('math.floor: %.1fms  mod: %.1fms  ref: %.1fms  ratio: %d%%', tf * 1000, tm * 1000, tn * 1000, tf / tm * 100))
