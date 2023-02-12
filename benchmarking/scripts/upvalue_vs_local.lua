
local upvalue = 2

local function test_upvalue()
	local result = 1

	result = result * upvalue
	result = result * upvalue
	result = result * upvalue
	result = result * upvalue
	result = result * upvalue

	result = result * upvalue
	result = result * upvalue
	result = result * upvalue
	result = result * upvalue
	result = result * upvalue

	result = result * upvalue
	result = result * upvalue
	result = result * upvalue
	result = result * upvalue
	result = result * upvalue

	result = result * upvalue
	result = result * upvalue
	result = result * upvalue
	result = result * upvalue
	result = result * upvalue

	result = result * upvalue
	result = result * upvalue
	result = result * upvalue
	result = result * upvalue
	result = result * upvalue

	result = result * upvalue
	result = result * upvalue
	result = result * upvalue
	result = result * upvalue
	result = result * upvalue
end

local function test_local()
	local result = 1
	local lovalue = 2

	result = result * lovalue
	result = result * lovalue
	result = result * lovalue
	result = result * lovalue
	result = result * lovalue

	result = result * lovalue
	result = result * lovalue
	result = result * lovalue
	result = result * lovalue
	result = result * lovalue

	result = result * lovalue
	result = result * lovalue
	result = result * lovalue
	result = result * lovalue
	result = result * lovalue

	result = result * lovalue
	result = result * lovalue
	result = result * lovalue
	result = result * lovalue
	result = result * lovalue

	result = result * lovalue
	result = result * lovalue
	result = result * lovalue
	result = result * lovalue
	result = result * lovalue

	result = result * lovalue
	result = result * lovalue
	result = result * lovalue
	result = result * lovalue
	result = result * lovalue
end

local function test_localise_upvalue()
	local result = 1

	result = upvalue
	result = upvalue
	result = upvalue
	result = upvalue
	result = upvalue

	result = upvalue
	result = upvalue
	result = upvalue
	result = upvalue
	result = upvalue

	result = upvalue
	result = upvalue
	result = upvalue
	result = upvalue
	result = upvalue

	result = upvalue
	result = upvalue
	result = upvalue
	result = upvalue
	result = upvalue

	result = upvalue
	result = upvalue
	result = upvalue
	result = upvalue
	result = upvalue

	result = upvalue
	result = upvalue
	result = upvalue
	result = upvalue
	result = upvalue
end

local function test_addition()
	local result = 1

	result = result + 1
	result = result + 1
	result = result + 1
	result = result + 1
	result = result + 1

	result = result + 1
	result = result + 1
	result = result + 1
	result = result + 1
	result = result + 1

	result = result + 1
	result = result + 1
	result = result + 1
	result = result + 1
	result = result + 1

	result = result + 1
	result = result + 1
	result = result + 1
	result = result + 1
	result = result + 1

	result = result + 1
	result = result + 1
	result = result + 1
	result = result + 1
	result = result + 1

	result = result + 1
	result = result + 1
	result = result + 1
	result = result + 1
	result = result + 1
end

local currentTime = os.clock

if ccemux then
	currentTime = function() return ccemux.nanoTime() / 1000000000 end
end

local t0 = currentTime()
for i = 1, 1000000 do
	test_upvalue()
end
local tu = currentTime() - t0

local t1 = currentTime()
for i = 1, 1000000 do
	test_local()
end
local tl = currentTime() - t1

local t2 = currentTime()
for i = 1, 1000000 do
	test_local()
end
local tlu = currentTime() - t2

local t3 = currentTime()
for i = 1, 1000000 do
	test_local()
end
local ta = currentTime() - t3

print(string.format('local: %.1fs  upvalue: %.1fs  ratio: %d%%', tl, tu, tl / tu * 100))
print(string.format('localise upvalue: %.1fs  addition: %.1fs  ratio: %d%%', tlu, ta, tlu / ta * 100))
