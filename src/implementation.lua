
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


local function framebuffer_clear(fb, colour)
	local fb_colour = fb.colour
	local fb_depth = fb.depth
	for i = 1, fb.width * fb.height do
		fb_colour[i] = colour
		fb_depth[i] = 0
	end
end

local function framebuffer_blit_subpixel(fb, term, dx, dy)
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

local function framebuffer_blit_subpixel_depth(fb, term, dx, dy, update_palette)
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
	framebuffer_blit_subpixel(fb, term, dx, dy)
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
	fb.blit_subpixel = framebuffer_blit_subpixel
	fb.blit_subpixel_depth = framebuffer_blit_subpixel_depth

	framebuffer_clear(fb, 1)

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

	table.insert(layout.attributes, attr)
	layout.attribute_lookup[name] = #layout.attributes

	if type == 'vertex' then
		layout.vertex_stride = layout.vertex_stride + size
	else
		layout.face_stride = layout.face_stride + size
	end

	return layout
end

local function layout_has_attribute(layout, name)
	return layout.attribute_lookup[name] ~= nil
end

local function layout_get_attribute(layout, name)
	local index = layout.attribute_lookup[name]
	return index and layout.attributes[index]
end

local function create_layout(label)
	local layout = {}

	layout.attributes = {}
	layout.attribute_lookup = {}
	layout.vertex_stride = 0
	layout.face_stride = 0

	layout.add_attribute = layout_add_attribute
	layout.has_attribute = layout_has_attribute
	layout.get_attribute = layout_get_attribute

	return layout
end


--------------------------------------------------------------------------------
--[ Geometry functions ]--------------------------------------------------------
--------------------------------------------------------------------------------


local function geometry_to_builder(geometry)
	local gb = v3d.create_geometry_builder(geometry.layout)

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
		:set_data('normal', {
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
--[ Camera functions ]----------------------------------------------------------
--------------------------------------------------------------------------------


local function camera_set_position(camera, x, y, z)
	camera.x = x or camera.x
	camera.y = y or camera.y
	camera.z = z or camera.z
end

local function camera_set_rotation(camera, x, y, z)
	camera.xRotation = x or camera.xRotation
	camera.yRotation = y or camera.yRotation
	camera.zRotation = z or camera.zRotation
end

local function camera_set_fov(camera, fov)
	camera.fov = fov
end

local function create_camera(fov)
	--- @type V3DCamera
	local camera = {}

	camera.fov = fov or math.pi / 6
	camera.x = 0
	camera.y = 0
	camera.z = 0
	camera.yRotation = 0
	camera.xRotation = 0
	camera.zRotation = 0

	camera.set_position = camera_set_position
	camera.set_rotation = camera_set_rotation
	camera.set_fov = camera_set_fov

	return camera
end


--------------------------------------------------------------------------------
--[ Rasterization functions ]---------------------------------------------------
--------------------------------------------------------------------------------


-- #section depth_test depth_store interpolate_uvs enable_fs
local function rasterize_triangle(
	fb_colour, fb_depth,
	fb_width, fb_height_m1,
	p0x, p0y, p0w, p0u, p0v,
	p1x, p1y, p1w, p1u, p1v,
	p2x, p2y, p2w, p2u, p2v,
	fixed_colour,
	fragment_shader, pipeline_uniforms)
	local math_ceil = math.ceil
	local math_floor = math.floor
	local fb_width_m1 = fb_width - 1

	-- see: https://github.com/exerro/v3d/blob/main/raster_visuals/src/main/kotlin/me/exerro/raster_visuals/rasterize.kt
	-- there's an explanation of the algorithm there
	-- this code has been heavily microoptimised so won't perfectly resemble that
	-- this has also had depth testing and UV interpolation added in, so good
	-- luck understanding anything here :/

	-- #if depth_test depth_store interpolate_uvs
	-- #if interpolate_uvs
	if p0y > p1y then p0x, p0y, p0w, p0u, p0v, p1x, p1y, p1w, p1u, p1v = p1x, p1y, p1w, p1u, p1v, p0x, p0y, p0w, p0u, p0v end
	if p1y > p2y then p1x, p1y, p1w, p1u, p1v, p2x, p2y, p2w, p2u, p2v = p2x, p2y, p2w, p2u, p2v, p1x, p1y, p1w, p1u, p1v end
	if p0y > p1y then p0x, p0y, p0w, p0u, p0v, p1x, p1y, p1w, p1u, p1v = p1x, p1y, p1w, p1u, p1v, p0x, p0y, p0w, p0u, p0v end
	-- #else
	if p0y > p1y then p0x, p0y, p0w, p1x, p1y, p1w = p1x, p1y, p1w, p0x, p0y, p0w end
	if p1y > p2y then p1x, p1y, p1w, p2x, p2y, p2w = p2x, p2y, p2w, p1x, p1y, p1w end
	if p0y > p1y then p0x, p0y, p0w, p1x, p1y, p1w = p1x, p1y, p1w, p0x, p0y, p0w end
	-- #end
	-- #else
	if p0y > p1y then p0x, p0y, p1x, p1y = p1x, p1y, p0x, p0y end
	if p1y > p2y then p1x, p1y, p2x, p2y = p2x, p2y, p1x, p1y end
	if p0y > p1y then p0x, p0y, p1x, p1y = p1x, p1y, p0x, p0y end
	-- #end
	if p0y == p2y then return end -- skip early if we have a perfectly flat triangle

	local f = (p1y - p0y) / (p2y - p0y)
	local pMx = p0x * (1 - f) + p2x * f
	-- #if depth_test depth_store interpolate_uvs
	local pMw = p0w * (1 - f) + p2w * f
	-- #end
	-- #if interpolate_uvs
	local pMu = (p0u * p0w * (1 - f) + p2u * p2w * f) / pMw
	local pMv = (p0v * p0w * (1 - f) + p2v * p2w * f) / pMw
	-- #end

	if pMx > p1x then
		pMx, p1x = p1x, pMx
		-- #if depth_test depth_store interpolate_uvs
		pMw, p1w = p1w, pMw
		-- #end
		-- #if interpolate_uvs
		pMu, p1u = p1u, pMu
		pMv, p1v = p1v, pMv
		-- #end
	end

	local rowTopMin = math_floor(p0y + 0.5)
	local rowBottomMin = math_floor(p1y + 0.5)
	local rowTopMax = rowBottomMin - 1
	local rowBottomMax = math_ceil(p2y - 0.5)

	if rowTopMin < 0 then rowTopMin = 0 end
	if rowBottomMin < 0 then rowBottomMin = 0 end
	if rowTopMax > fb_height_m1 then rowTopMax = fb_height_m1 end
	if rowBottomMax > fb_height_m1 then rowBottomMax = fb_height_m1 end

	local function rasterise_flat_triangle(
		triLeftGradientX, triRightGradientX,
		triLeftGradientW, triRightGradientW,
		triLeftGradientUW, triRightGradientUW,
		triLeftGradientVW, triRightGradientVW,
		triLeftX, triRightX,
		triLeftW, triRightW,
		triLeftUW, triRightUW,
		triLeftVW, triRightVW,
		it_a, it_b
	)
		for baseIndex = it_a, it_b, fb_width do
			local columnMinX = math_ceil(triLeftX)
			local columnMaxX = math_ceil(triRightX)
			-- #if depth_test depth_store interpolate_uvs
			local rowTotalDeltaX = triRightX - triLeftX + 1 -- 'cause of awkward optimisations above
			local rowDeltaW = (triRightW - triLeftW) / rowTotalDeltaX
			local rowLeftW = triLeftW + (columnMinX - triLeftX) * rowDeltaW
			-- #end
			-- #if interpolate_uvs
			local rowDeltaU = (triRightUW - triLeftUW) / rowTotalDeltaX
			local rowLeftU = triLeftUW + (columnMinX - triLeftX) * rowDeltaU
			local rowDeltaV = (triRightVW - triLeftVW) / rowTotalDeltaX
			local rowLeftV = triLeftVW + (columnMinX - triLeftX) * rowDeltaV
			-- #end

			if columnMinX < 0 then columnMinX = 0 end
			if columnMaxX > fb_width_m1 then columnMaxX = fb_width_m1 end

			for x = columnMinX, columnMaxX do
				local index = baseIndex + x

				local u, v = 0, 0
				-- #if interpolate_uvs
				u = rowLeftU / rowLeftW
				v = rowLeftV / rowLeftW
				-- #end

				-- #if depth_test
				if rowLeftW > fb_depth[index] then
					-- #if enable_fs
					local fs_colour = fragment_shader(pipeline_uniforms, u, v)
					if fs_colour ~= nil then
						fb_colour[index] = fs_colour
						-- #if depth_store
						fb_depth[index] = rowLeftW
						-- #end
					end
					-- #else
					fb_colour[index] = fixed_colour
					-- #if depth_store
					fb_depth[index] = rowLeftW
					-- #end
					-- #end
				end
				-- #else
				-- #if enable_fs
				local fs_colour = fragment_shader(pipeline_uniforms, 0, 0)
				if fs_colour ~= 0 then
					fb_colour[index] = fs_colour
					-- #if depth_store
					fb_depth[index] = rowLeftW
					-- #end
				end
				-- #else
				fb_colour[index] = fixed_colour
				-- #if depth_store
				fb_depth[index] = rowLeftW
				-- #end
				-- #end
				-- #end

				-- #if depth_test depth_store interpolate_uvs
				rowLeftW = rowLeftW + rowDeltaW
				-- #end
				-- #if interpolate_uvs
				rowLeftU = rowLeftU + rowDeltaU
				rowLeftV = rowLeftV + rowDeltaV
				-- #end
			end

			triLeftX = triLeftX + triLeftGradientX
			triRightX = triRightX + triRightGradientX
			-- #if depth_test depth_store interpolate_uvs
			triLeftW = triLeftW + triLeftGradientW
			triRightW = triRightW + triRightGradientW
			-- #end
			-- #if interpolate_uvs
			triLeftUW = triLeftUW + triLeftGradientUW
			triRightUW = triRightUW + triRightGradientUW
			triLeftVW = triLeftVW + triLeftGradientVW
			triRightVW = triRightVW + triRightGradientVW
			-- #end
		end
	end

	if rowTopMin <= rowTopMax then
		local triDeltaY = p1y - p0y
		local triLeftGradientX = (pMx - p0x) / triDeltaY
		local triRightGradientX = (p1x - p0x) / triDeltaY
		local triLeftGradientW, triRightGradientW
		-- #if depth_test depth_store interpolate_uvs
		triLeftGradientW = (pMw - p0w) / triDeltaY
		triRightGradientW = (p1w - p0w) / triDeltaY
		-- #end
		local triLeftGradientUW, triRightGradientUW
		local triLeftGradientVW, triRightGradientVW
		-- #if interpolate_uvs
		triLeftGradientUW = (pMu * pMw - p0u * p0w) / triDeltaY
		triRightGradientUW = (p1u * p1w - p0u * p0w) / triDeltaY
		triLeftGradientVW = (pMv * pMw - p0v * p0w) / triDeltaY
		triRightGradientVW = (p1v * p1w - p0v * p0w) / triDeltaY
		-- #end

		local triProjection = rowTopMin + 0.5 - p0y
		local triLeftX = p0x + triLeftGradientX * triProjection - 0.5
		local triRightX = p0x + triRightGradientX * triProjection - 1.5
		local triLeftW, triRightW
		-- #if depth_test depth_store interpolate_uvs
		triLeftW = p0w + triLeftGradientW * triProjection
		triRightW = p0w + triRightGradientW * triProjection
		-- #end
		local triLeftUW, triRightUW
		local triLeftVW, triRightVW
		-- #if interpolate_uvs
		triLeftUW = p0u * p0w + triLeftGradientUW * triProjection
		triRightUW = p0u * p0w + triRightGradientUW * triProjection
		triLeftVW = p0v * p0w + triLeftGradientVW * triProjection
		triRightVW = p0v * p0w + triRightGradientVW * triProjection
		-- #end

		local it_a, it_b = rowTopMin * fb_width + 1, rowTopMax * fb_width + 1

		rasterise_flat_triangle(
			triLeftGradientX, triRightGradientX,
			triLeftGradientW, triRightGradientW,
			triLeftGradientUW, triRightGradientUW,
			triLeftGradientVW, triRightGradientVW,
			triLeftX, triRightX,
			triLeftW, triRightW,
			triLeftUW, triRightUW,
			triLeftVW, triRightVW,
			it_a, it_b)
	end

	if rowBottomMin <= rowBottomMax then
		local triDeltaY = p2y - p1y
		local triLeftGradientX = (p2x - pMx) / triDeltaY
		local triRightGradientX = (p2x - p1x) / triDeltaY
		local triLeftGradientW, triRightGradientW
		-- #if depth_test depth_store interpolate_uvs
		triLeftGradientW = (p2w - pMw) / triDeltaY
		triRightGradientW = (p2w - p1w) / triDeltaY
		-- #end
		local triLeftGradientUW, triRightGradientUW
		local triLeftGradientVW, triRightGradientVW
		-- #if interpolate_uvs
		triLeftGradientUW = (p2u * p2w - pMu * pMw) / triDeltaY
		triRightGradientUW = (p2u * p2w - p1u * p1w) / triDeltaY
		triLeftGradientVW = (p2v * p2w - pMv * pMw) / triDeltaY
		triRightGradientVW = (p2v * p2w - p1v * p1w) / triDeltaY
		-- #end

		local triProjection = rowBottomMin + 0.5 - p1y
		local triLeftX = pMx + triLeftGradientX * triProjection - 0.5
		local triRightX = p1x + triRightGradientX * triProjection - 1.5
		local triLeftW, triRightW
		-- #if depth_test depth_store interpolate_uvs
		triLeftW = pMw + triLeftGradientW * triProjection
		triRightW = p1w + triRightGradientW * triProjection
		-- #end
		local triLeftUW, triRightUW
		local triLeftVW, triRightVW
		-- #if interpolate_uvs
		triLeftUW = pMu * pMw + triLeftGradientUW * triProjection
		triRightUW = p1u * p1w + triRightGradientUW * triProjection
		triLeftVW = pMv * pMw + triLeftGradientVW * triProjection
		triRightVW = p1v * p1w + triRightGradientVW * triProjection
		-- #end

		local it_a, it_b = rowBottomMin * fb_width + 1, rowBottomMax * fb_width + 1

		rasterise_flat_triangle(
			triLeftGradientX, triRightGradientX,
			triLeftGradientW, triRightGradientW,
			triLeftGradientUW, triRightGradientUW,
			triLeftGradientVW, triRightGradientVW,
			triLeftX, triRightX,
			triLeftW, triRightW,
			triLeftUW, triRightUW,
			triLeftVW, triRightVW,
			it_a, it_b)
	end
end
-- #endsection

local function create_pipeline(options)
	--- @cast options V3DPipelineOptions
	local opt_pixel_aspect_ratio = options.pixel_aspect_ratio or 1
	local opt_layout = options.layout
	local opt_position_attribute = options.position_attribute or 'position'
	local opt_interpolate_attribute = options.interpolate_attribute
	local opt_colour_attribute = options.colour_attribute
	local opt_cull_face = options.cull_face == nil and v3d.CULL_BACK_FACE or options.cull_face
	-- used by the #select below
	--- @diagnostic disable-next-line: unused-local
	local opt_depth_store = options.depth_store == nil or options.depth_store
	-- used by the #select below
	--- @diagnostic disable-next-line: unused-local
	local opt_depth_test = options.depth_test == nil or options.depth_test
	local opt_fragment_shader = options.fragment_shader or nil

	local vertex_stride = opt_layout.vertex_stride
	local face_stride = opt_layout.face_stride
	local position_local_offset = opt_layout:get_attribute(opt_position_attribute).offset or 0
	local interpolate_local_offset = opt_interpolate_attribute and opt_layout:get_attribute(opt_interpolate_attribute).offset or 0
	local colour_local_offset = opt_colour_attribute and opt_layout:get_attribute(opt_colour_attribute).offset or 0

	--- @type V3DPipeline
	local pipeline = {}
	local uniforms = {}

	local rasterize_triangle_fn = rasterize_triangle
	-- #select rasterize_triangle_fn rasterize_triangle
	-- #select-param depth_test opt_depth_test
	-- #select-param depth_store opt_depth_store
	-- #select-param interpolate_uvs opt_interpolate_attribute
	-- #select-param enable_fs opt_fragment_shader

	local function render_geometry(_, geometry, fb, camera)
		--- @cast geometry V3DGeometry2
		local clipping_plane = -0.0001
		local pxd = (fb.width - 1) / 2
		local pyd = (fb.height - 1) / 2
		local pxs = pyd
		local pys = -pyd
		local fb_colour, fb_width = fb.colour, fb.width
		local fb_depth = fb.depth
		local fb_height_m1 = fb.height - 1
		local math_sin, math_cos = math.sin, math.cos

		local sinX = math_sin(-camera.xRotation)
		local sinY = math_sin(camera.yRotation)
		local sinZ = math_sin(-camera.zRotation)
		local cosX = math_cos(-camera.xRotation)
		local cosY = math_cos(camera.yRotation)
		local cosZ = math_cos(-camera.zRotation)
		local scale_y = 1 / math.tan(camera.fov)
		local scale_x = scale_y * opt_pixel_aspect_ratio

		scale_x = scale_x * pxs
		scale_y = scale_y * pys

		local fxx = cosY*cosZ+sinX*sinY*sinZ
		local fxy = cosX*sinZ
		local fxz = -sinY*cosZ + sinX*cosY*sinZ
		local fyx = -cosY*sinZ + sinX*sinY*cosZ
		local fyy = cosX*cosZ
		local fyz = sinY*sinZ + sinX*cosY*cosZ
		local fzx = cosX*sinY
		local fzy = -sinX
		local fzz = cosX*cosY
		local fdx = -camera.x
		local fdy = -camera.y
		local fdz = -camera.z

		local position_index = position_local_offset + geometry.vertex_offset + 1
		local interpolate_index = interpolate_local_offset + geometry.vertex_offset + 1
		local colour_index = colour_local_offset + 1
		local position_max_offset = geometry.vertex_offset + geometry.vertices * opt_layout.vertex_stride
		local faceID = 0

		while position_index <= position_max_offset do
			faceID = faceID + 1

			local p0x = geometry[position_index]
			local p0y = geometry[position_index + 1]
			local p0z = geometry[position_index + 2]
			position_index = position_index + vertex_stride
			local p1x = geometry[position_index]
			local p1y = geometry[position_index + 1]
			local p1z = geometry[position_index + 2]
			position_index = position_index + vertex_stride
			local p2x = geometry[position_index]
			local p2y = geometry[position_index + 1]
			local p2z = geometry[position_index + 2]
			position_index = position_index + vertex_stride
			local colour

			if opt_colour_attribute then
				colour = geometry[colour_index]
				colour_index = colour_index + face_stride
			end

			local p0u, p0v, p1u, p1v, p2u, p2v

			if opt_interpolate_attribute then
				p0u = geometry[interpolate_index]
				p0v = geometry[interpolate_index + 1]
				interpolate_index = interpolate_index + vertex_stride
				p1u = geometry[interpolate_index]
				p1v = geometry[interpolate_index + 1]
				interpolate_index = interpolate_index + vertex_stride
				p2u = geometry[interpolate_index]
				p2v = geometry[interpolate_index + 1]
				interpolate_index = interpolate_index + vertex_stride
			end

			p0x = p0x + fdx
			p0y = p0y + fdy
			p0z = p0z + fdz

			p1x = p1x + fdx
			p1y = p1y + fdy
			p1z = p1z + fdz

			p2x = p2x + fdx
			p2y = p2y + fdy
			p2z = p2z + fdz

			local cull_face = false

			if opt_cull_face then
				local d1x = p1x - p0x
				local d1y = p1y - p0y
				local d1z = p1z - p0z
				local d2x = p2x - p0x
				local d2y = p2y - p0y
				local d2z = p2z - p0z
				local cx = d1y*d2z - d1z*d2y
				local cy = d1z*d2x - d1x*d2z
				local cz = d1x*d2y - d1y*d2x
				local d = cx * p0x + cy * p0y + cz * p0z
				cull_face = d * opt_cull_face > 0
			end

			if not cull_face then
				p0x, p0y, p0z = fxx * p0x + fxy * p0y + fxz * p0z
								, fyx * p0x + fyy * p0y + fyz * p0z
								, fzx * p0x + fzy * p0y + fzz * p0z

				p1x, p1y, p1z = fxx * p1x + fxy * p1y + fxz * p1z
								, fyx * p1x + fyy * p1y + fyz * p1z
								, fzx * p1x + fzy * p1y + fzz * p1z

				p2x, p2y, p2z = fxx * p2x + fxy * p2y + fxz * p2z
								, fyx * p2x + fyy * p2y + fyz * p2z
								, fzx * p2x + fzy * p2y + fzz * p2z

				-- TODO: make this split polygons
				if p0z <= clipping_plane and p1z <= clipping_plane and p2z <= clipping_plane then
					local p0w = -1 / p0z
					local p1w = -1 / p1z
					local p2w = -1 / p2z

					p0x = pxd + p0x * scale_x * p0w
					p0y = pyd + p0y * scale_y * p0w
					p1x = pxd + p1x * scale_x * p1w
					p1y = pyd + p1y * scale_y * p1w
					p2x = pxd + p2x * scale_x * p2w
					p2y = pyd + p2y * scale_y * p2w

					uniforms.u_faceID = faceID
					uniforms.u_face_colour = colour
					rasterize_triangle_fn(fb_colour, fb_depth, fb_width, fb_height_m1, p0x, p0y, p0w, p0u, p0v, p1x, p1y, p1w, p1u, p1v, p2x, p2y, p2w, p2u, p2v, colour, opt_fragment_shader, uniforms)
				end
			end
		end
	end

	-- magical hacks to get around the language server!
	select(1, pipeline).render_geometry = render_geometry

	select(1, pipeline).set_uniform = function(_, name, value)
		uniforms[name] = value
	end

	select(1, pipeline).get_uniform = function(_, name)
		return uniforms[name]
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
		if x == image_width then x = image_width - 1 end
		local y = math_floor(v * image_height)
		if y == image_height then y = image_height - 1 end

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
	set_library('create_camera', create_camera)
	set_library('create_pipeline', create_pipeline)
	set_library('create_texture_sampler', create_texture_sampler)

	set_library('CULL_FRONT_FACE', -1)
	set_library('CULL_BACK_FACE', 1)
	set_library('GEOMETRY_COLOUR', 1)
	set_library('GEOMETRY_UV', 2)
	set_library('GEOMETRY_COLOUR_UV', 3)
	set_library('DEFAULT_LAYOUT', v3d.create_layout()
		:add_attribute('position', 3, 'vertex', true)
		:add_attribute('colour', 1, 'face', false))
	set_library('UV_LAYOUT', v3d.create_layout()
		:add_attribute('position', 3, 'vertex', true)
		:add_attribute('uv', 2, 'vertex', true))
	set_library('DEBUG_CUBE_LAYOUT', v3d.create_layout()
		:add_attribute('position', 3, 'vertex', true)
		:add_attribute('uv', 3, 'vertex', true)
		:add_attribute('colour', 1, 'face', false)
		:add_attribute('normal', 3, 'face', true)
		:add_attribute('face_index', 1, 'face', false)
		:add_attribute('side_index', 1, 'face', false)
		:add_attribute('side_name', 1, 'face', false))
end

return v3d
