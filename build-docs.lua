
-- TODO: parse [[@ref]] in docstrings

local path = shell and (shell.getRunningProgram():match '.+/' or '') or 'v3d/'
local sections = {}
local section = nil

for line in io.lines(path .. 'src/library.lua') do
	if line:find '%-%-%- @diagnostic' then
		-- do nothing
	elseif line:find '^%s*%-%-%- ' or line:find '^%s*%-%-%-$' then
		if not section then
			section = {}
			table.insert(sections, section)
		end
		table.insert(section, line)
	elseif section then
		table.insert(section, line)
		section = nil
	end
end

for i = 1, #sections do
	for j = 1, #sections[i] do
		sections[i][j] = sections[i][j]:gsub('^%s*%-%-%- *', '')
	end
end

--------------------------------------------------------------------------------

--- @class NameType
--- @field name string
--- @field type string
--- @field docstring string

--- @class Function
--- @field method_syntax boolean
--- @field name string
--- @field docstring string
--- @field parameters NameType[]
--- @field returns string

--- @class Class
--- @field name string
--- @field extends string | nil
--- @field docstring string
--- @field fields NameType[]
--- @field methods Function[]

--- @type { [integer]: string, [string]: Class }
local classes = {}

local function get_class(name)
	if classes[name] then
		return classes[name]
	end

	local c = { name = name, docstring = '', fields = {}, methods = {} }
	classes[name] = c
	table.insert(classes, name)
	return c
end

local function register_class(section)
	local docstring = {}

	while section[1] do
		if section[1]:sub(1, 6) == '@class' then
			break
		else
			table.insert(docstring, table.remove(section, 1))
		end
	end

	if section[1]:sub(1, 6) ~= '@class' then
		error('Expected @class in section, got ' .. tostring(section[1]))
	end

	local class_name, class_extends = table.remove(section, 1):match '^@class ([%w_]+)(:?.*)$'
	local class = get_class(class_name)

	class.docstring = table.concat(docstring, '\n')

	if #class_extends > 0 then
		class.extends = class_extends:gsub(':%s*', '', 1)
	end

	local field_docstring = {}

	while section[1] do
		if section[1]:sub(1, 6) == '@field' then
			local field_name, field_type = table.remove(section, 1):match '@field%s+([%w_]+) (.+)$'
			table.insert(class.fields, {
				name = field_name,
				type = field_type,
				docstring = table.concat(field_docstring, '\n')
			})
			field_docstring = {}
		else
			table.insert(field_docstring, table.remove(section, 1))
		end
	end

	if #field_docstring > 0 then
		error('Unexpected overflow field docstring for class \'' .. class.name .. '\'')
	end
end

local function register_function(section, parent_class, method_like, function_name)
	local function_docstring = {}

	while section[1] do
		if section[1]:sub(1, 1) == '@' then
			break
		end

		table.insert(function_docstring, table.remove(section, 1))
	end

	local class = get_class(parent_class)
	--- @type Function
	local m = {}
	m.method_syntax = method_like
	m.name = function_name
	m.docstring = table.concat(function_docstring, '\n')
	m.parameters = {}
	m.returns = 'nil'

	while section[1] and section[1]:sub(1, 6) == '@param' do
		local name, rest = table.remove(section, 1):match '^@param%s+([%w_]+)%s+(.+)$'
		local counter = 0
		local type_parts = {}

		for part in rest:gmatch '[^ ]+' do
			if part == '|' then
				counter = counter - 1
			else
				counter = counter + 1
			end

			if counter < 2 then
				table.insert(type_parts, part)
			else
				break
			end
		end

		local type = table.concat(type_parts, ' ')
		local docstring = rest:sub(#type + 2)

		table.insert(m.parameters, {
			name = name,
			type = type,
			docstring = docstring,
		})
	end

	if section[1] and section[1]:sub(1, 7) == '@return' then
		m.returns = section[1]:sub(9)
		table.remove(section, 1)
	else
		term.setTextColour(colours.yellow)
		print('Function ' .. function_name .. ' is missing a return type!')
		term.setTextColour(colours.white)
	end

	assert(#section == 0, 'Leftover section for function \'' .. function_name .. '\': ' .. tostring(section[1]))

	table.insert(class.methods, m)
end

local function register_alias(section)
	local name, values = table.remove(section, #section):match '^@alias ([%w_]+)%s+(.+)$'

	local a = get_class(name)

	a.docstring = ''

	while section[1] and section[1]:sub(1, 4) ~= '@see' do
		a.docstring = a.docstring .. table.remove(section, 1) .. '\n'
	end

	a.docstring = a.docstring .. '\nAliases to:\n\n```\n' .. values .. '\n```'

	local see = {}

	while section[1] and section[1]:sub(1, 4) == '@see' do
		table.insert(see, table.remove(section, 1):sub(6))
	end

	assert(#section == 0)

	if #see > 0 then
		a.docstring = a.docstring .. '\n\nSee also: '
	end

	for i = 1, #see do
		if i ~= 1 then
			a.docstring = a.docstring .. ', '
		end

		a.docstring = a.docstring .. '[`' .. see[i] .. '`](#' .. see[i]:gsub('[^%w_]+', ''):lower() .. ')'
	end
end

for _, section in ipairs(sections) do
	if section[#section]:sub(1, 6) == 'local ' then
		table.remove(section, #section)
		register_class(section)
	elseif section[#section]:sub(1, 9) == 'function ' then
		local line = table.remove(section, #section)
		local parent_class, method_like, function_name = line:match 'function ([%w_]+)([:%.])([%w_]+)'
		register_function(section, parent_class, method_like == ':', function_name)
	elseif section[#section] == '' then
		table.remove(section, #section)
		register_alias(section)
	else
		error('Unknown section type for section\n' .. table.concat(section, '\n'))
	end
end

--------------------------------------------------------------------------------

local function type_to_markdown(s)
	return (s:gsub('[%w_][^ ]*', function(ss)
		if classes[ss] then
			return '[`' .. ss .. '`](#' .. ss:lower() .. ')'
		else
			return '`' .. ss .. '`'
		end
	end))
end

local function docstring_to_markdown(s)
	return (s:gsub('%[%[@([%w_%.]+)%]%]', function(ss)
		return '[`' .. ss .. '`](#' .. ss:gsub('[^%w_]', ''):lower() .. ')'
	end))
end

local OUTPUT_PATH = 'v3d/build/docs.md'
local h = assert(io.open(OUTPUT_PATH, 'w'))

h:write '\n# Index\n\n'

for i = 1, #classes do
	local class = classes[classes[i]]
	h:write '* [`'
	h:write(class.name)
	h:write '`](#'
	h:write(class.name:lower())
	h:write ')\n'

	for j = 1, #class.fields do
		h:write '  * [`'
		h:write(class.name)
		h:write '.'
		h:write(class.fields[j].name)
		h:write('`](#')
		h:write(class.name:lower())
		h:write(class.fields[j].name:lower())
		h:write ')\n'
	end

	for j = 1, #class.methods do
		h:write '  * [`'
		h:write(class.name)
		h:write(class.methods[j].method_syntax and ':' or '.')
		h:write(class.methods[j].name)
		h:write('()`](#')
		h:write(class.name:lower())
		h:write(class.methods[j].name:lower())
		h:write ')\n'
	end
end

h:write '\n'

for i = 1, #classes do
	local class = classes[classes[i]]

	h:write '---\n\n# `'
	h:write(class.name)
	h:write '`\n\n'

	if class.extends then
		h:write '## Extends `'
		h:write(class.extends)
		h:write '`\n\n'
	end

	h:write(docstring_to_markdown(class.docstring))
	h:write '\n\n'

	for j = 1, #class.fields do
		h:write '### `'
		h:write(class.name)
		h:write '.'
		h:write(class.fields[j].name)
		h:write '`\n\n'

		h:write '#### (type) '
		h:write(type_to_markdown(class.fields[j].type))
		h:write '\n\n'

		if class.fields[j].docstring ~= '' then
			h:write(docstring_to_markdown(class.fields[j].docstring))
			h:write '\n\n'
		end
	end

	for j = 1, #class.methods do
		h:write '## `'
		h:write(class.name)
		h:write(class.methods[j].method_syntax and ':' or '.')
		h:write(class.methods[j].name)
		h:write '()`\n\n'

		if class.methods[j].docstring ~= '' then
			h:write(docstring_to_markdown(class.methods[j].docstring))
			h:write '\n\n'
		end

		h:write '```lua\nfunction '
		h:write(class.name)
		h:write(class.methods[j].method_syntax and ':' or '.')
		h:write(class.methods[j].name)
		h:write '('

		for k = 1, #class.methods[j].parameters do
			if k ~= 1 then
				h:write ', '
			end
			h:write(class.methods[j].parameters[k].name)
		end

		h:write '): '
		h:write(class.methods[j].returns)

		h:write '\n```\n\n'

		for k = 1, #class.methods[j].parameters do
			h:write '#### (parameter) `'
			h:write(class.methods[j].parameters[k].name)
			h:write '` :  '
			h:write(type_to_markdown(class.methods[j].parameters[k].type))
			h:write '\n\n'

			if class.methods[j].parameters[k].docstring ~= '' then
				h:write(docstring_to_markdown(class.methods[j].parameters[k].docstring))
				h:write '\n\n'
			end
		end

		h:write '#### (returns) '
		h:write(type_to_markdown(class.methods[j].returns))
		h:write '\n\n'
	end
end

h:close()

term.write 'Wrote documentation to '
term.setTextColour(colours.cyan)
print(OUTPUT_PATH)
term.setTextColour(colours.white)
