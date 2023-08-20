
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
	print(context)
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

	for _, library in ipairs { 'math', 'table' } do
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
		if s then
			local close = source:find((operator == '%' and '%' or '') .. operator .. '}', f)
			           or error('Missing end to \'{' .. operator .. '\': expected a matching \'' .. operator .. '}\'', 2)

			local pre_text = source:sub(1, s - 1 + #indent + #text)
			local content = source:sub(f + 1, close - 1):gsub('^%s+', ''):gsub('%s+$', '')

			if (operator == '%' or operator == '#') and not text:find '%S' then -- I'm desperately trying to remove newlines and it's not working
				pre_text = source:sub(1, s - 1)
			end

			if #pre_text > 0 then
				table.insert(write_content, '_table_insert(_text_segments, ' .. env.quote(pre_text) .. ')')
			end

			source = source:sub(close + 2)

			if (operator == '%' or operator == '#') and not source:sub(1, 1) == '\n' then -- I'm desperately trying to remove newlines and it's not working
				source = source:sub(2)
			end

			if operator == '=' then
				table.insert(write_content, '_table_insert(_text_segments, tostring(' .. content .. '))')
			elseif operator == '%' then
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
				source = result:gsub('%${([^}]+)}', '{= %1 =}'):gsub('\n', '\n' .. indent) .. source
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
--- local buffer = v3d.format_buffer(my_format, my_value)
---
--- assert(buffer[1] == 1)
--- assert(buffer[2] == true)
--- @v3d-example
--- local my_format = v3d.tuple { v3d.integer(), v3d.boolean() }
--- local my_value = { 1, true }
--- local my_buffer = {}
---
--- v3d.format_buffer(my_format, my_value, my_buffer, 1)
---
--- assert(my_buffer[1] == nil) -- skipped due to the offset of 1
--- assert(my_buffer[2] == 1)
--- assert(my_buffer[3] == true)
--- @v3d-example
function v3d.format_buffer(format, value, buffer, offset)
	buffer = buffer or {}
	offset = offset or 0

	if format.kind == 'boolean' or format.kind == 'integer' or format.kind == 'uinteger' or format.kind == 'number' or format.kind == 'character' or format.kind == 'string' then
		buffer[offset + 1] = value
	elseif format.kind == 'tuple' then
		for i = 1, #format.fields do
			buffer = v3d.format_buffer(format.fields[i], value[i], buffer, offset)
			offset = offset + v3d.format_size(format.fields[i])
		end
	elseif format.kind == 'struct' then
		for i = 1, #format.fields do
			buffer = v3d.format_buffer(format.fields[i].format, value[format.fields[i].name], buffer, offset)
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
--- local value = v3d.format_unbuffer(my_format, my_buffer)
---
--- assert(value.x == 1)
--- assert(value.y == true)
--- @v3d-example
--- local my_format = v3d.struct { x = v3d.integer(), y = v3d.boolean() }
--- local my_buffer = { 1, true, 2, false, 3, true }
---
--- local value = v3d.format_unbuffer(my_format, my_buffer, 2 * v3d.format_size(my_format))
---
--- assert(value.x == 3)
--- assert(value.y == true)
--- @v3d-example
function v3d.format_unbuffer(format, buffer, offset)
	offset = offset or 0

	if format.kind == 'boolean' or format.kind == 'integer' or format.kind == 'uinteger' or format.kind == 'number' or format.kind == 'character' or format.kind == 'string' then
		return buffer[offset + 1]
	elseif format.kind == 'tuple' then
		local value = {}
		for i = 1, #format.fields do
			value[i] = v3d.format_unbuffer(format.fields[i], buffer, offset)
			offset = offset + v3d.format_size(format.fields[i])
		end
		return value
	elseif format.kind == 'struct' then
		local value = {}
		for i = 1, #format.fields do
			value[format.fields[i].name] = v3d.format_unbuffer(format.fields[i].format, buffer, offset)
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
	local pixel_data = v3d.format_buffer(format, pixel_value or v3d.format_default_value(format))
	local pixel_data_size = #pixel_data

	image.format = format
	image.width = width
	image.height = height
	image.depth = depth

	local index = 1
	for _ = 1, width * height * depth do
		for i = 1, pixel_data_size do
			image[index] = pixel_data[i]
			index = index + 1
		end
	end

	return _finalise_instance(image)
end

----------------------------------------------------------------

--- Return a region containing the entire image.
--- @param image V3DImage
--- @return V3DImageRegion
--- @v3d-nolog
--- local my_image = v3d.create_image(v3d.number(), 1, 2, 3)
--- local my_region = v3d.image_full_region(my_image)
--- assert(my_region.x == 0)
--- assert(my_region.y == 0)
--- assert(my_region.z == 0)
--- assert(my_region.width == 1)
--- assert(my_region.height == 2)
--- assert(my_region.depth == 3)
--- @v3d-example 2:8
function v3d.image_full_region(image)
	return {
		x = 0,
		y = 0,
		z = 0,
		width = image.width,
		height = image.height,
		depth = image.depth,
	}
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

--- Fill a region of an image with the specified value.
--- * If no region is specified, the entire image will be filled.
--- * If no value is provided, the image will be filled with the default value
---   for the image's format.
---
--- Note, the value must be compatible with the image's format and will be
--- flattened within the image's internal data buffer.
---
--- Returns the image.
--- @param image V3DImage
--- @param value any | nil
--- @param region V3DImageRegion | nil
--- @return V3DImage
--- @v3d-chainable
--- Pixel value must be an instance of the specified format or nil
--- @v3d-validate value == nil or v3d.format_is_instance(image.format, value)
--- Region must be contained within the image
--- @v3d-validate region == nil or v3d.image_contains_region(image, region)
--- local my_image = v3d.create_image(v3d.uinteger(), 51, 19, 1, colours.white)
---
--- v3d.image_fill(my_image, colours.black)
---
--- assert(my_image:get_pixel(0, 0, 0) == colours.black)
--- @v3d-example 3
--- local my_image = v3d.create_image(v3d.uinteger(), 51, 19, 1, colours.white)
--- local my_region = {
--- 	x = 1, y = 1, z = 0,
--- 	width = 50, height = 18, depth = 1,
--- }
---
--- v3d.image_fill(my_image, colours.orange, my_region)
---
--- assert(my_image:get_pixel(0, 0, 0) == colours.white)
--- assert(my_image:get_pixel(1, 1, 0) == colours.orange)
--- @v3d-example 7
function v3d.image_fill(image, value, region)
	value = value or v3d.format_default_value(image.format)

	local pixel_data = v3d.format_buffer(image.format, value)
	local pixel_data_size = #pixel_data

	local z_init = 1
	local z_end = image.depth
	local y_init = 1
	local y_end = image.height
	local x_init = 1
	local x_end = image.width
	local index = 1
	local z_step = 0
	local y_step = 0

	if region then
		x_init = region.x + 1
		x_end = region.x + region.width
		y_init = region.y + 1
		y_end = region.y + region.height
		z_init = region.z + 1
		z_end = region.z + region.depth

		index = ((z_init - 1) * image.width * image.height + (y_init - 1) * image.width + (x_init - 1)) * pixel_data_size + 1
		y_step = (image.width - region.width) * pixel_data_size
		z_step = (image.height - region.height) * image.width * pixel_data_size
	end

	for _ = z_init, z_end do
		for _ = y_init, y_end do
			for _ = x_init, x_end do
				for i = 1, pixel_data_size do
					image[index] = pixel_data[i]
					index = index + 1
				end
			end
			index = index + y_step
		end
		index = index + z_step
	end

	return image
end

----------------------------------------------------------------

--- Get the value of a pixel in the image. If the pixel is out of bounds, nil
--- will be returned. The coordinates are 0-indexed, meaning (0, 0, 0) is the
--- first pixel in the image (top-left, front-most).
---
--- Note, the value will be unflattened from the image's internal data buffer.
--- For example, if the image's format is a struct, a table with the field values
--- will be returned.
---
--- @see v3d.image_buffer
--- @param image V3DImage
--- @param x integer
--- @param y integer
--- @param z integer
--- @return any
--- @v3d-nolog
--- local my_image = v3d.create_image(v3d.number(), 16, 16, 16, 42)
---
--- local single_pixel_value = v3d.image_get_pixel(my_image, 0, 0, 0)
---
--- assert(single_pixel_value == 42)
--- @v3d-example 3
--- local rgba_format = v3d.tuple { v3d.number(), v3d.number(), v3d.number(), v3d.number() }
--- local my_image = v3d.create_image(rgba_format, 16, 16, 16, { 0.1, 0.2, 0.3, 1 })
---
--- local rgba = v3d.image_get_pixel(my_image, 0, 0, 0)
---
--- assert(rgba[1] == 0.1)
--- assert(rgba[2] == 0.2)
--- assert(rgba[3] == 0.3)
--- assert(rgba[4] == 1)
--- @v3d-example 4
function v3d.image_get_pixel(image, x, y, z)
	if x < 0 or x >= image.width or y < 0 or y >= image.height or z < 0 or z >= image.depth then
		return nil
	end

	local pixel_data_size = v3d.format_size(image.format)
	local offset = ((z * image.width * image.height) + (y * image.width) + x) * pixel_data_size

	return v3d.format_unbuffer(image.format, image, offset)
end

--- Set the value of a pixel in the image. If the pixel is out of bounds, the
--- image will be returned unchanged. The coordinates are 0-indexed, meaning
--- (0, 0, 0) is the first pixel in the image (top-left, front-most).
---
--- Note, the value must be compatible with the image's format and will be
--- flattened within the image's internal data buffer.
---
--- Returns the image.
---
--- @see v3d.image_unbuffer
--- @param image V3DImage
--- @param x integer
--- @param y integer
--- @param z integer
--- @param value any
--- @return V3DImage
--- @v3d-chainable
--- Pixel value must be an instance of the specified format
--- @v3d-validate v3d.format_is_instance(image.format, value)
--- local my_image = v3d.create_image(v3d.uinteger(), 51, 19, colours.white)
---
--- v3d.image_set_pixel(my_image, 0, 0, 0, colours.black)
---
--- assert(v3d.image_get_pixel(my_image, 0, 0, 0) == colours.black)
--- @v3d-example 3
function v3d.image_set_pixel(image, x, y, z, value)
	if x < 0 or x >= image.width or y < 0 or y >= image.height or z < 0 or z >= image.depth then
		return image
	end

	local pixel_data_size = v3d.format_size(image.format)
	local offset = ((z * image.width * image.height) + (y * image.width) + x) * pixel_data_size

	v3d.format_buffer(image.format, value, image, offset)

	return image
end

----------------------------------------------------------------

--- Copy the contents of a region within the image into a buffer.
--- * If no region is specified, the entire image will be copied.
--- * If no buffer is provided, a new buffer will be created. Regardless, the
---   buffer will be returned.
--- * If an offset is provided, the buffer will be written to from that offset.
---   For example, an offset of 1 will start writing at the second element of
---   the buffer.
---
--- Note, the buffer will contain the unflattened values of the image's internal
--- data buffer. For example, if the image's format is a struct, the buffer will
--- contain tables with the field values for each pixel, e.g.
--- ```
--- {
--- 	{ r = 1, g = 2, b = 3 },
--- 	{ r = 4, g = 5, b = 6 },
--- }
--- ```
---
--- Buffer values will be depth-major, row-major, meaning the first value will
--- be the front-most, top-left pixel, the second value will be the pixel to the
--- right of that, and so on.
--- @param image V3DImage
--- @param buffer table | nil
--- @param offset integer | nil
--- @param region V3DImageRegion | nil
--- @return table
--- @v3d-nolog
--- @v3d-advanced
--- Offset must not be negative
--- @v3d-validate offset == nil or offset >= 0
--- Region must be contained within the image
--- @v3d-validate region == nil or v3d.image_contains_region(image, region)
--- local my_image = v3d.create_image(v3d.number(), 16, 16, 16, 42)
---
--- local buffer = v3d.image_buffer(my_image)
---
--- assert(buffer[1] == 42)
--- @v3d-example 3
--- local my_image = v3d.create_image(v3d.number(), 16, 16, 16, 42)
--- local my_region = {
--- 	x = 1, y = 1, z = 0,
--- 	width = 14, height = 14, depth = 14,
--- }
---
--- local buffer = v3d.image_buffer(my_image, nil, nil, my_region)
--- -- buffer only contains contents from that region
--- @v3d-example 7
--- local my_image = v3d.create_image(v3d.number(), 16, 16, 16, 42)
--- local my_buffer = {}
---
--- v3d.image_buffer(my_image, my_buffer)
---
--- assert(my_buffer[1] == 42)
--- @v3d-example 4
function v3d.image_buffer(image, buffer, offset, region)
	buffer = buffer or {}
	offset = offset or 0

	local image_format = image.format
	local image_width = image.width
	local image_height = image.height
	local v3d_format_unbuffer = v3d.format_unbuffer
	local pixel_value_size = v3d.format_size(image.format)

	local z_init = 1
	local z_end = image.depth
	local y_init = 1
	local y_end = image_height
	local x_init = 1
	local x_end = image_width

	local z_step = 0
	local y_step = 0

	if region then
		x_init = region.x + 1
		x_end = region.x + region.width
		y_init = region.y + 1
		y_end = region.y + region.height
		z_init = region.z + 1
		z_end = region.z + region.depth

		z_step = (image_height - region.height) * image_width * pixel_value_size
		y_step = (image_width - region.width) * pixel_value_size
	end

	local buffer_index = offset + 1
	local image_offset = ((z_init - 1) * image_width * image_height + (y_init - 1) * image_width + (x_init - 1)) * pixel_value_size

	for _ = z_init, z_end do
		for _ = y_init, y_end do
			for _ = x_init, x_end do
				buffer[buffer_index] = v3d_format_unbuffer(image_format, image, image_offset)
				buffer_index = buffer_index + 1
				image_offset = image_offset + pixel_value_size
			end
			image_offset = image_offset + y_step
		end
		image_offset = image_offset + z_step
	end

	return buffer
end

-- TODO: validate buffer contents as well
--- Copy the contents of a buffer into a region within the image.
--- * If no offset is provided, the buffer will be read from the first element.
--- * If no region is specified, the buffer will be copied into the entire
---   image.
---
--- The buffer must contain enough values to fill the region.
---
--- Note, the buffer must contain values compatible with the image's format and
--- will be flattened within the image's internal data buffer. For example, if
--- the image's format is a struct, the buffer must contain tables with the field
--- values for each pixel, e.g.
--- ```
--- {
--- 	{ r = 1, g = 2, b = 3 },
--- 	{ r = 4, g = 5, b = 6 },
--- }
--- ```
---
--- This function can be used to load values into an image efficiently.
--- @param image V3DImage
--- @param buffer table
--- @param offset integer | nil
--- @param region V3DImageRegion | nil
--- @return V3DImage
--- @v3d-chainable
--- @v3d-nolog
--- @v3d-advanced
--- Offset must not be negative
--- @v3d-validate offset == nil or offset >= 0
--- Region must be contained within the image
--- @v3d-validate region == nil or v3d.image_contains_region(image, region)
--- Buffer must contain enough values to fill the region
--- @v3d-validate #buffer - (offset or 0) >= v3d.format_size(image.format) * (region or image).width * (region or image).height * (region or image).depth
--- local my_image = v3d.create_image(v3d.number(), 2, 1, 1)
--- local my_buffer = { 1, 2 }
---
--- v3d.image_unbuffer(my_image, my_buffer)
---
--- assert(v3d.image_get_pixel(my_image, 0, 0, 0) == 1)
--- assert(v3d.image_get_pixel(my_image, 1, 0, 0) == 2)
--- @v3d-example 4
--- local my_image = v3d.create_image(v3d.number(), 2, 1, 1, 42)
--- local my_buffer = { 5, 6 }
--- local my_region = {
--- 	x = 1, y = 0, z = 0,
--- 	width = 1, height = 1, depth = 1,
--- }
---
--- v3d.image_unbuffer(my_image, my_buffer, 1, my_region)
---
--- assert(v3d.image_get_pixel(my_image, 0, 0, 0) == 42)
--- assert(v3d.image_get_pixel(my_image, 1, 0, 0) == 6)
--- @v3d-example 8
function v3d.image_unbuffer(image, buffer, offset, region)
	offset = offset or 0

	local image_format = image.format
	local image_width = image.width
	local image_height = image.height
	local v3d_format_buffer = v3d.format_buffer
	local pixel_value_size = v3d.format_size(image.format)

	local z_init = 1
	local z_end = image.depth
	local y_init = 1
	local y_end = image_height
	local x_init = 1
	local x_end = image_width

	local z_step = 0
	local y_step = 0

	if region then
		x_init = region.x + 1
		x_end = region.x + region.width
		y_init = region.y + 1
		y_end = region.y + region.height
		z_init = region.z + 1
		z_end = region.z + region.depth

		z_step = (image_height - region.height) * image_width * pixel_value_size
		y_step = (image_width - region.width) * pixel_value_size
	end

	local buffer_index = offset + 1
	local image_offset = ((z_init - 1) * image_width * image_height + (y_init - 1) * image_width + (x_init - 1)) * pixel_value_size

	for _ = z_init, z_end do
		for _ = y_init, y_end do
			for _ = x_init, x_end do
				v3d_format_buffer(image_format, buffer[buffer_index], image, image_offset)
				buffer_index = buffer_index + 1
				image_offset = image_offset + pixel_value_size
			end
			image_offset = image_offset + y_step
		end
		image_offset = image_offset + z_step
	end

	return image
end

----------------------------------------------------------------

--- Return an identical copy of the image with the same format and dimensions.
--- @param image V3DImage
--- @param label string | nil
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

--- Copy the contents of one image into another image.
--- * If no source region is specified, the entire source image will be copied.
--- * If no destination region is specified, the source image will be copied
---   into the entire destination image.
---
--- Note, this may not be as efficient as using `image_buffer` and
--- `image_unbuffer` directly, and also affords less control when it comes to
--- casting data. This function is meant as an easy way to copy images of
--- compatible formats.
---
--- TODO: implement copy shaders
---
--- Returns the source image.
---
--- @see v3d.image_buffer
--- @see v3d.image_unbuffer
--- @param source V3DImage
--- @param destination V3DImage
--- @param source_region V3DImageRegion | nil
--- @param destination_region V3DImageRegion | nil
--- @return V3DImage
--- @v3d-chainable
--- Source region must be contained within the source image
--- @v3d-validate source_region == nil or v3d.image_contains_region(source, source_region)
--- Destination region must be contained within the destination image
--- @v3d-validate destination_region == nil or v3d.image_contains_region(destination, destination_region)
--- If source and destination regions are specified, they must have the same size
--- @v3d-validate source_region == nil or destination_region == nil or (source_region.width == destination_region.width and source_region.height == destination_region.height and source_region.depth == destination_region.depth)
--- If no regions are specified, source and destination images must have the same size
--- @v3d-validate source_region ~= nil or destination_region ~= nil or (source.width == destination.width and source.height == destination.height and source.depth == destination.depth)
--- If only a source region is specified, the source region and desination image must have the same size
--- @v3d-validate source_region == nil or destination_region ~= nil or (source_region.width == destination.width and source_region.height == destination.height and source_region.depth == destination.depth)
--- If only a destination region is specified, the destination region and source image must have the same size
--- @v3d-validate source_region ~= nil or destination_region == nil or (source.width == destination_region.width and source.height == destination_region.height and source.depth == destination_region.depth)
--- Source format must be compatible with the destination format
--- @v3d-validate v3d.format_is_compatible_with(source.format, destination.format)
--- local my_image = v3d.create_image(v3d.number(), 16, 16, 16, 42)
--- local my_other_image = v3d.create_image(v3d.number(), 16, 16, 16, 24)
---
--- v3d.image_copy_into(my_image, my_other_image)
---
--- assert(v3d.image_get_pixel(my_other_image, 0, 0, 0) == 42)
--- assert(v3d.image_get_pixel(my_other_image, 15, 15, 15) == 42)
--- @v3d-example 4
--- local my_image = v3d.create_image(v3d.number(), 16, 16, 16, 42)
--- local my_other_image = v3d.create_image(v3d.number(), 16, 16, 16, 24)
--- local my_region = {
--- 	x = 1, y = 1, z = 1,
--- 	width = 14, height = 14, depth = 14,
--- }
---
--- v3d.image_copy_into(my_image, my_other_image, my_region, my_region)
---
--- assert(v3d.image_get_pixel(my_other_image, 0, 0, 0) == 24)
--- assert(v3d.image_get_pixel(my_other_image, 1, 1, 1) == 42)
--- assert(v3d.image_get_pixel(my_other_image, 14, 14, 14) == 42)
--- assert(v3d.image_get_pixel(my_other_image, 15, 15, 15) == 24)
--- @v3d-example 8
function v3d.image_copy_into(source, destination, source_region, destination_region)
	local buffer = v3d.image_buffer(source, nil, nil, source_region)
	v3d.image_unbuffer(destination, buffer, nil, destination_region)
	return source
end

end ----------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Framebuffers ----------------------------------------------------------------
do -----------------------------------------------------------------------------

--- A framebuffer is a collection of images known as layers. Layers are named
--- and may be any format, but must all have the same dimensions.
--- @class V3DFramebuffer
--- Format of the framebuffer. Will always be a struct mapping layer names to
--- layer formats.
--- @field format V3DFormat
--- Width of the framebuffer. All layers must have the same width.
--- @field width integer
--- Height of the framebuffer. All layers must have the same height.
--- @field height integer
--- Depth of the framebuffer. All layers must have the same depth.
--- @field depth integer
--- @field private n_layers integer
--- @field private layer_formats V3DFormat[]

--- String name of a layer within a framebuffer.
--- @alias V3DLayerName string
--- Layer names must be valid Lua identifiers
--- @v3d-validate self:match '^[%a_][%w_]*$'

--- Create a new framebuffer with the specified format and dimensions.
--- @param width integer
--- @param height integer
--- @param depth integer
--- @param layers { [V3DLayerName]: V3DFormat }
--- @param label string | nil
--- @return V3DFramebuffer
--- @v3d-constructor
--- @v3d-nomethod
--- Width must not be negative
--- @v3d-validate width >= 0
--- Height must not be negative
--- @v3d-validate height >= 0
--- Depth must not be negative
--- @v3d-validate depth >= 0
--- At least one layer must be specified
--- @v3d-validate next(layers) ~= nil
--- -- Create a blank 16x16x16 3D framebuffer.
--- local my_framebuffer = v3d.create_framebuffer(16, 16, 16, { colour = v3d.number() })
--- @v3d-example 2
function v3d.create_framebuffer(width, height, depth, layers, label)
	local framebuffer = _create_instance('V3DFramebuffer', label)

	framebuffer.format = v3d.struct(layers)
	framebuffer.width = width
	framebuffer.height = height
	framebuffer.depth = depth
	
	--- @diagnostic disable: invisible
	framebuffer.n_layers = #framebuffer.format.fields
	framebuffer.layer_formats = {}

	for i, struct_field in ipairs(framebuffer.format.fields) do
		framebuffer.layer_formats[i] = struct_field.format
	end
	--- @diagnostic enable: invisible

	for i, struct_field in ipairs(framebuffer.format.fields) do
		framebuffer[i] = v3d.create_image(struct_field.format, width, height, depth)
	end

	return framebuffer
end

--- Return whether a framebuffer has a layer with the specified name.
--- @param framebuffer V3DFramebuffer
--- @param layer_name V3DLayerName
--- @return boolean
--- @v3d-nolog
--- local my_framebuffer = v3d.create_framebuffer(16, 16, 16, { colour = v3d.number() })
--- assert(v3d.framebuffer_has_layer(my_framebuffer, 'colour'))
--- @v3d-example 2
function v3d.framebuffer_has_layer(framebuffer, layer_name)
	for _, struct_field in ipairs(framebuffer.format.fields) do
		if struct_field.name == layer_name then
			return true
		end
	end
	return false
end

--- Get the underlying V3DImage for a layer within a framebuffer. If the layer
--- does not exist, nil will be returned.
--- @param framebuffer V3DFramebuffer
--- @param layer_name V3DLayerName
--- @return V3DImage | nil
--- @v3d-nolog
--- local my_framebuffer = v3d.create_framebuffer(16, 16, 16, { colour = v3d.number() })
--- local my_layer = v3d.framebuffer_layer(my_framebuffer, 'colour')
--- @v3d-example 2
function v3d.framebuffer_layer(framebuffer, layer_name)
	for i, struct_field in ipairs(framebuffer.format.fields) do
		if struct_field.name == layer_name then
			return framebuffer[i]
		end
	end
	return nil
end

--- Fill the layers of a framebuffer using the specified values. `values` should
--- be a table mapping layer names to the value to fill that layer with.
--- If a region is specified, only the specified region of each layer will be
--- filled.
--- @param framebuffer V3DFramebuffer
--- @param values { [V3DLayerName]: any }
--- @param region V3DImageRegion | nil
--- @return V3DFramebuffer
--- @v3d-chainable
--- Values provided should match the format of the framebuffer.
--- @v3d-validate v3d.format_is_instance(framebuffer.format, values)
--- Region should be contained within the framebuffer.
--- @v3d-validate region == nil or v3d.image_contains_region(framebuffer[1], region)
--- local my_framebuffer = v3d.create_framebuffer(16, 16, 16, { colour = v3d.number() })
--- v3d.framebuffer_fill(my_framebuffer, { colour = 42 })
--- local colour_layer = v3d.framebuffer_layer(my_framebuffer, 'colour')
--- assert(v3d.image_get_pixel(colour_layer, 0, 0, 0) == 42)
--- @v3d-example 1:2
function v3d.framebuffer_fill(framebuffer, values, region)
	for i, struct_field in ipairs(framebuffer.format.fields) do
		v3d.image_fill(framebuffer[i], values[struct_field.name], region)
	end
	return framebuffer
end

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

--- Present this image to the terminal drawing subpixels to increase the
--- effective resolution of the terminal.
---
--- If specified, dx and dy will be used as the offset of the top-left pixel
--- when drawing, i.e. with an offset of (2, 1), the image will appear 2 to the
--- right and 1 down from the top-left of the terminal. These are 0-based and
--- both default to 0. A value of 0 means no offset.
---
--- If an image region is specified, only that region of the image will be
--- drawn.
--- @param image V3DImage
--- @param term CCTermObject
--- @param dx integer | nil
--- @param dy integer | nil
--- @param image_region V3DImageRegion | nil
--- @return V3DImage
--- @v3d-chainable
--- Image format must be compatible with `v3d.uinteger()`.
--- @v3d-validate v3d.format_is_compatible_with(image.format, v3d.uinteger())
--- If a region is specified, it must be contained within the image.
--- @v3d-validate image_region == nil or v3d.image_contains_region(image, image_region)
--- If a region is specified, it must have a width and height that are multiples of 2 and 3 respectively.
--- @v3d-validate image_region == nil or (image_region.width % 2 == 0 and image_region.height % 3 == 0)
--- If a region is not specified, the image must have a width and height that are multiples of 2 and 3 respectively.
--- @v3d-validate image_region ~= nil or (image.width % 2 == 0 and image.height % 3 == 0)
--- local term_width, term_height = term.getSize()
--- local my_image = v3d.create_image(v3d.uinteger(), term_width * 2, term_height * 3, 1)
--- local fill_region = {
--- 	x = 1, y = 1, z = 0,
--- 	width = 6, height = 6, depth = 1,
--- }
---
--- v3d.image_fill(my_image, colours.white)
--- v3d.image_fill(my_image, colours.red)
---
--- -- Draw the image to `term.current()`
--- v3d.image_present_term_subpixel(my_image, term.current())
--- @v3d-example 11:12
--- local term_width, term_height = term.getSize()
--- local my_image = v3d.create_image(v3d.uinteger(), term_width * 2, term_height * 3, 1)
--- local fill_region = {
--- 	x = 1, y = 1, z = 0,
--- 	width = 6, height = 6, depth = 1,
--- }
---
--- v3d.image_fill(my_image, colours.white)
--- v3d.image_fill(my_image, colours.red)
---
--- -- Draw the red part of the image to `term.current()`, 5 pixels to the
--- -- right, and 10 down
--- v3d.image_present_term_subpixel(my_image, term.current(), 5, 10, fill_region)
--- @v3d-example 11:13
function v3d.image_present_term_subpixel(image, term, dx, dy, image_region)
	dy = dy or 0

	local SUBPIXEL_WIDTH = 2
	local SUBPIXEL_HEIGHT = 3

	local fb_colour = image
	local fb_width = image.width

	local x_blit = 1 + (dx or 0)

	--- @diagnostic disable-next-line: deprecated
	local table_unpack = table.unpack
	local string_char = string.char
	local term_blit = term.blit
	local term_setCursorPos = term.setCursorPos

	local i0 = 1
	local i_delta = fb_width * (SUBPIXEL_HEIGHT - 1)
	local num_columns = fb_width / SUBPIXEL_WIDTH
	local ch_t = {}
	local fg_t = {}
	local bg_t = {}

	if image_region ~= nil then
		i0 = i0 + image_region.x + image_region.y * fb_width
		num_columns = image_region.width / SUBPIXEL_WIDTH
		i_delta = i_delta + image.width - image_region.width
	end

	for y_blit = 1 + dy, (image_region or image).height / SUBPIXEL_HEIGHT + dy do
		for ix = 1, num_columns do
			local i1 = i0 + fb_width
			local i2 = i1 + fb_width
			local c00, c10 = fb_colour[i0], fb_colour[i0 + 1]
			local c01, c11 = fb_colour[i1], fb_colour[i1 + 1]
			local c02, c12 = fb_colour[i2], fb_colour[i2 + 1]

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

			i0 = i0 + SUBPIXEL_WIDTH
		end

		term_setCursorPos(x_blit, y_blit)
		term_blit(string_char(table_unpack(ch_t)), string_char(table_unpack(fg_t)), string_char(table_unpack(bg_t)))
		i0 = i0 + i_delta
	end

	return image
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
--- If an image region is specified, only that region of the image will be
--- drawn.
--- @param image V3DImage
--- @param term CraftOSPCTermObject
--- @param normalise boolean
--- @param dx integer | nil
--- @param dy integer | nil
--- @param image_region V3DImageRegion | nil
--- @return V3DImage
--- @v3d-chainable
--- Image format must be compatible with `v3d.uinteger()`.
--- @v3d-validate v3d.format_is_compatible_with(image.format, v3d.uinteger())
--- If a region is specified, it must be contained within the image.
--- @v3d-validate image_region == nil or v3d.image_contains_region(image, image_region)
--- Any graphics mode is being used.
--- @v3d-validate term.getGraphicsMode()
--- local term_width, term_height = 720, 540
--- local image = v3d.create_image(v3d.uinteger(), term_width, term_height, 1)
---
--- v3d.image_fill(image, colours.white)
--- v3d.image_fill(image, colours.red, {
--- 	x = 20, y = 20, z = 0,
--- 	width = 100, height = 100, depth = 1,
--- })
---
--- term.setGraphicsMode(1)
--- v3d.image_present_graphics(image, term, true)
--- @v3d-example 10:11
--- local term_width, term_height = 720, 540
--- local image = v3d.create_image(v3d.uinteger(), term_width, term_height, 1)
---
--- v3d.image_fill(image, 0)
--- v3d.image_fill(image, 7, {
--- 	x = 20, y = 20, z = 0,
--- 	width = 100, height = 100, depth = 1,
--- })
---
--- term.setGraphicsMode(1)
--- v3d.image_present_graphics(image, term, false)
--- @v3d-example 10:11
function v3d.image_present_graphics(image, term, normalise, dx, dy, image_region)
	local lines = {}
	local index = 1
	local index_delta = 0
	local fb_width = image.width
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

	if image_region then
		index = index + image_region.x + image_region.y * fb_width
		index_delta = index_delta + image.width - image_region.width
		fb_width = image_region.width
	end

	for y = 1, (image_region or image).height do
		local line = {}

		for x = 1, fb_width do
			line[x] = string_char(convert_pixel(image[index]))
			index = index + 1
		end

		lines[y] = table_concat(line)
		index = index + index_delta
	end

	term.drawPixels(dx, dy, lines)

	return image
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

	local index = 1
	for i = 1, builder.n_faces do
		--- @diagnostic disable-next-line: invisible
		v3d.format_buffer(builder.face_format, builder.faces[i], g, index)
		index = index + g.face_stride
	end
	for i = 1, builder.n_vertices do
		--- @diagnostic disable-next-line: invisible
		v3d.format_buffer(builder.vertex_format, builder.vertices[i], g, index)
		index = index + g.vertex_stride
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
		b.faces[i] = v3d.format_unbuffer(geometry.face_format, geometry, index)
		index = index + geometry.face_stride
	end
	for i = 1, geometry.n_vertices do
		--- @diagnostic disable-next-line: invisible
		b.vertices[i] = v3d.format_unbuffer(geometry.vertex_format, geometry, index)
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

local MACRO_EXPAND_LATER = {}
local _process_pipeline_source_macro_calls
--------------------------------------------------------------------------------
-- Pipelines -------------------------------------------------------------------
do -----------------------------------------------------------------------------

--- Name of a uniform variable for a pipeline.
--- @alias V3DUniformName string
--- Uniform names must be valid Lua identifiers
--- @v3d-validate self:match '^[%a_][%w_]*$'

----------------------------------------------------------------

--- A pipeline is a compiled, optimised function inspired by OpenGL shaders.
--- There are many types of pipeline, each specialised for a specific purpose.
---
--- @see V3DImageMapPipeline
---
--- Pipelines are compiled from 'sources', which are just strings containing Lua
--- code. The exception to this is that pipeline source code is run through a
--- templating and macro engine before being compiled.
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
--- Table storing uniform values for the pipeline.
--- @field private uniforms table
--- @v3d-abstract

----------------------------------------------------------------

--- Options common to all pipelines used when creating the pipeline.
--- @class V3DPipelineOptions
--- Sources to compile the pipeline from. This field contains a map of source
--- name to source code, e.g.
--- ```
--- {
--- 	vertex = '...',
--- 	fragment = '...',
--- }
--- ```
--- @field sources { [string]: string }
--- Label to assign to the pipeline.
--- @field label string | nil
--- @v3d-untracked

----------------------------------------------------------------

--- Write a value to a uniform variable.
---
--- Returns the shader.
--- @param pipeline V3DPipeline
--- @param name V3DUniformName
--- @param value any
--- @return V3DPipeline
--- @v3d-chainable
--- local my_pipeline = TODO()
--- v3d.pipeline_write_uniform(my_pipeline, 'my_uniform', 42)
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
--- local my_pipeline = TODO()
--- v3d.pipeline_write_uniform(my_pipeline, 'my_uniform', 42)
--- local my_uniform_value = v3d.pipeline_read_uniform(my_pipeline, 'my_uniform')
--- assert(my_uniform_value == 42)
--- @v3d-example 2:4
function v3d.pipeline_read_uniform(pipeline, name)
	--- @diagnostic disable-next-line: invisible
	return pipeline.uniforms[name]
end

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
function _process_pipeline_source_macro_calls(source, aliases)
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

				if aliased_content ~= MACRO_EXPAND_LATER then
					source = source:sub(1, i + #prefix - 1)
					      .. aliased_content
					      .. source:sub(i + #prefix + #macro_name + #params_str)
					expand_macro_later = false
				end
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

end ----------------------------------------------------------------------------

local _macro_environments = {}
local _combine_macro_environments
--------------------------------------------------------------------------------
-- Macro environments ----------------------------------------------------------
do -----------------------------------------------------------------------------


function _combine_macro_environments(...)
	local e = {}

	for _, env in ipairs { ... } do
		for k, v in pairs(env) do
			e[k] = v
		end
	end

	return e
end

--- @diagnostic disable: return-type-mismatch
--- @diagnostic disable: unused-local

----------------------------------------------------------------

_macro_environments.core = {}

--- @param name string
--- @return any
function _macro_environments.core.v3d_uniform(name)
	return MACRO_EXPAND_LATER
end

--- @param name string
--- @return nil
function _macro_environments.core.v3d_event(name)
	return MACRO_EXPAND_LATER
end

--- @param name string
--- @return nil
function _macro_environments.core.v3d_start_timer(name)
	return MACRO_EXPAND_LATER
end

--- @param name string
--- @return nil
function _macro_environments.core.v3d_stop_timer(name)
	return MACRO_EXPAND_LATER
end

--- @param a number
--- @param b number
--- @return boolean
function _macro_environments.core.v3d_compare_depth(a, b)
	return '(' .. a .. ' > ' .. b .. ')'
end

----------------------------------------------------------------

_macro_environments.images = {}

--- @param lens string
--- @param attribute 'width' | 'height' | 'depth' | nil
--- @return integer | V3DImage
function _macro_environments.images.v3d_image(lens, attribute)
	assert(not attribute or attribute == 'width' or attribute == 'height' or attribute == 'depth')
	return MACRO_EXPAND_LATER
end

----------------------------------------------------------------

_macro_environments.pixel = {}

--- @param lens string
--- @param xyzuvw string
--- @param absolute 'absolute' | 'relative' | nil
--- @return integer ...
function _macro_environments.pixel.v3d_pixel_position(lens, xyzuvw, absolute)
	if not absolute then
		return 'v3d_pixel_position(' .. lens .. ', ' .. xyzuvw .. ', relative)'
	end

	if #xyzuvw > 1 then
		local t = {}
		for i = 1, #xyzuvw do
			table.insert(t, 'v3d_pixel_position(' .. lens .. ', ' .. xyzuvw:sub(i, i) .. ', ' .. absolute .. ')')
		end
		return table.concat(t, ', ')
	end

	assert(xyzuvw == 'x' or xyzuvw == 'y' or xyzuvw == 'z' or xyzuvw == 'u' or xyzuvw == 'v' or xyzuvw == 'w')
	assert(not absolute or absolute == 'absolute' or absolute == 'relative')
	return MACRO_EXPAND_LATER
end

--- @param lens string
--- @param xyzwhd string
--- @return integer ...
function _macro_environments.pixel.v3d_pixel_region(lens, xyzwhd, absolute)
	if not absolute then
		return 'v3d_pixel_region(' .. lens .. ', ' .. xyzwhd .. ', relative)'
	end

	if #xyzwhd > 1 then
		local t = {}
		for i = 1, #xyzwhd do
			table.insert(t, 'v3d_pixel_region(' .. lens .. ', ' .. xyzwhd:sub(i, i) .. ', ' .. absolute .. ')')
		end
		return table.concat(t, ', ')
	end

	assert(xyzwhd == 'x' or xyzwhd == 'y' or xyzwhd == 'z' or xyzwhd == 'w' or xyzwhd == 'h' or xyzwhd == 'd')
	assert(not absolute or absolute == 'absolute' or absolute == 'relative')
	return MACRO_EXPAND_LATER
end

--- @param lens string
--- @return integer
function _macro_environments.pixel.v3d_pixel_index(lens)
	return MACRO_EXPAND_LATER
end

--- @param lens string
--- @return any
function _macro_environments.pixel.v3d_pixel(lens)
	return MACRO_EXPAND_LATER
end

--- @param lens string
--- @return any ...
function _macro_environments.pixel.v3d_pixel_unpacked(lens)
	return MACRO_EXPAND_LATER
end

--- @param lens string
--- @param value any
--- @return nil
function _macro_environments.pixel.v3d_set_pixel(lens, value)
	return MACRO_EXPAND_LATER
end

--- @param lens string
--- @param ... any
--- @return nil
function _macro_environments.pixel.v3d_set_pixel_unpacked(lens, ...)
	return MACRO_EXPAND_LATER
end

----------------------------------------------------------------

_macro_environments.image_map = {}

--- @return boolean
function _macro_environments.image_map.is_self_allowed()
	return MACRO_EXPAND_LATER
end

--- @diagnostic enable: return-type-mismatch
--- @diagnostic enable: unused-local

end ----------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Image map pipelines ---------------------------------------------------------
do -----------------------------------------------------------------------------

--- TODO
--- @class V3DImageMapPipeline: V3DPipeline

--- TODO
--- @class V3DImageMapPipelineOptions: V3DPipelineOptions
--- TODO
--- @field source_image_format V3DFormat
--- TODO
--- @field destination_image_format V3DFormat
--- Whether to allow the pipeline to read from and write to the same image. If
--- true, the order of operations will ensure that the pipeline does not read
--- from a pixel that it has written to previously, at a minor performance
--- penalty. Defaults to false.
--- @field allow_self boolean | nil
--- @v3d-untracked
--- @v3d-structural

--- TODO
--- @param options V3DImageMapPipelineOptions
--- @return V3DImageMapPipeline
--- @v3d-nomethod
function v3d.compile_image_map_pipeline(options)
	local pipeline = _create_instance('V3DImageMapPipeline', options.label)

	local sources = options.sources
	local allow_self = options.allow_self ~= false

	local init_finish_aliases = _combine_macro_environments(_macro_environments.core, _macro_environments.images)
	local init_source, init_macro_calls = _process_pipeline_source_macro_calls(sources.init or '', init_finish_aliases)
	local finish_source, finish_macro_calls = _process_pipeline_source_macro_calls(sources.finish or '', init_finish_aliases)

	local main_aliases = _combine_macro_environments(_macro_environments.core, _macro_environments.images, _macro_environments.pixel, _macro_environments.image_map)
	local main_source, main_macro_calls = _process_pipeline_source_macro_calls(sources.main or '', main_aliases)

	_v3d_contextual_error(main_source, 0)

	return pipeline
end

--- @param pipeline V3DImageMapPipeline
--- @param source_image V3DImage
--- @param source_region V3DImageRegion
--- @param destination_image V3DImage
--- @param destination_region V3DImageRegion
--- @return V3DImageMapPipeline
--- @v3d-chainable
--- @v3d-generated
function v3d.imagemappipeline_execute(pipeline, source_image, source_region, destination_image, destination_region)
	---@diagnostic disable-next-line: missing-return
end

end ----------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Image render pipelines ------------------------------------------------------
do -----------------------------------------------------------------------------

-- TODO

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
--- Note, to wrap them into a struct, use `v3d.format_unbuffer`.
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
--- v3d.image_set_pixel(my_image, 1, 0, 0, 10)
---
--- local single_value = v3d.sampler1d_sample(my_sampler, my_image, 0.5)
--- assert(math.abs(single_value - 5) < 0.0001)
--- @v3d-example 5
--- local rgb_format = v3d.struct { r = v3d.number(), g = v3d.number(), b = v3d.number() }
--- local my_sampler = v3d.create_sampler1D { format = rgb_format, interpolate_u = 'linear' }
--- local my_rgb_image = v3d.create_image(rgb_format, 2, 1, 1)
--- v3d.image_set_pixel(my_rgb_image, 1, 0, 0, { r = 10, g = 20, b = 30 })
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
--- v3d.image_set_pixel(my_rgba_image, 1, 0, 0, { r = 10, g = 20, b = 30, a = 1 })
---
--- local rgba = v3d.format_unbuffer(rgba_format, { v3d.sampler1d_sample(my_sampler, my_rgba_image, 0.1) })
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
