
--- @class ContentGenerator
--- @field lines string[]
--- @field indentation integer
local ContentGenerator = {}

--- @param line string | nil
--- @param ... any
--- @return ContentGenerator
function ContentGenerator:writeLine(line, ...)
	line = line or ''
	line = string.format(line, ...)
	local indent = string.rep('\t', self.indentation)
	table.insert(self.lines, indent .. line:gsub('\n', '\n' .. indent))
	return self
end

--- @param indentation integer | nil
--- @return ContentGenerator
function ContentGenerator:indent(indentation)
	self.indentation = self.indentation + (indentation or 1)
	return self
end

--- @return string
function ContentGenerator:build()
	return table.concat(self.lines, '\n')
end

local gen = {}

--- @return ContentGenerator
function gen.generator()
	return setmetatable({
		lines = {},
		indentation = 0,
	}, { __index = ContentGenerator })
end

return gen
