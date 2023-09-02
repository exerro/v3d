
local docstring = {}

--- @alias DocstringMarkup string

--- @class DocstringAlias
--- @field name string
--- @field alias string
--- @field docstring DocstringMarkup
--- @field validations { message: string | nil, check_code: string }[]

--- @class DocstringClass
--- @field name string
--- @field extends string | nil
--- @field fields DocstringClassField[]
--- @field subclasses DocstringClass[]
--- @field methods DocstringFunction[]
--- @field docstring DocstringMarkup
--- @field instances_tracked boolean
--- @field is_abstract boolean
--- @field is_structural boolean
--- @field validations { message: string | nil, check_code: string }[]

--- @class DocstringFunction
--- @field line_defined integer
--- @field name string
--- @field method_name string | nil
--- @field parameters DocstringFunctionParameter[]
--- @field return_type string
--- @field docstring DocstringMarkup
--- @field metamethods string[]
--- @field is_advanced boolean
--- @field is_constructor boolean
--- @field is_generated boolean
--- @field is_v3debug_logged boolean
--- @field is_chainable boolean
--- @field example_usages DocstringFunctionExampleUsage[]
--- @field validations { message: string | nil, check_code: string }[]

----------------------------------------------------------------

--- @class DocstringClassField
--- @field name string
--- @field type string
--- @field is_private boolean
--- @field docstring DocstringMarkup

--- @class DocstringFunctionParameter
--- @field name string
--- @field type string

--- @class DocstringFunctionExampleUsage
--- @field lines string[]
--- @field start_line integer
--- @field end_line integer

----------------------------------------------------------------

--- @class Docstring
--- @field aliases { [string]: DocstringAlias, [integer]: DocstringAlias }
--- @field classes { [string]: DocstringClass, [integer]: DocstringClass }
--- @field functions { [string]: DocstringFunction, [integer]: DocstringFunction }

----------------------------------------------------------------

local lua_types = {
	['string'] = true,
	['number'] = true,
	['integer'] = true,
	['boolean'] = true,
	['table'] = true,
	['function'] = true,
}

local lua_constants = {
	['nil'] = true,
	['true'] = true,
	['false'] = true,
}

local handled_alias_annotations = {
	['alias'] = true,
	['v3d-validate'] = true,
}

local handled_class_annotations = {
	['class'] = true,
	['field'] = true,
	['v3d-abstract'] = true,
	['v3d-untracked'] = true,
	['v3d-structural'] = true,
	['v3d-validate'] = true,
}

local handled_function_annotations = {
	['generic'] = true,
	['param'] = true,
	['return'] = true,
	['v3d-generated'] = true,
	['v3d-nolog'] = true,
	['v3d-mt'] = true,
	['v3d-nomethod'] = true,
	['v3d-chainable'] = true,
	['v3d-validate'] = true,
	['v3d-constructor'] = true,
	['v3d-example'] = true,
	['v3d-advanced'] = true,
}

----------------------------------------------------------------

--- @class DocstringWarning
--- @field type 'trailing-annotation-context'
---           | 'unexpected-annotation-context'
---           | 'unknown-entity-type'
---           | 'duplicate-annotation'
---           | 'trailing-suffix'
---           | 'missing-docstring'
---           | 'missing-return-type'
---           | 'unused-annotation'
---           | 'unexpected-validations'
---           | 'missing-constructor-annotation'
---           | 'missing-example-usage'
---           | 'missing-validation-message' ...
--- @field line number
--- @field message string

--------------------------------------------------------------------------------

--- @alias DocstringType
---      | { kind: 'union', types: DocstringType[] }
---      | { kind: 'map', key_type: DocstringType, value_type: DocstringType }
---      | { kind: 'list', type: DocstringType }
---      | { kind: 'lua-builtin', name: string }
---      | { kind: 'constant', value: string }
---      | { kind: 'ref', name: string }
---      | { kind: 'any' }

--- @param type_str string
--- @return DocstringType
function docstring.parse_type(type_str)
	type_str = type_str:gsub('^%s+', ''):gsub('%s+$', '')

	if type_str:sub(1, 1) == '{' then
		assert(type_str:match '%b{}' == type_str, type_str)
		local key_type, value_type = type_str:match '{%s*%[%s*(.-)%s*%]%s*:%s*(.-)%s*}'
		assert(key_type, type_str)
		return { kind = 'map', key_type = docstring.parse_type(key_type), value_type = docstring.parse_type(value_type) }
	else
		local union_parts = {}
		for part in type_str:gmatch '[^|]+' do
			table.insert(union_parts, part)
		end
		if #union_parts > 1 then
			local types = {}
			for i = 1, #union_parts do
				table.insert(types, docstring.parse_type(union_parts[i]))
			end
			for i = 1, #types do
				if types[i].kind == 'any' then
					return types[i]
				end
			end
			return { kind = 'union', types = types }
		elseif union_parts[1] == 'any' then
			return { kind = 'any' }
		elseif union_parts[1]:sub(1, 1) == '\'' or union_parts[1]:sub(1, 1) == '"' or lua_constants[union_parts[1]] or union_parts[1]:find '^%d+$' then
			return { kind = 'constant', value = union_parts[1] }
		else
			local ref = union_parts[1]:match '^[^%[%]]+'
			local type
			if ref:sub(1, 1) == '`' then
				type = { kind = 'lua-builtin', name = 'string' }
			elseif lua_types[ref] then
				type = { kind = 'lua-builtin', name = ref }
			else
				type = { kind = 'ref', name = ref }
			end
			for _ in union_parts[1]:gmatch '%[%]' do
				type = { kind = 'list', type = type }
			end
			return type
		end
	end
end

--------------------------------------------------------------------------------

--- @class _Annotation
--- @field starting_line number
--- @field annotation string
--- @field payload string
--- @field context string[]

--- @class _AnnotatedEntity
--- @field starting_line number
--- @field suffix_line number
--- @field suffix string
--- @field annotations _Annotation[]
--- @field trailing_context string[]
local _AnnotatedEntity = {}

--- @param annotation string
--- @return _Annotation[]
function _AnnotatedEntity:find_annotations(annotation)
	local annotations = {}

	for i = 1, #self.annotations do
		if self.annotations[i].annotation == annotation then
			table.insert(annotations, self.annotations[i])
		end
	end

	return annotations
end

--- @param annotation string
--- @return _Annotation
function _AnnotatedEntity:find_annotation(annotation)
	return self:find_annotations(annotation)[1]
end

--- @param annotation string
--- @return boolean
function _AnnotatedEntity:has_annotation(annotation)
	for i = 1, #self.annotations do
		if self.annotations[i].annotation == annotation then
			return true
		end
	end

	return false
end

--------------------------------------------------------------------------------

--- @param content string
--- @return string[]
local function content_to_lines(content)
	local lines = {}

	local i = 1
	local f = content:find '\n'
	while f do
		table.insert(lines, (content:sub(i, f - 1):gsub('\r$', '')))
		i = f + 1
		f = content:find('\n', i)
	end
	table.insert(lines, content:sub(i))

	return lines
end

--- @param lines string[]
--- @return { [integer]: string, starting_line: integer, suffix: string | nil }[]
local function lines_to_groups(lines)
	local groups = {}
	local group

	for i = 1, #lines do
		local is_docstring = lines[i]:find '^%s*%-%-%-%s' or lines[i]:find '^%s*%-%-%-$'

		if lines[i]:find '^%s*%-%-%-%s*@diagnostic' then
			is_docstring = nil
		end

		if is_docstring then
			if group then
				if lines[i]:find '^%s*%-%-%-%s*|' then
					group[#group] = group[#group] .. ' | ' .. lines[i]:gsub('^%s*%-%-%-%s*|%s*', '')
				else
					table.insert(group, #group + 1, lines[i])
				end
			else
				group = {
					lines[i],
					starting_line = i,
					suffix = nil,
				}
				table.insert(groups, group)
			end
		elseif group then
			group.suffix = lines[i]
			group = nil
		end
	end

	return groups
end

--- @param groups { [integer]: string, starting_line: integer, suffix: string | nil }[]
local function filter_groups(groups)
	for i = #groups, 1, -1 do
		local group = groups[i]
		local is_class = false
		local is_alias = false

		for i = 1, #group do
			if group[i]:find '^%s*%-%-%-%s*@class' then
				is_class = true
				break
			elseif group[i]:find '^%s*%-%-%-%s*@alias' then
				is_alias = true
				break
			end
		end

		if not is_class and not is_alias then
			if not group.suffix or group.suffix:find '^%s*local%s' or group.suffix:find 'function%s*_' then
				table.remove(groups, i)
			end
		end
	end
end

local blacklisted_annotations = {
	['see'] = true,
}
--- @param groups { [integer]: string, starting_line: integer, suffix: string | nil }[]
--- @return _AnnotatedEntity[]
local function parse_groups(groups)
	local entities = {}

	for i = 1, #groups do
		local group = groups[i]
		local entity = {
			starting_line = group.starting_line,
			suffix_line = group.starting_line + #group,
			suffix = group.suffix or '',
			annotations = {},
			trailing_context = {},
		}

		for k, v in pairs(_AnnotatedEntity) do
			entity[k] = v
		end

		for j = 1, #group do
			local line = group[j]
			local annotation, payload = line:match '^%s*%-%-%-%s*@(%S+)%s*(.*)$'

			if annotation and not blacklisted_annotations[annotation] then
				table.insert(entity.annotations, {
					starting_line = group.starting_line + j - 1,
					annotation = annotation,
					payload = payload,
					context = entity.trailing_context,
				})
				entity.trailing_context = {}
			else
				table.insert(entity.trailing_context, (line:gsub('^%s*%-%-%-%s?', '')))
			end
		end

		table.insert(entities, entity)
	end

	return entities
end

----------------------------------------------------------------

--- @param annotation _Annotation | nil
--- @param warnings DocstringWarning[]
local function warn_unexpected_context(annotation, warnings)
	if not annotation then
		return
	end

	if #annotation.context > 0 then
		table.insert(warnings, {
			type = 'unexpected-annotation-context',
			line = annotation.starting_line,
			message = 'A \'@' .. annotation.annotation .. '\' annotation was found with unexpected context.',
		})
	end
end

--- @param entity _AnnotatedEntity
local function find_validations(entity, warnings)
	local annotations = entity:find_annotations 'v3d-validate'
	local validations = {}

	for i = 1, #annotations do
		local annotation = annotations[i]

		if #annotation.context == 0 then
			table.insert(warnings, {
				type = 'missing-validation-message',
				line = annotation.starting_line,
				message = 'A validation was found without a message.',
			})
		end

		table.insert(validations, {
			message = #annotation.context > 0 and table.concat(annotation.context, '\n') or annotation.payload,
			check_code = annotation.payload,
		})
	end

	return validations
end

--- @param entity _AnnotatedEntity
--- @param warnings DocstringWarning[]
local function warn_no_trailing_context(entity, warnings)
	if #entity.trailing_context > 0 then
		table.insert(warnings, {
			type = 'trailing-annotation-context',
			line = entity.starting_line + #entity,
			message = 'Entity has trailing annotation context.',
		})
	end
end

----------------------------------------------------------------

--- @param entity _AnnotatedEntity
--- @param warnings DocstringWarning[]
--- @return DocstringAlias | nil
local function parse_alias(entity, warnings)
	local alias_annotation = entity:find_annotation 'alias'
	local name, aliased_type = alias_annotation.payload:match '^%s*(%S+)%s+(.+)%s*$'

	if name:sub(1, 1) == '_' then
		return nil
	end

	local alias = {
		name = name,
		alias = aliased_type,
		docstring = table.concat(alias_annotation.context, '\n'),
		validations = find_validations(entity, warnings),
	}

	if #alias_annotation.context == 0 then
		table.insert(warnings, {
			type = 'missing-docstring',
			line = alias_annotation.starting_line,
			message = 'An alias was found without a docstring.',
		})
	end

	if entity.suffix ~= '' then
		table.insert(warnings, {
			type = 'trailing-suffix',
			line = entity.suffix_line,
			message = 'An alias was found without a docstring.',
		})
	end

	for _, annotation in ipairs(entity.annotations) do
		if not handled_alias_annotations[annotation.annotation] then
			table.insert(warnings, {
				type = 'unused-annotation',
				line = annotation.starting_line,
				message = 'An alias was found with an unknown annotation \'' .. annotation.annotation .. '\'.',
			})
		end
	end

	return alias
end

--- @param entity _AnnotatedEntity
--- @param warnings DocstringWarning[]
--- @return DocstringClass | nil
local function parse_class(entity, warnings)
	local class_annotation = entity:find_annotation 'class'
	local name, extends = class_annotation.payload:match '^%s*(%S+):%s*(%S*)%s*$'

	if not name then
		name = class_annotation.payload:match '^%s*(%S+)%s*$'
		extends = nil
	end

	if name:sub(1, 1) == '_' then
		return nil
	end

	local class = {
		name = name,
		extends = extends,
		fields = {},
		subclasses = {},
		methods = {},
		docstring = table.concat(class_annotation.context, '\n'),
		instances_tracked = not entity:has_annotation 'v3d-untracked'
		                and not entity:has_annotation 'v3d-structural'
		                and not entity:has_annotation 'v3d-abstract',
		is_abstract = entity:has_annotation 'v3d-abstract',
		is_structural = entity:has_annotation 'v3d-structural',
		validations = find_validations(entity, warnings),
	}

	if #class.validations > 0 and not class.is_structural then
		table.insert(warnings, {
			type = 'unexpected-validations',
			line = class_annotation.starting_line,
			message = 'A class \'' .. class.name .. '\' was found with validations but is not structural.',
		})
	end

	warn_unexpected_context(entity:find_annotation 'v3d-untracked', warnings)

	if #class_annotation.context == 0 then
		table.insert(warnings, {
			type = 'missing-docstring',
			line = class_annotation.starting_line,
			message = 'A class was found without a docstring.',
		})
	end

	if entity.suffix ~= '' and class_annotation.payload ~= 'V3D' then
		table.insert(warnings, {
			type = 'trailing-suffix',
			line = entity.suffix_line,
			message = 'A class \'' .. class_annotation.payload .. '\' was found with a trailing suffix.',
		})
	end

	for _, annotation in ipairs(entity:find_annotations 'field') do
		local is_private = true
		local name, type = annotation.payload:match '^%s*private%s*(%S+)%s+(.+)%s*$'

		if not name then
			is_private = false
			name, type = annotation.payload:match '^%s*(%S+)%s+(.+)%s*$'
		end

		table.insert(class.fields, {
			name = name,
			type = type,
			is_private = is_private,
			docstring = table.concat(annotation.context, '\n'),
		})

		if #annotation.context == 0 and not is_private then
			table.insert(warnings, {
				type = 'missing-docstring',
				line = annotation.starting_line,
				message = 'A class field was found without a docstring.',
			})
		end
	end

	for _, annotation in ipairs(entity.annotations) do
		if not handled_class_annotations[annotation.annotation] then
			table.insert(warnings, {
				type = 'unused-annotation',
				line = annotation.starting_line,
				message = 'A class was found with an unknown annotation \'' .. annotation.annotation .. '\'.',
			})
		end
	end

	return class
end

--- @param entity _AnnotatedEntity
--- @param warnings DocstringWarning[]
--- @return DocstringFunction
local function parse_function(entity, warnings)
	local fn_docstring_context = #entity.annotations > 0
		and entity.annotations[1].context
		or entity.trailing_context

	if #entity.annotations > 0 then
		warn_no_trailing_context(entity, warnings)
	end

	local fn = {
		line_defined = entity.suffix_line,
		name = entity.suffix:match 'function%s+(%S+)%s*%(',
		method_name = nil, -- assigned later
		parameters = {}, -- assigned later
		return_type = '', -- assigned later
		docstring = table.concat(fn_docstring_context, '\n'),
		metamethods = {}, -- assigned later
		is_advanced = entity:has_annotation 'v3d-advanced',
		is_constructor = entity:has_annotation 'v3d-constructor',
		is_generated = entity:has_annotation 'v3d-generated',
		is_v3debug_logged = not entity:has_annotation 'v3d-nolog',
		is_chainable = entity:has_annotation 'v3d-chainable',
		validations = find_validations(entity, warnings),
		example_usages = {},
	}

	for _, annotation in ipairs(entity:find_annotations 'v3d-example') do
		local example_start_line, example_end_line = annotation.payload:match '^%s*(%d+)%s*:%s*(%d+)%s*$'

		if not example_start_line then
			example_start_line = annotation.payload:match '^%s*(%d+)%s*$'
			example_end_line = example_start_line
		end

		if not example_start_line then
			example_start_line = 1
			example_end_line = #annotation.context
		end

		if #annotation.context == 0 then
			table.insert(warnings, {
				type = 'missing-example-usage',
				line = annotation.starting_line,
				message = 'An example usage annotation was found without any code.',
			})
		end

		table.insert(fn.example_usages, {
			lines = annotation.context,
			start_line = tonumber(example_start_line),
			end_line = tonumber(example_end_line),
		})
	end

	warn_unexpected_context(entity:find_annotation 'v3d-nolog', warnings)

	if #fn_docstring_context == 0 then
		table.insert(warnings, {
			type = 'missing-docstring',
			line = entity.starting_line,
			message = 'A function was found without a docstring.',
		})
	end

	if entity:has_annotation 'return' then
		local return_annotation = entity:find_annotation 'return'

		fn.return_type = return_annotation.payload
		
		if return_annotation ~= entity.annotations[1] then
			warn_unexpected_context(return_annotation, warnings)
		end
	else
		table.insert(warnings, {
			type = 'missing-return-type',
			line = entity.starting_line,
			message = 'A function was found without a return type.',
		})
	end

	for _, annotation in ipairs(entity:find_annotations 'param') do
		local name, type = annotation.payload:match '^%s*(%S+)%s+(.+)%s*$'

		if annotation ~= entity.annotations[1] then
			warn_unexpected_context(annotation, warnings)
		end

		table.insert(fn.parameters, {
			name = name,
			type = type,
		})
	end

	for _, annotation in ipairs(entity:find_annotations 'v3d-mt') do
		warn_unexpected_context(annotation, warnings)
		table.insert(fn.metamethods, annotation.payload)
	end

	if not entity:has_annotation 'v3d-nomethod' and #fn.parameters > 0 then
		local self_type = fn.parameters[1].type

		if self_type:match '^V3D%w+$' then
			fn.method_name = fn.name
				:gsub('^.*%.', '')
				:gsub('^' .. self_type:sub(4):gsub('([a-z])([A-Z])', '%1_%2'):lower() .. '_', '')
		end
	end

	for _, annotation in ipairs(entity.annotations) do
		if not handled_function_annotations[annotation.annotation] then
			table.insert(warnings, {
				type = 'unused-annotation',
				line = annotation.starting_line,
				message = 'A function was found with an unknown annotation \'' .. annotation.annotation .. '\'.',
			})
		end
	end

	return fn
end

----------------------------------------------------------------

--- @param parameter_type string
--- @return string | nil
local function type_to_method_impl_type(parameter_type)
	local parsed = docstring.parse_type(parameter_type)
	if parsed.kind == 'ref' then
		return parsed.name
	elseif parsed.kind == 'union' then
		for _, type in ipairs(parsed.types) do
			if type.kind == 'ref' then
				return type.name
			end
		end
	end
	return nil
end

--- @param docstring Docstring
--- @param warnings DocstringWarning[]
local function complete_classes(docstring, warnings)
	for i = 1, #docstring.classes do
		local this_class = docstring.classes[i]
		local class = this_class
		while class.extends do
			table.insert(docstring.classes[class.extends].subclasses, this_class)
			class = docstring.classes[class.extends]
		end
	end

	for _, class in ipairs(docstring.classes) do
		for _, fn in ipairs(docstring.functions) do
			--- @cast fn DocstringFunction
			if fn.return_type == class.name and not fn.is_constructor then
				if #fn.parameters == 0 or fn.parameters[1].type ~= class.name then
					table.insert(warnings, {
						type = 'missing-constructor-annotation',
						line = fn.line_defined,
						message = 'A function \'' .. fn.name .. '\' seems like a constructor but isn\'t annotated as such.',
					})
				end
			end
		end
	end

	for _, class in ipairs(docstring.classes) do
		for _, fn in ipairs(docstring.functions) do
			local fn_method_type = fn.parameters[1] and type_to_method_impl_type(fn.parameters[1].type)
			if fn.method_name ~= nil and fn_method_type then
				local c = class
				while c do
					if c.name == fn_method_type then
						table.insert(class.methods, fn)
						break
					end
					c = docstring.classes[c.extends]
				end
			end
		end
	end
end

--- @param docstring Docstring
--- @param warnings DocstringWarning[]
local function complete_functions(docstring, warnings)
	for i = 1, #docstring.functions do
		if #docstring.functions[i].example_usages == 0 then
			table.insert(warnings, {
				type = 'missing-example-usage',
				line = docstring.functions[i].line_defined,
				message = 'A function \'' .. docstring.functions[i].name .. '\' was found without an example usage.',
			})
		end
	end
end

--- @param content string
--- @return Docstring, DocstringWarning[]
function docstring.parse(content)
	local warnings = {}

	local lines = content_to_lines(content)
	local groups = lines_to_groups(lines)

	filter_groups(groups)

	local entities = parse_groups(groups)

	local docstring = {
		aliases = {},
		classes = {},
		functions = {},
	}

	for i = 1, #entities do
		if entities[i]:has_annotation 'alias' then
			warn_no_trailing_context(entities[i], warnings)
			if entities[i]:has_annotation 'class' then
				table.insert(warnings, {
					type = 'duplicate-annotation',
					line = entities[i].starting_line,
					message = 'An alias cannot also be a class.',
				})
			elseif #entities[i]:find_annotations 'alias' > 1 then
				table.insert(warnings, {
					type = 'duplicate-annotation',
					line = entities[i].starting_line,
					message = 'Multiple `@alias` annotations were found.',
				})
			end
			local alias = parse_alias(entities[i], warnings)
			if alias ~= nil then
				table.insert(docstring.aliases, alias)
			end
		elseif entities[i]:has_annotation 'class' then
			warn_no_trailing_context(entities[i], warnings)
			if #entities[i]:find_annotations 'class' > 1 then
				table.insert(warnings, {
					type = 'duplicate-annotation',
					line = entities[i].starting_line,
					message = 'Multiple `@class` annotations were found.',
				})
			end
			local class = parse_class(entities[i], warnings)
			if class ~= nil then
				table.insert(docstring.classes, class)
			end
		elseif entities[i].suffix and entities[i].suffix:find 'function' then
			table.insert(docstring.functions, parse_function(entities[i], warnings))
		else
			table.insert(warnings, {
				type = 'unknown-entity-type',
				line = entities[i].starting_line,
				message = 'No known annotation was found and is not a function.',
			})
		end
	end

	for i = 1, #docstring.aliases do
		docstring.aliases[docstring.aliases[i].name] = docstring.aliases[i]
	end

	for i = 1, #docstring.classes do
		docstring.classes[docstring.classes[i].name] = docstring.classes[i]
	end

	for i = 1, #docstring.functions do
		docstring.functions[docstring.functions[i].name] = docstring.functions[i]
	end

	complete_classes(docstring, warnings)
	complete_functions(docstring, warnings)

	return docstring, warnings
end

return docstring
