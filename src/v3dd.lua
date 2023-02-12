
local args = { ... }
local fps_bc = colours.black
local fps_fc = colours.white
local fps_enabled = false
local validation_enabled = true
local capture_key = keys.f12
local v3d_require_path = '/v3d'

-- error 'v3dd is not updated to latest version of v3d'

while args[1] and args[1]:sub(1, 1) == '-' do
	local arg = table.remove(args, 1)

	if arg == '--fps-bc' then
		fps_bc = table.remove(args, 1) or error('Expected colour after --fps-bc', 0)
		fps_bc = colours[fps_bc] or error('Unknown colour \'' .. fps_bc .. '\'', 0)
	elseif arg == '--fps-fc' then
		fps_fc = table.remove(args, 1) or error('Expected colour after --fps-fc', 0)
		fps_fc = colours[fps_fc] or error('Unknown colour \'' .. fps_fc .. '\'', 0)
	elseif arg == '--show-fps' or arg == '--fps' or arg == '-f' then
		fps_enabled = true
	elseif arg == '--no-validation' or arg == '-V' then
		validation_enabled = false
	elseif arg == '--capture-key' or arg == '--key' or arg == '-k' then
		capture_key = table.remove(args, 1) or error('Expected key name after --capture-key', 0)
		capture_key = keys[capture_key] or error('Unknown key name \'' .. capture_key .. '\'', 0)
	elseif arg == '--v3d-path' then
		v3d_require_path = table.remove(args, 1) or error('Expected path after --v3d-path', 0)
	else
		error('Unknown option \'' .. arg .. '\'', 0)
	end
end

local program = table.remove(args, 1) or error('Expected program path', 0)

--------------------------------------------------------------------------------

local program_environment = setmetatable({}, getmetatable(_ENV))
local v3dd_debug_marker = tostring {} :sub(8)
local program_fn

do
	for k, v in pairs(_ENV) do
		program_environment[k] = v
	end

	local requirelib = require '/rom.modules.main.cc.require'
	program_environment.require, program_environment.package = requirelib.make(program_environment, fs.getDir(program))

	local program_file = io.open(program, 'r')
	local program_contents = ''

	if program_file then
		program_contents = program_file:read '*a'
		program_file:close()
	else
		error('Failed to read program \'' .. program .. '\'', 0)
	end

	local err
	program_fn, err = load(program_contents, 'v3dd@' .. v3dd_debug_marker .. ' ' .. program, nil, program_environment)

	if not program_fn then
		error('Failed to load program: ' .. err, 0)
	end
end

--------------------------------------------------------------------------------

--- @class Pane
--- @field present fun(x: integer, y: integer, width: integer, height: integer)

--- @class Resource
--- @field label string
--- @field category string
--- @field data any
--- @field preview Pane
--- @field view Pane

--- @class Instruction
--- @field description string

--- @class Capture
--- @field all_resources Resource[]
--- @field frame_resources Resource[] | { [Resource]: true | nil }
--- @field instructions Instruction[]

--- @class LibraryWrapper
--- @field library table
--- @field begin_frame fun(): nil
--- @field finish_frame fun(): boolean
--- @field begin_capture fun(): nil
--- @field finish_capture fun(): Capture

--- @return LibraryWrapper
local function create_v3d_wrapper(enable_validation)
	local v3d_ok, v3d_lib = pcall(require, v3d_require_path)
	--- @cast v3d_lib v3d
	--- @type v3d
	local v3d_wrapper = {}

	if not v3d_ok then
		error('Failed to load v3d library at \'' .. v3d_require_path .. '\': ' .. v3d_lib .. '.\nUse --v3d-path to specify alternate path', 0)
	end

	local resource_labels = setmetatable({}, {
		__index = function(_, data)
			return tostring(data):sub(8)
		end,
	})
	--- @type Resource[]
	local all_resources = {}
	--- @type Capture | nil
	local capture
	local blit_called = false

	--- @param r Resource
	--- @return Resource
	local function create_resource(r)
		table.insert(all_resources, r)
		if capture then
			table.insert(capture.frame_resources, r)
			capture.frame_resources[r] = true
		end
		return r
	end

	--- @diagnostic disable: duplicate-set-field

	v3d_wrapper.CULL_BACK_FACE = v3d_lib.CULL_BACK_FACE
	v3d_wrapper.CULL_FRONT_FACE = v3d_lib.CULL_FRONT_FACE
	v3d_wrapper.DEFAULT_LAYOUT = v3d_lib.DEFAULT_LAYOUT
	v3d_wrapper.UV_LAYOUT = v3d_lib.UV_LAYOUT
	v3d_wrapper.DEBUG_CUBE_LAYOUT = v3d_lib.DEBUG_CUBE_LAYOUT

	function v3d_wrapper.create_framebuffer(width, height, label)
		if enable_validation then
			assert(type(width) == 'number', 'Width given to create framebuffer was not a number')
			assert(type(height) == 'number', 'Height given to create framebuffer was not a number')
			assert(width > 0, 'Width given to create framebuffer was <= 0 (' .. width .. ')')
			assert(height > 0, 'Height given to create framebuffer was <= 0 (' .. height .. ')')
		end

		local fb = v3d_lib.create_framebuffer(width, height)

		local blit_subpixel_orig = fb.blit_subpixel
		local blit_subpixel_depth_orig = fb.blit_subpixel_depth
		local clear_orig = fb.clear
		local clear_depth_orig = fb.clear_depth

		function fb.blit_subpixel(self, term, dx, dy)
			dx = dx == nil and 0 or dx
			dy = dy == nil and 0 or dy

			if enable_validation then
				assert(type(term) == 'table', 'Term passed to TODO')
				-- TODO
			end

			if capture then
				table.insert(capture.instructions, {
					description = string.format('framebuffer_blit_subpixel(%s, term, %d, %d)',
						resource_labels[self], dx, dy)
				})
			end

			blit_subpixel_orig(self, term, dx, dy)
			blit_called = true
		end

		function fb.blit_subpixel_depth(self, term, dx, dy, update_palette)
			-- TODO: validation

			blit_subpixel_depth_orig(self, term, dx, dy, update_palette)
			blit_called = true
		end

		function fb.clear(self, colour)
			colour = colour or 1

			-- TODO: validation

			if capture then
				local colour_name = tostring(colour)

				for k, v in pairs(colours) do
					if colour == v then
						colour_name = colour_name .. ' \'' .. k .. '\''
						break
					end
				end

				table.insert(capture.instructions, {
					description = string.format('framebuffer_clear(%s, %s)',
						resource_labels[self], colour_name)
				})
			end

			clear_orig(self, colour)
		end

		-- TODO: clear_depth

		if label ~= nil then
			resource_labels[fb] = label
		end

		create_resource {
			label = resource_labels[fb],
			category = 'framebuffer',
			data = fb,
			preview = { present = function()
				error('NYI')
			end },
			view = { present = function()
				error('NYI')
			end },
		}

		return fb
	end

	function v3d_wrapper.create_framebuffer_subpixel(width, height, label)
		return v3d_wrapper.create_framebuffer(width * 2, height * 3, label)
	end

	-- TODO
	v3d_wrapper.create_layout = v3d_lib.create_layout

	-- TODO
	v3d_wrapper.create_geometry_builder = v3d_lib.create_geometry_builder

	-- TODO
	v3d_wrapper.create_debug_cube = v3d_lib.create_debug_cube

	function v3d_wrapper.create_camera(fov, label)
		if enable_validation then
			-- TODO
			assert(fov == nil or type(fov) == 'number')
			assert(fov == nil or fov > 0)
			assert(fov == nil or fov < math.pi / 2)
		end

		local cam = v3d_lib.create_camera(fov)

		if label ~= nil then
			resource_labels[cam] = label
		end

		create_resource {
			label = resource_labels[cam],
			category = 'camera',
			data = cam,
			preview = { present = function()
				error('NYI')
			end },
			view = { present = function()
				error('NYI')
			end },
		}

		return cam
	end

	function v3d_wrapper.create_pipeline(options, label)
		if enable_validation then
			--- @cast options V3DPipelineOptions
			-- TODO
			assert(type(options) == 'table')
			assert(options.layout) -- TODO
			-- TODO: all the new layout/attribute stuff
			assert(not options.cull_face or options.cull_face == v3d_lib.CULL_BACK_FACE or options.cull_face == v3d_lib.CULL_FRONT_FACE)
			assert(options.depth_store == nil or type(options.depth_store) == 'boolean')
			assert(options.depth_test == nil or type(options.depth_test) == 'boolean')
			assert(options.fragment_shader == nil or type(options.fragment_shader) == 'function')
			assert(options.pixel_aspect_ratio == nil or type(options.pixel_aspect_ratio) == 'number')
			assert(options.pixel_aspect_ratio == nil or options.pixel_aspect_ratio > 0)
		end

		local pipeline = v3d_lib.create_pipeline(options)

		local render_geometry_orig = pipeline.render_geometry
		local set_uniform_orig = pipeline.set_uniform
		local get_uniform_orig = pipeline.get_uniform

		function pipeline.render_geometry(self, geometry, fb, camera)
			-- TODO: validation

			if capture then
				table.insert(capture.instructions, {
					description = string.format('pipeline_render_geometry(%s, %s, %s, %s)',
						resource_labels[self], resource_labels[geometry],
						resource_labels[fb], resource_labels[camera])
				})
			end

			render_geometry_orig(self, geometry, fb, camera)
		end

		-- TODO

		if label ~= nil then
			resource_labels[pipeline] = label
		end

		create_resource {
			label = resource_labels[pipeline],
			category = 'pipeline',
			data = pipeline,
			preview = { present = function()
				error('NYI')
			end },
			view = { present = function()
				error('NYI')
			end },
		}

		return pipeline
	end

	function v3d_wrapper.create_texture_sampler(texture_uniform, width_uniform, height_uniform)
		if enable_validation then
			-- TODO
			assert(texture_uniform == nil or type(texture_uniform) == 'string')
			assert(width_uniform == nil or type(width_uniform) == 'string')
			assert(height_uniform == nil or type(height_uniform) == 'string')
		end

		local fn = v3d_lib.create_texture_sampler(texture_uniform, width_uniform, height_uniform)

		-- TODO: track this?

		return fn
	end

	--- @diagnostic enable: duplicate-set-field

	return {
		library = v3d_wrapper,
		begin_capture = function()
			capture = {
				all_resources = all_resources,
				frame_resources = {},
				instructions = {},
			}
		end,
		finish_capture = function()
			local c = capture
			assert(c ~= nil)
			capture = nil
			return c
		end,
		begin_frame = function()
			blit_called = false
		end,
		finish_frame = function()
			return blit_called
		end,
	}
end

----------------------------------------------------------------

local v3d_wrapper = create_v3d_wrapper(validation_enabled)
program_environment.package.loaded['/v3d'] = v3d_wrapper.library
program_environment.package.loaded['v3d'] = v3d_wrapper.library
program_environment.package.loaded[v3d_require_path] = v3d_wrapper.library

--------------------------------------------------------------------------------

--- @param capture Capture
local function present_captures(capture)
	local palette = {}
	do -- setup
		term.setBackgroundColour(colours.black)
		term.setTextColour(colours.white)
		term.clear()
		term.setCursorPos(1, 1)

		for i = 0, 15 do
			palette[i + 1] = { term.getPaletteColour(2 ^ i) }
		end

		for i = 0, 15 do
			term.setPaletteColour(2 ^ i, term.nativePaletteColour(2 ^ i))
		end

		term.setPaletteColour(colours.white, 0.95, 0.95, 0.95)
		term.setPaletteColour(colours.grey, 0.2, 0.2, 0.2)
		term.setPaletteColour(colours.lightGrey, 0.6, 0.6, 0.6)
		term.setPaletteColour(colours.purple, 0.45, 0.25, 0.55)
	end

	--- @alias ResourcesList ({ type: 'category', name: string, next: integer, previous: integer, count: integer } | { type: 'resource', resource: Resource })[]

	--- @return ResourcesList
	local function generate_resources_list(show_all)
		local capture_categories = {}
		local resources_list = show_all and capture.all_resources or capture.frame_resources
		local result = { __value = true }

		for i = 1, #resources_list do
			if capture_categories[resources_list[i].category] then
				table.insert(capture_categories[resources_list[i].category], resources_list[i])
			else
				capture_categories[resources_list[i].category] = { resources_list[i] }
				table.insert(capture_categories, resources_list[i].category)
			end
		end

		table.sort(capture_categories)

		local previous_category = 0

		for i = 1, #capture_categories do
			local count = #capture_categories[capture_categories[i]]
	
			table.insert(result, {
				type = 'category',
				name = capture_categories[i],
				next = #result + 2 + count,
				previous = previous_category,
				count = count,
			})

			previous_category = #result

			local resources = capture_categories[capture_categories[i]]

			table.sort(resources, function(a, b) return a.label < b.label end)

			for j = 1, #resources do
				table.insert(result, {
					type = 'resource',
					resource = resources[j],
				})
			end
		end

		return result
	end

	--- @class CaptureViewModel
	--- @field fullscreen_pane Pane | nil
	--- @field width integer
	--- @field half_width integer
	--- @field tab 'resources' | 'instructions'
	--- @field resources_scroll integer
	--- @field resources_selection_index integer
	--- @field resources_show_all boolean
	--- @field resources_expanded_categories { [string]: true | nil }
	--- @field resources_list ResourcesList
	--- @field instructions_scroll integer
	local model = {
		fullscreen_pane = nil,
		width = term.getSize(),
		half_width = math.floor(term.getSize() / 2),
		tab = 'resources',
		resources_scroll = 0,
		resources_selection_index = 0,
		resources_show_all = true,
		resources_expanded_categories = { __value = true },
		resources_list = generate_resources_list(true),
		instructions_scroll = 0,
	}

	--- @param t CaptureViewModel
	local function update_model(t, m)
		m = m or model
		for k, v in pairs(t) do
			if type(v) == 'table' then
				if m[k].__value then
					m[k] = v
					v.__value = true
				else
					update_model(v, m[k])
				end
			else
				m[k] = v
			end
		end
	end

	local function redraw_header()
		term.setCursorPos(1, 1)
		term.setTextColour(colours.white)
		term.setBackgroundColour(model.tab == 'resources' and colours.purple or colours.grey)
		term.write(string.rep(' ', model.half_width))
		term.setCursorPos(2, 1)
		term.write(model.tab == 'resources' and '[' or ' ')
		term.write 'Resources'
		term.write(model.tab == 'resources' and ']' or '')

		term.setCursorPos(model.half_width + 1, 1)
		term.setBackgroundColour(model.tab == 'resources' and colours.grey or colours.purple)
		term.write(string.rep(' ', model.width - model.half_width))
		term.setCursorPos(model.half_width + 2, 1)
		term.write(model.tab == 'resources' and ' ' or '[')
		term.write 'Instructions'
		term.write(model.tab == 'resources' and '' or ']')
	end

	local function redraw_resource_list()
		do
			local format = model.resources_selection_index == 0 and '[%s]' or ' %s '
			term.setCursorPos(2, 3)
			term.setBackgroundColour(colours.lightGrey)
			term.setTextColour(colours.black)
			term.write(format:format(model.resources_show_all and 'x' or ' '))
			term.setBackgroundColour(colours.grey)
			term.setTextColour(colours.white)
			term.write ' Show all resources'
		end

		local max_category_length = 0

		for i = 1, #model.resources_list do
			if model.resources_list[i].type == 'category' then
				max_category_length = math.max(max_category_length, #model.resources_list[i].name)
			end
		end

		local y = -model.resources_scroll
		local i = 1

		while i <= #model.resources_list do
			term.setCursorPos(2, y + 5)

			local format = model.resources_selection_index == i and '[%s]' or ' %s '

			if y >= 0 then
				if i == model.resources_selection_index then
					term.setTextColour(colours.cyan)
				elseif model.resources_list[i].type == 'category' then
					term.setTextColour(colours.white)
				else
					term.setTextColour(colours.lightGrey)
				end

				if model.resources_list[i].type == 'category' then
					local name = model.resources_list[i].name

					term.write(format:format(name:sub(1, 1):upper() .. name:sub(2)))
					term.setTextColour(colours.white)
					term.write(string.rep(' ', max_category_length - #model.resources_list[i].name + 1))
					term.write(string.format('%6s', model.resources_list[i].count))

					if model.resources_expanded_categories[model.resources_list[i].name] then
						term.write ' -'
					else
						term.write ' +'
						i = model.resources_list[i].next - 1
					end
				else
					term.write ' '
					term.write(format:format('@' .. model.resources_list[i].resource.label))
				end
			end

			i = i + 1
			y = y + 1
		end
	end

	local function redraw()
		term.setBackgroundColour(colours.grey)
		term.clear()

		redraw_header()

		if model.tab == 'resources' then
			redraw_resource_list()
		else
			for i = 1, #capture.instructions do
				term.setCursorPos(2, i + 2)
				term.write(capture.instructions[i].description)
			end
		end
	end

	while true do
		redraw()

		local event = { coroutine.yield() }

		if event[1] == 'terminate' then
			return false
		elseif event[1] == 'key' and event[2] == keys.backspace then
			break
		elseif event[1] == 'key' and event[2] == keys.pageUp then
			update_model { tab = 'resources' }
		elseif event[1] == 'key' and event[2] == keys.pageDown then
			update_model { tab = 'instructions' }
		elseif event[1] == 'key' and (event[2] == keys.space or event[2] == keys.enter) then
			if model.tab == 'resources' and model.resources_selection_index == 0 then
				update_model {
					resources_show_all = not model.resources_show_all,
					resources_list = generate_resources_list(not model.resources_show_all),
				}
			end
		elseif event[1] == 'key' and event[2] == keys.down then
			if model.tab == 'resources' and model.resources_selection_index < #model.resources_list then
				update_model {
					resources_selection_index = model.resources_list[model.resources_selection_index]
						and model.resources_list[model.resources_selection_index].type == 'category'
						and not model.resources_expanded_categories[model.resources_list[model.resources_selection_index].name]
						and model.resources_list[model.resources_selection_index].next
						or model.resources_selection_index + 1,
				}
			end
		elseif event[1] == 'key' and event[2] == keys.up then
			if model.tab == 'resources' and model.resources_selection_index > 0 then
				update_model {
					resources_selection_index = model.resources_list[model.resources_selection_index]
						and model.resources_list[model.resources_selection_index].type == 'category'
						and model.resources_list[model.resources_selection_index].previous > 0
						and not model.resources_expanded_categories[model.resources_list[model.resources_list[model.resources_selection_index].previous].name]
						and model.resources_list[model.resources_selection_index].previous
						or model.resources_selection_index - 1,
				}
			end
		elseif event[1] == 'key' and (event[2] == keys.left or event[2] == keys.right) then
			if model.tab == 'resources' and model.resources_selection_index > 0 then
				local expand = event[2] == keys.right
				local this_item = model.resources_list[model.resources_selection_index]
				local this_category = this_item.type == 'category' and this_item.name
				local expand_list = this_category and {} or model.resources_expanded_categories

				if this_category then
					for k, v in pairs(model.resources_expanded_categories) do
						expand_list[k] = v
					end
					expand_list[this_category] = expand or nil
					update_model { resources_expanded_categories = expand_list }
				end
			end
		elseif event[1] == 'term_resize' then
			update_model { width = term.getSize(), half_width = math.floor(term.getSize() / 2) }
		end
	end

	for i = 0, 15 do
		term.setPaletteColour(2 ^ i, table.unpack(palette[i + 1]))
	end

	return true
end

--------------------------------------------------------------------------------

local currentTime = os.clock

if ccemux then
	function currentTime()
		return ccemux.nanoTime() / 1000000000
	end
end

local event = args
local filter = nil
local program_co = coroutine.create(program_fn)
local is_capturing = false
local capture_ready = false
local last_frame = currentTime()
local fps_avg = 0
local frame_time_avg = 0
local avg_samples = 10

local function begin_frame()
	v3d_wrapper.begin_frame()
end

local function finish_frame()
	return v3d_wrapper.finish_frame()
end

local function begin_capture()
	v3d_wrapper.begin_capture()
	is_capturing = true
	capture_ready = false
end

local function finish_capture()
	is_capturing = false
	capture_ready = false

	local v3d_capture = v3d_wrapper.finish_capture()

	return { v3d_capture }
end

while true do
	if filter == nil or event[1] == filter then
		begin_frame()
		local start_time = currentTime()
		local ok, err = coroutine.resume(program_co, table.unpack(event))
		local this_frame = currentTime()
		local delta_time = this_frame - last_frame
		last_frame = this_frame

		if finish_frame() then
			capture_ready = is_capturing
			fps_avg = (fps_avg * avg_samples + 1 / delta_time) / (avg_samples + 1)
			frame_time_avg = (frame_time_avg * avg_samples + this_frame - start_time) / (avg_samples + 1)
		end

		if fps_enabled then
			term.setBackgroundColour(fps_bc)
			term.setTextColour(fps_fc)
			term.setCursorPos(1, 1)
			term.write(string.format('%.01ffps %.01fms <%.01ffps', fps_avg, frame_time_avg * 1000, 1 / frame_time_avg))
		end

		if capture_ready then
			local captures = finish_capture()
	
			for _, capture in ipairs(captures) do
				if not present_captures(capture) then
					return
				end
			end
		end

		if not ok then
			error(err, 0)
		elseif coroutine.status(program_co) == 'dead' then
			break
		else
			filter = err
		end
	end

	event = { coroutine.yield() }

	if event[1] == 'key' and event[2] == capture_key then
		begin_capture()
	elseif event[1] == 'terminate' then
		break
	end
end
