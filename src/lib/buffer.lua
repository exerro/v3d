
local BufferFormat = require "lib.BufferFormat"
local unique = require "lib.unique"

local buffer = {}
local buffer_mt = {}

buffer.__type = unique "Buffer"

function buffer_mt:__call(data)
	assert(type(data) == "table", "Expected a data table")

	-- TODO: typecheck etc

	local original_size = self.size
	local data_len = #data

	self.size = original_size + data_len

	for i = 1, data_len do
		self[original_size + i] = data[i]
	end

	return self
end

function buffer.create(format)
	return setmetatable({
		__type = buffer.__type,
		format = format,
		size = 0,
	}, buffer_mt)
end

return buffer
