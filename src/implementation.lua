
-- #remove
-- note: this code will be stripped out during the build process, thus removing
--       the error
error 'Cannot use v3d source code, must build the library'
-- #end
--- @type v3d
local v3d = {}


local function v3d_internal_error(message)
	local traceback
	pcall(function()
		traceback = debug and debug.traceback and debug.traceback()
	end)
	error(
		'V3D INTERNAL ERROR: ' .. tostring(message == nil and '' or message) ..
		(traceback and '\n' .. traceback or ''),
		0
	)
end


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
--[ Format functions ]----------------------------------------------------------
--------------------------------------------------------------------------------


local function format_add_attachment(format, name, type, components)
	local new_attachment = {}

	new_attachment.name = name
	new_attachment.type = type
	new_attachment.components = components

	--- @type table
	local new_format = v3d.create_format()

	for i = 1, #format.attachments do
		new_format.attachments[i] = format.attachments[i]
		new_format.attachment_lookup[format.attachments[i].name] = i
	end

	table.insert(new_format.attachments, new_attachment)
	new_format.attachment_lookup[name] = #new_format.attachments

	return new_format
end

local function format_drop_attachment(format, attachment)
	if not format:has_attachment(attachment) then return format end
	local attachment_name = attachment.name or attachment

	local new_format = v3d.create_format()

	for i = 1, #format.attachments do
		local attachment = format.attachments[i]
		if attachment.name ~= attachment_name then
			new_format = format_add_attachment(new_format, attachment.name, attachment.type, attachment.components)
		end
	end

	return new_format
end

local function format_has_attachment(format, attachment)
	if type(attachment) == 'table' then
		local index = format.attachment_lookup[attachment.name]
		if not index then return false end
		return format.attachments[index].type == attachment.type
		   and format.attachments[index].components == attachment.components
	end

	return format.attachment_lookup[attachment] ~= nil
end

local function format_get_attachment(format, name)
	local index = format.attachment_lookup[name]
	return index and format.attachments[index]
end

local function create_format()
	local format = {}

	format.attachments = {}
	format.attachment_lookup = {}

	format.add_attachment = format_add_attachment
	format.drop_attachment = format_drop_attachment
	format.has_attachment = format_has_attachment
	format.get_attachment = format_get_attachment

	return format
end


--------------------------------------------------------------------------------
--[ Framebuffer functions ]-----------------------------------------------------
--------------------------------------------------------------------------------


local attachment_defaults = {
	['palette-index'] = 0,
	['exp-palette-index'] = 1,
	['depth-reciprocal'] = 0,
	['any-numeric'] = 0,
	['any'] = 0,
}

local function framebuffer_get_buffer(fb, attachment)
	return fb.attachment_data[attachment]
end

local function framebuffer_clear(fb, attachment, value)
	local data = fb.attachment_data[attachment]

	if value == nil then
		local a = fb.format:get_attachment(attachment)
		value = attachment_defaults[a.type] or v3d_internal_error('no default for attachment type ' .. a.type)
	end

	for i = 1, fb.width * fb.height do
		data[i] = value
	end
end

local function framebuffer_blit_term_subpixel(fb, term, attachment, dx, dy)
	dx = dx or 0
	dy = dy or 0

	local SUBPIXEL_WIDTH = 2
	local SUBPIXEL_HEIGHT = 3

	local fb_colour, fb_width = fb.attachment_data[attachment], fb.width

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

local function framebuffer_blit_term_subpixel_depth(fb, term, dx, dy, update_palette)
	local math_floor = math.floor

	if update_palette ~= false then
		for i = 0, 15 do
			term.setPaletteColour(2 ^ i, i / 15, i / 15, i / 15)
		end
	end

	-- we're gonna do a hack to swap out the buffers and draw it like normal

	-- TODO: hardcoded attachments
	local fb_depth = fb.attachment_data.depth
	local old_colour = fb.attachment_data.colour
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

	-- TODO: hardcoded attachments
	fb.attachment_data.colour = new_colour
	framebuffer_blit_term_subpixel(fb, term, dx, dy)
	fb.attachment_data.colour = old_colour
end

local function framebuffer_blit_graphics(fb, term, dx, dy)
	local lines = {}
	local index = 1
	-- TODO: hardcoded attachments
	local fb_colour = fb.attachment_data.colour
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

	-- TODO: hardcoded attachments
	local fb_depth = fb.attachment_data.depth
	local old_colour = fb.attachment_data.colour
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

	-- TODO: hardcoded attachments
	fb.attachment_data.colour = new_colour
	framebuffer_blit_graphics(fb, term, dx, dy)
	fb.attachment_data.colour = old_colour
end

local function create_framebuffer(format, width, height)
	local fb = {}

	fb.format = format
	fb.width = width
	fb.height = height
	fb.attachment_data = {}
	fb.get_buffer = framebuffer_get_buffer
	fb.clear = framebuffer_clear
	fb.blit_term_subpixel = framebuffer_blit_term_subpixel
	fb.blit_term_subpixel_depth = framebuffer_blit_term_subpixel_depth
	fb.blit_graphics = framebuffer_blit_graphics
	fb.blit_graphics_depth = framebuffer_blit_graphics_depth

	for i = 1, #format.attachments do
		local attachment = format.attachments[i]
		fb.attachment_data[attachment.name] = {}
		framebuffer_clear(fb, attachment.name)
	end

	return fb
end

local function create_framebuffer_subpixel(format, width, height)
	return create_framebuffer(format, width * 2, height * 3) -- multiply by subpixel dimensions
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

local function geometry_builder_transform(gb, attribute_name, transform, translate)
	local attr_size = gb.layout:get_attribute(attribute_name).size
	local tr_fn = transform.transform

	if translate == nil and attr_size ~= 4 then
		translate = true
	end

	local data = gb.attribute_data[attribute_name]
	local vertex_data = {}

	for i = 1, #data, attr_size do
		local translate_this = translate == nil and data[i + 3] == 1 or translate or false
		vertex_data[1] = data[i]
		vertex_data[2] = data[i + 1]
		vertex_data[3] = data[i + 2]
		local result = tr_fn(transform, vertex_data, translate_this)
		data[i] = result[1]
		data[i + 1] = result[2]
		data[i + 2] = result[3]
	end

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

local function transform_inverse(transform)
	local t = create_identity_transform()

	error 'TODO'

	-- TODO: populate t[1 .. 12] with correct values

	return t
end

local transform_mt = { __mul = transform_combine }

function create_identity_transform()
	local t = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0 }

	t.combine = transform_combine
	t.transform = transform_transform
	t.inverse = transform_inverse

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


local RENDER_GEOMETRY_SOURCE = [[
local upvalue_uniforms, upvalue_opt_fragment_shader = ...
return function(_, geometry, fb, transform, model_transform)
	local uniforms = upvalue_uniforms
	local opt_fragment_shader = upvalue_opt_fragment_shader
	local math = math
	local math_ceil = math.ceil
	local math_floor = math.floor
	-- TODO: hardcoded attachments
	local fb_colour = fb.attachment_data.colour
	local fb_depth = fb.attachment_data.depth
	local fb_width = fb.width
	local fb_width_m1 = fb_width - 1
	local fb_height_m1 = fb.height - 1
	local screen_dx = (fb.width - 1) / 2
	local screen_dy = (fb.height - 1) / 2
	local screen_sy = -(screen_dy - 0.5)
	local screen_sx = ${PIXEL_ASPECT_RATIO} * (screen_dy - 0.5)

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

	-- TODO: implement this properly
	if model_transform then
		transform = transform:combine(model_transform)
	end

	local transform_xx = transform[ 1]
	local transform_xy = transform[ 2]
	local transform_xz = transform[ 3]
	local transform_dx = transform[ 4]
	local transform_yx = transform[ 5]
	local transform_yy = transform[ 6]
	local transform_yz = transform[ 7]
	local transform_dy = transform[ 8]
	local transform_zx = transform[ 9]
	local transform_zy = transform[10]
	local transform_zz = transform[11]
	local transform_dz = transform[12]

	local vertex_offset = geometry.vertex_offset
	local face_offset = 0

	-- #embed FRAGMENT_PACKED_PARAMS

	for _ = 1, geometry.vertices, 3 do
		local p0x=geometry[vertex_offset + ${P0X_OFFSET}]
		local p0y=geometry[vertex_offset + ${P0Y_OFFSET}]
		local p0z=geometry[vertex_offset + ${P0Z_OFFSET}]
		local p1x=geometry[vertex_offset + ${P1X_OFFSET}]
		local p1y=geometry[vertex_offset + ${P1Y_OFFSET}]
		local p1z=geometry[vertex_offset + ${P1Z_OFFSET}]
		local p2x=geometry[vertex_offset + ${P2X_OFFSET}]
		local p2y=geometry[vertex_offset + ${P2Y_OFFSET}]
		local p2z=geometry[vertex_offset + ${P2Z_OFFSET}]

		-- #embed VERTEX_ATTRIBUTE_ASSIGNMENT
		-- #embed FACE_ATTRIBUTE_ASSIGNMENT

		local colour = ${FACE_COLOUR_SNIPPET}

		local transformed_p0x = transform_xx * p0x + transform_xy * p0y + transform_xz * p0z + transform_dx
		local transformed_p0y = transform_yx * p0x + transform_yy * p0y + transform_yz * p0z + transform_dy
		local transformed_p0z = transform_zx * p0x + transform_zy * p0y + transform_zz * p0z + transform_dz

		local transformed_p1x = transform_xx * p1x + transform_xy * p1y + transform_xz * p1z + transform_dx
		local transformed_p1y = transform_yx * p1x + transform_yy * p1y + transform_yz * p1z + transform_dy
		local transformed_p1z = transform_zx * p1x + transform_zy * p1y + transform_zz * p1z + transform_dz

		local transformed_p2x = transform_xx * p2x + transform_xy * p2y + transform_xz * p2z + transform_dx
		local transformed_p2y = transform_yx * p2x + transform_yy * p2y + transform_yz * p2z + transform_dy
		local transformed_p2z = transform_zx * p2x + transform_zy * p2y + transform_zz * p2z + transform_dz

		local cull_face

		-- #embed FACE_CULLING

		-- #increment_statistic candidate_faces

		if not cull_face then
			-- TODO: make this split polygons
			if transformed_p0z <= ${CLIPPING_PLANE} and transformed_p1z <= ${CLIPPING_PLANE} and transformed_p2z <= ${CLIPPING_PLANE} then
				local rasterize_p0_w = -1 / transformed_p0z
				local rasterize_p0_x = screen_dx + transformed_p0x * rasterize_p0_w * screen_sx
				local rasterize_p0_y = screen_dy + transformed_p0y * rasterize_p0_w * screen_sy
				local rasterize_p1_w = -1 / transformed_p1z
				local rasterize_p1_x = screen_dx + transformed_p1x * rasterize_p1_w * screen_sx
				local rasterize_p1_y = screen_dy + transformed_p1y * rasterize_p1_w * screen_sy
				local rasterize_p2_w = -1 / transformed_p2z
				local rasterize_p2_x = screen_dx + transformed_p2x * rasterize_p2_w * screen_sx
				local rasterize_p2_y = screen_dy + transformed_p2y * rasterize_p2_w * screen_sy

				-- #embed TRIANGLE_RASTERIZATION_NOCLIP_VERTEX_ATTRIBUTE_PARAMETERS
				-- #embed TRIANGLE_RASTERIZATION
				-- #increment_statistic drawn_faces
			else
				-- #increment_statistic discarded_faces
			end
		else
			-- #increment_statistic culled_faces
		end

		vertex_offset = vertex_offset + ${VERTEX_STRIDE_3}
		face_offset = face_offset + ${FACE_STRIDE}
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

local FACE_CULLING_EMBED = [[
local d1x = transformed_p1x - transformed_p0x
local d1y = transformed_p1y - transformed_p0y
local d1z = transformed_p1z - transformed_p0z
local d2x = transformed_p2x - transformed_p0x
local d2y = transformed_p2y - transformed_p0y
local d2z = transformed_p2z - transformed_p0z
local cx = d1y*d2z - d1z*d2y
local cy = d1z*d2x - d1x*d2z
local cz = d1x*d2y - d1y*d2x
cull_face = cx * transformed_p0x + cy * transformed_p0y + cz * transformed_p0z ${CULL_FACE_COMPARISON_OPERATOR} 0
]]

local TRIANGLE_RASTERIZATION_EMBED = [[
-- #embed VERTEX_ORDERING

local midpoint_scalar = (rasterize_p1_y - rasterize_p0_y) / (rasterize_p2_y - rasterize_p0_y)
local rasterize_pM_x = rasterize_p0_x * (1 - midpoint_scalar) + rasterize_p2_x * midpoint_scalar

-- #embed MIDPOINT_CALCULATION

if rasterize_pM_x > rasterize_p1_x then
	rasterize_pM_x, rasterize_p1_x = rasterize_p1_x, rasterize_pM_x
	-- #embed MIDPOINT_SWAP
end

local row_top_min = math_floor(rasterize_p0_y + 0.5)
local row_bottom_min = math_floor(rasterize_p1_y + 0.5)
local row_top_max = row_bottom_min - 1
local row_bottom_max = math_ceil(rasterize_p2_y - 0.5)

if row_top_min < 0 then row_top_min = 0 end
if row_bottom_min < 0 then row_bottom_min = 0 end
if row_top_max > fb_height_m1 then row_top_max = fb_height_m1 end
if row_bottom_max > fb_height_m1 then row_bottom_max = fb_height_m1 end

if row_top_min <= row_top_max then
	local tri_dy = rasterize_p1_y - rasterize_p0_y
	if tri_dy > 0 then
		-- #embed FLAT_TRIANGLE_CALCULATIONS(top, p0, p0, pM, p1)

		local row_min_index = row_top_min * fb_width + 1
		local row_max_index = row_top_max * fb_width + 1

		-- #embed FLAT_TRIANGLE_RASTERIZATION
	end
end

if row_bottom_min <= row_bottom_max then
	local tri_dy = rasterize_p2_y - rasterize_p1_y

	if tri_dy > 0 then
		-- #embed FLAT_TRIANGLE_CALCULATIONS(bottom, pM, p1, p2, p2)

		local row_min_index = row_bottom_min * fb_width + 1
		local row_max_index = row_bottom_max * fb_width + 1

		-- #embed FLAT_TRIANGLE_RASTERIZATION
	end
end
]]

local FLAT_TRIANGLE_RASTERIZATION_EMBED = [[
for base_index = row_min_index, row_max_index, fb_width do
	local row_min_column = math_ceil(tri_left_x)
	local row_max_column = math_ceil(tri_right_x)

	-- #embed ROW_CALCULATIONS

	if row_min_column < 0 then row_min_column = 0 end
	if row_max_column > fb_width_m1 then row_max_column = fb_width_m1 end

	for x = row_min_column, row_max_column do
		local index = base_index + x
		-- #increment_statistic candidate_fragments
		-- #embed COLUMN_DRAW_PIXEL_ENTRY
		-- #embed COLUMN_ADVANCE
	end

	tri_left_x = tri_left_x + tri_left_dx_dy
	tri_right_x = tri_right_x + tri_right_dx_dy
	-- #embed ROW_ADVANCE
end
]]

local COLUMN_DRAW_PIXEL_DEPTH_TESTED_EMBED = [[
if row_w > fb_depth[index] then
	-- #embed COLUMN_DRAW_PIXEL_DEPTH_TEST_PASSED
else
	-- #increment_statistic fragments_occluded
end]]

local COLUMN_DRAW_PIXEL_FRAGMENT_SHADER_EMBED = [[
-- #embed FRAGMENT_SHADER_CALCULATE_ATTRIBUTES

local fs_colour = opt_fragment_shader(uniforms${FRAGMENT_SHADER_PARAMETERS})
-- #increment_statistic fragments_shaded
if fs_colour ~= nil then
	fb_colour[index] = fs_colour
	-- #embed COLUMN_DRAW_PIXEL_DEPTH_STORE
	-- #increment_statistic fragments_drawn
else
	-- #increment_statistic fragments_discarded
end]]

local COLUMN_DRAW_PIXEL_FIXED_COLOUR_EMBED = [[
fb_colour[index] = colour
-- #embed COLUMN_DRAW_PIXEL_DEPTH_STORE
-- #increment_statistic fragments_drawn]]

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

	do -- STAT_TOTAL_TIME
		-- TODO
	end

	do -- STAT_RASTERIZE_TIME
		-- TODO
	end

	do -- embeds
		local embeds = {
			FRAGMENT_PACKED_PARAMS = function()
				if not opt_pack_attributes then
					return ''
				end

				local result = ''
				for _, attr in ipairs(attributes) do
					result = result .. 'local fs_params_' .. attr.name .. '={}\n'
				end
				result = result .. 'local fs_params = {'
				for _, attr in ipairs(attributes) do
					result = result .. attr.name .. '=' .. 'fs_params_' .. attr.name .. ','
				end
				result = result .. '}\n'
				return result
			end,
			FACE_CULLING = opt_cull_face and FACE_CULLING_EMBED or '',
			TRIANGLE_RASTERIZATION = TRIANGLE_RASTERIZATION_EMBED,
			FLAT_TRIANGLE_RASTERIZATION = FLAT_TRIANGLE_RASTERIZATION_EMBED,
			VERTEX_ATTRIBUTE_ASSIGNMENT = function()
				local result = ''

				for _, attr in ipairs(geometry_vertex_attributes) do
					for i = 1, attr.size do
						result = result .. 'local p0_va_' .. attr.name .. (i - 1) .. ' = geometry[vertex_offset + ' .. (attr.offset + i) .. ']\n'
						                .. 'local p1_va_' .. attr.name .. (i - 1) .. ' = geometry[vertex_offset + ' .. (attr.offset + opt_layout.vertex_stride + i) .. ']\n'
						                .. 'local p2_va_' .. attr.name .. (i - 1) .. ' = geometry[vertex_offset + ' .. (attr.offset + opt_layout.vertex_stride * 2 + i) .. ']\n'
					end
				end

				return result
			end,
			FACE_ATTRIBUTE_ASSIGNMENT = function()
				local result = ''

				for _, attr in ipairs(geometry_face_attributes) do
					for i = 1, attr.size do
						if opt_pack_attributes then
							result = result .. 'fs_params_' .. attr.name .. '[' .. i .. ']'
						else
							result = result .. 'local fa_' .. attr.name .. (i - 1)
						end
						result = result .. ' = geometry[face_offset+' .. (attr.offset + i) .. ']\n'
					end
				end

				return result
			end,
			TRIANGLE_RASTERIZATION_NOCLIP_VERTEX_ATTRIBUTE_PARAMETERS = function()
				local result = ''

				for _, attr in ipairs(interpolate_attributes) do
					for i = 1, attr.size do
						result = result .. 'local rasterize_p0_va_' .. attr.name .. (i - 1) .. '=p0_va_' .. attr.name .. (i - 1) .. '\n'
						                .. 'local rasterize_p1_va_' .. attr.name .. (i - 1) .. '=p1_va_' .. attr.name .. (i - 1) .. '\n'
						                .. 'local rasterize_p2_va_' .. attr.name .. (i - 1) .. '=p2_va_' .. attr.name .. (i - 1) .. '\n'
					end
				end

				return result
			end,
			VERTEX_ORDERING = function()
				local to_swap = { 'rasterize_pN_x', 'rasterize_pN_y' }

				if opt_depth_test or opt_depth_store or #interpolate_attributes > 0 then
					table.insert(to_swap, 'rasterize_pN_w')
				end

				for _, attr in ipairs(interpolate_attributes) do
					for i = 1, attr.size do
						table.insert(to_swap, 'rasterize_pN_va_' .. attr.name .. (i - 1))
					end
				end

				local function swap_test(a, b)
					local result = 'if rasterize_pA_y > rasterize_pB_y then\n'

					for i = 1, #to_swap do
						local sA = to_swap[i]:gsub('N', 'A')
						local sB = to_swap[i]:gsub('N', 'B')
						result = result .. '\t' .. sA .. ', ' .. sB .. ' = ' .. sB .. ', ' .. sA .. '\n'
					end

					return (result .. 'end'):gsub('A', a):gsub('B', b)
				end

				return swap_test(0, 1) .. '\n' .. swap_test(1, 2) .. '\n' .. swap_test(0, 1)
			end,
			MIDPOINT_CALCULATION = function()
				local calculation = ''

				if opt_depth_test or opt_depth_store or #interpolate_attributes > 0 then
					calculation = calculation .. 'local rasterize_pM_w = rasterize_p0_w * (1 - midpoint_scalar) + rasterize_p2_w * midpoint_scalar\n'
				end

				for _, attr in ipairs(interpolate_attributes) do
					for i = 1, attr.size do
						local s = attr.name .. (i - 1)
						calculation = calculation .. 'local rasterize_pM_va_' .. s .. ' = (rasterize_p0_va_' ..s .. ' * rasterize_p0_w * (1 - midpoint_scalar) + rasterize_p2_va_' .. s .. ' * rasterize_p2_w * midpoint_scalar) / rasterize_pM_w\n'
					end
				end

				return calculation
			end,
			MIDPOINT_SWAP = function()
				local swap = ''

				if opt_depth_test or opt_depth_store or #interpolate_attributes > 0 then
					swap = swap .. 'rasterize_pM_w, rasterize_p1_w = rasterize_p1_w, rasterize_pM_w\n'
				end

				for _, attr in ipairs(interpolate_attributes) do
					for i = 1, attr.size do
						local s = attr.name .. (i - 1)
						swap = swap .. 'rasterize_pM_va_' .. s .. ', rasterize_p1_va_' .. s .. ' = rasterize_p1_va_' .. s .. ', rasterize_pM_va_' .. s .. '\n'
					end
				end

				return swap
			end,
			FLAT_TRIANGLE_CALCULATIONS = function(name, top_left, top_right, bottom_left, bottom_right)
				local result = 'local tri_y_correction = row_' .. name .. '_min + 0.5 - rasterize_' .. top_right .. '_y\n'
				            .. 'local tri_left_dx_dy = (rasterize_' .. bottom_left .. '_x - rasterize_' .. top_left .. '_x) / tri_dy\n'
				            .. 'local tri_right_dx_dy = (rasterize_' .. bottom_right .. '_x - rasterize_' .. top_right .. '_x) / tri_dy\n'
				            .. 'local tri_left_x = rasterize_' .. top_left .. '_x + tri_left_dx_dy * tri_y_correction - 0.5\n'
				            .. 'local tri_right_x = rasterize_' .. top_right .. '_x + tri_right_dx_dy * tri_y_correction - 1.5\n'

				if opt_depth_test or opt_depth_store or #interpolate_attributes > 0 then
					result = result .. 'local tri_left_dw_dy = (rasterize_' .. bottom_left .. '_w - rasterize_' .. top_left .. '_w) / tri_dy\n'
					                .. 'local tri_right_dw_dy = (rasterize_' .. bottom_right .. '_w - rasterize_' .. top_right .. '_w) / tri_dy\n'
					                .. 'local tri_left_w = rasterize_' .. top_left .. '_w + tri_left_dw_dy * tri_y_correction\n'
					                .. 'local tri_right_w = rasterize_' .. top_right .. '_w + tri_right_dw_dy * tri_y_correction\n'
				end

				for _, attr in ipairs(interpolate_attributes) do
					for i = 1, attr.size do
						local s = attr.name .. (i - 1)
						result = result .. 'local tri_left_va_d' .. s .. 'w_dy = (rasterize_' .. bottom_left .. '_va_' .. s .. ' * rasterize_' .. bottom_left .. '_w - rasterize_' .. top_left .. '_va_' .. s .. ' * rasterize_' .. top_left .. '_w) / tri_dy\n'
						                .. 'local tri_right_va_d' .. s .. 'w_dy = (rasterize_' .. bottom_right .. '_va_' .. s .. ' * rasterize_' .. bottom_right .. '_w - rasterize_' .. top_right .. '_va_' .. s .. ' * rasterize_' .. top_right .. '_w) / tri_dy\n'
						                .. 'local tri_left_va_' .. s .. '_w = rasterize_' .. top_left .. '_va_' .. s .. ' * rasterize_' .. top_left .. '_w + tri_left_va_d' .. s .. 'w_dy * tri_y_correction\n'
						                .. 'local tri_right_va_' .. s .. '_w = rasterize_' .. top_right .. '_va_' .. s .. ' * rasterize_' .. top_right .. '_w + tri_right_va_d' .. s .. 'w_dy * tri_y_correction\n'
					end
				end

				return result
			end,
			ROW_CALCULATIONS = function()
				local result = ''

				if opt_depth_test or opt_depth_store or #interpolate_attributes > 0 then
					result = result .. 'local row_x_correction = row_min_column - tri_left_x\n'
					                .. 'local row_dx = tri_right_x - tri_left_x + 1\n' -- TODO: + 1 ???
					                .. 'local row_dw_dx = (tri_right_w - tri_left_w) / row_dx\n'
					                .. 'local row_w = tri_left_w + row_dw_dx * row_x_correction\n'
				end

				for _, attr in ipairs(interpolate_attributes) do
					for i = 1, attr.size do
						local s = attr.name .. (i - 1)
						result = result .. 'local row_va_d' .. s .. 'w_dx = (tri_right_va_' .. s .. '_w - tri_left_va_' .. s .. '_w) / row_dx\n'
						                .. 'local row_va_' .. s .. '_w = tri_left_va_' .. s .. '_w + row_va_d' .. s .. 'w_dx * row_x_correction\n'
					end
				end

				return result
			end,
			FRAGMENT_SHADER_CALCULATE_ATTRIBUTES = function()
				local result = ''

				for _, attr in ipairs(interpolate_attributes) do
					for i = 1, attr.size do
						local s = attr.name .. (i - 1)
						result = result .. 'local fs_p_va_' .. s .. ' = row_va_' .. s .. '_w / row_w\n'

						if opt_pack_attributes then
							result = result .. 'fs_params_' .. attr.name .. '[' .. i .. '] = fs_p_va_' .. attr.name .. (i - 1) .. '\n'
						end
					end
				end

				return result
			end,
			COLUMN_DRAW_PIXEL_DEPTH_TEST_PASSED = opt_fragment_shader and COLUMN_DRAW_PIXEL_FRAGMENT_SHADER_EMBED
			                                                           or COLUMN_DRAW_PIXEL_FIXED_COLOUR_EMBED,
			COLUMN_DRAW_PIXEL_DEPTH_STORE = opt_depth_store and 'fb_depth[index] = row_w\n' or '',
			COLUMN_DRAW_PIXEL_ENTRY = opt_depth_test and COLUMN_DRAW_PIXEL_DEPTH_TESTED_EMBED
			                                          or '-- #embed COLUMN_DRAW_PIXEL_DEPTH_TEST_PASSED\n',
			COLUMN_ADVANCE = function()
				local result = ''

				if opt_depth_test or opt_depth_store or #interpolate_attributes > 0 then
					result = result .. 'row_w = row_w + row_dw_dx\n'
				end

				for _, attr in ipairs(interpolate_attributes) do
					for i = 1, attr.size do
						local s = attr.name .. (i - 1)
						result = result .. 'row_va_' .. s .. '_w = row_va_' .. s .. '_w + row_va_d' .. s .. 'w_dx\n'
					end
				end

				return result
			end,
			ROW_ADVANCE = function()
				local result = ''

				if opt_depth_test or opt_depth_store or #interpolate_attributes > 0 then
					result = result .. 'tri_left_w = tri_left_w + tri_left_dw_dy\n'
					                .. 'tri_right_w = tri_right_w + tri_right_dw_dy\n'
				end

				for _, attr in ipairs(interpolate_attributes) do
					for i = 1, attr.size do
						local s = attr.name .. (i - 1)
						result = result .. 'tri_left_va_' .. s .. '_w = tri_left_va_' .. s .. '_w + tri_left_va_d' .. s .. 'w_dy\n'
						                .. 'tri_right_va_' .. s .. '_w = tri_right_va_' .. s .. '_w + tri_right_va_d' .. s .. 'w_dy\n'
					end
				end

				return result
			end,
		}
		local count

		repeat
			pipeline_source, count = pipeline_source:gsub('(\t+)%-%-%s*#embed%s+([%w_]+)([^\n]*)\n', function(indent, name, params)
				local embed = embeds[name]

				if not embed then
					error(name)
				end

				if type(embed) == 'function' then
					local ps = {}
					for p in params:sub(2, -2):gmatch '[^,]+' do
						table.insert(ps, (p:gsub('^%s+', '', 1):gsub('%s+$', '', 1)))
					end
					embed = embed(table.unpack(ps))
				end

				--- @cast embed string

				return indent .. embed:gsub('\n', '\n' .. indent) .. '\n'
			end)
		until count == 0
	end

	do -- variables
		local position_base_offset = opt_layout:get_attribute(opt_position_attribute).offset
		local face_colour_snippet = '1'

		if opt_colour_attribute then
			local colour_base_offset = opt_layout:get_attribute(opt_colour_attribute).offset
			face_colour_snippet = 'geometry[face_offset+' .. (colour_base_offset + 1) .. ']'
		end

		local replacements = {
			['${PIXEL_ASPECT_RATIO}'] = opt_pixel_aspect_ratio,
			['${P0X_OFFSET}'] = position_base_offset + 1,
			['${P0Y_OFFSET}'] = position_base_offset + 2,
			['${P0Z_OFFSET}'] = position_base_offset + 3,
			['${P1X_OFFSET}'] = position_base_offset + opt_layout.vertex_stride + 1,
			['${P1Y_OFFSET}'] = position_base_offset + opt_layout.vertex_stride + 2,
			['${P1Z_OFFSET}'] = position_base_offset + opt_layout.vertex_stride + 3,
			['${P2X_OFFSET}'] = position_base_offset + opt_layout.vertex_stride * 2 + 1,
			['${P2Y_OFFSET}'] = position_base_offset + opt_layout.vertex_stride * 2 + 2,
			['${P2Z_OFFSET}'] = position_base_offset + opt_layout.vertex_stride * 2 + 3,
			['${FACE_COLOUR_SNIPPET}'] = face_colour_snippet,
			['${VERTEX_STRIDE_3}'] = opt_layout.vertex_stride * 3,
			['${FACE_STRIDE}'] = opt_layout.face_stride,
			['${CULL_FACE_COMPARISON_OPERATOR}'] = opt_cull_face == v3d.CULL_FRONT_FACE and '<' or '>',
			['${CLIPPING_PLANE}'] = '0.0001',
			['${FRAGMENT_SHADER_PARAMETERS}'] = function()
				local fs_params = ''

				if opt_pack_attributes then
					fs_params = fs_params .. ', fs_params'
				else
					for _, attr in ipairs(attributes) do
						for i = 1, attr.size do
							if attr.type == 'vertex' then
								fs_params = fs_params .. ', fs_p_va_'
							else
								fs_params = fs_params .. ', fa_'
							end
							fs_params = fs_params .. attr.name .. (i - 1)
						end
					end
				end

				return fs_params
			end
		}

		pipeline_source = pipeline_source:gsub('%${[%w_]+}', function(name)
			local replacement = replacements[name]

			if type(replacement) == 'function' then
				replacement = replacement()
			end

			return replacement
		end)
	end

	for k, v in pairs(pipeline.options.statistics) do -- statistics
		local name = k:match '^count_(.+)$'
		if name then
			local replace = '--%s*#increment_statistic%s+' .. name
			local replace_with = v and 'stat_' .. name .. ' = stat_' .. name .. ' + 1' or ''
			pipeline_source = pipeline_source:gsub(replace, replace_with)
		end
	end

	pipeline.source = pipeline_source
	pipeline.render_geometry = assert(load(pipeline_source, 'pipeline source'))(uniforms, opt_fragment_shader)

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

	set_library('create_format', create_format)
	set_library('create_layout', create_layout)
	set_library('create_framebuffer', create_framebuffer)
	set_library('create_framebuffer_subpixel', create_framebuffer_subpixel)
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
	set_library('COLOUR_FORMAT', v3d.create_format()
		:add_attachment('colour', 'exp-palette-index', 1))
	set_library('COLOUR_DEPTH_FORMAT', v3d.create_format()
		:add_attachment('colour', 'exp-palette-index', 1)
		:add_attachment('depth', 'depth-reciprocal', 1))
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
