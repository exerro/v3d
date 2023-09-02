
local args = { ... }

local program_name
local program_args = {}
local headless = false
local capture_frame = nil
local capture_current_key = keys.f11
local capture_next_frame_key = keys.f12
do -- parse CLI args
	while args[1] do
		if args[1] == '--capture-frame' or args[1] == '--frame' or args[1] == '-f' then
			table.remove(args, 1)
			if args[1] and tonumber(args[1]) then
				capture_frame = tonumber(args[1])
				table.remove(args, 1)
			else
				capture_frame = 0
			end
		elseif args[1] == '--capture-current-key' then
			local flag = table.remove(args, 1)
			if not args[1] then error('Expected key name after ' .. flag, 0) end
			local key_name = table.remove(args, 1)
			if not keys[key_name] then error('Invalid key name \'' .. key_name .. '\'', 0) end
			capture_current_key = keys[key_name]
		elseif args[1] == '--capture-next-frame-key' or args[1] == '-k' then
			local flag = table.remove(args, 1)
			if not args[1] then error('Expected key name after ' .. flag, 0) end
			local key_name = table.remove(args, 1)
			if not keys[key_name] then error('Invalid key name \'' .. key_name .. '\'', 0) end
			capture_next_frame_key = keys[key_name]
		elseif args[1] == '--headless' then
			headless = true
			table.remove(args, 1)
		else
			program_name = args[1]
			table.remove(args, 1)
			program_args = args
			break
		end
	end

	if not program_name then
		error('Program name not specified', 0)
	end
end

-- here's a load of mutable state with functions to wrap (some of) it up:

--- @alias V3DDebugNormalCall { fn_name: string, parameters: any[], result: any | nil }
--- @alias V3DDebugCall V3DDebugNormalCall
---                   | { debug_region: true, name: string | nil, calls: V3DDebugCall[] }

--- @class V3DValidationErrorContext
--- @field errors { attribute: string | nil, value: any, message: string }[]
--- @field fn_name string
--- @field parameters { name: string, value: any }[]

--- @type { context: V3DValidationErrorContext }
local V3D_VALIDATION_ERROR = setmetatable({ context = nil }, { __tostring = function() return 'V3D_VALIDATION_ERROR' end })

-- Keep track of all v3d calls made this frame.
--- @type V3DDebugCall[]
local v3d_this_frame_calls = {}
-- Keep track of a stack of call tables. When a debug region is entered, it will
-- push a new call table onto the stack after inserting a nested call into the
-- previous top table.
--- @type V3DDebugCall[][]
local v3d_this_frame_call_stack = {}

local enter_capture_view -- function defined later
local end_frame -- functions defined later
local get_frame_number, get_frame_duration, get_effective_fps -- functions defined later
local set_normal_error, set_validation_error -- functions defined later
local get_normal_error, get_validation_error, get_stacktrace -- functions defined later
local forcibly_stop_running, should_continue_running -- functions defined later
local program_event_queue = { program_args }
do -- state stuff
	local FPS_SAMPLES = 4

	local frame_number = 0
	local frame_start_time = os.clock()
	local frame_duration = 0
	local effective_fps = 0
	local program_has_validation_error = false
	local program_error_message = nil
	local program_error_stacktrace = nil
	local is_running = true

	function end_frame()
		local actual_samples = math.min(FPS_SAMPLES, frame_number)

		frame_number = frame_number + 1
		frame_duration = os.clock() - frame_start_time
		effective_fps = (actual_samples * effective_fps + 1 / frame_duration) / (actual_samples + 1)

		if capture_frame then
			if capture_frame == 0 then
				if not enter_capture_view() then
					forcibly_stop_running()
				end
				capture_frame = nil
			else
				capture_frame = capture_frame - 1
			end
		end

		v3d_this_frame_call_stack = {}
		v3d_this_frame_calls = {}
		frame_start_time = os.clock()
	end

	function get_frame_number()
		return frame_number
	end

	function get_frame_duration()
		return frame_duration
	end

	function get_effective_fps()
		return effective_fps
	end

	function set_normal_error(message, traceback)
		program_has_validation_error = false
		program_error_message = message
		program_error_stacktrace = traceback
	end

	function set_validation_error(traceback)
		program_has_validation_error = true
		program_error_message = nil
		program_error_stacktrace = traceback
	end

	--- @return string | nil
	function get_normal_error()
		return program_error_message
	end

	--- @return V3DValidationErrorContext | nil
	function get_validation_error()
		return program_has_validation_error and V3D_VALIDATION_ERROR.context or nil
	end

	function get_stacktrace()
		return program_error_stacktrace
	end

	function forcibly_stop_running()
		is_running = false
	end

	function should_continue_running()
		return is_running
	end
end

local program_path
local program_environment
local program_coroutine
do -- load the program
	program_path = shell.resolveProgram(program_name)
	if not program_path then
		error('Program not found \'' .. program_name .. '\'', 0)
	end

	local h = io.open(program_path)
	if not h then
		error('Could not read program \'' .. program_path .. '\'', 0)
	end
	local program_content = h:read '*a'
	h:close()

	program_environment = {}
	local copy_env = _ENV
	while copy_env do
		for k, v in pairs(copy_env) do
			program_environment[k] = v
		end
		copy_env = getmetatable(copy_env) and getmetatable(copy_env).__index
	end

	local program_fn, err = load(program_content, '=' .. program_name, nil, program_environment)
	if not program_fn then
		error('Could not load program \'' .. program_path .. '\': ' .. err, 0)
	end

	program_coroutine = coroutine.create(function()
		local ok, err = xpcall(program_fn, function(message, level)
			local lines = {}
			local traceback = debug.traceback('', (level or 1) + 1)

			for line in traceback:gmatch '[^\n]+' do
				table.insert(lines, (line:gsub('^%s*', '')))
			end

			for i = #lines, 1, -1 do
				if lines[i]:find '^%s*%[C%]: in function \'xpcall\'' then
					table.remove(lines, i)
					break
				else
					table.remove(lines, i)
				end
			end

			table.remove(lines, 1) -- stack traceback:

			if lines[1] == '[C]: in function \'error\'' then
				table.remove(lines, 1)
			end

			if type(message) == 'string' and message:find '^%[[^%]]*%]:%d+:' then
				message = message:match '^%[[^%]]+%]:%d+:%s*(.*)$'
			elseif type(message) == 'string' and message:find '^[^:]*:%d+:' then
				message = message:match '^[^:]+:%d+:%s*(.*)$'
			end

			if message == V3D_VALIDATION_ERROR then
				set_validation_error(lines)
			else
				set_normal_error(tostring(message), lines)
			end

			return ''
		end)
		if not ok then
			error(err, 0)
		end
	end)
end

--- @type V3D
local v3d
local v3d_modified_library
do -- load v3d
	local this_dir = shell
				 and shell.getRunningProgram()
				         :gsub('/v3debug%.lua$', '')
				         :gsub('^v3debug%.lua$', '')
				         :gsub('/v3debug$', '')
				         :gsub('^v3debug$', '')
				  or './'

	local v3d_try_paths = {
		this_dir .. 'artifacts/v3d.lua',
		this_dir .. 'v3d.lua',
		this_dir .. 'v3d',
		'/v3d/artifacts/v3d.lua',
		'/v3d.lua',
	}

	for _, v3d_path in ipairs(v3d_try_paths) do
		local h = io.open(v3d_path)
		if h then
			h:close()
			v3d = dofile(v3d_path)
			v3d_modified_library = dofile(v3d_path)
			break
		end
	end

	if not v3d or not v3d_modified_library then
		error('v3d library not found', 0)
	end
end

do -- provide a modified 'module' and 'require' to the program
	local require, module = require '/rom.modules.main.cc.require'
		.make(program_environment, program_path:gsub('[^/]+$', ''))

	program_environment.require = require
	program_environment.module = module

	module.loaded['v3d'] = v3d_modified_library
end

local COLOUR_BACKGROUND = colours.black
local COLOUR_BACKGROUND_SEL = colours.grey
local COLOUR_BACKGROUND_ALT = colours.grey
local COLOUR_BACKGROUND_HL = colours.purple
local COLOUR_FOREGROUND = colours.white
local COLOUR_FOREGROUND_ALT = colours.lightGrey
local COLOUR_FOREGROUND_HL = colours.white
local COLOUR_FOREGROUND_DIM = colours.grey
local COLOUR_V3D_TYPE = colours.lightBlue
local COLOUR_KEYWORD = colours.purple
local COLOUR_REGION = colours.green
local COLOUR_VARIABLE = colours.pink
local COLOUR_FUNCTION = colours.cyan
local COLOUR_CONSTANT = colours.orange
local COLOUR_CONSTANT_STRING = colours.orange
local PAGES = { 'Overview', 'Capture', 'Objects' }

local new_rich_line, line_inner_expanded_height, map_items_to_lines, insert_to_lines, last_nested_child, any_next_peer, draw_lines
do -- define operations on rich text lines
	--- @alias RichTextSegment { text: string, colour: number | nil }

	--- @class RichTextLine
	--- @field left_text_segments_contracted RichTextSegment[]
	--- @field left_text_segments_expanded RichTextSegment[]
	--- @field right_text_segments RichTextSegment[]
	--- @field indentation integer
	--- @field is_expanded boolean
	--- @field previous_peer RichTextLine | nil
	--- @field next_peer RichTextLine | nil
	--- @field parent RichTextLine | nil
	--- @field first_child RichTextLine | nil
	--- @field last_child RichTextLine | nil

	--- @return RichTextLine
	function new_rich_line(t)
		t.left_text_segments_contracted = t.left_text_segments_contracted or t.left_text_segments_expanded or {}
		t.left_text_segments_expanded = t.left_text_segments_expanded or t.left_text_segments_contracted
		t.right_text_segments = t.right_text_segments or {}
		t.indentation = t.indentation or 0
		t.is_expanded = t.is_expanded or false
		t.previous_peer = t.previous_peer or nil
		t.next_peer = t.next_peer or nil
		t.parent = t.parent or nil
		t.first_child = t.first_child or nil
		t.last_child = t.last_child or nil
		return t
	end

	--- Return the total number of expanded lines within a line
	--- @param line RichTextLine
	function line_inner_expanded_height(line)
		if not line.is_expanded then
			return 0
		end

		local total = 0
		local child = line.first_child

		while child do
			total = total + line_inner_expanded_height(child) + 1
			child = child.next_peer
		end

		return total
	end

	--- @param parent RichTextLine | nil
	--- @param items any[]
	--- @param map fun(item: any, index: integer): RichTextLine
	function map_items_to_lines(parent, items, map)
		local previous_peer = parent and parent.first_child
		local first_item = nil

		while previous_peer and previous_peer.next_peer do
			previous_peer = previous_peer.next_peer
		end

		for i = 1, #items do
			local item_mapped = map(items[i], i)

			if previous_peer then
				previous_peer.next_peer = item_mapped
				item_mapped.previous_peer = previous_peer
			elseif parent then
				parent.first_child = item_mapped
				item_mapped.previous_peer = nil
			end

			if parent then
				parent.last_child = item_mapped
			end

			item_mapped.parent = parent
			previous_peer = item_mapped

			if not first_item then
				first_item = item_mapped
			end
		end

		return first_item
	end

	--- @param parent RichTextLine
	--- @param line RichTextLine
	--- @return RichTextLine
	function insert_to_lines(parent, line)
		if parent.last_child then
			parent.last_child.next_peer = line
			line.previous_peer = parent.last_child
		end

		parent.first_child = parent.first_child or line
		parent.last_child = line
		line.parent = parent

		return line
	end

	--- @param line RichTextLine
	--- @param x integer
	--- @param y integer
	--- @param width integer
	local function draw_segments(line, x, y, width)
		local lx = x + line.indentation * 2 + 1
		local left_segments = line.is_expanded and line.left_text_segments_expanded or line.left_text_segments_contracted
		local parent_line = line.parent
		local is_terminal_line_in_parent = line.parent and line == line.parent.last_child and not line.is_expanded

		while parent_line do
			term.setCursorPos(x + parent_line.indentation * 2 + 1, y + 1)

			if is_terminal_line_in_parent then
				term.setTextColour(term.getBackgroundColour())
				term.setBackgroundColour(COLOUR_FOREGROUND_DIM)
				term.write('\138')
				term.setBackgroundColour(term.getTextColour())
			else
				term.setTextColour(COLOUR_FOREGROUND_DIM)
				term.write('\149')
			end

			is_terminal_line_in_parent = is_terminal_line_in_parent and parent_line.parent and parent_line == parent_line.parent.last_child
			parent_line = parent_line.parent
		end

		if line.first_child then
			term.setCursorPos(lx, y + 1)
			term.setTextColour(COLOUR_FOREGROUND_ALT)
			term.write(line.is_expanded and '\31' or '\16')
		end

		for i = 1, #left_segments do
			local segment = left_segments[i]
			term.setTextColour(segment.colour)
			term.setCursorPos(lx + 2, y + 1)
			term.write(segment.text)
			lx = lx + #segment.text
		end
	end

	function last_nested_child(line)
		while line.last_child and line.is_expanded do
			line = line.last_child
		end
		return line
	end
	
	function any_next_peer(line)
		while line do
			if line.next_peer then
				return line.next_peer
			end
			line = line.parent
		end
		return nil
	end

	--- @param line RichTextLine
	--- @param x integer
	--- @param y integer
	--- @param width integer
	--- @param min_y integer
	--- @param max_y integer
	function draw_lines(line, x, y, width, min_y, max_y)
		term.setBackgroundColour(COLOUR_BACKGROUND_SEL)

		local forward_line = line
		local forward_y = y
		while forward_line and forward_y <= max_y do
			draw_segments(forward_line, x, forward_y, width)
			term.setBackgroundColour(COLOUR_BACKGROUND)
			forward_y = forward_y + 1

			forward_line = forward_line.is_expanded and forward_line.first_child
			            or any_next_peer(forward_line)
		end

		local backward_line = line
		local backward_y = y - 1
		while true do
			backward_line = backward_line.previous_peer and last_nested_child(backward_line.previous_peer)
			             or backward_line.parent

			if backward_line and backward_y >= min_y then
				draw_segments(backward_line, x, backward_y, width)
				backward_y = backward_y - 1
			else
				break
			end
		end
	end
end

local map_call_to_lines
do -- TODO
	local show
	local v3d_show_types = {}
	local v3d_function_parameter_names = {}
	local v3d_struct_field_orderings = {}

	-- #gen-show-types
	-- #gen-function-parameter-names
	-- #gen-struct-field-orderings

	--- @param item V3DFormat
	--- @param line RichTextLine
	function v3d_show_types.V3DFormat(item, line)
		--- @cast item V3DFormat
		if item.kind == 'struct' then
			table.insert(line.left_text_segments_expanded, {
				text = 'struct',
				colour = COLOUR_KEYWORD,
			})
			map_items_to_lines(line, item.fields, function(field)
				local l = new_rich_line {
					left_text_segments_expanded = {
						{ text = field.name, colour = COLOUR_VARIABLE },
						{ text = ' = ', colour = COLOUR_FOREGROUND_ALT },
					},
					indentation = line.indentation + 1,
				}
				v3d_show_types.V3DFormat(field.format, l)
				return l
			end)
		elseif item.kind == 'tuple' then
			table.insert(line.left_text_segments_expanded, {
				text = 'tuple',
				colour = COLOUR_KEYWORD,
			})
			map_items_to_lines(line, item.fields, function(field, i)
				local l = new_rich_line {
					left_text_segments_expanded = {
						{ text = '.', colour = COLOUR_FOREGROUND_ALT },
						{ text = tostring(i), colour = COLOUR_VARIABLE },
						{ text = ' = ', colour = COLOUR_FOREGROUND_ALT },
					},
					indentation = line.indentation + 1,
				}
				v3d_show_types.V3DFormat(field, l)
				return l
			end)
		else
			table.insert(line.left_text_segments_expanded, {
				text = v3d.format_tostring(item),
				colour = COLOUR_FUNCTION,
			})
		end
	end

	--- @param item any
	--- @return RichTextSegment[]
	local function show_short_segments(item)
		if type(item) == 'table' then
			if item.__v3d_typename then
				if item.__v3d_label then
					return {
						{ text = item.__v3d_typename, colour = COLOUR_V3D_TYPE },
						{ text = ' \'' .. item.__v3d_label .. '\'', colour = COLOUR_FOREGROUND },
					}
				else
					return {
						{ text = item.__v3d_typename, colour = COLOUR_V3D_TYPE },
					}
				end
			else
				return {
					{ text = '{...}', colour = COLOUR_FOREGROUND_ALT },
				}
			end
		elseif type(item) == 'function' then
			return {
				{ text = 'function', colour = COLOUR_KEYWORD },
			}
		elseif type(item) == 'string' then
			return {
				{ text = '"' .. item:gsub('[\\"]', '\\%1') .. '"', colour = COLOUR_CONSTANT_STRING },
			}
		else
			return {
				{ text = tostring(item), colour = COLOUR_CONSTANT },
			}
		end
	end

	--- @param item any
	--- @param line RichTextLine
	function show(item, line)
		if type(item) == 'table' and item.__v3d_typename then
			if v3d_show_types[item.__v3d_typename] then
				v3d_show_types[item.__v3d_typename](item, line)
				return
			end
		end

		for _, segment in ipairs(show_short_segments(item)) do
			table.insert(line.left_text_segments_expanded, segment)
		end

		if type(item) == 'table' then
			local seen = {}
			local map_elements = {}
			local list_elements = {}

			for i = 1, #item do
				seen[i] = true
				table.insert(list_elements, { i, item[i] })
			end

			for k, v in pairs(item) do
				if not seen[k] then
					table.insert(map_elements, { k, v })
				end
			end

			table.sort(map_elements, function(a, b)
				local o1 = v3d_struct_field_orderings[a[1]]
				local o2 = v3d_struct_field_orderings[b[1]]
				if not o1 or not o2 or o1 == o2 then
					return tostring(a[1]) < tostring(b[1])
				end
				return o1 < o2
			end)

			map_items_to_lines(line, map_elements, function(element)
				local l = new_rich_line {
					left_text_segments_expanded = {},
					indentation = line.indentation + 1,
				}

				if type(element[1]) == 'string' then
					if element[1]:find '[^%w_]' then
						table.insert(l.left_text_segments_expanded, { text = '[', colour = COLOUR_FOREGROUND_ALT })
						table.insert(l.left_text_segments_expanded, { text = '"' .. element[1]:gsub('["\\]', '\\%1') .. '"', colour = COLOUR_CONSTANT_STRING })
						table.insert(l.left_text_segments_expanded, { text = ']', colour = COLOUR_FOREGROUND_ALT })
					else
						table.insert(l.left_text_segments_expanded, { text = element[1], colour = COLOUR_VARIABLE })
					end
				elseif type(element[1]) == 'table' or type(element[1]) == 'function' then
					table.insert(l.left_text_segments_expanded, { text = '[', colour = COLOUR_FOREGROUND_ALT })
					table.insert(l.left_text_segments_expanded, { text = tostring(element[1]), colour = COLOUR_FOREGROUND })
					table.insert(l.left_text_segments_expanded, { text = ']', colour = COLOUR_FOREGROUND_ALT })
				else
					table.insert(l.left_text_segments_expanded, { text = '[', colour = COLOUR_FOREGROUND_ALT })
					table.insert(l.left_text_segments_expanded, { text = tostring(element[1]), colour = COLOUR_CONSTANT })
					table.insert(l.left_text_segments_expanded, { text = ']', colour = COLOUR_FOREGROUND_ALT })
				end

				table.insert(l.left_text_segments_expanded, { text = ' = ', colour = COLOUR_FOREGROUND_ALT })
				show(element[2], l)

				return l
			end)
		end
	end

	--- @param indentation integer
	--- @return fun(call: V3DDebugCall): RichTextLine
	function map_call_to_lines(indentation)
		--- @param call V3DDebugCall
		return function(call)
			local result = new_rich_line {
				left_text_segments_contracted = {},
				left_text_segments_expanded = {},
				right_text_segments = {},
				indentation = indentation,
			}

			if call.debug_region then
				table.insert(result.left_text_segments_contracted, { text = 'Debug region', colour = COLOUR_REGION })
				table.insert(result.left_text_segments_expanded, { text = 'Debug region', colour = COLOUR_REGION })
				if call.name then
					table.insert(result.left_text_segments_contracted, { text = ' \'' .. call.name .. '\'', colour = COLOUR_FOREGROUND })
					table.insert(result.left_text_segments_expanded, { text = ' \'' .. call.name .. '\'', colour = COLOUR_FOREGROUND })
				end
				table.insert(result.left_text_segments_contracted, { text = ' (' .. tostring(#call.calls) .. ')', colour = COLOUR_FOREGROUND_ALT })
				table.insert(result.left_text_segments_expanded, { text = ' (' .. tostring(#call.calls) .. ')', colour = COLOUR_FOREGROUND_ALT })
				map_items_to_lines(result, call.calls, map_call_to_lines(indentation + 1))
			else
				table.insert(result.left_text_segments_contracted, { text = tostring(call.fn_name), colour = COLOUR_FUNCTION })
				table.insert(result.left_text_segments_expanded, { text = tostring(call.fn_name), colour = COLOUR_FUNCTION })
				table.insert(result.left_text_segments_expanded, { text = '(...)', colour = COLOUR_FOREGROUND_ALT })
				table.insert(result.left_text_segments_contracted, { text = '(', colour = COLOUR_FOREGROUND_ALT })

				for i = 1, #call.parameters do
					for _, segment in ipairs(show_short_segments(call.parameters[i])) do
						if i > 1 then
							table.insert(result.left_text_segments_contracted, { text = ', ', colour = COLOUR_FOREGROUND_ALT })
						end
						table.insert(result.left_text_segments_contracted, segment)
					end
				end

				table.insert(result.left_text_segments_contracted, { text = ')', colour = COLOUR_FOREGROUND_ALT })

				map_items_to_lines(result, call.parameters, function(parameter, parameter_index)
					local p = new_rich_line {
						left_text_segments_contracted = {
							{ text = v3d_function_parameter_names[call.fn_name][parameter_index], colour = COLOUR_VARIABLE },
							{ text = ' = ', colour = COLOUR_FOREGROUND_ALT },
						},
						right_text_segments = {},
						indentation = indentation + 1,
					}

					show(parameter, p)

					return p
				end)

				map_items_to_lines(result, { call.result }, function(result)
					local r = new_rich_line {
						left_text_segments_contracted = {
							{ text = 'return ', colour = COLOUR_KEYWORD },
						},
						right_text_segments = {},
						indentation = indentation + 1,
					}

					show(result, r)

					return r
				end)
			end

			return result
		end
	end
end

--- @return boolean continue_running
function enter_capture_view()
	if headless then
		local messages = {}

		if get_normal_error() then
			table.insert(messages, get_normal_error())
		elseif get_validation_error() then
			table.insert(messages, 'Validation error in ' .. V3D_VALIDATION_ERROR.context.fn_name .. ':')

			for _, e in ipairs(V3D_VALIDATION_ERROR.context.errors) do
				if e.attribute then
					table.insert(messages, ' \007 ' .. e.attribute .. ' (' .. tostring(e.value) .. '): ' .. e.message)
				else
					table.insert(messages, ' \007 ' .. e.message)
				end
			end
		else
			return true
		end

		table.insert(messages, '')
		table.insert(messages, 'Stack trace:')

		for _, st in ipairs(get_stacktrace()) do
			table.insert(messages, st)
		end

		error(table.concat(messages, '\n'), 0)
	end

	local state = {
		--- @type 'Overview' | 'Capture'
		page = 'Overview',

		frame_number = get_frame_number(),
		frame_duration = get_frame_duration(),
		effective_fps = get_effective_fps(),
		error_message = get_normal_error() or (get_validation_error() and 'A validation error occurred'),
		validation_error = get_validation_error(),
		error_traceback = get_stacktrace(),

		calls_min_y = 3,
		calls_max_y = select(2, term.getSize()) - 2,
		capture_line = map_items_to_lines(nil, v3d_this_frame_calls, map_call_to_lines(0)) or {
			left_text_segments_contracted = { { text = 'No calls captured', colour = colours.yellow } },
			right_text_segments = {},
			indentation = 0,
			is_expanded = false,
			previous_peer = nil,
			next_peer = nil,
			parent = nil,
			first_child = nil,
			last_child = nil,
		},
		capture_line_y = 3,
	}

	local restore_graphics
	do -- update graphics settings
		local graphics_mode = term.getGraphicsMode and term.getGraphicsMode()
		local old_palette = {}

		for i = 0, 15 do
			old_palette[i + 1] = { term.getPaletteColour(2 ^ i) }
		end
	
		if graphics_mode then
			term.setGraphicsMode(false)
		end
	
		term.setPaletteColour(colours.purple, 0x582d8c)

		function restore_graphics()
			for i = 0, 15 do
				term.setPaletteColour(2 ^ i, table.unpack(old_palette[i + 1]))
			end

			if graphics_mode then
				term.setGraphicsMode(graphics_mode)
			end
		end
	end

	local function draw()
		term.setBackgroundColour(COLOUR_BACKGROUND)
		term.setTextColour(COLOUR_FOREGROUND)
		term.clear()

		do -- draw the page tabs
			local term_width = select(1, term.getSize())
			local tab_width = math.floor(term_width / #PAGES)
			local tab_start_x = 1
			term.setBackgroundColour(COLOUR_BACKGROUND_ALT)

			for i, page_title in ipairs(PAGES) do
				local this_tab_width = i == #PAGES and (term_width - tab_start_x + 1) or tab_width

				if page_title == state.page then
					term.setBackgroundColour(COLOUR_BACKGROUND)
					term.setTextColour(COLOUR_BACKGROUND_HL)
					term.setCursorPos(tab_start_x + 1, 2)
					term.write(('\140'):rep(#page_title))

					term.setBackgroundColour(COLOUR_BACKGROUND_HL)
					term.setTextColour(COLOUR_FOREGROUND_HL)
				else
					term.setBackgroundColour(COLOUR_BACKGROUND_ALT)
					term.setTextColour(COLOUR_FOREGROUND)
				end

				term.setCursorPos(tab_start_x, 1)
				term.write(' ' .. page_title:sub(1, this_tab_width - 1) .. (' '):rep(math.max(0, this_tab_width - #page_title - 1)))
				tab_start_x = tab_start_x + this_tab_width
			end
			
			term.setBackgroundColour(COLOUR_BACKGROUND)
			term.setTextColour(COLOUR_FOREGROUND)
		end

		if state.page == 'Overview' then
			local y = 4
			term.setCursorPos(2, y)
			y = y + print('Frame ' .. state.frame_number)
			term.setCursorPos(2, y)
			y = y + print(('Frame duration: %.1fms'):format(state.frame_duration * 1000))
			term.setCursorPos(2, y)
			y = y + print(('Effective FPS: %.1f'):format(state.effective_fps))
			y = y + 1

			if get_validation_error() then
				term.setTextColour(colours.red)
				term.setCursorPos(2, y)
				y = y + print('Validation error in ' .. V3D_VALIDATION_ERROR.context.fn_name .. ':')
				term.setTextColour(COLOUR_FOREGROUND_ALT)
				for _, e in ipairs(V3D_VALIDATION_ERROR.context.errors) do
					term.setCursorPos(2, y)
					if e.attribute then
						y = y + print(' \007 ' .. e.attribute .. ' (' .. tostring(e.value) .. '): ' .. e.message)
					else
						y = y + print(' \007 ' .. e.message)
					end
				end
				y = y + 1
			elseif get_normal_error() then
				term.setTextColour(colours.red)
				term.setCursorPos(2, y)
				y = y + print('Program crashed')
				term.setTextColour(COLOUR_FOREGROUND)
				term.setCursorPos(2, y)
				y = y + print(get_normal_error())
				y = y + 1
			end

			if get_stacktrace() and #get_stacktrace() > 0 then
				local st = get_stacktrace()
				term.setTextColour(COLOUR_FOREGROUND)
				term.setCursorPos(2, y)
				y = y + print('Stack trace')
				term.setTextColour(COLOUR_FOREGROUND_ALT)

				for i = 1, #st do
					term.setCursorPos(2, y)
					y = y + print(' \007 ' .. st[i])
				end
			end

		elseif state.page == 'Capture' then
			-- highlight the selected line
			term.setBackgroundColour(COLOUR_BACKGROUND_ALT)
			term.setCursorPos(2, state.capture_line_y + 1)
			term.write((' '):rep(select(1, term.getSize()) - 2))
			term.setBackgroundColour(COLOUR_BACKGROUND)

			draw_lines(state.capture_line, 1, state.capture_line_y, select(1, term.getSize()), state.calls_min_y, state.calls_max_y)
		end
	end

	local is_ctrl_held = false

	while true do
		draw()
		local event = { coroutine.yield() }

		if event[1] == 'terminate' then
			restore_graphics()
			return false
		elseif event[1] == 'key' then
			if event[2] == keys.backspace then -- exit capture view
				restore_graphics()
				return true
			elseif event[2] == keys.up or event[2] == keys.w then -- up to previous line or previous peer
				if state.capture_line.previous_peer then
					if is_ctrl_held then
						state.capture_line = state.capture_line.previous_peer
					else
						state.capture_line = last_nested_child(state.capture_line.previous_peer)
					end

					state.capture_line_y = math.max(
						state.capture_line_y - 1 - line_inner_expanded_height(state.capture_line),
						state.calls_min_y
					)
				elseif state.capture_line.parent then
					state.capture_line = state.capture_line.parent
					state.capture_line_y = math.max(
						state.capture_line_y - 1,
						state.calls_min_y
					)
				end
			elseif event[2] == keys.down or event[2] == keys.s then -- down to next line or next peer
				if not is_ctrl_held and state.capture_line.first_child and state.capture_line.is_expanded then
					state.capture_line_y = math.min(
						state.capture_line_y + 1,
						state.calls_max_y
					)
					state.capture_line = state.capture_line.first_child
				else
					local next_peer = any_next_peer(state.capture_line)
					if next_peer then
						state.capture_line_y = math.min(
							state.capture_line_y + 1 + line_inner_expanded_height(state.capture_line),
							state.calls_max_y
						)
						state.capture_line = next_peer
					end
				end
			elseif event[2] == keys.e or event[2] == keys.tab then -- toggle line expanded
				state.capture_line.is_expanded = not state.capture_line.is_expanded
			elseif event[2] == keys.leftCtrl or event[2] == keys.rightCtrl then -- register whether ctrl is held
				is_ctrl_held = true
			elseif is_ctrl_held and event[2] == keys.pageUp then -- switch to previous page
				state.page = 'Overview'
			elseif is_ctrl_held and event[2] == keys.pageDown then -- switch to next page
				state.page = 'Capture'
			end
		elseif event[1] == 'key_up' then
			if event[2] == keys.leftCtrl or event[2] == keys.rightCtrl then
				is_ctrl_held = false
			end
		elseif event[1] == 'term_resize' then
			state.calls_max_y = select(2, term.getSize()) - 2
		end
	end
end

do -- create modified library
	-- #gen-type-validators
	-- #gen-function-wrappers

	function v3d_modified_library.enter_debug_region(name)
		local call = {
			debug_region = true,
			name = name ~= nil and tostring(name) or nil,
			calls = {},
		}
		table.insert(v3d_this_frame_calls, call)
		table.insert(v3d_this_frame_call_stack, v3d_this_frame_calls)
		v3d_this_frame_calls = call.calls
	end

	function v3d_modified_library.exit_debug_region()
		v3d_this_frame_calls = table.remove(v3d_this_frame_call_stack)
	end

	local image_view_present_term_subpixel = v3d_modified_library.image_view_present_term_subpixel
	local image_view_present_graphics = v3d_modified_library.image_view_present_graphics

	function v3d_modified_library.image_view_present_term_subpixel(...)
		image_view_present_term_subpixel(...)
		end_frame()
	end

	function v3d_modified_library.image_view_present_graphics(...)
		image_view_present_graphics(...)
		end_frame()
	end

	-- #gen-method-wrappers
	-- #gen-metamethod-wrappers
	-- #gen-generated-function-wrappers
end

-- keep a copy of the palette so we can restore it later
local palette = {}
for i = 0, 15 do
	palette[i + 1] = { term.getPaletteColour(2 ^ i) }
end

local event_filter = nil
while true do
	while true do
		if not should_continue_running() then
			program_event_queue = {} -- signal below to break the outer loop
			break
	
		-- if we don't have a queued event, pull one
		elseif not program_event_queue[1] then
			program_event_queue[1] = { coroutine.yield() }

		elseif program_event_queue[1][1] == 'terminate' then
			program_event_queue = {} -- signal below to break the outer loop
			break

		-- if the user has pressed the capture current key, enter the capture view
		elseif program_event_queue[1][1] == 'key' and program_event_queue[1][2] == capture_current_key then
			table.remove(program_event_queue, 1)
			if not enter_capture_view() then
				program_event_queue = {} -- signal below to break the outer loop
				break
			end

		-- if the user has pressed the capture next frame key, set the next frame to capture
		elseif program_event_queue[1][1] == 'key' and program_event_queue[1][2] == capture_next_frame_key then
			table.remove(program_event_queue, 1)
			capture_frame = 0

		-- if there is an event filter and we're not matching it, drop the event
		elseif event_filter and program_event_queue[1][1] ~= event_filter and program_event_queue[1][1] ~= 'terminate' then
			table.remove(program_event_queue, 1)

		-- otherwise, break out of the loop to resume the program
		else
			break
		end
	end

	-- if the queue is empty (from not continuing, above) then break
	if #program_event_queue == 0 then
		break
	end

	local event = table.remove(program_event_queue, 1)
	local yielded = { coroutine.resume(program_coroutine, table.unpack(event)) }

	if not should_continue_running() then
		break
	end

	-- if we've errored, enter the capture view then exit
	if not yielded[1] then
		enter_capture_view()
		break
	end

	-- if the program's finished, exit
	if coroutine.status(program_coroutine) == 'dead' then
		break
	end

	-- set the event filter for the next iteration
	event_filter = yielded[2]
end

end_frame()

-- restore the palette
for i = 0, 15 do
	term.setPaletteColour(2 ^ i, table.unpack(palette[i + 1]))
end
