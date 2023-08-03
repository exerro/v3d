
term.setTextColour(colours.lightGrey)
write "Comparing performance of "
term.setTextColour(colours.white)
write "bit.bor(bit.blshift(x, k), ...)"
term.setTextColour(colours.lightGrey)
write " vs "
term.setTextColour(colours.white)
write "x * k + ..."
term.setTextColour(colours.lightGrey)
write " vs "
term.setTextColour(colours.white)
print "string.char"

local WARMUP_ITERATIONS = 100
local MIN_ITERATIONS = 1000
local MIN_DURATION = 2
local CYCLE_ITERATIONS = 100

-- chosen randomly between 0 and 3
local CONST_V0 = 0
local CONST_V1 = 3
local CONST_V2 = 2
local CONST_V3 = 3
local CONST_V4 = 1
local CONST_V5 = 2

--- @diagnostic disable-next-line:undefined-global
local clock = ccemux and function() return ccemux.nanoTime() / 1000000000 end or os.clock
--- @diagnostic disable-next-line:undefined-global
local blshift, bor = bit.blshift, bit.bor
local string_char = string.char

local overhead_iterations = 0
local overhead_time = 0
local bitwise_iterations = 0
local bitwise_time = 0
local math_iterations = 0
local math_time = 0
local char_iterations = 0
local char_time = 0

do
	repeat
		local t0overhead = clock()

		for _ = 1, CYCLE_ITERATIONS do
			-- do nothing
		end

		overhead_time = overhead_time + (clock() - t0overhead)
		overhead_iterations = overhead_iterations + 1
	until overhead_iterations >= MIN_ITERATIONS and overhead_time >= MIN_DURATION
end

do
	local bitwise_lookup = {}

	for _ = 1, WARMUP_ITERATIONS * CYCLE_ITERATIONS do
		local v = CONST_V5
		v = bor(v, blshift(CONST_V0, 10))
		v = bor(v, blshift(CONST_V1, 8))
		v = bor(v, blshift(CONST_V2, 6))
		v = bor(v, blshift(CONST_V3, 4))
		v = bor(v, blshift(CONST_V4, 2))
		bitwise_lookup[v] = 0
	end

	repeat
		local t0bitwise = clock()

		for _ = 1, CYCLE_ITERATIONS do
			local v = CONST_V5
			v = bor(v, blshift(CONST_V0, 10))
			v = bor(v, blshift(CONST_V1, 8))
			v = bor(v, blshift(CONST_V2, 6))
			v = bor(v, blshift(CONST_V3, 4))
			v = bor(v, blshift(CONST_V4, 2))
			local _ = bitwise_lookup[v]
		end

		bitwise_time = bitwise_time + (clock() - t0bitwise)
		bitwise_iterations = bitwise_iterations + 1
	until bitwise_iterations >= MIN_ITERATIONS and bitwise_time >= MIN_DURATION
end

do
	local math_lookup = {}

	for _ = 1, WARMUP_ITERATIONS * CYCLE_ITERATIONS do
		local v = CONST_V0 * 1024
		        + CONST_V1 * 256
		        + CONST_V2 * 64
		        + CONST_V3 * 16
		        + CONST_V4 * 4
		        + CONST_V5
		math_lookup[v] = 0
	end

	repeat
		local t0math = clock()

		for _ = 1, CYCLE_ITERATIONS do
			local v = CONST_V0 * 1024
					+ CONST_V1 * 256
					+ CONST_V2 * 64
					+ CONST_V3 * 16
					+ CONST_V4 * 4
					+ CONST_V5
			local _ = math_lookup[v]
		end

		math_time = math_time + (clock() - t0math)
		math_iterations = math_iterations + 1
	until math_iterations >= MIN_ITERATIONS and math_time >= MIN_DURATION
end

do
	local char_lookup = {}

	for _ = 1, WARMUP_ITERATIONS * CYCLE_ITERATIONS do
		local v = string_char(CONST_V0, CONST_V1, CONST_V2, CONST_V3, CONST_V4, CONST_V5)
		char_lookup[v] = 0
	end

	repeat
		local t0char = clock()

		for _ = 1, CYCLE_ITERATIONS do
			local v = string_char(CONST_V0, CONST_V1, CONST_V2, CONST_V3, CONST_V4, CONST_V5)
			local _ = char_lookup[v]
		end

		char_time = char_time + (clock() - t0char)
		char_iterations = char_iterations + 1
	until char_iterations >= MIN_ITERATIONS and char_time >= MIN_DURATION
end

bitwise_time = bitwise_time / bitwise_iterations - overhead_time / overhead_iterations
math_time = math_time / math_iterations - overhead_time / overhead_iterations
char_time = char_time / char_iterations - overhead_time / overhead_iterations

local winner = bitwise_time < math_time and (bitwise_time < char_time and 'bitwise' or 'char') or (math_time < char_time and 'math' or 'char')

term.setTextColour(colours.lightGrey)
write "bitwise "
term.setTextColour(colours.purple)
write(string.format("%3.2fus  ", bitwise_time * 1000000))
term.setTextColour(colours.lightGrey)
write "math "
term.setTextColour(colours.orange)
write(string.format("%3.2fus  ", math_time * 1000000))
term.setTextColour(colours.lightGrey)
write "char "
term.setTextColour(colours.green)
write(string.format("%3.2fus  ", char_time * 1000000))
term.setTextColour(colours.lightGrey)
write "winner: "
term.setTextColour(winner == 'bitwise' and colours.purple or winner == 'math' and colours.orange or colours.green)
print(winner)

term.setTextColour(colours.white)
