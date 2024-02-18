
-- localise globals for performance
local type = type
local lua_type = type
local math_cos = math.cos
local math_pi = math.pi
local math_sin = math.sin
local math_tan = math.tan

--- The V3D library.
--- @class V3D
--- @v3d-untracked
local v3d = {}

local __type_methods = {}
local __type_metatables = {}
local __type_instances = {}
local __type_create_hooks = {}

--- @generic T
--- @param instance_type `T`
--- @param label string | nil
--- @return T
local function _create_instance(instance_type, label)
	local instance = {}

	instance.__v3d_typename = instance_type
	instance.__v3d_label = label

	local methods = __type_methods[instance_type]
	if methods then
		for k, v in pairs(methods) do
			instance[k] = v
		end
	end

	local mt = __type_metatables[instance_type]
	if mt then
		setmetatable(instance, mt)
	end

	return instance
end

--- @generic T
--- @param instance T
--- @return T
local function _finalise_instance(instance)
	--- @diagnostic disable-next-line: undefined-field
	local typename = instance.__v3d_typename

	local instances = __type_instances[typename]
	if instances then
		table.insert(instances, instance)
	end

	local create_hook = __type_create_hooks[typename]
	if create_hook then
		create_hook(instance)
	end

	return instance
end

--- @param message string
--- @return any
local function _v3d_internal_error(message)
	error('v3d internal error: ' .. tostring(message), 3)
end

local function _v3d_contextual_error(message, context)
	local traceback
	pcall(function()
		traceback = debug and debug.traceback and debug.traceback()
	end)
	local h
	if fs and fs.isDir('v3d/artifacts') then
		h = assert(io.open('v3d/artifacts/contextual_error.txt', 'w'))
	else
		h = assert(io.open('.v3d_contextual_error.txt', 'w'))
	end
	h:write(message)
	h:write('\n')
	h:write(traceback)
	h:write('\n')
	h:write('Context:\n')
	h:write(context)
	h:write('\n')
	h:close()

	error(message, 3)
end

----------------------------------------------------------------

--- Replace occurrences of code like `math.floor` with `__math_floor` and
--- prepend a localisation to the string.
---
--- For example, the following code would be translated:
--- ```lua
--- math.floor(6.7)
--- ```
--- to:
--- ```lua
--- local __math = math
--- local __math_floor = __math.floor
--- __math_floor(6.7)
--- ```
---
--- In the special case that the source code returns a function and
--- `handle_upvalues` is true, the localisations will be inserted at the start
--- of the function body and also localised as upvalues.
---
--- For example, the following code would be translated:
--- ```lua
--- return function()
--- 	return math.floor(6.7)
--- end
--- ```
--- to:
--- ```lua
--- local __math = math
--- local __math_floor_upvalue = __math.floor
--- return function()
--- 	local __math_floor = __math_floor_upvalue
--- 	return __math_floor(6.7)
--- end
--- @param source string
--- @return string
local function _v3d_optimise_globals(source, handle_upvalues)
	local libraries_found = {}
	local functions_found = {}

	for _, library in ipairs { 'math', 'table', 'ccemux', 'os' } do
		source = source:gsub(library .. '%.([%w_]+)', function(fn)
			if _G[library][fn] then
				local replacement_name = '__' .. library .. '_' .. fn
				libraries_found[library] = true
				functions_found[library .. '.' .. fn] = replacement_name
				return replacement_name
			end
		end)
	end

	local prefix = ''
	local suffix = source
	local handling_upvalues = false

	if handle_upvalues and source:find 'function%b()' then
		prefix, suffix = source:match '^(.*function%b()%s*)(.*)$'
		handling_upvalues = true
	elseif handle_upvalues and source:find 'function [%w_]+%b()' then
		prefix, suffix = source:match '^(.*function [%w_]+%b()%s*)(.*)$'
		handling_upvalues = true
	end

	if handling_upvalues then
		for fn, replacement_name in pairs(functions_found) do
			prefix = 'local ' .. replacement_name .. '_upvalue = ' .. fn .. '\n' .. prefix
		end
	else
		for library in pairs(libraries_found) do
			prefix = 'local __' .. library .. ' = ' .. library .. '\n' .. prefix
		end
	end

	local ws = prefix:match '([ \t]*)$'
	for fn, replacement_name in pairs(functions_found) do
		local replacement = handling_upvalues and replacement_name .. '_upvalue' or '__' .. fn
		suffix = 'local ' .. replacement_name .. ' = ' .. replacement .. '\n' .. ws .. suffix
	end

	return prefix .. suffix
end

--- Replace trivial operations like `* 1` with nothing.
--- @param source string
--- @return string
local function _v3d_optimise_maths(source)
	local s = source
		:gsub('%s*%*%s*1([^%w_%.])', '%1') -- * 1
		:gsub('%s*%+%s*0([^%w_%.])', '%1') -- + 0
		:gsub('([^%w_%.])0%s*%+%s*', '%1') -- 0 +
		:gsub('%b()%s*%*%s*0([^%w_%.])', '0%1') -- (...) * 0
		:gsub('([^%w_%.])0%s*%*%s*%b()', '%10') -- 0 * (...)
		:gsub('[%w_%.]+%s*%*%s*0([^%w_%.])', '0%1') -- xyz * 0
		:gsub('([^%w_%.])0%s*%*%s*[%w_%.]+', '%10') -- 0 * xyz
	return s
end

--- Remove leading indentation and empty leading/trailing lines
--- @param source string
--- @return string[]
local function _v3d_normalise_code_lines(source)
	local code_lines = {}
	local whitespace = {}
	local found_non_empty_line = false

	local function on_code_line(code_line)
		code_line = code_line:gsub('\t', '  ')
		if code_line:find '[^\t ]' then
			found_non_empty_line = true
			table.insert(whitespace, #code_line:match '^[\t ]*')
		end
		if found_non_empty_line then
			table.insert(code_lines, code_line)
		end
	end

	local s = 1
	local f = source:find('\n')
	while f do
		on_code_line(source:sub(s, f - 1))
		s = f + 1
		f = source:find('\n', s)
	end
	on_code_line(source:sub(s))

	local shortest_whitespace = whitespace[1] or 0
	for i = 2, #whitespace do
		shortest_whitespace = math.min(shortest_whitespace, whitespace[i])
	end

	for i = 1, #code_lines do
		code_lines[i] = code_lines[i]:sub(shortest_whitespace + 1)
	end

	for i = #code_lines, 1, -1 do
		if code_lines[i]:find '[^\t ]' then
			break
		end
		table.remove(code_lines, i)
	end

	return code_lines
end

local function _v3d_quote_string(text)
	return '\'' .. (text:gsub('[\\\'\n\t]', { ['\\'] = '\\\\', ['\''] = '\\\'', ['\n'] = '\\n', ['\t'] = '\\t' })) .. '\''
end

----------------------------------------------------------------

local function _xpcall_handler(...)
	return debug.traceback(...)
end

local function _v3d_apply_template(source, environment)
	local env = {}

	env._G = env
	env._VERSION = _VERSION
	env.assert = assert
	env.error = error
	env.getmetatable = getmetatable
	env.ipairs = ipairs
	env.load = load
	env.next = next
	env.pairs = pairs
	env.pcall = pcall
	env.print = print
	env.rawequal = rawequal
	env.rawget = rawget
	env.rawlen = rawlen
	env.rawset = rawset
	env.select = select
	env.setmetatable = setmetatable
	env.tonumber = tonumber
	env.tostring = tostring
	env.type = type
	env.xpcall = xpcall
	env.math = math
	env.string = string
	env.table = table

	env.quote = _v3d_quote_string

	for k, v in pairs(environment) do
		env[k] = v
	end

	source = source:gsub('%${([^}]+)}', '{= %1 =}')

	local write_content = {}

	write_content[1] = 'local _text_segments = {}'
	write_content[2] = 'local _table_insert = table.insert'

	while true do
		local s, f, indent, text, operator = ('\n' .. source):find('\n([\t ]*)([^\n{]*){([%%=#!])')
		if s and text:find "%-%-" then
			local newline = source:find('\n', f + 1) or #source
			table.insert(write_content, '_table_insert(_text_segments, ' .. env.quote(source:sub(1, newline)) .. ')')
			source = source:sub(newline + 1)
		elseif s then
			local close = source:find((operator == '%' and '%' or '') .. operator .. '}', f)
			           or error('Missing end to \'{' .. operator .. '\': expected a matching \'' .. operator .. '}\'', 2)

			local pre_text = source:sub(1, s - 1 + #indent + #text)
			local content = source:sub(f + 1, close - 1):gsub('^%s+', ''):gsub('%s+$', '')

			if (operator == '%' or operator == '#') and not text:find '%S' then -- I'm desperately trying to remove newlines and it's not working
				pre_text = source:sub(1, s - 1)
			end

			source = source:sub(close + 2)

			if (operator == '%' or operator == '#') and not source:sub(1, 1) == '\n' then -- I'm desperately trying to remove newlines and it's not working
				source = source:sub(2)
			end

			if operator == '=' then
				if #pre_text > 0 then
					table.insert(write_content, '_table_insert(_text_segments, ' .. env.quote(pre_text) .. ')')
				end

				table.insert(write_content, '_table_insert(_text_segments, (tostring(' .. content .. '):gsub("\\n", ' .. env.quote('\n' .. indent) .. ')))')
			elseif operator == '%' then
				if #pre_text > 0 then
					table.insert(write_content, '_table_insert(_text_segments, ' .. env.quote(pre_text) .. ')')
				end

				table.insert(write_content, content)
			elseif operator == '!' then
				local fn, err = load('return ' .. content, content, nil, env)
				if not fn then fn, err = load(content, content, nil, env) end
				if not fn then _v3d_contextual_error('Invalid {!!} section (syntax): ' .. err .. '\n    ' .. content, content) end
				local ok, result = xpcall(fn, _xpcall_handler)
				if ok and type(result) == 'function' then
					ok, result = pcall(result)
				end
				if not ok then _v3d_contextual_error('Invalid {!!} section (runtime):\n' .. result, content) end
				if type(result) == 'function' then
					ok, result = pcall(result)
					if not ok then _v3d_contextual_error('Invalid {!!} section (runtime):\n' .. result, content) end
				end
				if type(result) ~= 'string' then
					_v3d_contextual_error('Invalid {!!} section (return): not a string (got ' .. type(result) .. ')\n' .. content, content)
				end
				source = pre_text .. result:gsub('%${([^}]+)}', '{= %1 =}'):gsub('\n', '\n' .. indent) .. source
			elseif operator == '#' then
				-- do nothing, it's a comment
			end
		else
			table.insert(write_content, '_table_insert(_text_segments, ' .. env.quote(source) .. ')')
			break
		end
	end

	table.insert(write_content, 'return table.concat(_text_segments)')

	local code = table.concat(write_content, '\n')
	local f, err = load(code, '=template string', nil, env)
	if not f then _v3d_contextual_error('Invalid template builder (syntax): ' .. err, code) end
	local ok, result = xpcall(f, _xpcall_handler)
	if not ok then _v3d_contextual_error('Invalid template builder section (runtime):\n' .. result, code) end

	return result
end

--------------------------------------------------------------------------------
-- Debug -----------------------------------------------------------------------
do -----------------------------------------------------------------------------

--- Return every instance of `typename` which has been created and not yet
--- garbage collected (i.e. is still in use).
---
--- Note, this only applies to tracked types.
--- @generic T
--- @param typename `T`
--- @return T
--- @v3d-nolog
--- @v3d-advanced
--- local my_image = v3d.create_image(v3d.integer(), 1, 1, 1)
--- local instances = v3d.instances('V3DImage')
--- assert(instances[1] == my_image)
--- @v3d-example
function v3d.instances(typename)
	return __type_instances[typename] or {}
end

--- Set a method for a type. This method will be available on all instances of
--- the type that are created *after* this function has been called.
---
--- Note, this only applies to non-structural types.
--- @param typename string
--- @param methodname string
--- @param fn function
--- @return nil
--- @v3d-advanced
--- local was_called = false
--- v3d.set_method('V3DImage', 'my_method', function(self)
--- 	print('Hello from my_method!')
--- 	was_called = true
--- end)
---
--- local my_image = v3d.create_image(v3d.integer(), 1, 1, 1)
--- my_image:my_method() -- prints 'Hello from my_method!'
--- assert(was_called)
--- @v3d-example
function v3d.set_method(typename, methodname, fn)
	__type_methods[typename] = __type_methods[typename] or {}
	__type_methods[typename][methodname] = fn
end

--- Set a metamethod for a type. This metamethod will apply to all instances of
--- the type that are created *after* this function has been called.
---
--- Note, this only applies to non-structural types.
--- @param typename string
--- @param metamethod_name string
--- @param metamethod_value any
--- @return nil
--- @v3d-advanced
--- local was_called = false
--- v3d.set_metamethod('V3DImage', '__tostring', function(self)
--- 	was_called = true
--- 	return 'Hello from __tostring!'
--- end)
---
--- local my_image = v3d.create_image(v3d.integer(), 1, 1, 1)
--- print(my_image) -- prints 'Hello from __tostring!'
--- assert(was_called)
--- @v3d-example
function v3d.set_metamethod(typename, metamethod_name, metamethod_value)
	__type_metatables[typename] = __type_metatables[typename] or {}
	__type_metatables[typename][metamethod_name] = metamethod_value
end

--- Set a hook to be called whenever a new instance of a type is created. This
--- hook will be called for all instances of the type that are created *after*
--- this function has been called.
---
--- Only one hook may be set per type. Setting a new hook will overwrite the
--- previous one.
---
--- Note, this only applies to non-structural types.
--- @param typename string
--- @param fn function
--- @return nil
--- @v3d-advanced
--- local was_called = false
--- v3d.set_create_hook('V3DImage', function(self)
--- 	print('Hello from create hook!')
--- 	was_called = true
--- end)
---
--- local my_image = v3d.create_image(v3d.integer(), 1, 1, 1) -- prints 'Hello from create hook!'
--- assert(was_called)
--- @v3d-example
function v3d.set_create_hook(typename, fn)
	__type_create_hooks[typename] = fn
end

--- Indicate to V3D that calls following this should be considered part of a
--- debug region. This is purely a debug feature and does nothing by default,
--- but will allow debuggers to group together function calls under a
--- user-defined name.
---
--- Debug regions may be nested, but must be exited in the reverse order they
--- were entered.
--- @param name string
--- @return nil
--- @v3d-nolog
--- v3d.enter_debug_region('Map rendering')
--- @v3d-example
function v3d.enter_debug_region(name)
	-- do nothing: debuggers will hook into this
end

--- @see v3d.enter_debug_region
--- @param name string
--- @return nil
--- @v3d-nolog
--- v3d.exit_debug_region('Map rendering')
--- @v3d-example
function v3d.exit_debug_region(name)
	-- do nothing: debuggers will hook into this
end

end ----------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Formats ---------------------------------------------------------------------
do -----------------------------------------------------------------------------

--- A V3DFormat represents the structure of data within the V3D library. It is
--- used to describe the contents of things like geometry vertex data, image
--- contents, and more.
---
--- Formats are composed of primitives using tuples and structs. Tuples are
--- ordered sets of formats, and structs are ordered sets of named formats.
---
--- The primitive formats are:
--- - boolean: a true or false value
--- - integer: a signed integer
--- - uinteger: an unsigned integer
--- - number: a floating point number
--- - character: a single character
--- - string: a string of characters
--- @class V3DFormat
--- What kind of format this is.
--- @field kind 'boolean'
---           | 'integer'
---           | 'uinteger'
---           | 'number'
---           | 'character'
---           | 'string'
---           | 'tuple'
---           | 'struct'
--- The fields within the format if it is a tuple or struct. Nil otherwise.
--- @field fields V3DFormatStructField[] | V3DFormat[] | nil
--- @v3d-untracked

--- A field in a struct V3DFormat
--- @class V3DFormatStructField
--- The name of the field.
--- @field name string
--- The format of the field.
--- @field format V3DFormat
--- @v3d-structural

----------------------------------------------------------------

--- Return whether value is a value of this format. For example, if this format
--- is a boolean, return whether value is a boolean. If this format is a tuple,
--- return whether value is a table with at least the number of elements as this
--- format has fields, and each element is a value of the corresponding field's
--- format.
---
--- Note, for tuples and structs, the value may have more elements than the
--- format has fields. In this case, the extra elements will be ignored.
--- @param self V3DFormat
--- @param value any
--- @return boolean
--- @v3d-nolog
--- local my_format = v3d.tuple { v3d.integer(), v3d.boolean() }
--- local my_value = { 1, true }
--- assert(v3d.format_is_instance(my_format, my_value))
--- @v3d-example
--- local my_format = v3d.tuple { v3d.integer(), v3d.boolean() }
--- local my_value = "invalid value"
--- assert(not v3d.format_is_instance(my_format, my_value))
--- @v3d-example
function v3d.format_is_instance(self, value)
	local self_kind = self.kind
	if self_kind == 'boolean' then
		return value == true or value == false
	elseif self_kind == 'integer' then
		return type(value) == 'number' and value == math.floor(value)
	elseif self_kind == 'uinteger' then
		return type(value) == 'number' and value == math.floor(value) and value >= 0
	elseif self_kind == 'number' then
		return type(value) == 'number'
	elseif self_kind == 'character' then
		return type(value) == 'string' and #value == 1
	elseif self_kind == 'string' then
		return type(value) == 'string'
	elseif self_kind == 'tuple' then
		if type(value) ~= 'table' then
			return false
		end
		if #value < #self.fields then
			return false
		end
		for i = 1, #self.fields do
			if not v3d.format_is_instance(self.fields[i], value[i]) then
				return false
			end
		end
		return true
	elseif self_kind == 'struct' then
		if type(value) ~= 'table' then
			return false
		end
		for i = 1, #self.fields do
			local field = self.fields[i]
			if not v3d.format_is_instance(field.format, value[field.name]) then
				return false
			end
		end
		return true
	else
		return _v3d_internal_error('unknown format kind: ' .. tostring(self.kind))
	end
end

--- Return whether this format is equal to another format. Equality means that
--- the two formats are the exact same kind and have the exact same fields.
--- @param self V3DFormat
--- @param other V3DFormat
--- @return boolean
--- @v3d-nolog
--- @v3d-mt eq
--- local my_format = v3d.tuple { v3d.integer(), v3d.boolean() }
--- local my_other_format = v3d.tuple { v3d.integer(), v3d.boolean() }
--- assert(v3d.format_equals(my_format, my_other_format))
--- @v3d-example
--- local my_format = v3d.tuple { v3d.integer(), v3d.boolean() }
--- local my_other_format = v3d.tuple { v3d.uinteger(), v3d.boolean() }
--- assert(not v3d.format_equals(my_format, my_other_format))
--- @v3d-example
function v3d.format_equals(self, other)
	if self.kind ~= other.kind then
		return false
	end

	if self.kind == 'tuple' then
		if #self.fields ~= #other.fields then
			return false
		end

		for i = 1, #self.fields do
			if not v3d.format_equals(self.fields[i], other.fields[i]) then
				return false
			end
		end
	elseif self.kind == 'struct' then
		if #self.fields ~= #other.fields then
			return false
		end

		for i = 1, #self.fields do
			local self_field = self.fields[i]
			local other_field = other.fields[i]

			if self_field.name ~= other_field.name then
				return false
			end

			if not v3d.format_equals(self_field.format, other_field.format) then
				return false
			end
		end
	end

	return true
end

--- Return a string representation of this format.
--- @param self V3DFormat
--- @return string
--- @v3d-nolog
--- @v3d-mt tostring
--- local my_format = v3d.tuple { v3d.integer(), v3d.boolean() }
--- assert(v3d.format_tostring(my_format) == 'v3d.tuple { v3d.integer(), v3d.boolean() }')
--- @v3d-example
function v3d.format_tostring(self)
	if self.kind == 'tuple' then
		local fields = {}
		local any_different = false
		for i = 1, #self.fields do
			fields[i] = v3d.format_tostring(self.fields[i])
			any_different = any_different or not v3d.format_equals(self.fields[i], self.fields[1])
		end
		if any_different then
			return 'v3d.tuple { ' .. table.concat(fields, ', ') .. ' }'
		else
			return 'v3d.n_tuple(' .. fields[1] .. ', ' .. #self.fields .. ')'
		end
	elseif self.kind == 'struct' then
		local fields = {}
		local any_non_alphabetical = false

		for i = 2, #self.fields do
			if self.fields[i - 1].name > self.fields[i].name then
				any_non_alphabetical = true
				break
			end
		end

		if any_non_alphabetical then
			for i = 1, #self.fields do
				local field = self.fields[i]
				fields[i] = '{ name = \'' .. field.name .. '\', format = ' .. v3d.format_tostring(field.format) .. ' }'
			end
			return 'v3d.ordered_struct { ' .. table.concat(fields, ', ') .. ' }'
		else
			for i = 1, #self.fields do
				local field = self.fields[i]
				fields[i] = field.name .. ' = ' .. v3d.format_tostring(field.format)
			end
			return 'v3d.struct { ' .. table.concat(fields, ', ') .. ' }'
		end
	else
		return 'v3d.' .. self.kind .. '()'
	end
end

--- Return whether a buffered value of this format could be interpreted as the
--- other format. For example, a tuple of integers could be interpreted as a
--- tuple of numbers, but a tuple of numbers could not be interpreted as a tuple
--- of integers.
--- @param self V3DFormat
--- @param other V3DFormat
--- @return boolean
--- @v3d-nolog
--- local my_format = v3d.tuple { v3d.integer(), v3d.boolean() }
--- local my_other_format = v3d.tuple { v3d.number(), v3d.boolean() }
--- assert(v3d.format_is_compatible_with(my_format, my_other_format))
--- @v3d-example
function v3d.format_is_compatible_with(self, other)
	if self.kind == 'boolean' then
		return other.kind == 'boolean'
	elseif self.kind == 'integer' then
		return other.kind == 'integer' or other.kind == 'number'
	elseif self.kind == 'uinteger' then
		return other.kind == 'uinteger' or other.kind == 'integer' or other.kind == 'number'
	elseif self.kind == 'number' then
		return other.kind == 'number'
	elseif self.kind == 'character' then
		return other.kind == 'character' or other.kind == 'string'
	elseif self.kind == 'string' then
		return other.kind == 'string'
	elseif self.kind == 'tuple' then
		if other.kind ~= 'tuple' then
			return false
		end
		if #self.fields ~= #other.fields then
			return false
		end
		for i = 1, #self.fields do
			if not v3d.format_is_compatible_with(self.fields[i], other.fields[i]) then
				return false
			end
		end
		return true
	elseif self.kind == 'struct' then
		if other.kind ~= 'struct' then
			return false
		end

		if #self.fields ~= #other.fields then
			return false
		end

		for i = 1, #self.fields do
			local self_field = self.fields[i]
			local other_field = other.fields[i]

			if self_field.name ~= other_field.name then
				return false
			end

			if not v3d.format_is_compatible_with(self_field.format, other_field.format) then
				return false
			end
		end

		return true
	else
		return _v3d_internal_error('unknown format kind: ' .. tostring(self.kind))
	end
end

----------------------------------------------------------------

--- Flatten a value of this format into a table of basic Lua values. For
--- example, a tuple of integers would be flattened into a table of integers. A
--- struct would be flattened into a table of the values of its fields,
--- discarding the names.
---
--- If offset is not provided, it will default to 0.
---
--- If buffer is provided, the values will be written into the buffer at the
--- specified offset. Otherwise, a new buffer will be created. Either way, the
--- buffer will be returned.
--- @param format V3DFormat
--- @param value any
--- @param buffer table | nil
--- @param offset integer | nil
--- @return table
--- @v3d-nolog
--- @v3d-advanced
--- Value must be an instance of the specified format
--- @v3d-validate v3d.format_is_instance(format, value)
--- Offset must not be negative
--- @v3d-validate not offset or offset >= 0
--- local my_format = v3d.tuple { v3d.integer(), v3d.boolean() }
--- local my_value = { 1, true }
---
--- local buffer = v3d.format_buffer_into(my_format, my_value)
---
--- assert(buffer[1] == 1)
--- assert(buffer[2] == true)
--- @v3d-example
--- local my_format = v3d.tuple { v3d.integer(), v3d.boolean() }
--- local my_value = { 1, true }
--- local my_buffer = {}
---
--- v3d.format_buffer_into(my_format, my_value, my_buffer, 1)
---
--- assert(my_buffer[1] == nil) -- skipped due to the offset of 1
--- assert(my_buffer[2] == 1)
--- assert(my_buffer[3] == true)
--- @v3d-example
function v3d.format_buffer_into(format, value, buffer, offset)
	buffer = buffer or {}
	offset = offset or 0

	if format.kind == 'boolean' or format.kind == 'integer' or format.kind == 'uinteger' or format.kind == 'number' or format.kind == 'character' or format.kind == 'string' then
		buffer[offset + 1] = value
	elseif format.kind == 'tuple' then
		for i = 1, #format.fields do
			buffer = v3d.format_buffer_into(format.fields[i], value[i], buffer, offset)
			offset = offset + v3d.format_size(format.fields[i])
		end
	elseif format.kind == 'struct' then
		for i = 1, #format.fields do
			buffer = v3d.format_buffer_into(format.fields[i].format, value[format.fields[i].name], buffer, offset)
			offset = offset + v3d.format_size(format.fields[i].format)
		end
	else
		return _v3d_internal_error('unknown format kind: ' .. tostring(format.kind))
	end

	return buffer
end

--- Unflatten a table of basic Lua values into a value of this format. For
--- example, a tuple of integers would be unflattened from a table of integers.
--- A struct would be unflattened from a table of the values of its fields,
--- adding mapping the field names to their respective values.
--- @param format V3DFormat
--- @param buffer table
--- @param offset integer | nil
--- @return any
--- @v3d-nolog
--- @v3d-advanced
--- Buffer must be large enough to contain the format
--- @v3d-validate #buffer - (offset or 0) >= v3d.format_size(format)
--- Offset must not be negative
--- @v3d-validate not offset or offset >= 0
--- local my_format = v3d.struct { x = v3d.integer(), y = v3d.boolean() }
--- local my_buffer = { 1, true }
---
--- local value = v3d.format_unbuffer_from(my_format, my_buffer)
---
--- assert(value.x == 1)
--- assert(value.y == true)
--- @v3d-example
--- local my_format = v3d.struct { x = v3d.integer(), y = v3d.boolean() }
--- local my_buffer = { 1, true, 2, false, 3, true }
---
--- local value = v3d.format_unbuffer_from(my_format, my_buffer, 2 * v3d.format_size(my_format))
---
--- assert(value.x == 3)
--- assert(value.y == true)
--- @v3d-example
function v3d.format_unbuffer_from(format, buffer, offset)
	offset = offset or 0

	if format.kind == 'boolean' or format.kind == 'integer' or format.kind == 'uinteger' or format.kind == 'number' or format.kind == 'character' or format.kind == 'string' then
		return buffer[offset + 1]
	elseif format.kind == 'tuple' then
		local value = {}
		for i = 1, #format.fields do
			value[i] = v3d.format_unbuffer_from(format.fields[i], buffer, offset)
			offset = offset + v3d.format_size(format.fields[i])
		end
		return value
	elseif format.kind == 'struct' then
		local value = {}
		for i = 1, #format.fields do
			value[format.fields[i].name] = v3d.format_unbuffer_from(format.fields[i].format, buffer, offset)
			offset = offset + v3d.format_size(format.fields[i].format)
		end
		return value
	else
		return _v3d_internal_error('unknown format kind: ' .. tostring(format.kind))
	end
end

----------------------------------------------------------------

--- Return the size of the format in terms of how many primitive Lua values it
--- will occupy once buffered. For example, a tuple of 3 integers will have a
--- size of 3, and a struct with 4 of those tuples will have a size of 12
--- (4 * 3).
---
--- All primitive formats have a size of 1, e.g. integers, strings, and numbers.
--- @param format V3DFormat
--- @return integer
--- @v3d-nolog
--- @v3d-advanced
--- local my_format = v3d.tuple { v3d.integer(), v3d.boolean() }
--- assert(v3d.format_size(my_format) == 2)
--- @v3d-example
--- local my_format = v3d.struct { x = v3d.integer(), y = v3d.n_tuple(v3d.boolean(), 2) }
--- assert(v3d.format_size(my_format) == 3)
--- @v3d-example
function v3d.format_size(format)
	if format.kind == 'boolean' or format.kind == 'integer' or format.kind == 'uinteger' or format.kind == 'number' or format.kind == 'character' or format.kind == 'string' then
		return 1
	elseif format.kind == 'tuple' then
		local size = 0
		for i = 1, #format.fields do
			size = size + v3d.format_size(format.fields[i])
		end
		return size
	elseif format.kind == 'struct' then
		local size = 0
		for i = 1, #format.fields do
			size = size + v3d.format_size(format.fields[i].format)
		end
		return size
	else
		return _v3d_internal_error('unknown format kind: ' .. tostring(format.kind))
	end
end

----------------------------------------------------------------

--- Create a value of the specified format. If the format is a tuple or struct,
--- create a table with the appropriate fields. If the format is a primitive,
--- create a value of that format.
---
--- The default values of primitive format are as follows:
--- - boolean: `false`
--- - integer: `0`
--- - uinteger: `0`
--- - number: `0`
--- - character: `'\0'`
--- - string: `''`
--- @param format V3DFormat
--- @return any
--- @v3d-nolog
--- local my_format = v3d.tuple { v3d.integer(), v3d.boolean() }
---
--- local value = v3d.format_default_value(my_format)
---
--- assert(value[1] == 0)
--- assert(value[2] == false)
--- @v3d-example
function v3d.format_default_value(format)
	if format.kind == 'boolean' then
		return false
	elseif format.kind == 'integer' or format.kind == 'uinteger' or format.kind == 'number' then
		return 0
	elseif format.kind == 'character' then
		return '\0'
	elseif format.kind == 'string' then
		return ''
	elseif format.kind == 'tuple' then
		local value = {}
		for i = 1, #format.fields do
			value[i] = v3d.format_default_value(format.fields[i])
		end
		return value
	elseif format.kind == 'struct' then
		local value = {}
		for i = 1, #format.fields do
			value[format.fields[i].name] = v3d.format_default_value(format.fields[i].format)
		end
		return value
	else
		return _v3d_internal_error('unknown format kind: ' .. tostring(format.kind))
	end
end

----------------------------------------------------------------

--- Create a boolean format.
--- @return V3DFormat
--- @v3d-nolog
--- @v3d-constructor
--- local my_format = v3d.boolean()
--- @v3d-example
function v3d.boolean()
	local t = _create_instance 'V3DFormat'
	t.kind = 'boolean'
	return _finalise_instance(t)
end

----------------------------------------------------------------

--- Create a signed integer format.
--- @return V3DFormat
--- @v3d-nolog
--- @v3d-constructor
--- local my_format = v3d.integer()
--- @v3d-example
function v3d.integer()
	local t = _create_instance 'V3DFormat'
	t.kind = 'integer'
	return _finalise_instance(t)
end

----------------------------------------------------------------

--- Create an unsigned integer format (0 plus).
--- @return V3DFormat
--- @v3d-nolog
--- @v3d-constructor
--- local my_format = v3d.uinteger()
--- @v3d-example
function v3d.uinteger()
	local t = _create_instance 'V3DFormat'
	t.kind = 'uinteger'
	return _finalise_instance(t)
end

----------------------------------------------------------------

--- Create a floating point number format.
--- @return V3DFormat
--- @v3d-nolog
--- @v3d-constructor
--- local my_format = v3d.number()
--- @v3d-example
function v3d.number()
	local t = _create_instance 'V3DFormat'
	t.kind = 'number'
	return _finalise_instance(t)
end

----------------------------------------------------------------

--- Create a character format. A character is a string of length
--- 1.
--- @return V3DFormat
--- @v3d-nolog
--- @v3d-constructor
--- local my_format = v3d.character()
--- @v3d-example
function v3d.character()
	local t = _create_instance 'V3DFormat'
	t.kind = 'character'
	return _finalise_instance(t)
end

----------------------------------------------------------------

--- Create a string format.
--- @return V3DFormat
--- @v3d-nolog
--- @v3d-constructor
--- local my_format = v3d.string()
--- @v3d-example
function v3d.string()
	local t = _create_instance 'V3DFormat'
	t.kind = 'string'
	return _finalise_instance(t)
end

----------------------------------------------------------------

--- Construct a tuple format with the specified fields. A tuple is
--- an ordered set of formats.
--- @param fields V3DFormat[]
--- @return V3DFormat
--- @v3d-nolog
--- @v3d-constructor
--- local integer_string_tuple_format = v3d.tuple { v3d.integer(), v3d.string() }
--- @v3d-example
--- local empty_tuple_format = v3d.tuple {}
--- @v3d-example
function v3d.tuple(fields)
	local t = _create_instance 'V3DFormat'

	t.kind = 'tuple'
	t.fields = fields

	return _finalise_instance(t)
end

--- Construct a tuple format with `n` fields of format `format`.
--- @param format V3DFormat
--- @param n integer
--- @return V3DFormat
--- @v3d-mt mul
--- @v3d-nolog
--- @v3d-constructor
--- N must not be negative
--- @v3d-validate n >= 0
--- local vec3_format = v3d.n_tuple(v3d.number(), 3)
--- @v3d-example
--- local vec4_format = v3d.number() * 4
--- @v3d-example
function v3d.n_tuple(format, n)
	local fields = {}
	for i = 1, n do
		fields[i] = format
	end
	return _finalise_instance(v3d.tuple(fields))
end

----------------------------------------------------------------

--- Construct a struct format with the specified fields. A struct
--- is an ordered set of named formats. The fields are sorted
--- alphabetically by name.
--- @param fields { [string]: V3DFormat }
--- @return V3DFormat
--- @v3d-nolog
--- @v3d-constructor
--- local vec2_format = v3d.struct { x = v3d.number(), y = v3d.number() }
--- @v3d-example
function v3d.struct(fields)
	local t = _create_instance 'V3DFormat'
	local ordered_fields = {}

	for k, v in pairs(fields) do
		table.insert(ordered_fields, { name = k, format = v })
	end

	table.sort(ordered_fields, function(a, b)
		return a.name < b.name
	end)

	t.kind = 'struct'
	t.fields = ordered_fields

	return _finalise_instance(t)
end

--- Construct a struct format with the specified fields. A struct
--- is an ordered set of named formats. The fields are not sorted,
--- and are kept in the order they are provided in.
--- @param fields V3DFormatStructField[]
--- @return V3DFormat
--- @v3d-nolog
--- @v3d-constructor
--- @v3d-advanced
--- local vec2_format = v3d.ordered_struct {
--- 	{ name = 'x', format = v3d.number() },
--- 	{ name = 'y', format = v3d.number() },
--- }
--- @v3d-example
function v3d.ordered_struct(fields)
	local t = _create_instance 'V3DFormat'

	t.kind = 'struct'
	t.fields = fields

	return _finalise_instance(t)
end

end ----------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Lenses ----------------------------------------------------------------------
do -----------------------------------------------------------------------------

--- A lens is like a tunnel into a format. Consider a struct containing an X and
--- Y value. A lens could be used to refer to the X value or the Y value.
---
--- Lenses store both the input format and the output format. The input format
--- is the format of the value that the lens is applied to. The output format is
--- the format of the value that the lens refers to. For example, a lens into
--- the X/Y struct mentioned above would have an input format of the struct and
--- an output format of the X/Y value.
---
--- Lenses store the offset of where they are targeting within a buffered
--- instance of the format. For example, a lens into the X/Y struct mentioned
--- above would have an offset of 0 for the X value and an offset of 1 for the Y
--- value.
--- @class V3DLens
--- Format of the value that the lens is applied to.
--- @field in_format V3DFormat
--- Format of the value that the lens refers to.
--- @field out_format V3DFormat
--- The sequence of indices taken to get from an instance of the input format to
--- the output.
--- @field indices (string | integer)[]
--- Offset of the output relative to the start of an instance of the input
--- format.
--- @field offset integer

----------------------------------------------------------------

-- TODO: make this not accept string[] indices (move that to lens_get_index)
--- Create a lens with the specified input and output formats.
---
--- Can optionally pass a string `indices` which will index the input format. The
--- indices string can be a series of either:
--- - `.` followed by a field name, e.g. `.field`
--- - `.` followed by a numeric index, e.g. `.1`
--- - `[` followed by a field name and a closing ']', e.g. `[field]`
--- - `[` followed by a quoted string index and a closing ']', e.g. `['my field']`
---
--- Numeric indices are 1-based, so the first element of a tuple or struct is
--- index 1.
--- @param format V3DFormat
--- @param indices string[] | string | nil
--- @return V3DLens | nil
--- @v3d-constructor
--- @v3d-nolog
--- local my_format = v3d.struct { x = v3d.integer(), y = v3d.integer() }
--- local my_lens = v3d.format_lens(my_format, '.y')
---
--- assert(my_lens.in_format == my_format)
--- assert(my_lens.out_format == v3d.integer())
--- assert(my_lens.indices[1] == 'y')
--- assert(my_lens.offset == 1)
--- @v3d-example 2
--- local my_format = v3d.tuple { v3d.string(), v3d.struct { v = v3d.integer() * 3 } }
--- local my_lens = v3d.format_lens(my_format, '.2.v[3]')
---
--- assert(my_lens.in_format == my_format)
--- assert(my_lens.out_format == v3d.integer())
--- assert(my_lens.indices[1] == 2)
--- assert(my_lens.indices[2] == 'v')
--- assert(my_lens.indices[3] == 3)
--- assert(my_lens.offset == 3)
--- @v3d-example 2
function v3d.format_lens(format, indices)
	local lens = _create_instance('V3DLens')

	lens.in_format = format
	lens.out_format = format
	lens.indices = {}
	lens.offset = 0

	_finalise_instance(lens)

	if type(indices) == 'string' then
		for part in indices:gmatch '[^%.]+' do
			local end_parts = {}

			while part:find '%[[^%[%]]+%]$' do
				local rest, end_part = part:match '^(.*)%[([^%[%]]+)%]$'
				end_part = end_part:gsub('^%s*(.-)%s*$', '%1')
				if end_part:sub(1, 1) == '\'' or end_part:sub(1, 1) == '"' then
					end_part = end_part:sub(2, -2)
				end
				table.insert(end_parts, 1, tonumber(end_part) or end_part)
				part = rest
			end

			part = part:gsub('^%s*(.-)%s*$', '%1')

			if part ~= '' then
				table.insert(end_parts, 1, tonumber(part) or part)
			end

			for i = 1, #end_parts do
				if not v3d.lens_has_index(lens, end_parts[i]) then
					return nil
				end
				lens = v3d.lens_get_index(lens, end_parts[i])
			end
		end
	elseif type(indices) == 'table' then
		for i = 1, #indices do
			local index = tonumber(indices[i]) or indices[i]
			if not v3d.lens_has_index(lens, index) then
				return nil
			end
			lens = v3d.lens_get_index(lens, index)
		end
	end

	return lens
end

----------------------------------------------------------------

--- Return whether the specified lens has the specified index. The index may be
--- an integer index or a string field name.
---
--- If the lens' output format is a tuple, this function will return whether the
--- index is an integer within the range of the tuple's elements.
---
--- If the lens' output format is a struct, this function will return whether
--- the index is a string field name or an integer index belonging to the
--- struct.
---
--- If the lens' output format is a primitive, this function will always return
--- false.
---
--- Integer indices are 1-based, so the first element of a tuple or struct is
--- index 1.
--- @param lens V3DLens
--- @param index integer | string
--- @return boolean
--- @v3d-nolog
--- local my_format = v3d.tuple { v3d.integer(), v3d.boolean() }
--- local my_lens = v3d.format_lens(my_format)
---
--- assert(v3d.lens_has_index(my_lens, 1))
--- assert(v3d.lens_has_index(my_lens, 2))
--- assert(not v3d.lens_has_index(my_lens, 3))
--- @v3d-example
--- local my_format = v3d.struct { v = v3d.integer() }
--- local my_lens = v3d.format_lens(my_format)
---
--- assert(v3d.lens_has_index(my_lens, 'v'))
--- assert(not v3d.lens_has_index(my_lens, 'w'))
--- assert(v3d.lens_has_index(my_lens, 1))
--- assert(not v3d.lens_has_index(my_lens, 2))
--- @v3d-example
function v3d.lens_has_index(lens, index)
	if lens.out_format.kind == 'tuple' and type(index) == 'number' then
		return index >= 1 and index <= #lens.out_format.fields
	elseif lens.out_format.kind == 'struct' then
		for i = 1, #lens.out_format.fields do
			if i == index or lens.out_format.fields[i].name == index then
				return true
			end
		end
	end

	return false
end

----------------------------------------------------------------

--- Return a lens which gets the value at the specified index of the input
--- lens.
---
--- The index may be an integer index or a string field name but must exist on
--- the lens.
---
--- Integer indices are 1-based, so the first element of a tuple or struct is
--- index 1.
---
--- This returns a new lens without modifying the original.
--- @param lens V3DLens
--- @param index integer | string
--- @return V3DLens
--- @v3d-nolog
--- Index must exist on the lens.
--- @v3d-validate v3d.lens_has_index(lens, index)
--- local my_format = v3d.tuple { v3d.integer(), v3d.boolean() }
--- local my_lens = v3d.format_lens(my_format)
--- local my_integer_lens = v3d.lens_get_index(my_lens, 1)
---
--- assert(my_integer_lens.in_format == my_format)
--- assert(my_integer_lens.out_format == v3d.integer())
--- assert(my_integer_lens.indices[1] == 1)
--- assert(my_integer_lens.offset == 0)
--- @v3d-example
--- local my_format = v3d.struct { x = v3d.integer(), y = v3d.integer() }
--- local my_lens = v3d.format_lens(my_format)
--- local my_y_lens = v3d.lens_get_index(my_lens, 'y')
---
--- assert(my_y_lens.in_format == my_format)
--- assert(my_y_lens.out_format == v3d.integer())
--- assert(my_y_lens.indices[1] == 'y')
--- assert(my_y_lens.offset == 1)
--- assert(my_y_lens == v3d.lens_get_index(my_lens, 2))
--- @v3d-example
function v3d.lens_get_index(lens, index)
	local out_lens = _create_instance('V3DLens')

	out_lens.in_format = lens.in_format
	out_lens.out_format = lens.out_format.fields[index]
	out_lens.indices = {}
	out_lens.offset = lens.offset

	for _, idx in ipairs(lens.indices) do
		table.insert(out_lens.indices, idx)
	end

	if lens.out_format.kind == 'tuple' then
		for i = 1, index - 1 do
			out_lens.offset = out_lens.offset + v3d.format_size(lens.out_format.fields[i])
		end
		table.insert(out_lens.indices, index)
	elseif lens.out_format.kind == 'struct' then
		for i = 1, #lens.out_format.fields do
			if i == index or lens.out_format.fields[i].name == index then
				out_lens.out_format = lens.out_format.fields[i].format
				table.insert(out_lens.indices, lens.out_format.fields[i].name)
				break
			end
			out_lens.offset = out_lens.offset + v3d.format_size(lens.out_format.fields[i].format)
		end
	end

	return _finalise_instance(out_lens)
end

----------------------------------------------------------------

--- Return the composition of two lenses, first applying this lens, then the
--- other. The in_format of the result will equal the in_format of this lens,
--- and the out_format of the result will equal the out_format of the other
--- lens.
---
--- This returns a new lens without modifying the original.
--- @param lens V3DLens
--- @param other_lens V3DLens
--- @return V3DLens
--- @v3d-nolog
--- @v3d-mt concat
--- Lens output format must match other lens input format
--- @v3d-validate v3d.format_is_compatible_with(lens.out_format, other_lens.in_format)
--- local my_inner_format = v3d.struct { x = v3d.integer(), y = v3d.integer() }
--- local my_outer_format = v3d.struct { inner = my_inner_format }
--- local my_outer_lens = v3d.format_lens(my_outer_format, '.inner')
--- local my_inner_lens = v3d.format_lens(my_inner_format, '.y')
--- local my_lens = v3d.lens_compose(my_outer_lens, my_inner_lens)
---
--- assert(my_lens.in_format == my_outer_format)
--- assert(my_lens.out_format == v3d.integer())
--- assert(my_lens.indices[1] == 'inner')
--- assert(my_lens.indices[2] == 'y')
--- assert(my_lens.offset == 1)
--- @v3d-example 3:5
function v3d.lens_compose(lens, other_lens)
	local out_lens = _create_instance('V3DLens')

	out_lens.in_format = lens.in_format
	out_lens.out_format = other_lens.out_format
	out_lens.indices = {}
	out_lens.offset = lens.offset + other_lens.offset

	for _, idx in ipairs(lens.indices) do
		table.insert(out_lens.indices, idx)
	end

	for _, idx in ipairs(other_lens.indices) do
		table.insert(out_lens.indices, idx)
	end

	return _finalise_instance(out_lens)
end

----------------------------------------------------------------

-- TODO: lens_get
-- TODO: lens_set
-- TODO: lens_buffer (replace type one? nah)
-- TODO: lens_unbuffer (replace type one? nah)

----------------------------------------------------------------

--- Return the string representation of a lens.
--- @param lens V3DLens
--- @return string
--- @v3d-nolog
--- @v3d-mt tostring
function v3d.lens_tostring(lens)
	local indices = {}

	for _, idx in ipairs(lens.indices) do
		if type(idx) == 'number' then
			table.insert(indices, '[' .. tostring(idx) .. ']')
		elseif not idx:find '%w_' then
			table.insert(indices, '.' .. idx)
		else
			table.insert(indices, '["' .. idx .. '"]')
		end
	end

	return 'v3d.format_lens(' .. v3d.format_tostring(lens.in_format) .. ', \'' .. table.concat(indices) .. '\')'
end

--- Return whether two lenses are equal.
--- @param lens V3DLens
--- @param other_lens V3DLens
--- @return boolean
--- @v3d-nolog
--- @v3d-mt eq
function v3d.lens_equals(lens, other_lens)
	if lens.in_format ~= other_lens.in_format then
		return false
	end

	if #lens.indices ~= #other_lens.indices then
		return false
	end

	for i = 1, #lens.indices do
		if lens.indices[i] ~= other_lens.indices[i] then
			return false
		end
	end

	return true
end

end ----------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Images ----------------------------------------------------------------------
do -----------------------------------------------------------------------------

--- An image is an efficient 3D array of pixels with a width, height, and depth.
--- Each pixel is a value of a specified format, flattened into the image's
--- internal data buffer.
--- @class V3DImage
--- Format of each pixel in the image.
--- @field format V3DFormat
--- Width of the image in pixels.
--- @field width integer
--- Height of the image in pixels.
--- @field height integer
--- Depth of the image in pixels.
--- @field depth integer

----------------------------------------------------------------

--- Specifies a subregion of an image.
--- @class V3DImageRegion
--- Horizontal offset of the region. An offset of 0 means the region starts at
--- the leftmost pixel.
--- @field x integer
--- Vertical offset of the region. An offset of 0 means the region starts at the
--- topmost pixel.
--- @field y integer
--- Depth offset of the region. An offset of 0 means the region starts at the
--- frontmost pixel.
--- @field z integer
--- Width of the region. A width of 1 means the region is 1 pixel wide.
--- @field width integer
--- Height of the region. A height of 1 means the region is 1 pixel tall.
--- @field height integer
--- Depth of the region. A depth of 1 means the region is 1 pixel deep.
--- @field depth integer
--- @v3d-structural
--- Width must not be negative
--- @v3d-validate self.width >= 0
--- Height must not be negative
--- @v3d-validate self.height >= 0
--- Depth must not be negative
--- @v3d-validate self.depth >= 0

----------------------------------------------------------------

--- Create an image with the specified format, width, height, and depth. If
--- pixel_value is provided, the image will be filled with that value.
--- Otherwise, the image will be filled with the default value for the specified
--- format.
---
--- Note, a depth must be provided. If you want a 2D image, use a depth of 1.
--- @param format V3DFormat
--- @param width integer
--- @param height integer
--- @param depth integer
--- @param pixel_value any | nil
--- @param label string | nil
--- @return V3DImage
--- @v3d-nomethod
--- @v3d-constructor
--- Width must not be negative
--- @v3d-validate width >= 0
--- Height must not be negative
--- @v3d-validate height >= 0
--- Depth must not be negative
--- @v3d-validate depth >= 0
--- Pixel value must be an instance of the specified format or nil
--- @v3d-validate pixel_value == nil or v3d.format_is_instance(format, pixel_value)
--- -- Create a blank 16x16x16 3D image.
--- local my_image = v3d.create_image(v3d.number(), 16, 16, 16)
--- @v3d-example 2
--- -- Create an image ready for subpixel rendering.
--- local term_width, term_height = term.getSize()
--- local my_image = v3d.create_image(v3d.uinteger(), term_width * 2, term_height * 3, 1, colours.black)
--- @v3d-example 3
--- -- Create an image ready for text rendering
--- local term_width, term_height = term.getSize()
--- local colour_plus_text = v3d.tuple { v3d.uinteger(), v3d.uinteger(), v3d.character() }
--- local my_image = v3d.create_image(colour_plus_text, term_width, term_height, 1, { colours.black, colours.white, ' ' })
--- @v3d-example 4
function v3d.create_image(format, width, height, depth, pixel_value, label)
	local image = _create_instance('V3DImage', label)
	local pixel_data = v3d.format_buffer_into(format, pixel_value or v3d.format_default_value(format))
	local pixel_format_size = #pixel_data

	image.format = format
	image.width = width
	image.height = height
	image.depth = depth

	local index = 1
	for _ = 1, width * height * depth do
		for i = 1, pixel_format_size do
			image[index] = pixel_data[i]
			index = index + 1
		end
	end

	return _finalise_instance(image)
end

----------------------------------------------------------------

--- Return whether the region is entirely contained within the image.
--- @param image V3DImage
--- @param region V3DImageRegion
--- @return boolean
--- @v3d-nolog
--- local my_image = v3d.create_image(v3d.number(), 16, 16, 16)
--- local my_region = {
--- 	x = 0, y = 0, z = 0,
--- 	width = 16, height = 16, depth = 16,
--- }
--- assert(v3d.image_contains_region(my_image, my_region))
--- @v3d-example 6
--- local my_image = v3d.create_image(v3d.number(), 16, 16, 16)
--- local my_region = {
--- 	x = 7, y = -2, z = 0,
--- 	width = 16, height = 16, depth = 92,
--- }
--- assert(not v3d.image_contains_region(my_image, my_region))
--- @v3d-example 6
function v3d.image_contains_region(image, region)
	return region.x >= 0 and region.y >= 0 and region.z >= 0 and region.x + region.width <= image.width and region.y + region.height <= image.height and region.z + region.depth <= image.depth
end

----------------------------------------------------------------

--- Return an identical copy of the image with the same format and dimensions.
---
--- Modifying the returned image will not modify the original image, and vice
--- versa.
--- @param image V3DImage
--- @param label string | nil
--- @v3d-constructor
--- @return V3DImage
--- local my_image = v3d.create_image(v3d.number(), 16, 16, 16, 24)
--- local my_image_copy = v3d.image_copy(my_image)
---
--- assert(my_image.format == my_image_copy.format)
--- assert(my_image.width == my_image_copy.width)
--- assert(my_image.height == my_image_copy.height)
--- assert(my_image.depth == my_image_copy.depth)
---
--- for i = 1, 16 * 16 * 16 do
--- 	assert(my_image[i] == my_image_copy[i])
--- end
--- @v3d-example 2
function v3d.image_copy(image, label)
	local new_image = _create_instance('V3DImage', label)

	new_image.format = image.format
	new_image.width = image.width
	new_image.height = image.height
	new_image.depth = image.depth

	for i = 1, image.width * image.height * image.depth * v3d.format_size(image.format) do
		new_image[i] = image[i]
	end

	return new_image
end

end ----------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Image views -----------------------------------------------------------------
do -----------------------------------------------------------------------------

--- An image view is a view into an image. It has the same format as the image,
--- but represents a sub region of the image.
---
--- Image views are used to access and modify the data within images.
--- @class V3DImageView
--- Image this view is into.
--- @field image V3DImage
--- Region of the image this view is into. This region will always be specified
--- and entirely contained within the image.
--- @field region V3DImageRegion
--- @field private init_offset integer
--- @field private pixel_format_size integer
--- @field private row_end_delta integer
--- @field private layer_end_delta integer
--- @v3d-untracked

--- Partial assignment of image region fields. Used with `image_view` to specify
--- a sub region of an image.
--- If X, Y, or Z are not specified, they will default to 0. If width, height,
--- or depth are not specified, they will default to the maximum possible value
--- for that dimension, accounting for the specified X, Y, and Z.
--- @class V3DPartialImageRegion
--- Horizontal offset of the region. An offset of 0 means the region starts at
--- the leftmost pixel.
--- @field x integer | nil
--- Vertical offset of the region. An offset of 0 means the region starts at the
--- topmost pixel.
--- @field y integer | nil
--- Depth offset of the region. An offset of 0 means the region starts at the
--- frontmost pixel.
--- @field z integer | nil
--- Width of the region. A width of 1 means the region is 1 pixel wide.
--- @field width integer | nil
--- Height of the region. A height of 1 means the region is 1 pixel tall.
--- @field height integer | nil
--- Depth of the region. A depth of 1 means the region is 1 pixel deep.
--- @field depth integer | nil
--- @v3d-structural
--- Width must not be negative
--- @v3d-validate not self.width or self.width >= 0
--- Height must not be negative
--- @v3d-validate not self.height or self.height >= 0
--- Depth must not be negative
--- @v3d-validate not self.depth or self.depth >= 0

--- Create a new image view into an image. The image view will have the same
--- format as the image. If a region is specified, the image view will represent
--- that region of the image. Otherwise, the image view will represent the
--- entire image.
---
--- If provided, the region will be clamped to be within the image. This
--- includes negative X, Y, or Z values, and sizes that extend beyond the image.
--- @param image V3DImage
--- @param region V3DPartialImageRegion | nil
--- @return V3DImageView
--- @v3d-constructor
--- @v3d-nolog
--- local my_image = v3d.create_image(v3d.number(), 1, 2, 3, 42)
--- local my_image_view = v3d.image_view(my_image)
---
--- assert(my_image_view.image == my_image)
--- assert(my_image_view.region.x == 0)
--- assert(my_image_view.region.y == 0)
--- assert(my_image_view.region.z == 0)
--- assert(my_image_view.region.width == 1)
--- assert(my_image_view.region.height == 2)
--- assert(my_image_view.region.depth == 3)
--- @v3d-example 1:2
--- local my_image = v3d.create_image(v3d.number(), 2, 3, 4, 42)
--- local my_image_view = v3d.image_view(my_image, {
--- 	x = 1,
--- 	height = 2,
--- 	depth = 100,
--- })
---
--- assert(my_image_view.image == my_image)
--- assert(my_image_view.region.x == 1)
--- assert(my_image_view.region.y == 0)
--- assert(my_image_view.region.z == 0)
--- assert(my_image_view.region.width == 1)
--- assert(my_image_view.region.height == 2)
--- assert(my_image_view.region.depth == 4)
--- @v3d-example 1:6
function v3d.image_view(image, region)
	local view = _create_instance('V3DImageView')

	region = region or {
		x = 0, y = 0, z = 0,
		width = image.width, height = image.height, depth = image.depth,
	}

	local x = math.max(region.x or 0, 0)
	local y = math.max(region.y or 0, 0)
	local z = math.max(region.z or 0, 0)

	view.image = image
	view.region = {
		x = x,
		y = y,
		z = z,
		width = math.max(0, math.min(region.width or math.huge, image.width - x)),
		height = math.max(0, math.min(region.height or math.huge, image.height - y)),
		depth = math.max(0, math.min(region.depth or math.huge, image.depth - z)),
	}

	--- @diagnostic disable: invisible
	view.pixel_format_size = v3d.format_size(image.format)
	view.init_offset = ((view.region.z * image.width * image.height) + (view.region.y * image.width) + view.region.x) * view.pixel_format_size
	view.row_end_delta = (image.width - view.region.width) * view.pixel_format_size
	view.layer_end_delta = (image.height - view.region.height) * image.width * view.pixel_format_size
	--- @diagnostic enable: invisible

	return view
end

-- TODO: image_view_view(image_view, region)

----------------------------------------------------------------

--- Create a new image containing just the contents of this image view. The
--- image will have the same format as the image view and the resultant image's
--- data will not be linked with the original image. In other words, making a
--- change to the original image will not affect the new image, and vice versa.
--- @param image_view V3DImageView
--- @param label string | nil
--- @return V3DImage
--- @v3d-constructor
--- @v3d-advanced
--- local my_image = v3d.create_image(v3d.number(), 16, 16, 16, 42)
--- local my_image_view = v3d.image_view(my_image)
--- local my_image_copy = v3d.image_view_create_image(my_image_view)
--- @v3d-example 1:3
function v3d.image_view_create_image(image_view, label)
	local image = v3d.create_image(image_view.image.format, image_view.region.width, image_view.region.height, image_view.region.depth, label)

	--- @diagnostic disable: invisible
	local target_index = 1
	local index = image_view.init_offset + 1

	for _ = 1, image_view.region.depth do
		for _ = 1, image_view.region.height do
			for _ = 1, image_view.region.width do
				for _ = 1, image_view.pixel_format_size do
					image[target_index] = image_view.image[index]
					target_index = target_index + 1
					index = index + 1
				end
			end
			index = index + image_view.row_end_delta
		end
		index = index + image_view.layer_end_delta
	end
	--- @diagnostic enable: invisible

	return image
end

----------------------------------------------------------------

--- Fill an image view with the specified value. If no value is provided, the
--- image view will be filled with the default value for the image's format.
---
--- Note, the value must be compatible with the image's format and will be
--- flattened within the image's internal data buffer.
---
--- Returns the image view.
--- @param image_view V3DImageView
--- @param value any | nil
--- @return V3DImageView
--- @v3d-chainable
--- Pixel value must be an instance of the specified format or nil
--- @v3d-validate value == nil or v3d.format_is_instance(image_view.image.format, value)
--- local my_image = v3d.create_image(v3d.uinteger(), 51, 19, 1, colours.white)
--- local my_image_view = v3d.image_view(my_image)
---
--- v3d.image_view_fill(my_image_view, colours.black)
---
--- assert(v3d.image_view_get_pixel(my_image_view, 0, 0, 0) == colours.black)
--- @v3d-example 4
--- local my_image = v3d.create_image(v3d.uinteger(), 51, 19, 1, colours.white)
--- local my_region = {
--- 	x = 1, y = 1, z = 0,
--- 	width = 50, height = 18, depth = 1,
--- }
--- local my_image_view = v3d.image_view(my_image)
--- local my_image_sub_view = v3d.image_view(my_image, my_region)
---
--- v3d.image_view_fill(my_image_sub_view, colours.orange)
---
--- assert(v3d.image_view_get_pixel(my_image_view, 0, 0, 0) == colours.white)
--- assert(v3d.image_view_get_pixel(my_image_view, 1, 1, 0) == colours.orange)
--- @v3d-example 9
function v3d.image_view_fill(image_view, value)
	value = value or v3d.format_default_value(image_view.image.format)

	--- @diagnostic disable: invisible
	local image = image_view.image
	local index = image_view.init_offset + 1
	local pixel_data = v3d.format_buffer_into(image_view.image.format, value)
	local pixel_format_size = image_view.pixel_format_size
	local row_end_delta = image_view.row_end_delta
	local layer_end_delta = image_view.layer_end_delta
	--- @diagnostic enable: invisible

	-- TODO: consider reordering the loops to avoid unnecessary pixel data indexes
	for _ = 1, image_view.region.depth do
		for _ = 1, image_view.region.height do
			for _ = 1, image_view.region.width do
				for i = 1, pixel_format_size do
					image[index] = pixel_data[i]
					index = index + 1
				end
			end
			index = index + row_end_delta
		end
		index = index + layer_end_delta
	end

	return image_view
end

----------------------------------------------------------------

--- Get the value of a pixel in the image view. If the pixel is out of bounds,
--- nil will be returned. The coordinates are 0-indexed, meaning (0, 0, 0) is
--- the first pixel in the image view (top-left, front-most).
---
--- The coordinate provided is relative to the image view's offset within the
--- image, and coordinates outside the image view's region will not be
--- accessible.
---
--- Note, the value will be unflattened from the image's internal data buffer.
--- For example, if the image's format is a struct, a table with the field
--- values will be returned.
---
--- @see v3d.image_view_buffer_into
--- @param image_view V3DImageView
--- @param x integer
--- @param y integer
--- @param z integer
--- @return any
--- @v3d-nolog
--- local my_image = v3d.create_image(v3d.number(), 16, 16, 16, 42)
--- local my_image_view = v3d.image_view(my_image)
---
--- local single_pixel_value = v3d.image_view_get_pixel(my_image_view, 0, 0, 0)
---
--- assert(single_pixel_value == 42)
--- @v3d-example 4
--- local rgba_format = v3d.tuple { v3d.number(), v3d.number(), v3d.number(), v3d.number() }
--- local my_image = v3d.create_image(rgba_format, 16, 16, 16, { 0.1, 0.2, 0.3, 1 })
--- local my_image_view = v3d.image_view(my_image)
---
--- local rgba = v3d.image_view_get_pixel(my_image_view, 0, 0, 0)
---
--- assert(rgba[1] == 0.1)
--- assert(rgba[2] == 0.2)
--- assert(rgba[3] == 0.3)
--- assert(rgba[4] == 1)
--- @v3d-example 5
function v3d.image_view_get_pixel(image_view, x, y, z)
	local region = image_view.region

	if x < 0 or x >= region.width then
		return nil
	elseif y < 0 or y >= region.height then
		return nil
	elseif z < 0 or z >= region.depth then
		return nil
	end

	--- @diagnostic disable: invisible
	local pixel_format_size = image_view.pixel_format_size
	local offset = image_view.init_offset + ((z * image_view.image.width * image_view.image.height) + (y * image_view.image.width) + x) * pixel_format_size
	--- @diagnostic enable: invisible

	return v3d.format_unbuffer_from(image_view.image.format, image_view.image, offset)
end

--- Set the value of a pixel in the image viewport. If the pixel is out of
--- bounds, the image view will be returned with no changes applied. The
--- coordinates are 0-indexed, meaning (0, 0, 0) is the first pixel in the image
--- view (top-left, front-most).
---
--- The coordinate provided is relative to the image view's offset within the
--- image, and coordinates outside the image view's region will not be
--- accessible.
---
--- Note, the value must be compatible with the image views's image format and
--- will be flattened within the image's internal data buffer.
---
--- @see v3d.image_view_unbuffer_from
--- @param image_view V3DImageView
--- @param x integer
--- @param y integer
--- @param z integer
--- @param value any
--- @return V3DImageView
--- @v3d-chainable
--- Pixel value must be an instance of the specified format
--- @v3d-validate v3d.format_is_instance(image_view.image.format, value)
--- local my_image = v3d.create_image(v3d.uinteger(), 51, 19, colours.white)
--- local my_image_view = v3d.image_view(my_image)
---
--- v3d.image_view_set_pixel(my_image_view, 0, 0, 0, colours.black)
---
--- assert(v3d.image_view_get_pixel(my_image_view, 0, 0, 0) == colours.black)
--- @v3d-example 3
function v3d.image_view_set_pixel(image_view, x, y, z, value)
	local region = image_view.region

	if x < 0 or x >= region.width then
		return image_view
	elseif y < 0 or y >= region.height then
		return image_view
	elseif z < 0 or z >= region.depth then
		return image_view
	end

	--- @diagnostic disable: invisible
	local pixel_format_size = image_view.pixel_format_size
	local offset = image_view.init_offset + ((z * image_view.image.width * image_view.image.height) + (y * image_view.image.width) + x) * pixel_format_size
	--- @diagnostic enable: invisible

	v3d.format_buffer_into(image_view.image.format, value, image_view.image, offset)

	return image_view
end

----------------------------------------------------------------

--- Copy the contents of an image view into a buffer.
--- * If no buffer is provided, a new buffer will be created. Regardless, the
---   buffer will be returned.
--- * If an offset is provided, the buffer will be written to from that offset.
---   For example, an offset of 1 will start writing at the second element of
---   the buffer.
---
--- This function can be used to read values from an image efficiently.
---
--- Note, the buffer will contain the unflattened values of the image's internal
--- data buffer. For example, if the image view's image format is a struct, the
--- buffer will contain tables with the field values for each pixel, e.g.
--- ```
--- {
--- 	{ r = 1, g = 2, b = 3 },
--- 	{ r = 4, g = 5, b = 6 },
--- }
--- ```
---
--- Buffer values will be depth-major, row-major, meaning the first value will
--- be the back-most, top-left pixel, the second value will be the pixel to the
--- right of that, and so on.
--- @param image_view V3DImageView
--- @param buffer table | nil
--- @param offset integer | nil
--- @return table
--- @v3d-nolog
--- @v3d-advanced
--- Offset must not be negative
--- @v3d-validate offset == nil or offset >= 0
--- local my_image = v3d.create_image(v3d.number(), 16, 16, 16, 42)
--- local my_image_view = v3d.image_view(my_image)
---
--- local buffer = v3d.image_view_buffer_into(my_image_view)
---
--- assert(buffer[1] == 42)
--- @v3d-example 4
--- local my_image = v3d.create_image(v3d.number(), 16, 16, 16, 42)
--- local my_image_view = v3d.image_view(my_image)
--- local my_buffer = {}
---
--- v3d.image_view_buffer_into(my_image_view, my_buffer)
---
--- assert(my_buffer[1] == 42)
--- @v3d-example 5
function v3d.image_view_buffer_into(image_view, buffer, offset)
	buffer = buffer or {}
	offset = offset or 0

	--- @diagnostic disable: invisible
	local pixel_format_size = image_view.pixel_format_size
	local row_end_delta = image_view.row_end_delta
	local layer_end_delta = image_view.layer_end_delta
	local image_offset = image_view.init_offset
	--- @diagnostic enable: invisible
	local region = image_view.region
	local image = image_view.image
	local image_format = image.format
	local region_width = region.width
	local region_height = region.height
	local buffer_index = offset + 1
	local v3d_format_unbuffer_from = v3d.format_unbuffer_from

	for _ = 1, region.depth do
		for _ = 1, region_height do
			for _ = 1, region_width do
				buffer[buffer_index] = v3d_format_unbuffer_from(image_format, image, image_offset)
				buffer_index = buffer_index + 1
				image_offset = image_offset + pixel_format_size
			end
			image_offset = image_offset + row_end_delta
		end
		image_offset = image_offset + layer_end_delta
	end

	return buffer
end

-- TODO: validate buffer contents as well
--- Copy the contents of a buffer into an image view. If no offset is provided,
--- the buffer will be read from the first element.
---
--- This function can be used to load values into an image efficiently.
---
--- The buffer must contain enough values to fill the region.
---
--- Note, the buffer must contain values compatible with the image's format and
--- will be flattened within the image's internal data buffer. For example, if
--- the image's format is a struct, the buffer must contain tables with the
--- field values for each pixel, e.g.
--- ```
--- {
--- 	{ r = 1, g = 2, b = 3 },
--- 	{ r = 4, g = 5, b = 6 },
--- }
--- ```
--- @param image_view V3DImageView
--- @param buffer table
--- @param offset integer | nil
--- @return V3DImageView
--- @v3d-chainable
--- @v3d-nolog
--- @v3d-advanced
--- Offset must not be negative
--- @v3d-validate offset == nil or offset >= 0
--- Buffer must contain enough values to fill the region
--- @v3d-validate #buffer - (offset or 0) >= image_view.region.width * image_view.region.height * image_view.region.depth
--- local my_image = v3d.create_image(v3d.number(), 2, 1, 1)
--- local my_image_view = v3d.image_view(my_image)
--- local my_buffer = { 1, 2 }
---
--- v3d.image_view_unbuffer_from(my_image_view, my_buffer)
---
--- assert(v3d.image_view_get_pixel(my_image_view, 0, 0, 0) == 1)
--- assert(v3d.image_view_get_pixel(my_image_view, 1, 0, 0) == 2)
--- @v3d-example 5
function v3d.image_view_unbuffer_from(image_view, buffer, offset)
	offset = offset or 0

	--- @diagnostic disable: invisible
	local image_offset = image_view.init_offset
	local row_end_delta = image_view.row_end_delta
	local layer_end_delta = image_view.layer_end_delta
	local pixel_format_size = image_view.pixel_format_size
	--- @diagnostic enable: invisible
	local image = image_view.image
	local region = image_view.region
	local image_format = image.format
	local region_width = image.width
	local region_height = image.height
	local buffer_index = offset + 1
	local v3d_format_buffer_into = v3d.format_buffer_into

	for _ = 1, region.depth do
		for _ = 1, region_height do
			for _ = 1, region_width do
				v3d_format_buffer_into(image_format, buffer[buffer_index], image, image_offset)
				buffer_index = buffer_index + 1
				image_offset = image_offset + pixel_format_size
			end
			image_offset = image_offset + row_end_delta
		end
		image_offset = image_offset + layer_end_delta
	end

	return image_view
end

-- TODO: !copy_into
-- TODO: !present_graphics
-- TODO: !present_subpixel

end ----------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Presentation ----------------------------------------------------------------
do -----------------------------------------------------------------------------

local CH_SPACE = string.byte ' '
local CH_0 = string.byte '0'
local CH_A = string.byte 'a'
local CH_SUBPIXEL_NOISEY = 149
local colour_byte_lookup = {}
local subpixel_code_ch_lookup = {}
local subpixel_code_fg_lookup = {}
local subpixel_code_bg_lookup = {}

do -- compute lookup tables above
	for i = 0, 15 do
		colour_byte_lookup[2 ^ i] = i < 10 and CH_0 + i or CH_A + (i - 10)
	end

	local function subpixel_byte_value(v0, v1, v2, v3, v4, v5)
		local b0 = v0 == v5 and 0 or 1
		local b1 = v1 == v5 and 0 or 1
		local b2 = v2 == v5 and 0 or 1
		local b3 = v3 == v5 and 0 or 1
		local b4 = v4 == v5 and 0 or 1

		return 128 + b0 + b1 * 2 + b2 * 4 + b3 * 8 + b4 * 16
	end

	local function eval_subpixel_lookups(ci0, ci1, ci2, ci3, ci4, ci5, subpixel_code)
		local colour_count = { [ci0] = 1 }
		local unique_colour_values = { ci0 }
		local unique_colours = 1

		for _, c in ipairs { ci1, ci2, ci3, ci4, ci5 } do
			if colour_count[c] then
				colour_count[c] = colour_count[c] + 1
			else
				colour_count[c] = 1
				unique_colours = unique_colours + 1
				unique_colour_values[unique_colours] = c
			end
		end

		table.sort(unique_colour_values, function(a, b)
			return colour_count[a] > colour_count[b]
		end)

		if unique_colours == 1 then -- these should never be used!
			subpixel_code_ch_lookup[subpixel_code] = false
			subpixel_code_fg_lookup[subpixel_code] = false
			subpixel_code_bg_lookup[subpixel_code] = false
			return
		end

		local colour_indices = { ci0, ci1, ci2, ci3, ci4, ci5 }
		local modal1_colour_index = unique_colour_values[1]
		local modal2_colour_index = unique_colour_values[2]
		local modal1_index = 0
		local modal2_index = 0

		for i = 1, 6 do
			if colour_indices[i] == modal1_colour_index then
				modal1_index = i
			end
			if colour_indices[i] == modal2_colour_index then
				modal2_index = i
			end
		end

		-- spatially map pixels!
		ci0 = (ci0 == modal1_colour_index or ci0 == modal2_colour_index) and ci0 or (ci1 == modal1_colour_index or ci1 == modal2_colour_index) and ci1 or ci2
		ci1 = (ci1 == modal1_colour_index or ci1 == modal2_colour_index) and ci1 or (ci0 == modal1_colour_index or ci0 == modal2_colour_index) and ci0 or ci3
		ci2 = (ci2 == modal1_colour_index or ci2 == modal2_colour_index) and ci2 or (ci3 == modal1_colour_index or ci3 == modal2_colour_index) and ci3 or ci4
		ci3 = (ci3 == modal1_colour_index or ci3 == modal2_colour_index) and ci3 or (ci2 == modal1_colour_index or ci2 == modal2_colour_index) and ci2 or ci5
		ci4 = (ci4 == modal1_colour_index or ci4 == modal2_colour_index) and ci4 or (ci5 == modal1_colour_index or ci5 == modal2_colour_index) and ci5 or ci2
		ci5 = (ci5 == modal1_colour_index or ci5 == modal2_colour_index) and ci5 or (ci4 == modal1_colour_index or ci4 == modal2_colour_index) and ci4 or ci3
		subpixel_code_ch_lookup[subpixel_code] = subpixel_byte_value(ci0, ci1, ci2, ci3, ci4, ci5)
		subpixel_code_fg_lookup[subpixel_code] = ci5 == modal1_colour_index and modal2_index or modal1_index
		subpixel_code_bg_lookup[subpixel_code] = ci5 == modal1_colour_index and modal1_index or modal2_index
	end

	local subpixel_code = 0
	for c5 = 0, 3 do
		for c4 = 0, 3 do
			for c3 = 0, 3 do
				for c2 = 0, 3 do
					for c1 = 0, 3 do
						for c0 = 0, 3 do
							eval_subpixel_lookups(c0, c1, c2, c3, c4, c5, subpixel_code)
							subpixel_code = subpixel_code + 1
						end
					end
				end
			end
		end
	end
end

----------------------------------------------------------------

--- A CC `term` object which can be presented to, for example the `term` API or
--- a `window` object.
--- @class CCTermObject
--- Standard `setCursorPos` function.
--- @field setCursorPos function
--- Standard `blit` function.
--- @field blit function
--- @v3d-structural

--- An extension of the normal ComputerCraft terminal which adds extra graphics
--- capabilities.
--- @class CraftOSPCTermObject
--- Standard `getGraphicsMode` function.
--- @field getGraphicsMode function
--- Standard `drawPixels` function.
--- @field drawPixels function
--- @v3d-structural

----------------------------------------------------------------

--- Present an image view to the terminal drawing subpixels to increase the
--- effective resolution of the terminal.
---
--- If specified, dx and dy will be used as the offset of the top-left pixel
--- when drawing, i.e. with an offset of (2, 1), the image will appear 2 to the
--- right and 1 down from the top-left of the terminal. These are 0-based and
--- both default to 0. A value of 0 means no offset.
---
--- @param image_view V3DImageView
--- @param term CCTermObject
--- @param dx integer | nil
--- @param dy integer | nil
--- @return V3DImageView
--- @v3d-chainable
--- Image view's image format must be compatible with `v3d.uinteger()`.
--- @v3d-validate v3d.format_is_compatible_with(image_view.image.format, v3d.uinteger())
--- Image view's depth must be 1.
--- @v3d-validate image_view.region.depth == 1
--- Image view's region must have a width and height that are multiples of 2 and
--- 3 respectively.
--- @v3d-validate image_view.region.width % 2 == 0 and image_view.region.height % 3 == 0
--- local term_width, term_height = term.getSize()
--- local my_image = v3d.create_image(v3d.uinteger(), term_width * 2, term_height * 3, 1)
--- local fill_region = {
--- 	x = 1, y = 1, z = 0,
--- 	width = 6, height = 6, depth = 1,
--- }
--- local my_image_view = v3d.image_view(my_image)
--- local my_image_region_view = v3d.image_view(my_image, fill_region)
---
--- v3d.image_view_fill(my_image_view, colours.white)
--- v3d.image_view_fill(my_image_region_view, colours.red)
---
--- -- Draw the image to `term.current()`
--- v3d.image_view_present_term_subpixel(my_image_view, term.current())
--- @v3d-example 11:12
function v3d.image_view_present_term_subpixel(image_view, term, dx, dy)
	dy = dy or 0

	local SUBPIXEL_WIDTH = 2
	local SUBPIXEL_HEIGHT = 3

	local x_blit = 1 + (dx or 0)

	--- @diagnostic disable-next-line: deprecated
	local table_unpack = table.unpack
	local string_char = string.char
	local term_blit = term.blit
	local term_setCursorPos = term.setCursorPos

	--- @diagnostic disable: invisible
	local i0 = image_view.init_offset + 1
	local next_pixel_delta = image_view.pixel_format_size
	local next_row_delta = image_view.region.width * image_view.pixel_format_size
	local row_end_delta = image_view.row_end_delta + next_row_delta * (SUBPIXEL_HEIGHT - 1)
	--- @diagnostic enable: invisible

	local colour_data = image_view.image
	local next_macro_pixel_delta = next_pixel_delta * SUBPIXEL_WIDTH
	local num_columns = image_view.region.width / SUBPIXEL_WIDTH
	local ch_t = {}
	local fg_t = {}
	local bg_t = {}

	for y_blit = 1 + dy, image_view.region.height / SUBPIXEL_HEIGHT + dy do
		for ix = 1, num_columns do
			local i1 = i0 + next_row_delta
			local i2 = i1 + next_row_delta
			local c00, c10 = colour_data[i0], colour_data[i0 + next_pixel_delta]
			local c01, c11 = colour_data[i1], colour_data[i1 + next_pixel_delta]
			local c02, c12 = colour_data[i2], colour_data[i2 + next_pixel_delta]

			-- I've considered turning this into a alrge decision tree to avoid
			-- the table accesses, however the tree is so large it would not be
			-- optimal.

			local unique_colour_lookup = { [c00] = 0 }
			local unique_colours = 1

			if c01 ~= c00 then
				unique_colour_lookup[c01] = unique_colours
				unique_colours = unique_colours + 1
			end
			if not unique_colour_lookup[c02] then
				unique_colour_lookup[c02] = unique_colours
				unique_colours = unique_colours + 1
			end
			if not unique_colour_lookup[c10] then
				unique_colour_lookup[c10] = unique_colours
				unique_colours = unique_colours + 1
			end
			if not unique_colour_lookup[c11] then
				unique_colour_lookup[c11] = unique_colours
				unique_colours = unique_colours + 1
			end
			if not unique_colour_lookup[c12] then
				unique_colour_lookup[c12] = unique_colours
				unique_colours = unique_colours + 1
			end

			if unique_colours == 2 then
				local other_colour = c02

					if c00 ~= c12 then other_colour = c00
				elseif c10 ~= c12 then other_colour = c10
				elseif c01 ~= c12 then other_colour = c01
				elseif c11 ~= c12 then other_colour = c11
				end

				local subpixel_ch = 128

				if c00 ~= c12 then subpixel_ch = subpixel_ch + 1 end
				if c10 ~= c12 then subpixel_ch = subpixel_ch + 2 end
				if c01 ~= c12 then subpixel_ch = subpixel_ch + 4 end
				if c11 ~= c12 then subpixel_ch = subpixel_ch + 8 end
				if c02 ~= c12 then subpixel_ch = subpixel_ch + 16 end

				ch_t[ix] = subpixel_ch
				fg_t[ix] = colour_byte_lookup[other_colour]
				bg_t[ix] = colour_byte_lookup[c12]
			elseif unique_colours == 1 then
				ch_t[ix] = CH_SPACE
				fg_t[ix] = CH_0
				bg_t[ix] = colour_byte_lookup[c00]
			elseif unique_colours > 4 then -- so random that we're gonna just give up lol
				ch_t[ix] = CH_SUBPIXEL_NOISEY
				fg_t[ix] = colour_byte_lookup[c01]
				bg_t[ix] = colour_byte_lookup[c00]
			else
				local colours = { c00, c10, c01, c11, c02, c12 }
				local subpixel_code = unique_colour_lookup[c12] * 1024
				                    + unique_colour_lookup[c02] * 256
				                    + unique_colour_lookup[c11] * 64
				                    + unique_colour_lookup[c01] * 16
				                    + unique_colour_lookup[c10] * 4
				                    + unique_colour_lookup[c00]

				ch_t[ix] = subpixel_code_ch_lookup[subpixel_code]
				fg_t[ix] = colour_byte_lookup[colours[subpixel_code_fg_lookup[subpixel_code]]]
				bg_t[ix] = colour_byte_lookup[colours[subpixel_code_bg_lookup[subpixel_code]]]
			end

			i0 = i0 + next_macro_pixel_delta
		end

		term_setCursorPos(x_blit, y_blit)
		term_blit(string_char(table_unpack(ch_t)), string_char(table_unpack(fg_t)), string_char(table_unpack(bg_t)))
		i0 = i0 + row_end_delta
	end

	return image_view
end

----------------------------------------------------------------

--- Present this image to the terminal utilising the graphics mode of
--- CraftOS-PC which has vastly superior resolution and colour depth.
---
--- If specified, dx and dy will be used as the offset of the top-left pixel
--- when drawing, i.e. with an offset of (2, 1), the image will appear 2 to the
--- right and 1 down from the top-left of the terminal. These are 0-based and
--- both default to 0. A value of 0 means no offset.
---
--- The `normalise` parameter specifies whether to normalise the image data
--- prior to rendering.
--- * If you are using power-of-two values such as `colours.red` to specify
---   image colours, this must be set to `true`.
--- * Otherwise, this must be set to `false`.
---
--- @param image_view V3DImageView
--- @param term CraftOSPCTermObject
--- @param normalise boolean
--- @param dx integer | nil
--- @param dy integer | nil
--- @return V3DImageView
--- @v3d-chainable
--- Image view's image format must be compatible with `v3d.uinteger()`.
--- @v3d-validate v3d.format_is_compatible_with(image_view.image.format, v3d.uinteger())
--- Image view's depth must be 1.
--- @v3d-validate image_view.region.depth == 1
--- Any graphics mode must be being used.
--- @v3d-validate term.getGraphicsMode()
--- local term_width, term_height = 720, 540
--- local image = v3d.create_image(v3d.uinteger(), term_width, term_height, 1)
--- local fill_region = {
--- 	x = 20, y = 20, z = 0,
--- 	width = 100, height = 100, depth = 1,
--- }
--- local image_view = v3d.image_view(image)
--- local image_region_view = v3d.image_view(image, fill_region)
---
--- v3d.image_view_fill(image_view, colours.white)
--- v3d.image_view_fill(image_region_view, colours.red)
---
--- term.setGraphicsMode(1)
--- v3d.image_present_graphics(image_view, term, true)
function v3d.image_view_present_graphics(image_view, term, normalise, dx, dy)
	local lines = {}
	local string_char = string.char
	local table_concat = table.concat
	local math_floor = math.floor
	local math_log = math.log
	local convert_pixel

	if normalise then
		convert_pixel = function(n) return math_floor(math_log(n + 0.5, 2)) end
	else
		convert_pixel = function(n) return n end
	end

	dx = dx or 0
	dy = dy or 0

	local n_columns = image_view.region.width
	local pixel_data = image_view.image

	--- @diagnostic disable: invisible
	local index = image_view.init_offset + 1
	local next_pixel_delta = image_view.pixel_format_size
	local row_end_delta = image_view.row_end_delta
	--- @diagnostic enable: invisible

	for y = 1, image_view.region.height do
		local line = {}

		for x = 1, n_columns do
			line[x] = string_char(convert_pixel(pixel_data[index]))
			index = index + next_pixel_delta
		end

		lines[y] = table_concat(line)
		index = index + row_end_delta
	end

	term.drawPixels(dx, dy, lines)

	return image_view
end

end ----------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Transforms ------------------------------------------------------------------
do -----------------------------------------------------------------------------

--- A transform is an object representing a transformation which can be applied
--- to 3D positions and directions. Transforms are capable of things like
--- translation, rotation, and scaling.
---
--- Internally, they represent the first 3 rows of a row-major 4x4 matrix. The
--- last row is dropped for performance reasons, but is assumed to be equal to
--- `[0, 0, 0, 1]` at all times.
--- @class V3DTransform
--- @v3d-untracked

--- Combine this transform with another, returning a transform which first
--- applies the 2nd transform, and then this one.
--- @param transform V3DTransform
--- @param other_transform V3DTransform
--- @return V3DTransform
--- @nodiscard
--- @v3d-nolog
--- @v3d-mt mul
--- local transform_a = v3d.identity()
--- local transform_b = v3d.identity()
---
--- local result = transform_a:combine(transform_b)
--- -- result is a transform which will first apply transform_b, then
--- -- transform_a
--- @v3d-example 4:6
--- local transform_a = v3d.identity()
--- local transform_b = v3d.identity()
---
--- local result = transform_a * transform_b
--- -- result is a transform which will first apply transform_b, then
--- -- transform_a
--- @v3d-example 4:6
function v3d.transform_combine(transform, other_transform)
	local t = _create_instance('V3DTransform')

	t[ 1] = transform[ 1] * other_transform[1] + transform[ 2] * other_transform[5] + transform[ 3] * other_transform[ 9]
	t[ 2] = transform[ 1] * other_transform[2] + transform[ 2] * other_transform[6] + transform[ 3] * other_transform[10]
	t[ 3] = transform[ 1] * other_transform[3] + transform[ 2] * other_transform[7] + transform[ 3] * other_transform[11]
	t[ 4] = transform[ 1] * other_transform[4] + transform[ 2] * other_transform[8] + transform[ 3] * other_transform[12] + transform[ 4]

	t[ 5] = transform[ 5] * other_transform[1] + transform[ 6] * other_transform[5] + transform[ 7] * other_transform[ 9]
	t[ 6] = transform[ 5] * other_transform[2] + transform[ 6] * other_transform[6] + transform[ 7] * other_transform[10]
	t[ 7] = transform[ 5] * other_transform[3] + transform[ 6] * other_transform[7] + transform[ 7] * other_transform[11]
	t[ 8] = transform[ 5] * other_transform[4] + transform[ 6] * other_transform[8] + transform[ 7] * other_transform[12] + transform[ 8]

	t[ 9] = transform[ 9] * other_transform[1] + transform[10] * other_transform[5] + transform[11] * other_transform[ 9]
	t[10] = transform[ 9] * other_transform[2] + transform[10] * other_transform[6] + transform[11] * other_transform[10]
	t[11] = transform[ 9] * other_transform[3] + transform[10] * other_transform[7] + transform[11] * other_transform[11]
	t[12] = transform[ 9] * other_transform[4] + transform[10] * other_transform[8] + transform[11] * other_transform[12] + transform[12]

	return _finalise_instance(t)
end

--- TODO
--- @param transform V3DTransform
--- @param n integer
--- @return V3DTransform
--- @nodiscard
--- @v3d-nolog
--- @v3d-mt pow
--- local transform_a = v3d.identity()
---
--- local result = v3d.transform_repeated(transform_a, 5)
--- -- result is a transform which will first apply transform_b, then
--- -- transform_a
--- @v3d-example 4:6
function v3d.transform_repeated(transform, n)
	local t = _create_instance('V3DTransform')

	for i = 1, n do
		t[ 1] = transform[ 1] * transform[1] + transform[ 2] * transform[5] + transform[ 3] * transform[ 9]
		t[ 2] = transform[ 1] * transform[2] + transform[ 2] * transform[6] + transform[ 3] * transform[10]
		t[ 3] = transform[ 1] * transform[3] + transform[ 2] * transform[7] + transform[ 3] * transform[11]
		t[ 4] = transform[ 1] * transform[4] + transform[ 2] * transform[8] + transform[ 3] * transform[12] + transform[ 4]

		t[ 5] = transform[ 5] * transform[1] + transform[ 6] * transform[5] + transform[ 7] * transform[ 9]
		t[ 6] = transform[ 5] * transform[2] + transform[ 6] * transform[6] + transform[ 7] * transform[10]
		t[ 7] = transform[ 5] * transform[3] + transform[ 6] * transform[7] + transform[ 7] * transform[11]
		t[ 8] = transform[ 5] * transform[4] + transform[ 6] * transform[8] + transform[ 7] * transform[12] + transform[ 8]

		t[ 9] = transform[ 9] * transform[1] + transform[10] * transform[5] + transform[11] * transform[ 9]
		t[10] = transform[ 9] * transform[2] + transform[10] * transform[6] + transform[11] * transform[10]
		t[11] = transform[ 9] * transform[3] + transform[10] * transform[7] + transform[11] * transform[11]
		t[12] = transform[ 9] * transform[4] + transform[10] * transform[8] + transform[11] * transform[12] + transform[12]

		-- TODO: broken
	end

	return _finalise_instance(t)
end

----------------------------------------------------------------

--- Apply this transformation to the data provided, returning the 3 numeric
--- values after the transformation.
---
--- `translate` determines whether the translation of the transformation will be
--- applied.
---
--- Offset specifies the offset within the data to transform the vertex. 0 means
--- no offset (uses indices 1, 2, and 3). Defaults to 0.
--- @param transform V3DTransform
--- @param data number[]
--- @param translate boolean
--- @param offset integer | nil
--- @return number, number, number
--- @nodiscard
--- @v3d-nolog
--- @v3d-mt call
--- local my_transform = v3d.translate(-1, -2, -3)
--- local my_data = { 1, 2, 3 }
---
--- local x, y, z = v3d.transform_apply(my_transform, my_data, false)
---
--- assert(x == 1)
--- assert(y == 2)
--- assert(z == 3)
--- @v3d-example 4
--- local my_transform = v3d.translate(-1, -2, -3)
--- local my_data = { 1, 2, 3, 4, 5, 6 }
---
--- local x, y, z = v3d.transform_apply(my_transform, my_data, true, 3)
---
--- assert(x == 3) -- 4 + -1
--- assert(y == 3) -- 5 + -2
--- assert(z == 3) -- 6 + -3
--- @v3d-example 4
--- local my_transform = v3d.identity()
--- local my_data = { 1, 2, 3 }
---
--- local x, y, z = my_transform(my_data, false)
---
--- assert(x == 1)
--- assert(y == 2)
--- assert(z == 3)
--- @v3d-example 4
function v3d.transform_apply(transform, data, translate, offset)
	offset = offset or 0

	local d1 = data[offset + 1]
	local d2 = data[offset + 2]
	local d3 = data[offset + 3]

	local r1 = transform[1] * d1 + transform[ 2] * d2 + transform[ 3] * d3
	local r2 = transform[5] * d1 + transform[ 6] * d2 + transform[ 7] * d3
	local r3 = transform[9] * d1 + transform[10] * d2 + transform[11] * d3

	if translate then
		r1 = r1 + transform[ 4]
		r2 = r2 + transform[ 8]
		r3 = r3 + transform[12]
	end

	return r1, r2, r3
end

----------------------------------------------------------------

-- --- TODO
-- --- @return v3d.Transform
-- --- @nodiscard
-- function v3d.Transform:inverse()
-- 	-- TODO: untested!
-- 	local tr_xx = self[1]
-- 	local tr_xy = self[2]
-- 	local tr_xz = self[3]
-- 	local tr_yx = self[5]
-- 	local tr_yy = self[6]
-- 	local tr_yz = self[7]
-- 	local tr_zx = self[9]
-- 	local tr_zy = self[10]
-- 	local tr_zz = self[11]

-- 	local inverse_det = 1/(tr_xx*(tr_yy*tr_zz-tr_zy*tr_yz)
-- 						-tr_xy*(tr_yx*tr_zz-tr_yz*tr_zx)
-- 						+tr_xz*(tr_yx*tr_zy-tr_yy*tr_zx))
-- 	local inverse_xx =  (tr_yy*tr_zz-tr_zy*tr_yz) * inverse_det
-- 	local inverse_xy = -(tr_xy*tr_zz-tr_xz*tr_zy) * inverse_det
-- 	local inverse_xz =  (tr_xy*tr_yz-tr_xz*tr_yy) * inverse_det
-- 	local inverse_yx = -(tr_yx*tr_zz-tr_yz*tr_zx) * inverse_det
-- 	local inverse_yy =  (tr_xx*tr_zz-tr_xz*tr_zx) * inverse_det
-- 	local inverse_yz = -(tr_xx*tr_yz-tr_yx*tr_xz) * inverse_det
-- 	local inverse_zx =  (tr_yx*tr_zy-tr_zx*tr_yy) * inverse_det
-- 	local inverse_zy = -(tr_xx*tr_zy-tr_zx*tr_xy) * inverse_det
-- 	local inverse_zz =  (tr_xx*tr_yy-tr_yx*tr_xy) * inverse_det

-- 	return v3d.translate(-self[4], -self[8], -self[12]):combine {
-- 		inverse_xx, inverse_xy, inverse_xz, 0,
-- 		inverse_yx, inverse_yy, inverse_yz, 0,
-- 		inverse_zx, inverse_zy, inverse_zz, 0,
-- 	}
-- end

----------------------------------------------------------------

--- Create a transform which has no effect.
--- @return V3DTransform
--- @v3d-constructor
--- @v3d-nolog
--- local my_vector = { 1, 2, 3 }
--- local my_transform = v3d.identity()
---
--- local x, y, z = v3d.transform_apply(my_transform, my_vector, true)
--- assert(x == 1)
--- assert(y == 2)
--- assert(z == 3)
--- @v3d-example 2
function v3d.identity()
	local t = _create_instance('V3DTransform')

	t[1] = 1
	t[2] = 0
	t[3] = 0
	t[4] = 0
	t[5] = 0
	t[6] = 1
	t[7] = 0
	t[8] = 0
	t[9] = 0
	t[10] = 0
	t[11] = 1
	t[12] = 0

	return _finalise_instance(t)
end

----------------------------------------------------------------

--- Create a transform which translates by the given amount.
--- @param dx number
--- @param dy number
--- @param dz number
--- @return V3DTransform
--- @v3d-constructor
--- @v3d-nolog
--- local my_vector = { 1, 2, 3 }
--- local my_transform = v3d.translate(1, 2, 3)
---
--- local x, y, z = v3d.transform_apply(my_transform, my_vector, true)
--- assert(x == 2)
--- assert(y == 4)
--- assert(z == 6)
--- @v3d-example 2
function v3d.translate(dx, dy, dz)
	local t = _create_instance('V3DTransform')

	t[1] = 1
	t[2] = 0
	t[3] = 0
	t[4] = dx
	t[5] = 0
	t[6] = 1
	t[7] = 0
	t[8] = dy
	t[9] = 0
	t[10] = 0
	t[11] = 1
	t[12] = dz

	return _finalise_instance(t)
end

----------------------------------------------------------------

--- Create a transform which scales by the given amount.
--- @param sx number
--- @param sy number
--- @param sz number
--- @return V3DTransform
--- @v3d-constructor
--- @v3d-nolog
--- local my_vector = { 1, 2, 3 }
--- local my_transform = v3d.scale(1, 2, 3)
---
--- local x, y, z = v3d.transform_apply(my_transform, my_vector, true)
--- assert(x == 1)
--- assert(y == 4)
--- assert(z == 9)
--- @v3d-example 2
function v3d.scale(sx, sy, sz)
	local t = _create_instance('V3DTransform')

	t[1] = sx
	t[2] = 0
	t[3] = 0
	t[4] = 0
	t[5] = 0
	t[6] = sy
	t[7] = 0
	t[8] = 0
	t[9] = 0
	t[10] = 0
	t[11] = sz
	t[12] = 0

	return _finalise_instance(t)
end

--- Create a transform which scales all values by the given amount.
--- @param scale number
--- @return V3DTransform
--- @v3d-constructor
--- @v3d-nolog
--- local my_vector = { 1, 2, 3 }
--- local my_transform = v3d.scale_all(2)
---
--- local x, y, z = v3d.transform_apply(my_transform, my_vector, true)
--- assert(x == 2)
--- assert(y == 4)
--- assert(z == 6)
--- @v3d-example 2
function v3d.scale_all(scale)
	return v3d.scale(scale, scale, scale)
end

----------------------------------------------------------------

--- Create a transform which rotates `theta` radians counter-clockwise around
--- the X axis.
--- @param theta number
--- @return V3DTransform
--- @v3d-constructor
--- @v3d-nolog
--- local my_vector = { 1, 2, 3 }
--- local my_transform = v3d.rotate_x(math.pi / 2)
---
--- local x, y, z = v3d.transform_apply(my_transform, my_vector, true)
--- assert(math.abs(x - 1) < 0.0001) -- tolerate precision errors
--- assert(math.abs(y - -3) < 0.0001)
--- assert(math.abs(z - 2) < 0.0001)
--- @v3d-example 2
function v3d.rotate_x(theta)
	local t = _create_instance('V3DTransform')

	local cos_theta = math_cos(theta)
	local sin_theta = math_sin(theta)

	t[1] = 1
	t[2] = 0
	t[3] = 0
	t[4] = 0
	t[5] = 0
	t[6] = cos_theta
	t[7] = -sin_theta
	t[8] = 0
	t[9] = 0
	t[10] = sin_theta
	t[11] = cos_theta
	t[12] = 0

	return _finalise_instance(t)
end

--- Create a transform which rotates `theta` radians counter-clockwise around
--- the Y axis.
--- @param theta number
--- @return V3DTransform
--- @v3d-constructor
--- @v3d-nolog
--- local my_vector = { 1, 2, 3 }
--- local my_transform = v3d.rotate_y(math.pi / 2)
---
--- local x, y, z = v3d.transform_apply(my_transform, my_vector, true)
--- assert(math.abs(x - 3) < 0.0001) -- tolerate precision errors
--- assert(math.abs(y - 2) < 0.0001)
--- assert(math.abs(z - -1) < 0.0001)
--- @v3d-example 2
function v3d.rotate_y(theta)
	local t = _create_instance('V3DTransform')

	local cos_theta = math_cos(theta)
	local sin_theta = math_sin(theta)

	t[1] = cos_theta
	t[2] = 0
	t[3] = sin_theta
	t[4] = 0
	t[5] = 0
	t[6] = 1
	t[7] = 0
	t[8] = 0
	t[9] = -sin_theta
	t[10] = 0
	t[11] = cos_theta
	t[12] = 0

	return _finalise_instance(t)
end

--- Create a transform which rotates `theta` radians counter-clockwise around
--- the Z axis.
--- @param theta number
--- @return V3DTransform
--- @v3d-constructor
--- @v3d-nolog
--- local my_vector = { 1, 2, 3 }
--- local my_transform = v3d.rotate_z(math.pi / 2)
---
--- local x, y, z = v3d.transform_apply(my_transform, my_vector, true)
--- assert(math.abs(x - -2) < 0.0001) -- tolerate precision errors
--- assert(math.abs(y - 1) < 0.0001)
--- assert(math.abs(z - 3) < 0.0001)
--- @v3d-example
function v3d.rotate_z(theta)
	local t = _create_instance('V3DTransform')

	local cos_theta = math_cos(theta)
	local sin_theta = math_sin(theta)

	t[1] = cos_theta
	t[2] = -sin_theta
	t[3] = 0
	t[4] = 0
	t[5] = sin_theta
	t[6] = cos_theta
	t[7] = 0
	t[8] = 0
	t[9] = 0
	t[10] = 0
	t[11] = 1
	t[12] = 0

	return _finalise_instance(t)
end

-- TODO: no idea if this actually works, but thanks Copilot!
--- Create a transform which rotates `theta` radians counter-clockwise around
--- the given axis.
--- @param theta number
--- @param ax number
--- @param ay number
--- @param az number
--- @return V3DTransform
--- @v3d-constructor
--- @v3d-nolog
--- local my_transform = v3d.rotate(math.pi / 2, 1, 0, 0)
--- @v3d-example
function v3d.rotate(theta, ax, ay, az)
	local t = _create_instance('V3DTransform')

	local cos_theta = math_cos(theta)
	local sin_theta = math_sin(theta)
	local one_minus_cos_theta = 1 - cos_theta

	t[1] = cos_theta + ax * ax * one_minus_cos_theta
	t[2] = ax * ay * one_minus_cos_theta - az * sin_theta
	t[3] = ax * az * one_minus_cos_theta + ay * sin_theta
	t[4] = 0
	t[5] = ay * ax * one_minus_cos_theta + az * sin_theta
	t[6] = cos_theta + ay * ay * one_minus_cos_theta
	t[7] = ay * az * one_minus_cos_theta - ax * sin_theta
	t[8] = 0
	t[9] = az * ax * one_minus_cos_theta - ay * sin_theta
	t[10] = az * ay * one_minus_cos_theta + ax * sin_theta
	t[11] = cos_theta + az * az * one_minus_cos_theta
	t[12] = 0

	return _finalise_instance(t)
end

----------------------------------------------------------------

--- Settings for a virtual camera used with `v3d.camera` to create a
--- corresponding transform.
--- @class V3DCameraSettings
--- Translation of the camera along the X axis. Defaults to 0.
--- @field x number | nil
--- Translation of the camera along the Y axis. Defaults to 0.
--- @field y number | nil
--- Translation of the camera along the Z axis. Defaults to 0.
--- @field z number | nil
--- Counter-clockwise rotation of the camera around the X axis, in radians.
--- Defaults to 0.
--- @field pitch number | nil
--- Counter-clockwise rotation of the camera around the Y axis, in radians.
--- Defaults to 0.
--- @field yaw number | nil
--- Counter-clockwise rotation of the camera around the Z axis, in radians.
--- Defaults to 0.
--- @field roll number | nil
--- Angle between the topmost and bottommost pixels of the image, in radians.
--- Defaults to 60 degrees.
--- @field fov number | nil
--- @v3d-structural
--- FOV must be less than 180 degrees.
--- @v3d-validate self.fov == nil or self.fov < math.pi
--- FOV must be greater than 0.
--- @v3d-validate self.fov == nil or self.fov > 0

-- TODO: untested
--- Create a transform which represents a virtual camera.
---
--- The camera is positioned at the origin, and looks down the negative Z axis.
--- @param settings V3DCameraSettings | nil
--- @return V3DTransform
--- @v3d-constructor
--- @v3d-nolog
--- local my_transform = v3d.camera {
--- 	x = 1, y = 2, z = 3,
--- 	pitch = x_rotation, -- how "up" we're looking
--- 	yaw = y_rotation, -- how "left" we're looking
--- 	roll = 0,
--- }
--- @v3d-example
function v3d.camera(settings)
	local x = settings and settings.x or 0
	local y = settings and settings.y or 0
	local z = settings and settings.z or 0
	local pitch = settings and settings.pitch or 0
	local yaw = settings and settings.yaw or 0
	local roll = settings and settings.roll or 0
	local fov = settings and settings.fov or math_pi / 3
	local tan_inverse = 1 / math_tan(fov / 2)

	return v3d.transform_combine(
		v3d.transform_combine(
			v3d.scale(tan_inverse, tan_inverse, 1),
			v3d.transform_combine(
				v3d.transform_combine(
					v3d.rotate_z(-roll),
					v3d.rotate_x(-pitch)
				),
				v3d.rotate_y(-yaw)
			)
		),
		v3d.translate(-x, -y, -z)
	)
end

----------------------------------------------------------------

--- Create a transform from raw values.
--- @param values number[]
--- @return V3DTransform
--- @v3d-constructor
--- @v3d-nolog
--- Values must contain exactly 12 elements.
--- @v3d-validate #values == 12
--- local my_transform = v3d.transform_from_values {
--- 	1, 0, 0, 0,
--- 	0, 1, 0, 0,
--- 	0, 0, 1, 0,
--- }
--- @v3d-example
function v3d.transform_from_values(values)
	local t = _create_instance('V3DTransform')

	for i = 1, 12 do
		t[i] = values[i]
	end

	return _finalise_instance(t)
end

end ----------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Geometry --------------------------------------------------------------------
do -----------------------------------------------------------------------------

--- A geometry builder is an intermediate object which can be used to create a
--- geometry instance. It's not efficient and cannot be used to render, but
--- allows the construction of arbitrary geometry instances from code, for
--- example for programmatically generated shapes.
---
--- Each face should be accompanied by 3 vertices.
--- @class V3DGeometryBuilder
--- Number of vertices stored in the geometry builder.
--- @field n_vertices integer
--- Number of faces stored in the geometry builder.
--- @field n_faces integer
--- Format of data stored per-vertex.
--- @field vertex_format V3DFormat
--- Format of data stored per-face.
--- @field face_format V3DFormat
--- @field private vertices any[]
--- @field private faces any[]
--- @v3d-untracked

--- A geometry instance is an immutable collection of vertices and indices which
--- can be rendered.
--- @class V3DGeometry
--- Offset of the first vertex within the geometry's internal data buffer.
--- @field vertex_offset integer
--- Stride between vertices within the geometry's internal data buffer.
--- @field vertex_stride integer
--- Stride between faces within the geometry's internal data buffer.
--- @field face_stride integer
--- Number of vertices stored in the geometry.
--- @field n_vertices integer
--- Number of faces stored in the geometry.
--- @field n_faces integer
--- Format of data stored per-vertex.
--- @field vertex_format V3DFormat
--- Format of data stored per-face.
--- @field face_format V3DFormat

----------------------------------------------------------------

--- Add a vertex to the geometry builder.
--- @param builder V3DGeometryBuilder
--- @param vertex any
--- @return V3DGeometryBuilder
--- @v3d-advanced
--- @v3d-chainable
--- @v3d-nolog
--- Vertex must be an instance of the builder's vertex format.
--- @v3d-validate v3d.format_is_instance(builder.vertex_format, vertex)
function v3d.geometry_builder_add_vertex(builder, vertex)
	builder.n_vertices = builder.n_vertices + 1
	--- @diagnostic disable-next-line: invisible
	builder.vertices[builder.n_vertices] = vertex

	return builder
end

--- Add a face to the geometry builder.
--- @param builder V3DGeometryBuilder
--- @param face any
--- @return V3DGeometryBuilder
--- @v3d-advanced
--- @v3d-chainable
--- @v3d-nolog
--- Face must be an instance of the builder's face format.
--- @v3d-validate v3d.format_is_instance(builder.face_format, face)
function v3d.geometry_builder_add_face(builder, face)
	builder.n_faces = builder.n_faces + 1
	--- @diagnostic disable-next-line: invisible
	builder.faces[builder.n_faces] = face

	return builder
end

--- Set a vertex in the geometry builder.
--- @param builder V3DGeometryBuilder
--- @param index integer
--- @param vertex any
--- @return V3DGeometryBuilder
--- @v3d-advanced
--- @v3d-chainable
--- @v3d-nolog
--- Index must be within the range of vertices in the builder.
--- @v3d-validate index >= 1 and index <= builder.n_vertices
--- Vertex must be an instance of the builder's vertex format.
--- @v3d-validate v3d.format_is_instance(builder.vertex_format, vertex)
function v3d.geometry_builder_set_vertex(builder, index, vertex)
	--- @diagnostic disable-next-line: invisible
	builder.vertices[index] = vertex

	return builder
end

--- Set a face in the geometry builder.
--- @param builder V3DGeometryBuilder
--- @param index integer
--- @param face any
--- @return V3DGeometryBuilder
--- @v3d-advanced
--- @v3d-chainable
--- @v3d-nolog
--- Index must be within the range of faces in the builder.
--- @v3d-validate index >= 1 and index <= builder.n_faces
--- Face must be an instance of the builder's face format.
--- @v3d-validate v3d.format_is_instance(builder.face_format, face)
function v3d.geometry_builder_set_face(builder, index, face)
	--- @diagnostic disable-next-line: invisible
	builder.faces[index] = face

	return builder
end

--- Remove a vertex from the geometry builder.
--- @param builder V3DGeometryBuilder
--- @param index integer
--- @return V3DGeometryBuilder
--- @v3d-advanced
--- @v3d-chainable
--- @v3d-nolog
--- Index must be within the range of vertices in the builder.
--- @v3d-validate index >= 1 and index <= builder.n_vertices
function v3d.geometry_builder_remove_vertex(builder, index)
	--- @diagnostic disable-next-line: invisible
	local vertices = builder.vertices
	local n_vertices = builder.n_vertices

	for i = index, n_vertices - 1 do
		vertices[i] = vertices[i + 1]
	end

	vertices[n_vertices] = nil
	builder.n_vertices = n_vertices - 1

	return builder
end

--- Remove a face from the geometry builder.
--- @param builder V3DGeometryBuilder
--- @param index integer
--- @return V3DGeometryBuilder
--- @v3d-advanced
--- @v3d-chainable
--- @v3d-nolog
--- Index must be within the range of faces in the builder.
--- @v3d-validate index >= 1 and index <= builder.n_faces
function v3d.geometry_builder_remove_face(builder, index)
	--- @diagnostic disable-next-line: invisible
	local faces = builder.faces
	local n_faces = builder.n_faces

	for i = index, n_faces - 1 do
		faces[i] = faces[i + 1]
	end

	faces[n_faces] = nil
	builder.n_faces = n_faces - 1

	return builder
end

----------------------------------------------------------------

-- TODO: add validation for map function
--- Replace every vertex in this builder using the given map function. The
--- return value may differ from the builder's vertex format but must match the
--- new vertex format. The builder's vertex format will be replaced with the new
--- vertex format.
--- @param builder V3DGeometryBuilder
--- @param new_vertex_format V3DFormat
--- @param map function
--- @return V3DGeometryBuilder
--- @v3d-advanced
--- @v3d-chainable
--- @v3d-nolog
function v3d.geometry_builder_map_vertices(builder, new_vertex_format, map)
	--- @diagnostic disable-next-line: invisible
	local vertices = builder.vertices

	for i = 1, builder.n_vertices do
		vertices[i] = map(vertices[i])
	end

	--- @diagnostic disable-next-line: invisible
	builder.vertices = vertices
	builder.vertex_format = new_vertex_format

	return builder
end

-- TODO: add validation for map function
--- Replace every face in this builder using the given map function. The return
--- value may differ from the builder's face format but must match the new face
--- format. The builder's face format will be replaced with the new face format.
--- @param builder V3DGeometryBuilder
--- @param new_face_format V3DFormat
--- @param map function
--- @return V3DGeometryBuilder
--- @v3d-advanced
--- @v3d-chainable
--- @v3d-nolog
function v3d.geometry_builder_map_faces(builder, new_face_format, map)
	--- @diagnostic disable-next-line: invisible
	local faces = builder.faces

	for i = 1, builder.n_faces do
		faces[i] = map(faces[i])
	end

	--- @diagnostic disable-next-line: invisible
	builder.faces = faces
	builder.face_format = new_face_format

	return builder
end

----------------------------------------------------------------

--- Append the faces and vertices from another builder to this one.
--- @param builder V3DGeometryBuilder
--- @param other V3DGeometryBuilder
--- @return V3DGeometryBuilder
--- @v3d-chainable
--- @v3d-nolog
--- @v3d-mt concat
--- The other builder's vertex format must be compatible with this one's.
--- @v3d-validate v3d.format_is_compatible_with(other.vertex_format, builder.vertex_format)
--- The other builder's face format must be compatible with this one's.
--- @v3d-validate v3d.format_is_compatible_with(other.face_format, builder.face_format)
function v3d.geometry_builder_concat(builder, other)
	--- @diagnostic disable-next-line: invisible
	local vertices = builder.vertices
	--- @diagnostic disable-next-line: invisible
	local faces = builder.faces
	local n_vertices = builder.n_vertices
	local n_faces = builder.n_faces

	for i = 1, other.n_vertices do
		n_vertices = n_vertices + 1
		--- @diagnostic disable-next-line: invisible
		vertices[n_vertices] = other.vertices[i]
	end

	for i = 1, other.n_faces do
		n_faces = n_faces + 1
		--- @diagnostic disable-next-line: invisible
		faces[n_faces] = other.faces[i]
	end

	builder.n_vertices = n_vertices
	builder.n_faces = n_faces

	return builder
end

----------------------------------------------------------------

--- Create a new geometry builder.
--- @param vertex_format V3DFormat
--- @param face_format V3DFormat
--- @return V3DGeometryBuilder
--- @v3d-advanced
--- @v3d-constructor
--- @v3d-nolog
--- @v3d-nomethod
function v3d.create_geometry_builder(vertex_format, face_format)
	local b = _create_instance('V3DGeometryBuilder')

	b.n_vertices = 0
	b.n_faces = 0
	b.vertex_format = vertex_format
	b.face_format = face_format

	--- @diagnostic disable: invisible
	b.vertices = {}
	b.faces = {}
	--- @diagnostic enable: invisible

	return _finalise_instance(b)
end

--- Create a new geometry instance from the given builder.
--- @param builder V3DGeometryBuilder
--- @param label string | nil
--- @return V3DGeometry
--- @v3d-constructor
function v3d.geometry_builder_build(builder, label)
	local g = _create_instance('V3DGeometry', label)

	g.vertex_offset = builder.n_faces * v3d.format_size(builder.face_format)
	g.vertex_stride = v3d.format_size(builder.vertex_format)
	g.face_stride = v3d.format_size(builder.face_format)
	g.n_vertices = builder.n_vertices
	g.n_faces = builder.n_faces
	g.vertex_format = builder.vertex_format
	g.face_format = builder.face_format

	local offset = 0
	for i = 1, builder.n_faces do
		--- @diagnostic disable-next-line: invisible
		v3d.format_buffer_into(builder.face_format, builder.faces[i], g, offset)
		offset = offset + g.face_stride
	end
	for i = 1, builder.n_vertices do
		--- @diagnostic disable-next-line: invisible
		v3d.format_buffer_into(builder.vertex_format, builder.vertices[i], g, offset)
		offset = offset + g.vertex_stride
	end

	return _finalise_instance(g)
end

--- Create a new geometry builder from the given geometry instance.
--- @param geometry V3DGeometry
--- @return V3DGeometryBuilder
--- @v3d-constructor
--- @v3d-nolog
function v3d.geometry_to_builder(geometry)
	local b = _create_instance('V3DGeometryBuilder')

	b.n_vertices = geometry.n_vertices
	b.n_faces = geometry.n_faces
	b.vertex_format = geometry.vertex_format
	b.face_format = geometry.face_format

	local index = 1
	for i = 1, geometry.n_faces do
		--- @diagnostic disable-next-line: invisible
		b.faces[i] = v3d.format_unbuffer_from(geometry.face_format, geometry, index)
		index = index + geometry.face_stride
	end
	for i = 1, geometry.n_vertices do
		--- @diagnostic disable-next-line: invisible
		b.vertices[i] = v3d.format_unbuffer_from(geometry.vertex_format, geometry, index)
		index = index + geometry.vertex_stride
	end

	return _finalise_instance(b)
end

----------------------------------------------------------------

--- @class V3DDebugCuboidOptions
--- X coordinate of the cuboid's centre. Defaults to 0.
--- @field x number | nil
--- Y coordinate of the cuboid's centre. Defaults to 0.
--- @field y number | nil
--- Z coordinate of the cuboid's centre. Defaults to 0.
--- @field z number | nil
--- Width of the cuboid. Defaults to 1.
--- @field width number | nil
--- Height of the cuboid. Defaults to 1.
--- @field height number | nil
--- Depth of the cuboid. Defaults to 1.
--- @field depth number | nil
--- Whether to include normals in the geometry. Defaults to false. If set to
--- 'vertex', the normals will be stored only in the vertex data. If set to
--- 'face', the normals will be stored only in the face data.
--- @field include_normals 'vertex' | 'face' | boolean | nil
--- @field include_uvs boolean | nil
--- Whether to include indices in the geometry. Defaults to false. If set to
--- 'vertex', the indices will be stored only in the vertex data. If set to
--- 'face', the indices will be stored only in the face data.
--- @field include_indices 'vertex' | 'face' | boolean | nil
--- Whether to include face names in the geometry. Defaults to false.
--- @field include_face_name boolean | nil
--- Whether to include polygon (triangle) indices in the geometry. Defaults to
--- false.
--- @field include_poly_index boolean | nil
--- Width must not be negative.
--- @v3d-validate self.width == nil or self.width >= 0
--- Height must not be negative.
--- @v3d-validate self.height == nil or self.height >= 0
--- Depth must not be negative.
--- @v3d-validate self.depth == nil or self.depth >= 0
--- @v3d-structural

--- Create a debug cuboid geometry builder.
---
--- Its vertex format will be a struct containing the following fields (if enabled
--- according to options):
--- * `position`: `v3d.struct { x = v3d.number(), y = v3d.number(), z = v3d.number() }`
--- * `normal`: `v3d.struct { x = v3d.number(), y = v3d.number(), z = v3d.number() }` (only if `include_normals` is true or 'vertex')
--- * `index`: `v3d.uinteger()` (only if `include_indices` is true or 'vertex')
---
--- Its face format will be a struct containing the following fields (if enabled
--- according to options):
--- * `normal`: `v3d.struct { x = v3d.number(), y = v3d.number(), z = v3d.number() }` (only if `include_normals` is true or 'face')
--- * `index`: `v3d.uinteger()` (only if `include_indices` is true or 'face')
--- * `name`: `v3d.string()` (only if `include_face_name` is true)
--- * `poly_index`: `v3d.uinteger()` (only if `include_poly_index` is true)
--- @param options V3DDebugCuboidOptions | nil
--- @return V3DGeometryBuilder
--- @v3d-constructor
--- @v3d-nolog
function v3d.debug_cuboid(options)
	options = options or {}

	local vec3 = v3d.struct {
		x = v3d.number(),
		y = v3d.number(),
		z = v3d.number(),
	}
	local vertex_format = v3d.struct {
		position = vec3,
		normal = (options.include_normals == true or options.include_normals == 'vertex') and vec3 or nil,
		uv = (options.include_uvs == true) and v3d.struct { u = v3d.number(), v = v3d.number() } or nil,
		index = (options.include_indices == true or options.include_indices == 'vertex') and v3d.uinteger() or nil,
	}

	local face_format = v3d.struct {
		normal = (options.include_normals == true or options.include_normals == 'face') and vec3 or nil,
		index = (options.include_indices == true or options.include_indices == 'face') and v3d.uinteger() or nil,
		name = options.include_face_name and v3d.string() or nil,
		poly_index = options.include_poly_index and v3d.uinteger() or nil,
	}

	local builder = v3d.create_geometry_builder(vertex_format, face_format)

	local x = options.x or 0
	local y = options.y or 0
	local z = options.z or 0
	local w = options.width or 1
	local h = options.height or 1
	local d = options.depth or 1

	local function _add_face(name, normal, index, poly_index)
		local face = {}

		if options.include_face_name then
			face.name = name
		end
		if options.include_normals == true or options.include_normals == 'face' then
			face.normal = normal
		end
		if options.include_indices == true or options.include_indices == 'face' then
			face.index = index
		end
		if options.include_poly_index then
			face.poly_index = poly_index
		end

		v3d.geometry_builder_add_face(builder, face)
	end

	local function _add_vertex(x, y, z, normal, u, v, index)
		local vertex = {
			position = { x = x, y = y, z = z },
		}

		if options.include_normals == true or options.include_normals == 'vertex' then
			vertex.normal = normal
		end
		if options.include_uvs == true then
			vertex.uv = { u = u, v = v }
		end
		if options.include_indices == true or options.include_indices == 'vertex' then
			vertex.index = index
		end

		v3d.geometry_builder_add_vertex(builder, vertex)
	end

	local front_normal = { x = 0, y = 0, z = 1 }
	local front_index = 0
	_add_vertex(x - w / 2, y + h / 2, z + d / 2, front_normal, 0, 0, 0)
	_add_vertex(x - w / 2, y - h / 2, z + d / 2, front_normal, 0, 1, 1)
	_add_vertex(x + w / 2, y - h / 2, z + d / 2, front_normal, 1, 1, 2)
	_add_face('front', front_normal, front_index, 0)
	_add_vertex(x + w / 2, y - h / 2, z + d / 2, front_normal, 1, 1, 3)
	_add_vertex(x + w / 2, y + h / 2, z + d / 2, front_normal, 1, 0, 4)
	_add_vertex(x - w / 2, y + h / 2, z + d / 2, front_normal, 0, 0, 5)
	_add_face('front', front_normal, front_index, 1)

	local back_normal = { x = 0, y = 0, z = -1 }
	local back_index = 1
	_add_vertex(x - w / 2, y + h / 2, z - d / 2, back_normal, 1, 0, 6)
	_add_vertex(x + w / 2, y + h / 2, z - d / 2, back_normal, 0, 0, 7)
	_add_vertex(x + w / 2, y - h / 2, z - d / 2, back_normal, 0, 1, 8)
	_add_face('back', back_normal, back_index, 2)
	_add_vertex(x + w / 2, y - h / 2, z - d / 2, back_normal, 0, 1, 9)
	_add_vertex(x - w / 2, y - h / 2, z - d / 2, back_normal, 1, 1, 10)
	_add_vertex(x - w / 2, y + h / 2, z - d / 2, back_normal, 1, 0, 11)
	_add_face('back', back_normal, back_index, 3)

	local left_normal = { x = -1, y = 0, z = 0 }
	local left_index = 2
	_add_vertex(x - w / 2, y + h / 2, z - d / 2, left_normal, 0, 0, 12)
	_add_vertex(x - w / 2, y - h / 2, z - d / 2, left_normal, 0, 1, 13)
	_add_vertex(x - w / 2, y - h / 2, z + d / 2, left_normal, 1, 1, 14)
	_add_face('left', left_normal, left_index, 4)
	_add_vertex(x - w / 2, y - h / 2, z + d / 2, left_normal, 1, 1, 15)
	_add_vertex(x - w / 2, y + h / 2, z + d / 2, left_normal, 1, 0, 16)
	_add_vertex(x - w / 2, y + h / 2, z - d / 2, left_normal, 0, 0, 17)
	_add_face('left', left_normal, left_index, 5)

	local right_normal = { x = 1, y = 0, z = 0 }
	local right_index = 3
	_add_vertex(x + w / 2, y + h / 2, z + d / 2, right_normal, 0, 0, 18)
	_add_vertex(x + w / 2, y - h / 2, z + d / 2, right_normal, 0, 1, 19)
	_add_vertex(x + w / 2, y - h / 2, z - d / 2, right_normal, 1, 1, 20)
	_add_face('right', right_normal, right_index, 6)
	_add_vertex(x + w / 2, y - h / 2, z - d / 2, right_normal, 1, 1, 21)
	_add_vertex(x + w / 2, y + h / 2, z - d / 2, right_normal, 1, 0, 22)
	_add_vertex(x + w / 2, y + h / 2, z + d / 2, right_normal, 0, 0, 23)
	_add_face('right', right_normal, right_index, 7)

	local top_normal = { x = 0, y = 1, z = 0 }
	local top_index = 4
	_add_vertex(x - w / 2, y + h / 2, z - d / 2, top_normal, 0, 0, 24)
	_add_vertex(x - w / 2, y + h / 2, z + d / 2, top_normal, 0, 1, 25)
	_add_vertex(x + w / 2, y + h / 2, z + d / 2, top_normal, 1, 1, 26)
	_add_face('top', top_normal, top_index, 8)
	_add_vertex(x + w / 2, y + h / 2, z + d / 2, top_normal, 1, 1, 27)
	_add_vertex(x + w / 2, y + h / 2, z - d / 2, top_normal, 1, 0, 28)
	_add_vertex(x - w / 2, y + h / 2, z - d / 2, top_normal, 0, 0, 29)
	_add_face('top', top_normal, top_index, 9)

	local bottom_normal = { x = 0, y = -1, z = 0 }
	local bottom_index = 5
	_add_vertex(x - w / 2, y - h / 2, z + d / 2, bottom_normal, 0, 0, 30)
	_add_vertex(x - w / 2, y - h / 2, z - d / 2, bottom_normal, 0, 1, 31)
	_add_vertex(x + w / 2, y - h / 2, z - d / 2, bottom_normal, 1, 1, 32)
	_add_face('bottom', bottom_normal, bottom_index, 10)
	_add_vertex(x + w / 2, y - h / 2, z - d / 2, bottom_normal, 1, 1, 33)
	_add_vertex(x + w / 2, y - h / 2, z + d / 2, bottom_normal, 1, 0, 34)
	_add_vertex(x - w / 2, y - h / 2, z + d / 2, bottom_normal, 0, 0, 35)
	_add_face('bottom', bottom_normal, bottom_index, 11)

	return builder
end

end ----------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Shaders ---------------------------------------------------------------------
do -----------------------------------------------------------------------------

--- Name of an external variable for a shader.
--- @alias V3DExternalVariableName string
--- Uniform names must be valid Lua identifiers
--- @v3d-validate self:match '^[%a_][%w_]*$'

--- @class V3DShaderOptions
--- @field source_format V3DFormat | nil
--- Format of face data within geometry accessible to this shader. If nil, face
--- data will not be accessible from within shader source code.
--- @field face_format V3DFormat | nil
--- @field image_formats { [string]: V3DFormat }
--- @field code string | string[]
--- @field constants { [string]: any } | nil
--- @field label string | nil
--- @v3d-structural
--- At least one image format must be provided
--- @v3d-validate next(self.image_formats)

--- @class V3DShader
--- Code with variable expansions replaced by their actual values, as outlined
--- below.
---
--- Note: refer to the `uses_*` fields to determine which variables are used in
--- the shader code.
---
--- Variable expansion | Example | Replacement
--- :-|:-|:-
--- `v3d_constant` | `v3d_constant.<xyz>` | `_v3d_shader_constant_<xyz>`
--- `v3d_external` | `v3d_external.<xyz>` | `_v3d_shader_external_<xyz>`
--- `v3d_face` | `v3d_face.<lens>` | `_v3d_shader_face_<lens_offset_0>, ..., _v3d_shader_face_<lens_offset_N>`
--- `v3d_src_depth` | `v3d_src_depth` | `_v3d_shader_src_depth`
--- `v3d_src_absolute_normal` (all) | `v3d_src_absolute_normal` | `_v3d_shader_src_abs_norm_x, _v3d_shader_src_abs_norm_y, _v3d_shader_src_abs_norm_z`
--- `v3d_src_absolute_normal` (component) | `v3d_src_absolute_normal.x` | `_v3d_shader_src_abs_norm_x`
--- `v3d_src_absolute_pos` (all) | `v3d_src_absolute_pos` | `v3d_shader_src_abs_pos_x, _v3d_shader_src_abs_pos_y, _v3d_shader_src_abs_pos_z`
--- `v3d_src_absolute_pos` (component) | `v3d_src_absolute_pos.x` | `v3d_shader_src_abs_pos_x`
--- `v3d_src_pos` (all) | `v3d_src_pos` | `_v3d_shader_src_pos_x, _v3d_shader_src_pos_y, _v3d_shader_src_pos_z`
--- `v3d_src_pos` (component) | `v3d_src_pos.x` | `_v3d_shader_src_pos_x`
--- `v3d_src` | `v3d_src.<lens>` | `_v3d_shader_src_<lens_offset_0>, ..., _v3d_shader_src_<lens_offset_N>`
--- `v3d_dst_absolute_pos` (all) | `v3d_dst_absolute_pos` | `_v3d_shader_dst_abs_pos_x, _v3d_shader_dst_abs_pos_y, _v3d_shader_dst_abs_pos_z`
--- `v3d_dst_absolute_pos` (component) | `v3d_dst_absolute_pos.x` | `_v3d_shader_dst_abs_pos_x`
--- `v3d_dst_pos` (all) | `v3d_dst_pos.<image>` | `_v3d_shader_dst_pos_<image>_x, _v3d_shader_dst_pos_<image>_y, _v3d_shader_dst_pos_<image>_z`
--- `v3d_dst_pos` (component) | `v3d_dst_pos.<image>.x` | `_v3d_shader_dst_pos_<image>_x`
--- `v3d_dst` | `v3d_dst.<image>.<lens>` | `_v3d_shader_image_<image>[_v3d_shader_dst_base_offset_<image>_<lens_offset_0>], ..., _v3d_shader_image_<image>[_v3d_shader_dst_base_offset_<image>_<lens_offset_N>]`
--- `v3d_image` | `v3d_image.<image>` | `_v3d_shader_image_<image>`
--- `v3d_image_view` | `v3d_image_view.<image>` | `_v3d_shader_image_view_<image>`
--- @field expanded_code string
--- @field source_format V3DFormat | nil
--- @field face_format V3DFormat | nil
--- @field image_formats { [string]: V3DFormat }
--- @field uses_shader_constants string[]
--- @field uses_external_variables string[]
--- @field uses_face_offsets number[]
--- @field uses_source_depth boolean
--- @field uses_source_absolute_normal_x boolean
--- @field uses_source_absolute_normal_y boolean
--- @field uses_source_absolute_normal_z boolean
--- @field uses_source_absolute_position_x boolean
--- @field uses_source_absolute_position_y boolean
--- @field uses_source_absolute_position_z boolean
--- @field uses_source_position_x boolean
--- @field uses_source_position_y boolean
--- @field uses_source_position_z boolean
--- @field uses_source_offsets number[]
--- @field uses_destination_absolute_position_x string[]
--- @field uses_destination_absolute_position_y string[]
--- @field uses_destination_absolute_position_z string[]
--- @field uses_destination_position_x string[]
--- @field uses_destination_position_y string[]
--- @field uses_destination_position_z string[]
--- @field uses_destination_base_offsets string[]
--- @field uses_images string[]
--- @field uses_image_views string[]
--- @field private shader_constants table
--- @field private external_variables { [string]: any }

--- @class V3DShaderError
--- @field message string
--- @field line number
--- @field column number
--- @field length number
--- @v3d-structural

--- @class V3DShaderErrors
--- @field options V3DShaderOptions
--- @field errors V3DShaderError[]
--- @field code_lines string[]
--- @v3d-untracked
--- @v3d-validate #self.errors > 0
--- There is at least one error

----------------------------------------------------------------

--- @class _V3DShaderRawVariableMethodContext
--- @field name string
--- @field parameters string[]
--- @field pre_line string

--- @class _V3DShaderRawVariableRef
--- @field line number
--- @field column number
--- @field name string
--- @field repr string
--- @field indices string[]
--- @field method _V3DShaderRawVariableMethodContext | nil

local allowed_with_methods = { v3d_constant = true }

--- @param str string
--- @return string[]
local function _split_commas(str)
	local s = 1
	local escaped = false
	local closers = {}
	local parts = {}

	for i = 1, #str do
		local ch = string.sub(str, i, i)
		if escaped then
			-- do nothing
		elseif ch == closers[#closers] then
			table.remove(closers, #closers)
		elseif ch == '\\' then
			escaped = true
		elseif ch == ',' and #closers == 0 then
			table.insert(parts, string.sub(str, s, i - 1))
			s = i + 1
		elseif ch == '\'' or ch == '\"' then
			table.insert(closers, ch)
		elseif ch == '(' then
			table.insert(closers, ')')
		elseif ch == '[' then
			table.insert(closers, ']')
		elseif ch == '{' then
			table.insert(closers, '}')
		end
	end

	table.insert(parts, string.sub(str, s))

	return parts
end

--- @param code string
--- @return _V3DShaderRawVariableRef[], string
local function _parse_shader(code)
	local line_number = 1
	local next_variable_index = 0
	--- @type _V3DShaderRawVariableRef[]
	local variables = {}
	local lines = {}

	local function accept_line(line, column_offset)
		local offset = 1
		local line_length = #line
		local transformed_line = ''
		while offset <= line_length do
			local v3d_offset = string.find(line, 'v3d_', offset, true)
			if not v3d_offset then
				transformed_line = transformed_line .. string.sub(line, offset)
				break
			end

			if string.sub(line, v3d_offset - 1, v3d_offset - 1):find '[%w_]' then
				transformed_line = transformed_line .. string.sub(line, offset, v3d_offset)
				offset = v3d_offset + 1
			else
				transformed_line = transformed_line .. string.sub(line, offset, v3d_offset - 1)

				local v3d_variable_name = string.match(line, '^v3d_[%w_]*', v3d_offset)
				offset = v3d_offset + #v3d_variable_name

				local indices = {}
				while string.find(line, '^%.[%w_]', offset) do
					local index = string.match(line, '^%.([%w_]+)', offset)
					table.insert(indices, index)
					offset = offset + 1 + #index
				end

				local method = nil
				if allowed_with_methods[v3d_variable_name] and string.find(line, ':[%w_]+%b()', offset) then
					local method_name, parameters = string.match(line, '^:([%w_]+)(%b())', offset)
					local method_parameters = _split_commas(accept_line(parameters:sub(2, -2), offset + 1 + #method_name + 1))
					method = {
						name = method_name,
						parameters = method_parameters,
						pre_line = transformed_line,
					}
					transformed_line = ''
					offset = offset + 1 + #method_name + #parameters
				end

				local repr = '$r' .. next_variable_index
				next_variable_index = next_variable_index + 1
				transformed_line = transformed_line .. repr

				table.insert(variables, {
					line = line_number,
					column = column_offset + v3d_offset,
					name = v3d_variable_name,
					repr = repr,
					indices = indices,
					method = method,
				})
			end
		end

		return transformed_line
	end

	for line in string.gmatch(code, '[^\n]+') do
		lines[line_number] = accept_line(line, 0)
		line_number = line_number + 1
	end

	return variables, table.concat(lines, "\n")
end

--------------------------------------------------------------------------------

--- Variable | Type | Mutability | Description
--- :-|:-|:-|:-
--- `v3d_constant` | `table` | `readonly` | Table containing shader options expanded as constants where possible.
--- `v3d_external` | `table` | `readwrite` | Table containing variables provided externally.
--- `v3d_face` | `face_format` | `readonly` | Polygon-specific values. For rasterization, this provides access to face attributes. For other contexts, this contains no data.
--- `v3d_src_depth` | `num` | `readonly` | Depth of the pixel. For rasterization, this is the depth of the pixel being drawn relative to the camera. For other contexts, this is equal to 0.
--- `v3d_src_absolute_normal` | `vec3` | `readonly` | Context dependent.
--- `v3d_src_absolute_pos` | `vec3` | `readonly` | Context dependent.
--- `v3d_src_pos` | `vec3` | `readonly` | Context dependent.
--- `v3d_src` | `source_format` | `readonly` | Context dependent.
--- `v3d_dst_absolute_pos` | `{ [string]: vec3 }` | `readonly` | Context dependent.
--- `v3d_dst_pos` | `{ [string]: vec3 }` | `readonly` | Context dependent.
--- `v3d_dst` | `image_formats` | `readwrite` | Context dependent.
--- `v3d_image` | `{ [string]: V3DImage }` | `readonly` | Get an image object by name.
--- `v3d_image_view` | `{ [string]: V3DImageView }` | `readonly` | Get an image view object by name.
---
--- Example: local p = v3d_constant.palette:lookup(v3d_src.colour)
--- @param options V3DShaderOptions
--- @return V3DShader | V3DShaderErrors
--- @v3d-constructor
function v3d.shader(options)
	local raw_code = options.code
	local constants = options.constants or {}

	if type(raw_code) == 'table' then
		raw_code = table.concat(raw_code, '\n')
	end

	local shader_object = _create_instance('V3DShader', options.label)
	--- @diagnostic disable-next-line: invisible
	shader_object.shader_constants = constants
	--- @diagnostic disable-next-line: invisible
	shader_object.external_variables = {}
	shader_object.source_format = options.source_format
	shader_object.face_format = options.face_format
	shader_object.image_formats = options.image_formats
	shader_object.uses_shader_constants = {}
	shader_object.uses_external_variables = {}
	shader_object.uses_face_offsets = {}
	shader_object.uses_source_depth = false
	shader_object.uses_source_absolute_normal_x = false
	shader_object.uses_source_absolute_normal_y = false
	shader_object.uses_source_absolute_normal_z = false
	shader_object.uses_source_absolute_position_x = false
	shader_object.uses_source_absolute_position_y = false
	shader_object.uses_source_absolute_position_z = false
	shader_object.uses_source_position_x = false
	shader_object.uses_source_position_y = false
	shader_object.uses_source_position_z = false
	shader_object.uses_source_offsets = {}
	shader_object.uses_destination_absolute_position_x = {}
	shader_object.uses_destination_absolute_position_y = {}
	shader_object.uses_destination_absolute_position_z = {}
	shader_object.uses_destination_position_x = {}
	shader_object.uses_destination_position_y = {}
	shader_object.uses_destination_position_z = {}
	shader_object.uses_destination_base_offsets = {}
	shader_object.uses_images = {}
	shader_object.uses_image_views = {}

	local code_substitutions = {}

	local variables, parsed_code = _parse_shader(raw_code)

	----------------------------------------------------------------------------

	local errors = {}
	local error_lookup = {}
	local function create_error(line, column, length, message)
		local msg_key = message .. ' (line ' .. line .. ', column ' .. column .. ')'
		if not error_lookup[msg_key] then
			table.insert(errors, {
				message = message,
				line = line,
				column = column,
				length = length,
			})
			error_lookup[msg_key] = true
		end
	end

	------------------------------------------------------------

	local function insert_if_not_present(t, value)
		for i = 1, #t do
			if t[i] == value then
				return
			end
		end
		table.insert(t, value)
	end

	local function guard_no_indexing(fn)
		return function(var)
			if #var.indices > 0 then
				create_error(var.line, var.column, #var.name, var.name .. ' cannot be indexed')
				return
			end

			fn(var)
		end
	end

	local function guard_image_first_index(fn)
		return function(var)
			local image_name = var.indices[1]
			if not image_name then
				create_error(var.line, var.column, #var.name, var.name .. ' requires an image name')
				return
			end

			local image_format = options.image_formats[image_name]
			if not image_format then
				create_error(var.line, var.column + #var.name + 1, #image_name, 'image \'' .. image_name .. '\' does not exist')
				return
			end

			fn(var, image_name, image_format)
		end
	end

	local function simple_xyz_handler(uses_prefix, subst_prefix)
		return function(var)
			if #var.indices > 1 then
				local s = var.name .. '.' .. table.concat(var.indices, '.')
				create_error(var.line, var.column, #s, s .. ' does not exist')
				return
			end

			local referenced_component = var.indices[1]
			if referenced_component and referenced_component ~= 'x' and referenced_component ~= 'y' and referenced_component ~= 'z' then
				create_error(var.line, var.column + #var.name + 1, #referenced_component, 'invalid component \'' .. referenced_component .. '\'')
				return
			end

			local substitution_parts = {}
			for _, component in ipairs { 'x', 'y', 'z' } do
				if not referenced_component or referenced_component == component then
					shader_object[uses_prefix .. component] = true
					table.insert(substitution_parts, subst_prefix .. component)
				end
			end

			code_substitutions[var.repr] = table.concat(substitution_parts, ', ')
		end
	end

	local function image_xyz_handler(uses_prefix, subst_prefix)
		return guard_image_first_index(function(var, image_name)
			local referenced_component = var.indices[2]

			if #var.indices > 2 then
				local length = #table.concat(var.indices, '.') - #image_name - 1 - #referenced_component
				create_error(var.line, var.column + #var.name + 1 + #image_name + 1 + #referenced_component, length, 'unexpected indices')
				return
			end

			if referenced_component and referenced_component ~= 'x' and referenced_component ~= 'y' and referenced_component ~= 'z' then
				create_error(var.line, var.column + #var.name + 1 + #image_name + 1, #referenced_component, 'invalid component \'' .. referenced_component .. '\'')
				return
			end

			local substitution_parts = {}

			for _, component in ipairs { 'x', 'y', 'z' } do
				if not referenced_component or referenced_component == component then
					shader_object[uses_prefix .. component] = shader_object[uses_prefix .. component] or {}
					insert_if_not_present(shader_object[uses_prefix .. component], image_name)
					table.insert(substitution_parts, subst_prefix .. image_name .. '_' .. component)
				end
			end

			code_substitutions[var.repr] = table.concat(substitution_parts, ', ')
		end)
	end

	------------------------------------------------------------

	local expansion_handlers = {}

	function expansion_handlers.v3d_constant(var)
		local shader_constant_name = var.indices[1]
		if not shader_constant_name then
			create_error(var.line, var.column, #var.name, var.name .. ' requires a variable name')
			return
		end

		local cst = constants[shader_constant_name]
		local cst_type = type(cst)

		if cst_type == 'nil' or cst_type == 'boolean' or cst_type == 'number' then
			if var.method then
				create_error(
					var.line, var.column + #var.name + 1 + #shader_constant_name + 1,
					#var.method.name, 'method \'' .. var.method.name .. '\' does not exist on ' .. cst_type .. ' constant')
				return
			end
			code_substitutions[var.repr] = tostring(cst)
			return
		elseif cst_type == 'string' then
			local subst = _v3d_quote_string(cst)
			if var.method then
				subst = var.method.pre_line .. 'string.' .. var.method.name .. '(' .. subst .. ', ' .. table.concat(var.method.parameters, ',') .. ')'
			end
			code_substitutions[var.repr] = subst
			return
		elseif cst_type == 'table' and var.method and cst['embed_' .. var.method.name] then
			local embed = cst['embed_' .. var.method.name](cst, table.unpack(var.method.parameters))
				:gsub('$return', var.method.pre_line)
			code_substitutions[var.repr] = embed
			return
		end

		local subst = '_v3d_shader_constant_' .. shader_constant_name

		if var.method then
			subst = var.method.pre_line .. subst .. ':' .. var.method.name .. '(' .. table.concat(var.method.parameters, ',') .. ')'
		end

		insert_if_not_present(shader_object.uses_shader_constants, shader_constant_name)
		code_substitutions[var.repr] = subst
	end

	function expansion_handlers.v3d_external(var)
		local external_variable_name = var.indices[1]
		if not external_variable_name then
			create_error(var.line, var.column, #var.name, var.name .. ' requires a variable name')
			return
		end

		insert_if_not_present(shader_object.uses_external_variables, external_variable_name)
		code_substitutions[var.repr] = '_v3d_shader_external_' .. external_variable_name
	end

	function expansion_handlers.v3d_face(var)
		if not options.face_format then
			create_error(var.line, var.column, #var.name, var.name .. ' used but face_format not provided')
			return
		end

		local lens = v3d.format_lens(options.face_format, var.indices)
		if not lens then
			local s = var.name .. '.' .. table.concat(var.indices, '.')
			create_error(var.line, var.column, #s, s .. ' does not exist')
			return
		end

		local size = v3d.format_size(lens.out_format)
		local substitution_parts = {}
		for attr = lens.offset, lens.offset + size - 1 do
			insert_if_not_present(shader_object.uses_face_offsets, attr)
			table.insert(substitution_parts, '_v3d_shader_face_' .. attr)
		end

		code_substitutions[var.repr] = table.concat(substitution_parts, ', ')
	end

	expansion_handlers.v3d_src_depth = guard_no_indexing(function(var)
		shader_object.uses_source_depth = true
		code_substitutions[var.repr] = '_v3d_shader_src_depth'
	end)

	expansion_handlers.v3d_src_absolute_normal = simple_xyz_handler('uses_source_absolute_normal_', '_v3d_shader_src_abs_norm_')
	expansion_handlers.v3d_src_absolute_pos = simple_xyz_handler('uses_source_absolute_position_', '_v3d_shader_src_abs_pos_')
	expansion_handlers.v3d_src_pos = simple_xyz_handler('uses_source_position_', '_v3d_shader_src_pos_')

	function expansion_handlers.v3d_src(var)
		if not options.source_format then
			create_error(var.line, var.column, #var.name, 'v3d_src used but source_format not provided')
			return
		end

		local lens = v3d.format_lens(options.source_format, var.indices)
		if not lens then
			local s = 'v3d_src.' .. table.concat(var.indices, '.')
			create_error(var.line, var.column, #s, s .. ' does not exist')
			return
		end

		local size = v3d.format_size(lens.out_format)
		local substitution_parts = {}
		for attr = lens.offset, lens.offset + size - 1 do
			insert_if_not_present(shader_object.uses_source_offsets, attr)
			table.insert(substitution_parts, '_v3d_shader_src_' .. attr)
		end

		code_substitutions[var.repr] = table.concat(substitution_parts, ', ')
	end

	expansion_handlers.v3d_dst_absolute_pos = image_xyz_handler('uses_destination_absolute_position_', '_v3d_shader_dst_abs_pos_')
	expansion_handlers.v3d_dst_pos = image_xyz_handler('uses_destination_position_', '_v3d_shader_dst_pos_')

	expansion_handlers.v3d_dst = guard_image_first_index(function(var, image_name, image_format)
		local indices = {}
		for i = 2, #var.indices do
			table.insert(indices, var.indices[i])
		end

		local lens = v3d.format_lens(image_format, indices)
		if not lens then
			local s = 'v3d_dst.' .. image_name .. '.' .. table.concat(indices, '.')
			create_error(var.line, var.column, #s, s .. ' does not exist')
			return
		end

		insert_if_not_present(shader_object.uses_destination_base_offsets, image_name)
		insert_if_not_present(shader_object.uses_images, image_name)

		local size = v3d.format_size(lens.out_format)
		local substitution_parts = {}
		for attr = lens.offset, lens.offset + size - 1 do
			local index_repr = '_v3d_shader_dst_base_offset_' .. image_name .. ' + ' .. (attr + 1)
			local repr = '_v3d_shader_image_' .. image_name .. '[' .. index_repr .. ']'
			table.insert(substitution_parts, repr)
		end

		code_substitutions[var.repr] = table.concat(substitution_parts, ', ')
	end)

	expansion_handlers.v3d_image = guard_image_first_index(function(var, image_name)
		if #var.indices > 1 then
			local length = #table.concat(var.indices, '.') - #image_name
			create_error(var.line, var.column + #var.name + 1 + #image_name, length, 'unexpected indices')
			return
		end

		insert_if_not_present(shader_object.uses_images, image_name)
		code_substitutions[var.repr] = '_v3d_shader_image_' .. image_name
	end)

	expansion_handlers.v3d_image_view = guard_image_first_index(function(var, image_name)
		if #var.indices > 1 then
			local length = #table.concat(var.indices, '.') - #image_name
			create_error(var.line, var.column + #var.name + 1 + #image_name, length, 'unexpected indices')
			return
		end

		insert_if_not_present(shader_object.uses_image_views, image_name)
		code_substitutions[var.repr] = '_v3d_shader_image_view_' .. image_name
	end)

	----------------------------------------------------------------------------

	for i = 1, #variables do
		local var = variables[i]
		local fn = expansion_handlers[var.name]

		if fn then
			fn(var)
		else
			create_error(var.line, var.column, #var.name, 'unknown variable expansion \'' .. var.name .. '\'')
		end
	end

	if #errors > 0 then
		local e = _create_instance('V3DShaderErrors')
		e.options = options
		e.errors = errors
		e.code_lines = _v3d_normalise_code_lines(raw_code)
		return _finalise_instance(e)
	end

	local code_lines = _v3d_normalise_code_lines(parsed_code
		:gsub('$%w+', code_substitutions)
		:gsub('$%w+', code_substitutions)) -- twice to account for method refs embedding weird things

	shader_object.expanded_code = table.concat(code_lines, '\n')

	return _finalise_instance(shader_object)
end

--- @param shader V3DShader
--- @param name V3DExternalVariableName
--- @param value any
--- @return V3DShader
function v3d.shader_set_variable(shader, name, value)
	--- @diagnostic disable-next-line: invisible
	shader.external_variables[name] = value
	return shader
end

--- @param shader V3DShader
--- @param name V3DExternalVariableName
--- @return any
function v3d.shader_get_variable(shader, name)
	--- @diagnostic disable-next-line: invisible
	return shader.external_variables[name]
end

end ----------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Renderer --------------------------------------------------------------------
do -----------------------------------------------------------------------------

--- A renderer is a compiled, optimised function dedicated to rendering pixels
--- to one or more images. Renderers are incredibly versatile, supporting 2D or
--- 3D rasterization with customisable per-pixel behaviour.
--- @class V3DRenderer
--- Options that the renderer was created with.
--- @field created_options V3DRendererOptions
--- Options that the renderer is using, accounting for default values.
--- @field used_options V3DRendererOptions
--- @field pixel_shader V3DShader
--- @field private compiled_source string
--- @v3d-abstract

----------------------------------------------------------------

-- TODO: init_shader, vertex_shader, finish_shader
-- TODO: validations
--- Miscellaneous options used when creating a renderer.
--- @class V3DRendererOptions
--- @field pixel_shader V3DShader
--- Lens pointing to a 3-component/4-component number part of vertices. Must be
--- applicable to the vertex format.
--- @field position_lens V3DLens | nil
--- Specify a face to cull (not draw), or false to disable face culling.
--- Defaults to 'back'. This is a technique to improve performance and should
--- only be changed from the default when doing something weird. For example, to
--- not draw faces facing towards the camera, use `cull_face = 'front'`.
--- @field cull_faces 'front' | 'back' | false | nil
--- Aspect ratio of the pixels being drawn. For square pixels, this should be 1.
--- For non-square pixels, like the ComputerCraft non-subpixel characters, this
--- should be their width/height, for example 2/3 for non-subpixel characters.
--- Defaults to `1`.
--- @field pixel_aspect_ratio number | nil
--- Whether to reverse the horizontal iteration order when drawing rows of
--- horizontal pixels. If true, the X value will decrease from right to left as
--- each row is drawn. Defaults to false.
--- TODO: not yet implemented
--- @field reverse_horizontal_iteration boolean | nil
--- Whether to reverse the vertical iteration order when drawing rows of
--- horizontal pixels. If true, the Y value will decrease from bottom to top as
--- each row is drawn. Defaults to false.
--- TODO: not yet implemented
--- @field reverse_vertical_iteration boolean | nil
--- If true, the v3d_event macro will be enabled in shaders and timings will be
--- recorded. This may incur a performance penalty depending on the macro's
--- usage. Defaults to false, however v3debug will default this to true.
--- @field record_statistics boolean | nil
--- Label to assign to the renderer.
--- @field label string | nil
--- @v3d-structural
--- Pixel shader must have a source format
--- @v3d-validate self.pixel_shader.source_format ~= nil

-- TODO: culled_faces?
--- Statistics related to renderer execution, recorded per-execution.
--- @class V3DRendererStatistics
--- Total durations for each timer, including the time spent in any nested
--- timers. Timer names are defined by the renderer's source code but include
--- 'parents', e.g. a nested timer will have a name like 'a/b'.
--- @field timers { [string]: number }
--- Number of times an event was recorded.
--- @field events { [string]: integer }
--- @v3d-untracked

----------------------------------------------------------------

-- TODO: validations
--- @param renderer V3DRenderer
--- @param geometry V3DGeometry
--- @param views { [string]: V3DImageView }
--- @param transform V3DTransform | nil
--- @param model_transform V3DTransform | nil
--- @param viewport V3DImageRegion | nil
--- @return V3DRendererStatistics
--- @v3d-generated
--- @v3d-constructor
function v3d.renderer_render(renderer, geometry, views, transform, model_transform, viewport)
	-- Generated at runtime based on renderer settings.
	--- @diagnostic disable-next-line: missing-return
end

local _BASE_RENDERER_ENVIRONMENT = {}
do

function _BASE_RENDERER_ENVIRONMENT.get_event_counter_local_variable(name)
	return '_v3d_event_counter_' .. name
end

function _BASE_RENDERER_ENVIRONMENT.get_timer_start_local_variable(name)
	return '_v3d_timer_start_' .. name:gsub('[^%w_]', '_')
end

function _BASE_RENDERER_ENVIRONMENT.get_timer_local_variable(name)
	return '_v3d_timer_total_' .. name:gsub('[^%w_]', '_')
end

function _BASE_RENDERER_ENVIRONMENT.v3d_event(...)
	-- TODO
	return ""
end

_BASE_RENDERER_ENVIRONMENT._RENDERER_RENDER_MAIN = [[
local _v3d_create_instance, _v3d_finalise_instance = ...
return function(_v3d_renderer, _v3d_geometry, _v3d_views, _v3d_transform, _v3d_model_transform, _v3d_viewport)
	{! start_timer('render') !}

	{! _RENDERER_INIT !}

	local _v3d_vertex_offset = _v3d_geometry.vertex_offset + 1
	local _v3d_face_offset = 1
	for _ = 1, _v3d_geometry.n_vertices, 3 do
		{! _RENDERER_RENDER_FACE !}
	end

	{! stop_timer('render') !}

	{! _RENDERER_RETURN_STATISTICS !}
end
]]

_BASE_RENDERER_ENVIRONMENT._RENDERER_INIT = [[
-- Viewport --------------------------------------------------------------------
local _v3d_viewport_width, _v3d_viewport_height
local _v3d_viewport_min_x, _v3d_viewport_max_x
local _v3d_viewport_min_y, _v3d_viewport_max_y

do
	{% local any_image_name = next(_ENV.options.pixel_shader.image_formats) %}
	local any_view = _v3d_views[{= quote(any_image_name) =}]
	if _v3d_viewport then
		_v3d_viewport_width = _v3d_viewport.width
		_v3d_viewport_height = _v3d_viewport.height
		_v3d_viewport_min_x = math.max(0, -_v3d_viewport.x)
		_v3d_viewport_min_y = math.max(0, -_v3d_viewport.y)
		_v3d_viewport_max_x = math.min(_v3d_viewport.width, _v3d_viewport_min_x + any_view.width) - 1
		_v3d_viewport_max_y = math.min(_v3d_viewport.height, _v3d_viewport_min_y + any_view.height) - 1
	else
		_v3d_viewport_width = any_view.region.width
		_v3d_viewport_height = any_view.region.height
		_v3d_viewport_min_x = 0
		_v3d_viewport_min_y = 0
		_v3d_viewport_max_x = _v3d_viewport_width - 1
		_v3d_viewport_max_y = _v3d_viewport_height - 1
	end
end

local _v3d_viewport_translate_scale_x = (_v3d_viewport_width - 1) * 0.5
local _v3d_viewport_translate_scale_y = (_v3d_viewport_height - 1) * 0.5
{% if options.pixel_aspect_ratio ~= 1 then %}
local _v3d_aspect_ratio_reciprocal = _v3d_viewport_height / _v3d_viewport_width / {= options.pixel_aspect_ratio =}
{% else %}
local _v3d_aspect_ratio_reciprocal = _v3d_viewport_height / _v3d_viewport_width
{% end %}

-- Image data ------------------------------------------------------------------
{% for _, image_name in ipairs(_ENV.options.pixel_shader.uses_image_views) do %}
local _v3d_shader_image_view_{= image_name =} = _v3d_views.{= image_name =}
{% end %}

{% for _, image_name in ipairs(_ENV.options.pixel_shader.uses_images) do %}
local _v3d_shader_image_{= image_name =} = _v3d_views.{= image_name =}.image
{% end %}

-- Image view base offsets -----------------------------------------------------
{% for _, view_name in ipairs(_ENV.options.pixel_shader.uses_destination_base_offsets) do %}
local _v3d_view_init_offset_{= view_name =} = _v3d_views.{= view_name =}.init_offset
local _v3d_image_width_{= view_name =} = _v3d_views.{= view_name =}.image.width
{% end %}

-- Shader constants ------------------------------------------------------------
{% for _, name in ipairs(_ENV.options.pixel_shader.uses_shader_constants) do %}
local _v3d_shader_constant_{= name =}
{% end %}
{% if #_ENV.options.pixel_shader.uses_shader_constants > 0 then %}
do
	local _v3d_shader_constants = _v3d_renderer.used_options.pixel_shader.shader_constants
	{% for _, name in ipairs(_ENV.options.pixel_shader.uses_shader_constants) do %}
		_v3d_shader_constant_{= name =} = _v3d_shader_constants[{= quote(name) =}]
	{% end %}
end
{% end %}

-- External variables ----------------------------------------------------------
{% for _, name in ipairs(_ENV.options.pixel_shader.uses_external_variables) do %}
local _v3d_shader_external_{= name =}
{% end %}
{% if #_ENV.options.pixel_shader.uses_external_variables > 0 then %}
do
	local _v3d_external_variables = _v3d_renderer.used_options.pixel_shader.external_variables
	{% for _, name in ipairs(_ENV.options.pixel_shader.uses_external_variables) do %}
	_v3d_shader_external_{= name =} = _v3d_external_variables[{= quote(name) =}]
	{% end %}
end
{% end %}

-- Statistics ------------------------------------------------------------------
{% if options.record_statistics then %}
	{% for _, counter_name in ipairs(_ENV.event_counters_updated) do %}
local {= get_event_counter_local_variable(counter_name) =} = 0
	{% end %}

	{% if #_ENV.timers_updated > 0 then %}
local _v3d_timer_now
	{% end %}

	{% for _, timer_name in ipairs(_ENV.timers_updated) do %}
local {= get_timer_local_variable(timer_name) =} = 0
	{% end %}
{% end %}

-- Transforms ------------------------------------------------------------------
{% if _ENV.needs_source_absolute_position then %}
local _v3d_model_transform_xx
local _v3d_model_transform_xy
local _v3d_model_transform_xz
local _v3d_model_transform_dx
local _v3d_model_transform_yx
local _v3d_model_transform_yy
local _v3d_model_transform_yz
local _v3d_model_transform_dy
local _v3d_model_transform_zx
local _v3d_model_transform_zy
local _v3d_model_transform_zz
local _v3d_model_transform_dz
if _v3d_model_transform then
	_v3d_model_transform_xx = _v3d_model_transform[ 1]
	_v3d_model_transform_xy = _v3d_model_transform[ 2]
	_v3d_model_transform_xz = _v3d_model_transform[ 3]
	_v3d_model_transform_dx = _v3d_model_transform[ 4]
	_v3d_model_transform_yx = _v3d_model_transform[ 5]
	_v3d_model_transform_yy = _v3d_model_transform[ 6]
	_v3d_model_transform_yz = _v3d_model_transform[ 7]
	_v3d_model_transform_dy = _v3d_model_transform[ 8]
	_v3d_model_transform_zx = _v3d_model_transform[ 9]
	_v3d_model_transform_zy = _v3d_model_transform[10]
	_v3d_model_transform_zz = _v3d_model_transform[11]
	_v3d_model_transform_dz = _v3d_model_transform[12]
end
{% else %}
-- TODO: implement this properly
if _v3d_model_transform then
	_v3d_transform = _v3d_transform:combine(_v3d_model_transform)
end
{% end %}

local _v3d_transform_xx = _v3d_transform[ 1]
local _v3d_transform_xy = _v3d_transform[ 2]
local _v3d_transform_xz = _v3d_transform[ 3]
local _v3d_transform_dx = _v3d_transform[ 4]
local _v3d_transform_yx = _v3d_transform[ 5]
local _v3d_transform_yy = _v3d_transform[ 6]
local _v3d_transform_yz = _v3d_transform[ 7]
local _v3d_transform_dy = _v3d_transform[ 8]
local _v3d_transform_zx = _v3d_transform[ 9]
local _v3d_transform_zy = _v3d_transform[10]
local _v3d_transform_zz = _v3d_transform[11]
local _v3d_transform_dz = _v3d_transform[12]
]]

_BASE_RENDERER_ENVIRONMENT._RENDERER_RENDER_FACE = [[
{! start_timer('process_vertices') !}
{! _RENDERER_INIT_FACE_VERTICES !}

{% for _, idx in ipairs(_ENV.options.pixel_shader.uses_face_offsets) do %}
local _v3d_shader_face_{= idx =} = _v3d_geometry[_v3d_face_offset + {= idx =}]
{% end %}

{! increment_statistic 'candidate_faces' !}

{% if options.cull_faces then %}
local _v3d_cull_face
do
	local _v3d_d1x = _v3d_transformed_p1x - _v3d_transformed_p0x
	local _v3d_d1y = _v3d_transformed_p1y - _v3d_transformed_p0y
	local _v3d_d1z = _v3d_transformed_p1z - _v3d_transformed_p0z
	local _v3d_d2x = _v3d_transformed_p2x - _v3d_transformed_p0x
	local _v3d_d2y = _v3d_transformed_p2y - _v3d_transformed_p0y
	local _v3d_d2z = _v3d_transformed_p2z - _v3d_transformed_p0z
	local _v3d_cx = _v3d_d1y * _v3d_d2z - _v3d_d1z * _v3d_d2y
	local _v3d_cy = _v3d_d1z * _v3d_d2x - _v3d_d1x * _v3d_d2z
	local _v3d_cz = _v3d_d1x * _v3d_d2y - _v3d_d1y * _v3d_d2x
	{% local cull_face_comparison_operator = options.cull_faces == 'front' and '<=' or '>=' %}
	_v3d_cull_face = _v3d_cx * _v3d_transformed_p0x + _v3d_cy * _v3d_transformed_p0y + _v3d_cz * _v3d_transformed_p0z {= cull_face_comparison_operator =} 0
end

if not _v3d_cull_face then
{% end %}

{! stop_timer('process_vertices') !}

-- TODO: make this split polygons for clipping
{% local clipping_plane = -0.0001 %}
if _v3d_transformed_p0z <= {= clipping_plane =} and _v3d_transformed_p1z <= {= clipping_plane =} and _v3d_transformed_p2z <= {= clipping_plane =} then
	{! start_timer('process_vertices') !}
	local _v3d_rasterize_p0_w = -1 / _v3d_transformed_p0z
	local _v3d_rasterize_p0_x = (_v3d_transformed_p0x * _v3d_rasterize_p0_w * _v3d_aspect_ratio_reciprocal + 1) * _v3d_viewport_translate_scale_x
	local _v3d_rasterize_p0_y = (-_v3d_transformed_p0y * _v3d_rasterize_p0_w + 1) * _v3d_viewport_translate_scale_y
	local _v3d_rasterize_p1_w = -1 / _v3d_transformed_p1z
	local _v3d_rasterize_p1_x = (_v3d_transformed_p1x * _v3d_rasterize_p1_w * _v3d_aspect_ratio_reciprocal + 1) * _v3d_viewport_translate_scale_x
	local _v3d_rasterize_p1_y = (-_v3d_transformed_p1y * _v3d_rasterize_p1_w + 1) * _v3d_viewport_translate_scale_y
	local _v3d_rasterize_p2_w = -1 / _v3d_transformed_p2z
	local _v3d_rasterize_p2_x = (_v3d_transformed_p2x * _v3d_rasterize_p2_w * _v3d_aspect_ratio_reciprocal + 1) * _v3d_viewport_translate_scale_x
	local _v3d_rasterize_p2_y = (-_v3d_transformed_p2y * _v3d_rasterize_p2_w + 1) * _v3d_viewport_translate_scale_y

	{% if needs_source_absolute_position then %}
	local _v3d_rasterize_p0_wx = _v3d_world_transformed_p0x
	local _v3d_rasterize_p0_wy = _v3d_world_transformed_p0y
	local _v3d_rasterize_p0_wz = _v3d_world_transformed_p0z
	local _v3d_rasterize_p1_wx = _v3d_world_transformed_p1x
	local _v3d_rasterize_p1_wy = _v3d_world_transformed_p1y
	local _v3d_rasterize_p1_wz = _v3d_world_transformed_p1z
	local _v3d_rasterize_p2_wx = _v3d_world_transformed_p2x
	local _v3d_rasterize_p2_wy = _v3d_world_transformed_p2y
	local _v3d_rasterize_p2_wz = _v3d_world_transformed_p2z
	{% end %}

	{% for _, idx in ipairs(_ENV.options.pixel_shader.uses_source_offsets) do %}
	local _v3d_rasterize_p0_va_{= idx =} = _v3d_geometry[_v3d_vertex_offset + {= idx =}]
	local _v3d_rasterize_p1_va_{= idx =} = _v3d_geometry[_v3d_vertex_offset + {= idx + options.pixel_shader.source_format:size() =}]
	local _v3d_rasterize_p2_va_{= idx =} = _v3d_geometry[_v3d_vertex_offset + {= idx + options.pixel_shader.source_format:size() * 2 =}]
	{% end %}

	{%
	local values_to_interpolate = {}

	if _ENV.options.pixel_shader.uses_source_position_x then
		table.insert(values_to_interpolate, {
			name = 'source_position_x',
			interpolated_name = '_v3d_shader_src_pos_x',
			p0_init = '_v3d_p0x',
			p1_init = '_v3d_p1x',
			p2_init = '_v3d_p2x',
		})
	end

	if _ENV.options.pixel_shader.uses_source_position_y then
		table.insert(values_to_interpolate, {
			name = 'source_position_y',
			interpolated_name = '_v3d_shader_src_pos_y',
			p0_init = '_v3d_p0y',
			p1_init = '_v3d_p1y',
			p2_init = '_v3d_p2y',
		})
	end

	if _ENV.options.pixel_shader.uses_source_position_z then
		table.insert(values_to_interpolate, {
			name = 'source_position_z',
			interpolated_name = '_v3d_shader_src_pos_z',
			p0_init = '_v3d_p0z',
			p1_init = '_v3d_p1z',
			p2_init = '_v3d_p2z',
		})
	end

	if _ENV.options.pixel_shader.uses_source_absolute_position_x then
		table.insert(values_to_interpolate, {
			name = 'source_absolute_position_x',
			interpolated_name = '_v3d_shader_src_abs_pos_x',
			p0_init = '_v3d_world_transformed_p0x',
			p1_init = '_v3d_world_transformed_p1x',
			p2_init = '_v3d_world_transformed_p2x',
		})
	end

	if _ENV.options.pixel_shader.uses_source_absolute_position_y then
		table.insert(values_to_interpolate, {
			name = 'source_absolute_position_y',
			interpolated_name = '_v3d_shader_src_abs_pos_y',
			p0_init = '_v3d_world_transformed_p0y',
			p1_init = '_v3d_world_transformed_p1y',
			p2_init = '_v3d_world_transformed_p2y',
		})
	end

	if _ENV.options.pixel_shader.uses_source_absolute_position_z then
		table.insert(values_to_interpolate, {
			name = 'source_absolute_position_z',
			interpolated_name = '_v3d_shader_src_abs_pos_z',
			p0_init = '_v3d_world_transformed_p0z',
			p1_init = '_v3d_world_transformed_p1z',
			p2_init = '_v3d_world_transformed_p2z',
		})
	end

	for _, idx in ipairs(_ENV.options.pixel_shader.uses_source_offsets) do
		table.insert(values_to_interpolate, {
			name = 'va_' .. idx,
			interpolated_name = '_v3d_shader_src_' .. idx,
			p0_init = '_v3d_rasterize_p0_va_' .. idx,
			p1_init = '_v3d_rasterize_p1_va_' .. idx,
			p2_init = '_v3d_rasterize_p2_va_' .. idx,
		})
	end
	%}

	{! stop_timer('process_vertices') !}

	{! _RENDERER_RENDER_TRIANGLE !}
	{! increment_statistic 'drawn_faces' !}
else
	{! increment_statistic 'discarded_faces' !}
end

{% if options.cull_faces then %}
else
	{! increment_statistic 'discarded_faces' !}
end
{% end %}

_v3d_vertex_offset = _v3d_vertex_offset + {= options.pixel_shader.source_format:size() * 3 =}
{% if options.pixel_shader.face_format then %}
_v3d_face_offset = _v3d_face_offset + {= options.pixel_shader.face_format:size() =}
{% end %}
]]

_BASE_RENDERER_ENVIRONMENT._RENDERER_INIT_FACE_VERTICES = [[
local _v3d_transformed_p0x, _v3d_transformed_p0y, _v3d_transformed_p0z,
      _v3d_transformed_p1x, _v3d_transformed_p1y, _v3d_transformed_p1z,
      _v3d_transformed_p2x, _v3d_transformed_p2y, _v3d_transformed_p2z

{% if _ENV.needs_source_absolute_position then %}
local _v3d_world_transformed_p0x, _v3d_world_transformed_p0y, _v3d_world_transformed_p0z,
      _v3d_world_transformed_p1x, _v3d_world_transformed_p1y, _v3d_world_transformed_p1z,
      _v3d_world_transformed_p2x, _v3d_world_transformed_p2y, _v3d_world_transformed_p2z
{% end %}

{% if _ENV.needs_source_absolute_normal then %}
local _v3d_face_world_normal0, _v3d_face_world_normal1, _v3d_face_world_normal2
{% end %}
{% if not _ENV.needs_source_position then %}
do
{% end %}
	{% local position_base_offset = options.position_lens.offset %}
	{% local vertex_stride = options.pixel_shader.source_format:size() %}
	local _v3d_p0x = _v3d_geometry[_v3d_vertex_offset + {= position_base_offset =}]
	local _v3d_p0y = _v3d_geometry[_v3d_vertex_offset + {= position_base_offset + 1 =}]
	local _v3d_p0z = _v3d_geometry[_v3d_vertex_offset + {= position_base_offset + 2 =}]
	local _v3d_p1x = _v3d_geometry[_v3d_vertex_offset + {= position_base_offset + vertex_stride =}]
	local _v3d_p1y = _v3d_geometry[_v3d_vertex_offset + {= position_base_offset + vertex_stride + 1 =}]
	local _v3d_p1z = _v3d_geometry[_v3d_vertex_offset + {= position_base_offset + vertex_stride + 2 =}]
	local _v3d_p2x = _v3d_geometry[_v3d_vertex_offset + {= position_base_offset + vertex_stride * 2 =}]
	local _v3d_p2y = _v3d_geometry[_v3d_vertex_offset + {= position_base_offset + vertex_stride * 2 + 1 =}]
	local _v3d_p2z = _v3d_geometry[_v3d_vertex_offset + {= position_base_offset + vertex_stride * 2 + 2 =}]
{% if _ENV.needs_source_position then %}
do
{% end %}
	{% if _ENV.needs_source_absolute_position then %}
	{! _RENDERER_INIT_FACE_VERTICES_WITH_ABSOLUTE_POSITION !}
	{% else %}
	{! _RENDERER_INIT_FACE_VERTICES_WITHOUT_ABSOLUTE_POSITION !}
	{% end %}

	{% if _ENV.needs_source_absolute_normal then %}
	local _v3d_face_normal_d1x = _v3d_world_transformed_p1x - _v3d_world_transformed_p0x
	local _v3d_face_normal_d1y = _v3d_world_transformed_p1y - _v3d_world_transformed_p0y
	local _v3d_face_normal_d1z = _v3d_world_transformed_p1z - _v3d_world_transformed_p0z
	local _v3d_face_normal_d2x = _v3d_world_transformed_p2x - _v3d_world_transformed_p0x
	local _v3d_face_normal_d2y = _v3d_world_transformed_p2y - _v3d_world_transformed_p0y
	local _v3d_face_normal_d2z = _v3d_world_transformed_p2z - _v3d_world_transformed_p0z
	_v3d_face_world_normal0 = _v3d_face_normal_d1y*_v3d_face_normal_d2z - _v3d_face_normal_d1z*_v3d_face_normal_d2y
	_v3d_face_world_normal1 = _v3d_face_normal_d1z*_v3d_face_normal_d2x - _v3d_face_normal_d1x*_v3d_face_normal_d2z
	_v3d_face_world_normal2 = _v3d_face_normal_d1x*_v3d_face_normal_d2y - _v3d_face_normal_d1y*_v3d_face_normal_d2x
	local _v3d_face_normal_divisor = 1 / math.sqrt(_v3d_face_world_normal0 * _v3d_face_world_normal0 + _v3d_face_world_normal1 * _v3d_face_world_normal1 + _v3d_face_world_normal2 * _v3d_face_world_normal2)
	_v3d_face_world_normal0 = _v3d_face_world_normal0 * _v3d_face_normal_divisor
	_v3d_face_world_normal1 = _v3d_face_world_normal1 * _v3d_face_normal_divisor
	_v3d_face_world_normal2 = _v3d_face_world_normal2 * _v3d_face_normal_divisor
	{% end %}
end
]]

_BASE_RENDERER_ENVIRONMENT._RENDERER_INIT_FACE_VERTICES_WITH_ABSOLUTE_POSITION = [[
if _v3d_model_transform then
	_v3d_world_transformed_p0x = _v3d_model_transform_xx * _v3d_p0x + _v3d_model_transform_xy * _v3d_p0y + _v3d_model_transform_xz * _v3d_p0z + _v3d_model_transform_dx
	_v3d_world_transformed_p0y = _v3d_model_transform_yx * _v3d_p0x + _v3d_model_transform_yy * _v3d_p0y + _v3d_model_transform_yz * _v3d_p0z + _v3d_model_transform_dy
	_v3d_world_transformed_p0z = _v3d_model_transform_zx * _v3d_p0x + _v3d_model_transform_zy * _v3d_p0y + _v3d_model_transform_zz * _v3d_p0z + _v3d_model_transform_dz

	_v3d_world_transformed_p1x = _v3d_model_transform_xx * _v3d_p1x + _v3d_model_transform_xy * _v3d_p1y + _v3d_model_transform_xz * _v3d_p1z + _v3d_model_transform_dx
	_v3d_world_transformed_p1y = _v3d_model_transform_yx * _v3d_p1x + _v3d_model_transform_yy * _v3d_p1y + _v3d_model_transform_yz * _v3d_p1z + _v3d_model_transform_dy
	_v3d_world_transformed_p1z = _v3d_model_transform_zx * _v3d_p1x + _v3d_model_transform_zy * _v3d_p1y + _v3d_model_transform_zz * _v3d_p1z + _v3d_model_transform_dz

	_v3d_world_transformed_p2x = _v3d_model_transform_xx * _v3d_p2x + _v3d_model_transform_xy * _v3d_p2y + _v3d_model_transform_xz * _v3d_p2z + _v3d_model_transform_dx
	_v3d_world_transformed_p2y = _v3d_model_transform_yx * _v3d_p2x + _v3d_model_transform_yy * _v3d_p2y + _v3d_model_transform_yz * _v3d_p2z + _v3d_model_transform_dy
	_v3d_world_transformed_p2z = _v3d_model_transform_zx * _v3d_p2x + _v3d_model_transform_zy * _v3d_p2y + _v3d_model_transform_zz * _v3d_p2z + _v3d_model_transform_dz
else
	_v3d_world_transformed_p0x = _v3d_p0x
	_v3d_world_transformed_p0y = _v3d_p0y
	_v3d_world_transformed_p0z = _v3d_p0z

	_v3d_world_transformed_p1x = _v3d_p1x
	_v3d_world_transformed_p1y = _v3d_p1y
	_v3d_world_transformed_p1z = _v3d_p1z

	_v3d_world_transformed_p2x = _v3d_p2x
	_v3d_world_transformed_p2y = _v3d_p2y
	_v3d_world_transformed_p2z = _v3d_p2z
end

_v3d_transformed_p0x = _v3d_transform_xx * _v3d_world_transformed_p0x + _v3d_transform_xy * _v3d_world_transformed_p0y + _v3d_transform_xz * _v3d_world_transformed_p0z + _v3d_transform_dx
_v3d_transformed_p0y = _v3d_transform_yx * _v3d_world_transformed_p0x + _v3d_transform_yy * _v3d_world_transformed_p0y + _v3d_transform_yz * _v3d_world_transformed_p0z + _v3d_transform_dy
_v3d_transformed_p0z = _v3d_transform_zx * _v3d_world_transformed_p0x + _v3d_transform_zy * _v3d_world_transformed_p0y + _v3d_transform_zz * _v3d_world_transformed_p0z + _v3d_transform_dz

_v3d_transformed_p1x = _v3d_transform_xx * _v3d_world_transformed_p1x + _v3d_transform_xy * _v3d_world_transformed_p1y + _v3d_transform_xz * _v3d_world_transformed_p1z + _v3d_transform_dx
_v3d_transformed_p1y = _v3d_transform_yx * _v3d_world_transformed_p1x + _v3d_transform_yy * _v3d_world_transformed_p1y + _v3d_transform_yz * _v3d_world_transformed_p1z + _v3d_transform_dy
_v3d_transformed_p1z = _v3d_transform_zx * _v3d_world_transformed_p1x + _v3d_transform_zy * _v3d_world_transformed_p1y + _v3d_transform_zz * _v3d_world_transformed_p1z + _v3d_transform_dz

_v3d_transformed_p2x = _v3d_transform_xx * _v3d_world_transformed_p2x + _v3d_transform_xy * _v3d_world_transformed_p2y + _v3d_transform_xz * _v3d_world_transformed_p2z + _v3d_transform_dx
_v3d_transformed_p2y = _v3d_transform_yx * _v3d_world_transformed_p2x + _v3d_transform_yy * _v3d_world_transformed_p2y + _v3d_transform_yz * _v3d_world_transformed_p2z + _v3d_transform_dy
_v3d_transformed_p2z = _v3d_transform_zx * _v3d_world_transformed_p2x + _v3d_transform_zy * _v3d_world_transformed_p2y + _v3d_transform_zz * _v3d_world_transformed_p2z + _v3d_transform_dz
]]

_BASE_RENDERER_ENVIRONMENT._RENDERER_INIT_FACE_VERTICES_WITHOUT_ABSOLUTE_POSITION = [[
_v3d_transformed_p0x = _v3d_transform_xx * _v3d_p0x + _v3d_transform_xy * _v3d_p0y + _v3d_transform_xz * _v3d_p0z + _v3d_transform_dx
_v3d_transformed_p0y = _v3d_transform_yx * _v3d_p0x + _v3d_transform_yy * _v3d_p0y + _v3d_transform_yz * _v3d_p0z + _v3d_transform_dy
_v3d_transformed_p0z = _v3d_transform_zx * _v3d_p0x + _v3d_transform_zy * _v3d_p0y + _v3d_transform_zz * _v3d_p0z + _v3d_transform_dz

_v3d_transformed_p1x = _v3d_transform_xx * _v3d_p1x + _v3d_transform_xy * _v3d_p1y + _v3d_transform_xz * _v3d_p1z + _v3d_transform_dx
_v3d_transformed_p1y = _v3d_transform_yx * _v3d_p1x + _v3d_transform_yy * _v3d_p1y + _v3d_transform_yz * _v3d_p1z + _v3d_transform_dy
_v3d_transformed_p1z = _v3d_transform_zx * _v3d_p1x + _v3d_transform_zy * _v3d_p1y + _v3d_transform_zz * _v3d_p1z + _v3d_transform_dz

_v3d_transformed_p2x = _v3d_transform_xx * _v3d_p2x + _v3d_transform_xy * _v3d_p2y + _v3d_transform_xz * _v3d_p2z + _v3d_transform_dx
_v3d_transformed_p2y = _v3d_transform_yx * _v3d_p2x + _v3d_transform_yy * _v3d_p2y + _v3d_transform_yz * _v3d_p2z + _v3d_transform_dy
_v3d_transformed_p2z = _v3d_transform_zx * _v3d_p2x + _v3d_transform_zy * _v3d_p2y + _v3d_transform_zz * _v3d_p2z + _v3d_transform_dz
]]

_BASE_RENDERER_ENVIRONMENT._RENDERER_RENDER_TRIANGLE = [[
{! start_timer('rasterize') !}
{! _RENDERER_RENDER_TRIANGLE_SORT_VERTICES !}
{! _RENDERER_RENDER_TRIANGLE_CALCULATE_FLAT_MIDPOINT !}

local _v3d_row_top_min = math.floor(_v3d_rasterize_p0_y + 0.5)
local _v3d_row_top_max = math.floor(_v3d_rasterize_p1_y - 0.5)
local _v3d_row_bottom_min = _v3d_row_top_max + 1
local _v3d_row_bottom_max = math.ceil(_v3d_rasterize_p2_y - 0.5)

local _v3d_region_dy

_v3d_region_dy = _v3d_rasterize_p1_y - _v3d_rasterize_p0_y
if _v3d_region_dy > 0 then
	if _v3d_row_top_min < _v3d_viewport_min_y then _v3d_row_top_min = _v3d_viewport_min_y end
	if _v3d_row_top_max > _v3d_viewport_max_y then _v3d_row_top_max = _v3d_viewport_max_y end

	{%
	local flat_triangle_name = 'top'
	local flat_triangle_top_left = 'p0'
	local flat_triangle_top_right = 'p0'
	local flat_triangle_bottom_left = 'pM'
	local flat_triangle_bottom_right = 'p1'
	%}

	{! _RENDERER_RENDER_REGION_SETUP !}
	{! _RENDERER_RENDER_REGION !}
end

_v3d_region_dy = _v3d_rasterize_p2_y - _v3d_rasterize_p1_y
if _v3d_region_dy > 0 then
	if _v3d_row_bottom_min < _v3d_viewport_min_y then _v3d_row_bottom_min = _v3d_viewport_min_y end
	if _v3d_row_bottom_max > _v3d_viewport_max_y then _v3d_row_bottom_max = _v3d_viewport_max_y end

	{%
	local flat_triangle_name = 'bottom'
	local flat_triangle_top_left = 'pM'
	local flat_triangle_top_right = 'p1'
	local flat_triangle_bottom_left = 'p2'
	local flat_triangle_bottom_right = 'p2'
	%}

	{! _RENDERER_RENDER_REGION_SETUP !}
	{! _RENDERER_RENDER_REGION !}
end

{! stop_timer('rasterize') !}
]]

_BASE_RENDERER_ENVIRONMENT._RENDERER_RENDER_TRIANGLE_SORT_VERTICES = [[
-- Sort vertices by Y value (ascending)
if _v3d_rasterize_p0_y <= _v3d_rasterize_p1_y then
	if _v3d_rasterize_p1_y <= _v3d_rasterize_p2_y then
		-- No swapping required
	elseif _v3d_rasterize_p0_y <= _v3d_rasterize_p2_y then
		-- Swap p1 and p2
		_v3d_rasterize_p1_x, _v3d_rasterize_p2_x = _v3d_rasterize_p2_x, _v3d_rasterize_p1_x
		_v3d_rasterize_p1_y, _v3d_rasterize_p2_y = _v3d_rasterize_p2_y, _v3d_rasterize_p1_y
		{% if _ENV.needs_interpolated_depth then %}
		_v3d_rasterize_p1_w, _v3d_rasterize_p2_w = _v3d_rasterize_p2_w, _v3d_rasterize_p1_w
		{% end %}
		{% for _, t in ipairs(values_to_interpolate) do %}
		{= t.p1_init =}, {= t.p2_init =} = {= t.p2_init =}, {= t.p1_init =}
		{% end %}
	else
		-- Shuffle by 1
		_v3d_rasterize_p0_x, _v3d_rasterize_p1_x, _v3d_rasterize_p2_x = _v3d_rasterize_p2_x, _v3d_rasterize_p0_x, _v3d_rasterize_p1_x
		_v3d_rasterize_p0_y, _v3d_rasterize_p1_y, _v3d_rasterize_p2_y = _v3d_rasterize_p2_y, _v3d_rasterize_p0_y, _v3d_rasterize_p1_y
		{% if _ENV.needs_interpolated_depth then %}
		_v3d_rasterize_p0_w, _v3d_rasterize_p1_w, _v3d_rasterize_p2_w = _v3d_rasterize_p2_w, _v3d_rasterize_p0_w, _v3d_rasterize_p1_w
		{% end %}
		{% for _, t in ipairs(values_to_interpolate) do %}
		{= t.p0_init =}, {= t.p1_init =}, {= t.p2_init =} = {= t.p2_init =}, {= t.p0_init =}, {= t.p1_init =}
		{% end %}
	end
else
	if _v3d_rasterize_p0_y <= _v3d_rasterize_p2_y then
		-- Swap p0 and p1
		_v3d_rasterize_p0_x, _v3d_rasterize_p1_x = _v3d_rasterize_p1_x, _v3d_rasterize_p0_x
		_v3d_rasterize_p0_y, _v3d_rasterize_p1_y = _v3d_rasterize_p1_y, _v3d_rasterize_p0_y
		{% if _ENV.needs_interpolated_depth then %}
		_v3d_rasterize_p0_w, _v3d_rasterize_p1_w = _v3d_rasterize_p1_w, _v3d_rasterize_p0_w
		{% end %}
		{% for _, t in ipairs(values_to_interpolate) do %}
		{= t.p0_init =}, {= t.p1_init =} = {= t.p1_init =}, {= t.p0_init =}
		{% end %}
	elseif _v3d_rasterize_p1_y <= _v3d_rasterize_p2_y then
		_v3d_rasterize_p0_x, _v3d_rasterize_p1_x, _v3d_rasterize_p2_x = _v3d_rasterize_p1_x, _v3d_rasterize_p2_x, _v3d_rasterize_p0_x
		_v3d_rasterize_p0_y, _v3d_rasterize_p1_y, _v3d_rasterize_p2_y = _v3d_rasterize_p1_y, _v3d_rasterize_p2_y, _v3d_rasterize_p0_y
		{% if _ENV.needs_interpolated_depth then %}
		_v3d_rasterize_p0_w, _v3d_rasterize_p1_w, _v3d_rasterize_p2_w = _v3d_rasterize_p1_w, _v3d_rasterize_p2_w, _v3d_rasterize_p0_w
		{% end %}
		{% for _, t in ipairs(values_to_interpolate) do %}
		{= t.p0_init =}, {= t.p1_init =}, {= t.p2_init =} = {= t.p1_init =}, {= t.p2_init =}, {= t.p0_init =}
		{% end %}
	else
		-- Swap p0 and p2
		_v3d_rasterize_p0_x, _v3d_rasterize_p2_x = _v3d_rasterize_p2_x, _v3d_rasterize_p0_x
		_v3d_rasterize_p0_y, _v3d_rasterize_p2_y = _v3d_rasterize_p2_y, _v3d_rasterize_p0_y
		{% if _ENV.needs_interpolated_depth then %}
		_v3d_rasterize_p0_w, _v3d_rasterize_p2_w = _v3d_rasterize_p2_w, _v3d_rasterize_p0_w
		{% end %}
		{% for _, t in ipairs(values_to_interpolate) do %}
		{= t.p0_init =}, {= t.p2_init =} = {= t.p2_init =}, {= t.p0_init =}
		{% end %}
	end
end
]]

_BASE_RENDERER_ENVIRONMENT._RENDERER_RENDER_TRIANGLE_CALCULATE_FLAT_MIDPOINT = [[
local _v3d_rasterize_pM_x
{% if _ENV.needs_interpolated_depth then %}
local _v3d_rasterize_pM_w
{% end %}
{% for _, t in ipairs(values_to_interpolate) do %}
local _v3d_rasterize_pM_{= t.name =}
{% end %}

do
	local _v3d_midpoint_scalar = (_v3d_rasterize_p1_y - _v3d_rasterize_p0_y) / (_v3d_rasterize_p2_y - _v3d_rasterize_p0_y)
	local _v3d_midpoint_scalar_inv = 1 - _v3d_midpoint_scalar
	_v3d_rasterize_pM_x = _v3d_rasterize_p0_x * _v3d_midpoint_scalar_inv + _v3d_rasterize_p2_x * _v3d_midpoint_scalar

	{% if _ENV.needs_interpolated_depth then %}
	_v3d_rasterize_pM_w = _v3d_rasterize_p0_w * _v3d_midpoint_scalar_inv + _v3d_rasterize_p2_w * _v3d_midpoint_scalar
	{% end %}

	{% for _, t in ipairs(values_to_interpolate) do %}
	_v3d_rasterize_pM_{= t.name =} = ({= t.p0_init =} * _v3d_rasterize_p0_w * _v3d_midpoint_scalar_inv + {= t.p2_init =} * _v3d_rasterize_p2_w * _v3d_midpoint_scalar) / _v3d_rasterize_pM_w
	{% end %}
end

if _v3d_rasterize_pM_x > _v3d_rasterize_p1_x then
	_v3d_rasterize_pM_x, _v3d_rasterize_p1_x = _v3d_rasterize_p1_x, _v3d_rasterize_pM_x

	{% if _ENV.needs_interpolated_depth then %}
	_v3d_rasterize_pM_w, _v3d_rasterize_p1_w = _v3d_rasterize_p1_w, _v3d_rasterize_pM_w
	{% end %}

	{% for _, t in ipairs(values_to_interpolate) do %}
	_v3d_rasterize_pM_{= t.name =}, {= t.p1_init =} = {= t.p1_init =}, _v3d_rasterize_pM_{= t.name =}
	{% end %}
end
]]

_BASE_RENDERER_ENVIRONMENT._RENDERER_RENDER_REGION_SETUP = [[
local _v3d_region_y_correction = _v3d_row_{= flat_triangle_name =}_min + 0.5 - _v3d_rasterize_{= flat_triangle_top_right =}_y
local _v3d_region_left_dx_dy = (_v3d_rasterize_{= flat_triangle_bottom_left =}_x - _v3d_rasterize_{= flat_triangle_top_left =}_x) / _v3d_region_dy
local _v3d_region_right_dx_dy = (_v3d_rasterize_{= flat_triangle_bottom_right =}_x - _v3d_rasterize_{= flat_triangle_top_right =}_x) / _v3d_region_dy
local _v3d_region_left_x = _v3d_rasterize_{= flat_triangle_top_left =}_x + _v3d_region_left_dx_dy * _v3d_region_y_correction - 0.5
local _v3d_region_right_x = _v3d_rasterize_{= flat_triangle_top_right =}_x + _v3d_region_right_dx_dy * _v3d_region_y_correction - 1.5

{% if _ENV.needs_interpolated_depth then %}
local _v3d_region_left_dw_dy = (_v3d_rasterize_{= flat_triangle_bottom_left =}_w - _v3d_rasterize_{= flat_triangle_top_left =}_w) / _v3d_region_dy
local _v3d_region_right_dw_dy = (_v3d_rasterize_{= flat_triangle_bottom_right =}_w - _v3d_rasterize_{= flat_triangle_top_right =}_w) / _v3d_region_dy
local _v3d_region_left_w = _v3d_rasterize_{= flat_triangle_top_left =}_w + _v3d_region_left_dw_dy * _v3d_region_y_correction
local _v3d_region_right_w = _v3d_rasterize_{= flat_triangle_top_right =}_w + _v3d_region_right_dw_dy * _v3d_region_y_correction
{% end %}

{% for _, t in ipairs(values_to_interpolate) do %}
{%
local function get_var(point)
	if point == 'pM' then
		return '_v3d_rasterize_pM_' .. t.name
	else
		return t[point .. '_init']
	end
end
%}
local _v3d_region_left_dVwdy_{= t.name =} = ({= get_var(flat_triangle_bottom_left) =} * _v3d_rasterize_{= flat_triangle_bottom_left =}_w - {= get_var(flat_triangle_top_left) =} * _v3d_rasterize_{= flat_triangle_top_left =}_w) / _v3d_region_dy
local _v3d_region_right_dVwdy_{= t.name =} = ({= get_var(flat_triangle_bottom_right) =} * _v3d_rasterize_{= flat_triangle_bottom_right =}_w - {= get_var(flat_triangle_top_right) =} * _v3d_rasterize_{= flat_triangle_top_right =}_w) / _v3d_region_dy
local _v3d_region_left_Vw_{= t.name =} = {= get_var(flat_triangle_top_left) =} * _v3d_rasterize_{= flat_triangle_top_left =}_w + _v3d_region_left_dVwdy_{= t.name =} * _v3d_region_y_correction
local _v3d_region_right_Vw_{= t.name =} = {= get_var(flat_triangle_top_right) =} * _v3d_rasterize_{= flat_triangle_top_right =}_w + _v3d_region_right_dVwdy_{= t.name =} * _v3d_region_y_correction
{% end %}
]]

_BASE_RENDERER_ENVIRONMENT._RENDERER_RENDER_REGION = [[
for _v3d_row = _v3d_row_{= flat_triangle_name =}_min, _v3d_row_{= flat_triangle_name =}_max do
	local _v3d_row_min_column = math.ceil(_v3d_region_left_x)
	local _v3d_row_max_column = math.ceil(_v3d_region_right_x)

	if _v3d_row_min_column < _v3d_viewport_min_x then _v3d_row_min_column = _v3d_viewport_min_x end
	if _v3d_row_max_column > _v3d_viewport_max_x then _v3d_row_max_column = _v3d_viewport_max_x end

	{% if _ENV.needs_interpolated_depth then %}
	local _v3d_row_x_correction = _v3d_row_min_column - _v3d_region_left_x
	local _v3d_row_dx_inv = 1 / (_v3d_region_right_x - _v3d_region_left_x + 1)
	-- TODO: if _v3d_row_min_column == _v3d_row_max_column then _v3d_row_dx_inv = 1 end
	local _v3d_row_dw_dx = (_v3d_region_right_w - _v3d_region_left_w) * _v3d_row_dx_inv
	local _v3d_shader_src_depth = _v3d_region_left_w + _v3d_row_dw_dx * _v3d_row_x_correction
	{% end %}

	{% for _, t in ipairs(values_to_interpolate) do %}
	local _v3d_row_dVwdx_{= t.name =} = (_v3d_region_right_Vw_{= t.name =} - _v3d_region_left_Vw_{= t.name =}) * _v3d_row_dx_inv
	local _v3d_row_Vw_{= t.name =} = _v3d_region_left_Vw_{= t.name =} + _v3d_row_dVwdx_{= t.name =} * _v3d_row_x_correction
	{% end %}

	{% for _, view_name in ipairs(_ENV.options.pixel_shader.uses_destination_base_offsets) do %}
	local _v3d_shader_dst_base_offset_{= view_name =} = _v3d_view_init_offset_{= view_name =} + (_v3d_image_width_{= view_name =} * _v3d_row + _v3d_row_min_column) * {= _ENV.options.pixel_shader.image_formats[view_name]:size() =}
	{% end %}

	-- TODO
	for _v3d_x = _v3d_row_min_column, _v3d_row_max_column do
		{% for _, t in ipairs(values_to_interpolate) do %}
		local {= t.interpolated_name =} = _v3d_row_Vw_{= t.name =} / _v3d_shader_src_depth
		{% end %}

		{! increment_statistic 'candidate_fragments' !}

		--#pipeline_source_start pixel
		{! PIXEL_SOURCE_EMBED !}
		--#pipeline_source_end pixel

		{% for _, view_name in ipairs(options.pixel_shader.uses_destination_base_offsets) do %}
		_v3d_shader_dst_base_offset_{= view_name =} = _v3d_shader_dst_base_offset_{= view_name =} + {= _ENV.options.pixel_shader.image_formats[view_name]:size() =}
		{% end %}

		{% if _ENV.needs_interpolated_depth then %}
		_v3d_shader_src_depth = _v3d_shader_src_depth + _v3d_row_dw_dx
		{% end %}

		{% for _, t in ipairs(values_to_interpolate) do %}
		_v3d_row_Vw_{= t.name =} = _v3d_row_Vw_{= t.name =} + _v3d_row_dVwdx_{= t.name =}
		{% end %}
	end

	_v3d_region_left_x = _v3d_region_left_x + _v3d_region_left_dx_dy
	_v3d_region_right_x = _v3d_region_right_x + _v3d_region_right_dx_dy

	{% if _ENV.needs_interpolated_depth then %}
	_v3d_region_left_w = _v3d_region_left_w + _v3d_region_left_dw_dy
	_v3d_region_right_w = _v3d_region_right_w + _v3d_region_right_dw_dy
	{% end %}

	{% for _, t in ipairs(values_to_interpolate) do %}
	_v3d_region_left_Vw_{= t.name =} = _v3d_region_left_Vw_{= t.name =} + _v3d_region_left_dVwdy_{= t.name =}
	_v3d_region_right_Vw_{= t.name =} = _v3d_region_right_Vw_{= t.name =} + _v3d_region_right_dVwdy_{= t.name =}
	{% end %}
end
]]

_BASE_RENDERER_ENVIRONMENT._RENDERER_RETURN_STATISTICS = [[
-- _v3d_create_instance, _v3d_finalise_instance
{% if options.record_statistics then %}
	local _v3d_return_statistics = _v3d_create_instance('V3DRendererStatistics')
	_v3d_return_statistics.timers = {! _RENDERER_RETURN_STATISTICS_TOTAL_TIMER_VALUE !}
	_v3d_return_statistics.events = {! _RENDERER_RETURN_STATISTICS_EVENT_VALUE !}
	return _v3d_finalise_instance(_v3d_return_statistics)
{% else %}
	return {
		timers = {! _RENDERER_RETURN_STATISTICS_TOTAL_TIMER_VALUE !},
		events = {! _RENDERER_RETURN_STATISTICS_EVENT_VALUE !},
	}
{% end %}
]]

_BASE_RENDERER_ENVIRONMENT._RENDERER_RETURN_STATISTICS_TOTAL_TIMER_VALUE = [[
{
	{% for _, timer_name in ipairs(_ENV.timers_updated) do %}
		{% if options.record_statistics then %}
	['{= timer_name =}'] = {= get_timer_local_variable(timer_name) =},
		{% else %}
	['{= timer_name =}'] = 0,
		{% end %}
	{% end %}
}
]]

_BASE_RENDERER_ENVIRONMENT._RENDERER_RETURN_STATISTICS_EVENT_VALUE = [[
{
{% for _, counter_name in ipairs(_ENV.event_counters_updated) do %}
	{% if options.record_statistics then %}
{= counter_name =} = {= get_event_counter_local_variable(counter_name) =},
	{% else %}
{= counter_name =} = 0,
	{% end %}
{% end %}
}
]]
end

-- TODO: validations
-- TODO: examples
--- TODO
--- @param options V3DRendererOptions
--- @return V3DRenderer
--- @v3d-constructor
function v3d.compile_renderer(options)
	local renderer = _create_instance('V3DRenderer', options.label)

	local actual_options = {}
	actual_options.pixel_shader = options.pixel_shader
	actual_options.position_lens = options.position_lens or v3d.format_lens(options.pixel_shader.source_format, 'position')
	actual_options.cull_faces = options.cull_faces or 'back'
	actual_options.pixel_aspect_ratio = options.pixel_aspect_ratio or 1
	actual_options.reverse_horizontal_iteration = options.reverse_horizontal_iteration or false
	actual_options.reverse_vertical_iteration = options.reverse_vertical_iteration or false
	actual_options.record_statistics = options.record_statistics or false
	actual_options.flat_interpolation = false
	actual_options.label = options.label

	--- @diagnostic disable-next-line: invisible
	renderer.created_options = options
	renderer.used_options = actual_options
	renderer.pixel_shader = actual_options.pixel_shader

	----------------------------------------------------------------------------

	local clock_function_str = ccemux and 'ccemux.nanoTime() / 1000000000' or 'os.clock()'

	local _environment = {}
	for k, v in pairs(_BASE_RENDERER_ENVIRONMENT) do
		_environment[k] = v
	end

	_environment.options = actual_options

	_environment.access_image_view_base_offsets = {}
	_environment.event_counters_updated = {}
	_environment.timers_updated = {}
	_environment.needs_source_position = actual_options.pixel_shader.uses_source_position_x
	                                  or actual_options.pixel_shader.uses_source_position_y
	                                  or actual_options.pixel_shader.uses_source_position_z
	_environment.needs_source_absolute_normal = actual_options.pixel_shader.uses_source_absolute_normal_x
	                                         or actual_options.pixel_shader.uses_source_absolute_normal_y
	                                         or actual_options.pixel_shader.uses_source_absolute_normal_z
	_environment.needs_source_absolute_position = actual_options.pixel_shader.uses_source_absolute_position_x
	                                           or actual_options.pixel_shader.uses_source_absolute_position_y
	                                           or actual_options.pixel_shader.uses_source_absolute_position_z
	                                           or _environment.needs_source_absolute_normal
	_environment.needs_interpolated_depth = actual_options.pixel_shader.uses_source_depth
	                                     or _environment.needs_source_position
	                                     or _environment.needs_source_absolute_normal
	                                     or _environment.needs_source_absolute_position
	                                     or #actual_options.pixel_shader.uses_source_offsets > 0
	_environment.timer_stack = {}

	function _environment.start_timer(name)
		if not actual_options.record_statistics then
			return ''
		end

		if #_environment.timer_stack > 0 then
			name = _environment.timer_stack[#_environment.timer_stack] .. '/' .. name
		end

		if not _environment.timers_updated[name] then
			_environment.timers_updated[name] = true
			table.insert(_environment.timers_updated, name)
		end

		local timer_start_name = _environment.get_timer_start_local_variable(name)
		table.insert(_environment.timer_stack, name)
		return 'local ' .. timer_start_name .. ' = ' .. clock_function_str
	end

	function _environment.stop_timer(name)
		if not actual_options.record_statistics then
			return ''
		end

		table.remove(_environment.timer_stack)

		if #_environment.timer_stack > 0 then
			name = _environment.timer_stack[#_environment.timer_stack] .. '/' .. name
		end

		local timer_start_name = _environment.get_timer_start_local_variable(name)
		local timer_name = _environment.get_timer_local_variable(name)

		return timer_name .. ' = ' .. timer_name .. ' + (' .. clock_function_str .. ' - ' .. timer_start_name .. ')'
	end

	function _environment.increment_statistic(name)
		if not actual_options.record_statistics then
			return ''
		end

		return '{! v3d_event(\'' .. name .. '\') !}'
	end

	----------------------------------------------------------------------------

	local pixel_source = _v3d_apply_template(actual_options.pixel_shader.expanded_code, _environment)

	_environment.PIXEL_SOURCE_EMBED = pixel_source

	local compiled_source = _v3d_apply_template(_environment._RENDERER_RENDER_MAIN, _environment)
	compiled_source = _v3d_optimise_globals(compiled_source, true)
	compiled_source = _v3d_optimise_maths(compiled_source)

	local f, err = load(compiled_source, '=render', nil, _ENV)
	if f then
		--- @diagnostic disable-next-line: inject-field
		renderer.render = f(_create_instance, _finalise_instance)
	else
		_v3d_contextual_error(err, compiled_source)
	end

	-- TODO: remove this, add functionality to v3debug
	local h = assert(io.open('/v3d/artifacts/renderer.lua', 'w'))
	h:write(compiled_source)
	h:close()

	--- @diagnostic disable-next-line: invisible
	renderer.compiled_source = compiled_source

	return _finalise_instance(renderer)
end

end ----------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Samplers --------------------------------------------------------------------
do -----------------------------------------------------------------------------

--- Sampler wrapping determines what happens to image coordinates that lie
--- outside the 0-1 inclusive range.
---
--- * `clamp`: Coordinates are clamped to the 0-1 inclusive range, e.g. a
---            coordinate of -0.3 would become 0, and a coordinate of 1.3 would
---            become 1.
--- * `repeat`: Coordinates repeat mod 1, e.g. a coordinate of 1.3 would be the
---             same as a coordinate of 0.3.
--- * `mirror`: Like `repeat` but mirrors the coordinates every other repeat,
---             e.g. a coordinate of 1.3 would be the same as a coordinate of
---             0.7, but a coordinate of 2.3 would be the same as a coordinate
---             of 0.3.
--- @alias V3DSamplerWrap 'clamp' | 'repeat' | 'mirror'

--- Sampler interpolation determines how the image is sampled when a coordinate
--- lies between pixels.
---
--- * `nearest`: The single value of the nearest pixel is used.
--- * `linear`: The values of the directly neighbouring pixels are linearly
---             interpolated.
--- @alias V3DSamplerInterpolation 'nearest' | 'linear'

----------------------------------------------------------------

--- A 1D sampler is a function that returns the pixel value within an image at a
--- given coordinate. The coordinate is a continuous value between 0 and 1
--- inclusive, where 0 is the leftmost pixel and 1 is the rightmost pixel.
---
--- The sampler's options determine how the image is sampled. The options are
--- specified when the sampler is created and cannot be changed afterwards.
---
--- The sampler's format determines what images the sampler is compatible with.
--- @class V3DSampler1D
--- The options that the sampler is using, not necessarily what it was created
--- with. For example, if a value was not provided as an option, this field will
--- contain its default value.
--- @field options V3DSampler1DOptions
--- The generated sampler function code. This is the string that was used to
--- load the sample function for this instance.
--- @field compiled_sampler string

----------------------------------------------------------------

--- A 2D sampler is a function that returns the pixel value within an image at a
--- pair of given coordinates (XY/UV). The coordinates are continuous values
--- between 0 and 1 inclusive, where 0 is the top-left pixel and 1 is the
--- bottom-right pixel.
---
--- The sampler's options determine how the image is sampled. The options are
--- specified when the sampler is created and cannot be changed afterwards.
---
--- The sampler's format determines what images the sampler is compatible with.
--- @class V3DSampler2D
--- The options that the sampler is using, not necessarily what it was created
--- with. For example, if a value was not provided as an option, this field will
--- contain its default value.
--- @field options V3DSampler2DOptions
--- The generated sampler function code. This is the string that was used to
--- load the sample function for this instance.
--- @field compiled_sampler string

----------------------------------------------------------------

--- A 3D sampler is a function that returns the pixel value within an image at a
--- triple of given coordinates (XYZ/UVW). The coordinates are continuous values
--- between 0 and 1 inclusive, where 0 is the top-left-front pixel and 1 is the
--- bottom-right-back pixel.
---
--- The sampler's options determine how the image is sampled. The options are
--- specified when the sampler is created and cannot be changed afterwards.
---
--- The sampler's format determines what images the sampler is compatible with.
--- @class V3DSampler3D
--- The options that the sampler is using, not necessarily what it was created
--- with. For example, if a value was not provided as an option, this field will
--- contain its default value.
--- @field options V3DSampler3DOptions
--- The generated sampler function code. This is the string that was used to
--- load the sample function for this instance.
--- @field compiled_sampler string

----------------------------------------------------------------

--- Options for a 1D sampler.
---
--- @see v3d.create_sampler1D
--- @see V3DSampler1D
--- @class V3DSampler1DOptions
--- Format of the sampler. Images sampled with this sampler must have a format
--- compatible with the sampler's format.
--- @field format V3DFormat
--- Lens within the format to sample. This allows sampling specific parts of an
--- image, such as the red channel of an RGB image. Defaults to the format's
--- default lens, therefore sampling all the data.
--- @field lens V3DLens | nil
--- Interpolation mode for the sampler. Defaults to `nearest`.
---
--- @see V3DSamplerInterpolation
--- @field interpolate V3DSamplerInterpolation | nil
--- Wrapping mode for the U coordinate. Defaults to `clamp`.
---
--- @see V3DSamplerWrap
--- @field wrap_u V3DSamplerWrap | nil
--- Label for the sampler. This is used for debugging purposes.
--- @field label string | nil
--- @v3d-structural

----------------------------------------------------------------

--- Options for a 2D sampler.
---
--- @see v3d.create_sampler2D
--- @see V3DSampler2D
--- @class V3DSampler2DOptions: V3DSampler1DOptions
--- Wrapping mode for the V coordinate. Defaults to `clamp`.
---
--- @see V3DSamplerWrap
--- @field wrap_v V3DSamplerWrap | nil
--- @v3d-structural

----------------------------------------------------------------

--- Options for a 3D sampler.
---
--- @see v3d.create_sampler3D
--- @see V3DSampler3D
--- @class V3DSampler3DOptions: V3DSampler2DOptions
--- Wrapping mode for the W coordinate. Defaults to `clamp`.
---
--- @see V3DSamplerWrap
--- @field wrap_w V3DSamplerWrap | nil
--- @v3d-structural

----------------------------------------------------------------

local function _wrap_nearest_to_code(wrap, vT, vS, vM)
	if wrap == 'clamp' then
		return table.concat({
			'local ' .. vT .. ' = math.floor(' .. vS .. ' * ' .. vM .. ')',
			'if ' .. vT .. ' < 0 then ' .. vT .. ' = 0',
			'elseif ' .. vT .. ' >= ' .. vM .. ' then ' .. vT .. ' = ' .. vM .. ' - 1',
			'end',
		}, '\n')
	elseif wrap == 'repeat' then
		return table.concat({
			'local ' .. vS .. 'mod1 = ' .. vS .. ' % 1',
			'if ' .. vS .. 'mod1 == 0 then ' .. vS .. ' = ' .. vS .. ' % 2 -- prevent ' .. vS .. '=1 wrapping to 0',
			'else               ' .. vS .. ' = ' .. vS .. 'mod1',
			'end',
			'local ' .. vT .. ' = math.floor(' .. vS .. ' * ' .. vM .. ')',
			'if ' .. vT .. ' >= ' .. vM .. ' then ' .. vT .. ' = ' .. vM .. ' - 1 end',
		}, '\n')
	elseif wrap == 'mirror' then
		return table.concat({
			'local ' .. vM .. '2 = ' .. vM .. ' + ' .. vM,
			'local ' .. vT .. ' = math.floor((' .. vS .. ' % 2) * ' .. vM .. ')',
			'if ' .. vT .. ' >= ' .. vM .. ' then',
			'	' .. vT .. ' = ' .. vM .. '2 - ' .. vT .. ' - 1',
			'end',
		}, '\n')
	end
end

local function _wrap_linear_to_code(wrap, vT, vS, vM)
	if wrap == 'clamp' then
		return table.concat({
			'if ' .. vS .. ' < 0 then ' .. vS .. ' = 0',
			'elseif ' .. vS .. ' > 1 then ' .. vS .. ' = 1 end',
			'local ' .. vT .. ' = ' .. vS .. ' * (' .. vM .. ' - 1)',
			'local ' .. vT .. '0 = math.floor(' .. vT .. ')',
			'local ' .. vT .. '1 = ' .. vT .. '0 + 1',
			'if ' .. vT .. '1 < 0 then ' .. vT .. '1 = 0',
			'elseif ' .. vT .. '1 >= ' .. vM .. ' then ' .. vT .. '1 = ' .. vM .. ' - 1 end',
			'local ' .. vT .. 't1 = ' .. vT .. ' - ' .. vT .. '0',
			'local ' .. vT .. 't0 = 1 - ' .. vT .. 't1',
		}, '\n')
	elseif wrap == 'repeat' then
		return table.concat({
			'' .. vS .. ' = ' .. vS .. ' % 1',
			'',
			'local ' .. vT .. ' = ' .. vS .. ' * (' .. vM .. ' - 1)',
			'local ' .. vT .. '0 = math.floor(' .. vT .. ')',
			'local ' .. vT .. '1 = ' .. vT .. '0 + 1',
			'if ' .. vT .. '1 == ' .. vM .. ' - 1 then ' .. vT .. '1 = 0 end',
			'local ' .. vT .. 't1 = ' .. vT .. ' - ' .. vT .. '0',
			'local ' .. vT .. 't0 = 1 - ' .. vT .. 't1',
			'',
			vT .. '0 = ' .. vT .. '0 % ' .. vM,
			'' .. vT .. '1 = ' .. vT .. '1 % ' .. vM,
		}, '\n')
	elseif wrap == 'mirror' then
		-- TODO: pretty sure this is broken...
		return table.concat({
			'local ' .. vM .. '2 = ' .. vM .. ' + ' .. vM,
			'local ' .. vT .. ' = ' .. vS .. ' * ' .. vM .. ' % ' .. vM .. '2',
			'local ' .. vT .. '0 = math.floor(' .. vT .. ')',
			'local ' .. vT .. '1 = (' .. vT .. '0 + 1) % ' .. vM .. '2',
			'local ' .. vT .. 't1 = (' .. vT .. ' - ' .. vT .. '0) % 1',
			'local ' .. vT .. 't0 = 1 - ' .. vT .. 't1',
			'',
			'if ' .. vT .. '0 >= ' .. vM .. ' then ' .. vT .. '0 = ' .. vM .. ' - (' .. vT .. '0 % ' .. vM .. ') - 1 end',
			'if ' .. vT .. '1 >= ' .. vM .. ' then ' .. vT .. '1 = ' .. vM .. ' - (' .. vT .. '1 % ' .. vM .. ') - 1 end',
		}, '\n')
	end
end

----------------------------------------------------------------

local _SAMPLER1D_TEMPLATE_NEAREST = [[
	local _v3d_sampler_image_width = $image.width

	{! _wrap_nearest_to_code(options.wrap_u, '_v3d_sampler_x', '$u', '_v3d_sampler_image_width') !}

	{!
	local c = {}
	for i = first_component_offset + 1, first_component_offset + n_components do
		table.insert(c, '$image[' .. i .. ' + _v3d_sampler_x * ' .. n_components .. ']')
	end
	return '$return ' .. table.concat(c, ', ')
	!}
]]

local _SAMPLER1D_TEMPLATE_LINEAR = [[
	local _v3d_sampler_image_width = $image.width

	{! _wrap_linear_to_code(options.wrap_u, '_v3d_sampler_x', '$u', '_v3d_sampler_image_width') !}

	{!
	local c = {}
	for i = first_component_offset + 1, first_component_offset + n_components do
		local x0 = '$image[' .. i .. ' + _v3d_sampler_x0 * ' .. n_components .. ']'
		local x1 = '$image[' .. i .. ' + _v3d_sampler_x1 * ' .. n_components .. ']'
		table.insert(c, x0 .. ' * _v3d_sampler_xt0 + ' .. x1 .. ' * _v3d_sampler_xt1')
	end
	return '$return ' .. table.concat(c, ', ')
	!}
]]

--- Create a 1D sampler.
---
--- @see V3DSampler1D
--- @param options V3DSampler1DOptions
--- @return V3DSampler1D
--- @v3d-nomethod
--- @v3d-constructor
--- local my_sampler = v3d.create_sampler1D {
--- 	format = v3d.uinteger(),
--- }
--- @v3d-example
--- local my_sampler = v3d.create_sampler1D {
--- 	format = v3d.number(),
--- 	wrap_u = 'repeat',
--- 	interpolate_u = 'linear',
--- }
--- @v3d-example
function v3d.create_sampler1D(options)
	local sampler = _create_instance('V3DSampler1D', options.label)
	options = options or {}
	sampler.options = {
		format = options.format,
		lens = options.lens or v3d.format_lens(options.format),
		interpolate = options.interpolate or 'nearest',
		wrap_u = options.wrap_u or 'clamp',
	}
	local environment = {
		first_component_offset = sampler.options.lens.offset,
		n_components = v3d.format_size(sampler.options.lens.out_format),
		options = sampler.options,
		_wrap_nearest_to_code = _wrap_nearest_to_code,
		_wrap_linear_to_code = _wrap_linear_to_code,
	}
	local template

	if sampler.options.interpolate == 'nearest' then
		template = _SAMPLER1D_TEMPLATE_NEAREST
	elseif sampler.options.interpolate == 'linear' then
		template = _SAMPLER1D_TEMPLATE_LINEAR
	else
		_v3d_internal_error('Invalid interpolation mode: ' .. sampler.options.interpolate)
	end

	template = 'return function(sampler, image, u)\n' .. template .. '\nend'

	local compiled_sampler = _v3d_apply_template(template, environment)
	compiled_sampler = compiled_sampler:gsub('$image', 'image')
	compiled_sampler = compiled_sampler:gsub('$u', 'u')
	compiled_sampler = compiled_sampler:gsub('$return', 'return')
	compiled_sampler = _v3d_optimise_globals(compiled_sampler, true)
	compiled_sampler = _v3d_optimise_maths(compiled_sampler)
	compiled_sampler = table.concat(_v3d_normalise_code_lines(compiled_sampler), '\n')

	sampler.compiled_sampler = compiled_sampler
	--- @diagnostic disable-next-line: inject-field
	sampler.sample = assert(load(compiled_sampler))()
	return _finalise_instance(sampler)
end

----------------------------------------------------------------

local _SAMPLER2D_TEMPLATE_NEAREST = [[
	local _v3d_sampler_image_width = $image.width
	local _v3d_sampler_image_height = $image.height

	{! _wrap_nearest_to_code(options.wrap_u, '_v3d_sampler_x', '$u', '_v3d_sampler_image_width') !}
	{! _wrap_nearest_to_code(options.wrap_v, '_v3d_sampler_y', '$v', '_v3d_sampler_image_height') !}

	{!
	local c = {}
	for i = first_component_offset + 1, first_component_offset + n_components do
		table.insert(c, '$image[' .. i .. ' + (_v3d_sampler_x + _v3d_sampler_y * _v3d_sampler_image_width) * ' .. n_components .. ']')
	end
	return '$return ' .. table.concat(c, ', ')
	!}
]]

local _SAMPLER2D_TEMPLATE_LINEAR = [[
	local _v3d_sampler_image_width = $image.width
	local _v3d_sampler_image_height = $image.height

	{! _wrap_linear_to_code(options.wrap_u, '_v3d_sampler_x', '$u', '_v3d_sampler_image_width') !}
	{! _wrap_linear_to_code(options.wrap_v, '_v3d_sampler_y', '$v', '_v3d_sampler_image_height') !}

	{!
	local c = {}
	for i = first_component_offset + 1, first_component_offset + n_components do
		local x0y0 = '$image[' .. i .. ' + (_v3d_sampler_x0 + _v3d_sampler_y0 * _v3d_sampler_image_width) * ' .. n_components .. ']'
		local x1y0 = '$image[' .. i .. ' + (_v3d_sampler_x1 + _v3d_sampler_y0 * _v3d_sampler_image_width) * ' .. n_components .. ']'
		local x0y1 = '$image[' .. i .. ' + (_v3d_sampler_x0 + _v3d_sampler_y1 * _v3d_sampler_image_width) * ' .. n_components .. ']'
		local x1y1 = '$image[' .. i .. ' + (_v3d_sampler_x1 + _v3d_sampler_y1 * _v3d_sampler_image_width) * ' .. n_components .. ']'
		local y0 = '(' .. x0y0 .. ' * _v3d_sampler_xt0 + ' .. x1y0 .. ' * _v3d_sampler_xt1)'
		local y1 = '(' .. x0y1 .. ' * _v3d_sampler_xt0 + ' .. x1y1 .. ' * _v3d_sampler_xt1)'
		table.insert(c, y0 .. ' * _v3d_sampler_yt0 + ' .. y1 .. ' * _v3d_sampler_yt1')
	end
	return '$return ' .. table.concat(c, ', ')
	!}
]]

--- Create a 2D sampler.
---
--- @see V3DSampler2D
--- @param options V3DSampler2DOptions
--- @return V3DSampler2D
--- @v3d-nomethod
--- @v3d-constructor
--- local my_sampler = v3d.create_sampler2D {
--- 	format = v3d.uinteger(),
--- }
--- @v3d-example
--- local my_sampler = v3d.create_sampler2D {
--- 	format = v3d.number(),
--- 	wrap_u = 'repeat',
--- 	interpolate_v = 'linear',
--- }
--- @v3d-example
function v3d.create_sampler2D(options)
	local sampler = _create_instance('V3DSampler2D', options.label)
	options = options or {}
	sampler.options = {
		format = options.format,
		lens = options.lens or v3d.format_lens(options.format),
		interpolate = options.interpolate or 'nearest',
		wrap_u = options.wrap_u or 'clamp',
		wrap_v = options.wrap_v or 'clamp',
	}
	local environment = {
		first_component_offset = sampler.options.lens.offset,
		n_components = v3d.format_size(sampler.options.lens.out_format),
		options = sampler.options,
		_wrap_nearest_to_code = _wrap_nearest_to_code,
		_wrap_linear_to_code = _wrap_linear_to_code,
	}

	local template
	if sampler.options.interpolate == 'nearest' then
		template = _SAMPLER2D_TEMPLATE_NEAREST
	elseif sampler.options.interpolate == 'linear' then
		template = _SAMPLER2D_TEMPLATE_LINEAR
	else
		_v3d_internal_error('Invalid interpolation mode: ' .. sampler.options.interpolate)
	end

	template = 'return function(sampler, image, u, v)\n' .. template .. '\nend'

	local compiled_sampler = _v3d_apply_template(template, environment)
	compiled_sampler = compiled_sampler:gsub('$image', 'image')
	compiled_sampler = compiled_sampler:gsub('$u', 'u')
	compiled_sampler = compiled_sampler:gsub('$v', 'v')
	compiled_sampler = compiled_sampler:gsub('$return', 'return')
	compiled_sampler = _v3d_optimise_globals(compiled_sampler, true)
	compiled_sampler = _v3d_optimise_maths(compiled_sampler)
	compiled_sampler = table.concat(_v3d_normalise_code_lines(compiled_sampler), '\n')

	sampler.compiled_sampler = compiled_sampler
	--- @diagnostic disable-next-line: inject-field
	sampler.sample = assert(load(compiled_sampler))()
	return _finalise_instance(sampler)
end

----------------------------------------------------------------

-- TODO:
-- --- @param options V3DSampler3DOptions
-- --- @return V3DSampler3D
-- --- @v3d-nomethod
-- function v3d.create_sampler3D(options)
-- 	local sampler = _create_instance('V3DSampler3D', options.label)
-- 	sampler.options = options
-- 	--- @diagnostic disable-next-line: invisible
-- 	sampler.components = v3d.format_size(options.format)
-- 	return sampler
-- end

----------------------------------------------------------------

--- @param sampler V3DSampler1D
--- @param image_var string
--- @param u_var string
--- @return string
--- @v3d-nolog
--- @v3d-advanced
function v3d.sampler1d_embed_sample(sampler, image_var, u_var)
	local environment = {
		first_component_offset = sampler.options.lens.offset,
		n_components = v3d.format_size(sampler.options.lens.out_format),
		options = sampler.options,
		_wrap_nearest_to_code = _wrap_nearest_to_code,
		_wrap_linear_to_code = _wrap_linear_to_code,
	}

	local template
	if sampler.options.interpolate == 'nearest' then
		template = _SAMPLER1D_TEMPLATE_NEAREST
	elseif sampler.options.interpolate == 'linear' then
		template = _SAMPLER1D_TEMPLATE_LINEAR
	else
		_v3d_internal_error('Invalid interpolation mode: ' .. sampler.options.interpolate)
	end

	local compiled_sampler = _v3d_apply_template(template, environment)
	compiled_sampler = table.concat(_v3d_normalise_code_lines(compiled_sampler), '\n')
	compiled_sampler = compiled_sampler:gsub('$image', image_var)
	compiled_sampler = compiled_sampler:gsub('$u', u_var)

	return _finalise_instance(compiled_sampler)
end

--- @param sampler V3DSampler2D
--- @param image_var string
--- @param u_var string
--- @param v_var string
--- @return string
function v3d.sampler2d_embed_sample(sampler, image_var, u_var, v_var)
	local environment = {
		first_component_offset = sampler.options.lens.offset,
		n_components = v3d.format_size(sampler.options.lens.out_format),
		options = sampler.options,
		_wrap_nearest_to_code = _wrap_nearest_to_code,
		_wrap_linear_to_code = _wrap_linear_to_code,
	}

	local template
	if sampler.options.interpolate == 'nearest' then
		template = _SAMPLER2D_TEMPLATE_NEAREST
	elseif sampler.options.interpolate == 'linear' then
		template = _SAMPLER2D_TEMPLATE_LINEAR
	else
		_v3d_internal_error('Invalid interpolation mode: ' .. sampler.options.interpolate)
	end

	local compiled_sampler = _v3d_apply_template(template, environment)
	compiled_sampler = table.concat(_v3d_normalise_code_lines(compiled_sampler), '\n')
	compiled_sampler = compiled_sampler:gsub('$image', image_var)
	compiled_sampler = compiled_sampler:gsub('$u', u_var)
	compiled_sampler = compiled_sampler:gsub('$v', v_var)

	return _finalise_instance(compiled_sampler)
end

----------------------------------------------------------------

-- Note: these aren't actual implementations. The actual functions are loaded in
--       when the sampler is created.

--- Sample a value from the image at the specified coordinate.
---
--- The coordinate is a value between 0 and 1 inclusive, where 0 is the leftmost
--- pixel and 1 is the rightmost pixel. The coordinate is affected by the
--- sampler's wrapping mode.
---
--- This function will return the image values unpacked, i.e. if the image
--- format is a struct, the inner values of the pixel will be returned as
--- separate values.
---
--- Note, to wrap them into a struct, use `v3d.format_unbuffer_from`.
--- @param sampler V3DSampler1D
--- @param image V3DImage
--- @param u number
--- @return any ...
--- @v3d-generated
--- @v3d-nolog
--- Image format must be compatible with the sampler format
--- @v3d-validate v3d.format_is_compatible_with(image.format, sampler.options.format)
--- local my_sampler = v3d.create_sampler1D { format = v3d.number(), interpolate_u = 'linear' }
--- local my_image = v3d.create_image(v3d.number(), 2, 1, 1, 0)
--- v3d.image_view_set_pixel(v3d.image_view(my_image), 1, 0, 0, 10)
---
--- local single_value = v3d.sampler1d_sample(my_sampler, my_image, 0.5)
--- assert(math.abs(single_value - 5) < 0.0001)
--- @v3d-example 5
--- local rgb_format = v3d.struct { r = v3d.number(), g = v3d.number(), b = v3d.number() }
--- local my_sampler = v3d.create_sampler1D { format = rgb_format, interpolate_u = 'linear' }
--- local my_rgb_image = v3d.create_image(rgb_format, 2, 1, 1)
--- v3d.image_view_set_pixel(v3d.image_view(my_rgb_image), 1, 0, 0, { r = 10, g = 20, b = 30 })
---
--- -- note, the u value will be clamped to 1
--- -- b, g, r is the internal order of the struct (alphabetical)
--- local b, g, r = v3d.sampler1d_sample(my_sampler, my_rgb_image, 1.72)
--- assert(math.abs(r - 10) < 0.0001)
--- assert(math.abs(g - 20) < 0.0001)
--- assert(math.abs(b - 30) < 0.0001)
--- @v3d-example 8
--- local rgba_format = v3d.struct { r = v3d.number(), g = v3d.number(), b = v3d.number(), a = v3d.number() }
--- local my_sampler = v3d.create_sampler1D { format = rgba_format, interpolate_u = 'linear' }
--- local my_rgba_image = v3d.create_image(rgba_format, 2, 1, 1)
--- v3d.image_view_set_pixel(v3d.image_view(my_rgba_image), 1, 0, 0, { r = 10, g = 20, b = 30, a = 1 })
---
--- local rgba = v3d.format_unbuffer_from(rgba_format, { v3d.sampler1d_sample(my_sampler, my_rgba_image, 0.1) })
--- assert(math.abs(rgba.r - 1) < 0.0001)
--- assert(math.abs(rgba.g - 2) < 0.0001)
--- assert(math.abs(rgba.b - 3) < 0.0001)
--- assert(math.abs(rgba.a - 0.1) < 0.0001)
--- @v3d-example 6
function v3d.sampler1d_sample(sampler, image, u) end

--- @param sampler V3DSampler2D
--- @param image V3DImage
--- @param u number
--- @param v number
--- @return any ...
function v3d.sampler2d_sample(sampler, image, u, v) end

--- @param sampler V3DSampler3D
--- @param image V3DImage
--- @param u number
--- @param v number
--- @param w number
--- @return any ...
function v3d.sampler3d_sample(sampler, image, u, v, w) end

end ----------------------------------------------------------------------------

-- TODO: palette/rgb
-- TODO: util/support

-- #gen-type-methods
-- #gen-type-instances
-- #gen-generated-functions

return v3d
