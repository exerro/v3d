
--- @class Profile
--- @field benchmark_options Dataset
--- @field chart_selectors string[]
--- @field row_selectors string[]
--- @field column_selectors string[]
--- @field chart_sorter fun(a: Datapoint, b: Datapoint): boolean
--- @field row_sorter fun(a: Datapoint, b: Datapoint): boolean
--- @field column_sorter fun(a: Datapoint, b: Datapoint): boolean
--- @field chart_formatter fun(a: Datapoint): string
--- @field row_formatter fun(a: Datapoint): string
--- @field column_formatter fun(a: Datapoint): string
--- @field uses_screen_size boolean | nil
--- @field validate_renders boolean | nil

local args = { ... }
local root_dir = shell.getRunningProgram():match("^.+/") or ""

package.path = root_dir .. "?.lua:" .. package.path

--- @module "libraries"
--- @module "standard_models"
--- @module "standard_screen_sizes"

local common = require 'common'

local warmup_iterations = 10
local min_iterations = 25
local min_duration = 0.2
--- @type 'all' | 'one' | 'none'
local present_buffers = 'all'
local blacklisted_libraries = {}

local term_width, term_height = term.getSize()

--- @alias ScreenSize { name: string, width: integer, height: integer }
--- @type { [integer]: ScreenSize }
local screen_sizes = {
	{ name = 'Native', width = term_width, height = term_height },
	{ name = 'Normal',  width = 51, height = 19 },
	{ name = 'Pocket',  width = 26, height = 20 },
	{ name = 'Turtle',  width = 39, height = 13 },
}

local function cell_formatter(cd)
	return string.format("&lightGrey;%4d fps", 1 / cd.total_time)
end

do
	local i = 1

	while i <= #args do
		if args[i] == '-tmin' then
			warmup_iterations = 1
			min_iterations = 3
			min_duration = 0
			table.remove(args, i)
			i = i - 1
		elseif args[i] == '-tmax' then
			warmup_iterations = 20
			min_iterations = 50
			min_duration = 0.5
			table.remove(args, i)
			i = i - 1
		elseif args[i] == '-sall' then
			screen_sizes = {
				{ name = 'Native', width = term_width, height = term_height },
				{ name = 'Monitor', width = 162, height =  80 },
				{ name = 'Large',   width = 100, height =  50 },
				{ name = 'Normal',  width =  51, height =  19 },
				{ name = 'Pocket',  width =  26, height =  20 },
				{ name = 'Turtle',  width =  39, height =  13 },
				{ name = 'Small',   width =  10, height =   5 },
			}
			table.remove(args, i)
			i = i - 1
		elseif args[i] == '-snormal' then
			screen_sizes = {
				{ name = 'Normal', width = 51, height = 19 },
			}
			table.remove(args, i)
			i = i - 1
		elseif args[i] == '-snative' then
			screen_sizes = {
				{ name = 'Native', width = term_width, height = term_height },
			}
			table.remove(args, i)
			i = i - 1
		elseif args[i] == '-v' then
			function cell_formatter(cd)
				return string.format("%4d fps (%02.3fms %3d%%)",
					1 / cd.total_time,
					cd.total_time * 1000,
					cd.draw_time / cd.total_time * 100)
			end
			table.remove(args, i)
			i = i - 1
		elseif args[i] == '-P' then
			present_buffers = 'one'
			table.remove(args, i)
			i = i - 1
		elseif args[i] == '-PP' then
			present_buffers = 'none'
			table.remove(args, i)
			i = i - 1
		elseif args[i] == '-L' then
			table.remove(args, i)
			table.insert(blacklisted_libraries, table.remove(args, i))
			i = i - 1
		elseif args[i] == '-h' or args[i] == '--help' then
			print('Run benchmarks for CCGL3D')
			print(' run <profile> [<options>]')

			local t = {
				{ '-tmin', 'Run with a small duration/number of iterations' },
				{ '-tmax', 'Run with a large duration/number of iterations' },
				{ '-sall', 'Run with all screen sizes' },
				{ '-snormal', 'Run with only the 51x19 screen size' },
				{ '-snative', 'Run with only the native (current) screen size' },
				{ '-v', 'Show verbose timings' },
				{ '-P', 'Don\'t measure present time' },
				{ '-PP', 'Don\'t measure present time nor display anything' },
				{ '-L', 'Blacklist a library from benchmarks', 'library' },
			}

			local fw = 0

			for _, d in ipairs(t) do
				local w = #d[1]
				if d[3] then
					w = w + 3 + #d[3]
				end
				fw = math.max(fw, w)
			end

			for _, d in ipairs(t) do
				term.write ' '
				term.setTextColour(colours.cyan)
				term.write(d[1])
				local pad = fw - #d[1]
				if d[3] then
					term.setTextColour(colours.white)
					term.write(" <" .. d[3] .. ">")
					pad = pad - 3 - #d[3]
				end
				term.write((" "):rep(pad))
				term.setTextColour(colours.lightGrey)
				term.write(" " .. d[2])
				print()
			end

			return
		end

		i = i + 1
	end
end

local profile_name = table.remove(args, 1) or error('No profile provided')

--- @type Profile
local profile = require('profiles.' .. profile_name)
local benchmark_options = profile.benchmark_options

if profile.uses_screen_size then
	benchmark_options = benchmark_options:copy():add_permutation('screen_size', screen_sizes)
end

if profile.validate_renders then
	present_buffers = 'one'
end

benchmark_options = benchmark_options:filter(function (o)
	for i = 1, #blacklisted_libraries do
		if blacklisted_libraries[i]:lower() == o.library.id:lower() then
			return false
		end
	end

	return true
end)

--------------------------------------------------------------------------------

local clock = os.clock

if ccemux then
	function clock()
		return ccemux.nanoTime() / 1000000000
	end
end

----------------------------------------------------------------

--- @param dataset Dataset
--- @param options table
--- @param triangles integer
--- @param clear_fn function
--- @param draw_fn function
--- @param present_fn function
--- @param warmup_iterations integer
--- @param min_iterations integer
--- @param min_duration number
--- @param present_buffers 'all' | 'one' | 'none'
local function benchmark(
	dataset, options, triangles,
	clear_fn, draw_fn, present_fn,
	warmup_iterations, min_iterations, min_duration, present_buffers)
	local clock = clock

	for i = 1, warmup_iterations do
		clear_fn()
		draw_fn()
		if present_buffers == 'all' or present_buffers == 'one' and i == 1 then
			present_fn()
			if profile.validate_renders then
			--- @diagnostic disable-next-line: undefined-field
				os.pullEvent 'key'
			end
		end
	end

	local iterations = 0
	local t0 = clock()
	local ty = t0
	repeat
		clear_fn()
		local t0d = clock()
		draw_fn()
		local td = clock() - t0d
		local t0p = clock()
		if present_buffers == 'all' then
			present_fn()
		end
		local tp = clock() - t0p
		iterations = iterations + 1
		dataset:add_datapoint({
			library = options.library,
			model = options.model,
			screen_size = options.screen_size,
			library_flags = options.library_flags or {},
			triangles = triangles,
			iteration = iterations,
			draw_time = td,
			present_time = tp,
			total_time = td + tp,
		})
		if clock() - ty > 0.2 then
			--- @diagnostic disable-next-line: undefined-field
			os.queueEvent 'benchmark_yield'; os.pullEvent 'benchmark_yield'
			ty = clock()
		end
	until iterations >= min_iterations and clock() - t0 >= min_duration

	return iterations
end

----------------------------------------------------------------

--- @returns Shape
local function flat_model_to_shape(t)
	local r = { triangles = #t / 10 }

	for i = 1, #t, 10 do
		local s = {}
		s.x0 = t[i]
		s.y0 = t[i + 1]
		s.z0 = t[i + 2]
		s.x1 = t[i + 3]
		s.y1 = t[i + 4]
		s.z1 = t[i + 5]
		s.x2 = t[i + 6]
		s.y2 = t[i + 7]
		s.z2 = t[i + 8]
		s.colour = t[i + 9]
		table.insert(r, s)
	end

	return r
end

--------------------------------------------------------------------------------

local benchmark_data = common.create_dataset()
local benchmarks_run = 0
local benchmarks_iterations = 0
local benchmark_start = clock()
local palette = {}

for i = 0, 15 do
	palette[i + 1] = { term.getPaletteColour(2 ^ i) }
end

for _, option in benchmark_options:iterator() do
	local ok, err = pcall(function()
		local model_data = option.model.create_model(option.model_detail)
		local shape

		if option.model.format == 'flat' then
			shape = flat_model_to_shape(model_data)
		else
			error("Unimplemented model format '" .. option.model.format .. "'")
		end

		local clear_fn, draw_fn, present_fn = option.library.setup_fn(
			option.library.library, shape, option.screen_size.width, option.screen_size.height, option.library_flags or {})

		benchmarks_run = benchmarks_run + 1
		benchmarks_iterations = benchmarks_iterations + benchmark(
			benchmark_data, option, shape.triangles, clear_fn, draw_fn, present_fn,
			warmup_iterations, min_iterations, min_duration, present_buffers)

		--- @diagnostic disable-next-line: undefined-field
		os.queueEvent 'benchmark_yield'; os.pullEvent 'benchmark_yield'
	end)

	if not ok then
		term.setTextColour(colours.red)
		print(err)
	end
end

local elapsed_time = clock() - benchmark_start
local elapsed_minutes = math.floor(elapsed_time / 60)
local elapsed_seconds = math.ceil(elapsed_time % 60)

for i = 0, 15 do
	--- @diagnostic disable-next-line: deprecated
	term.setPaletteColour(2 ^ i, table.unpack(palette[i + 1]))
end

--- @type Chart[]
local charts = {}

--- @type { library: Library, library_flags: table }[]
local chart_selectors = benchmark_data:distinct(table.unpack(profile.chart_selectors))

table.sort(chart_selectors, profile.chart_sorter)

for _, this_chart_selectors in ipairs(chart_selectors) do
	local this_data = benchmark_data:filter_values(this_chart_selectors)
	local columns = this_data:distinct(table.unpack(profile.column_selectors))
	local rows = this_data:distinct(table.unpack(profile.row_selectors))

	table.sort(columns, profile.column_sorter)
	table.sort(rows, profile.row_sorter)

	local chart = common.create_chart {
		title = profile.chart_formatter(this_chart_selectors),
		columns = columns,
		rows = rows,
		format_column = profile.column_formatter,
		format_row = profile.row_formatter,
		format_cell = function(row, column)
			local cell_data = this_data
				:filter_values(column)
				:filter_values(row)
				:reduce(function(a, b, n)
					return {
						draw_time = a.draw_time + b.draw_time / n,
						present_time = a.present_time + b.present_time / n,
						total_time = a.total_time + b.total_time / n,
					}
				end, { draw_time = 0, present_time = 0, total_time = 0 })

			return cell_formatter(cell_data)
		end,
	}

	table.insert(charts, chart)
end

term.setCursorPos(1, -1)
term.clear()

for i = 1, #charts do
	charts[i]:pretty_print {
		text_colour = colours.white,
		background_colour = colours.black,
		alternate_background_colour = colours.grey,
		separator_colour = colours.grey,
		alternate_separator_colour = colours.lightGrey,
		y_offset = select(2, term.getCursorPos()) + 1
	}
end

term.setBackgroundColour(colours.black)
term.setTextColour(colours.white)
print()
print(string.format("Elapsed time: %dm %ds", elapsed_minutes, elapsed_seconds))
print(string.format("Ran %d benchmarks with %d total iterations", benchmarks_run, benchmarks_iterations))

