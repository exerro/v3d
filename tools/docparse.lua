
local luatools = require 'luatools'

--- @class NameType
--- @field name string
--- @field type string
--- @field docstring string

--- @class FunctionOverload
--- @field parameters NameType[]
--- @field returns string

--- @class OperatorOverload
--- @field operator string
--- @field parameters string[]
--- @field returns string

--- @class Function
--- @field is_method boolean
--- @field name string
--- @field docstring string
--- @field overloads FunctionOverload[]

--- @class Type
--- @field name string
--- @field extends string | nil
--- @field is_structural boolean
--- @field docstring string
--- @field fields NameType[]
--- @field operators OperatorOverload[]
--- @field functions Function[]

--- @alias TypeList { [integer]: Type, [string]: Type }

--- @alias AnnotatedGroup LuaToken[] | { annotations: { annotation: string, content: string, pretext: string | nil }[] }

local MISSING_DOCUMENTATION = 'Missing documentation.'

--- @param group AnnotatedGroup
--- @return Type | { codename: string }
local function parse_class(group)
	if group[1] and group[1].text == 'local' then
		assert(#group == 5)
		assert(group[1].text == 'local')
		assert(group[2].type == 'word')
		assert(group[3].text == '=')
		assert(group[4].text == '{')
		assert(group[5].text == '}')
	else
		assert(#group == 0)
	end

	local classname = group.annotations[1].content
	local docstring = group.annotations[1].pretext or MISSING_DOCUMENTATION
	local extends = nil

	if classname:find ':' then
		classname, extends = classname:match '^([%w_]+)%s*:%s*(.+)$'
	end

	--- @type Type
	local class = {
		name = classname,
		extends = extends,
		is_structural = not group[2],
		docstring = docstring,
		fields = {},
		operators = {},
		functions = {},
		codename = group[2] and group[2].text or classname,
	}

	for i = 2, #group.annotations do
		if group.annotations[i].annotation == 'field' then
			local name, type = group.annotations[i].content:match '^([%w_]+)%s+(.+)$'
			if not name then
				error('Failed to parse docstring for class \'' .. classname .. '\': ' .. group.annotations[i].content)
			end
			if name ~= 'private' then
				table.insert(class.fields, {
					name = name,
					type = type,
					docstring = group.annotations[i].pretext or MISSING_DOCUMENTATION,
				})
			end
		elseif group.annotations[i].annotation == 'operator' then
			local operator, paramstring, returns = group.annotations[i].content
				:match '^([%w_]+)%s*%(([^%)]+)%)%s*:%s*(.+)$'
			local parameters = {}

			for param in paramstring:gmatch '[^,%s]+' do
				table.insert(parameters, param)
			end

			table.insert(class.operators, {
				operator = operator,
				parameters = parameters,
				returns = returns,
			})
		else
			error('Unknown annotation for class: \'@' .. group.annotations[i].annotation .. '\'', 0)
		end
	end

	return class
end

--- @param group AnnotatedGroup
--- @return Function | { type_codename: string }
local function parse_function(group)
	assert(#group >= 6)
	assert(group[1].text == 'function')
	assert(group[2].type == 'word')
	assert(group[3].text == ':' or group[3].text == '.')
	assert(group[4].type == 'word')
	assert(group[5].text == '(')

	local fn = {
		is_method = group[3].text == ':',
		name = group[4].text,
		docstring = group.annotations[1].pretext or MISSING_DOCUMENTATION,
		overloads = {},
		type_codename = group[2].text,
	}

	--- @type { [string]: NameType }
	local params = {}
	local returns = 'nil'
	local has_overloads = false

	for i = 1, #group.annotations do
		assert(i == 1 or group.annotations[i].pretext == nil)

		if group.annotations[i].annotation == 'param' then
			local name, rest = group.annotations[i].content:match '^([%w_]+)%s+(.*)$'
			local type, docstring = rest, nil

			if rest:find '^{' then
				type, docstring = rest:match '^(%b{})%s*(.*)$'

				if not type then error('Error parsing param type for \'' .. name .. '\': ' .. rest) end
			elseif rest:find '^fun' then
				type, docstring = rest:match '^(fun%s*%b()%s*:%s*[%w_]+)%s*(.*)$'

				if not type then error('Error parsing param type for \'' .. name .. '\': ' .. rest) end
			else
				type, docstring = rest:match '^([%w_]+)%s*(.*)$'

				if not type then error('Error parsing param type for \'' .. name .. '\': ' .. rest) end

				while docstring:sub(1, 1) == '|' do
					local t, r = docstring:match '^|%s*([%w_]+)%s*(.*)$'
					if not t then error('Error parsing param type for \'' .. name .. '\': ' .. docstring) end
					type = type .. ' | ' .. t
					docstring = r
				end
			end

			while docstring:sub(1, 2) == '[]' do
				type = type .. '[]'
				docstring = docstring:gsub('^%[%]%s*', '', 1)
			end

			if docstring == '' then
				docstring = MISSING_DOCUMENTATION
			end

			params[name] = { name = name, type = type, docstring = docstring }
			table.insert(params, name)
		elseif group.annotations[i].annotation == 'return' then
			returns = group.annotations[i].content
		elseif group.annotations[i].annotation == 'overload' then
			local overload_param_string, overload_returns = group.annotations[i].content
				:match '^fun%s*%(([^%)]+)%)%s*:%s*(.+)$'
			local parameters = {}
			
			for overload_param in overload_param_string:gmatch '[^,]+' do
				local param_name, param_type = overload_param:match '^%s*([%w_]+)%s*:%s*(.+)%s*$'
				local param = params[param_name] or { name = param_name, type = param_type, docstring = '' }
				
				assert(param_type == param.type)
				table.insert(parameters, param)
			end

			table.insert(fn.overloads, {
				parameters = parameters,
				returns = overload_returns,
			})
			has_overloads = true
		elseif group.annotations[i].annotation == 'nodiscard' then
			-- TODO
		else
			error('Unknown annotation for function: \'@' .. group.annotations[i].annotation .. '\'', 0)
		end
	end

	if has_overloads then
		for i = 1, #fn.overloads do
			assert(fn.overloads[i].returns == returns)
		end
	else
		local parameters = {}
		for i = 1, #params do
			parameters[i] = params[params[i]]
		end
		table.insert(fn.overloads, {
			parameters = parameters,
			returns = returns,
		})
	end

	return fn
end

--- @param group AnnotatedGroup
--- @return Type | { codename: string }
local function parse_alias(group)
	assert(#group.annotations == 1)
	assert(#group == 0)

	local typename, extends = group.annotations[1].content:match '^([%w_]+)%s+(.+)$'
	local docstring = group.annotations[1].pretext or MISSING_DOCUMENTATION

	return {
		name = typename,
		extends = extends,
		is_structural = true,
		docstring = docstring,
		fields = {},
		operators = {},
		functions = {},
		codename = typename,
	}
end

local docparse = {}

docparse.MISSING_DOCUMENTATION = MISSING_DOCUMENTATION

--- @param source string
--- @return TypeList
function docparse.parse(source)
	local tokens = luatools.tokenise(source)
	luatools.strip_comments(tokens)
	luatools.strip_whitespace(tokens)

	--- @type AnnotatedGroup[]
	local token_groups = { {} }

	-- generate token groups from token list
	for i = 1, #tokens do
		if tokens[i].type == 'whitespace' then
			if tokens[i].text:find '\n' and #token_groups[#token_groups] > 0 then
				table.insert(token_groups, {})
			end
		else
			table.insert(token_groups[#token_groups], tokens[i])
		end
	end

	-- extract annotations from token groups
	for i = #token_groups, 1, -1 do
		local annotation_pretext = nil

		token_groups[i].annotations = {}

		while token_groups[i][1] and token_groups[i][1].type == 'doccomment' do
			local token_text = table.remove(token_groups[i], 1).text
			if token_text:find '%-%-%-%s*@%w' then
				local annotation, content = token_text:match '%-%-%-%s*@([%w_%-]+)%s*([^\n]*)\n?$'
				table.insert(token_groups[i].annotations, {
					annotation = annotation,
					content = content,
					pretext = annotation_pretext,
				})
				annotation_pretext = nil
			else
				annotation_pretext = (annotation_pretext and annotation_pretext .. '\n' or '')
				                  .. token_text:match '%-%-%-%s*([^\n]*)\n?$'
			end
		end

		if #token_groups[i].annotations == 0 then
			table.remove(token_groups, i)
		end
	end

	-- generate types and functions
	local types = {}
	local functions = {}
	for i = 1, #token_groups do
		if token_groups[i].annotations[1].annotation == 'class' then
			table.insert(types, parse_class(token_groups[i]))
		elseif token_groups[i].annotations[1].annotation == 'param' or token_groups[i].annotations[1].annotation == 'return' then
			table.insert(functions, parse_function(token_groups[i]))
		elseif token_groups[i].annotations[1].annotation == 'alias' then
			table.insert(types, parse_alias(token_groups[i]))
		elseif token_groups[i].annotations[1].annotation == 'diagnostic' then
			assert(#token_groups[i].annotations == 1)
			assert(token_groups[i].annotations[1].pretext == nil)
		else
			error('Unknown annotation \'@' .. token_groups[i].annotations[1].annotation .. '\'', 0)
		end
	end

	-- add functions to types
	local type_lookup = {}
	for i = 1, #types do
		type_lookup[types[i].codename] = types[i]
		types[types[i].name] = types[i]
	end
	for i = 1, #functions do
		local type = type_lookup[functions[i].type_codename]

		if not type then
			error('Failed to find type \'' .. functions[i].type_codename .. '\' for method \'' .. functions[i].name .. '\'')
		end

		table.insert(type.functions, functions[i])
	end

	-- replace TODO docstrings with MISSING_DOCUMENTATION constant
	for i = 1, #types do
		if types[i].docstring == 'TODO' then
			types[i].docstring = MISSING_DOCUMENTATION
		end

		for j = 1, #types[i].fields do
			if types[i].fields[j].docstring == 'TODO' then
				types[i].fields[j].docstring = MISSING_DOCUMENTATION
			end
		end

		for j = 1, #types[i].functions do
			if types[i].functions[j].docstring == 'TODO' then
				types[i].functions[j].docstring = MISSING_DOCUMENTATION
			end

			for k = 1, #types[i].functions[j].overloads do
				for l = 1, #types[i].functions[j].overloads[k].parameters do
					if types[i].functions[j].overloads[k].parameters[l].docstring == 'TODO' then
						types[i].functions[j].overloads[k].parameters[l].docstring = MISSING_DOCUMENTATION
					end
				end
			end
		end
	end

	return types
end

return docparse
