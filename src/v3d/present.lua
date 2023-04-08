
local v3d_framebuffer = require '_framebuffer'

--------------------------------------------------------------------------------
--[[ Lookup table generation ]]-------------------------------------------------
--------------------------------------------------------------------------------

local CH_SPACE = string.byte ' '
local CH_0 = string.byte '0'
local CH_A = string.byte 'a'
local CH_SUBPIXEL_NOISEY = 149
local colour_byte_lookup = {}
local subpixel_code_ch_lookup = {}
local subpixel_code_fg_lookup = {}
local subpixel_code_bg_lookup = {}

do
	for i = 0, 15 do
		colour_byte_lookup[2 ^ i] = i < 10 and CH_0 + i or CH_A + (i - 10)
	end

	local function subpixel_byte_value(v0, v1, v2, v3, v4, v5)
		local b0 = v0 == v5 and 0 or 1
		local b1 = v1 == v5 and 0 or 1
		local b2 = v2 == v5 and 0 or 1
		local b3 = v3 == v5 and 0 or 1
		local b4 = v4 == v5 and 0 or 1

		return 128 + b0 + b1 * 2 + b2 * 4 + b3 * 8 + b4 * 16
	end

	local function eval_subpixel_lookups(ci0, ci1, ci2, ci3, ci4, ci5, subpixel_code)
		local colour_count = { [ci0] = 1 }
		local unique_colour_values = { ci0 }
		local unique_colours = 1

		for _, c in ipairs { ci1, ci2, ci3, ci4, ci5 } do
			if colour_count[c] then
				colour_count[c] = colour_count[c] + 1
			else
				colour_count[c] = 1
				unique_colours = unique_colours + 1
				unique_colour_values[unique_colours] = c
			end
		end

		table.sort(unique_colour_values, function(a, b)
			return colour_count[a] > colour_count[b]
		end)

		if unique_colours == 1 then -- these should never be used!
			subpixel_code_ch_lookup[subpixel_code] = false
			subpixel_code_fg_lookup[subpixel_code] = false
			subpixel_code_bg_lookup[subpixel_code] = false
			return
		end

		local colour_indices = { ci0, ci1, ci2, ci3, ci4, ci5 }
		local modal1_colour_index = unique_colour_values[1]
		local modal2_colour_index = unique_colour_values[2]
		local modal1_index = 0
		local modal2_index = 0

		for i = 1, 6 do
			if colour_indices[i] == modal1_colour_index then
				modal1_index = i
			end
			if colour_indices[i] == modal2_colour_index then
				modal2_index = i
			end
		end

		-- spatially map pixels!
		ci0 = (ci0 == modal1_colour_index or ci0 == modal2_colour_index) and ci0 or (ci1 == modal1_colour_index or ci1 == modal2_colour_index) and ci1 or ci2
		ci1 = (ci1 == modal1_colour_index or ci1 == modal2_colour_index) and ci1 or (ci0 == modal1_colour_index or ci0 == modal2_colour_index) and ci0 or ci3
		ci2 = (ci2 == modal1_colour_index or ci2 == modal2_colour_index) and ci2 or (ci3 == modal1_colour_index or ci3 == modal2_colour_index) and ci3 or ci4
		ci3 = (ci3 == modal1_colour_index or ci3 == modal2_colour_index) and ci3 or (ci2 == modal1_colour_index or ci2 == modal2_colour_index) and ci2 or ci5
		ci4 = (ci4 == modal1_colour_index or ci4 == modal2_colour_index) and ci4 or (ci5 == modal1_colour_index or ci5 == modal2_colour_index) and ci5 or ci2
		ci5 = (ci5 == modal1_colour_index or ci5 == modal2_colour_index) and ci5 or (ci4 == modal1_colour_index or ci4 == modal2_colour_index) and ci4 or ci3
		subpixel_code_ch_lookup[subpixel_code] = subpixel_byte_value(ci0, ci1, ci2, ci3, ci4, ci5)
		subpixel_code_fg_lookup[subpixel_code] = ci5 == modal1_colour_index and modal2_index or modal1_index
		subpixel_code_bg_lookup[subpixel_code] = ci5 == modal1_colour_index and modal1_index or modal2_index
	end

	local subpixel_code = 0
	for c5 = 0, 3 do
		for c4 = 0, 3 do
			for c3 = 0, 3 do
				for c2 = 0, 3 do
					for c1 = 0, 3 do
						for c0 = 0, 3 do
							eval_subpixel_lookups(c0, c1, c2, c3, c4, c5, subpixel_code)
							subpixel_code = subpixel_code + 1
						end
					end
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
--[[ CCTermAPI ]]---------------------------------------------------------------
--------------------------------------------------------------------------------

do
	--- ComputerCraft native terminal objects, for example `term` or `window`
	--- objects.
	--- @alias CCTermAPI table
end

--------------------------------------------------------------------------------
--[[ v3d.Framebuffer extensions ]]----------------------------------------------
--------------------------------------------------------------------------------

do
	--- Render the framebuffer to the terminal, drawing a high resolution image
	--- using subpixel conversion.
	--- @param term CCTermAPI CC term API, e.g. 'term', or a window object you want to draw to.
	--- @param layer v3d.LayerName TODO
	--- @param dx integer | nil Horizontal integer pixel offset when drawing. 0 (default) means no offset.
	--- @param dy integer | nil Vertical integer pixel offset when drawing. 0 (default) means no offset.
	--- @return nil
	function v3d_framebuffer.Framebuffer:blit_term_subpixel(term, layer, dx, dy)
		dx = dx or 0
		dy = dy or 0

		local SUBPIXEL_WIDTH = 2
		local SUBPIXEL_HEIGHT = 3

		local fb_colour, fb_width = self:get_buffer(layer), self.width

		local xBlit = 1 + dx

		--- @diagnostic disable-next-line: deprecated
		local table_unpack = table.unpack
		local string_char = string.char
		local term_blit = term.blit
		local term_setCursorPos = term.setCursorPos

		local i0 = 1
		local ch_t = {}
		local fg_t = {}
		local bg_t = {}

		local ixMax = fb_width / SUBPIXEL_WIDTH

		for yBlit = 1 + dy, self.height / SUBPIXEL_HEIGHT + dy do
			for ix = 1, ixMax do
				local i1 = i0 + fb_width
				local i2 = i1 + fb_width
				local c00, c10 = fb_colour[i0], fb_colour[i0 + 1]
				local c01, c11 = fb_colour[i1], fb_colour[i1 + 1]
				local c02, c12 = fb_colour[i2], fb_colour[i2 + 1]

				-- TODO: make this a massive decision tree?
				-- no!
				-- if two middle pixels are equal, that's a guaranteed colour

				local unique_colour_lookup = { [c00] = 0 }
				local unique_colours = 1

				if c01 ~= c00 then
					unique_colour_lookup[c01] = unique_colours
					unique_colours = unique_colours + 1
				end
				if not unique_colour_lookup[c02] then
					unique_colour_lookup[c02] = unique_colours
					unique_colours = unique_colours + 1
				end
				if not unique_colour_lookup[c10] then
					unique_colour_lookup[c10] = unique_colours
					unique_colours = unique_colours + 1
				end
				if not unique_colour_lookup[c11] then
					unique_colour_lookup[c11] = unique_colours
					unique_colours = unique_colours + 1
				end
				if not unique_colour_lookup[c12] then
					unique_colour_lookup[c12] = unique_colours
					unique_colours = unique_colours + 1
				end

				if unique_colours == 2 then
					local other_colour = c02

						if c00 ~= c12 then other_colour = c00
					elseif c10 ~= c12 then other_colour = c10
					elseif c01 ~= c12 then other_colour = c01
					elseif c11 ~= c12 then other_colour = c11
					end

					local subpixel_ch = 128

					if c00 ~= c12 then subpixel_ch = subpixel_ch + 1 end
					if c10 ~= c12 then subpixel_ch = subpixel_ch + 2 end
					if c01 ~= c12 then subpixel_ch = subpixel_ch + 4 end
					if c11 ~= c12 then subpixel_ch = subpixel_ch + 8 end
					if c02 ~= c12 then subpixel_ch = subpixel_ch + 16 end

					ch_t[ix] = subpixel_ch
					fg_t[ix] = colour_byte_lookup[other_colour]
					bg_t[ix] = colour_byte_lookup[c12]
				elseif unique_colours == 1 then
					ch_t[ix] = CH_SPACE
					fg_t[ix] = CH_0
					bg_t[ix] = colour_byte_lookup[c00]
				elseif unique_colours > 4 then -- so random that we're gonna just give up lol
					ch_t[ix] = CH_SUBPIXEL_NOISEY
					fg_t[ix] = colour_byte_lookup[c01]
					bg_t[ix] = colour_byte_lookup[c00]
				else
					local colours = { c00, c10, c01, c11, c02, c12 }
					local subpixel_code = unique_colour_lookup[c12] * 1024
										+ unique_colour_lookup[c02] * 256
										+ unique_colour_lookup[c11] * 64
										+ unique_colour_lookup[c01] * 16
										+ unique_colour_lookup[c10] * 4
										+ unique_colour_lookup[c00]

					ch_t[ix] = subpixel_code_ch_lookup[subpixel_code]
					fg_t[ix] = colour_byte_lookup[colours[subpixel_code_fg_lookup[subpixel_code]]]
					bg_t[ix] = colour_byte_lookup[colours[subpixel_code_bg_lookup[subpixel_code]]]
				end

				i0 = i0 + SUBPIXEL_WIDTH
			end

			term_setCursorPos(xBlit, yBlit)
			term_blit(string_char(table_unpack(ch_t)), string_char(table_unpack(fg_t)), string_char(table_unpack(bg_t)))
			i0 = i0 + fb_width * 2
		end
	end

	--- TODO
	--- @param term CCTermAPI CC term API, e.g. 'term', or a window object you want to draw to.
	--- @param layer v3d.LayerName TODO
	--- @param dx integer | nil Horizontal integer pixel offset when drawing. 0 (default) means no offset.
	--- @param dy integer | nil Vertical integer pixel offset when drawing. 0 (default) means no offset.
	--- @param width integer | nil Width of the area to draw. Defaults to the framebuffer width.
	--- @param height integer | nil Height of the area to draw. Defaults to the framebuffer height.
	--- @param x integer | nil Horizontal integer pixel offset within the framebuffer. 0 (default) means no offset.
	--- @param y integer | nil Vertical integer pixel offset within the framebuffer. 0 (default) means no offset.
	--- @param sx integer | nil Horizontal integer pixel scale factor. 1 (default) means no scaling.
	--- @param sy integer | nil Vertical integer pixel scale factor. 1 (default) means no scaling.
	--- @return nil
	function v3d_framebuffer.Framebuffer:blit_graphics(term, layer, dx, dy, width, height, x, y, sx, sy)
		dx = dx or 0
		dy = dy or 0
		x = x or 0
		y = y or 0
		width = width or self.width
		height = height or self.height
		sx = sx or 1
		sy = sy or 1

		local lines = {}
		local index = 1 + x
		local lines_index = 1
		local fb_colour = self:get_buffer(layer)
		local row_delta = self.width - width
		local fb_width = self.width
		local string_char = string.char
		local string_rep = string.rep
		local table_concat = table.concat
		local math_floor = math.floor
		local math_log = math.log
		local function convert_pixel(n) return math_floor(math_log(n + 0.5, 2)) end

		if term.getGraphicsMode() == 2 then
			convert_pixel = function(n) return n end
		end

		for _ = 1, height do
			local line = {}
			local line_index = 1

			for _ = 1, width do
				line[line_index] = string_rep(string_char(convert_pixel(fb_colour[index])), sx)
				line_index = line_index + 1
				index = index + 1
			end

			index = index + row_delta

			local line_string = table_concat(line)

			for _ = 1, sy do
				lines[lines_index] = line_string
				lines_index = lines_index + 1
			end
		end

		term.drawPixels(dx, dy, lines)
	end
end
