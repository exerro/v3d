
local TextureFormat = require "lib.TextureFormat"
local libfallbackTable = require "lib.fallback_table"
local libtexture = require "lib.texture"

local math_floor = math.floor
local math_log = math.log
local string_char = string.char
local table_unpack = table.unpack

local SUBPIXEL_WIDTH = 2
local SUBPIXEL_HEIGHT = 3
local SUBPIXEL_SIZE = SUBPIXEL_WIDTH * SUBPIXEL_HEIGHT
local SUBPIXEL_INVERT_THRESHOLD = 2 ^ (SUBPIXEL_SIZE - 1)
local SUBPIXEL_BASE = 128

local colour_lookup = {}

for i = 0, 15 do
	colour_lookup[i + 1] = i < 10 and ("0"):byte() + i or ("a"):byte() + i - 10
end

local function blit_idx(texture_data, texture_width, texture_height, term, fallback_table)
	local base_index = 1
	local base_index_delta = texture_width * 3
	local y = 1

	for ty = 1, texture_height, SUBPIXEL_HEIGHT do
		local rowBg = {}
		local rowFg = {}
		local rowCh = {}
		local rowIdx = 1

		for txd = 0, texture_width - 1, SUBPIXEL_WIDTH do
			local px_index = base_index + txd
			local px_index1 = px_index + texture_width
			local px_index2 = px_index1 + texture_width
			local c0 = texture_data[px_index]
			local c1 = texture_data[px_index + 1]
			local c2 = texture_data[px_index1]
			local c3 = texture_data[px_index1 + 1]
			local c4 = texture_data[px_index2]
			local c5 = texture_data[px_index2 + 1]
			local colours = { c0, c1, c2, c3, c4, c5 }

			local totals = { [c0] = 1 }
			local max_count0, max_count0_colour = 1, c0
			local max_count1, max_count1_colour = 0, max_count0_colour + 1

			for i = 2, SUBPIXEL_SIZE do
				local c = colours[i]
				local total = (totals[c] or 0) + 1

				if c == max_count0_colour then
					max_count0 = total
				elseif c == max_count1_colour then
					max_count1 = total
				elseif total > max_count1 then
					max_count1 = total
					max_count1_colour = c
				end

				if max_count1 > max_count0 then
					max_count0, max_count1 = max_count1, max_count0
					max_count0_colour, max_count1_colour = max_count1_colour, max_count0_colour
				end

				totals[c] = total
			end

			local subpixel_n = SUBPIXEL_BASE
			local bg_colour, fg_colour = max_count0_colour, max_count1_colour

			for i = 1, SUBPIXEL_SIZE do
				local c = colours[i]

				if c ~= bg_colour and c ~= fg_colour then
					local ftl = fallback_table[c]
					for j = 1, #ftl do
						if ftl[j] == bg_colour or ftl[j] == fg_colour then
							colours[i] = ftl[j]
							break
						end
					end
				end
			end

			if colours[SUBPIXEL_SIZE] == fg_colour then
				bg_colour, fg_colour = fg_colour, bg_colour
			end

			for i = 1, SUBPIXEL_SIZE - 1 do
				if colours[i] == fg_colour then
					subpixel_n = subpixel_n + 2 ^ (i - 1)
				end
			end

			rowBg[rowIdx] = colour_lookup[bg_colour + 1]
			rowFg[rowIdx] = colour_lookup[fg_colour + 1]
			rowCh[rowIdx] = subpixel_n
			rowIdx = rowIdx + 1
		end

		term.setCursorPos(1, y)
		term.blit(string_char(table_unpack(rowCh)), string_char(table_unpack(rowFg)), string_char(table_unpack(rowBg)))

		base_index = base_index + base_index_delta
		y = y + 1
	end
end

return function(texture, term, fallback_table)
	assert(type(texture) == "table" and texture.__type == libtexture.__type, "Expected Texture")
	assert(type(term) == "table", "Expected table term")
	assert(type(fallback_table) == "table" and fallback_table.__type == libfallbackTable.__type, "Expected FallbackTable")
	assert(texture.width % SUBPIXEL_WIDTH == 0, "Texture width is not a multiple of " .. SUBPIXEL_WIDTH)
	assert(texture.height % SUBPIXEL_HEIGHT == 0, "Texture height is not a multiple of " .. SUBPIXEL_HEIGHT)

	if texture.format == TextureFormat.Idx1 then
		return blit_idx(texture, texture.width, texture.height, term, fallback_table)
	elseif texture.format == TextureFormat.Col1 then
		local data = {}

		for i = 1, texture.size do
			data[i] = math_floor(math_log(texture[i], 2))
		end

		return blit_idx(data, texture.width, texture.height, term, fallback_table)
	else
		error("Unsupported texture format " .. tostring(texture.format))
	end
end
