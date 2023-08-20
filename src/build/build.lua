
-- TODO: how do I do custom visualisation in v3debug?

local quick_build = ...

-- TODO: move codegen into this file
local codegen = require 'codegen'
local docgen = require 'docgen'
local embedgen = require 'embedgen'
local docstring = require 'docstring'

local v3d_base_dir = shell
	and shell.getRunningProgram():gsub('src/build/build.lua$', '')
	or '../../../'

--- @param filename string
local function read_file(filename)
	local h = assert(io.open(v3d_base_dir .. filename, 'r'))
	local content = h:read '*a'
	h:close()
	return content
end

--- @param filename string
--- @param content string
local function write_file(filename, content)
	local h = assert(io.open(v3d_base_dir .. filename, 'w'))
	h:write(content)
	h:close()
end

local v3d_content = read_file('src/v3d/v3d.lua')
local v3debug_content = read_file('src/v3debug/v3debug.lua')
local v3d_docstring, v3d_warnings = docstring.parse(v3d_content)

do -- replace `-- #gen-type-methods`
	--- @param class DocstringClass
	local function gen_type_methods_for(class)
		local typename = class.name

		local metamethod_annotation_snippets = {}
		local metamethod_snippets = {}
		local method_annotation_snippets = {}
		local method_snippets = {}

		if #class.methods == 0 then
			return ''
		end

		for _, fn in ipairs(class.methods) do
			local param_names = {}
			local param_types = {}
			local s = {}

			table.insert(method_snippets, '__type_methods.' .. typename .. '[\'' .. fn.method_name .. '\'] = ' .. fn.name)

			table.insert(s, '--- ' .. fn.docstring:gsub('\n', '\n--- '))

			for i = 2, #fn.parameters do
				table.insert(param_names, fn.parameters[i].name)
				table.insert(param_types, fn.parameters[i].type)
				table.insert(s, '--- @param ' .. fn.parameters[i].name .. ' ' .. fn.parameters[i].type)
			end

			if fn.parameters[1].type == typename then
				table.insert(s, '--- @return ' .. fn.return_type)
				table.insert(s, 'function __' .. typename .. '_extension:' .. fn.method_name .. '(' .. table.concat(param_names, ',') .. ')end')
				table.insert(method_annotation_snippets, table.concat(s, '\n'))
			end

			for _, metamethod in ipairs(fn.metamethods) do
				table.insert(metamethod_annotation_snippets, '--- @operator ' .. metamethod .. '(' .. table.concat(param_types, ',') .. '): ' .. fn.return_type)
				table.insert(metamethod_snippets, '__type_metatables.' .. typename .. '[\'__' .. metamethod .. '\'] = ' .. fn.name)
			end
		end

		local str = {}
		
		if #metamethod_annotation_snippets > 0 or #method_annotation_snippets > 0 then
			table.insert(str, '--- @class ' .. typename)

			for _, snippet in ipairs(metamethod_annotation_snippets) do
				table.insert(str, snippet)
			end

			if #method_annotation_snippets > 0 then
				table.insert(str, 'local __' .. typename .. '_extension = {}')
			end

			for _, snippet in ipairs(method_annotation_snippets) do
				table.insert(str, snippet)
			end
		end

		if not class.is_abstract and #method_snippets > 0 then
			table.insert(str, '__type_methods.' .. typename .. ' = {}')

			for _, snippet in ipairs(method_snippets) do
				table.insert(str, snippet)
			end
		end

		if #metamethod_snippets > 0 then
			table.insert(str, '__type_metatables.' .. typename .. ' = {}')

			for _, snippet in ipairs(metamethod_snippets) do
				table.insert(str, snippet)
			end
		end

		return table.concat(str, '\n')
	end

	--- @return string
	local function gen_type_methods()
		local blocks = {}

		table.insert(blocks, '--- @diagnostic disable: missing-return, unused-local')

		for i = 1, #v3d_docstring.classes do
			local str = gen_type_methods_for(v3d_docstring.classes[i])

			if str ~= '' then
				table.insert(blocks, str)
			end
		end

		table.insert(blocks, '--- @diagnostic enable: missing-return, unused-local')

		return table.concat(blocks, '\n')
	end

	v3d_content = v3d_content:gsub('%-%- #gen%-type%-methods', gen_type_methods)
end

do -- replace `-- #gen-type-instances`
	--- @return string
	local function gen_type_instances()
		local blocks = {}

		for i = 1, #v3d_docstring.classes do
			local class = v3d_docstring.classes[i]
			if class.instances_tracked then
				table.insert(blocks, '__type_instances.' .. class.name .. ' = setmetatable({}, { __mode = \'v\' })')
			end
		end

		return table.concat(blocks, '\n')
	end

	v3d_content = v3d_content:gsub('%-%- #gen%-type%-instances', gen_type_instances)
end

do -- replace `-- #gen-generated-functions`
	local function gen_generated_functions()
		local lines = {}
		local has_generated = {}

		for i = 1, #v3d_docstring.classes do
			for _, fn in ipairs(v3d_docstring.classes[i].methods) do
				if not has_generated[fn.name] and fn.is_generated then
					-- we use this weird write_name to confuse the LS so it
					-- doesn't complain about us overwriting a field
					local write_name = fn.name
						:gsub('%.([%w_]+)', function(field)
							return string.format('[true and %q]', field)
						end)
					has_generated[fn.name] = true
					table.insert(lines, write_name .. ' = function(instance, ...)')
					table.insert(lines, '\treturn instance:' .. fn.method_name .. '(...)')
					table.insert(lines, 'end')
				end
			end
		end

		return table.concat(lines, '\n')
	end

	v3d_content = v3d_content:gsub('%-%- #gen%-generated%-functions', gen_generated_functions)
end

do -- replace `-- #gen-show-types`
	local function gen_show_types()
		local lines = {}

		for _, class in ipairs(v3d_docstring.classes) do
			if not class.is_structural then
				table.insert(lines, 'v3d_show_types[\'' .. class.name .. '\'] = function(item, line)')
				table.insert(lines, '\ttable.insert(line.left_text_segments_expanded, {')
				table.insert(lines, '\t\ttext = \'' .. class.name .. '\',')
				table.insert(lines, '\t\tcolour = COLOUR_V3D_TYPE,')
				table.insert(lines, '\t})')

				for _, field in ipairs(class.fields) do
					if not field.is_private then
						table.insert(lines, '\tshow(item.' .. field.name .. ', insert_to_lines(line, new_rich_line {')
						table.insert(lines, '\t\tleft_text_segments_expanded = {')
						table.insert(lines, '\t\t\t{ text = \'' .. field.name .. '\', colour = COLOUR_VARIABLE },')
						table.insert(lines, '\t\t\t{ text = \' = \', colour = COLOUR_FOREGROUND_ALT },')
						table.insert(lines, '\t\t},')
						table.insert(lines, '\t\tindentation = line.indentation + 1')
						table.insert(lines, '\t}))')
					end
				end

				table.insert(lines, 'end')
			end
		end

		return table.concat(lines, '\n\t')
	end

	v3debug_content = v3debug_content:gsub('%-%- #gen%-show%-types', gen_show_types)
end

do -- replace `-- #gen-function-parameter-names`
	local function gen_function_parameter_names()
		local lines = {}

		for i, fn in ipairs(v3d_docstring.functions) do
			local parameter_names = {}
			for j = 1, #fn.parameters do
				table.insert(parameter_names, '\'' .. fn.parameters[j].name .. '\'')
			end

			lines[i] = 'v3d_function_parameter_names[\'' .. fn.name .. '\'] = '
			        .. '{ ' .. table.concat(parameter_names, ', ') .. ' }'
		end

		return table.concat(lines, '\n\t')
	end

	v3debug_content = v3debug_content:gsub('%-%- #gen%-function%-parameter%-names', gen_function_parameter_names)
end

do -- replace `-- #gen-function-wrappers` and `-- #gen-generated-function-wrappers`
	local fn_blacklist = {
		['v3d.enter_debug_region'] = true,
		['v3d.exit_debug_region'] = true,
	}

	local type_validator_lines = {}
	local generated_union_validator = false
	local generated_map_validator = false
	local generated_list_validator = false
	local generated_builtin_type_validators = {}
	local generated_constant_type_validators = {}
	local generated_v3d_type_validators = {}
	local get_type_validator

	local function get_union_type_validator(types)
		if not generated_union_validator then
			table.insert(type_validator_lines, 'local function _v3d_validate_union(validators)')
			table.insert(type_validator_lines, '\treturn function(errors, attribute, value)')
			table.insert(type_validator_lines, '\t\tlocal sub_errors = {}')
			table.insert(type_validator_lines, '\t\tfor i = 1, #validators do')
			table.insert(type_validator_lines, '\t\t\tlocal pre_error_count = #sub_errors')
			table.insert(type_validator_lines, '\t\t\tvalidators[i](sub_errors, attribute, value)')
			table.insert(type_validator_lines, '\t\t\tif #sub_errors == pre_error_count then return end')
			table.insert(type_validator_lines, '\t\tend')
			table.insert(type_validator_lines, '\t\tfor i = 1, #sub_errors do')
			table.insert(type_validator_lines, '\t\t\ttable.insert(errors, sub_errors[i])')
			table.insert(type_validator_lines, '\t\tend')
			table.insert(type_validator_lines, '\tend')
			table.insert(type_validator_lines, 'end')
			generated_union_validator = true
		end

		local validators = {}
		for i = 1, #types do
			table.insert(validators, get_type_validator(types[i]))
		end

		return '_v3d_validate_union {' .. table.concat(validators, ', ') .. '}'
	end

	local function get_map_type_validator(key_type, value_type)
		if not generated_map_validator then
			table.insert(type_validator_lines, 'local function _v3d_validate_map(key_validator, value_validator)')
			table.insert(type_validator_lines, '\treturn function(errors, attribute, value)')
			table.insert(type_validator_lines, '\t\tif type(value) ~= \'table\' then')
			table.insert(type_validator_lines, '\t\t\ttable.insert(errors, { attribute = attribute, value = value, message = \'expected table, got \' .. type(value) })')
			table.insert(type_validator_lines, '\t\telse')
			table.insert(type_validator_lines, '\t\t\tfor k, v in pairs(value) do')
			table.insert(type_validator_lines, '\t\t\t\tlocal sub_attribute = attribute .. \'[\' .. tostring(k) .. \']\'')
			table.insert(type_validator_lines, '\t\t\t\tif type(k) == \'string\' and not k:find \'[^%w_]\' then')
			table.insert(type_validator_lines, '\t\t\t\t\tsub_attribute = attribute .. \'.\' .. k')
			table.insert(type_validator_lines, '\t\t\t\tend')
			table.insert(type_validator_lines, '\t\t\t\tif key_validator then key_validator(errors, attribute .. \' key \' .. tostring(k), k) end')
			table.insert(type_validator_lines, '\t\t\t\tif value_validator then value_validator(errors, sub_attribute, v) end')
			table.insert(type_validator_lines, '\t\t\tend')
			table.insert(type_validator_lines, '\t\tend')
			table.insert(type_validator_lines, '\tend')
			table.insert(type_validator_lines, 'end')
			generated_map_validator = true
		end

		return string.format(
			'_v3d_validate_map(%s, %s)',
			tostring(get_type_validator(key_type)),
			tostring(get_type_validator(value_type))
		)
	end

	local function get_list_type_validator(value_type)
		if not generated_list_validator then
			table.insert(type_validator_lines, 'local function _v3d_validate_list(validator)')
			table.insert(type_validator_lines, '\treturn function(errors, attribute, value)')
			table.insert(type_validator_lines, '\t\tif type(value) ~= \'table\' then')
			table.insert(type_validator_lines, '\t\t\ttable.insert(errors, { attribute = attribute, value = value, message = \'expected table, got \' .. type(value) })')
			table.insert(type_validator_lines, '\t\telseif validator then')
			table.insert(type_validator_lines, '\t\t\tfor i = 1, #value do')
			table.insert(type_validator_lines, '\t\t\t\tlocal v = value[i]')
			table.insert(type_validator_lines, '\t\t\t\tlocal sub_attribute = attribute .. \'[\' .. i .. \']\'')
			table.insert(type_validator_lines, '\t\t\t\tvalidator(errors, sub_attribute, v)')
			table.insert(type_validator_lines, '\t\t\tend')
			table.insert(type_validator_lines, '\t\tend')
			table.insert(type_validator_lines, '\tend')
			table.insert(type_validator_lines, 'end')
			generated_list_validator = true
		end

		return string.format(
			'_v3d_validate_list(%s)',
			tostring(get_type_validator(value_type))
		)
	end

	local function get_lua_builtin_type_validator(typename)
		if generated_builtin_type_validators[typename] then
			return generated_builtin_type_validators[typename]
		end

		local validator_name = '_v3d_validate_builtin_type_' .. typename
		generated_builtin_type_validators[typename] = validator_name

		table.insert(type_validator_lines, 'local function ' .. validator_name .. '(errors, attribute, value)')

		if typename == 'integer' then
			table.insert(type_validator_lines, '\tif type(value) ~= \'number\' or value % 1 ~= 0 then')
			table.insert(type_validator_lines, '\t\ttable.insert(errors, { attribute = attribute, value = value, message = \'expected ' .. typename .. ', got \' .. type(value) })')
		else
			table.insert(type_validator_lines, '\tif type(value) ~= \'' .. typename .. '\' then')
			table.insert(type_validator_lines, '\t\ttable.insert(errors, { attribute = attribute, value = value, message = \'expected ' .. typename .. ', got \' .. type(value) })')
		end

		table.insert(type_validator_lines, '\tend')
		table.insert(type_validator_lines, 'end')

		return validator_name
	end

	local function get_constant_type_validator(value)
		if generated_constant_type_validators[value] then
			return generated_constant_type_validators[value]
		end

		local validator_name = '_v3d_validate_constant_type_' .. value:gsub('[^%w_]+', '_')
		generated_constant_type_validators[value] = validator_name

		table.insert(type_validator_lines, 'local function ' .. validator_name .. '(errors, attribute, value)')
		table.insert(type_validator_lines, '\tif value ~= ' .. value .. ' then')
		table.insert(type_validator_lines, '\t\ttable.insert(errors, { attribute = attribute, value = value, message = \'expected ' .. value:gsub('\'', '\\\'') .. ', got \' .. tostring(value) })')
		table.insert(type_validator_lines, '\tend')
		table.insert(type_validator_lines, 'end')

		return validator_name
	end

	local function get_v3d_alias_type_validator(alias)
		if #alias.validations == 0 then
			return get_type_validator(docstring.parse_type(alias.alias))
		end

		if generated_v3d_type_validators[alias.name] then
			return generated_v3d_type_validators[alias.name]
		end

		local validator_name = '_v3d_validate_v3d_alias_type_' .. alias.name
		generated_v3d_type_validators[alias.name] = validator_name

		local validator = get_type_validator(docstring.parse_type(alias.alias))

		table.insert(type_validator_lines, 'local function ' .. validator_name .. '(errors, attribute, value)')
		table.insert(type_validator_lines, '\tlocal pre_error_count = #errors')
		table.insert(type_validator_lines, '\t' .. validator .. '(errors, attribute, value)')
		table.insert(type_validator_lines, '\tif #errors > pre_error_count then return end')

		for i = 1, #alias.validations do
			local validation = alias.validations[i]
			table.insert(type_validator_lines, '\tif not (' .. validation.check_code:gsub('self', 'value') .. ') then')
			table.insert(type_validator_lines, '\t\ttable.insert(errors, { attribute = attribute, value = value, message = \'' .. validation.message:gsub('\'', '\\\'') .. '\' })')
			table.insert(type_validator_lines, '\tend')
		end

		table.insert(type_validator_lines, 'end')

		return validator_name
	end

	local function get_v3d_structural_type_validator(class)
		if generated_v3d_type_validators[class.name] then
			return generated_v3d_type_validators[class.name]
		end

		local validator_name = '_v3d_validate_v3d_structural_type_' .. class.name
		generated_v3d_type_validators[class.name] = validator_name

		local fields_to_validate = {}
		local class_to_check = class

		while class_to_check do
			for _, field in ipairs(class_to_check.fields) do
				if not field.is_private then
					local field_validator = get_type_validator(docstring.parse_type(field.type))
					table.insert(fields_to_validate, { field = field, validator = field_validator })
				end
			end
			class_to_check = v3d_docstring.classes[class_to_check.extends]
		end

		table.insert(type_validator_lines, 'local function ' .. validator_name .. '(errors, attribute, value)')
		table.insert(type_validator_lines, '\tif type(value) ~= \'table\' then')
		table.insert(type_validator_lines, '\t\ttable.insert(errors, { attribute = attribute, value = value, message = \'expected ' .. class.name .. ', got \' .. type(value) })')
		table.insert(type_validator_lines, '\telse')
		for i = 1, #fields_to_validate do
			local field = fields_to_validate[i].field
			local field_validator = fields_to_validate[i].validator
			if field_validator then
				table.insert(type_validator_lines, '\t\t' .. field_validator .. '(errors, attribute .. \'.' .. field.name .. '\', value.' .. field.name .. ')')
			end
		end

		for _, validation in ipairs(class.validations) do
			table.insert(type_validator_lines, '\t\tif not (' .. validation.check_code:gsub('self', 'value') .. ') then')
			table.insert(type_validator_lines, '\t\t\ttable.insert(errors, { attribute = attribute, value = value, message = \'' .. validation.message:gsub('\'', '\\\'') .. '\' })')
			table.insert(type_validator_lines, '\t\tend')
		end

		table.insert(type_validator_lines, '\tend')
		table.insert(type_validator_lines, 'end')

		return validator_name
	end

	--- @param class DocstringClass
	local function get_v3d_non_structural_type_validator(class)
		if generated_v3d_type_validators[class.name] then
			return generated_v3d_type_validators[class.name]
		end

		local validator_name = '_v3d_validate_v3d_non_structural_type_' .. class.name
		generated_v3d_type_validators[class.name] = validator_name

		local valid_typenames = { class.name }
		for _, subclass in ipairs(class.subclasses) do
			table.insert(valid_typenames, subclass.name)
		end

		local init = ''
		local checks = {}

		if #valid_typenames <= 3 then
			for i = 1, #valid_typenames do
				table.insert(checks, 'value.__v3d_typename ~= \'' .. valid_typenames[i] .. '\'')
			end
		else
			init = 'local ' .. validator_name .. '_valid_typenames = {'
		
			for i = 1, #valid_typenames do
				init = init .. '[\'' .. valid_typenames[i] .. '\'] = true, '
			end

			init = init .. '}'

			checks[1] = 'not ' .. validator_name .. '_valid_typenames[value.__v3d_typename]'
		end

		if init ~= '' then table.insert(type_validator_lines, init) end
		table.insert(type_validator_lines, 'local function ' .. validator_name .. '(errors, attribute, value)')
		table.insert(type_validator_lines, '\tif type(value) ~= \'table\' then')
		table.insert(type_validator_lines, '\t\ttable.insert(errors, { attribute = attribute, value = value, message = \'expected ' .. class.name .. ', got \' .. type(value) })')
		table.insert(type_validator_lines, '\telseif ' .. table.concat(checks, ' and ') .. ' then')
		table.insert(type_validator_lines, '\t\ttable.insert(errors, { attribute = attribute, value = value, message = \'expected ' .. class.name .. ', got \' .. (value.__v3d_typename or \'generic table\') })')
		table.insert(type_validator_lines, '\tend')
		table.insert(type_validator_lines, 'end')

		return validator_name
	end

	--- @param type DocstringType
	--- @return string | nil
	function get_type_validator(type)
		if type.kind == 'union' then
			return get_union_type_validator(type.types)
		elseif type.kind == 'map' then
			return get_map_type_validator(type.key_type, type.value_type)
		elseif type.kind == 'list' then
			return get_list_type_validator(type.type)
		elseif type.kind == 'lua-builtin' then
			return get_lua_builtin_type_validator(type.name)
		elseif type.kind == 'constant' then
			return get_constant_type_validator(type.value)
		elseif type.kind == 'ref' then
			local v3d_alias_type = v3d_docstring.aliases[type.name]
			local v3d_class_type = v3d_docstring.classes[type.name]
			assert(v3d_alias_type or v3d_class_type, type.name)

			if v3d_alias_type then
				return get_v3d_alias_type_validator(v3d_alias_type)
			elseif v3d_class_type.is_structural then
				return get_v3d_structural_type_validator(v3d_class_type)
			else
				return get_v3d_non_structural_type_validator(v3d_class_type)
			end
		elseif type.kind == 'any' then
			return nil
		end
	end

	local function gen_function_wrapper(lines, revised_name, fn)
		local param_names = {}
		local reference_name = '_original_' .. fn.name:gsub('%.', '_')
		for i = 1, #fn.parameters do
			table.insert(param_names, fn.parameters[i].name)
		end
		table.insert(lines, 'local ' .. reference_name .. ' = ' .. revised_name)
		table.insert(lines, 'function ' .. revised_name .. '(' .. table.concat(param_names, ', ') .. ')')

		if #fn.parameters > 0 then
			table.insert(lines, '\tlocal _validation_errors = {}')

			for i = 1, #fn.parameters do
				local validator = get_type_validator(docstring.parse_type(fn.parameters[i].type))
				if validator ~= nil then
					table.insert(lines, string.format('\t%s(_validation_errors, %q, %s)', validator, fn.parameters[i].name, fn.parameters[i].name))
				end
			end
		end

		if #fn.validations > 0 then
			table.insert(lines, '\tif #_validation_errors == 0 then')
			for i = 1, #fn.validations do
				local validation = fn.validations[i]
				table.insert(lines, '\t\tif not (' .. validation.check_code .. ') then')
				table.insert(lines, '\t\t\ttable.insert(_validation_errors, { attribute = nil, value = nil, message = \'' .. validation.message:gsub('\'', '\\\'') .. '\' })')
				table.insert(lines, '\t\tend')
			end
			table.insert(lines, '\tend')
		end

		table.insert(lines, '\tif #_validation_errors > 0 then')
		table.insert(lines, '\t\tV3D_VALIDATION_ERROR.context = {')
		table.insert(lines, '\t\t\terrors = _validation_errors,')
		table.insert(lines, '\t\t\tfn_name = \'' .. fn.name .. '\',')
		table.insert(lines, '\t\t\tparameters = {')

		for i = 1, #param_names do
			table.insert(lines, '\t\t\t\t{ name = \'' .. param_names[i] .. '\', value = ' .. param_names[i] .. ' },')
		end

		table.insert(lines, '\t\t\t}')
		table.insert(lines, '\t\t}')
		table.insert(lines, '\t\terror(V3D_VALIDATION_ERROR, 2)')
		table.insert(lines, '\tend')

		if fn.is_v3debug_logged then
			table.insert(lines, '\tlocal _call = { fn_name = \'' .. fn.name .. '\', parameters = { ' .. table.concat(param_names, ', ') .. ' } }')
			table.insert(lines, '\t_table_insert(v3d_this_frame_calls, _call)')
			table.insert(lines, '\tlocal result = ' .. reference_name .. '(' .. table.concat(param_names, ', ') .. ')')
			table.insert(lines, '\t_call.result = result')
			table.insert(lines, '\treturn result')
		else
			table.insert(lines, '\treturn ' .. reference_name .. '(' .. table.concat(param_names, ', ') .. ')')
		end
		table.insert(lines, 'end')
	end

	local function gen_function_wrappers(indent)
		local lines = {}

		lines[1] = 'local _table_insert = table.insert'

		for _, fn in ipairs(v3d_docstring.functions) do
			if not fn_blacklist[fn.name] and (fn.is_v3debug_logged or #fn.parameters > 0) and not fn.is_generated then
				local revised_name = fn.name:gsub('v3d%.', 'v3d_modified_library%.')
				gen_function_wrapper(lines, revised_name, fn)
			end
		end

		return '\n' .. indent .. table.concat(lines, '\n' .. indent)
	end

	local function gen_generated_function_wrappers(indent)
		local lines = {}

		for _, class in ipairs(v3d_docstring.classes) do
			local methods_to_generate_for = {}
			for _, fn in ipairs(class.methods) do
				if not fn_blacklist[fn.name] and (fn.is_v3debug_logged or #fn.parameters > 0) and fn.is_generated then
					methods_to_generate_for[fn.method_name] = fn
				end
			end
			if next(methods_to_generate_for) then
				table.insert(lines, string.format('_original_v3d_set_create_hook(%q, function(instance)', class.name))
				local l = {}
				for method_name, fn in pairs(methods_to_generate_for) do
					gen_function_wrapper(l, 'instance.' .. method_name, fn)
				end
				for i = 1, #l do
					table.insert(lines, '\t' .. l[i])
				end
				table.insert(lines, 'end)')
			end
		end

		return '\n' .. indent .. table.concat(lines, '\n' .. indent)
	end

	v3debug_content = v3debug_content:gsub('\n(%s*)%-%-%s*#gen%-function%-wrappers', gen_function_wrappers)
	v3debug_content = v3debug_content:gsub('\n(%s*)%-%-%s*#gen%-generated%-function%-wrappers', gen_generated_function_wrappers)
	v3debug_content = v3debug_content:gsub('\n(%s*)%-%-%s*#gen%-type%-validators', function(indent)
		return '\n' .. indent .. table.concat(type_validator_lines, '\n' .. indent)
	end)
end

do -- replace `-- #gen-method-wrappers`
	local function gen_method_wrappers(indent)
		local s = {}
		for _, class in ipairs(v3d_docstring.classes) do
			if not class.is_abstract and #class.methods > 0 then
				for _, fn in ipairs(class.methods) do
					if not fn.is_generated then
						table.insert(s, string.format(
							'_original_v3d_set_method(%q, %q, %s)',
							class.name,
							fn.method_name,
							fn.name:gsub('v3d%.', 'v3d_modified_library%.')
						))
					end
				end
			end
		end
		return '\n' .. indent .. table.concat(s, '\n' .. indent)
	end

	v3debug_content = v3debug_content:gsub('\n(%s*)%-%-%s*#gen%-method%-wrappers', gen_method_wrappers)
end

do -- replace `-- #gen-metamethod-wrappers`
	local function gen_metamethod_wrappers(indent)
		local s = {}
		for _, class in ipairs(v3d_docstring.classes) do
			if not class.is_abstract and #class.methods > 0 then
				for _, fn in pairs(class.methods) do
					for _, metamethod in ipairs(fn.metamethods) do
						table.insert(s, string.format(
							'_original_v3d_set_metamethod(%q, %q, %s)',
							class.name,
							'__' .. metamethod,
							fn.name:gsub('v3d%.', 'v3d_modified_library%.')
						))
					end
				end
			end
		end
		return '\n' .. indent .. table.concat(s, '\n' .. indent)
	end

	v3debug_content = v3debug_content:gsub('\n(%s*)%-%-%s*#gen%-metamethod%-wrappers', gen_metamethod_wrappers)
end

write_file('artifacts/v3d.lua', v3d_content)
write_file('artifacts/v3debug.lua', v3debug_content)
assert(load(v3d_content, 'v3d.lua'))
assert(load(v3debug_content, 'v3debug.lua'))

do -- write warnings to warnings.txt:
	local h = assert(io.open(v3d_base_dir .. 'artifacts/warnings.txt', 'w'))
	local max_type_length = 0
	local max_line_length = 0

	for i = 1, #v3d_warnings do
		local line_length = #tostring(v3d_warnings[i].line)

		if #v3d_warnings[i].type > max_type_length then
			max_type_length = #v3d_warnings[i].type
		end

		if line_length > max_line_length then
			max_line_length = line_length
		end
	end

	for i = 1, #v3d_warnings do
		h:write(string.format('(%' .. max_type_length .. 's) [%' .. max_line_length .. 'd]: %s\n',
			v3d_warnings[i].type,
			v3d_warnings[i].line,
			v3d_warnings[i].message))
	end

	h:close()
end

if quick_build then
	return
end

write_file('artifacts/v3d-no-doc-comment.lua', v3d_content:gsub('%-%-%-.-\n', '\n'))

do -- generate a function and type list
	local advanced_function_lines = {}
	local advanced_function_type_lines = {}
	local function_lines = {}
	local function_type_lines = {}
	local type_lines = {}

	for _, fn in ipairs(v3d_docstring.functions) do
		local parameters = {}
		for i = 1, #fn.parameters do
			table.insert(parameters, fn.parameters[i].name .. ': ' .. fn.parameters[i].type)
		end

		local to_insert = fn.name:gsub('^v3d%.', '%* ')
		local type_to_insert = to_insert .. '(' .. table.concat(parameters, ', ') .. ')'

		if fn.is_advanced then
			table.insert(advanced_function_lines, to_insert)
			table.insert(advanced_function_type_lines, type_to_insert)
		else
			table.insert(function_lines, to_insert)
			table.insert(function_type_lines, type_to_insert)
		end
	end

	for _, alias in ipairs(v3d_docstring.aliases) do
		table.insert(type_lines, '* ' .. alias.name)
	end
	for _, class in ipairs(v3d_docstring.classes) do
		table.insert(type_lines, '* ' .. class.name)
	end

	table.sort(function_lines)
	table.sort(type_lines)

	write_file('artifacts/v3doc/advanced-function-list.txt', table.concat(advanced_function_lines, '\n'))
	write_file('artifacts/v3doc/function-list.txt', table.concat(function_lines, '\n'))
	write_file('artifacts/v3doc/advanced-function-type-list.txt', table.concat(advanced_function_type_lines, '\n'))
	write_file('artifacts/v3doc/function-type-list.txt', table.concat(function_type_lines, '\n'))
	write_file('artifacts/v3doc/type-list.txt', table.concat(type_lines, '\n'))
end

do -- generate v3doc source_documents for embedding
	local document_sources = 'artifacts/v3doc/document_sources/'

	for i = 1, #v3d_docstring.aliases do
		write_file(
			document_sources .. 'alias/' .. v3d_docstring.aliases[i].name .. '.md',
			embedgen.generate_alias_embedded_documentation(v3d_docstring.aliases[i]))
	end

	for i = 1, #v3d_docstring.classes do
		local methods = v3d_docstring.classes[i].methods
		local class_name = v3d_docstring.classes[i].name
		local main_content = embedgen.generate_class_embedded_documentation(v3d_docstring.classes[i], v3d_docstring.classes)
		local constructors_content = embedgen.generate_class_constructor_embedded_documentation(v3d_docstring.classes[i], v3d_docstring.functions)
		write_file(document_sources .. 'class/type/' .. class_name .. '.md', main_content)
		write_file(document_sources .. 'class/constructor/' .. class_name .. '.md', constructors_content)

		if #methods > 0 then
			write_file(
				document_sources .. 'class/method/' .. class_name .. '.md',
				embedgen.generate_class_method_embedded_documentation(v3d_docstring.classes[i]))
		end
	end

	for i = 1, #v3d_docstring.functions do
		write_file(
			document_sources .. 'function/' .. v3d_docstring.functions[i].name .. '.md',
				embedgen.generate_function_embedded_documentation(v3d_docstring.functions[i]))
	end

	local snippet_files = fs.list(v3d_base_dir .. 'src/v3d/doc')
	for i = 1, #snippet_files do
		local snippet_content = read_file('src/v3d/doc/' .. snippet_files[i])
		write_file(
			document_sources .. 'snippet/' .. snippet_files[i],
			embedgen.annotate_snippet(snippet_files[i]:gsub('%.md$', ''), snippet_content))
	end
end

do -- generate human-facing docstrings
	-- generate function docstrings
	for i = 1, #v3d_docstring.functions do
		write_file(
			'artifacts/v3doc/user/function/' .. v3d_docstring.functions[i].name .. '.md',
			docgen.generate_function_documentation(v3d_docstring.functions[i], false))
	end

	-- generate alias docstrings
	for i = 1, #v3d_docstring.aliases do
		write_file(
			'artifacts/v3doc/user/alias/' .. v3d_docstring.aliases[i].name .. '.md',
			docgen.generate_alias_documentation(v3d_docstring.aliases[i]))
	end

	-- generate class docstrings
	for i = 1, #v3d_docstring.classes do
		write_file(
			'artifacts/v3doc/user/class/' .. v3d_docstring.classes[i].name .. '.md',
			docgen.generate_class_documentation(v3d_docstring.classes[i], v3d_docstring, false))
	end
end

do -- run tests:
	local h = assert(io.open(v3d_base_dir .. 'src/v3d/test.lua'))
	local test_content = h:read '*a'
	h:close()

	local test_env = {}

	local env = _ENV
	while env do
		for k, v in pairs(env) do
			test_env[k] = v
		end
		env = getmetatable(env) and getmetatable(env).__index
	end

	test_env.require, test_env.module = require '/rom.modules.main.cc.require' .make(_ENV, v3d_base_dir .. 'src/v3d')
	test_env.module.preload['v3d'] = assert(load(v3d_content, 'v3d.lua'))

	local test_f = assert(load(test_content, 'test.lua', nil, test_env))
	test_f()
end

do -- test examples:
	local w, h = term.getSize()
	local window = _ENV.window.create(term.current(), 1, 1, w, h, false)

	for _, fn in ipairs(v3d_docstring.functions) do
		for i, example_usage in ipairs(fn.example_usages) do
			local filename = 'artifacts/examples/' .. fn.name .. '-' .. i .. '.lua'
			local content = 'local v3d = require \'v3d\''
			             .. table.concat(example_usage.lines, '\n')
			write_file(filename, content)
			local prev = term.redirect(window)
			local ok = shell.execute('/' .. v3d_base_dir .. 'artifacts/v3debug.lua', '/' .. v3d_base_dir .. filename)
			term.redirect(prev)
			if not ok then
				error('Example ' .. i .. ' from ' .. fn.name .. ' failed', 0)
			end
		end
	end
end
