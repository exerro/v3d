
local a = require 'v3dtest'

local function _parse_parameters(s)
	local params = {}
	local i = 1
	local start = 1
	local in_string = nil

	while i <= #s do
		local char = s:sub(i, i)

		if (char == '\'' or char == '"') and not in_string then
			in_string = char
			i = i + 1
		elseif char == in_string then
			in_string = nil
			i = i + 1
		elseif char == '\\' then
			i = i + (in_string and 2 or 1)
		elseif in_string then
			i = select(2, assert(s:find('[^\\\'"]+', i))) + 1
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
		params[i] = params[i]:gsub('^%s+', '', 1):gsub('%s+$', '', 1)
	end

	return params
end

--- @param macros { [string]: string | fun (context: table, local_context: table, append_line: fun (line: string), parameters: string[]) }
--- @param context { [string]: any }
--- @param content string
local function _rewrite_vfsl(macros, context, content)
	local changed
	local table_insert = table.insert
	local local_contexts = {}

	repeat
		changed = false
		content = ('\n' .. content):gsub('(\n[ \t]*)([^\n]-[^_])(v3d_[%w_]+)(%b())', function(w, c, f, p)
			local params = _parse_parameters(p:sub(2, -2))
			local result = {}

			if c:find '%-%-' then
				return w .. c .. f .. p
			end

			local replace = macros[f]

			if not replace then
				return w .. c .. f .. p
			end

			if not c:find "[^ \t]" then
				w = w .. c
				c = ''
			end

			if type(replace) == 'function' then
				local local_context = local_contexts[f]
				if not local_context then
					local_context = {}
					local_contexts[f] = local_context
				end

				replace(context, local_context, function(line) table_insert(result, line) end, params)
			elseif #params == 0 then
				result[1] = replace
			else
				error('Tried to pass parameters to a string replacement')
			end

			changed = true

			return w .. c .. table.concat(result, w)
		end):sub(2)
	until not changed

	return content
end

print(_rewrite_vfsl(
	{
		v3d_my_function = function(context, local_context, append_line, params)
			if not local_context.flag then
				append_line('first_invocation!')
				local_context.flag = true
			end
			append_line(params[1] .. ' ' .. context.variable)
		end,
	},
	{
		variable = 'context_variable'
	},
	[[
		v3d_my_function('abc')
		v3d_my_function('def')
		v3d_my_function('hij')
	]]
))
