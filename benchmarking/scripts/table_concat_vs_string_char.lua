
term.setTextColour(colours.lightGrey)
write "Comparing performance of "
term.setTextColour(colours.white)
write "string.char(table.unpack(...))"
term.setTextColour(colours.lightGrey)
write " vs "
term.setTextColour(colours.white)
print "table.concat(...)"

local WARMUP_ITERATIONS = 100
local MIN_ITERATIONS = 1000
local MIN_DURATION = 0.5
local lengths = { 25, 50, 100, 200, 400, 800, 1600, 3600, 7200 }

local BYTE_A = string.byte 'a'

local clock = os.clock
local string_char = string.char
local table_concat = table.concat
--- @diagnostic disable-next-line: deprecated
local table_unpack = table.unpack

for _, length in ipairs(lengths) do
	local char_iterations = 0
	local char_time = 0
	local concat_iterations = 0
	local concat_time = 0

	term.setTextColour(colours.lightGrey)
	write "Testing length "
	term.setTextColour(colours.cyan)
	write(string.format("%4d", length))
	term.setTextColour(colours.grey)
	write " :: "

	do
		local char_data = {}

		for _ = 1, WARMUP_ITERATIONS do
			for i = 1, length do
				char_data[i] = BYTE_A
			end
		end

		repeat
			local t0char = clock()
			
			for i = 1, length do
				char_data[i] = BYTE_A
			end

			string_char(table_unpack(char_data))

			char_time = char_time + (clock() - t0char)
			char_iterations = char_iterations + 1
		until char_iterations >= MIN_ITERATIONS and char_time >= MIN_DURATION
	end
	
	do
		local concat_data = {}

		for _ = 1, WARMUP_ITERATIONS do
			for i = 1, length do
				concat_data[i] = BYTE_A
			end
		end

		repeat
			local t0concat = clock()
			
			for i = 1, length do
				concat_data[i] = 'a'
			end

			table_concat(concat_data)

			concat_time = concat_time + (clock() - t0concat)
			concat_iterations = concat_iterations + 1
		until concat_iterations >= MIN_ITERATIONS and concat_time >= MIN_DURATION
	end

	char_time = char_time / char_iterations
	concat_time = concat_time / concat_iterations

	term.setTextColour(colours.lightGrey)
	write "char "
	term.setTextColour(colours.purple)
	write(string.format("%3dus  ", char_time * 1000000))
	term.setTextColour(colours.lightGrey)
	write "concat "
	term.setTextColour(colours.orange)
	write(string.format("%3dus  ", concat_time * 1000000))
	term.setTextColour(colours.lightGrey)
	write "winner: "
	term.setTextColour(char_time < concat_time and colours.purple or colours.orange)
	print(char_time < concat_time and "char" or "concat")

	--- @diagnostic disable-next-line: undefined-field
	os.queueEvent 'benchmark_yield'; os.pullEvent 'benchmark_yield'
end

term.setTextColour(colours.white)
