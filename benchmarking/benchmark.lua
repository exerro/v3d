
local screen_sizes = require 'screen_sizes'
local libraries = require 'libraries'
local models = require 'models'
local chartlib = require 'chart'
local profiles = require 'profiles'

--------------------------------------------------------------------------------

local args = { ... }

-- TODO: use these
local present_buffers = false
local profile

while args[1] do
	if args[1] == 'd' then
		present_buffers = true
		table.remove(args, 1)
	elseif profile then
		return error("Unexpected arguments: " .. table.concat(args))
	else
		profile = table.remove(args, 1)
	end
end

if profile == 'profiles' then
	for k in pairs(profiles) do
		print(k)
	end
	return
elseif profile then
	print("Running profile " .. profile)
else
	return error('Expected profile')
end

if present_buffers then
	print("Presenting buffers")
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
			model_triangles = model.name .. " (" .. triangles .. ")",
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

	return iterations
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

local benchmark_start = os.clock()
local benchmarks_run = 0
local benchmarks_iterations = 0

local chart = chartlib.new()

local this_profile = profiles[profile] or error("Unknown profile '" .. profile .. "'")

local included_models = models
if this_profile.include_models then
	included_models = {}
	for i = 1, #this_profile.include_models do
		included_models[i] = models[this_profile.include_models[i]]
	end
end

local included_libraries = libraries
if this_profile.include_libraries then
	included_libraries = {}
	for i = 1, #this_profile.include_libraries do
		included_libraries[i] = libraries[this_profile.include_libraries[i]]
	end
end

for si = 1, #screen_sizes do
	local screen_size = screen_sizes[si]
	local ok = true

	if this_profile.min_width and screen_size.width < this_profile.min_width then ok = false end
	if this_profile.max_width and screen_size.width > this_profile.max_width then ok = false end
	if this_profile.min_height and screen_size.height < this_profile.min_height then ok = false end
	if this_profile.max_height and screen_size.height > this_profile.max_height then ok = false end
	if this_profile.min_pixels and screen_size.width * screen_size.height < this_profile.min_pixels then ok = false end
	if this_profile.max_pixels and screen_size.width * screen_size.height > this_profile.max_pixels then ok = false end

	if ok then
		for _, model in ipairs(included_models) do
			local parameter_map = (this_profile.model_parameters or {})[model.id] or {}

			-- all this parameter stuff is bs but fuck it idc
			for i = 1, #model.parameters do
				parameter_map[model.parameters[i]] = parameter_map[model.parameters[i]] or { model.parameters[i].default }
			end

			for parameter_name, parameter_values in pairs(parameter_map) do
				for _, parameter_value in ipairs(parameter_values) do
					local model_parameters = {}

					for i = 1, #model.parameters do
						if model.parameters[i].name == parameter_name then
							model_parameters[i] = parameter_value
						else
							model_parameters[i] = model.parameters[i].default
						end
					end

					local model_data = model.create_model(table.unpack(model_parameters))
					local shape

					if model.format == 'flat' then
						shape = flat_model_to_shape(model_data)
					else
						error("Unimplemented model format '" .. model.format .. "'")
					end

					for _, lib in ipairs(included_libraries) do
						local clear_fn, draw_fn, present_fn = lib.setup_fn(lib.library, shape, screen_size.width, screen_size.height)

						benchmarks_iterations = benchmarks_iterations + benchmark(chart, lib, model, screen_size, shape.triangles, clear_fn, draw_fn, present_fn,
							this_profile.warmup_iterations, this_profile.min_iterations, this_profile.min_duration)
						benchmarks_run = benchmarks_run + 1

						os.queueEvent 'benchmark_yield'
						os.pullEvent 'benchmark_yield'
						if this_profile.post_run then
							this_profile.post_run()
						end
					end
				end
			end
		end
	end
end

local chart_options = this_profile.get_charts()

if #chart_options == 0 then
	return
end

term.setCursorPos(1, 1)
term.clear()

for i, options in ipairs(chart_options) do
	local dark = true
	local first = true
	for line in chartlib.to_string(chart, options):gmatch("[^\n]+") do
		if first and i ~= 1 then
			print(("-"):rep(#line))
		end
		local row_label, rest = line:match "^([^|]*)(|?.*)$"
		term.setBackgroundColour(dark and colours.black or colours.grey)
		term.setTextColour(colours.white)
		write(row_label)
		if not first then term.setTextColour(colours.lightGrey) end
		print(rest)
		dark = not dark
		first = false
	end
	term.setTextColour(colours.white)
	term.setBackgroundColour(colours.black)
end

local elapsed_seconds = os.clock() - benchmark_start
local elapsed_minutes = math.floor(elapsed_seconds / 60)
elapsed_seconds = math.floor(elapsed_seconds % 60 + 0.5)

print()
print(string.format("Elapsed time: %dm %ds", elapsed_minutes, elapsed_seconds))
print(string.format("Ran %d benchmarks with %d total iterations", benchmarks_run, benchmarks_iterations))
