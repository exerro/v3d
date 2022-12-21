
local screen_sizes = require 'screen_sizes'
local libraries = require 'libraries'
local models = require 'models'
local chartlib = require 'chart'

--------------------------------------------------------------------------------

local args = { ... }

-- TODO: use these
local specific_benchmark = nil
local show_results = false
local test_only = false

while true do
	if args[1] == '-b' then
		specific_benchmark = table.remove(args, 2)
		table.remove(args, 1)
	elseif args[1] == 'd' then
		show_results = true
		table.remove(args, 1)
	elseif args[1] == '-t' then
		test_only = true
		table.remove(args, 1)
	else
		break
	end
end

if args[1] then
	return error("Unexpected arguments: " .. table.concat(args))
end

if specific_benchmark then
	print("Running benchmark: " .. specific_benchmark)
else
	print("Running all benchmarks")
end

if show_results then
	print("Showing results")
end

--------------------------------------------------------------------------------

local function benchmark(
	chart, library, model, screen_size, triangles,
	clear_fn, draw_fn, present_fn,
	warmup_iterations, min_iterations, min_duration)
	local clock = os.clock

	for _ = 1, warmup_iterations do
		clear_fn()
		draw_fn()
		present_fn()
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
		present_fn()
		local tp = clock() - t0p
		iterations = iterations + 1
		chartlib.add_data(chart, {
			library = library,
			model = model,
			screen_size = screen_size,
			triangles = triangles,
			iteration = iterations,
			draw_time = td,
			present_time = tp,
			total_time = td + tp,
			fps = 1 / (td + tp),
		})
		if clock() - ty > 0.5 then
			os.queueEvent 'benchmark_yield'
			os.pullEvent 'benchmark_yield'
			ty = clock()
		end
	until iterations >= min_iterations and clock() - t0 >= min_duration
end

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

if test_only then
	local w, h = term.getSize()
	h = h - 1
	for mi = 1, #models do
		for li = 1, #libraries do
			local model = models[mi]
			local lib = libraries[li]
			local model_parameters = {}

			for i = 1, #model.parameters do
				model_parameters[i] = model.parameters[i].default
			end

			local model_data = model.create_model(table.unpack(model_parameters))
			local shape

			if model.format == 'flat' then
				shape = flat_model_to_shape(model_data)
			else
				error("Unimplemented model format '" .. model.format .. "'")
			end

			local clear_fn, draw_fn, present_fn = lib.setup_fn(lib.library, shape, w, h)

			clear_fn()
			draw_fn()
			present_fn()
			print ''
			write('Model: ' .. model.name .. '  ::  Library: ' .. lib.name)
			
			if mi ~= #models or li ~= #libraries then
				os.pullEvent 'mouse_click'
			end
		end
	end

	return
end

--------------------------------------------------------------------------------

local chart = chartlib.new()
local warmup_iterations = 50
local min_iterations = 100
local min_duration = 1

for si = 1, #screen_sizes do
	for mi = 1, #models do
		for li = 1, #libraries do
			local screen_size = screen_sizes[si]
			local model = models[mi]
			local lib = libraries[li]
			local model_parameters = {}

			for i = 1, #model.parameters do
				model_parameters[i] = model.parameters[i].default
			end

			local model_data = model.create_model(table.unpack(model_parameters))
			local shape

			if model.format == 'flat' then
				shape = flat_model_to_shape(model_data)
			else
				error("Unimplemented model format '" .. model.format .. "'")
			end

			local clear_fn, draw_fn, present_fn = lib.setup_fn(lib.library, shape, screen_size.width, screen_size.height)

			benchmark(chart, lib, model, screen_size, shape.triangles, clear_fn, draw_fn, present_fn, warmup_iterations, min_iterations, min_duration)
		end
	end
end

term.setCursorPos(1, 1)
term.clear()

for li = 1, #libraries do
	if li ~= 1 then
		print(("="):rep(term.getSize()))
	end
	print(chartlib.to_string(chart, {
		title = libraries[li].name,
		filter_values = {
			library = libraries[li],
		},
		aggregate = function(...)
			local t = { ... }
			local n = #t
			local r = { iterations = n, draw_time = 0, present_time = 0, total_time = 0, fps = 0 }

			for i = 1, n do
				r.draw_time = r.draw_time + t[i].draw_time / n
				r.present_time = r.present_time + t[i].present_time / n
			end

			r.total_time = r.draw_time + r.present_time
			r.fps = 1 / r.total_time

			return r
		end,
		column_key = 'model',
		column_key_writer = function (model, dp)
			return model.name .. ' (' .. dp.triangles .. ')'
		end,
		column_key_sorter = function(a, b)
			return a.triangles < b.triangles
		end,
		row_key = 'screen_size',
		row_key_writer = function (screen_size)
			return screen_size.name .. ' (' .. screen_size.width .. 'x' .. screen_size.height .. ')'
		end,
		row_key_sorter = function(a, b)
			return a.fps < b.fps
		end,
		value_keys = { 'fps', 'draw_time', 'present_time', 'ratio' },
		value_format = '%4dfps (%5dus %5dus %s)',
		value_writers = {
			draw_time = function(t)
				return t * 1000000
			end,
			present_time = function(t)
				return t * 1000000
			end,
			ratio = function(_, dp)
				local dpd = dp.draw_time / dp.total_time
				dpd = math.floor(dpd * 100 + 0.5)
				return string.format('%2d:%2d', dpd, 100 - dpd)
			end,
		},
	}))
end
