
local v3d_internal = require '_internal'

local v3d_text = {}

--------------------------------------------------------------------------------
--[[ v3d.text.TemplateContext ]]------------------------------------------------
--------------------------------------------------------------------------------

do
	--- TODO
	--- @alias v3d.text.TemplateContext { [string]: any }
end

--------------------------------------------------------------------------------
--[[ v3d.text.quote ]]----------------------------------------------------------
--------------------------------------------------------------------------------

do
	--- Return the text, quoted in apostrophes and escaped as required.
	--- @param text string
	--- @return string
	--- @nodiscard
	function v3d_text.quote(text)
		return '\'' .. (text:gsub('[\\\'\n\t]', { ['\\'] = '\\\\', ['\''] = '\\\'', ['\n'] = '\\n', ['\t'] = '\\t' })) .. '\''
	end
end

--------------------------------------------------------------------------------
--[[ v3d.text.unquote ]]--------------------------------------------------------
--------------------------------------------------------------------------------

do
	--- Return the text, quoted in apostrophes and escaped as required.
	--- @param text string
	--- @return string
	--- @nodiscard
	function v3d_text.unquote(text)
		-- TODO: should handle escape sequences
		return (text:gsub('^[\'"]', '', 1):gsub('[\'"]$', '', 1))
	end
end

--------------------------------------------------------------------------------
--[[ v3d.text.trim ]]--------------------------------------------------------
--------------------------------------------------------------------------------

do
	--- TODO
	--- @param text string
	--- @return string
	--- @nodiscard
	function v3d_text.trim(text)
		return (text:gsub('^%s+', '', 1):gsub('%s+$', '', 1))
	end
end

--------------------------------------------------------------------------------
--[[ v3d.text.unindent ]]-------------------------------------------------------
--------------------------------------------------------------------------------

do
	--- Strips common leading whitespace from all lines.
	--- @param text string
	--- @return string
	--- @nodiscard
	function v3d_text.unindent(text)
		text = text:gsub('%s+$', '')

		local lines = {}
		local min_line_length = math.huge
		local matching_indentation_length = 0

		for line in text:gmatch '[^\n]+' do
			if line:find '%S' then
				line = line:match '^%s*'
				table.insert(lines, line)
				min_line_length = math.min(min_line_length, #line)
			end
		end

		if lines[1] then
			for i = 1, min_line_length do
				local c = lines[1]:sub(i, i)
				local ok = true
				for j = 2, #lines do
					if lines[j]:sub(i, i) ~= c then
						ok = false
						break
					end
				end
				if not ok then
					break
				end
				matching_indentation_length = i
			end

			text = text
				:gsub('^' .. lines[1]:sub(1, matching_indentation_length), '')
				:gsub('\n' .. lines[1]:sub(1, matching_indentation_length), '\n')
		end

		return text
	end
end

--------------------------------------------------------------------------------
--[[ v3d.text.generate_template ]]----------------------------------------------
--------------------------------------------------------------------------------

do
	local function _xpcall_handler(...)
		return debug.traceback(...)
	end

	--- Generate a string from a template.
	--- The template string allows you to embed special sections that impact the
	--- result, for example embedding variables or executing code.
	---
	--- There are 3 phases to computing the result: the template text, the
	--- generator, and the result text.
	---
	--- ---
	---
	--- The template text is what you pass in to the function. `{! !}` sections
	--- allow you to modify the template text directly and recursively. The
	--- contents of the section are executed, and the return value of that is
	--- used as a replacement for the section.
	---
	--- For example, with a template string `{! 'hello {% world %}' !}`, after
	--- processing the first section, the template would be `hello {% %}` going
	--- forwards.
	---
	--- Code within `{! !}` sections must be "complete", i.e. a valid Lua block
	--- with an optional `return` placed at the start implicitly.
	---
	--- ---
	---
	--- Templates are ultimately used to build a "generator", which is code that
	--- writes the result text for you. `{% %}` sections allow you to modify the
	--- generator text directly. The contents of the section are appended
	--- directly to the generator (rather than being wrapped in a string)
	--- allowing your templates to execute arbitrary code whilst being
	--- evaluated.
	---
	--- For example, with a template string
	--- `{% for i = 1, 3 do %}hello{% end %}` we would see a result of
	--- "hellohellohello".
	---
	--- As indicated, code within `{% %}` sections need not be "complete", i.e.
	--- Lua code can be distributed across multiple sections as long as it is
	--- valid once the generator has been assembled.
	---
	--- ---
	---
	--- Additionally, we can write text directly to the result with `{= =}`
	--- sections. The contents of the section are evaluated in the generator and
	--- appended to the result text after being passed to `tostring`.
	---
	--- For example, with a template string `{= my_variable =}` and a context
	--- where `my_variable` was set to the string 'hello', we would see a result
	--- of "hello".
	---
	--- For another example, with a template string
	--- `{= my_variable:gsub('e', 'E') =}` and the same context, we would see a
	--- result of "hEllo".
	---
	--- Code within `{= =}` sections should be a valid Lua expression, for
	--- example a variable name, function call, table access, etc.
	---
	--- ---
	---
	--- Finally, we can include comments in the template with `{# #}` sections.
	--- These are ignored and not included with the output text.
	---
	--- For example, with a template string `hello {# world #}` we would see a
	--- result of "hello ".
	---
	--- ---
	---
	--- Context is a table passed in as the environment to sections. Any values
	--- are permitted in this table, and will be available as global variables
	--- within all code-based sections (not comments, duh).
	--- @param template string String text to generate result text from.
	--- @param context v3d.text.TemplateContext Variables and functions available in the scope of sections in the template.
	--- @return string
	--- @nodiscard
	function v3d_text.generate_template(template, context)
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

		env.quote = v3d_text.quote

		for k, v in pairs(context) do
			env[k] = v
		end

		template = template:gsub('%${([^}]+)}', '{= %1 =}')

		local write_content = {}

		write_content[1] = 'local _text_segments = {}'
		write_content[2] = 'local _table_insert = table.insert'

		while true do
			local s, f, indent, text, operator = ('\n' .. template):find('\n([\t ]*)([^\n{]*){([%%=#!])')
			if s then
				local close = template:find( (operator == '%' and '%' or '') .. operator .. '}', f)
				           or error('Missing end to \'{' .. operator .. '\': expected a matching \'' .. operator .. '}\'', 2)

				local pre_text = template:sub(1, s - 1 + #indent + #text)
				local content = template:sub(f + 1, close - 1):gsub('^%s+', ''):gsub('%s+$', '')

				if (operator == '%' or operator == '#') and not text:find '%S' then -- I'm desperately trying to remove newlines and it's not working
					pre_text = template:sub(1, s - 1)
				end

				if #pre_text > 0 then
					table.insert(write_content, '_table_insert(_text_segments, ' .. v3d_text.quote(pre_text) .. ')')
				end

				template = template:sub(close + 2)

				if (operator == '%' or operator == '#') and not template:sub(1, 1) == '\n' then -- I'm desperately trying to remove newlines and it's not working
					template = template:sub(2)
				end

				if operator == '=' then
					table.insert(write_content, '_table_insert(_text_segments, tostring(' .. content .. '))')
				elseif operator == '%' then
					table.insert(write_content, content)
				elseif operator == '!' then
					local fn, err = load('return ' .. content, content, nil, env)
					if not fn then fn, err = load(content, content, nil, env) end
					if not fn then v3d_internal.contextual_error('Invalid {!!} section (syntax): ' .. err .. '\n    ' .. content, content) end
					local ok, result = xpcall(fn, _xpcall_handler)
					if ok and type(result) == 'function' then
						ok, result = pcall(result)
					end
					if not ok then v3d_internal.contextual_error('Invalid {!!} section (runtime):\n' .. result, content) end
					if type(result) == 'function' then
						ok, result = pcall(result)
						if not ok then v3d_internal.contextual_error('Invalid {!!} section (runtime):\n' .. result, content) end
					end
					if type(result) ~= 'string' then
						v3d_internal.contextual_error('Invalid {!!} section (return): not a string (got ' .. type(result) .. ')\n' .. content, content)
					end
					template = result:gsub('%${([^}]+)}', '{= %1 =}'):gsub('\n', '\n' .. indent) .. template
				elseif operator == '#' then
					-- do nothing, it's a comment
				end
			else
				table.insert(write_content, '_table_insert(_text_segments, ' .. v3d_text.quote(template) .. ')')
				break
			end
		end

		table.insert(write_content, 'return table.concat(_text_segments)')

		local code = table.concat(write_content, '\n')
		local f, err = load(code, 'template string', nil, env)
		if not f then v3d_internal.contextual_error('Invalid template builder (syntax): ' .. err, code) end
		local ok, result = xpcall(f, _xpcall_handler)
		if not ok then v3d_internal.contextual_error('Invalid template builder section (runtime):\n' .. result, code) end

		return result
	end
end

return v3d_text
