
-- localise globals for performance
local type = type
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
	local methods = __type_methods[instance_type]
	local mt = __type_metatables[instance_type]
	local instances = __type_instances[instance_type]
	local hook = __type_create_hooks[instance_type]

	instance.__v3d_typename = instance_type
	instance.__v3d_label = label

	if methods then
		for k, v in pairs(methods) do
			instance[k] = v
		end
	end

	if mt then
		setmetatable(instance, mt)
	end

	if instances then
		table.insert(instances, instance)
	end

	return instance
end

--- @generic T
--- @param instance T
--- @return T
local function _finalise_instance(instance)
	--- @diagnostic disable-next-line: undefined-field
	local typename = instance.__v3d_typename
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
	local h = assert(io.open('v3d/artifacts/contextual_error.txt', 'w'))
	h:write(message)
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

	env.quote = function(text)
		return '\'' .. (text:gsub('[\\\'\n\t]', { ['\\'] = '\\\\', ['\''] = '\\\'', ['\n'] = '\\n', ['\t'] = '\\t' })) .. '\''
	end

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
--- @param indices string | nil
--- @return V3DLens
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

	if indices then
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
				lens = v3d.lens_get_index(lens, end_parts[i])
			end
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
--- @v3d-validate v3d.format_is_compatible(other.vertex_format, builder.vertex_format)
--- The other builder's face format must be compatible with this one's.
--- @v3d-validate v3d.format_is_compatible(other.face_format, builder.face_format)
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

--- Create a debug cube geometry builder.
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
function v3d.debug_cube(options)
	options = options or {}

	local vec3 = v3d.struct {
		x = v3d.number(),
		y = v3d.number(),
		z = v3d.number(),
	}
	local vertex_format = v3d.struct {
		position = vec3,
		normal = (options.include_normals == true or options.include_normals == 'vertex') and vec3 or nil,
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

	local function _add_vertex(x, y, z, normal, index)
		local vertex = {
			position = { x = x, y = y, z = z },
		}

		if options.include_normals == true or options.include_normals == 'vertex' then
			vertex.normal = normal
		end
		if options.include_indices == true or options.include_indices == 'vertex' then
			vertex.index = index
		end

		v3d.geometry_builder_add_vertex(builder, vertex)
	end

	local front_normal = { x = 0, y = 0, z = 1 }
	local front_index = 0
	_add_vertex(x - w / 2, y + h / 2, z + d / 2, front_normal, 0)
	_add_vertex(x - w / 2, y - h / 2, z + d / 2, front_normal, 1)
	_add_vertex(x + w / 2, y - h / 2, z + d / 2, front_normal, 2)
	_add_face('front', front_normal, front_index, 0)
	_add_vertex(x + w / 2, y - h / 2, z + d / 2, front_normal, 3)
	_add_vertex(x + w / 2, y + h / 2, z + d / 2, front_normal, 4)
	_add_vertex(x - w / 2, y + h / 2, z + d / 2, front_normal, 5)
	_add_face('front', front_normal, front_index, 1)

	local back_normal = { x = 0, y = 0, z = -1 }
	local back_index = 1
	_add_vertex(x - w / 2, y + h / 2, z - d / 2, back_normal, 6)
	_add_vertex(x + w / 2, y + h / 2, z - d / 2, back_normal, 7)
	_add_vertex(x + w / 2, y - h / 2, z - d / 2, back_normal, 8)
	_add_face('back', back_normal, back_index, 2)
	_add_vertex(x + w / 2, y - h / 2, z - d / 2, back_normal, 9)
	_add_vertex(x - w / 2, y - h / 2, z - d / 2, back_normal, 10)
	_add_vertex(x - w / 2, y + h / 2, z - d / 2, back_normal, 11)
	_add_face('back', back_normal, back_index, 3)

	local left_normal = { x = -1, y = 0, z = 0 }
	local left_index = 2
	_add_vertex(x - w / 2, y + h / 2, z - d / 2, left_normal, 12)
	_add_vertex(x - w / 2, y - h / 2, z - d / 2, left_normal, 13)
	_add_vertex(x - w / 2, y - h / 2, z + d / 2, left_normal, 14)
	_add_face('left', left_normal, left_index, 4)
	_add_vertex(x - w / 2, y - h / 2, z + d / 2, left_normal, 15)
	_add_vertex(x - w / 2, y + h / 2, z + d / 2, left_normal, 16)
	_add_vertex(x - w / 2, y + h / 2, z - d / 2, left_normal, 17)
	_add_face('left', left_normal, left_index, 5)

	local right_normal = { x = 1, y = 0, z = 0 }
	local right_index = 3
	_add_vertex(x + w / 2, y + h / 2, z + d / 2, right_normal, 18)
	_add_vertex(x + w / 2, y - h / 2, z + d / 2, right_normal, 19)
	_add_vertex(x + w / 2, y - h / 2, z - d / 2, right_normal, 20)
	_add_face('right', right_normal, right_index, 6)
	_add_vertex(x + w / 2, y - h / 2, z - d / 2, right_normal, 21)
	_add_vertex(x + w / 2, y + h / 2, z - d / 2, right_normal, 22)
	_add_vertex(x + w / 2, y + h / 2, z + d / 2, right_normal, 23)
	_add_face('right', right_normal, right_index, 7)

	local top_normal = { x = 0, y = 1, z = 0 }
	local top_index = 4
	_add_vertex(x - w / 2, y + h / 2, z - d / 2, top_normal, 24)
	_add_vertex(x - w / 2, y + h / 2, z + d / 2, top_normal, 25)
	_add_vertex(x + w / 2, y + h / 2, z + d / 2, top_normal, 26)
	_add_face('top', top_normal, top_index, 8)
	_add_vertex(x + w / 2, y + h / 2, z + d / 2, top_normal, 27)
	_add_vertex(x + w / 2, y + h / 2, z - d / 2, top_normal, 28)
	_add_vertex(x - w / 2, y + h / 2, z - d / 2, top_normal, 29)
	_add_face('top', top_normal, top_index, 9)

	local bottom_normal = { x = 0, y = -1, z = 0 }
	local bottom_index = 5
	_add_vertex(x - w / 2, y - h / 2, z + d / 2, bottom_normal, 30)
	_add_vertex(x - w / 2, y - h / 2, z - d / 2, bottom_normal, 31)
	_add_vertex(x + w / 2, y - h / 2, z - d / 2, bottom_normal, 32)
	_add_face('bottom', bottom_normal, bottom_index, 10)
	_add_vertex(x + w / 2, y - h / 2, z - d / 2, bottom_normal, 33)
	_add_vertex(x + w / 2, y - h / 2, z + d / 2, bottom_normal, 34)
	_add_vertex(x - w / 2, y - h / 2, z + d / 2, bottom_normal, 35)
	_add_face('bottom', bottom_normal, bottom_index, 11)

	return builder
end

end ----------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Pipelines -------------------------------------------------------------------
do -----------------------------------------------------------------------------

--- Name of a uniform variable for a pipeline.
--- @alias V3DUniformName string
--- Uniform names must be valid Lua identifiers
--- @v3d-validate self:match '^[%a_][%w_]*$'

----------------------------------------------------------------

--- A pipeline is a compiled, optimised function dedicated to rendering pixels
--- to one or more images. They are incredibly versatile, supporting 2D or 3D
--- rasterization with customisable per-pixel behaviour.
---
--- Pipelines are compiled from 'sources', which are just strings containing Lua
--- code. The exception to this is that pipeline source code is run through a
--- templating and macro engine before being compiled. This allows common
--- operations to be optimised by the library.
---
--- 'Uniform variables' are values that are bound to a pipeline and remain
--- constant during its execution. They can be used to pass values in from
--- outside the pipeline, for example passing a constant colour to a pipeline
--- from your code. Uniform variables can be written to and read by the caller
--- but cannot be modified by the pipeline itself. They may have any type, and
--- this is not checked by the pipeline.
---
--- @see v3d.pipeline_write_uniform
--- @see v3d.pipeline_read_uniform
--- @class V3DPipeline
--- Options that the pipeline was created with.
--- @field created_options V3DPipelineOptions
--- Options that the pipeline is using, accounting for default values.
--- @field used_options V3DPipelineOptions
--- TODO
--- @field compiled_sources { [string]: string }
--- TODO
--- @field compiled_source string
--- Table storing uniform values for the pipeline.
--- @field private uniforms table
--- @v3d-abstract

----------------------------------------------------------------

--- @class V3DPipelineSources
--- @field init string | nil
--- @field vertex string | nil
--- @field pixel string | nil
--- @field finish string | nil
--- @v3d-structural

--- Miscellaneous options used when creating a pipeline.
--- @class V3DPipelineOptions
--- Sources to compile the pipeline from. This field contains a map of source
--- name to source code.
--- @field sources V3DPipelineSources | nil
--- Formats of the images accessible to the pipeline. This field contains a map
--- of image name to image format.
--- @field image_formats { [string]: V3DFormat }
--- Format of vertex data within geometry passed to this pipeline during
--- rendering.
--- @field vertex_format V3DFormat
--- Format of face data within geometry passed to this pipeline during
--- rendering. If nil, face data will not be accessible from within pipeline
--- source code.
--- @field face_format V3DFormat | nil
--- Lens pointing to a 3-component/4-component number part of vertices. Must be
--- applicable to the vertex format.
--- @field position_lens V3DLens
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
--- @field reverse_horizontal_iteration boolean | nil
--- Whether to reverse the vertical iteration order when drawing rows of
--- horizontal pixels. If true, the Y value will decrease from bottom to top as
--- each row is drawn. Defaults to false.
--- @field reverse_vertical_iteration boolean | nil
--- If true, the v3d_event macro will be enabled in pipeline sources and timings
--- will be recorded. This may incur a performance penalty depending on the
--- macro's usage. Defaults to false, however v3debug will default this to true.
--- @field record_statistics boolean | nil
--- Label to assign to the pipeline.
--- @field label string | nil
--- @v3d-structural

-- TODO: culled_faces?
--- Statistics related to pipeline execution, recorded per-execution.
--- @class V3DPipelineStatistics
--- Total durations for each timer, including the time spent in any nested
--- timers. Timer names are defined by the pipeline's source code but include
--- 'parents', e.g. a nested timer will have a name like 'a/b'.
--- @field timers { [string]: number }
--- Number of times an event was recorded.
--- @field events { [string]: integer }
--- @v3d-untracked

----------------------------------------------------------------

--- @alias _V3DPipelineMacroCalls { macro_name: string, parameters: string[] }[]

local function _parse_parameters(s)
	local params = {}
	local i = 1
	local start = 1
	local in_string = nil

	while i <= #s do
		local char = s:sub(i, i)

		if char == in_string then
			in_string = nil
			i = i + 1
		elseif in_string then
			i = select(2, assert(s:find('[^\\\'"]+', i))) + 1
		elseif char == '\'' or char == '"' then
			in_string = char
			i = i + 1
		elseif char == '\\' then
			i = i + (in_string and 2 or 1)
		elseif char == '(' or char == '{' or char == '[' then
			local close = char == '(' and ')' or char == '{' and '}' or ']'
			i = select(2, assert(s:find('%b' .. char .. close, i))) + 1
		elseif char == ',' then
			table.insert(params, s:sub(start, i - 1))
			start = i + 1
			i = i + 1
		else
			i = select(2, assert(s:find('[^\\\'"(){}%[%],]+', i))) + 1
		end
	end

	if i > start then
		table.insert(params, s:sub(start))
	end

	for i = 1, #params do
		params[i] = params[i]
			:gsub('^%s+', ''):gsub('%s+$', '')
			:gsub('^["\'](.*)["\']$', function(content)
				return content:gsub('\\.', '%1')
			end)
	end

	return params
end

--- @param source string
--- @param aliases { [string]: fun(...: string): string }
--- @return string, _V3DPipelineMacroCalls
local function _process_pipeline_source_macro_calls(source, aliases)
	local calls = {}
	local i = 1

	source = '\n' .. source

	repeat
		local prefix, macro_name, params_str = source:match('(.-)([%w_]*v3d_[%w_]+)(%b())', i)
		if not prefix then
			break
		end

		if macro_name:sub(1, 4) == 'v3d_' then
			local params = _parse_parameters(params_str:sub(2, -2))
			local expand_macro_later = true

			if aliases[macro_name] then
				local ok, aliased_content = pcall(aliases[macro_name], table.unpack(params))

				if not ok then
					error('error while processing macro ' .. macro_name .. params_str .. ': ' .. aliased_content, 0)
				end

				source = source:sub(1, i + #prefix - 1)
				      .. aliased_content
				      .. source:sub(i + #prefix + #macro_name + #params_str)
				expand_macro_later = false
			end

			if expand_macro_later then
				table.insert(calls, { macro_name = macro_name, parameters = params })
				source = source:sub(1, i - 1 + #prefix)
				      .. '{! ' .. macro_name .. params_str .. ' !}'
				      .. source:sub(i + #prefix + #macro_name + #params_str)
				i = i + #prefix + 6 + #macro_name + #params_str
			end
		else
			i = i + #prefix + #macro_name
		end
	until false

	return source, calls
end

----------------------------------------------------------------

--- Write a value to a uniform variable.
---
--- Returns the shader.
--- @param pipeline V3DPipeline
--- @param name V3DUniformName
--- @param value any
--- @return V3DPipeline
--- @v3d-chainable
--- -- local my_pipeline = TODO()
--- -- v3d.pipeline_write_uniform(my_pipeline, 'my_uniform', 42)
--- @v3d-example 2
function v3d.pipeline_write_uniform(pipeline, name, value)
	--- @diagnostic disable-next-line: invisible
	pipeline.uniforms[name] = value
	return pipeline
end

--- Read a value from a uniform variable.
--- @param pipeline V3DPipeline
--- @param name V3DUniformName
--- @return any
--- @v3d-nolog
--- -- local my_pipeline = TODO()
--- -- v3d.pipeline_write_uniform(my_pipeline, 'my_uniform', 42)
--- -- local my_uniform_value = v3d.pipeline_read_uniform(my_pipeline, 'my_uniform')
--- -- assert(my_uniform_value == 42)
--- @v3d-example 2:4
function v3d.pipeline_read_uniform(pipeline, name)
	--- @diagnostic disable-next-line: invisible
	return pipeline.uniforms[name]
end

--- TODO
-- TODO: validations
-- TODO: examples
--- @param pipeline V3DPipeline
--- @param geometry V3DGeometry
--- @param views { [string]: V3DImageView }
--- @param transform V3DTransform | nil
--- @param model_transform V3DTransform | nil
--- @param viewport V3DImageRegion | nil
--- @return V3DPipelineStatistics
--- @v3d-generated
--- @v3d-constructor
function v3d.pipeline_render(pipeline, geometry, views, transform, model_transform, viewport)
	-- Generated at runtime based on pipeline settings.
	--- @diagnostic disable-next-line: missing-return
end

local _PIPELINE_INIT_CONSTANTS = [[
local _v3d_viewport_width, _v3d_viewport_height
local _v3d_viewport_min_x, _v3d_viewport_max_x
local _v3d_viewport_min_y, _v3d_viewport_max_y

do
	{% local any_image_name = next(options.image_formats) %}
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

{% for _, image_name in ipairs(_ENV.access_images) do %}
local {= get_image_local_variable(image_name) =} = _v3d_views.{= image_name =}.image
{% end %}

{% for _, view_name in ipairs(_ENV.access_view_indices) do %}
local _v3d_view_init_offset_{= view_name =} = _v3d_views.{= view_name =}.init_offset
local _v3d_image_width_{= view_name =} = _v3d_views.{= view_name =}.image.width
{% end %}
]]

-- locals: N(uniforms_accessed)
local _PIPELINE_INIT_UNIFORMS = [[
{% for _, name in ipairs(uniforms_accessed) do %}
local {= get_uniform_local_variable(name) =}
{% end %}
{% if #uniforms_accessed > 0 then %}
do
	local _v3d_uniforms = _v3d_pipeline.uniforms
	{% for _, name in ipairs(uniforms_accessed) do %}
	{= get_uniform_local_variable(name) =} = _v3d_uniforms[{= quote(name) =}]
	{% end %}
end
{% end %}
]]

-- locals: 8 + N(event_counters)
local _PIPELINE_INIT_STATISTICS = [[
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
]]

-- TODO
local _PIPELINE_INIT_IMAGES = [[
-- {% for _, layer in ipairs(fragment_shader.layers_accessed) do %}
-- local _v3d_layer_{= layer.name =} = _v3d_fb.layer_data['{= layer.name =}']
-- {% end %}
]]

local _PIPELINE_INIT_TRANSFORMS = [[
{% if _ENV.needs_fragment_world_position then %}
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

local _PIPELINE_INIT_FACE_VERTICES = [[
local _v3d_transformed_p0x, _v3d_transformed_p0y, _v3d_transformed_p0z,
      _v3d_transformed_p1x, _v3d_transformed_p1y, _v3d_transformed_p1z,
      _v3d_transformed_p2x, _v3d_transformed_p2y, _v3d_transformed_p2z

{% if _ENV.needs_fragment_world_position then %}
local _v3d_world_transformed_p0x, _v3d_world_transformed_p0y, _v3d_world_transformed_p0z,
      _v3d_world_transformed_p1x, _v3d_world_transformed_p1y, _v3d_world_transformed_p1z,
      _v3d_world_transformed_p2x, _v3d_world_transformed_p2y, _v3d_world_transformed_p2z
{% end %}

{% if _ENV.needs_face_world_normal then %}
local _v3d_face_world_normal0, _v3d_face_world_normal1, _v3d_face_world_normal2
{% end %}
do
	{% local position_base_offset = options.position_lens.offset %}
	{% local vertex_stride = options.vertex_format:size() %}
	local _v3d_p0x = _v3d_geometry[_v3d_vertex_offset + {= position_base_offset =}]
	local _v3d_p0y = _v3d_geometry[_v3d_vertex_offset + {= position_base_offset + 1 =}]
	local _v3d_p0z = _v3d_geometry[_v3d_vertex_offset + {= position_base_offset + 2 =}]
	local _v3d_p1x = _v3d_geometry[_v3d_vertex_offset + {= position_base_offset + vertex_stride =}]
	local _v3d_p1y = _v3d_geometry[_v3d_vertex_offset + {= position_base_offset + vertex_stride + 1 =}]
	local _v3d_p1z = _v3d_geometry[_v3d_vertex_offset + {= position_base_offset + vertex_stride + 2 =}]
	local _v3d_p2x = _v3d_geometry[_v3d_vertex_offset + {= position_base_offset + vertex_stride * 2 =}]
	local _v3d_p2y = _v3d_geometry[_v3d_vertex_offset + {= position_base_offset + vertex_stride * 2 + 1 =}]
	local _v3d_p2z = _v3d_geometry[_v3d_vertex_offset + {= position_base_offset + vertex_stride * 2 + 2 =}]

	{% if _ENV.needs_fragment_world_position then %}
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
	{% else %}
	_v3d_transformed_p0x = _v3d_transform_xx * _v3d_p0x + _v3d_transform_xy * _v3d_p0y + _v3d_transform_xz * _v3d_p0z + _v3d_transform_dx
	_v3d_transformed_p0y = _v3d_transform_yx * _v3d_p0x + _v3d_transform_yy * _v3d_p0y + _v3d_transform_yz * _v3d_p0z + _v3d_transform_dy
	_v3d_transformed_p0z = _v3d_transform_zx * _v3d_p0x + _v3d_transform_zy * _v3d_p0y + _v3d_transform_zz * _v3d_p0z + _v3d_transform_dz

	_v3d_transformed_p1x = _v3d_transform_xx * _v3d_p1x + _v3d_transform_xy * _v3d_p1y + _v3d_transform_xz * _v3d_p1z + _v3d_transform_dx
	_v3d_transformed_p1y = _v3d_transform_yx * _v3d_p1x + _v3d_transform_yy * _v3d_p1y + _v3d_transform_yz * _v3d_p1z + _v3d_transform_dy
	_v3d_transformed_p1z = _v3d_transform_zx * _v3d_p1x + _v3d_transform_zy * _v3d_p1y + _v3d_transform_zz * _v3d_p1z + _v3d_transform_dz

	_v3d_transformed_p2x = _v3d_transform_xx * _v3d_p2x + _v3d_transform_xy * _v3d_p2y + _v3d_transform_xz * _v3d_p2z + _v3d_transform_dx
	_v3d_transformed_p2y = _v3d_transform_yx * _v3d_p2x + _v3d_transform_yy * _v3d_p2y + _v3d_transform_yz * _v3d_p2z + _v3d_transform_dy
	_v3d_transformed_p2z = _v3d_transform_zx * _v3d_p2x + _v3d_transform_zy * _v3d_p2y + _v3d_transform_zz * _v3d_p2z + _v3d_transform_dz
	{% end %}

	{% if _ENV.needs_face_world_normal then %}
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

local _PIPELINE_RENDER_REGION_SETUP = [[
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

{% if _ENV.interpolate_world_position then %}
local _v3d_region_left_dwx_dy = (_v3d_rasterize_{= flat_triangle_bottom_left =}_wx - _v3d_rasterize_{= flat_triangle_top_left =}_wx) / _v3d_region_dy
local _v3d_region_left_dwy_dy = (_v3d_rasterize_{= flat_triangle_bottom_left =}_wy - _v3d_rasterize_{= flat_triangle_top_left =}_wy) / _v3d_region_dy
local _v3d_region_left_dwz_dy = (_v3d_rasterize_{= flat_triangle_bottom_left =}_wz - _v3d_rasterize_{= flat_triangle_top_left =}_wz) / _v3d_region_dy
local _v3d_region_right_dwx_dy = (_v3d_rasterize_{= flat_triangle_bottom_right =}_wx - _v3d_rasterize_{= flat_triangle_top_right =}_wx) / _v3d_region_dy
local _v3d_region_right_dwy_dy = (_v3d_rasterize_{= flat_triangle_bottom_right =}_wy - _v3d_rasterize_{= flat_triangle_top_right =}_wy) / _v3d_region_dy
local _v3d_region_right_dwz_dy = (_v3d_rasterize_{= flat_triangle_bottom_right =}_wz - _v3d_rasterize_{= flat_triangle_top_right =}_wz) / _v3d_region_dy
local _v3d_region_left_wx = _v3d_rasterize_{= flat_triangle_top_left =}_wx + _v3d_region_left_dwx_dy * _v3d_region_y_correction
local _v3d_region_left_wy = _v3d_rasterize_{= flat_triangle_top_left =}_wy + _v3d_region_left_dwy_dy * _v3d_region_y_correction
local _v3d_region_left_wz = _v3d_rasterize_{= flat_triangle_top_left =}_wz + _v3d_region_left_dwz_dy * _v3d_region_y_correction
local _v3d_region_right_wx = _v3d_rasterize_{= flat_triangle_top_right =}_wx + _v3d_region_right_dwx_dy * _v3d_region_y_correction
local _v3d_region_right_wy = _v3d_rasterize_{= flat_triangle_top_right =}_wy + _v3d_region_right_dwy_dy * _v3d_region_y_correction
local _v3d_region_right_wz = _v3d_rasterize_{= flat_triangle_top_right =}_wz + _v3d_region_right_dwz_dy * _v3d_region_y_correction
{% end %}

{% for _, idx in ipairs(_ENV.interpolate_vertex_indices) do %}
local _v3d_region_left_va_d{= idx =}w_dy = (_v3d_rasterize_{= flat_triangle_bottom_left =}_va_{= idx =} * _v3d_rasterize_{= flat_triangle_bottom_left =}_w - _v3d_rasterize_{= flat_triangle_top_left =}_va_{= idx =} * _v3d_rasterize_{= flat_triangle_top_left =}_w) / _v3d_region_dy
local _v3d_region_right_va_d{= idx =}w_dy = (_v3d_rasterize_{= flat_triangle_bottom_right =}_va_{= idx =} * _v3d_rasterize_{= flat_triangle_bottom_right =}_w - _v3d_rasterize_{= flat_triangle_top_right =}_va_{= idx =} * _v3d_rasterize_{= flat_triangle_top_right =}_w) / _v3d_region_dy
local _v3d_region_left_va_{= idx =}w = _v3d_rasterize_{= flat_triangle_top_left =}_va_{= idx =} * _v3d_rasterize_{= flat_triangle_top_left =}_w + _v3d_region_left_va_d{= idx =}w_dy * _v3d_region_y_correction
local _v3d_region_right_va_{= idx =}w = _v3d_rasterize_{= flat_triangle_top_right =}_va_{= idx =} * _v3d_rasterize_{= flat_triangle_top_right =}_w + _v3d_region_right_va_d{= idx =}w_dy * _v3d_region_y_correction
{% end %}
]]

local _PIPELINE_RENDER_REGION = [[
{! _PIPELINE_RENDER_REGION_SETUP !}

for _v3d_row = _v3d_row_{= flat_triangle_name =}_min, _v3d_row_{= flat_triangle_name =}_max do
	local _v3d_row_min_column = math.ceil(_v3d_region_left_x)
	local _v3d_row_max_column = math.ceil(_v3d_region_right_x)

	if _v3d_row_min_column < _v3d_viewport_min_x then _v3d_row_min_column = _v3d_viewport_min_x end
	if _v3d_row_max_column > _v3d_viewport_max_x then _v3d_row_max_column = _v3d_viewport_max_x end

	{% if _ENV.needs_interpolated_depth then %}
	local _v3d_row_x_correction = _v3d_row_min_column - _v3d_region_left_x
	local _v3d_row_dx = _v3d_region_right_x - _v3d_region_left_x
	local _v3d_row_dw_dx = (_v3d_region_right_w - _v3d_region_left_w) / _v3d_row_dx
	local _v3d_row_w = _v3d_region_left_w + _v3d_row_dw_dx * _v3d_row_x_correction
	{% end %}

	{% if _ENV.interpolate_world_position then %}
	local _v3d_row_dwx = (_v3d_region_right_wx - _v3d_region_left_wx) / _v3d_row_dx
	local _v3d_row_dwy = (_v3d_region_right_wy - _v3d_region_left_wy) / _v3d_row_dx
	local _v3d_row_dwz = (_v3d_region_right_wz - _v3d_region_left_wz) / _v3d_row_dx
	local _v3d_row_wx = _v3d_region_left_wx + _v3d_row_dwx * _v3d_row_x_correction
	local _v3d_row_wy = _v3d_region_left_wy + _v3d_row_dwy * _v3d_row_x_correction
	local _v3d_row_wz = _v3d_region_left_wz + _v3d_row_dwz * _v3d_row_x_correction
	{% end %}

	{% for _, idx in ipairs(_ENV.interpolate_vertex_indices) do %}
	local _v3d_row_va_d{= idx =}w_dx = (_v3d_region_right_va_{= idx =}w - _v3d_region_left_va_{= idx =}w) / _v3d_row_dx
	local _v3d_row_va_{= idx =}w = _v3d_region_left_va_{= idx =}w + _v3d_row_va_d{= idx =}w_dx * _v3d_row_x_correction
	{% end %}

	{% for _, view_name in ipairs(_ENV.access_view_indices) do %}
	local _v3d_view_base_index_{= view_name =} = _v3d_view_init_offset_{= view_name =} + (_v3d_image_width_{= view_name =} * _v3d_row + _v3d_row_min_column) * {= options.image_formats[view_name]:size() =}
	{% end %}

	-- TODO
	for _v3d_x = _v3d_row_min_column, _v3d_row_max_column do
		-- TODO: world position

		{% for _, idx in ipairs(_ENV.interpolate_vertex_indices) do %}
		local {= get_interpolated_vertex_index_local_variable(idx) =} = _v3d_row_va_{= idx =}w / _v3d_row_w
		{% end %}

		-- TODO: {= fragment_shader.is_called_is_fragment_discarded and 'local _v3d_builtin_fragment_discarded = false' or '' =}

		{! increment_statistic 'candidate_fragments' !}

		--#pipeline_source_start pixel
		{! PIXEL_SOURCE_EMBED !}
		--#pipeline_source_end pixel

		{% for _, view_name in ipairs(access_view_indices) do %}
		_v3d_view_base_index_{= view_name =} = _v3d_view_base_index_{= view_name =} + {= options.image_formats[view_name]:size() =}
		{% end %}

		{% if _ENV.needs_interpolated_depth then %}
		_v3d_row_w = _v3d_row_w + _v3d_row_dw_dx
		{% end %}

		-- TODO: world position

		{% for _, idx in ipairs(_ENV.interpolate_vertex_indices) do %}
		_v3d_row_va_{= idx =}w = _v3d_row_va_{= idx =}w + _v3d_row_va_d{= idx =}w_dx
		{% end %}
	end

	_v3d_region_left_x = _v3d_region_left_x + _v3d_region_left_dx_dy
	_v3d_region_right_x = _v3d_region_right_x + _v3d_region_right_dx_dy

	{% if _ENV.needs_interpolated_depth then %}
	_v3d_region_left_w = _v3d_region_left_w + _v3d_region_left_dw_dy
	_v3d_region_right_w = _v3d_region_right_w + _v3d_region_right_dw_dy
	{% end %}

	-- TODO: world position

	{% for _, idx in ipairs(_ENV.interpolate_vertex_indices) do %}
	_v3d_region_left_va_{= idx =}w = _v3d_region_left_va_{= idx =}w + _v3d_region_left_va_d{= idx =}w_dy
	_v3d_region_right_va_{= idx =}w = _v3d_region_right_va_{= idx =}w + _v3d_region_right_va_d{= idx =}w_dy
	{% end %}
end
]]

local _PIPELINE_RENDER_TRIANGLE_SORT_VERTICES = [[
{%
local to_swap = { '_v3d_rasterize_pN_x', '_v3d_rasterize_pN_y' }

if _ENV.needs_interpolated_depth then
	table.insert(to_swap, '_v3d_rasterize_pN_w')
end

if _ENV.interpolate_world_position then
	table.insert(to_swap, '_v3d_rasterize_pN_wx')
	table.insert(to_swap, '_v3d_rasterize_pN_wy')
	table.insert(to_swap, '_v3d_rasterize_pN_wz')
end

for _, idx in ipairs(_ENV.interpolate_vertex_indices) do
	table.insert(to_swap, get_vertex_index_local_variable('N', idx))
end

local function test_and_swap(a, b)
	local result = 'if _v3d_rasterize_pA_y > _v3d_rasterize_pB_y then\n'

	for i = 1, #to_swap do
		local sA = to_swap[i]:gsub('N', 'A')
		local sB = to_swap[i]:gsub('N', 'B')
		result = result .. '\t' .. sA .. ', ' .. sB .. ' = ' .. sB .. ', ' .. sA .. '\n'
	end

	return (result .. 'end'):gsub('A', a):gsub('B', b)
end
%}

{= test_and_swap(0, 1) =}
{= test_and_swap(1, 2) =}
{= test_and_swap(0, 1) =}
]]

local _PIPELINE_RENDER_TRIANGLE_CALCULATE_FLAT_MIDPOINT = [[
local _v3d_rasterize_pM_x
{% if _ENV.needs_interpolated_depth then %}
local _v3d_rasterize_pM_w
{% end %}
{% if _ENV.interpolate_world_position then %}
local _v3d_rasterize_pM_wx
local _v3d_rasterize_pM_wy
local _v3d_rasterize_pM_wz
{% end %}
{% for _, idx in ipairs(_ENV.interpolate_vertex_indices) do %}
local {= get_vertex_index_local_variable('M', idx) =}
{% end %}

do
	local _v3d_midpoint_scalar = (_v3d_rasterize_p1_y - _v3d_rasterize_p0_y) / (_v3d_rasterize_p2_y - _v3d_rasterize_p0_y)
	local _v3d_midpoint_scalar_inv = 1 - _v3d_midpoint_scalar
	_v3d_rasterize_pM_x = _v3d_rasterize_p0_x * _v3d_midpoint_scalar_inv + _v3d_rasterize_p2_x * _v3d_midpoint_scalar

	{% if _ENV.needs_interpolated_depth then %}
	_v3d_rasterize_pM_w = _v3d_rasterize_p0_w * _v3d_midpoint_scalar_inv + _v3d_rasterize_p2_w * _v3d_midpoint_scalar
	{% end %}

	{% if _ENV.interpolate_world_position then %}
	_v3d_rasterize_pM_wx = _v3d_rasterize_p0_wx * _v3d_midpoint_scalar_inv + _v3d_rasterize_p2_wx * _v3d_midpoint_scalar
	_v3d_rasterize_pM_wy = _v3d_rasterize_p0_wy * _v3d_midpoint_scalar_inv + _v3d_rasterize_p2_wy * _v3d_midpoint_scalar
	_v3d_rasterize_pM_wz = _v3d_rasterize_p0_wz * _v3d_midpoint_scalar_inv + _v3d_rasterize_p2_wz * _v3d_midpoint_scalar
	{% end %}

	{% for _, idx in ipairs(_ENV.interpolate_vertex_indices) do %}
		{% local mid_name = get_vertex_index_local_variable('M', idx) %}
		{% local p0_name = get_vertex_index_local_variable(0, idx) %}
		{% local p2_name = get_vertex_index_local_variable(2, idx) %}
	{= mid_name =} = ({= p0_name =} * _v3d_rasterize_p0_w * _v3d_midpoint_scalar_inv + {= p2_name =} * _v3d_rasterize_p2_w * _v3d_midpoint_scalar) / _v3d_rasterize_pM_w
	{% end %}
end

if _v3d_rasterize_pM_x > _v3d_rasterize_p1_x then
	_v3d_rasterize_pM_x, _v3d_rasterize_p1_x = _v3d_rasterize_p1_x, _v3d_rasterize_pM_x

	{% if _ENV.needs_interpolated_depth then %}
	_v3d_rasterize_pM_w, _v3d_rasterize_p1_w = _v3d_rasterize_p1_w, _v3d_rasterize_pM_w
	{% end %}

	{% if _ENV.interpolate_world_position then %}
	_v3d_rasterize_pM_wx, _v3d_rasterize_p1_wx = _v3d_rasterize_p1_wx, _v3d_rasterize_pM_wx
	_v3d_rasterize_pM_wy, _v3d_rasterize_p1_wy = _v3d_rasterize_p1_wy, _v3d_rasterize_pM_wy
	_v3d_rasterize_pM_wz, _v3d_rasterize_p1_wz = _v3d_rasterize_p1_wz, _v3d_rasterize_pM_wz
	{% end %}

	{% for _, idx in ipairs(_ENV.interpolate_vertex_indices) do %}
		{% local mid_name = get_vertex_index_local_variable('M', idx) %}
		{% local p1_name = get_vertex_index_local_variable(1, idx) %}
	{= mid_name =}, {= p1_name =} = {= p1_name =}, {= mid_name =}
	{% end %}
end
]]

-- TODO
local _PIPELINE_RENDER_TRIANGLE = [[
{! start_timer('rasterize') !}
{! _PIPELINE_RENDER_TRIANGLE_SORT_VERTICES !}
{! _PIPELINE_RENDER_TRIANGLE_CALCULATE_FLAT_MIDPOINT !}

-- TODO
-- {% for _, attr in ipairs(fragment_shader.face_attribute_max_pixel_deltas) do %}
-- local _v3d_face_attribute_max_pixel_delta_${attr.name}${attr.component}
-- {% end %}

-- TODO
-- {% if #fragment_shader.face_attribute_max_pixel_deltas > 0 then %}
-- do
-- 	local dx_0_1 = _v3d_rasterize_p1_x - _v3d_rasterize_p0_x
-- 	local dx_0_2 = _v3d_rasterize_p2_x - _v3d_rasterize_p0_x
-- 	local dx_1_2 = _v3d_rasterize_p2_x - _v3d_rasterize_p1_x
-- 	local dy_0_1 = _v3d_rasterize_p1_y - _v3d_rasterize_p0_y
-- 	local dy_0_2 = _v3d_rasterize_p2_y - _v3d_rasterize_p0_y
-- 	local dy_1_2 = _v3d_rasterize_p2_y - _v3d_rasterize_p1_y
-- 	local len_0_1 = _v3d_math_sqrt(dx_0_1 * dx_0_1 + dy_0_1 * dy_0_1)
-- 	local len_0_2 = _v3d_math_sqrt(dx_0_2 * dx_0_2 + dy_0_2 * dy_0_2)
-- 	local len_1_2 = _v3d_math_sqrt(dx_1_2 * dx_1_2 + dy_1_2 * dy_1_2)

-- 	{% for _, attr in ipairs(fragment_shader.face_attribute_max_pixel_deltas) do %}
-- 	local d_attr_${attr.name}${attr.component}_0_1 = _v3d_rasterize_p1_va_${attr.name}${attr.component} - _v3d_rasterize_p0_va_${attr.name}${attr.component}
-- 	local d_attr_${attr.name}${attr.component}_0_2 = _v3d_rasterize_p2_va_${attr.name}${attr.component} - _v3d_rasterize_p0_va_${attr.name}${attr.component}
-- 	local d_attr_${attr.name}${attr.component}_1_2 = _v3d_rasterize_p2_va_${attr.name}${attr.component} - _v3d_rasterize_p1_va_${attr.name}${attr.component}
-- 	_v3d_face_attribute_max_pixel_delta_${attr.name}${attr.component} = _v3d_math_min(
-- 		len_0_1 / _v3d_math_abs(d_attr_${attr.name}${attr.component}_0_1),
-- 		len_0_2 / _v3d_math_abs(d_attr_${attr.name}${attr.component}_0_2),
-- 		len_1_2 / _v3d_math_abs(d_attr_${attr.name}${attr.component}_1_2)
-- 	)
-- 	{% end %}
-- end
-- {% end %}

local _v3d_row_top_min = math.floor(_v3d_rasterize_p0_y + 0.5)
local _v3d_row_top_max = math.floor(_v3d_rasterize_p1_y - 0.5)
local _v3d_row_bottom_min = _v3d_row_top_max + 1
local _v3d_row_bottom_max = math.ceil(_v3d_rasterize_p2_y - 0.5)

if _v3d_row_top_min < _v3d_viewport_min_y then _v3d_row_top_min = _v3d_viewport_min_y end
if _v3d_row_bottom_min < _v3d_viewport_min_y then _v3d_row_bottom_min = _v3d_viewport_min_y end
if _v3d_row_top_max > _v3d_viewport_max_y then _v3d_row_top_max = _v3d_viewport_max_y end
if _v3d_row_bottom_max > _v3d_viewport_max_y then _v3d_row_bottom_max = _v3d_viewport_max_y end

local _v3d_region_dy

_v3d_region_dy = _v3d_rasterize_p1_y - _v3d_rasterize_p0_y
if _v3d_region_dy > 0 then
	{%
	local flat_triangle_name = 'top'
	local flat_triangle_top_left = 'p0'
	local flat_triangle_top_right = 'p0'
	local flat_triangle_bottom_left = 'pM'
	local flat_triangle_bottom_right = 'p1'
	%}

	{! _PIPELINE_RENDER_REGION !}
end

_v3d_region_dy = _v3d_rasterize_p2_y - _v3d_rasterize_p1_y
if _v3d_region_dy > 0 then
	{%
	local flat_triangle_name = 'bottom'
	local flat_triangle_top_left = 'pM'
	local flat_triangle_top_right = 'p1'
	local flat_triangle_bottom_left = 'p2'
	local flat_triangle_bottom_right = 'p2'
	%}

	{! _PIPELINE_RENDER_REGION !}
end

{! stop_timer('rasterize') !}
]]

-- TODO
-- uses environment: interpolate_vertex_indices, interpolate_world_position, needs_interpolated_depth, needs_fragment_world_position, needs_face_world_normal
-- uses utility: increment_statistic
local _PIPELINE_RENDER_FACE = [[
{! start_timer('process_vertices') !}
{! _PIPELINE_INIT_FACE_VERTICES !}

{% for _, idx in ipairs(_ENV.access_face_indices) do %}
local {= get_face_attribute_local_variable(idx) =} = _v3d_geometry[_v3d_face_offset + {= idx =}]
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
{% local clipping_plane = 0.0001 %}
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

	{% if interpolate_world_position then %}
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

	{% for _, idx in ipairs(interpolate_vertex_indices) do %}
	local {= get_vertex_index_local_variable(0, idx) =} = _v3d_geometry[_v3d_vertex_offset + {= idx =}]
	local {= get_vertex_index_local_variable(1, idx) =} = _v3d_geometry[_v3d_vertex_offset + {= idx + options.vertex_format:size() =}]
	local {= get_vertex_index_local_variable(2, idx) =} = _v3d_geometry[_v3d_vertex_offset + {= idx + options.vertex_format:size() * 2 =}]
	{% end %}

	{! stop_timer('process_vertices') !}

	{! _PIPELINE_RENDER_TRIANGLE !}
	{! increment_statistic 'drawn_faces' !}
else
	{! increment_statistic 'discarded_faces' !}
end

{% if options.cull_faces then %}
else
	{! increment_statistic 'discarded_faces' !}
end
{% end %}

_v3d_vertex_offset = _v3d_vertex_offset + {= options.vertex_format:size() * 3 =}
{% if options.face_format then %}
_v3d_face_offset = _v3d_face_offset + {= options.face_format:size() =}
{% end %}
]]

local _PIPELINE_RETURN_STATISTICS_TOTAL_TIMER_VALUE = [[
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

local _PIPELINE_RETURN_STATISTICS_EVENT_VALUE = [[
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

local _PIPELINE_RETURN_STATISTICS = [[
-- _v3d_create_instance, _v3d_finalise_instance
{% if options.record_statistics then %}
	local _v3d_return_statistics = _v3d_create_instance('V3DPipelineStatistics')
	_v3d_return_statistics.timers = {! _PIPELINE_RETURN_STATISTICS_TOTAL_TIMER_VALUE !}
	_v3d_return_statistics.events = {! _PIPELINE_RETURN_STATISTICS_EVENT_VALUE !}
	return _v3d_finalise_instance(_v3d_return_statistics)
{% else %}
	return {
		timers = {! _PIPELINE_RETURN_STATISTICS_TOTAL_TIMER_VALUE !},
		events = {! _PIPELINE_RETURN_STATISTICS_EVENT_VALUE !},
	}
{% end %}
]]

local _PIPELINE_RENDER_MAIN = [[
local _v3d_create_instance, _v3d_finalise_instance = ...
return function(_v3d_pipeline, _v3d_geometry, _v3d_views, _v3d_transform, _v3d_model_transform, _v3d_viewport)
	{! start_timer('render') !}

	{! _PIPELINE_INIT_CONSTANTS !}
	{! _PIPELINE_INIT_UNIFORMS !}
	{! _PIPELINE_INIT_STATISTICS !}
	{! _PIPELINE_INIT_IMAGES !}
	{! _PIPELINE_INIT_TRANSFORMS !}

	local _v3d_vertex_offset = _v3d_geometry.vertex_offset + 1
	local _v3d_face_offset = 1

	for _ = 1, _v3d_geometry.n_vertices, 3 do
		{! _PIPELINE_RENDER_FACE !}
	end

	{! stop_timer('render') !}

	{! _PIPELINE_RETURN_STATISTICS !}
end
]]

local DEFAULT_PIPELINE_PIXEL_SOURCE = [[
v3d_set_pixel_flat(colour, 2 ^ v3d_face_flat('index'))
]]

--- TODO
--- @param options V3DPipelineOptions
--- @return V3DPipeline
--- @v3d-constructor
-- TODO: validations
-- TODO: examples
function v3d.compile_pipeline(options)
	local pipeline = _create_instance('V3DPipeline', options.label)

	local clock_function_str = ccemux and 'ccemux.nanoTime() / 1000000000' or 'os.clock()'

	local actual_options = {}
	actual_options.sources = {}
	actual_options.sources.init = options.sources and options.sources.init or ""
	actual_options.sources.finish = options.sources and options.sources.finish or ""
	actual_options.sources.vertex = options.sources and options.sources.vertex or ""
	actual_options.sources.pixel = options.sources and options.sources.pixel or DEFAULT_PIPELINE_PIXEL_SOURCE
	actual_options.image_formats = options.image_formats
	actual_options.vertex_format = options.vertex_format
	actual_options.face_format = options.face_format or nil
	actual_options.position_lens = options.position_lens
	actual_options.cull_faces = options.cull_faces or 'back'
	actual_options.pixel_aspect_ratio = options.pixel_aspect_ratio or 1
	actual_options.reverse_horizontal_iteration = options.reverse_horizontal_iteration or false
	actual_options.reverse_vertical_iteration = options.reverse_vertical_iteration or false
	actual_options.record_statistics = options.record_statistics or false
	actual_options.flat_interpolation = false
	actual_options.label = options.label

	--- @diagnostic disable-next-line: invisible
	pipeline.uniforms = {}
	pipeline.created_options = options
	pipeline.used_options = actual_options
	-- TODO: pipeline.compiled_sources
	-- TODO: pipeline.compiled_source

	local _environment = {}
	_environment.options = actual_options
	_environment._PIPELINE_INIT_CONSTANTS = _PIPELINE_INIT_CONSTANTS
	_environment._PIPELINE_INIT_UNIFORMS = _PIPELINE_INIT_UNIFORMS
	_environment._PIPELINE_INIT_STATISTICS = _PIPELINE_INIT_STATISTICS
	_environment._PIPELINE_INIT_IMAGES = _PIPELINE_INIT_IMAGES
	_environment._PIPELINE_INIT_TRANSFORMS = _PIPELINE_INIT_TRANSFORMS
	_environment._PIPELINE_INIT_FACE_VERTICES = _PIPELINE_INIT_FACE_VERTICES
	_environment._PIPELINE_RENDER_REGION_SETUP = _PIPELINE_RENDER_REGION_SETUP
	_environment._PIPELINE_RENDER_REGION = _PIPELINE_RENDER_REGION
	_environment._PIPELINE_RENDER_TRIANGLE_SORT_VERTICES = _PIPELINE_RENDER_TRIANGLE_SORT_VERTICES
	_environment._PIPELINE_RENDER_TRIANGLE_CALCULATE_FLAT_MIDPOINT = _PIPELINE_RENDER_TRIANGLE_CALCULATE_FLAT_MIDPOINT
	_environment._PIPELINE_RENDER_TRIANGLE = _PIPELINE_RENDER_TRIANGLE
	_environment._PIPELINE_RENDER_FACE = _PIPELINE_RENDER_FACE
	_environment._PIPELINE_RETURN_STATISTICS_TOTAL_TIMER_VALUE = _PIPELINE_RETURN_STATISTICS_TOTAL_TIMER_VALUE
	_environment._PIPELINE_RETURN_STATISTICS_EVENT_VALUE = _PIPELINE_RETURN_STATISTICS_EVENT_VALUE
	_environment._PIPELINE_RETURN_STATISTICS = _PIPELINE_RETURN_STATISTICS

	_environment.uniforms_accessed = {}
	_environment.access_images = {}
	_environment.access_view_indices = {}
	_environment.access_face_indices = { set = {} }
	_environment.interpolate_vertex_indices = { set = {} }
	_environment.event_counters_updated = {}
	_environment.timers_updated = {}
	_environment.interpolate_world_position = false
	_environment.needs_fragment_world_position = false
	_environment.needs_face_world_normal = false
	_environment.needs_interpolated_depth = false
	_environment.timer_stack = {}

	local function TODO() error('TODO') end

	----------------------------------------------------------------------------

	--- @diagnostic disable: return-type-mismatch
	--- @diagnostic disable: unused-local
	--- @diagnostic disable: missing-return-value

	--- @v3d-macro -- TODO
	function _environment.v3d_uniform(name)
		if not _environment.uniforms_accessed[name] then
			_environment.uniforms_accessed[name] = true
			table.insert(_environment.uniforms_accessed, name)
		end

		return _environment.get_uniform_local_variable(name)
	end

	--- Record an event. This only has an effect when the pipeline has event
	--- recording enabled.
	--- @param name string
	--- @param count integer | nil
	--- @return nil
	function _environment.v3d_event(name, count)
		if not actual_options.record_statistics then
			return ''
		end

		if not _environment.event_counters_updated[name] then
			_environment.event_counters_updated[name] = true
			table.insert(_environment.event_counters_updated, name)
		end

		local varname = _environment.get_event_counter_local_variable(name)
		return varname .. ' = ' .. varname .. ' + ' .. tostring(count or 1)
	end

	--- Return whether the depth represented by `a` is closer than the depth
	--- represented by `b`.
	--- @param a number
	--- @param b number
	--- @return boolean
	function _environment.v3d_compare_depth(a, b)
		return '(' .. a .. ' > ' .. b .. ')'
	end

	-- TODO: local w, h, d, fmt = v3d_image(image, 'whdf')
	-- allow rx, ry, rz, rw, rh, rd too?
	--- Return a named image object being used in this pipeline's execution.
	--- TODO: Note: v3d optimises accessing image fields if they immediately follow this
	---       macro invocation. For example:
	--- ```lua
	--- local width = v3d_image('my_image').width -- optimised
	--- local image = v3d_image('my_image')
	--- local width = image.width -- not optimised
	--- ```
	--- @param name string
	--- @return V3DImage
	function _environment.v3d_image(name)
		if not _environment.access_images[name] then
			_environment.access_images[name] = true
			table.insert(_environment.access_images, name)
		end

		return _environment.get_image_local_variable(name)
	end
	--- @param name string
	--- @return V3DImageView
	function _environment.v3d_image_view(name)
		return '_v3d_views[\'' .. name .. '\']'
	end

	-- plus something for views?

	----------------------------------------------------------------

	-- --- Return one or more position values of the current pixel.
	-- --- @param xyzuvw string
	-- --- @param reference_image string | nil
	-- --- @return integer ...
	-- function _environment.v3d_pixel_position(xyzuvw, reference_image)
	-- 	if not absolute then
	-- 		return 'v3d_pixel_position(' .. lens .. ', ' .. xyzuvw .. ', relative)'
	-- 	end

	-- 	if #xyzuvw > 1 then
	-- 		local t = {}
	-- 		for i = 1, #xyzuvw do
	-- 			table.insert(t, 'v3d_pixel_position(' .. lens .. ', ' .. xyzuvw:sub(i, i) .. ', ' .. absolute .. ')')
	-- 		end
	-- 		return table.concat(t, ', ')
	-- 	end

	-- 	assert(xyzuvw == 'x' or xyzuvw == 'y' or xyzuvw == 'z' or xyzuvw == 'u' or xyzuvw == 'v' or xyzuvw == 'w')
	-- 	assert(not absolute or absolute == 'absolute' or absolute == 'relative')
	-- 	return MACRO_EXPAND_LATER
	-- end

	--- @param lens string
	--- @return integer
	function _environment.v3d_pixel_index(lens)
		-- TODO
		local view_name, rest = lens:match '^([%w_]+)%.?(.*)$'

		if not _environment.access_view_indices[view_name] then
			_environment.access_view_indices[view_name] = true
			table.insert(_environment.access_view_indices, view_name)
		end

		local l = v3d.format_lens(options.image_formats[view_name], rest)
		return l.offset .. ' + _v3d_view_base_index_' .. view_name
	end

	--- @param lens string
	--- @return any
	function _environment.v3d_pixel(lens)
		return TODO()
	end

	--- @param lens string
	--- @return any ...
	function _environment.v3d_pixel_flat(lens)
		local view_name, rest = lens:match '^([%w_]+)%.?(.*)$'
		local elements = {}
		local l = v3d.format_lens(options.image_formats[view_name], rest)

		for i = 1, v3d.format_size(l.out_format) do
			table.insert(elements, 'v3d_image(\'' .. view_name .. '\')[' .. (i - 1) .. ' + v3d_pixel_index(' .. lens .. ')]')
		end

		return table.concat(elements, ', ')
	end

	--- @param lens string
	--- @param value any
	--- @return nil
	function _environment.v3d_set_pixel(lens, value)
		return TODO()
	end

	--- @param lens string
	--- @param ... any
	--- @return nil
	function _environment.v3d_set_pixel_flat(lens, ...)
		local values = { ... }
		local view_name, rest = lens:match '^([%w_]+)%.?(.*)$'
		local l = v3d.format_lens(options.image_formats[view_name], rest)
		local lines = {}

		for i = 1, v3d.format_size(l.out_format) do
			table.insert(lines, 'v3d_image(\'' .. view_name .. '\')[' .. (i - 1) .. ' + v3d_pixel_index(' .. lens .. ')] = ' .. values[i])
		end

		return table.concat(lines, '\n')
	end

	-- TODO: methods for getting offsets and getting/setting values at those offsets

	--- @param lens string
	--- @return any
	function _environment.v3d_face(lens)
		TODO()
	end

	--- @param lens string
	--- @return any
	function _environment.v3d_face_flat(lens)
		-- TODO: validate lens
		local l = v3d.format_lens(actual_options.face_format, lens)
		local indices = {}

		for i = 0, v3d.format_size(l.out_format) - 1 do
			local index = l.offset + i
			if not _environment.access_face_indices.set[index] then
				_environment.access_face_indices.set[index] = true
				table.insert(_environment.access_face_indices, index)
			end
			table.insert(indices, _environment.get_face_attribute_local_variable(index))
		end

		return table.concat(indices, ', ')
	end

	--- @param lens string
	--- @return any
	function _environment.v3d_vertex(lens)
		return TODO()
	end

	--- @param lens string
	--- @return any
	function _environment.v3d_vertex_flat(lens)
		-- TODO: validate lens
		local l = v3d.format_lens(actual_options.vertex_format, lens)
		local indices = {}

		for i = 0, v3d.format_size(l.out_format) - 1 do
			local index = l.offset + i
			if not _environment.interpolate_vertex_indices.set[index] then
				_environment.needs_interpolated_depth = true
				_environment.interpolate_vertex_indices.set[index] = true
				table.insert(_environment.interpolate_vertex_indices, index)
			end
			table.insert(indices, _environment.get_interpolated_vertex_index_local_variable(index))
		end

		return table.concat(indices, ', ')
	end

	--- @return number
	function _environment.v3d_vertex_depth(lens)
		_environment.needs_interpolated_depth = true
		return '_v3d_row_w'
	end

	--- TODO
	function _environment.v3d_vertex_world_position()
		return TODO()
	end

	--- TODO
	--- @return number, number, number
	function _environment.v3d_vertex_world_position_flat()
		_environment.interpolate_world_position = true
		_environment.needs_fragment_world_position = false
		_environment.needs_interpolated_depth = true

		return '_v3d_row_wx', '_v3d_row_wy', '_v3d_row_wz'
	end

	--- TODO
	--- @return number, number, number
	function _environment.v3d_face_world_normal()
		_environment.needs_face_world_normal = true
		return '_v3d_face_world_normal0', '_v3d_face_world_normal1', '_v3d_face_world_normal2'
	end

	--- @diagnostic enable: return-type-mismatch
	--- @diagnostic enable: unused-local
	--- @diagnostic enable: missing-return-value

	----------------------------------------------------------------------------

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

	function _environment.get_event_counter_local_variable(name)
		return '_v3d_event_counter_' .. name
	end

	function _environment.get_timer_start_local_variable(name)
		return '_v3d_timer_start_' .. name:gsub('[^%w_]', '_')
	end

	function _environment.get_timer_local_variable(name)
		return '_v3d_timer_total_' .. name:gsub('[^%w_]', '_')
	end

	function _environment.get_uniform_local_variable(name)
		return '_v3d_uniforms_' .. name
	end

	function _environment.get_image_local_variable(image_name)
		return '_v3d_image_' .. image_name
	end

	function _environment.get_vertex_index_local_variable(vertex, index)
		return '_v3d_rasterize_p' .. vertex .. '_va_' .. index
	end

	function _environment.get_interpolated_vertex_index_local_variable(index)
		return '_v3d_va_interpolated_' .. index
	end

	function _environment.get_face_attribute_local_variable(index)
		return '_v3d_fa_' .. index
	end

	function _environment.increment_statistic(name)
		if not actual_options.record_statistics then
			return ''
		end

		return '{! v3d_event(\'' .. name .. '\') !}'
	end

	local pixel_source = _v3d_apply_template(actual_options.sources.pixel, _environment)
	pixel_source = _process_pipeline_source_macro_calls(pixel_source, _environment)

	_environment.PIXEL_SOURCE_EMBED = pixel_source

	local content = _v3d_apply_template(_PIPELINE_RENDER_MAIN, _environment)
	content = _v3d_optimise_globals(content, true)

	local f, err = load(content, '=render', nil, _ENV)
	if f then
		--- @diagnostic disable-next-line: inject-field
		pipeline.render = f(_create_instance, _finalise_instance)
	else
		_v3d_contextual_error(err, content)
	end

	local h = assert(io.open('/v3d/artifacts/pipeline.lua', 'w'))
	h:write(content)
	h:close()

	return _finalise_instance(pipeline)
end

end ----------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Samplers --------------------------------------------------------------------
do -----------------------------------------------------------------------------

--- Sampler wrapping determines what happens to image coordinates that lie
--- outside the 0-1 inclusive range.
---
--- * `clamp`: Coordinates are clamped to the 0-1 inclusive range.
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
--- Wrapping mode for the U coordinate. Defaults to `clamp`.
---
--- @see V3DSamplerWrap
--- @field wrap_u V3DSamplerWrap | nil
--- Interpolation mode for the U coordinate. Defaults to `nearest`.
---
--- @see V3DSamplerInterpolation
--- @field interpolate_u V3DSamplerInterpolation | nil
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
--- Interpolation mode for the V coordinate. Defaults to `nearest`.
---
--- @see V3DSamplerInterpolation
--- @field interpolate_v V3DSamplerInterpolation | nil
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
--- Interpolation mode for the W coordinate. Defaults to `nearest`.
---
--- @see V3DSamplerInterpolation
--- @field interpolate_w V3DSamplerInterpolation | nil
--- @v3d-structural

----------------------------------------------------------------

local _SAMPLER1D_TEMPLATE = [[
return function(sampler, image, u)
	local image_width = image.width
	local image_width2 = image_width + image_width

	{% if options.interpolate_u == 'nearest' then %}
		{% if options.wrap_u == 'clamp' then %}
			local x = math.floor(u * image_width)
			if x < 0 then x = 0
			elseif x >= image_width then x = image_width - 1 end
		{% elseif options.wrap_u == 'repeat' then %}
			local umod1 = u % 1
			if umod1 == 0 then
				u = u % 2
			else
				u = umod1
			end
			local x = math.floor(u * image_width)
			if x == image_width then x = image_width - 1 end
		{% elseif options.wrap_u == 'mirror' then %}
			local x = math.floor((u % 2) * image_width)
			if x >= image_width then
				x = image_width2 - x - 1
			end
		{% end %}

		return
		{% for i = 1, components do %}
			{% if i > 1 then %}, {% end %}
			image[${i} + x * ${components}]
		{% end %}
	{% elseif options.interpolate_u == 'linear' then %}
		{% if options.wrap_u == 'clamp' then %}
			local x = u * (image_width - 1)

			if x <= 0 then
				return
				{% for i = 1, components do %}
					{% if i > 1 then %}, {% end %}
					image[${i}]
				{% end %}
			elseif x >= image_width - 1 then
				local last_pixel = (image_width - 1) * ${components}
				return
				{% for i = 1, components do %}
					{% if i > 1 then %}, {% end %}
					image[last_pixel + ${i}]
				{% end %}
			end

			local x0 = math.floor(x)
			local x1 = x0 + 1
			local xt1 = x - x0
			local xt0 = 1 - xt1
		{% elseif options.wrap_u == 'repeat' then %}
			u = u % 1

			local x = u * (image_width - 1)
			local x0 = math.floor(x)
			local x1 = x0 + 1
			local xt1 = x - x0
			local xt0 = 1 - xt1

			x0 = x0 % image_width
			x1 = x1 % image_width
		{% elseif options.wrap_u == 'mirror' then %}
			u = u % 2

			local x = u * (image_width - 1)
			local x0 = math.floor(x)
			local x1 = x0 + 1
			local xt1 = x - x0
			local xt0 = 1 - xt1

			x0 = x0 % image_width
			x1 = x1 % image_width
		{% end %}

		return
		{% for i = 1, components do %}
			{% if i > 1 then %}, {% end %}
			image[${i} + x0 * ${components}] * xt0 + image[${i} + x1 * ${components}] * xt1
		{% end %}
	{% end %}
end
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
		wrap_u = options.wrap_u or 'clamp',
		interpolate_u = options.interpolate_u or 'nearest',
	}
	local environment = {
		components = v3d.format_size(options.format),
		options = sampler.options,
		v3d = v3d,
	}
	sampler.compiled_sampler = _v3d_optimise_globals(_v3d_apply_template(_SAMPLER1D_TEMPLATE, environment), true)
	--- @diagnostic disable-next-line: inject-field
	sampler.sample = assert(load(sampler.compiled_sampler))()
	return _finalise_instance(sampler)
end

----------------------------------------------------------------

-- TODO:
-- --- @param options V3DSampler2DOptions
-- --- @return V3DSampler2D
-- --- @v3d-nomethod
-- function v3d.create_sampler2D(options)
-- 	local sampler = _create_instance('V3DSampler2D', options.label)
-- 	sampler.options = options
-- 	--- @diagnostic disable-next-line: invisible
-- 	sampler.components = v3d.format_size(options.format)
-- 	return sampler
-- end

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

-- --- @param sampler V3DSampler2D
-- --- @param image V3DImage
-- --- @param u number
-- --- @param v number
-- --- @return any ...
-- function v3d.sampler2d_sample(sampler, image, u, v) end

-- --- @param sampler V3DSampler3D
-- --- @param image V3DImage
-- --- @param u number
-- --- @param v number
-- --- @param w number
-- --- @return any ...
-- function v3d.sampler3d_sample(sampler, image, u, v, w) end

end ----------------------------------------------------------------------------

-- TODO: palette/rgb
-- TODO: util/support

-- #gen-type-methods
-- #gen-type-instances
-- #gen-generated-functions

return v3d
