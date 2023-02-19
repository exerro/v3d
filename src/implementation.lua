
-- #remove
-- note: this code will be stripped out during the build process, thus removing
--       the error
error 'Cannot use v3d source code, must build the library'
-- #end
--- @type v3d
local v3d = {}


--------------------------------------------------------------------------------
--[ Subpixel lookup tables ]----------------------------------------------------
--------------------------------------------------------------------------------


local CH_SPACE = string.byte ' '
local CH_0 = string.byte '0'
local CH_A = string.byte 'a'
local CH_SUBPIXEL_NOISEY = 149
local colour_byte_lookup = {}
local subpixel_code_ch_lookup = {}
local subpixel_code_fg_lookup = {}
local subpixel_code_bg_lookup = {}

-- Code for pre-generating the lookup tables above
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
--[ Framebuffer functions ]-----------------------------------------------------
--------------------------------------------------------------------------------


local function framebuffer_clear(fb, colour, clear_depth)
	local fb_colour = fb.colour
	local fb_depth = fb.depth
	for i = 1, fb.width * fb.height do
		fb_colour[i] = colour or 1
	end
	if clear_depth ~= false then
		for i = 1, fb.width * fb.height do
			fb_depth[i] = 0
		end
	end
end

local function framebuffer_clear_depth(fb, depth)
	local fb_depth = fb.depth
	for i = 1, fb.width * fb.height do
		fb_depth[i] = depth
	end
end

local function framebuffer_blit_term_subpixel(fb, term, dx, dy)
	dx = dx or 0
	dy = dy or 0

	local SUBPIXEL_WIDTH = 2
	local SUBPIXEL_HEIGHT = 3

	local fb_colour, fb_width = fb.colour, fb.width

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

	for yBlit = 1 + dy, fb.height / SUBPIXEL_HEIGHT + dy do
		for ix = 1, ixMax do
			local i1 = i0 + fb_width
			local i2 = i1 + fb_width
			local c00, c10 = fb_colour[i0], fb_colour[i0 + 1]
			local c01, c11 = fb_colour[i1], fb_colour[i1 + 1]
			local c02, c12 = fb_colour[i2], fb_colour[i2 + 1]

			-- TODO: make this a massive decision tree?
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

local function framebuffer_blit_term_subpixel_depth(fb, term, dx, dy, update_palette)
	local math_floor = math.floor

	if update_palette ~= false then
		for i = 0, 15 do
			term.setPaletteColour(2 ^ i, i / 15, i / 15, i / 15)
		end
	end

	-- we're gonna do a hack to swap out the buffers and draw it like normal

	local fb_depth = fb.depth
	local old_colour = fb.colour
	local new_colour = {}
	local min = fb_depth[1]
	local max = fb_depth[1]

	for i = 2, #fb_depth do
		local a = fb_depth[i]
		if a < min then min = a end
		if a > max then max = a end
	end

	local delta = max - min

	if min == max then
		delta = 1
	end

	for i = 1, #fb_depth do
		local a = (fb_depth[i] - min) / delta
		local b = math_floor(a * 16)
		if b == 16 then b = 15 end
		new_colour[i] = 2 ^ b
	end

	fb.colour = new_colour
	framebuffer_blit_term_subpixel(fb, term, dx, dy)
	fb.colour = old_colour
end

local function framebuffer_blit_graphics(fb, term, dx, dy)
	local lines = {}
	local index = 1
	local fb_colour = fb.colour
	local fb_width = fb.width
	local string_char = string.char
	local table_concat = table.concat
	local math_floor = math.floor
	local math_log = math.log
	local function convert_pixel(n) return math_floor(math_log(n + 0.5, 2)) end

	if term.getGraphicsMode() == 2 then
		convert_pixel = function(n) return n end
	end

	dx = dx or 0
	dy = dy or 0

	for y = 1, fb.height do
		local line = {}

		for x = 1, fb_width do
			if not pcall(string_char, convert_pixel(fb_colour[index])) then error(fb_colour[index]) end
			line[x] = string_char(convert_pixel(fb_colour[index]))
			index = index + 1
		end

		lines[y] = table_concat(line)
	end

	term.drawPixels(dx, dy, lines)
end

-- TODO: find and remove replication with framebuffer_blit_term_subpixel_depth
local function framebuffer_blit_graphics_depth(fb, term, dx, dy, update_palette)
	local math_floor = math.floor
	local palette_size = 16
	local function convert_pixel(n) return 2 ^ n end

	if term.getGraphicsMode() == 2 then
		palette_size = 256
		convert_pixel = function(n) return n end
	end

	if update_palette ~= false then
		for i = 0, palette_size - 1 do
			term.setPaletteColour(convert_pixel(i), i / (palette_size - 1), i / (palette_size - 1), i / (palette_size - 1))
		end
	end

	-- we're gonna do a hack to swap out the buffers and draw it like normal

	local fb_depth = fb.depth
	local old_colour = fb.colour
	local new_colour = {}
	local min = fb_depth[1]
	local max = fb_depth[1]

	for i = 2, #fb_depth do
		local a = fb_depth[i]
		if a < min then min = a end
		if a > max then max = a end
	end

	local delta = max - min

	if min == max then
		delta = 1
	end

	for i = 1, #fb_depth do
		local a = (fb_depth[i] - min) / delta
		local b = math_floor(a * palette_size)
		if b == palette_size then b = palette_size - 1 end
		new_colour[i] = convert_pixel(b)
	end

	fb.colour = new_colour
	framebuffer_blit_graphics(fb, term, dx, dy)
	fb.colour = old_colour
end

local function create_framebuffer(width, height)
	--- @type V3DFramebuffer
	local fb = {}

	fb.width = width
	fb.height = height
	fb.colour = {}
	fb.depth = {}
	fb.clear = framebuffer_clear
	fb.clear_depth = framebuffer_clear_depth
	fb.blit_term_subpixel = framebuffer_blit_term_subpixel
	fb.blit_term_subpixel_depth = framebuffer_blit_term_subpixel_depth
	fb.blit_graphics = framebuffer_blit_graphics
	fb.blit_graphics_depth = framebuffer_blit_graphics_depth

	framebuffer_clear(fb)

	return fb
end

local function create_framebuffer_subpixel(width, height)
	return create_framebuffer(width * 2, height * 3) -- multiply by subpixel dimensions
end


--------------------------------------------------------------------------------
--[ Layout functions ]----------------------------------------------------------
--------------------------------------------------------------------------------


local function layout_add_attribute(layout, name, size, type, is_numeric)
	local attr = {}

	attr.name = name
	attr.size = size
	attr.type = type
	attr.is_numeric = is_numeric
	attr.offset = type == 'vertex' and layout.vertex_stride or layout.face_stride

	--- @type table
	local new_layout = v3d.create_layout()

	for i = 1, #layout.attributes do
		new_layout.attributes[i] = layout.attributes[i]
		new_layout.attribute_lookup[layout.attributes[i].name] = i
	end

	table.insert(new_layout.attributes, attr)
	new_layout.attribute_lookup[name] = #new_layout.attributes

	if type == 'vertex' then
		new_layout.vertex_stride = layout.vertex_stride + size
		new_layout.face_stride = layout.face_stride
	else
		new_layout.vertex_stride = layout.vertex_stride
		new_layout.face_stride = layout.face_stride + size
	end

	return new_layout
end

local function layout_add_vertex_attribute(layout, name, size, is_numeric)
	return layout_add_attribute(layout, name, size, 'vertex', is_numeric)
end

local function layout_add_face_attribute(layout, name, size)
	return layout_add_attribute(layout, name, size, 'face', false)
end

local function layout_drop_attribute(layout, attribute)
	if not layout:has_attribute(attribute) then return layout end
	local attribute_name = attribute.name or attribute

	local new_layout = v3d.create_layout()

	for i = 1, #layout.attributes do
		local attr = layout.attributes[i]
		if attr.name ~= attribute_name then
			new_layout = layout_add_attribute(new_layout, attr.name, attr.size, attr.type, attr.is_numeric)
		end
	end

	return new_layout
end

local function layout_has_attribute(layout, attribute)
	if type(attribute) == 'table' then
		local index = layout.attribute_lookup[attribute.name]
		if not index then return false end
		return layout.attributes[index].size == attribute.size
		   and layout.attributes[index].type == attribute.type
		   and layout.attributes[index].is_numeric == attribute.is_numeric
	end

	return layout.attribute_lookup[attribute] ~= nil
end

local function layout_get_attribute(layout, name)
	local index = layout.attribute_lookup[name]
	return index and layout.attributes[index]
end

local function create_layout()
	local layout = {}

	layout.attributes = {}
	layout.attribute_lookup = {}
	layout.vertex_stride = 0
	layout.face_stride = 0

	layout.add_vertex_attribute = layout_add_vertex_attribute
	layout.add_face_attribute = layout_add_face_attribute
	layout.drop_attribute = layout_drop_attribute
	layout.has_attribute = layout_has_attribute
	layout.get_attribute = layout_get_attribute

	return layout
end


--------------------------------------------------------------------------------
--[ Geometry functions ]--------------------------------------------------------
--------------------------------------------------------------------------------


local function geometry_to_builder(geometry)
	local gb = v3d.create_geometry_builder(geometry.layout)

	-- TODO
	error 'NYI'

	return gb
end

local function geometry_builder_set_data(gb, attribute_name, data)
	gb.attribute_data[attribute_name] = data

	return gb
end

local function geometry_builder_append_data(gb, attribute_name, data)
	local existing_data = gb.attribute_data[attribute_name] or {}

	gb.attribute_data[attribute_name] = existing_data

	for i = 1, #data do
		table.insert(existing_data, data[i])
	end

	return gb
end

local function geometry_builder_map(gb, attribute_name, fn)
	local size = gb.layout:get_attribute(attribute_name).size
	local data = gb.attribute_data[attribute_name]

	for i = 0, #data - 1, size do
		local unmapped = {}
		for j = 1, size do
			unmapped[j] = data[i + j]
		end
		local mapped = fn(unmapped)
		for j = 1, size do
			data[i + j] = mapped[j]
		end
	end

	return gb
end

local function geometry_builder_transform(gb, attribute_name, transform)
	-- TODO
	error 'NYI'
	return gb
end

local function geometry_builder_insert(gb, other)
	for i = 1, #gb.layout.attributes do
		local attr = gb.layout.attributes[i]
		local self_data = gb.attributes_data[attr.name]
		local other_data = other.attributes_data[attr.name]
		local offset = #self_data

		for j = 1, #other_data do
			self_data[j + offset] = other_data[j]
		end
	end

	gb.vertices = gb.vertices + other.vertices
	gb.faces = gb.faces + other.faces

	return gb
end

local function geometry_builder_cast(gb, layout)
	gb.layout = layout
	return gb
end

local function geometry_builder_build(gb, label)
	local geometry = {}
	--- @type V3DLayout
	local layout = gb.layout

	geometry.layout = layout
	geometry.vertices = 0
	geometry.faces = 0

	geometry.to_builder = geometry_to_builder

	for i = 1, #layout.attributes do
		local attr = layout.attributes[i]
		local data = gb.attribute_data[attr.name]

		if attr.type == 'vertex' then
			geometry.vertices = #data / attr.size
		else
			geometry.faces = #data / attr.size
		end
	end

	geometry.vertex_offset = layout.face_stride * geometry.faces

	for i = 1, #layout.attributes do
		local attr = layout.attributes[i]
		local data = gb.attribute_data[attr.name]
		local base_offset = attr.offset
		local stride = 0
		local count = 0

		if attr.type == 'vertex' then
			base_offset = base_offset + geometry.vertex_offset
			stride = layout.vertex_stride
			count = geometry.vertices
		else
			stride = layout.face_stride
			count = geometry.faces
		end

		for j = 0, count - 1 do
			local this_offset = base_offset + stride * j
			local data_offset = attr.size * j

			for k = 1, attr.size do
				geometry[this_offset + k] = data[data_offset + k]
			end
		end
	end

	return geometry
end

local function create_geometry_builder(layout)
	local gb = {}

	gb.layout = layout
	gb.attribute_data = {}

	gb.set_data = geometry_builder_set_data
	gb.append_data = geometry_builder_append_data
	gb.map = geometry_builder_map
	gb.transform = geometry_builder_transform
	gb.insert = geometry_builder_insert
	gb.cast = geometry_builder_cast
	gb.build = geometry_builder_build

	return gb
end

local function create_debug_cube(cx, cy, cz, size)
	local s2 = (size or 1) / 2

	cx = cx or 0
	cy = cy or 0
	cz = cz or 0

	return create_geometry_builder(v3d.DEBUG_CUBE_LAYOUT)
		:set_data('position', {
			-s2,  s2,  s2, -s2, -s2,  s2,  s2,  s2,  s2, -- front 1
			-s2, -s2,  s2,  s2, -s2,  s2,  s2,  s2,  s2, -- front 2
			 s2,  s2, -s2,  s2, -s2, -s2, -s2,  s2, -s2, -- back 1
			 s2, -s2, -s2, -s2, -s2, -s2, -s2,  s2, -s2, -- back 2
			-s2,  s2, -s2, -s2, -s2, -s2, -s2,  s2,  s2, -- left 1
			-s2, -s2, -s2, -s2, -s2,  s2, -s2,  s2,  s2, -- left 2
			 s2,  s2,  s2,  s2, -s2,  s2,  s2,  s2, -s2, -- right 1
			 s2, -s2,  s2,  s2, -s2, -s2,  s2,  s2, -s2, -- right 2
			-s2,  s2, -s2, -s2,  s2,  s2,  s2,  s2, -s2, -- top 1
			-s2,  s2,  s2,  s2,  s2,  s2,  s2,  s2, -s2, -- top 2
			 s2, -s2, -s2,  s2, -s2,  s2, -s2, -s2, -s2, -- bottom 1
			 s2, -s2,  s2, -s2, -s2,  s2, -s2, -s2, -s2, -- bottom 2
		})
		:set_data('uv', {
			0, 0, 0, 1, 1, 0, -- front 1
			0, 1, 1, 1, 1, 0, -- front 2
			0, 0, 0, 1, 1, 0, -- back 1
			0, 1, 1, 1, 1, 0, -- back 2
			0, 0, 0, 1, 1, 0, -- left 1
			0, 1, 1, 1, 1, 0, -- left 2
			0, 0, 0, 1, 1, 0, -- right 1
			0, 1, 1, 1, 1, 0, -- right 2
			0, 0, 0, 1, 1, 0, -- top 1
			0, 1, 1, 1, 1, 0, -- top 2
			0, 0, 0, 1, 1, 0, -- bottom 1
			0, 1, 1, 1, 1, 0, -- bottom 2
		})
		:set_data('colour', {
			colours.blue, colours.cyan, -- front,
			colours.brown, colours.yellow, -- back
			colours.lightBlue, colours.pink, -- left
			colours.red, colours.orange, -- right
			colours.green, colours.lime, -- top
			colours.purple, colours.magenta, -- bottom
		})
		:set_data('face_normal', {
			 0,  0,  1,  0,  0,  1, -- front
			 0,  0,  1,  0,  0, -1, -- back
			-1,  0,  0, -1,  0,  0, -- left
			 1,  0,  0,  1,  0,  0, -- right
			 0,  1,  0,  0,  1,  0, -- top
			 0, -1,  0,  0, -1,  0, -- bottom
		})
		:set_data('face_index', { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 })
		:set_data('side_index', { 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5 })
		:set_data('side_name', {
			'front', 'front',
			'back', 'back',
			'left', 'left',
			'right', 'right',
			'top', 'top',
			'bottom', 'bottom',
		})
		:map('position', function(d)
			return { d[1] + cx, d[2] + cy, d[3] + cz }
		end)
end


--------------------------------------------------------------------------------
--[ Transform functions ]-------------------------------------------------------
--------------------------------------------------------------------------------


local create_identity_transform

local function transform_combine(transform, other)
	local t = create_identity_transform()

	t[ 1] = transform[ 1] * other[1] + transform[ 2] * other[5] + transform[ 3] * other[ 9]
	t[ 2] = transform[ 1] * other[2] + transform[ 2] * other[6] + transform[ 3] * other[10]
	t[ 3] = transform[ 1] * other[3] + transform[ 2] * other[7] + transform[ 3] * other[11]
	t[ 4] = transform[ 1] * other[4] + transform[ 2] * other[8] + transform[ 3] * other[12] + transform[ 4]

	t[ 5] = transform[ 5] * other[1] + transform[ 6] * other[5] + transform[ 7] * other[ 9]
	t[ 6] = transform[ 5] * other[2] + transform[ 6] * other[6] + transform[ 7] * other[10]
	t[ 7] = transform[ 5] * other[3] + transform[ 6] * other[7] + transform[ 7] * other[11]
	t[ 8] = transform[ 5] * other[4] + transform[ 6] * other[8] + transform[ 7] * other[12] + transform[ 8]

	t[ 9] = transform[ 9] * other[1] + transform[10] * other[5] + transform[11] * other[ 9]
	t[10] = transform[ 9] * other[2] + transform[10] * other[6] + transform[11] * other[10]
	t[11] = transform[ 9] * other[3] + transform[10] * other[7] + transform[11] * other[11]
	t[12] = transform[ 9] * other[4] + transform[10] * other[8] + transform[11] * other[12] + transform[12]

	return t
end

local function transform_transform(transform, data, translate)
	local d1 = data[1]
	local d2 = data[2]
	local d3 = data[3]

	local r1 = transform[1] * d1 + transform[ 2] * d2 + transform[ 3] * d3
	local r2 = transform[5] * d1 + transform[ 6] * d2 + transform[ 7] * d3
	local r3 = transform[9] * d1 + transform[10] * d2 + transform[11] * d3

	if translate then
		r1 = r1 + transform[ 4]
		r2 = r2 + transform[ 8]
		r3 = r3 + transform[12]
	end

	return { r1, r2, r3 }
end

local transform_mt = { __mul = transform_combine }

function create_identity_transform()
	local t = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0 }

	t.combine = transform_combine
	t.transform = transform_transform

	return setmetatable(t, transform_mt)
end

local function create_translate_transform(dx, dy, dz)
	local t = { 1, 0, 0, dx, 0, 1, 0, dy, 0, 0, 1, dz }

	t.combine = transform_combine
	t.transform = transform_transform

	return setmetatable(t, transform_mt)
end

local function create_scale_transform(sx, sy, sz)
	local t = { sx, 0, 0, 0, 0, sy or sx, 0, 0, 0, 0, sz or sx, 0 }

	t.combine = transform_combine
	t.transform = transform_transform

	return setmetatable(t, transform_mt)
end

local function create_rotate_transform(tx, ty, tz)
	local math_sin = math.sin
	local math_cos = math.cos
	local sin_x = math_sin(tx)
	local sin_y = math_sin(ty)
	local sin_z = math_sin(tz)
	local cos_x = math_cos(tx)
	local cos_y = math_cos(ty)
	local cos_z = math_cos(tz)
	local fxx = cos_y*cos_z - sin_x*sin_y*sin_z
	local fxy = cos_x*sin_z
	local fxz = sin_y*cos_z + sin_x*cos_y*sin_z
	local fyx = -cos_y*sin_z - sin_x*sin_y*cos_z
	local fyy = cos_x*cos_z
	local fyz = -sin_y*sin_z + sin_x*cos_y*cos_z
	local fzx = -cos_x*sin_y
	local fzy = -sin_x
	local fzz = cos_x*cos_y
	local t = { fxx, fxy, fxz, 0, fyx, fyy, fyz, 0, fzx, fzy, fzz, 0 }

	t.combine = transform_combine
	t.transform = transform_transform

	return setmetatable(t, transform_mt)
end

local function create_camera_transform(x, y, z, rx, ry, rz, fov)
	if not y then
		fov = x
		x = 0
	end

	if not rz then
		fov = ry
		ry = rx
		rx = 0
	end

	fov = fov or math.pi / 3
	rx = rx or 0
	ry = ry or 0
	rz = rz or 0
	x = x or 0
	y = y or 0
	z = z or 0

	local tan_inverse = 1 / math.tan(fov / 2)

	return transform_combine(transform_combine(
		{ tan_inverse, 0, 0, 0, 0, tan_inverse, 0, 0, 0, 0, 1, 0 },
		create_rotate_transform(-rx, -ry, -rz)),
		{ 1, 0, 0, -x, 0, 1, 0, -y, 0, 0, 1, -z })
end


--------------------------------------------------------------------------------
--[ Rasterization functions ]---------------------------------------------------
--------------------------------------------------------------------------------


local RASTERIZE_FLAT_TRIANGLE_SOURCE = [[
for base_index = _pflat_it_a, _pflat_it_b, fb_width do
	local column_min_x = math_ceil(_pflat_tri_left_x)
	local column_max_x = math_ceil(_pflat_tri_right_x)

	-- #marker ROW_CALCULATIONS

	if column_min_x < 0 then column_min_x = 0 end
	if column_max_x > fb_width_m1 then column_max_x = fb_width_m1 end

	for x = column_min_x, column_max_x do
		local index = base_index + x
		-- #marker PIXEL_DRAW_ADVANCE
	end

	_pflat_tri_left_x = _pflat_tri_left_x + _pflat_tri_left_gradient_x
	_pflat_tri_right_x = _pflat_tri_right_x + _pflat_tri_right_gradient_x
	-- #marker ROW_ADVANCE
end
]]

local RASTERIZE_TRIANGLE_SOURCE = [[
-- #marker VERTEX_ORDERING
if _ptri_p0y == _ptri_p2y then return end -- skip early if we have a perfectly flat triangle

local f = (_ptri_p1y - _ptri_p0y) / (_ptri_p2y - _ptri_p0y)
local pMx = _ptri_p0x * (1 - f) + _ptri_p2x * f

-- #marker MIDPOINT_CALCULATION

if pMx > _ptri_p1x then
	pMx, _ptri_p1x = _ptri_p1x, pMx
	-- #marker MIDPOINT_SWAP
end

local row_top_min = math_floor(_ptri_p0y + 0.5)
local row_bottom_min = math_floor(_ptri_p1y + 0.5)
local row_top_max = row_bottom_min - 1
local row_bottom_max = math_ceil(_ptri_p2y - 0.5)

if row_top_min < 0 then row_top_min = 0 end
if row_bottom_min < 0 then row_bottom_min = 0 end
if row_top_max > fb_height_m1 then row_top_max = fb_height_m1 end
if row_bottom_max > fb_height_m1 then row_bottom_max = fb_height_m1 end

if row_top_min <= row_top_max then
	local tri_delta_y = _ptri_p1y - _ptri_p0y
	if tri_delta_y > 0 then
		local _pflat_tri_left_gradient_x = (pMx - _ptri_p0x) / tri_delta_y
		local _pflat_tri_right_gradient_x = (_ptri_p1x - _ptri_p0x) / tri_delta_y
		local tri_projection = row_top_min + 0.5 - _ptri_p0y
		local _pflat_tri_left_x = _ptri_p0x + _pflat_tri_left_gradient_x * tri_projection - 0.5
		local _pflat_tri_right_x = _ptri_p0x + _pflat_tri_right_gradient_x * tri_projection - 1.5
		-- #marker TOP_HALF_CALCULATIONS

		local _pflat_it_a, _pflat_it_b = row_top_min * fb_width + 1, row_top_max * fb_width + 1

		-- #marker RASTERIZE_FLAT_TRIANGLE_SOURCE
	end
end

if row_bottom_min <= row_bottom_max then
	local tri_delta_y = _ptri_p2y - _ptri_p1y

	if tri_delta_y > 0 then
		local _pflat_tri_left_gradient_x = (_ptri_p2x - pMx) / tri_delta_y
		local _pflat_tri_right_gradient_x = (_ptri_p2x - _ptri_p1x) / tri_delta_y
		local tri_projection = row_bottom_min + 0.5 - _ptri_p1y
		local _pflat_tri_left_x = pMx + _pflat_tri_left_gradient_x * tri_projection - 0.5
		local _pflat_tri_right_x = _ptri_p1x + _pflat_tri_right_gradient_x * tri_projection - 1.5
		-- #marker BOTTOM_HALF_CALCULATIONS

		local _pflat_it_a, _pflat_it_b = row_bottom_min * fb_width + 1, row_bottom_max * fb_width + 1

		-- #marker RASTERIZE_FLAT_TRIANGLE_SOURCE
	end
end
]]

local RENDER_GEOMETRY_SOURCE = [[
local upvalue_uniforms, upvalue_opt_fragment_shader = ...
return function(_, geometry, fb, transform, model_transform)
	local uniforms = upvalue_uniforms
	local opt_fragment_shader = upvalue_opt_fragment_shader
	local math = math
	local math_ceil, math_floor = math.ceil, math.floor
	local fb_colour, fb_depth, fb_width = fb.colour, fb.depth, fb.width
	local clipping_plane = -0.0001
	local fb_width_m1, fb_height_m1 = fb_width - 1, fb.height - 1
	local pxd = (fb.width - 1) / 2
	local pyd = (fb.height - 1) / 2

	local stat_total_time = 0
	local stat_rasterize_time = 0
	local stat_candidate_faces = 0
	local stat_drawn_faces = 0
	local stat_culled_faces = 0
	local stat_clipped_faces = 0
	local stat_discarded_faces = 0
	local stat_candidate_fragments = 0
	local stat_fragments_occluded = 0
	local stat_fragments_shaded = 0
	local stat_fragments_discarded = 0
	local stat_fragments_drawn = 0

	local scale_y = -pyd - 0.5
	local scale_x = opt_pixel_aspect_ratio * (pyd - 0.5)

	-- TODO: implement this properly
	if model_transform then
		transform = transform:combine(model_transform)
	end

	local fxx = transform[ 1]
	local fxy = transform[ 2]
	local fxz = transform[ 3]
	local fdx = transform[ 4]
	local fyx = transform[ 5]
	local fyy = transform[ 6]
	local fyz = transform[ 7]
	local fdy = transform[ 8]
	local fzx = transform[ 9]
	local fzy = transform[10]
	local fzz = transform[11]
	local fdz = transform[12]

	local vertex_offset = geometry.vertex_offset
	local face_offset = 0

	-- #marker FRAGMENT_PACKED_PARAMS

	for _ = 1, geometry.vertices, 3 do
		-- #marker POSITION_ASSIGNMENT
		-- #marker ATTRIBUTE_ASSIGNMENT
		-- #marker COLOUR_ASSIGNMENT
		-- #marker INCREMENT_OFFSETS

		local sp0x = fxx * p0x + fxy * p0y + fxz * p0z + fdx
		local sp0y = fyx * p0x + fyy * p0y + fyz * p0z + fdy
		local sp0z = fzx * p0x + fzy * p0y + fzz * p0z + fdz

		local sp1x = fxx * p1x + fxy * p1y + fxz * p1z + fdx
		local sp1y = fyx * p1x + fyy * p1y + fyz * p1z + fdy
		local sp1z = fzx * p1x + fzy * p1y + fzz * p1z + fdz

		local sp2x = fxx * p2x + fxy * p2y + fxz * p2z + fdx
		local sp2y = fyx * p2x + fyy * p2y + fyz * p2z + fdy
		local sp2z = fzx * p2x + fzy * p2y + fzz * p2z + fdz

		local cull_face

		-- #marker FACE_CULLING

		-- #marker STAT_CANDIDATE_FACE

		if not cull_face then
			-- TODO: make this split polygons
			if sp0z <= clipping_plane and sp1z <= clipping_plane and sp2z <= clipping_plane then
				local _ptri_p0w = -1 / sp0z
				local _ptri_p0x = pxd + sp0x * _ptri_p0w * scale_x
				local _ptri_p0y = pyd + sp0y * _ptri_p0w * scale_y
				local _ptri_p1w = -1 / sp1z
				local _ptri_p1x = pxd + sp1x * _ptri_p1w * scale_x
				local _ptri_p1y = pyd + sp1y * _ptri_p1w * scale_y
				local _ptri_p2w = -1 / sp2z
				local _ptri_p2x = pxd + sp2x * _ptri_p2w * scale_x
				local _ptri_p2y = pyd + sp2y * _ptri_p2w * scale_y
				-- #marker RASTERIZE_TRIANGLE_ATTR_PARAM_DEFAULT
				-- #marker RASTERIZE_TRIANGLE_SOURCE
				-- #marker STAT_DRAW_FACE
			else
				-- #marker STAT_DISCARD_FACE
			end
		else
			-- #marker STAT_CULL_FACE
		end
	end

	return {
		total_time = stat_total_time,
		rasterize_time = stat_rasterize_time,
		candidate_faces = stat_candidate_faces,
		drawn_faces = stat_drawn_faces,
		culled_faces = stat_culled_faces,
		clipped_faces = stat_clipped_faces,
		discarded_faces = stat_discarded_faces,
		candidate_fragments = stat_candidate_fragments,
		fragments_occluded = stat_fragments_occluded,
		fragments_shaded = stat_fragments_shaded,
		fragments_discarded = stat_fragments_discarded,
		fragments_drawn = stat_fragments_drawn,
	}
end
]]

local function create_pipeline(options)
	local opt_pixel_aspect_ratio = options.pixel_aspect_ratio or 1
	local opt_layout = options.layout
	local opt_position_attribute = options.position_attribute or 'position'
	local opt_attributes = options.attributes or {}
	local opt_pack_attributes = options.pack_attributes ~= false
	local opt_colour_attribute = options.colour_attribute
	local opt_cull_face = options.cull_face == nil and v3d.CULL_BACK_FACE or options.cull_face
	local opt_depth_store = options.depth_store ~= false
	local opt_depth_test = options.depth_test ~= false
	local opt_fragment_shader = options.fragment_shader or nil
	local opt_statistics = options.statistics or {}
	local stat_measure_total_time = opt_statistics.measure_total_time or false
	local stat_measure_rasterize_time = opt_statistics.measure_rasterize_time or false
	local stat_count_candidate_faces = opt_statistics.count_candidate_faces or false
	local stat_count_drawn_faces = opt_statistics.count_culled_faces or false
	local stat_count_culled_faces = opt_statistics.count_culled_faces or false
	local stat_count_clipped_faces = opt_statistics.count_clipped_faces or false
	local stat_count_discarded_faces = opt_statistics.count_discarded_faces or false
	local stat_count_candidate_fragments = opt_statistics.count_candidate_fragments or false
	local stat_count_fragments_occluded = opt_statistics.count_fragments_occluded or false
	local stat_count_fragments_shaded = opt_statistics.count_fragments_shaded or false
	local stat_count_fragments_discarded = opt_statistics.count_fragments_discarded or false
	local stat_count_fragments_drawn = opt_statistics.count_fragments_drawn or false

	local pipeline = {}
	local uniforms = {}

	--- @type V3DPipelineOptions
	pipeline.options = {
		attributes = opt_attributes,
		colour_attribute = not opt_fragment_shader and opt_colour_attribute or nil,
		cull_face = opt_cull_face,
		depth_store = opt_depth_store,
		depth_test = opt_depth_test,
		fragment_shader = opt_fragment_shader,
		layout = opt_layout,
		pack_attributes = opt_pack_attributes,
		pixel_aspect_ratio = opt_pixel_aspect_ratio,
		position_attribute = opt_position_attribute,
		statistics = {
			measure_total_time = stat_measure_total_time,
			measure_rasterize_time = stat_measure_rasterize_time,
			count_candidate_faces = stat_count_candidate_faces,
			count_drawn_faces = stat_count_drawn_faces,
			count_culled_faces = stat_count_culled_faces,
			count_clipped_faces = stat_count_clipped_faces,
			count_discarded_faces = stat_count_discarded_faces,
			count_candidate_fragments = stat_count_candidate_fragments,
			count_fragments_occluded = stat_count_fragments_occluded,
			count_fragments_shaded = stat_count_fragments_shaded,
			count_fragments_discarded = stat_count_fragments_discarded,
			count_fragments_drawn = stat_count_fragments_drawn,
		}
	}

	local geometry_face_attributes = {}
	local geometry_vertex_attributes = {}
	local interpolate_attributes = {}
	local attributes = {}

	for _, attribute_name in ipairs(opt_attributes) do
		local attribute = opt_layout:get_attribute(attribute_name)
		local attr = {}
		attr.name = attribute.name
		attr.size = attribute.size
		attr.type = attribute.type

		if attribute.type == 'vertex' then
			table.insert(geometry_vertex_attributes, attribute)
			table.insert(interpolate_attributes, attr)
		else
			table.insert(geometry_face_attributes, attribute)
		end
		table.insert(attributes, attr)
	end

	local pipeline_source = RENDER_GEOMETRY_SOURCE
		:gsub('-- #marker RASTERIZE_TRIANGLE_SOURCE', RASTERIZE_TRIANGLE_SOURCE)
		:gsub('-- #marker RASTERIZE_FLAT_TRIANGLE_SOURCE', RASTERIZE_FLAT_TRIANGLE_SOURCE)

	if opt_pack_attributes then -- FRAGMENT_PACKED_PARAMS
		local fpp = ''
		for _, attr in ipairs(attributes) do
			fpp = fpp .. 'local fs_params_' .. attr.name .. '={}\n'
		end
		fpp = fpp .. 'local fs_params = {'
		for _, attr in ipairs(attributes) do
			fpp = fpp .. attr.name .. '=' .. 'fs_params_' .. attr.name .. ','
		end
		fpp = fpp .. '}\n'
		pipeline_source = pipeline_source:gsub('-- #marker FRAGMENT_PACKED_PARAMS', fpp)
	else
		pipeline_source = pipeline_source:gsub('-- #marker FRAGMENT_PACKED_PARAMS', '')
	end

	do -- opt_pixel_aspect_ratio
		pipeline_source = pipeline_source:gsub('opt_pixel_aspect_ratio', opt_pixel_aspect_ratio)
	end

	do -- STAT_TOTAL_TIME

	end

	do -- STAT_RASTERIZE_TIME

	end

	do -- STAT_CANDIDATE_FACE
		pipeline_source = pipeline_source:gsub('--%s*#marker%s+STAT_DRAW_FACE',
			stat_count_drawn_faces and 'stat_drawn_faces = stat_drawn_faces + 1' or '')
	end

	do -- STAT_CANDIDATE_FACE
		pipeline_source = pipeline_source:gsub('--%s*#marker%s+STAT_CANDIDATE_FACE',
			stat_count_candidate_faces and 'stat_candidate_faces = stat_candidate_faces + 1' or '')
	end

	do -- STAT_CULL_FACE
		pipeline_source = pipeline_source:gsub('--%s*#marker%s+STAT_CULL_FACE',
			stat_count_culled_faces and opt_cull_face and 'stat_culled_faces = stat_culled_faces + 1' or '')
	end

	do -- STAT_CLIP_FACE
		pipeline_source = pipeline_source:gsub('--%s*#marker%s+STAT_CLIP_FACE',
			stat_count_clipped_faces and 'stat_clipped_faces = stat_clipped_faces + 1' or '')
	end

	do -- STAT_DISCARD_FACE
		pipeline_source = pipeline_source:gsub('--%s*#marker%s+STAT_DISCARD_FACE',
			stat_count_discarded_faces and 'stat_discarded_faces = stat_discarded_faces + 1' or '')
	end

	do -- POSITION_ASSIGNMENT
		local position_base_offset = opt_layout:get_attribute(opt_position_attribute).offset
		pipeline_source = pipeline_source:gsub(
			'-- #marker POSITION_ASSIGNMENT',
			'local p0x=geometry[vertex_offset+' .. (position_base_offset + 1) .. ']\n' ..
			'local p0y=geometry[vertex_offset+' .. (position_base_offset + 2) .. ']\n' ..
			'local p0z=geometry[vertex_offset+' .. (position_base_offset + 3) .. ']\n' ..
			'local p1x=geometry[vertex_offset+' .. (position_base_offset + opt_layout.vertex_stride + 1) .. ']\n' ..
			'local p1y=geometry[vertex_offset+' .. (position_base_offset + opt_layout.vertex_stride + 2) .. ']\n' ..
			'local p1z=geometry[vertex_offset+' .. (position_base_offset + opt_layout.vertex_stride + 3) .. ']\n' ..
			'local p2x=geometry[vertex_offset+' .. (position_base_offset + opt_layout.vertex_stride * 2 + 1) .. ']\n' ..
			'local p2y=geometry[vertex_offset+' .. (position_base_offset + opt_layout.vertex_stride * 2 + 2) .. ']\n' ..
			'local p2z=geometry[vertex_offset+' .. (position_base_offset + opt_layout.vertex_stride * 2 + 3) .. ']'
		)
	end

	do -- ATTRIBUTE_ASSIGNMENT
		local aa = ''

		for _, attr in ipairs(geometry_vertex_attributes) do
			local base_offset = attr.offset

			for i = 1, attr.size do
				aa = aa .. 'local p0_va_' .. attr.name .. (i - 1) .. '=geometry[vertex_offset+' .. (base_offset + i) .. ']\n'
				        .. 'local p1_va_' .. attr.name .. (i - 1) .. '=geometry[vertex_offset+' .. (base_offset + opt_layout.vertex_stride + i) .. ']\n'
				        .. 'local p2_va_' .. attr.name .. (i - 1) .. '=geometry[vertex_offset+' .. (base_offset + opt_layout.vertex_stride * 2 + i) .. ']\n'
			end
		end

		for _, attr in ipairs(geometry_face_attributes) do
			local base_offset = attr.offset

			for i = 1, attr.size do
				if opt_pack_attributes then
					aa = aa .. 'fs_params_' .. attr.name .. '[' .. i .. ']'
				else
					aa = aa .. 'local fa_' .. attr.name .. (i - 1)
				end
				aa = aa .. '=geometry[face_offset+' .. (base_offset + i) .. ']\n'
			end
		end

		pipeline_source = pipeline_source:gsub('-- #marker ATTRIBUTE_ASSIGNMENT', aa)
	end

	if opt_colour_attribute then -- COLOUR_ASSIGNMENT
		local colour_base_offset = opt_layout:get_attribute(opt_colour_attribute).offset
		pipeline_source = pipeline_source:gsub(
			'-- #marker COLOUR_ASSIGNMENT',
			'local colour=geometry[face_offset+' .. (colour_base_offset + 1) .. ']\n'
		)
	else
		pipeline_source = pipeline_source:gsub('-- #marker COLOUR_ASSIGNMENT', 'local colour=1')
	end

	do -- INCREMENT_OFFSETS
		pipeline_source = pipeline_source:gsub(
			'-- #marker INCREMENT_OFFSETS',
			'vertex_offset = vertex_offset + ' .. (opt_layout.vertex_stride * 3) .. '\n' ..
			'face_offset = face_offset + ' .. opt_layout.face_stride)
	end

	if opt_cull_face then
		pipeline_source = pipeline_source:gsub(
			'-- #marker FACE_CULLING',
			'local d1x = sp1x - sp0x\n' ..
			'local d1y = sp1y - sp0y\n' ..
			'local d1z = sp1z - sp0z\n' ..
			'local d2x = sp2x - sp0x\n' ..
			'local d2y = sp2y - sp0y\n' ..
			'local d2z = sp2z - sp0z\n' ..
			'local cx = d1y*d2z - d1z*d2y\n' ..
			'local cy = d1z*d2x - d1x*d2z\n' ..
			'local cz = d1x*d2y - d1y*d2x\n' ..
			'local d = cx * sp0x + cy * sp0y + cz * sp0z\n' ..
			'cull_face = d * ' .. opt_cull_face .. ' > 0\n')
	else
		pipeline_source = pipeline_source:gsub('-- #marker FACE_CULLING', 'cull_face = false')
	end

	do -- RASTERIZE_TRIANGLE_ATTR_PARAM_DEFAULT
		local rtvpd = ''

		for _, attr in ipairs(interpolate_attributes) do
			for i = 1, attr.size do
				rtvpd = rtvpd .. 'local _ptri_p0_va_' .. attr.name .. (i - 1) .. '=p0_va_' .. attr.name .. (i - 1) .. '\n'
				              .. 'local _ptri_p1_va_' .. attr.name .. (i - 1) .. '=p1_va_' .. attr.name .. (i - 1) .. '\n'
				              .. 'local _ptri_p2_va_' .. attr.name .. (i - 1) .. '=p2_va_' .. attr.name .. (i - 1) .. '\n'
			end
		end

		pipeline_source = pipeline_source:gsub('-- #marker RASTERIZE_TRIANGLE_ATTR_PARAM_DEFAULT', rtvpd)
	end

	do -- VERTEX_ORDERING
		local params = '_ptri_pAx,_ptri_pAy,_ptri_pBx,_ptri_pBy'

		if opt_depth_test or opt_depth_store or #interpolate_attributes > 0 then
			params = params .. ',_ptri_pAw,_ptri_pBw'
		end

		for _, attr in ipairs(interpolate_attributes) do
			for i = 1, attr.size do
				params = params .. ',_ptri_pA_va_' .. attr.name .. (i - 1)
				                .. ',_ptri_pB_va_' .. attr.name .. (i - 1)
			end
		end

		local vo = 'if _ptri_p0y > _ptri_p1y then ' .. params:gsub('A', 0):gsub('B', 1) .. '=' .. params:gsub('A', 1):gsub('B', 0) .. ' end\n'
		        .. 'if _ptri_p1y > _ptri_p2y then ' .. params:gsub('A', 1):gsub('B', 2) .. '=' .. params:gsub('A', 2):gsub('B', 1) .. ' end\n'
		        .. 'if _ptri_p0y > _ptri_p1y then ' .. params:gsub('A', 0):gsub('B', 1) .. '=' .. params:gsub('A', 1):gsub('B', 0) .. ' end\n'

		pipeline_source = pipeline_source:gsub('-- #marker VERTEX_ORDERING', vo)
	end

	do -- MIDPOINT_CALCULATION, MIDPOINT_SWAP
		local calculation = ''
		local swap = ''

		if opt_depth_test or opt_depth_store or #interpolate_attributes > 0 then
			calculation = calculation .. 'local pMw = _ptri_p0w * (1 - f) + _ptri_p2w * f\n'
			swap = swap .. 'pMw, _ptri_p1w = _ptri_p1w, pMw\n'
		end

		for _, attr in ipairs(interpolate_attributes) do
			for i = 1, attr.size do
				local s = attr.name .. (i - 1)
				calculation = calculation .. 'local pM_va_' .. s .. ' = (_ptri_p0_va_' ..s .. ' * _ptri_p0w * (1 - f) + _ptri_p2_va_' .. s .. ' * _ptri_p2w * f) / pMw\n'
				swap = swap .. 'pM_va_' .. s .. ', _ptri_p1_va_' .. s .. ' = _ptri_p1_va_' .. s .. ', pM_va_' .. s .. '\n'
			end
		end

		pipeline_source = pipeline_source:gsub('-- #marker MIDPOINT_CALCULATION', calculation)
		                                 :gsub('-- #marker MIDPOINT_SWAP', swap)
	end

	do -- ROW_CALCULATIONS
		local rc = ''

		if opt_depth_test or opt_depth_store or #interpolate_attributes > 0 then
			rc = rc .. 'local row_total_delta_x = _pflat_tri_right_x - _pflat_tri_left_x + 1\n'
			        .. 'local row_delta_w = (_pflat_tri_right_w - _pflat_tri_left_w) / row_total_delta_x\n'
			        .. 'local row_left_w = _pflat_tri_left_w + (column_min_x - _pflat_tri_left_x) * row_delta_w\n'
		end

		for _, attr in ipairs(interpolate_attributes) do
			for i = 1, attr.size do
				local s = attr.name .. (i - 1)
				rc = rc .. 'local row_delta_va_' .. s .. ' = (_pflat_tri_right_va_' .. s .. '_w - _pflat_tri_left_va_' .. s .. '_w) / row_total_delta_x\n'
				        .. 'local row_left_va_' .. s .. ' = _pflat_tri_left_va_' .. s .. '_w + (column_min_x - _pflat_tri_left_x) * row_delta_va_' .. s .. '\n'
			end
		end

		pipeline_source = pipeline_source:gsub('-- #marker ROW_CALCULATIONS', rc)
	end

	do -- PIXEL_DRAW_ADVANCE
		local pda = ''
		-- count_fragments_shaded
		-- count_fragments_discarded

		if stat_count_candidate_fragments then
			pda = pda .. 'stat_candidate_fragments = stat_candidate_fragments + 1\n'
		end

		for _, attr in ipairs(interpolate_attributes) do
			for i = 1, attr.size do
				local s = attr.name .. (i - 1)
				pda = pda .. 'local fs_p_va_' .. s .. ' = row_left_va_' .. s .. ' / row_left_w\n'
			end
		end

		if opt_depth_test then
			pda = pda .. 'if row_left_w > fb_depth[math_floor(index)] then\n'
		end

		if opt_fragment_shader then
			local fs_params = ''

			if opt_pack_attributes then
				fs_params = fs_params .. ',fs_params'
				for _, attr in ipairs(interpolate_attributes) do
					for i = 1, attr.size do
						pda = pda .. 'fs_params_' .. attr.name .. '[' .. i .. ']=fs_p_va_' .. attr.name .. (i - 1) .. '\n'
					end
				end
			else
				for _, attr in ipairs(attributes) do
					for i = 1, attr.size do
						if attr.type == 'vertex' then
							fs_params = fs_params .. ',fs_p_va_'
						else
							fs_params = fs_params .. ',fa_'
						end
						fs_params = fs_params .. attr.name .. (i - 1)
					end
				end
			end

			pda = pda .. 'local fs_colour = opt_fragment_shader(uniforms' .. fs_params .. ')\n'

			if stat_count_fragments_shaded then
				pda = pda .. 'stat_fragments_shaded = stat_fragments_shaded + 1\n'
			end

			pda = pda .. 'if fs_colour ~= nil then\n'
			          .. 'fb_colour[index] = fs_colour\n'
		else
			pda = pda .. 'fb_colour[index] = colour\n'
		end

		if opt_depth_store then
			pda = pda .. 'fb_depth[index] = row_left_w\n'
		end

		if stat_count_fragments_drawn then
			pda = pda .. 'stat_fragments_drawn = stat_fragments_drawn + 1\n'
		end

		if opt_fragment_shader then
			if stat_count_fragments_discarded then
				pda = pda .. 'stat_fragments_discarded = stat_fragments_discarded + 1\n'
			end
	
			pda = pda .. 'end\n'
		end

		if opt_depth_test then
			if stat_count_fragments_occluded then
				pda = pda .. 'else\n\tstat_fragments_occluded = stat_fragments_occluded + 1\n'
			end
			pda = pda .. 'end\n'
		end

		if opt_depth_test or opt_depth_store or #interpolate_attributes > 0 then
			pda = pda .. 'row_left_w = row_left_w + row_delta_w\n'
		end

		for _, attr in ipairs(interpolate_attributes) do
			for i = 1, attr.size do
				local s = attr.name .. (i - 1)
				pda = pda .. 'row_left_va_' .. s .. '=row_left_va_' .. s .. ' + row_delta_va_' .. s .. '\n'
			end
		end

		pipeline_source = pipeline_source:gsub('-- #marker PIXEL_DRAW_ADVANCE', pda)
	end

	do -- ROW_ADVANCE
		local ra = ''

		if opt_depth_test or opt_depth_store or #interpolate_attributes > 0 then
			ra = ra .. '_pflat_tri_left_w = _pflat_tri_left_w + _pflat_tri_left_gradient_w\n'
			        .. '_pflat_tri_right_w = _pflat_tri_right_w + _pflat_tri_right_gradient_w\n'
		end

		for _, attr in ipairs(interpolate_attributes) do
			for i = 1, attr.size do
				local s = attr.name .. (i - 1)
				ra = ra .. '_pflat_tri_left_va_' .. s .. '_w = _pflat_tri_left_va_' .. s .. '_w + _pflat_tri_left_gradient_va_' .. s .. '_w\n'
				        .. '_pflat_tri_right_va_' .. s .. '_w = _pflat_tri_right_va_' .. s .. '_w + _pflat_tri_right_gradient_va_' .. s .. '_w\n'
			end
		end

		pipeline_source = pipeline_source:gsub('-- #marker ROW_ADVANCE', ra)
	end

	do -- TOP_HALF_CALCULATIONS
		local thc = ''

		if opt_depth_test or opt_depth_store or #interpolate_attributes > 0 then
			thc = thc .. 'local _pflat_tri_left_gradient_w = (pMw - _ptri_p0w) / tri_delta_y\n'
			          .. 'local _pflat_tri_right_gradient_w = (_ptri_p1w - _ptri_p0w) / tri_delta_y\n'
			          .. 'local _pflat_tri_left_w = _ptri_p0w + _pflat_tri_left_gradient_w * tri_projection\n'
			          .. 'local _pflat_tri_right_w = _ptri_p0w + _pflat_tri_right_gradient_w * tri_projection\n'
		end

		for _, attr in ipairs(interpolate_attributes) do
			for i = 1, attr.size do
				local s = attr.name .. (i - 1)
				thc = thc .. 'local _pflat_tri_left_gradient_va_' .. s .. '_w = (pM_va_' .. s .. ' * pMw - _ptri_p0_va_' .. s .. ' * _ptri_p0w) / tri_delta_y\n'
				          .. 'local _pflat_tri_right_gradient_va_' .. s .. '_w = (_ptri_p1_va_' .. s .. ' * _ptri_p1w - _ptri_p0_va_' .. s .. ' * _ptri_p0w) / tri_delta_y\n'
				          .. 'local _pflat_tri_left_va_' .. s .. '_w = _ptri_p0_va_' .. s .. ' * _ptri_p0w + _pflat_tri_left_gradient_va_' .. s .. '_w * tri_projection\n'
				          .. 'local _pflat_tri_right_va_' .. s .. '_w = _ptri_p0_va_' .. s .. ' * _ptri_p0w + _pflat_tri_right_gradient_va_' .. s .. '_w * tri_projection\n'
			end
		end

		pipeline_source = pipeline_source:gsub('-- #marker TOP_HALF_CALCULATIONS', thc)
	end

	do -- BOTTOM_HALF_CALCULATIONS
		local bhc = ''

		if opt_depth_test or opt_depth_store or #interpolate_attributes > 0 then
			bhc = bhc .. 'local _pflat_tri_left_gradient_w = (_ptri_p2w - pMw) / tri_delta_y\n'
			          .. 'local _pflat_tri_right_gradient_w = (_ptri_p2w - _ptri_p1w) / tri_delta_y\n'
			          .. 'local _pflat_tri_left_w = pMw + _pflat_tri_left_gradient_w * tri_projection\n'
			          .. 'local _pflat_tri_right_w = _ptri_p1w + _pflat_tri_right_gradient_w * tri_projection\n'
		end

		for _, attr in ipairs(interpolate_attributes) do
			for i = 1, attr.size do
				local s = attr.name .. (i - 1)
				bhc = bhc .. 'local _pflat_tri_left_gradient_va_' .. s .. '_w = (_ptri_p2_va_' .. s .. ' * _ptri_p2w - pM_va_' .. s .. ' * pMw) / tri_delta_y\n'
				          .. 'local _pflat_tri_right_gradient_va_' .. s .. '_w = (_ptri_p2_va_' .. s .. ' * _ptri_p2w - _ptri_p1_va_' .. s .. ' * _ptri_p1w) / tri_delta_y\n'
				          .. 'local _pflat_tri_left_va_' .. s .. '_w = pM_va_' .. s .. ' * pMw + _pflat_tri_left_gradient_va_' .. s .. '_w * tri_projection\n'
				          .. 'local _pflat_tri_right_va_' .. s .. '_w = _ptri_p1_va_' .. s .. ' * _ptri_p1w + _pflat_tri_right_gradient_va_' .. s .. '_w * tri_projection\n'
			end
		end

		pipeline_source = pipeline_source:gsub('-- #marker BOTTOM_HALF_CALCULATIONS', bhc)
	end

	local f, err = load(pipeline_source, 'pipeline source')

	pipeline.source = pipeline_source
	pipeline.source_error = err

	pipeline.render_geometry = f and f(uniforms, opt_fragment_shader)

	pipeline.set_uniform = function(_, name, value)
		uniforms[name] = value
	end

	pipeline.get_uniform = function(_, name)
		return uniforms[name]
	end

	pipeline.list_uniforms = function(_)
		local t = {}
		for k in pairs(uniforms) do
			t[#t + 1] = k
		end
		return t
	end

	return pipeline
end

local function create_texture_sampler(texture_uniform, width_uniform, height_uniform)
	local math_floor = math.floor

	texture_uniform = texture_uniform or 'u_texture'
	width_uniform = width_uniform or 'u_texture_width'
	height_uniform = height_uniform or 'u_texture_height'

	return function(uniforms, u, v)
		local image = uniforms[texture_uniform]
		local image_width = uniforms[width_uniform]
		local image_height = uniforms[height_uniform]

		local x = math_floor(u * image_width)
		if x < 0 then x = 0 end
		if x >= image_width then x = image_width - 1 end
		local y = math_floor(v * image_height)
		if y < 0 then y = 0 end
		if y >= image_height then y = image_height - 1 end

		local colour = image[y + 1][x + 1]

		if colour == 0 then
			return nil
		end

		return colour
	end
end


--------------------------------------------------------------------------------
--[ Library export ]------------------------------------------------------------
--------------------------------------------------------------------------------


do
	-- This purely exists to bypass the language server being too clever for itself.
	-- It's here so the LS can't work out what's going on so we keep the types and
	-- docstrings from the top of the file rather than adding weird shit from here.
	local function set_library(name, fn)
		local c = v3d
		c[name] = fn
	end

	set_library('create_framebuffer', create_framebuffer)
	set_library('create_framebuffer_subpixel', create_framebuffer_subpixel)
	set_library('create_layout', create_layout)
	set_library('create_geometry_builder', create_geometry_builder)
	set_library('create_debug_cube', create_debug_cube)
	set_library('identity', create_identity_transform)
	set_library('translate', create_translate_transform)
	set_library('scale', create_scale_transform)
	set_library('rotate', create_rotate_transform)
	set_library('camera', create_camera_transform)
	set_library('create_pipeline', create_pipeline)
	set_library('create_texture_sampler', create_texture_sampler)

	set_library('CULL_FRONT_FACE', -1)
	set_library('CULL_BACK_FACE', 1)
	set_library('GEOMETRY_COLOUR', 1)
	set_library('GEOMETRY_UV', 2)
	set_library('GEOMETRY_COLOUR_UV', 3)
	set_library('DEFAULT_LAYOUT', v3d.create_layout()
		:add_vertex_attribute('position', 3, true)
		:add_face_attribute('colour', 1))
	set_library('UV_LAYOUT', v3d.create_layout()
		:add_vertex_attribute('position', 3, true)
		:add_vertex_attribute('uv', 2, true))
	set_library('DEBUG_CUBE_LAYOUT', v3d.create_layout()
		:add_vertex_attribute('position', 3, true)
		:add_vertex_attribute('uv', 2, true)
		:add_face_attribute('colour', 1)
		:add_face_attribute('face_normal', 3)
		:add_face_attribute('face_index', 1)
		:add_face_attribute('side_index', 1)
		:add_face_attribute('side_name', 1))
end

return v3d
