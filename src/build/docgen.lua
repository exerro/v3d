
local gen = require 'gen'

--- @param alias DocstringAlias
--- @return string
local function alias_ref(alias)
	return '`' .. alias.name .. '`'
end

--- @param class DocstringClass
--- @return string
local function class_ref(class)
	return '`' .. class.name .. '`'
end

--- @param fn DocstringFunction
--- @return string
local function function_ref(fn)
	return '`' .. fn.name .. '`'
end

--- @param type string
--- @return string
local function str_type_ref(type)
	return '`' .. type .. '`'
end

--- @param docstring string
local function short_docstring(docstring)
	return docstring:match('^%s*(.-)[\n%.]')
end

local function function_sorter(a, b)
	return (not a.is_advanced and b.is_advanced) or (a.is_advanced == b.is_advanced and a.name < b.name)
end
local function method_sorter(a, b)
	return (not a.is_advanced and b.is_advanced) or (a.is_advanced == b.is_advanced and a.method_name < b.method_name)
end

--- @param generator ContentGenerator
--- @param fn DocstringFunction
--- @param method_name string | nil
--- @param compact boolean
local function generate_function_docstring_body(generator, fn, method_name, compact)
	if fn.is_advanced then
		generator:writeLine('> **This function is intended for advanced use cases.**')
		generator:writeLine()
	end

	generator:writeLine(fn.docstring)
	generator:writeLine()

	if #fn.parameters > (method_name and 1 or 0) then
		generator:writeLine('Parameter name | Type')
		generator:writeLine('-|-')

		for i = method_name and 2 or 1, #fn.parameters do
			generator:writeLine('`%s` | %s', fn.parameters[i].name, str_type_ref(fn.parameters[i].type):gsub('|', '\\|'))
		end

		generator:writeLine()
	end

	generator:writeLine('Returns %s', str_type_ref(fn.return_type))
	generator:writeLine()

	if #fn.example_usages > 0 then
		generator:writeLine('#### Example usage')
		generator:writeLine()

		for _, example_usage in ipairs(fn.example_usages) do
			generator:writeLine('```lua%s', compact and '' or ' ' .. example_usage.start_line .. ' ' .. example_usage.end_line)

			for line = compact and example_usage.start_line or 1, compact and example_usage.end_line or #example_usage.lines do
				local line_content = example_usage.lines[line]

				if method_name then
					line_content = line_content:gsub(
						fn.name:gsub('%.', '%%%.') .. '%(%s*([^,%(%)]-)%s*%)',
						'%1:' .. method_name .. '%(%)'
					):gsub(
						fn.name:gsub('%.', '%%%.') .. '%(%s*([^,]+)%s*,%s*',
						'%1:' .. method_name .. '%('
					)
				end

				generator:writeLine(line_content)
			end

			generator:writeLine('```')
			generator:writeLine()
		end
	end

	if #fn.validations > 0 then
		generator:writeLine('#### Parameter constraints')
		generator:writeLine()

		for i = 1, #fn.validations do
			generator:writeLine('* %s', fn.validations[i].message)
		end

		generator:writeLine()
	end

	generator:writeLine('#### %s properties', method_name and 'Method' or 'Function')
	generator:writeLine()

	generator:writeLine(
		'* Calls to this %s are%s visible in v3debug',
		method_name and 'method' or 'function',
		fn.is_v3debug_logged and '' or ' not')

	if fn.is_chainable then
		generator:writeLine(
			'* This %s returns `%s`',
			method_name and 'method' or 'function',
			method_name and 'self' or fn.parameters[1].name)
	end

	generator:writeLine()
end

local docgen = {}

--- @param fn DocstringFunction
--- @param compact boolean
--- @return string
function docgen.generate_function_documentation(fn, compact)
	local generator = gen.generator()

	generator:writeLine()
	generator:writeLine('# ' .. fn.name)
	generator:writeLine()

	generate_function_docstring_body(generator, fn, nil, compact)

	return generator:build()
end

--- @param alias DocstringAlias
--- @return string
function docgen.generate_alias_documentation(alias)
	local generator = gen.generator()

	generator:writeLine()
	generator:writeLine('# ' .. alias.name)
	generator:writeLine()
	generator:writeLine(alias.docstring)
	generator:writeLine()

	generator:writeLine('Alias for %s', str_type_ref(alias.alias))
	generator:writeLine()

	if #alias.validations > 0 then
		generator:writeLine('## Constraints')
		generator:writeLine()

		for i = 1, #alias.validations do
			generator:writeLine('* %s', alias.validations[i].message)
		end

		generator:writeLine()
	end

	return generator:build()
end

--- @param class DocstringClass
--- @param v3d_docstring Docstring
--- @param compact boolean
--- @return string
function docgen.generate_class_documentation(class, v3d_docstring, compact)
	local generator = gen.generator()
	local class_type = class.is_structural and 'structure' or 'class'

	generator:writeLine()
	generator:writeLine('# ' .. class.name)
	generator:writeLine()
	generator:writeLine(class.docstring)
	generator:writeLine()

	if class.extends ~= nil then
		if v3d_docstring.classes[class.extends] then
			generator:writeLine('## Extends %s', class_ref(v3d_docstring.classes[class.extends]))
		else
			generator:writeLine('## Extends %s', str_type_ref(class.extends))
		end
		generator:writeLine()
	end

	if class.is_abstract then
		generator:writeLine('This %s is abstract and cannot be instantiated directly.', class_type)
		generator:writeLine()
	end

	if class.instances_tracked then
		generator:writeLine('Instances of this %s are tracked and may be found using `v3d.instances(\'%s\')`', class_type, class.name)
		generator:writeLine()
	end

	if #class.subclasses > 0 then
		generator:writeLine('## Subtypes')
		generator:writeLine()

		for i = 1, #class.subclasses do
			generator:writeLine('* %s', class_ref(class.subclasses[i]))
		end

		generator:writeLine()
	end

	local constructors = {}
	for i = 1, #v3d_docstring.functions do
		local fn = v3d_docstring.functions[i]
		if fn.return_type == class.name and fn.is_constructor then
			table.insert(constructors, fn)
		end
	end
	table.sort(constructors, function_sorter)

	if #constructors > 0 or class.is_structural then
		generator:writeLine('## Constructors')
		generator:writeLine()

		if class.is_structural then
			generator:writeLine('### Normal `{}` syntax')
			generator:writeLine()
			generator:writeLine('```lua')
			generator:writeLine('local instance = {')
			for i = 1, #class.fields do
				generator:writeLine('\t%s = ...,', class.fields[i].name)
			end
			generator:writeLine('}')
			generator:writeLine('```')
			generator:writeLine()
		end

		for i = 1, #constructors do
			local parameter_names = {}

			for j = 1, #constructors[i].parameters do
				table.insert(parameter_names, constructors[i].parameters[j].name)
			end

			generator:writeLine('### `%s(%s)`', constructors[i].name, table.concat(parameter_names, ', '))
			generator:writeLine()
			generate_function_docstring_body(generator, constructors[i], nil, compact)
		end
	end

	local field_class = class
	local has_emitted_fields_header = false
	while field_class do
		if (#field_class.fields > 0) then
			if not has_emitted_fields_header then
				generator:writeLine('## Fields')
				generator:writeLine()
				generator:writeLine('> Fields should never be modified directly.')
				generator:writeLine()
				has_emitted_fields_header = true
			end

			for i = 1, #field_class.fields do
				if not field_class.fields[i].is_private then
					generator:writeLine('### %s`%s`: %s',
						class == field_class and '' or '(inherited) ',
						field_class.fields[i].name,
						str_type_ref(field_class.fields[i].type))
					generator:writeLine()
					generator:writeLine(field_class.fields[i].docstring)
					generator:writeLine()
				end
			end
		end

		field_class = v3d_docstring.classes[field_class.extends]
	end

	if #class.validations > 0 then
		generator:writeLine('## Constraints')
		generator:writeLine()

		for i = 1, #class.validations do
			generator:writeLine('* %s', class.validations[i].message)
		end

		generator:writeLine()
	end

	local has_metamethod = false
	if #class.methods > 0 then
		generator:writeLine('## Methods')
		generator:writeLine()

		local queued_methods = {}
		for _, fn in ipairs(class.methods) do
			table.insert(queued_methods, fn)
		end
		table.sort(queued_methods, method_sorter)

		for i = 1, #queued_methods do
			local fn = queued_methods[i]
			local parameter_names = {}

			for i = 1, #fn.parameters do
				table.insert(parameter_names, fn.parameters[i].name)
			end

			generator:writeLine('### `%s(%s)`', fn.method_name, table.concat(parameter_names, ', ', 2))
			generator:writeLine()
			generator:writeLine('> Also available as `%s(%s)`', fn.name, table.concat(parameter_names, ', '))
			generator:writeLine()

			generate_function_docstring_body(generator, fn, fn.method_name, compact)

			has_metamethod = has_metamethod or #fn.metamethods > 0
		end
	end

	if has_metamethod then
		generator:writeLine('## Operators')
		generator:writeLine()

		for _, fn in ipairs(class.methods) do
			if #fn.metamethods > 0 then
				for i = 1, #fn.metamethods do
					generator:writeLine('* `__%s` calls `%s`', fn.metamethods[i], fn.method_name)
				end
			end
		end

		generator:writeLine()
	end

	-- TODO: used by

	return generator:build()
end

return docgen
