
local args = { ... }
local fps_bc = colours.black
local fps_fc = colours.white
local fps_enabled = false
local validation_enabled = true
local capture_key = keys.f12
local v3d_require_path = '/v3d'
local capture_first_frame = false

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
	elseif arg == '--capture-first-frame' or arg == '-c' then
		capture_first_frame = true
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

	local program_path = shell.resolveProgram(program)
	
	if not program_path then
		error('Failed to find program \'' .. program .. '\'', 0)
	end

	local program_file = io.open(program_path, 'r')
	local program_contents = ''

	if program_file then
		program_contents = program_file:read '*a'
		program_file:close()
	else
		error('Failed to read file \'' .. program_path .. '\'', 0)
	end

	local err
	program_fn, err = load(program_contents, 'v3dd@' .. v3dd_debug_marker .. ' ' .. program, nil, program_environment)

	if not program_fn then
		error('Failed to load program: ' .. err, 0)
	end
end

--------------------------------------------------------------------------------

--- @class Tree
--- @field content string | nil
--- @field content_right string | nil
--- @field content_expanded string | nil
--- @field content_right_expanded string | nil
--- @field default_expanded boolean | nil
--- @field children Tree[] | nil

--------------------------------------------------------------------------------

--- @alias V3DType 'v3d' | 'V3DFramebuffer' | 'V3DLayout' | 'V3DGeometryBuilder' | 'V3DGeometry' | 'V3DTransform' | 'V3DPipeline'

local V3D_VALIDATION_FAILED = 'V3D_VALIDATION_FAILED'

--- @class v3d_state
--- @field object_types { [any]: V3DType | nil }
--- @field object_labels { [any]: string | nil }
--- @field next_object_id integer
--- @field call_trees Tree[]
--- @field blit_called boolean
local v3d_state = {
	object_types = {},
	object_labels = {},
	next_object_id = 1,
	call_trees = {},
	blit_called = false,
}

local v3d_wrapper = {}
do -- generate the wrapper
	local v3d_lib
	do -- load the library
		local ok, lib = pcall(require, v3d_require_path)

		if ok then
			v3d_lib = lib
		else
			error('Failed to load v3d library at \'' .. v3d_require_path .. '\': ' .. lib .. '.\nUse --v3d-path to specify alternate path', 0)
		end
	end

	------------------------------------------------------------

	--- @diagnostic disable: unused-function, unused-local

	--- @param type V3DType
	--- @param label string
	local function register_object(obj, type, label)
		local suffix = type .. v3d_state.next_object_id
		v3d_state.next_object_id = v3d_state.next_object_id + 1
		label = label and '&pink;' .. label .. '&reset; @' .. suffix or '@' .. suffix
		v3d_state.object_labels[obj] = label
		v3d_state.object_types[obj] = type
	end

	local function fmtobject(v)
		if type(v) == 'number' then
			return '&orange;' .. v .. '&reset;'
		elseif type(v) == 'string' then
			return '&green;"' .. v .. '"&reset;'
		elseif v == true or v == false or v == nil then
			return '&purple;' .. tostring(v) .. '&reset;'
		elseif type(v) == 'table' then
			return v3d_state.object_labels[v] or ('&lightGrey;@' .. tostring(v):sub(8) .. '&reset;')
		else
			return tostring(v)
		end
	end

	------------------------------------------------------------

	local convert_instance_v3d
	local convert_instance_V3DFramebuffer
	local convert_instance_V3DLayout
	local convert_instance_V3DGeometryBuilder
	local convert_instance_V3DGeometry
	local convert_instance_V3DTransform
	local convert_instance_V3DPipeline

	--- @diagnostic enable: unused-function, unused-local

	-- #marker GENERATE_WRAPPER

	for k, v in pairs(v3d_lib) do
		v3d_wrapper[k] = v
	end

	convert_instance_v3d(v3d_wrapper, 'v3d')

	for _, layout_name in ipairs { 'DEFAULT_LAYOUT', 'UV_LAYOUT', 'DEBUG_CUBE_LAYOUT' } do
		local s = tostring {}
		-- take a copy of the layout in a really hacky way, then wrap it
		-- we don't wanna wrap_layout the original since that would mutate it
		local layout_copy = v3d_wrapper[layout_name]
			:add_face_attribute(s, 0):drop_attribute(s) -- we take a copy like this
		convert_instance_V3DLayout(layout_copy, layout_name)
		v3d_wrapper[layout_name] = layout_copy
	end
end

----------------------------------------------------------------

program_environment.package.loaded['/v3d'] = v3d_wrapper
program_environment.package.loaded['v3d'] = v3d_wrapper
program_environment.package.loaded[v3d_require_path] = v3d_wrapper

--------------------------------------------------------------------------------

--- @alias RichTextSegments { text: string, colour: integer }[]

--- @class TreeItem
--- @field tree Tree
--- @field expanded boolean
--- @field previous_peer integer | nil
--- @field next_expanded integer
--- @field next_contracted integer
--- @field last_child integer
--- @field indent integer
--- @field draw_y integer

--- @param items TreeItem[]
--- @param tree Tree
--- @param previous_peer integer | nil
--- @param indent integer
local function tree_to_items(items, tree, previous_peer, indent)
	local seq = {
		tree = tree,
		expanded = tree.default_expanded and tree.children and #tree.children > 0 or false,
		previous_peer = previous_peer,
		next_expanded = #items + 2,
		-- note: deliberately incomplete! we finish this at the end of the function
		indent = indent,
		draw_y = 0,
	}
	table.insert(items, seq)
	local previous_peer = nil
	if tree.children and #tree.children > 0 then
		for i = 1, #tree.children do
			local next_previous_peer = #items + 1
			tree_to_items(items, tree.children[i], previous_peer, indent + 1)
			previous_peer = next_previous_peer
		end
	end
	seq.next_contracted = #items + 1
	seq.last_child = previous_peer
end

--- @param content string
--- @param initial_colour integer
--- @return RichTextSegments
local function rich_content_to_segments(content, initial_colour)
	local segments = {}
	local active_color = initial_colour

	local next_index = 1
	local s, f = content:find '&[%w_]+;'

	while s do
		table.insert(segments, { text = content:sub(next_index, s - 1), colour = active_color })

		local name = content:sub(s + 1, f - 1)

		if name == 'reset' then
			active_color = initial_colour
		else
			if not colours[name] and not colors[name] then error('Unknown colour: ' .. name) end
			active_color = colours[name] or colors[name]
		end

		next_index = f + 1
		s, f = content:find('&[%w_]+;', next_index)
	end

	table.insert(segments, { text = content:sub(next_index), colour = active_color })

	return segments
end

--- @param segments RichTextSegments
--- @return integer
local function segments_length(segments)
	local length = 0

	for i = 1, #segments do
		length = length + #segments[i].text
	end

	return length
end

--- @param segments RichTextSegments
--- @param length integer
--- @return RichTextSegments
local function trim_segments_left(segments, length)
	return segments -- TODO
end

--- @param segments RichTextSegments
--- @param length integer
--- @return RichTextSegments
local function trim_segments_right(segments, length)
	local r = {}
	local r_length = 0

	for i = 1, #segments do
		r[i] = segments[i]
		r_length = r_length + #segments[i].text

		if r_length > length then
			break
		end
	end

	if r_length > length then
		r[#r].text = r[#r].text:sub(1, #r[#r].text - r_length + length)
	end

	return r
end

--- @param item TreeItem
--- @param y integer
--- @return integer next_y, integer next_index
local function redraw_tree_item(item, selected, x, y, w, by, bh)
	local initial_colour = colours.white
	local is_expanded = item.expanded
	local left = rich_content_to_segments(
		is_expanded and item.tree.content_expanded or item.tree.content or '',
		initial_colour)
	local right = rich_content_to_segments(
		is_expanded and item.tree.content_right_expanded or item.tree.content_right or '',
		initial_colour)
	local right_anchor = x + w
	local left_max_width = w

	if selected then
		term.setBackgroundColour(colours.black)
		term.setCursorPos(x, y)
		term.write((' '):rep(w))
	else
		term.setBackgroundColour(colours.grey)
	end

	x = x + item.indent * 2
	w = w - item.indent * 2

	if item.tree.children and #item.tree.children > 0 then
		table.insert(left, 1, { text = string.char(is_expanded and 31 or 16) .. ' ', colour = colours.lightGrey })
	-- elseif item.tree.on_select then -- TODO
	-- 	left_max_width = left_max_width - 2
	-- 	table.insert(left, 1, { text = '| ', colour = colours.lightGrey })
	-- 	table.insert(right, { text = ' >', colour = colours.purple })
	else
		table.insert(left, 1, { text = '\166 ', colour = colours.lightGrey })
	end

	item.draw_y = y

	if y >= by and y < by + bh then
		right = trim_segments_left(right, w)
		term.setCursorPos(right_anchor - segments_length(right), y)

		for _, segment in ipairs(right) do
			term.setTextColour(segment.colour)
			term.write(segment.text)
		end

		term.setCursorPos(x, y)
		left = trim_segments_right(left, left_max_width)

		for _, segment in ipairs(left) do
			term.setTextColour(segment.colour)
			term.write(segment.text)
		end
	end

	y = y + 1

	return y, item.expanded and item.next_expanded or item.next_contracted
end

--- @param trees Tree[]
local function present_capture(trees)
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

	local timers_captured = {}

	--- @class CaptureViewModel
	--- @field items TreeItem[]
	local model = {
		items = {},
		selected_item = 1,
		scroll = 0,
		items_start = 4,
	}

	local previous_peer = 0
	for i = 1, #trees do
		local next_previous_peer = #model.items + 1
		tree_to_items(model.items, trees[i], previous_peer, 0)
		previous_peer = next_previous_peer
	end

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

	local function redraw()
		local width, height = term.getSize()

		term.setBackgroundColour(colours.grey)
		term.clear()

		local y = model.items_start - model.scroll
		local index = 1

		while model.items[index] do
			y, index = redraw_tree_item(model.items[index], index == model.selected_item, 2, y, width - 2, 4, height - 4)
		end
	end

	while true do
		redraw()

		local event = { coroutine.yield() }

		if event[1] == 'terminate' then
			return false, timers_captured
		elseif event[1] == 'timer' then
			table.insert(timers_captured, event[2])
		elseif event[1] == 'key' and event[2] == keys.backspace then
			break
		elseif event[1] == 'key' and (event[2] == keys.space or event[2] == keys.enter) then
			if model.items[model.selected_item].tree.children and #model.items[model.selected_item].tree.children > 0 then
				model.items[model.selected_item].expanded = not model.items[model.selected_item].expanded
			-- elseif model.items[model.selected_item].tree.on_select then
			-- 	model.items[model.selected_item].tree.on_select()
			end
		elseif event[1] == 'key' and event[2] == keys.left then
			if model.items[model.selected_item].tree.children and #model.items[model.selected_item].tree.children > 0 then
				model.items[model.selected_item].expanded = false
			end
		elseif event[1] == 'key' and event[2] == keys.right then
			if model.items[model.selected_item].tree.children and #model.items[model.selected_item].tree.children > 0 then
				model.items[model.selected_item].expanded = true
			end
		elseif event[1] == 'key' and event[2] == keys.down then
			local current_item = model.items[model.selected_item]
			local next_index = current_item.expanded and current_item.next_expanded or current_item.next_contracted
			
			if model.items[next_index] then
				local height = select(2, term.getSize())
				local scroll = model.scroll
				if model.items[next_index].draw_y > height - 1 then
					scroll = scroll + model.items[next_index].draw_y - height + 1
				end
				update_model { selected_item = next_index, scroll = scroll }
			end
		elseif event[1] == 'key' and event[2] == keys.up then
			local next_index = model.items[model.selected_item].previous_peer
			
			if next_index and model.items[next_index] then
				while model.items[next_index].expanded do
					next_index = model.items[next_index].last_child
				end
			elseif model.items[model.selected_item - 1] then
				next_index = model.selected_item - 1
			end

			if model.items[next_index] then
				local scroll = model.scroll
				if model.items[next_index].draw_y < model.items_start then
					scroll = scroll + model.items[next_index].draw_y - model.items_start
				end
				update_model { selected_item = next_index, scroll = scroll }
			end
		elseif event[1] == 'key' and (event[2] == keys.left or event[2] == keys.right) then
			
		elseif event[1] == 'term_resize' then
			
		end
	end

	for i = 0, 15 do
		term.setPaletteColour(2 ^ i, table.unpack(palette[i + 1]))
	end

	return true, timers_captured
end

--------------------------------------------------------------------------------

local currentTime = os.clock

if ccemux then
	function currentTime()
		return ccemux.nanoTime() / 1000000000
	end
end

local event_queue = {}
local event = args
local filter = nil
local program_co = coroutine.create(program_fn)
local last_frame = currentTime()
local fps_avg = 0
local frame_time_avg = 0
local avg_samples = 10
local last_capture_trees = nil

while true do
	if filter == nil or event[1] == filter then
		local start_time = currentTime()
		local ok, err = coroutine.resume(program_co, table.unpack(event))
		local this_frame = currentTime()
		local delta_time = this_frame - last_frame

		last_frame = this_frame
		last_capture_trees = v3d_state.call_trees

		if v3d_state.blit_called then
			v3d_state.blit_called = false
			v3d_state.call_trees = {}
			fps_avg = (fps_avg * avg_samples + 1 / delta_time) / (avg_samples + 1)
			frame_time_avg = (frame_time_avg * avg_samples + this_frame - start_time) / (avg_samples + 1)
		end

		if fps_enabled then
			term.setBackgroundColour(fps_bc)
			term.setTextColour(fps_fc)
			term.setCursorPos(1, 1)
			term.write(string.format('%.01ffps %.01fms <%.01ffps', fps_avg, frame_time_avg * 1000, 1 / frame_time_avg))
		end

		if not ok then
			present_capture {
				{ content = 'Capture', children = last_capture_trees, default_expanded = false, },
				{ content = 'Error', children = {
					{ content = tostring(err) }
				}, default_expanded = true, }
			}
			return
		elseif coroutine.status(program_co) == 'dead' then
			if capture_first_frame then
				present_capture {
					{ content = 'Capture', children = last_capture_trees, default_expanded = true, },
				}
			end
			break
		else
			filter = err
		end
	end

	event = table.remove(event_queue, 1) or { coroutine.yield() }

	if (event[1] == 'key' and event[2] == capture_key) or capture_first_frame then
		local cont, timers = present_capture {
			{ content = 'Capture', children = last_capture_trees, default_expanded = true, },
		}
		if not cont then
			break
		end
		for i = 1, #timers do
			table.insert(event_queue, { 'timer', timers[i] })
		end
		capture_first_frame = false
	elseif event[1] == 'terminate' then
		break
	end
end
