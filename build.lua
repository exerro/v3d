
local function tokenise(source)
	local i = 1
	local tokens = {}

	while i <= #source do
		local whitespace_end = select(2, source:find('^%s+', i))
		local word_end = whitespace_end or select(2, source:find('^[%w_]+', i))
		local multiline_comment = word_end or source:match('^%-%-%[(=*)%[', i)
		local comment_end = multiline_comment or select(2, source:find('^%-%-[^\n]*\n', i))
		local string_char = comment_end or source:match('^[\'"]', i)
		local multiline_string = string_char or source:match('^%[(=*)%[', i)
		if whitespace_end then
			local has_newline = source:sub(i, whitespace_end):find '\n'
			table.insert(tokens, {
				type = has_newline and 'newline' or 'whitespace',
				text = has_newline and '\n' or ' ',
			})
			i = whitespace_end + 1
		elseif word_end then
			table.insert(tokens, {
				type = 'word',
				text = source:sub(i, word_end)
			})
			i = word_end + 1
		elseif multiline_comment then
			local _, comment_end = source:find('%]' .. ('='):rep(#multiline_comment) .. '%]', i)
			i = comment_end + 1
		elseif comment_end then
			local comment = source:sub(i, comment_end)
			if comment:sub(1, 4) == '--- ' then
				table.insert(tokens, {
					type = 'comment',
					text = '---' .. comment:sub(5)
				})
			elseif comment:sub(1, 10) == '-- #marker' then
				table.insert(tokens, {
					type = 'comment',
					text = comment
				})
			end
			i = comment_end + 1
		elseif string_char then
			local i0 = i
			i = i + 1
			while i <= #source do
				local ch = source:sub(i, i)
				if ch == string_char then
					i = i + 1
					break
				elseif ch == '\\' then
					i = i + 2
				else
					i = i + #source:match('^[^' .. string_char .. '\\]+', i)
				end
			end
			table.insert(tokens, {
				type = 'string',
				text = source:sub(i0, i - 1)
			})
		elseif multiline_string then
			local _, string_end = source:find('%]' .. ('='):rep(#multiline_string) .. '%]', i)
			table.insert(tokens, {
				type = 'string',
				text = source:sub(i, string_end):gsub('\n%s+', '\n')
			})
			i = string_end + 1
		else
			local _, symbol_end = source:find('^[^%s%w_"\']+', i)
			table.insert(tokens, {
				type = 'symbol',
				text = source:sub(i, symbol_end)
			})
			i = symbol_end + 1
		end
	end

	return tokens
end

local function strip_whitespace(tokens)
	for i = #tokens - 1, 2, -1 do
		if tokens[i].type == 'whitespace' and (tokens[i - 1].type ~= 'word' or tokens[i + 1].type ~= 'word') then
			table.remove(tokens, i)
		elseif tokens[i].type == 'newline' and (tokens[i - 1].text:sub(-1) == ',' or tokens[i - 1].text:sub(-1) == '(') then
			table.remove(tokens, i)
		elseif tokens[i].type == 'newline' and (tokens[i + 1].text:sub(1, 1) == ')') then
			table.remove(tokens, i)
		end
		if i % 10000 == 0 then
			sleep(0)
		end
	end

	while tokens[1] and tokens[1].type == 'whitespace' do
		table.remove(tokens, 1)
	end

	while tokens[#tokens] and tokens[#tokens].type == 'whitespace' do
		table.remove(tokens, #tokens)
	end

	return tokens
end

local all_characters = {}
local first_characters = {}

do
	for i = 0, 9 do
		table.insert(all_characters, string.char(string.byte '0' + i))
	end

	for i = 0, 25 do
		table.insert(first_characters, string.char(string.byte 'A' + i))
		table.insert(all_characters, string.char(string.byte 'A' + i))
	end

	for i = 0, 25 do
		table.insert(first_characters, string.char(string.byte 'a' + i))
		table.insert(all_characters, string.char(string.byte 'a' + i))
	end
end

local function index_of(v, t)
	for i = 1, #t do
		if t[i] == v then
			return i
		end
	end
	return nil
end

local function next_variable_name(v)
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

local function rename_shorter(tokens)
	local scopes = {}
	local scope = { ['$next'] = first_characters[1] }

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
		if tokens[i].type == 'word' then
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

				if rename_parameters and tokens[i] and tokens[i].text ~= '()' then
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

				local prev_symbol_is_dot = prev_symbol and prev_symbol:sub(#prev_symbol) == '.' and prev_symbol:sub(#prev_symbol - 1) ~= '..'

				local is_rewritable = not prev_symbol_is_dot and
				                      (not prev_symbol or not next_symbol or prev_symbol:sub(#prev_symbol) ~= '{' or next_symbol:sub(1, 1) ~= '=')

				if is_rewritable and scope[tokens[i].text] then
					tokens[i].text = scope[tokens[i].text]
				end

				i = i + 1
			end
		else
			i = i + 1
		end
	end

	return tokens
end

local function reconstruct(tokens)
	local s = {}

	for i = 1, #tokens do
		s[i] = tokens[i].text
	end

	return table.concat(s)
end

--------------------------------------------------------------------------------

local path = shell and (shell.getRunningProgram():match '.+/' or '') or 'v3d/'
local section = {}

for line in io.lines(path .. 'src/v3d.lua') do
	table.insert(section, line)
end

for line in io.lines(path .. 'src/implementation.lua') do
	table.insert(section, line)
end

local blocks = {}

local removing = false

for i = 1, #section do
	removing = removing and not section[i]:find '%s*%-%-%s*#end%s*$'
	local should_remove = removing
	removing = removing or section[i]:find '%s*%-%-%s*#remove%s*$'
	if should_remove then
		section[i] = ''
	end
end
table.insert(blocks, table.concat(section, '\n'))

sleep(0)

local content = table.concat(blocks, '\n')
local len = #content
local content_tokens = tokenise(content)
sleep(0)
local whitespace_free = strip_whitespace(content_tokens)
sleep(0)
content = reconstruct(rename_shorter(whitespace_free)):gsub('\n\n+', '\n')

print(string.format('Minified length: %d / %d (%d%%)', #content, len, #content / len * 100 + 0.5))

local license_text = ''
for line in io.lines(path .. 'LICENSE') do
	if line ~= '' then line = ' ' .. line end
	license_text = license_text .. '--' .. line .. '\n'
end

local h = assert(io.open(path .. 'build/v3d.lua', 'w'))
h:write(license_text)
h:write '---@diagnostic disable: duplicate-doc-field, duplicate-set-field, duplicate-doc-alias'
h:write(content)
h:close()

fs.delete('/v3d.lua')
fs.copy(path .. 'build/v3d.lua', '/v3d.lua')
