
local vsl_parse = {}

--- @class Token
--- @field type TokenType
--- @field text string
--- @field position TokenPosition

--- @class TokenPosition
--- @field offset integer
--- @field line integer
--- @field column integer

--- @enum TokenType
local TokenType = {
	KEYWORD = "keyword",
	IDENTIFIER = "identifier",
	NUMBER = "number",
	STRING = "string",
	SYMBOL = "symbol",
	COMMENT = "comment",
}

vsl_parse.TokenType = TokenType

--- @generic T
--- @param position TokenPosition
--- @param message string
--- @return T
function vsl_parse.error_at(position, message)
	error(message .. " on line " .. position.line)
end

do -- lexer fn
	local keywords_lookup = {
		["and"] = true,
		["break"] = true,
		["do"] = true,
		["else"] = true,
		["elseif"] = true,
		["end"] = true,
		["false"] = true,
		["for"] = true,
		["function"] = true,
		["if"] = true,
		["in"] = true,
		["local"] = true,
		["nil"] = true,
		["not"] = true,
		["or"] = true,
		["repeat"] = true,
		["return"] = true,
		["then"] = true,
		["true"] = true,
		["until"] = true,
		["while"] = true,
		["struct"] = true,
	}

	local symbols_lookup = {
		["+"] = true,
		["-"] = true,
		["*"] = true,
		["/"] = true,
		["%"] = true,
		["^"] = true,
		[".."] = true,
		["#"] = true,
		["<"] = true,
		["<="] = true,
		[">"] = true,
		[">="] = true,
		["=="] = true,
		["~="] = true,
		["="] = true,
		["+="] = true,
		["-="] = true,
		["*="] = true,
		["/="] = true,
		["%="] = true,
		["^="] = true,
		["("] = true,
		[")"] = true,
		["{"] = true,
		["}"] = true,
		["["] = true,
		["]"] = true,
		[";"] = true,
		[":"] = true,
		[","] = true,
		["."] = true,
		["::"] = true,
	}

	--- @param input string
	--- @return Token[]
	function vsl_parse.lex(input)
		local tokens, i, len = {}, 1, #input
		local line, col = 1, 1

		local table_insert = table.insert
		local string_match = string.match
		local string_find = string.find
		local string_sub = string.sub
		local string_format = string.format

		local function error_here(msg)
			error(string_format("%s at line %d, column %d", msg, line, col))
		end

		while i <= len do
			local c = string_sub(input, i, i)
			if c == '\n' then
				line = line + 1
				col = 1
				i = i + 1
			elseif string_match(c, "%s") then
				i = i + 1
				col = col + 1
			elseif c == "-" and string_sub(input, i, i + 1) == "--" then
				local _, e = string_find(input, "\n", i + 2)
				line = line + 1
				col = 1
				i = (e or len) + 1
			elseif c == '"' or c == "'" then
				local finished = false
				local start_i = i
				i = i + 1
				while i <= len do
					local ch = string_sub(input, i, i)
					if ch == '\n' then
						error_here("Newline in string")
					elseif ch == "\\" then
						i = i + 1
					elseif ch == c then
						finished = true
						break
					end
					i = i + 1
				end

				if finished then
					local text = string_sub(input, start_i, i)
					local position = { offset = start_i, line = line, column = col }
					table_insert(tokens, { type = TokenType.STRING, text = text, position = position })
					i = i + 1
					col = col + (i - start_i)
				else
					error_here("Unterminated string")
				end
			elseif string_match(c, "[%a_]") then
				local text = string_match(input, "[%w_]+", i)
				local type = keywords_lookup[text] and TokenType.KEYWORD or TokenType.IDENTIFIER
				local position = { offset = i, line = line, column = col }
				table_insert(tokens, { type = type, text = text, position = position })
				i = i + #text
				col = col + #text
			elseif string_match(c, "%d") then
				local start_i = i
				local prefix = string_sub(input, i, i + 1)
				local pattern
				if prefix == "0x" or prefix == "0X" then
					pattern = "^[0-9a-fA-F]"
					i = i + 2
				elseif prefix == "0b" or prefix == "0B" then
					pattern = "^[01]"
					i = i + 2
				else
					pattern = "^[0-9%.]"
				end

				while string_match(input, pattern, i) do
					i = i + 1
				end

				local num = string_sub(input, start_i, i - 1)
				if string_find(input, "^[%a_]", i) then
					error_here("Invalid number followed by letter or _")
				else
					local position = { offset = start_i, line = line, column = col }
					table_insert(tokens, { type = TokenType.NUMBER, text = num, position = position })
					col = col + i - start_i
				end
			else
				local two = string_sub(input, i, i + 1)
				local position = { offset = i, line = line, column = col }
				local text
				if symbols_lookup[two] then
					text = two
					i = i + 2
					col = col + 2
				elseif symbols_lookup[c] then
					text = c
					i = i + 1
					col = col + 1
				end
				if text then
					table_insert(tokens, { type = TokenType.SYMBOL, text = text, position = position })
				else
					error_here("Unknown character: " .. c)
				end
			end
		end

		return tokens
	end
end

do -- parser type definitions
	--- @class ParseCtx
	--- @field tokens Token[]
	--- @field current_token_index number
	--- @field last_token Token?
	vsl_parse.ParseCtx = {}

	--- @return ParseCtx
	function vsl_parse.ParseCtx.new(tokens)
		local object = {
			tokens = tokens,
			current_token_index = 1,
			last_token = nil,
		}
		setmetatable(object, { __index = vsl_parse.ParseCtx })
		return object
	end

	--- Return whether the next token's text is `token_text`
	--- @param token_text string
	--- @return boolean
	function vsl_parse.ParseCtx:test(token_text)
		if self.current_token_index > #self.tokens then
			return false
		end
		return self.tokens[self.current_token_index].text == token_text
	end

	--- Return whether the next token's type is `token_type`
	--- @param token_type TokenType
	--- @return boolean
	function vsl_parse.ParseCtx:test_type(token_type)
		if self.current_token_index > #self.tokens then
			return false
		end
		return self.tokens[self.current_token_index].type == token_type
	end

	--- Consume the next token if its text is `token_text`. Return whether the token was consumed.
	--- @param token_text string
	--- @return boolean
	function vsl_parse.ParseCtx:consume(token_text)
		if self:test(token_text) then
			self.last_token = self.tokens[self.current_token_index]
			self.current_token_index = self.current_token_index + 1
			return true
		else
			return false
		end
	end

	--- Consume the next token if its type is `token_type`. Return whether the token was consumed.
	--- @param token_type TokenType
	--- @return boolean
	function vsl_parse.ParseCtx:consume_type(token_type)
		if self:test_type(token_type) then
			self.last_token = self.tokens[self.current_token_index]
			self.current_token_index = self.current_token_index + 1
			return true
		else
			return false
		end
	end

	--- Unconditionally move forward one token, returning the token skipped.
	--- @return Token
	function vsl_parse.ParseCtx:advance()
		self.last_token = self.tokens[self.current_token_index]
		self.current_token_index = self.current_token_index + 1
		return self.last_token
	end

	--- @param token_text string
	--- @return Token
	function vsl_parse.ParseCtx:expect(token_text)
		if self.current_token_index > #self.tokens then
			if self.last_token == nil then
				error("Unexpected end of input, expected '" .. token_text .. "'")
			else
				error("Unexpected end of input, expected '" .. token_text .. "' after '" .. self.last_token.text .. "' on line " .. self.last_token.position.line)
			end
		end

		local current_token = self.tokens[self.current_token_index]

		if current_token.text == token_text then
			self.current_token_index = self.current_token_index + 1
			self.last_token = current_token
			return current_token
		else
			error("Expected '" ..
			token_text .. "', got '" .. current_token.text .. "' on line " .. current_token.position.line)
		end
	end

	--- @param token_type TokenType
	--- @return Token
	function vsl_parse.ParseCtx:expect_type(token_type)
		if self.current_token_index > #self.tokens then
			if self.last_token == nil then
				error("Unexpected end of input, expected <" .. token_type .. ">")
			else
				error("Unexpected end of input, expected <" .. token_type .. "> after '" .. self.last_token.text .. "' on line " .. self.last_token.position.line)
			end
		end

		local current_token = self.tokens[self.current_token_index]

		if current_token.type == token_type then
			self.current_token_index = self.current_token_index + 1
			self.last_token = current_token
			return current_token
		else
			error("Expected <" ..
			token_type .. ">, got <" .. current_token.type .. "> on line " .. current_token.position.line)
		end
	end

	--- @generic T
	--- @param message string
	--- @return T
	function vsl_parse.ParseCtx:error_next(message)
		if self.current_token_index > #self.tokens then
			error(message .. ", got <end of input> on line " .. (self.last_token and self.last_token.position.line or 0))
		else
			local next_token = self.tokens[self.current_token_index]
			error(message .. ", got '" .. (next_token.text) .. "' on line " .. (next_token.position.line))
		end
	end

	--- @generic T
	--- @generic R...
	--- @param open string
	--- @param parse_inner fun(ctx: ParseCtx, R...): T
	--- @param close string
	--- @return T[]
	function vsl_parse.ParseCtx:list_of(open, parse_inner, close, ...)
		self:expect(open)
		local list = {}
		if not self:test(close) then
			repeat
				table.insert(list, parse_inner(self, ...))
			until not (self:test(",") and self:expect(",")) or self:test(close)
		end
		self:expect(close)
		return list
	end
end

return vsl_parse
