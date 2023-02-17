
--- @class LuaToken
--- @field type 'whitespace' | 'word' | 'doccomment' | 'comment' | 'string' | 'symbol'
--- @field text string
local LuaToken = {}

--- @type { [1]: string, [2]: string, [3]: string | nil }[]
local patterns = {
	{ 'whitespace', '^%s+' },
	{ 'word', '^[%w_]+' },
	{ 'comment', '^%-%-%-%-[^\n]*\n' },
	{ 'doccomment', '^%-%-%-[^\n]*\n' },
	{ 'comment', '^%-%-[^\n]*\n' },
	{ 'comment', '^%-%-%[(=*)%[', '%]%s%]' },
	{ 'string', '^%[(=*)%[', '%]%s%]' },
}

local opening_brackets = { ['{'] = true, ['('] = true, ['['] = true, }
local closing_brackets = { ['}'] = '{', [')'] = '(', [']'] = '[', }

--- @type fun(name: string): string
local next_variable_name
do
	local all_characters = {}
	local first_characters = {}

	do
		for i = 0, 25 do
			table.insert(first_characters, string.char(string.byte 'A' + i))
			table.insert(all_characters, string.char(string.byte 'A' + i))
		end

		for i = 0, 25 do
			table.insert(first_characters, string.char(string.byte 'a' + i))
			table.insert(all_characters, string.char(string.byte 'a' + i))
		end

		for i = 0, 9 do
			table.insert(all_characters, string.char(string.byte '0' + i))
		end

		table.insert(all_characters, '_')
	end

	local function index_of(v, t)
		for i = 1, #t do
			if t[i] == v then
				return i
			end
		end
		return nil
	end

	function next_variable_name(v)
		if v == '' then
			return first_characters[1]
		end

		if #v == 1 then
			local idx = index_of(v, first_characters)
			return idx and idx < #first_characters and first_characters[idx + 1] or first_characters[1] .. all_characters[1]
		end

		local index = index_of(v:sub(#v), all_characters)

		if index and index < #all_characters then
			return v:sub(1, -2) .. all_characters[index + 1]
		else
			return next_variable_name(v:sub(1, -2)) .. all_characters[1]
		end
	end
end

--- @class luatools
local luatools = {}

--- @param source string
--- @return LuaToken[]
function luatools.tokenise(source)
	local i = 1
	local tokens = {}

	local string_find = string.find
	local string_gsub = string.gsub
	local string_sub = string.sub
	local table_insert = table.insert

	while i <= #source do
		local found = false
		local char = string_sub(source, i, i)


		if char == '\'' or char == '"' then
			local i0 = i
			local escaped = false

			repeat
				i = i + 1
				if escaped then
					escaped = false
				else
					local str_char = string_sub(source, i, i)
					if str_char == '\\' then
						escaped = true
					elseif str_char == char then
						break
					end
				end
			until i >= #source

			table_insert(tokens, { type = 'string', text = string_sub(source, i0, i) })
			i = i + 1
			found = true
		else
			for j = 1, #patterns do
				local tp, pat, finish_pat = patterns[j][1], patterns[j][2], patterns[j][3]
				local s, f, match = string_find(source, pat, i)

				if s then
					if finish_pat then
						s, f = string_find(source, string_gsub(finish_pat, '%%s', match), f + 1)
					end

					if s then
						table_insert(tokens, { type = tp, text = string_sub(source, i, f) })
						i = f + 1
						found = true
						break
					end
				end
			end
		end

		if not found then
			table_insert(tokens, { type = 'symbol', text = string_sub(source, i, i) })
			i = i + 1
		end
	end

	return tokens
end

--- @param tokens LuaToken[]
function luatools.strip_all_whitespace(tokens)
	-- shorten whitespace to its shortest equivalent
	for i = #tokens, 1, -1 do
		if tokens[i].type == 'whitespace' then
			table.remove(tokens, i)
		end
	end
end

--- @param tokens LuaToken[]
function luatools.strip_whitespace(tokens)
	-- shorten whitespace to its shortest equivalent
	for i = #tokens, 1, -1 do
		if tokens[i].type == 'whitespace' then
			local text = tokens[i].text

			if text:find '\n' then
				tokens[i].text = '\n'
			elseif text:find ' ' then
				tokens[i].text = ' '
			else -- remove indentation
				table.remove(tokens, i)
			end
		end
	end

	-- remove unnecessary spacing between tokens
	for i = #tokens - 1, 2, -1 do
		local last_type = tokens[i - 1].type
		local this_type = tokens[i].type
		local next_type = tokens[i + 1].type

		local last_text = tokens[i - 1].text
		local this_text = tokens[i].text
		local next_text = tokens[i + 1].text

		if this_type == 'whitespace' and this_text ~= '\n' then -- space
			-- note: we only remove whitespace between words when it's not a
			--       newline since we don't want the result to be _completely_
			--       unreadable
			if last_type ~= 'word' or next_type ~= 'word' then
				table.remove(tokens, i)
			end
		elseif this_type == 'whitespace' then -- newlines
			if last_text == ',' or last_text == '(' or last_text == '{' then
				table.remove(tokens, i)
			elseif next_text == ')' or next_text == '}' then
				table.remove(tokens, i)
			end
		end
	end

	-- remove leading whitespace
	while tokens[1] and tokens[1].type == 'whitespace' do
		table.remove(tokens, 1)
	end

	-- remove trailing whitespace
	while tokens[#tokens] and tokens[#tokens].type == 'whitespace' do
		table.remove(tokens, #tokens)
	end
end

--- @param tokens LuaToken[]
function luatools.strip_comments(tokens)
	for i = #tokens, 1, -1 do
		if tokens[i].type == 'comment' then
			table.remove(tokens, i)
		end
	end
end

--- @param tokens LuaToken[]
function luatools.strip_doccomments(tokens)
	for i = #tokens, 1, -1 do
		if tokens[i].type == 'doccomment' then
			table.remove(tokens, i)
		end
	end
end

-- TODO: refactor this!
--- @param tokens LuaToken[]
function luatools.minify(tokens)
	local scopes = {}
	local scope = { ['$next'] = next_variable_name '' }
	local brackets = {}

	local function push_scope()
		table.insert(scopes, scope)
		local new_scope = {}

		for k, v in pairs(scope) do
			new_scope[k] = v
		end

		new_scope['$transient'] = nil
		scope = new_scope
	end

	local function pop_scope()
		if not scopes[#scopes] then
			error(textutils.serialize(scope))
		end
		scope = table.remove(scopes, #scopes)
		if scope['$transient'] then
			pop_scope()
		end
	end

	local i = 1

	while i <= #tokens do
		if tokens[i].type == 'symbol' then
			if opening_brackets[tokens[i].text] then
				table.insert(brackets, tokens[i].text)
			elseif closing_brackets[tokens[i].text] then
				assert(brackets[#brackets] == closing_brackets[tokens[i].text])
				table.remove(brackets, #brackets)
			end
			i = i + 1
		elseif tokens[i].type == 'word' then
			if (tokens[i].text == 'local' or tokens[i].text == 'for') and tokens[i + 2] and tokens[i + 2].text ~= 'function' then
				if tokens[i].text == 'for' then
					push_scope()
					scope['$transient'] = true
				end
				i = i + 1
				repeat
					while tokens[i + 1] and tokens[i + 1].type == 'newline' do
						i = i + 1
					end
					if tokens[i + 1].text ~= '_' then
						local varname = scope['$next']
						scope[tokens[i + 1].text] = varname
						tokens[i + 1].text = varname
						scope['$next'] = next_variable_name(varname)
					end
					i = i + 2
				until not tokens[i] or tokens[i].text ~= ','
			elseif tokens[i].text == 'function' then
				local is_local_function = tokens[i - 2] and tokens[i - 2].text == 'local'

				i = i + 1

				local rename_parameters = true

				if tokens[i] and (tokens[i].type == 'whitespace' or tokens[i].type == 'newline') then
					i = i + 1
				end

				if tokens[i] and tokens[i].type == 'word' then
					i = i + 1
					if tokens[i] and tokens[i].type == 'symbol' and (tokens[i].text == ':' or tokens[i].text == '.') then
						i = i - 1
						rename_parameters = false
					elseif is_local_function then
						local varname = scope['$next']
						scope[tokens[i - 1].text] = varname
						tokens[i - 1].text = varname
						scope['$next'] = next_variable_name(varname)
					elseif scope[tokens[i - 1].text] then
						tokens[i - 1].text = scope[tokens[i - 1].text]
					end
				end

				push_scope()

				if rename_parameters and tokens[i] then
					assert(tokens[i] and tokens[i].text == '(', tokens[i].text)
					repeat
						i = i + 1
						while tokens[i] and tokens[i].type == 'newline' do
							i = i + 1
						end
						if tokens[i] and tokens[i].type == 'word' and tokens[i].text ~= '_' then
							local varname = scope['$next']
							scope[tokens[i].text] = varname
							tokens[i].text = varname
							scope['$next'] = next_variable_name(varname)
						end
						i = i + 1
					until not tokens[i] or tokens[i].text ~= ','
				end
				if tokens[i].text == ')' then
					i = i + 1
				end
			elseif tokens[i].text == 'do' or tokens[i].text == 'then' or tokens[i].text == 'repeat' then
				push_scope()
				i = i + 1
			elseif tokens[i].text == 'end' or tokens[i].text == 'until' then
				pop_scope()
				i = i + 1
			else
				local prev_symbol = nil
				local next_symbol = nil

				if tokens[i - 1] and tokens[i - 1].type == 'symbol' then
					prev_symbol = tokens[i - 1].text
				end

				if tokens[i + 1] and tokens[i + 1].type == 'symbol' then
					next_symbol = tokens[i + 1].text
				end

				local prev_symbol_is_dot = prev_symbol and prev_symbol == '.' and (not tokens[i - 2] or tokens[i - 2].text ~= '.')

				local is_rewritable = not prev_symbol_is_dot

				if prev_symbol and next_symbol and prev_symbol == '{' and next_symbol == '=' then
					is_rewritable = false
				end

				if prev_symbol and next_symbol and prev_symbol == ',' and next_symbol == '=' and brackets[#brackets] == '{' then
					is_rewritable = false
				end

				if is_rewritable and scope[tokens[i].text] then
					tokens[i].text = scope[tokens[i].text]
				end

				i = i + 1
			end
		else
			i = i + 1
		end
	end
end

--- @param tokens LuaToken[]
--- @return string
function luatools.concat(tokens)
	local s = {}

	for i = 1, #tokens do
		s[i] = tokens[i].text
	end

	return table.concat(s)
end

return luatools
