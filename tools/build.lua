
local luatools = require 'luatools'
local docparse = require 'docparse'

local base_path = shell and (shell.getRunningProgram():match '^(.+/).-/' or '') or 'v3d/'
local src_path = base_path .. 'src/'
local gen_path = base_path .. 'gen/'
local license_text, interface_text, implementation_text

do -- read the files
	local function preprocess(text)
		return text:gsub('%-%-%s*#remove.-%-%-%s*#end', '')
	end

	local h = assert(io.open(base_path .. 'LICENSE'), 'Failed to read LICENSE')
	license_text = h:read '*a'
	h:close()

	local h = assert(io.open(src_path .. 'v3d.lua'), 'Failed to read v3d.lua')
	interface_text = h:read '*a'
	h:close()

	local h = assert(io.open(src_path .. 'implementation.lua'), 'Failed to read implementation.lua')
	implementation_text = h:read '*a'
	h:close()

	interface_text = preprocess(interface_text)
	implementation_text = preprocess(implementation_text)
end

local v3d_types = docparse.parse(interface_text)
local v3d_library_type = v3d_types['v3d']

do -- warn on missing documentation
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

do -- produce compiled v3d.lua
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

	assert(load(content))

	local OUTPUT_PATH = gen_path .. 'v3d.lua'
	local h = assert(io.open(OUTPUT_PATH, 'w'))
	h:write(content)
	h:close()

	term.setTextColour(colours.lightGrey)
	term.write('Compiled library code to ')
	term.setTextColour(colours.cyan)
	print(OUTPUT_PATH)
	term.setTextColour(colours.lightGrey)
	print(string.format('  minification: %d / %d (%d%%)', #content, pre_minify_len, #content / pre_minify_len * 100 + 0.5))
	term.setTextColour(colours.white)
end

do -- produce compiled api_reference.md
	local function type_to_markdown(s)
		return (s:gsub('[%w_][^ ]*', function(ss)
			if v3d_types[ss] then
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

		for j = 1, #class.functions do
			local method = class.functions[j]

			h:write '## `'
			h:write(class.name)
			h:write(method.is_method and ':' or '.')
			h:write(method.name)
			h:write '()`\n\n'

			if method.docstring ~= '' then
				h:write(docstring_to_markdown(method.docstring))
				h:write '\n\n'
			end

			for k = 1, #method.overloads do
				local overload = method.overloads[k]

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

				for l = 1, #overload.parameters do
					h:write '#### (parameter) `'
					h:write(overload.parameters[l].name)
					h:write '` :  '
					h:write(type_to_markdown(overload.parameters[l].type))
					h:write '\n\n'

					if overload.parameters[l].docstring ~= '' then
						h:write(docstring_to_markdown(overload.parameters[l].docstring))
						h:write '\n\n'
					end
				end

				h:write '#### (returns) '
				h:write(type_to_markdown(overload.returns))
				h:write '\n\n'
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

do -- copy files to root
	fs.delete('/v3d.lua')
	fs.copy(gen_path .. 'v3d.lua', '/v3d.lua')
end
