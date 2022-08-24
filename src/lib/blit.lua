
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

local function blit_idx(texture_data, texture_width, texture_height, term, fallback_table, dirty_texture)
	local base_index = 1
	local base_index_delta = texture_width * 3
	local y = 1
	local dirty_index = 1
	
	local rowBg = {}
	local rowFg = {}
	local rowCh = {}

	dirty_texture = dirty_texture or {}

	for ty = 1, texture_height, SUBPIXEL_HEIGHT do
		local rowIdx = 1
		local row_dirty = false
		local row_dirty_first_index = 0
		local row_dirty_last_index = 0

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
					colours[i] = bg_colour
					for j = 1, 4 do -- check the first 4 fallback colours
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

			local bg = colour_lookup[bg_colour + 1]
			local fg = colour_lookup[fg_colour + 1]

			local this_dirty = dirty_texture == nil or dirty_texture[dirty_index] ~= bg or dirty_texture[dirty_index + 1] ~= fg or dirty_texture[dirty_index + 2] ~= subpixel_n

			if not row_dirty and this_dirty then
				row_dirty = true
				row_dirty_first_index = txd
			end

			if this_dirty then
				row_dirty_last_index = txd
			end

			if row_dirty then
				rowBg[rowIdx] = bg
				rowFg[rowIdx] = fg
				rowCh[rowIdx] = subpixel_n
				if dirty_texture then
					dirty_texture[dirty_index] = bg
					dirty_texture[dirty_index + 1] = fg
					dirty_texture[dirty_index + 2] = subpixel_n
				end
			end

			rowIdx = rowIdx + 1
			dirty_index = dirty_index + 3
		end

		if row_dirty then
			local i0 = row_dirty_first_index / SUBPIXEL_WIDTH + 1
			local i1 = row_dirty_last_index  / SUBPIXEL_WIDTH + 1
			local chs = string_char(table_unpack(rowCh, i0, i1))
			local fgs = string_char(table_unpack(rowFg, i0, i1))
			local bgs = string_char(table_unpack(rowBg, i0, i1))

			term.setCursorPos(i0, y)
			-- term.blit((" "):rep(#chs), fgs, ("a"):rep(#bgs))
			term.blit(chs, fgs, bgs)
		end

		base_index = base_index + base_index_delta
		y = y + 1
	end
end

return function(texture, term, fallback_table, dirty_texture)
	assert(type(texture) == "table" and texture.__type == libtexture.__type, "Expected Texture")
	assert(type(term) == "table", "Expected table term")
	assert(type(fallback_table) == "table" and fallback_table.__type == libfallbackTable.__type, "Expected FallbackTable")
	assert(dirty_texture == nil or type(dirty_texture) == "table" and dirty_texture.__type == libtexture.__type, "Expected dirty_texture texture")
	assert(texture.width % SUBPIXEL_WIDTH == 0, "Texture width is not a multiple of " .. SUBPIXEL_WIDTH)
	assert(texture.height % SUBPIXEL_HEIGHT == 0, "Texture height is not a multiple of " .. SUBPIXEL_HEIGHT)
	assert(dirty_texture == nil or texture.width == SUBPIXEL_WIDTH * dirty_texture.width, "Texture width is not proportional to dirty texture width")
	assert(dirty_texture == nil or texture.height == SUBPIXEL_HEIGHT * dirty_texture.height, "Texture height is not proportional to dirty texture height")

	if texture.format == TextureFormat.Idx1 then
		return blit_idx(texture, texture.width, texture.height, term, fallback_table, dirty_texture)
	elseif texture.format == TextureFormat.Col1 then
		local data = {}

		for i = 1, texture.size do
			data[i] = math_floor(math_log(texture[i], 2) + 0.5)
		end

		return blit_idx(data, texture.width, texture.height, term, fallback_table, dirty_texture)
	else
		error("Unsupported texture format " .. tostring(texture.format))
	end
end
