
local no_minify = ...

local luatools = require 'luatools'
local docparse = require 'docparse'

local build_config = require 'build_config'

local base_path = shell and (shell.getRunningProgram():match '^(.+/).-/' or '') or 'v3d/'
local src_path = base_path .. 'src/'
local gen_path = base_path .. 'gen/'
local license_text, interface_text, implementation_text, v3dd_text
local module_dependencies = {}
local modules = {}

do -- read the files
	local function preprocess(text)
		return text:gsub('%-%-%s*#remove.-%-%-%s*#end', '')
	end

	local h

	h = assert(io.open(base_path .. 'LICENSE'), 'Failed to read LICENSE')
	license_text = h:read '*a'
	h:close()

	h = assert(io.open(src_path .. 'v3d.lua'), 'Failed to read v3d.lua')
	interface_text = h:read '*a'
	h:close()

	h = assert(io.open(src_path .. 'implementation.lua'), 'Failed to read implementation.lua')
	implementation_text = h:read '*a'
	h:close()

	h = assert(io.open(src_path .. 'v3dd.lua'), 'Failed to read v3dd.lua')
	v3dd_text = h:read '*a'
	h:close()

	interface_text = preprocess(interface_text)
	implementation_text = preprocess(implementation_text)

	local module_names = fs.list(src_path .. 'v3d')
	for i = 1, #module_names do
		local module_name = module_names[i]:gsub('%.lua$', '', 1)
		h = assert(io.open(src_path .. 'v3d/' .. module_names[i], 'r'))
		local content = h:read '*a'

		local dependencies = {}

		for dependency in content:gmatch 'require%s*[\'"]([%w_]+)[\'"]' do
			table.insert(dependencies, dependency)
		end

		content = content:gsub('local%s+v3d%s*=%s*require%s*[\'"]core[\'"]', '')
		                 :gsub('require%s*[\'"]([%w_]+)[\'"]', '__modules_%1')
		                 :gsub('return (v3d_' .. module_name:gsub('^_', '') .. ')%s*$', '__modules_' .. module_name .. ' = %1\n')

		module_dependencies[module_name] = dependencies
		modules[module_name] = content
		h:close()
	end
end

local v3d_types = docparse.parse(interface_text)
local v3d_library_type = v3d_types['v3d']

if false then -- warn on missing documentation
	local missing = 0

	local function warn(fmt, ...)
		local params = { ... }
		local parts = {}

		missing = missing + 1
		fmt = 'Missing documentation: ' .. fmt .. ' '

		for part in fmt:gmatch '[^@]+' do
			table.insert(parts, part)
		end

		for i = 1, #parts do
			term.setTextColour(colours.yellow)
			term.write(parts[i])

			if i < #parts then
				term.setTextColour(colours.cyan)
				term.write('\'' .. params[i] .. '\'')
			end
		end

		print()
	end

	for i = 1, #v3d_types do
		if v3d_types[i].docstring == docparse.MISSING_DOCUMENTATION then
			warn('type @', v3d_types[i].name)
		end

		for j = 1, #v3d_types[i].fields do
			if v3d_types[i].fields[j].docstring == docparse.MISSING_DOCUMENTATION then
				warn('type @ field @', v3d_types[i].name, v3d_types[i].fields[j].name)
			end
		end

		for j = 1, #v3d_types[i].functions do
			if v3d_types[i].functions[j].docstring == docparse.MISSING_DOCUMENTATION then
				warn('type @ function @', v3d_types[i].name, v3d_types[i].functions[j].name)
			end

			for k = 1, #v3d_types[i].functions[j].overloads do
				for l = 1, #v3d_types[i].functions[j].overloads[k].parameters do
					if v3d_types[i].functions[j].overloads[k].parameters[l].docstring == docparse.MISSING_DOCUMENTATION then
						warn('type @ function @ parameter @', v3d_types[i].name, v3d_types[i].functions[j].name, v3d_types[i].functions[j].overloads[k].parameters[l].name)
					end
				end
			end
		end
	end

	term.setTextColour(colours.yellow)
	print('Total of ' .. missing .. ' missing entries')
end

if false then -- produce compiled v3d.lua
	local header_text = '-- ' .. license_text:gsub('\n', '\n-- ') .. '\n'
	                 .. '---@diagnostic disable:duplicate-doc-field,duplicate-set-field,duplicate-doc-alias\n'
	local content = interface_text .. '\n' .. implementation_text
	local pre_minify_len = #header_text + #content
	local content_tokens = luatools.tokenise(content)
	luatools.strip_comments(content_tokens)
	luatools.strip_whitespace(content_tokens)
	luatools.minify(content_tokens)
	content = header_text .. luatools.concat(content_tokens)
	content = content:gsub('\n\n+', '\n')

	local OUTPUT_PATH = gen_path .. 'v3d.lua'
	local h = assert(io.open(OUTPUT_PATH, 'w'))
	h:write(content)
	h:close()

	assert(load(content, 'v3d.lua'))

	term.setTextColour(colours.lightGrey)
	term.write('Compiled library code to ')
	term.setTextColour(colours.cyan)
	print(OUTPUT_PATH)
	term.setTextColour(colours.lightGrey)
	print(string.format('  minification: %d / %d (%d%%)', #content, pre_minify_len, #content / pre_minify_len * 100 + 0.5))
	term.setTextColour(colours.white)
end

if false then -- produce compiled api_reference.md
	local function type_to_markdown(s)
		return (s:gsub('\'.-\'', function(ss)
			return '`' .. ss .. '`'
		end):gsub('%[%]', function(ss)
			return '`' .. ss .. '`'
		end):gsub('[a-zA-Z\'][%w_%-]*', function(ss)
			if ss:sub(1, 1) == '\'' then
				return ss
			end
			if v3d_types[ss] then
				return '[`' .. ss .. '`](#' .. ss:lower() .. ')'
			else
				return '`' .. ss .. '` '
			end
		end))
	end

	local function docstring_to_markdown(s, inline)
		s = s:gsub('%[%[@([%w_%.]+)%]%]', function(ss)
			return '[`' .. ss .. '`](#' .. ss:gsub('[^%w_]', ''):lower() .. ')'
		end)

		if inline then
			return (s:gsub('\n\t*%*', '<br>'):gsub('\n\n', '<br><br>'):gsub('\n', ' '))
		else
			return s
		end
	end

	local OUTPUT_PATH = gen_path .. 'api_reference.md'
	local h = assert(io.open(OUTPUT_PATH, 'w'))

	local sorted_typenames = {}

	for i = 1, #v3d_types do
		if v3d_types[i].name ~= v3d_library_type.name then
			table.insert(sorted_typenames, v3d_types[i].name)
		end
	end

	table.sort(sorted_typenames)
	table.insert(sorted_typenames, 1, v3d_library_type.name)

	h:write '\n# Index\n\n'

	for i = 1, #sorted_typenames do
		local class = v3d_types[sorted_typenames[i]]
		h:write '* [`'
		h:write(class.name)
		h:write '`](#'
		h:write(class.name:lower())
		h:write ')\n'

		for j = 1, #class.functions do
			h:write '  * [`'
			h:write(class.name)
			h:write(class.functions[j].is_method and ':' or '.')
			h:write(class.functions[j].name)
			h:write('()`](#')
			h:write(class.name:lower())
			h:write(class.functions[j].name:lower())
			h:write ')\n'
		end
	end

	h:write '\n'

	for i = 1, #v3d_types do
		local class = v3d_types[i]

		h:write '---\n\n# `'
		h:write(class.name)
		h:write '`\n\n'

		if class.extends then
			if class.kind == 'alias' then
				h:write '## Alias of '
			else
				h:write '## Extends '
			end
			h:write(type_to_markdown(class.extends))
			h:write '\n\n'
		end

		h:write(docstring_to_markdown(class.docstring, false))
		h:write '\n\n'

		if class.kind ~= 'alias' then
			h:write '## Fields\n\n'

			if #class.fields > 0 then
				h:write 'Name | Type | Description\n'
				h:write '-|-|-\n'
			else
				h:write 'This type has no fields.\n'
			end

			for j = 1, #class.fields do
				h:write '`'
				h:write(class.fields[j].name)
				h:write '` | '
				h:write((type_to_markdown(class.fields[j].type):gsub('|', '\\|')))
				h:write ' | '
				h:write(docstring_to_markdown(class.fields[j].docstring, true))
				h:write '\n'
			end

			h:write '\n'
		end

		if class.kind ~= 'alias' then
			h:write '## Functions\n\n'

			if #class.functions == 0 then
				h:write 'This type has no functions.\n\n'
			end

			for j = 1, #class.functions do
				local method = class.functions[j]

				h:write '### `'
				h:write(class.name)
				h:write(method.is_method and ':' or '.')
				h:write(method.name)
				h:write '()`\n\n'

				if method.docstring ~= '' then
					h:write(docstring_to_markdown(method.docstring, false))
					h:write '\n\n'
				end

				for k = 1, #method.overloads do
					local overload = method.overloads[k]

					h:write '#### Signature\n\n'

					h:write '```lua\nfunction '
					h:write(class.name)
					h:write(method.is_method and ':' or '.')
					h:write(method.name)
					h:write '('

					for l = 1, #overload.parameters do
						if l ~= 1 then
							h:write ', '
						end
						h:write(overload.parameters[l].name)
					end

					h:write '): '
					h:write(overload.returns)

					h:write '\n```\n\n'
					h:write '#### Parameters\n\n'

					if #overload.parameters > 0 then
						h:write 'Name | Type | Description\n'
						h:write '-|-|-\n'
					else
						h:write 'This function has no parameters.\n'
					end

					for l = 1, #overload.parameters do
						h:write '`'
						h:write(overload.parameters[l].name)
						h:write '` | '
						h:write((type_to_markdown(overload.parameters[l].type):gsub('|', '\\|')))
						h:write ' | '
						h:write(docstring_to_markdown(overload.parameters[l].docstring, true))
						h:write '\n'
					end

					h:write '\n'

					h:write '#### Returns '
					h:write(type_to_markdown(overload.returns))
					h:write '\n\n'
				end
			end
		end
	end

	h:close()

	term.setTextColour(colours.lightGrey)
	term.write 'Wrote API reference to '
	term.setTextColour(colours.cyan)
	print(OUTPUT_PATH)
	term.setTextColour(colours.white)
end

if false then -- produce compiled v3dd.lua
	local meta_aliases = build_config.v3dd_meta_aliases
	local type_checkers = build_config.v3dd_type_checkers
	local fn_logging_blacklist = build_config.v3dd_fn_logging_blacklist
	local fn_pre_hooks = build_config.v3dd_fn_pre_body
	local fn_post_hooks = build_config.v3dd_fn_post_body
	local field_detail_blacklist = build_config.v3dd_field_detail_blacklist
	local extra_details_fields = build_config.v3dd_extra_field_details

	local CONVERT_INSTANCE_TEMPLATE = [[
function convert_instance_${INSTANCE_TYPE_NAME}(instance, instance_label)
	if v3d_state.object_types[instance] then return end
	register_object(instance, "${INSTANCE_TYPE_NAME}", instance_label)
	${INSTANCE_FUNCTION_OVERRIDES}
	${INSTANCE_METATABLE}
end
]]

	local WRAPPED_FUNCTION_TEMPLATE_LOGGED = [[
local ${WF_FUNCTION_NAME}_orig = instance.${WF_FUNCTION_NAME}
function instance${WF_METHOD_STR}${WF_FUNCTION_NAME}(${WF_FN_PARAMS})
	local validation_failed = false
	local call_tree = {
		content = string.format("&cyan;${WF_FUNCTION_PREFIX}${WF_FUNCTION_NAME}&reset;(${WF_PS_N})"${WF_FMT_PARAMS}),
		content_expanded = "&cyan;${WF_FUNCTION_PREFIX}${WF_FUNCTION_NAME}&reset;(...)",
		default_expanded = false,
		children = {},
	}
	${WF_OVERLOADS}
	table.insert(v3d_state.call_trees, call_tree)
	if validation_failed then
		call_tree.content_right = '&red;validation errors'
		call_tree.default_expanded = true
		error(V3D_VALIDATION_FAILED)
	end
	${WF_PRE_HOOK}
	local return_value = ${WF_FUNCTION_NAME}_orig(${WF_FN_SELF}${WF_FN_PARAMS})
	${WF_RETURN_CONVERT}
	local return_tree = { content = "&purple;return &reset;" .. fmtobject(return_value), children = {}, default_expanded = true }
	table.insert(call_tree.children, return_tree)
	${WF_RETURN_DETAILS}
	${WF_POST_HOOK}
	return return_value
end]]

	local WRAPPED_FUNCTION_TEMPLATE_UNLOGGED = [[
local ${WF_FUNCTION_NAME}_orig = instance.${WF_FUNCTION_NAME}
function instance${WF_METHOD_STR}${WF_FUNCTION_NAME}(${WF_FN_PARAMS})
	${WF_OVERLOADS}
	local return_value = ${WF_FUNCTION_NAME}_orig(${WF_FN_SELF}${WF_FN_PARAMS})
	${WF_RETURN_CONVERT}
	return return_value
end]]

	local PARAM_TEMPLATE_LOGGED = [[
local param_${PT_PARAM_NAME}_tree = {
	content = "&lightBlue;${PT_PARAM_NAME}&reset; = " .. fmtobject(${PT_VALUE_NAME}),
	default_expanded = false,
	children = {}
}
table.insert(call_tree.children, param_${PT_PARAM_NAME}_tree)
if validation_enabled and not (${PT_TYPECHECK}) then
	validation_failed = true
	param_${PT_PARAM_NAME}_tree.default_expanded = true
	table.insert(param_${PT_PARAM_NAME}_tree.children, { content = "&red;ERROR: Expected type '${PT_TYPENAME}', got " .. type(${PT_VALUE_NAME}) })
else
	${PT_DETAILS}
end]]

	local PARAM_TEMPLATE_UNLOGGED = [[
if validation_enabled and not (${PT_TYPECHECK}) then
	error("Expected type '${PT_TYPENAME}' for parameter '${PT_PARAM_NAME}', got " .. type(${PT_VALUE_NAME}))
end]]

local SHOW_DETAILS_STUB_TEMPLATE = [[
	local show_details_${INSTANCE_TYPE_NAME}]]

local SHOW_DETAILS_TEMPLATE = [[
	function show_details_${INSTANCE_TYPE_NAME}(instance, trees)
		${INSTANCE_FIELDS}
		${EXTRA_FIELDS}
	end
	v3d_detail_generators.${INSTANCE_TYPE_NAME} = show_details_${INSTANCE_TYPE_NAME}
]]

local SHOW_DETAILS_FIELD_TEMPLATE = [[
local field_${SDF_FIELD_NAME}_tree = {
	content = "&lightBlue;${SDF_FIELD_NAME}&reset; = " .. fmtobject(instance.${SDF_FIELD_NAME}),
	default_expanded = false,
	children = {}
}
trees.${SDF_FIELD_NAME} = field_${SDF_FIELD_NAME}_tree
table.insert(trees, field_${SDF_FIELD_NAME}_tree)
${SDF_SUB_DETAILS}]]

	local function map_list(t, fn)
		local r = {}
		for i = 1, #t do
			if fn then
				r[i] = fn(t[i])
			else
				r[i] = t[i]
			end
		end
		return r
	end

	local function is_class(s)
		return v3d_types[s] and (#v3d_types[s].fields > 0 or #v3d_types[s].functions > 0)
	end

	local function get_v3d_type(typename)
		if typename:find '|%s*nil' then
			return typename:match '^(.-)%s*|%s*nil$', true
		end
		return typename, false
	end

	--- @param param_name string
	--- @param param_type string
	--- @param source_name string
	--- @param hook string
	--- @return string
	local function generate_overload_param(param_name, param_type, source_name, hook, logged)
		local actual_param_type = param_type
		local is_optional = false
		local needs_structural_check = nil
		local needs_attribute_check = nil
		local needs_layer_check = nil
		local type_checker

		do -- generate 4 fields above
			param_type, is_optional = get_v3d_type(param_type)

			type_checker = type_checkers[param_type]

			if not type_checker and v3d_types[param_type] then
				if v3d_types[param_type].kind == 'structural-class' then
					needs_structural_check = v3d_types[param_type]
					type_checker = 'type(%s) == \'table\''
				else
					type_checker = 'v3d_state.object_types[%s] == \'' .. param_type .. '\''
				end
			elseif param_type == 'V3DAttributeName | V3DAttribute' then
				needs_attribute_check = v3d_types.V3DAttribute
				type_checker = 'type(%s) == \'string\' or type(%s) == \'table\''
			elseif param_type == 'V3DLayerName | V3DLayer' then
				needs_layer_check = v3d_types.V3DLayer
				type_checker = 'type(%s) == \'string\' or type(%s) == \'table\''
			elseif param_type:find '%[%]$' or param_type:find '^%b{}$' then
				-- TODO: check contents of the table?
				type_checker = type_checkers.table
			end

			if not type_checker then
				error('No type checker for type ' .. param_type)
			end

			if is_optional then
				type_checker = '%s == nil or (' .. type_checker .. ')'
			end

			type_checker = type_checker:gsub('%%s', source_name)
		end

		local content = logged and PARAM_TEMPLATE_LOGGED
		                        or PARAM_TEMPLATE_UNLOGGED

		-- TODO: use needs_structural_check and needs_attribute_check and needs_layer_check

		local pt_details = ''

		if is_class(param_type) then
			pt_details = 'show_details_' .. param_type .. '(' .. source_name
			          .. ', param_' .. param_name .. '_tree.children)'

			if is_optional then
				pt_details = 'if ' .. source_name .. ' then ' .. pt_details .. ' end'
			end
		end

		return (content
			:gsub('${PT_PARAM_NAME}', param_name)
			:gsub('${PT_VALUE_NAME}', source_name)
			:gsub('${PT_TYPECHECK}', function() return type_checker end)
			:gsub('${PT_TYPENAME}', actual_param_type)
			:gsub('${PT_DETAILS}', pt_details))
	end

	--- @param fn_param_names string[]
	--- @param parameters NameType[]
	--- @return string
	local function generate_overload_params(fn_param_names, parameters, hook_base, logged)
		local params = {}

		for i = 1, #parameters do
			local param_name = parameters[i].name
			local param_type = parameters[i].type
			local hook = hook_base .. ' ' .. param_name
			local content = generate_overload_param(param_name, param_type, fn_param_names[i], hook, logged)

			table.insert(params, content)
		end

		return table.concat(params, '\n')
	end

	local function generate_wrapped_function(type, fn, logged)
		local wrapper = logged and WRAPPED_FUNCTION_TEMPLATE_LOGGED
		                        or WRAPPED_FUNCTION_TEMPLATE_UNLOGGED

		local fn_param_names = {}
		local fn_overloads = {}
		local fn_hook = type.name .. '.' .. fn.name

		if #fn.overloads == 1 then
			fn_overloads[1] = fn.overloads[1]
			fn_param_names = map_list(
				fn.overloads[1].parameters,
				function(it) return it.name end)
		else
			local max_params = 0
			for j = 1, #fn.overloads do
				fn_overloads[j] = fn.overloads[j]
				max_params = math.max(max_params, #fn.overloads[j].parameters)
			end
			for j = 1, max_params do
				fn_param_names[j] = '_p' .. j
			end
			table.sort(fn_overloads, function(a, b) return #a.parameters < #b.parameters end)
		end

		wrapper = wrapper:gsub('${WF_FUNCTION_NAME}', fn.name)
		wrapper = wrapper:gsub('${WF_FUNCTION_PREFIX}', fn.is_method and ':' or '')
		wrapper = wrapper:gsub('${WF_METHOD_STR}', fn.is_method and ':' or '.')
		wrapper = wrapper:gsub('${WF_FN_PARAMS}', table.concat(fn_param_names, ','))
		wrapper = wrapper:gsub('${WF_PRE_HOOK}', fn_pre_hooks[fn_hook] or '')
		wrapper = wrapper:gsub('${WF_POST_HOOK}', fn_post_hooks[fn_hook] or '')
		wrapper = wrapper:gsub('${WF_FN_SELF}',
			fn.is_method and (#fn_param_names > 0 and 'self, ' or 'self') or '')
		wrapper = wrapper:gsub('${WF_PS_N}', function()
			return table.concat(map_list(fn_param_names, function() return '%s' end), ', ')
		end)
		wrapper = wrapper:gsub('${WF_FMT_PARAMS}', table.concat(map_list(fn_param_names,
			function(it) return ',fmtobject(' .. it .. ')' end)))

		wrapper = wrapper:gsub('${WF_OVERLOADS}', function()
			local fn_all_param_names = map_list(fn_param_names)

			if fn.is_method then
				table.insert(fn_all_param_names, 1, 'self')
			end

			if #fn.overloads == 1 then
				local parameters = map_list(fn.overloads[1].parameters)
				if fn.is_method then
					table.insert(parameters, 1, { name = 'self', type = type.name })
				end
				local params = generate_overload_params(fn_all_param_names, parameters, fn_hook, logged)
				return params:gsub('\n', '\n\t')
			else
				local s = ''
				for j = 1, #fn_overloads do
					local parameters = map_list(fn_overloads[j].parameters)
					if fn.is_method then
						table.insert(parameters, 1, { name = 'self', type = type.name })
					end
					s = s .. (j < #fn_overloads
					      and 'if ' .. fn_param_names[#parameters + 1] .. '== nil then\n\t\t'
					       or '\n\t\t')
					local params = generate_overload_params(fn_all_param_names, parameters, fn_hook, logged)

					s = s .. params:gsub('\n', '\n\t\t') .. '\n'
					      .. (j < #fn_overloads and '\n\telse' or '\n\tend\n')
				end
				return s
			end
		end)

		local return_type = fn.overloads[1].returns
		if is_class(return_type) and v3d_types[return_type].kind == 'class' then
			local label_param = 'nil'
			for j = 1, #fn.overloads[1].parameters do
				if fn.overloads[1].parameters[j].name == 'label' then
					label_param = 'label'
				end
			end
			local convert_instance = 'convert_instance_' .. return_type .. '(return_value, ' .. label_param .. ')'
			wrapper = wrapper:gsub('${WF_RETURN_CONVERT}', convert_instance)
		else
			wrapper = wrapper:gsub('${WF_RETURN_CONVERT}', '-- no conversion necessary')
		end

		if is_class(return_type) then
			wrapper = wrapper:gsub('${WF_RETURN_DETAILS}', 'show_details_' .. return_type .. '(return_value, return_tree.children)')
		elseif return_type == 'nil' or not logged then
			wrapper = wrapper:gsub('${WF_RETURN_DETAILS}', '-- no details')
		else
			error('Unhandled function return type: ' .. return_type)
		end

		return wrapper
	end

	--- @param type Type
	--- @return string
	local function generate_converter(type)
		local function_overrides = {}
		local operator_overrides = {}

		for i = 1, #type.functions do
			local fn = type.functions[i]
			local logged = not fn_logging_blacklist[type.name .. '.' .. fn.name]
			local fn_text = generate_wrapped_function(type, fn, logged)
			table.insert(function_overrides, (fn_text:gsub('\n', '\n\t')))
		end

		for i = 1, #type.operators do
			local op = type.operators[i]
			local fn = meta_aliases[type.name .. '.' .. op.operator]

			if not fn then
				error('Missing operator alias for ' .. type.name .. '.' .. op.operator)
			end

			table.insert(operator_overrides, '__' .. op.operator .. ' = instance.' .. fn)
		end

		local instance_metatable = ''

		if #operator_overrides > 0 then
			instance_metatable = 'setmetatable(instance, {\n\t\t'
			                  .. table.concat(operator_overrides, ',\n\t\t')
			                  .. '\n\t})'
		end

		return (CONVERT_INSTANCE_TEMPLATE
			:gsub('%${INSTANCE_TYPE_NAME}', type.name)
			:gsub('%${INSTANCE_FUNCTION_OVERRIDES}', function()
				return table.concat(function_overrides, '\n\t')
			end)
			:gsub('%${INSTANCE_METATABLE}', instance_metatable))
	end

	--- @param field NameType
	--- @return string
	local function generate_field_details(field)
		local sub_details = ''
		local field_type, field_is_optional = get_v3d_type(field.type)

		if is_class(field_type) then
			sub_details = 'show_details_' .. field_type
			           .. '(instance.' .. field.name .. ', '
			           .. 'field_' .. field.name .. '_tree.children)'

			if field_is_optional then
				sub_details = 'if instance.' .. field.name .. ' then '
				           .. sub_details .. ' end'
			end
		end

		return (SHOW_DETAILS_FIELD_TEMPLATE
			:gsub('${SDF_FIELD_NAME}', field.name)
			:gsub('${SDF_SUB_DETAILS}', sub_details)
			:gsub('\n', '\n\t'))
	end

	--- @param type Type
	--- @return string
	local function generate_details_stub(type)
		return (SHOW_DETAILS_STUB_TEMPLATE
			:gsub('%${INSTANCE_TYPE_NAME}', type.name))
	end

	--- @param type Type
	--- @return string
	local function generate_details(type)
		local instance_fields = {}

		for i = 1, #type.fields do
			if not field_detail_blacklist[type.name .. '.' .. type.fields[i].name] then
				local field_text = generate_field_details(type.fields[i])
				table.insert(instance_fields, (field_text:gsub('\n', '\n\t')))
			end
		end

		return (SHOW_DETAILS_TEMPLATE
			:gsub('%${INSTANCE_TYPE_NAME}', type.name)
			:gsub('%${INSTANCE_FIELDS}', function()
				return table.concat(instance_fields, '\n\t\t')
			end)
			:gsub('%${EXTRA_FIELDS}', function()
				return (extra_details_fields[type.name] or ''):gsub('\n', '\n\t\t')
			end))
	end

	local wrapper_tokens
	do
		local generated_content = {}

		for i = 1, #v3d_types do
			if is_class(v3d_types[i].name) then
				table.insert(generated_content, generate_details_stub(v3d_types[i]))
			end
		end

		for i = 1, #v3d_types do
			if is_class(v3d_types[i].name) then
				table.insert(generated_content, generate_details(v3d_types[i]))
			end
		end

		for i = 1, #v3d_types do
			if is_class(v3d_types[i].name) and v3d_types[i].kind == 'class' then
				table.insert(generated_content, generate_converter(v3d_types[i]))
			end
		end

		wrapper_tokens = luatools.tokenise(table.concat(generated_content, '\n'))
	end

	local statistics_tokens = {}
	do
		local generated_content = {}
		local statistics_fields = v3d_types.V3DStatistics.fields

		for i = 1, #statistics_fields do
			table.insert(generated_content, 'v3d_state.statistics.' .. statistics_fields[i].name .. ' = 0')
			table.insert(generated_content, 'v3d_state.statistics[' .. i .. '] = "' .. statistics_fields[i].name .. '"')
		end

		statistics_tokens = luatools.tokenise(table.concat(generated_content, '\n'))
	end

	local tokens = luatools.tokenise(v3dd_text)

	-- replace GENERATE_WRAPPER marker with wrapper tokens
	for i = 1, #tokens do
		if tokens[i].text:find '--%s*#marker%s+GENERATE_WRAPPER' then
			for j = 1, #wrapper_tokens do
				table.insert(tokens, i + j, wrapper_tokens[j])
			end
		elseif tokens[i].text:find '--%s*#marker%s+INIT_STATISTICS' then
			for j = 1, #statistics_tokens do
				table.insert(tokens, i + j, statistics_tokens[j])
			end
		end
	end

	local pre_minify_len = #luatools.concat(tokens)

	if not no_minify then
		luatools.strip_comments(tokens)
		luatools.strip_doccomments(tokens)
		luatools.strip_whitespace(tokens)
		luatools.minify(tokens)
	end

	local header_text = '-- ' .. license_text:gsub('\n', '\n-- ') .. '\n'
	                 .. '---@diagnostic disable:duplicate-doc-field,duplicate-set-field,duplicate-doc-alias\n'
	local content = header_text .. luatools.concat(tokens)

	local OUTPUT_PATH = gen_path .. 'v3dd.lua'
	local h = assert(io.open(OUTPUT_PATH, 'w'))
	h:write(content)
	h:close()

	assert(load(content, 'v3dd.lua'))

	term.setTextColour(colours.lightGrey)
	term.write('Compiled v3dd to ')
	term.setTextColour(colours.cyan)
	print(OUTPUT_PATH)
	term.setTextColour(colours.lightGrey)
	print(string.format('  minification: %d / %d (%d%%)', #content, pre_minify_len, #content / pre_minify_len * 100 + 0.5))
	term.setTextColour(colours.white)
end

if false then -- produce compiled v3d.d.ts
	local header_text = '// ' .. license_text:gsub('\n', '\n// ') .. '\n'
	                 .. 'type integer = number;\n'
	local content = header_text

	local type_mappings = {
		['fun(data: any[]): any[]'] = '(data: any[]) => any[]'
	}

	local alias_mappings = {
		V3DUniforms = {
			expected = '{ [string]: unknown }',
			replace_with = '{ [name: string]: unknown }',
		},
		V3DUnpackedFragmentShader = {
			expected = 'fun(...: unknown): integer | nil',
			replace_with = '(...uniform_attr_values: unknown[]) => integer | null',
		},
		V3DPackedFragmentShader = {
			expected = 'fun(uniforms: V3DUniforms, attr_values: { [string]: unknown[] }): integer | nil',
			replace_with = '(uniforms: V3DUniforms, attr_values: { [name: string]: unknown[] }) => integer | null',
		},
	}

	local function type_to_ts(type)
		type = type_mappings[type] or type
		type = type:gsub('(|?%s*)nil$', '%1null')
		return type
	end

	local function type_annotation(type)
		local infix = ': '
		type = type_to_ts(type)
		if type:find '|%s*null$' then
			infix = '?: '
		end
		return infix .. type
	end

	--- @param fn Function
	local function function_to_ts(fn, prefix)
		local result = ''

		for i = 1, #fn.overloads do
			if i ~= 1 then
				result = result .. '\n'
			end

			local ov = fn.overloads[i]
			local needs_comma = false

			result = result .. '/** ' .. fn.docstring .. ' */\n'
			result = result .. prefix .. fn.name .. '('

			if fn.is_method then
				result = result .. 'this: void'
				needs_comma = true
			end

			for j = 1, #ov.parameters do
				local param = ov.parameters[j]
				if needs_comma then
					result = result .. ', '
				end
				result = result .. param.name .. type_annotation(param.type)
				needs_comma = true
			end

			result = result .. '): ' .. type_to_ts(ov.returns)
		end

		return result
	end

	for i = 1, #v3d_library_type.fields do
		local field = v3d_library_type.fields[i]
		content = content .. '/** ' .. field.docstring .. '*/\n'
		content = content .. 'export const ' .. field.name .. ': ' .. type_to_ts(field.type) .. '\n'
	end

	for i = 1, #v3d_library_type.functions do
		local fn = v3d_library_type.functions[i]
		content = content .. function_to_ts(fn, 'export declare function ') .. '\n'
	end

	for i = 1, #v3d_types do
		if v3d_types[i] ~= v3d_library_type then
			content = content .. '/** ' .. v3d_types[i].docstring .. '*/\n'

			if v3d_types[i].kind == 'alias' then
				assert(#v3d_types[i].fields == 0)
				assert(#v3d_types[i].functions == 0)
				assert(#v3d_types[i].operators == 0)
				local alias_type = v3d_types[i].extends

				if alias_mappings[v3d_types[i].name] then
					assert(alias_mappings[v3d_types[i].name].expected == alias_type, 'Expected alias of ' .. alias_mappings[v3d_types[i].name].expected .. ' for ' .. v3d_types[i].name .. ' doesn\'t match ' .. alias_type)
					alias_type = alias_mappings[v3d_types[i].name].replace_with
				else
					alias_type = type_to_ts(alias_type)
				end

				content = content .. 'export type ' .. v3d_types[i].name
				                  .. ' = ' .. alias_type .. ';\n'
			else
				content = content .. 'export class ' .. v3d_types[i].name

				if v3d_types[i].extends then
					content = content .. ' extends ' .. type_to_ts(v3d_types[i].extends)
				end

				content = content .. ' {'

				for j = 1, #v3d_types[i].fields do
					local field = v3d_types[i].fields[j]
					content = content .. '\n\t/** ' .. field.docstring:gsub('\n', '\n\t') .. ' */'
					content = content .. '\n\t' .. field.name .. type_annotation(field.type)
				end

				for j = 1, #v3d_types[i].functions do
					local fn = v3d_types[i].functions[j]
					content = content .. '\n\t' .. function_to_ts(fn, ''):gsub('\n', '\n\t')
				end

				content = content .. '\n}\n'
			end
		end
	end

	local OUTPUT_PATH = gen_path .. 'v3d.d.ts'
	local h = assert(io.open(OUTPUT_PATH, 'w'))
	h:write(content)
	h:close()

	term.setTextColour(colours.lightGrey)
	term.write('Compiled typescript declarations to ')
	term.setTextColour(colours.cyan)
	print(OUTPUT_PATH)
	term.setTextColour(colours.white)
end

do -- produce compiled v3d modules
	local header_text = '-- ' .. license_text:gsub('\n', '\n-- ') .. '\n'
	.. '---@diagnostic disable:duplicate-doc-field,duplicate-set-field,duplicate-doc-alias,duplicate-doc-field,need-check-nil\n'
	local content = ''
	local insertion_fringe = {}
	local ordered_modules = {}

	for k, v in pairs(modules) do
		if k == 'core' then
			v = v:gsub('%s*return%s+v3d%s*$', '\n', 1)
		end
		local insertion = { k, v }
		for i = 1, #module_dependencies[k] do
			insertion[i + 2] = module_dependencies[k][i]
		end
		table.insert(insertion_fringe, insertion)
		table.insert(ordered_modules, k)
	end

	table.sort(ordered_modules)
	table.sort(insertion_fringe, function (a, b) return a[1] < b[1] end)

	while insertion_fringe[1] do
		local changed = false

		for i = #insertion_fringe, 1, -1 do
			if #insertion_fringe[i] == 2 then
				local module_data = table.remove(insertion_fringe, i)
				local module_name = module_data[1]

				content = content .. 'local __modules_' .. module_name .. '\n'
				content = content .. module_data[2]
				changed = true

				for j = 1, #insertion_fringe do
					for k = #insertion_fringe[j], 3, -1 do
						if insertion_fringe[j][k] == module_name then
							table.remove(insertion_fringe[j], k)
							break
						end
					end
				end
			end
		end

		if not changed then
			for i = 1, #insertion_fringe do
				print(insertion_fringe[i][1], table.concat(insertion_fringe[i], ', ', 3))
			end
			error('Cyclic dependency between modules :(')
		end
	end

	content = content .. 'local v3d = {}\n'

	for i = 1, #ordered_modules do
		local module_name = ordered_modules[i]
		if module_name:sub(1, 1) == '_' then
			content = content .. 'for k, v in pairs(__modules_' .. module_name .. ') do\n'
			                  .. '\tv3d[k] = v\n'
			                  .. 'end\n'
		else
			content = content .. 'v3d.' .. module_name .. ' = __modules_' .. module_name .. '\n'
		end
	end

	content = content .. 'return v3d\n'

	local pre_minify_len = #header_text + #content
	local content_tokens = luatools.tokenise(content)

	if not no_minify then
		luatools.strip_comments(content_tokens)
		luatools.strip_whitespace(content_tokens)
		luatools.minify(content_tokens)
	end

	content = header_text .. luatools.concat(content_tokens)
	content = content:gsub('---%s*@cast.-\n', '')
	content = content:gsub('\n%s*\n', '\n')

	local OUTPUT_PATH = gen_path .. 'v3dtest.lua'
	local h = assert(io.open(OUTPUT_PATH, 'w'))
	h:write(content)
	h:close()

	assert(load(content, 'v3d.lua'))

	term.setTextColour(colours.lightGrey)
	term.write('Compiled library code to ')
	term.setTextColour(colours.cyan)
	print(OUTPUT_PATH)
	term.setTextColour(colours.lightGrey)
	print(string.format('  minification: %d / %d (%d%%)', #content, pre_minify_len, #content / pre_minify_len * 100 + 0.5))
	term.setTextColour(colours.white)
end

do -- copy files to root
	fs.delete('/v3d.lua')
	fs.copy(gen_path .. 'v3d.lua', '/v3d.lua')

	fs.delete('/v3dd.lua')
	fs.copy(gen_path .. 'v3dd.lua', '/v3dd.lua')
end
