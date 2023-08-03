
local args = { ... }

local program_name
local program_args = {}
local capture_frame = nil
local capture_key = keys.f12
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
		elseif args[1] == '--capture-key' or args[1] == '-k' then
			local flag = table.remove(args, 1)
			if not args[1] then error('Expected key name after ' .. flag, 0) end
			local key_name = table.remove(args, 1)
			if not keys[key_name] then error('Invalid key name \'' .. key_name .. '\'', 0) end
			capture_key = keys[key_name]
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

	local program_fn, err = load(program_content, program_name, nil, program_environment)
	if not program_fn then
		error('Could not load program \'' .. program_path .. '\': ' .. err, 0)
	end

	program_coroutine = coroutine.create(function()
		local ok, err = xpcall(program_fn, function(message, level)
			local actual_message = message
			if type(message ~= 'string') then
				message = ''
			end
			local traceback = debug.traceback(message, (level or 1) + 3)
			local lines = {}
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
			return {
				message = actual_message,
				traceback = lines,
			}
		end)
		if not ok then
			error(err, 0)
		end
	end)
end

local v3d
local v3d_modified_library
do -- load v3d
	local this_dir = shell
				and shell.getRunningProgram()
						:gsub('src/v3debug/v3debug%.lua$', '')
						:gsub('v3debug%.lua$', '')
						:gsub('v3debug$', '')
				or '../../../'

	local v3d_try_paths = {
		this_dir .. 'artifacts/v3d.lua',
		this_dir .. 'v3d.lua',
		this_dir .. 'v3d',
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

--- @alias V3DDebugNormalCall { fn_name: string, parameters: any[], result: any | nil }
--- @alias V3DDebugCall V3DDebugNormalCall
---                   | { debug_region: true, name: string, calls: V3DDebugCall[] }

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

do -- provide a modified 'module' and 'require' to the program
	local require, module = require '/rom.modules.main.cc.require'
		.make(program_environment, program_path:gsub('[^/]+$', ''))

	program_environment.require = require
	program_environment.module = module

	module.loaded['v3d'] = v3d_modified_library
end

--- @param err { message: any, traceback: string[] } | nil
--- @return boolean continue, any[][] events
local function enter_capture_view(err)
	if err then
		if err.message == V3D_VALIDATION_ERROR then
			print('Error in ' .. V3D_VALIDATION_ERROR.context.fn_name .. ':')
			for _, e in ipairs(V3D_VALIDATION_ERROR.context.errors) do
				if e.attribute then
					print(' * ' .. e.attribute .. ' (' .. tostring(e.value) .. '): ' .. e.message)
				else
					print(' * ' .. e.message)
				end
			end
		else
			printError(err.message)
		end

		error(table.concat(err.traceback, '\n'), 0)
	end

	return false, {}
end

do -- create modified library
	-- #gen-type-validators
	-- #gen-function-wrappers
	-- #gen-method-wrappers
	-- #gen-metamethod-wrappers
	-- #gen-generated-function-wrappers

	function v3d_modified_library.enter_debug_region(name)
		local call = {
			debug_region = true,
			name = tostring(name == nil and 'Debug region' or name),
			calls = {},
		}
		table.insert(v3d_this_frame_calls, call)
		table.insert(v3d_this_frame_call_stack, v3d_this_frame_calls)
		v3d_this_frame_calls = call.calls
	end

	function v3d_modified_library.exit_debug_region()
		v3d_this_frame_calls = table.remove(v3d_this_frame_call_stack)
	end
end

-- keep a copy of the palette so we can restore it later
local palette = {}
for i = 0, 15 do
	palette[i + 1] = { term.getPaletteColour(2 ^ i) }
end

local event_queue = { program_args }
local event_filter = nil
while true do
	while true do
		-- if we don't have a queued event, pull one
		if not event_queue[1] then
			event_queue[1] = { coroutine.yield() }

		-- if the user has pressed the capture key, enter the capture view
		elseif event_queue[1][1] == 'key' and event_queue[1][2] == capture_key then
			table.remove(event_queue, 1)
			local continue, extra_events = enter_capture_view(nil)
			if not continue then
				event_queue = {} -- signal below to break the outer loop
				break
			end
			for _, event in ipairs(extra_events) do
				table.insert(event_queue, event)
			end

		-- if there is an event filter and we're not matching it, drop the event
		elseif event_filter and event_queue[1][1] ~= event_filter and event_queue[1][1] ~= 'terminate' then
			table.remove(event_queue, 1)

		-- otherwise, break out of the loop to resume the program
		else
			break
		end
	end

	-- if the queue is empty (from not continuing, above) then break
	if #event_queue == 0 then
		break
	end

	local event = table.remove(event_queue, 1)
	local yielded = { coroutine.resume(program_coroutine, table.unpack(event)) }

	-- if we've errored, enter the capture view then exit
	if not yielded[1] then
		enter_capture_view(yielded[2])
		break
	end

	-- if the program's finished, exit
	if coroutine.status(program_coroutine) == 'dead' then
		break
	end

	-- set the event filter for the next iteration
	event_filter = yielded[2]
end

-- restore the palette
for i = 0, 15 do
	term.setPaletteColour(2 ^ i, table.unpack(palette[i + 1]))
end
