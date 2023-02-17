
local base_path = shell and (shell.getRunningProgram():match '^(.+/).+/' or '') or 'v3d/'

term.clear()
term.setCursorPos(1, 1)

assert(shell.run(base_path .. 'tools/build.lua'))

local function run_handling_terminate(s, ...)
	local co = coroutine.create(function(...)
		assert(shell.execute(s, ...))
	end)
	local event = { ... }

	while true do
		local ok, data = coroutine.resume(co, table.unpack(event))

		if not ok then
			term.setTextColour(colours.red)
			print(data)
			break
		elseif coroutine.status(co) == 'dead' then
			break
		end

		event = { coroutine.yield(data) }

		if event[1] == 'terminate' then
			term.setTextColour(colours.yellow)
			print 'Terminated'
			break
		end
	end

	for i = 0, 15 do
		term.setPaletteColour(2 ^ i, term.nativePaletteColour(2 ^ i))
	end
end

print()
print()
local y = select(2, term.getCursorPos()) - 2

local function confirm(prompt)
	term.setBackgroundColour(colours.black)
	term.setTextColour(colours.lightBlue)
	term.setCursorPos(1, y)
	term.clearLine()
	term.setCursorBlink(true)
	term.write(prompt)
	term.setTextColour(colours.white)
	print ' y/N'

	return select(2, coroutine.yield 'char'):lower() == 'y'
end

if confirm 'Run examples?' then
	for _, file in ipairs(fs.list(base_path .. 'examples')) do
		if confirm('Run example \'' .. file .. '\'?') then
			term.setCursorBlink(false)
			run_handling_terminate(base_path .. 'examples/' .. file)
		else
			term.setCursorBlink(false)
		end
	end
end

if confirm 'Run benchmarks?' then
	if confirm 'Run default benchmarks?' then
		run_handling_terminate(base_path .. 'tools/benchmark/run.lua', '-tmin', '-snative', '-L', 'Pine3D', 'default')
	end
	if confirm 'Run compare benchmarks?' then
		run_handling_terminate(base_path .. 'tools/benchmark/run.lua', '-tmin', '-snative', '-L', 'Pine3D', 'compare')
	end
end
