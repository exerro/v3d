
local docstring = require 'docstring'
local gen = require 'gen'

--- @param docstring string
local function short_docstring(docstring)
	return (docstring:match('^%s*(.-)[%.]') or docstring):gsub('\n\n.*$', '')
end

local function function_sorter(a, b)
	return (not a.is_advanced and b.is_advanced) or (a.is_advanced == b.is_advanced and a.name < b.name)
end
local function method_sorter(a, b)
	return (not a.is_advanced and b.is_advanced) or (a.is_advanced == b.is_advanced and a.method_name < b.method_name)
end

--- @param type DocstringType
--- @param types string[] | nil
--- @return string[]
local function find_v3d_types(type, types)
	types = types or {}

	if type.kind == 'union' then
		for i = 1, #type.types do
			find_v3d_types(type.types[i], types)
		end
	elseif type.kind == 'map' then
		find_v3d_types(type.key_type, types)
		find_v3d_types(type.value_type, types)
	elseif type.kind == 'list' then
		find_v3d_types(type.type, types)
	elseif type.kind == 'ref' then
		table.insert(types, type.name)
	end

	return types
end

--- @param values string[]
--- @return string[]
local function to_set(values)
	local seen = {}
	local set = {}

	for i = 1, #values do
		if not seen[values[i]] then
			seen[values[i]] = true
			table.insert(set, values[i])
		end
	end

	table.sort(set)

	return set
end

local embedgen = {}

function embedgen.annotate_snippet(snippet_name, snippet_content)
	local frontmatter_fields = {
		{ key = 'type', value = 'snippet' },
		{ key = 'snippet', value = snippet_name },
	}

	if snippet_content:find '^%s*%-%-%-' then
		local existing_frontmatter = snippet_content:match('^%s*%-%-%-(.-)%-%-%-')
		for line in existing_frontmatter:gmatch '[^\n]+' do
			local key, value = line:match '^%s*(.-)%s*:%s*(.*)%s*$'
			if key ~= nil and value ~= nil then
				table.insert(frontmatter_fields, { key = key, value = value })
			else
				error('invalid frontmatter line in ' .. snippet_name .. ': ' .. line)
			end
		end
	end

	snippet_content = snippet_content:gsub('^%s*%-%-%-.-\n%-%-%-', '')

	local frontmatter_text = '---\n'
	for _, frontmatter_field in ipairs(frontmatter_fields) do
		frontmatter_text = frontmatter_text .. frontmatter_field.key .. ': ' .. frontmatter_field.value .. '\n'
	end

	return frontmatter_text .. '---' .. snippet_content
end

--- @param alias DocstringAlias
--- @return string
function embedgen.generate_alias_embedded_documentation(alias)
	local generator = gen.generator()

	generator:writeLine('---')
	generator:writeLine('type: alias')
	generator:writeLine('name: %s', alias.name)
	generator:writeLine('---')

	generator:writeLine('Name: %s', alias.name)
	generator:writeLine('Alias for: %s', alias.alias)
	generator:writeLine()
	generator:writeLine(alias.docstring)
	generator:writeLine()

	if #alias.validations > 0 then
		generator:writeLine('Constraints:')

		for i = 1, #alias.validations do
			generator:writeLine('* %s', alias.validations[i].message)
		end

		generator:writeLine()
	end

	return generator:build()
end

--- @param class DocstringClass
--- @return string
function embedgen.generate_class_embedded_documentation(class, classes)
	local generator = gen.generator()

	generator:writeLine('---')
	generator:writeLine('type: class')
	generator:writeLine('name: %s', class.name)
	generator:writeLine('---')

	generator:writeLine('# %s', class.name)
	generator:writeLine()

	if class.extends ~= nil then
		generator:writeLine('Extends: %s', class.extends)
		generator:writeLine()
	end

	generator:writeLine(class.docstring)
	generator:writeLine('Instances are %stracked in v3debug.', class.instances_tracked and '' or 'not ')
	generator:writeLine('Instances are %s.',
		class.is_structural and 'Lua tables containing all the fields below'
	                         or 'created with constructor functions within the library')

	if #class.subclasses > 0 then
		generator:writeLine()
		generator:writeLine('## Subtypes')
		for i = 1, #class.subclasses do
			generator:writeLine('* %s', class.subclasses[i].name)
		end
	end

	if #class.fields > 0 then
		generator:writeLine()
		generator:writeLine('## Fields', class.name)

		local focus = class
		local all_fields = {}
		while focus do
			for i = 1, #focus.fields do
				if not focus.fields[i].is_private then
					table.insert(all_fields, focus.fields[i])
				end
			end
			focus = classes[focus.extends]
		end

		table.sort(all_fields, function(a, b) return a.name < b.name end)
		for i = 1, #all_fields do
			generator:writeLine()
			generator:writeLine('### %s: %s', all_fields[i].name, all_fields[i].type)
			generator:writeLine()
			generator:writeLine(all_fields[i].docstring)
		end
	end

	if #class.validations > 0 then

		generator:writeLine()
		generator:writeLine('## Constraints')
		generator:writeLine()

		for i = 1, #class.validations do
			generator:writeLine('* %s', class.validations[i].message)
		end
	end

	return generator:build()
end

--- @param class DocstringClass
--- @return string
function embedgen.generate_class_constructor_embedded_documentation(class, all_functions)
	local generator = gen.generator()

	generator:writeLine('---')
	generator:writeLine('type: class_constructor')
	generator:writeLine('name: %s', class.name)
	generator:writeLine('---')

	generator:writeLine('# %s constructors', class.name)
	generator:writeLine()

	if class.is_abstract then
		generator:writeLine('This class is abstract and cannot be instantiated directly. Consider using a subclass:')

		for i = 1, #class.subclasses do
			generator:writeLine('* %s', class.subclasses[i])
		end

		generator:writeLine()
	end

	if class.is_structural then
		generator:writeLine('## Normal `{}` syntax')
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

	--- @type DocstringFunction[]
	local constructors = {}
	for i = 1, #all_functions do
		local fn = all_functions[i]
		if fn.return_type == class.name and fn.is_constructor then -- TODO: this is a shit check
			table.insert(constructors, fn)
		end
	end
	table.sort(constructors, function_sorter)

	for i = 1, #constructors do
		local parameters = {}

		for j = 1, #constructors[i].parameters do
			table.insert(parameters, constructors[i].parameters[j].name .. ': ' .. constructors[i].parameters[j].type)
		end

		generator:writeLine('## `%s(%s)`', constructors[i].name, table.concat(parameters, ', '))
		generator:writeLine()
		generator:writeLine(short_docstring(constructors[i].docstring))
		generator:writeLine()

		if #constructors[i].metamethods > 0 then
			for j = 1, #constructors[i].metamethods do
				generator:writeLine('* As metamethod: %s', constructors[i].metamethods[j])
			end
			generator:writeLine()
		end
	end

	return generator:build()
end

--- @param class DocstringClass
--- @return string
function embedgen.generate_class_method_embedded_documentation(class)
	local generator = gen.generator()

	generator:writeLine('---')
	generator:writeLine('type: class_methods')
	generator:writeLine('name: %s', class.name)
	generator:writeLine('---')

	generator:writeLine('# %s methods', class.name)
	generator:writeLine()

	local queued_methods = {}
	for _, fn in ipairs(class.methods) do
		table.insert(queued_methods, fn)
	end

	table.sort(queued_methods, method_sorter)

	for i = 1, #queued_methods do
		local parameters = {}
		for _, param in ipairs(queued_methods[i].parameters) do
			table.insert(parameters, param.name .. ': ' .. param.type)
		end

		generator:writeLine('## %s:%s(%s): %s',
			queued_methods[i].parameters[1].name,
			queued_methods[i].method_name, table.concat(parameters, ', ', 2),
			queued_methods[i].return_type)
		generator:writeLine()
		generator:writeLine(short_docstring(queued_methods[i].docstring))
		generator:writeLine()

		if #queued_methods[i].metamethods > 0 then
			for j = 1, #queued_methods[i].metamethods do
				generator:writeLine('* As metamethod: %s', queued_methods[i].metamethods[j])
			end
			generator:writeLine()
		end
	end

	return generator:build()
end

--- @param fn DocstringFunction
--- @return string
function embedgen.generate_function_embedded_documentation(fn)
	local generator = gen.generator()
	local parsed_return_type = docstring.parse_type(fn.return_type)
	local param_type_names = {}
	local return_type_names = find_v3d_types(parsed_return_type)

	for i = 1, #fn.parameters do
		local parsed_type = docstring.parse_type(fn.parameters[i].type)
		find_v3d_types(parsed_type, param_type_names)
	end

	generator:writeLine('---')
	generator:writeLine('type: function')
	generator:writeLine('name: %s', fn.name)
	generator:writeLine('uses: %s', table.concat(to_set(param_type_names), ', '))
	generator:writeLine('returns: %s', table.concat(to_set(return_type_names), ', '))
	generator:writeLine('---')

	generator:writeLine('Name: %s', fn.name)

	if fn.method_name ~= nil then
		generator:writeLine('As method: %s:%s(...)', fn.parameters[1].name, fn.method_name)
	end

	generator:writeLine()
	generator:writeLine(fn.docstring)
	generator:writeLine()
	generator:writeLine('Returns: %s%s', fn.return_type, fn.is_chainable and ' (' .. fn.parameters[1].name .. ')' or '')

	if #fn.parameters > 0 then
		generator:writeLine('Parameters:')

		for i = 1, #fn.parameters do
			generator:writeLine('* %s: %s', fn.parameters[i].name, fn.parameters[i].type)
		end
	end

	if #fn.validations > 0 then
		generator:writeLine()
		generator:writeLine('Constraints:')

		for i = 1, #fn.validations do
			generator:writeLine('* %s', fn.validations[i].message)
		end
	end

	-- TODO: show metamethods?

	generator:writeLine()
	generator:writeLine('Properties:')
	generator:writeLine('* Calls seen in v3debug: %s', fn.is_v3debug_logged and 'yes' or 'no')
	generator:writeLine('* Advanced usage: %s', fn.is_advanced and 'yes' or 'no')

	if #fn.example_usages > 0 then
		generator:writeLine()
		generator:writeLine('Example usage:')

		for _, example_usage in ipairs(fn.example_usages) do
			generator:writeLine('```lua')
			for line = example_usage.start_line, example_usage.end_line do
				generator:writeLine(example_usage.lines[line])
			end
			generator:writeLine('```')
		end
	end

	return generator:build()
end

return embedgen
