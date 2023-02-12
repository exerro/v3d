
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


local RASTERIZE_FLAT_TRIANGLE_SOURCE = [[
for baseIndex = _pflat_it_a, _pflat_it_b, fb_width do
	local columnMinX = math_ceil(_pflat_triLeftX)
	local columnMaxX = math_ceil(_pflat_triRightX)

	-- #marker ROW_CALCULATIONS

	if columnMinX < 0 then columnMinX = 0 end
	if columnMaxX > fb_width_m1 then columnMaxX = fb_width_m1 end

	for x = columnMinX, columnMaxX do
		local index = baseIndex + x
		-- #marker PIXEL_DRAW_ADVANCE
	end

	_pflat_triLeftX = _pflat_triLeftX + _pflat_triLeftGradientX
	_pflat_triRightX = _pflat_triRightX + _pflat_triRightGradientX
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

local rowTopMin = math_floor(_ptri_p0y + 0.5)
local rowBottomMin = math_floor(_ptri_p1y + 0.5)
local rowTopMax = rowBottomMin - 1
local rowBottomMax = math_ceil(_ptri_p2y - 0.5)

if rowTopMin < 0 then rowTopMin = 0 end
if rowBottomMin < 0 then rowBottomMin = 0 end
if rowTopMax > fb_height_m1 then rowTopMax = fb_height_m1 end
if rowBottomMax > fb_height_m1 then rowBottomMax = fb_height_m1 end

if rowTopMin <= rowTopMax then
	local tri_delta_y = _ptri_p1y - _ptri_p0y
	local _pflat_triLeftGradientX = (pMx - _ptri_p0x) / tri_delta_y
	local _pflat_triRightGradientX = (_ptri_p1x - _ptri_p0x) / tri_delta_y
	local tri_projection = rowTopMin + 0.5 - _ptri_p0y
	local _pflat_triLeftX = _ptri_p0x + _pflat_triLeftGradientX * tri_projection - 0.5
	local _pflat_triRightX = _ptri_p0x + _pflat_triRightGradientX * tri_projection - 1.5
	-- #marker TOP_HALF_CALCULATIONS

	local _pflat_it_a, _pflat_it_b = rowTopMin * fb_width + 1, rowTopMax * fb_width + 1

	-- #marker RASTERIZE_FLAT_TRIANGLE_SOURCE
end

if rowBottomMin <= rowBottomMax then
	local tri_delta_y = _ptri_p2y - _ptri_p1y
	local _pflat_triLeftGradientX = (_ptri_p2x - pMx) / tri_delta_y
	local _pflat_triRightGradientX = (_ptri_p2x - _ptri_p1x) / tri_delta_y
	local tri_projection = rowBottomMin + 0.5 - _ptri_p1y
	local _pflat_triLeftX = pMx + _pflat_triLeftGradientX * tri_projection - 0.5
	local _pflat_triRightX = _ptri_p1x + _pflat_triRightGradientX * tri_projection - 1.5
	-- #marker BOTTOM_HALF_CALCULATIONS

	local _pflat_it_a, _pflat_it_b = rowBottomMin * fb_width + 1, rowBottomMax * fb_width + 1

	-- #marker RASTERIZE_FLAT_TRIANGLE_SOURCE
end
]]

local RENDER_GEOMETRY_SOURCE = [[
local uniforms, opt_fragment_shader = ...
return function(_, geometry, fb, camera)
	local uniforms = uniforms
	local opt_fragment_shader = opt_fragment_shader
	local math = math
	local math_sin, math_cos = math.sin, math.cos
	local math_ceil, math_floor = math.ceil, math.floor
	local fb_colour, fb_depth, fb_width = fb.colour, fb.depth, fb.width
	local clipping_plane = -0.0001
	local fb_width_m1, fb_height_m1 = fb_width - 1, fb.height - 1
	local pxd = (fb.width - 1) / 2
	local pyd = (fb.height - 1) / 2
	local pxs = pyd
	local pys = -pyd

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

	local fxx = (cosY*cosZ+sinX*sinY*sinZ)*scale_x
	local fxy = (cosX*sinZ)*scale_x
	local fxz = (-sinY*cosZ + sinX*cosY*sinZ)*scale_x
	local fyx = (-cosY*sinZ + sinX*sinY*cosZ)*scale_y
	local fyy = (cosX*cosZ)*scale_y
	local fyz = (sinY*sinZ + sinX*cosY*cosZ)*scale_y
	local fzx = cosX*sinY
	local fzy = -sinX
	local fzz = cosX*cosY
	local fdx = -camera.x
	local fdy = -camera.y
	local fdz = -camera.z

	local vertex_offset = geometry.vertex_offset
	local face_offset = 0

	for faceID = 1, math.max(geometry.faces, geometry.vertices / 3) do
		-- #marker POSITION_ASSIGNMENT
		-- #marker INTERPOLATE_ASSIGNMENT
		-- #marker COLOUR_ASSIGNMENT
		-- #marker INCREMENT_OFFSETS

		p0x = p0x + fdx; p0y = p0y + fdy; p0z = p0z + fdz
		p1x = p1x + fdx; p1y = p1y + fdy; p1z = p1z + fdz
		p2x = p2x + fdx; p2y = p2y + fdy; p2z = p2z + fdz

		local cull_face

		-- #marker FACE_CULLING

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

				p0x = pxd + p0x * p0w
				p0y = pyd + p0y * p0w
				p1x = pxd + p1x * p1w
				p1y = pyd + p1y * p1w
				p2x = pxd + p2x * p2w
				p2y = pyd + p2y * p2w

				uniforms.u_faceID = faceID
				uniforms.u_face_colour = colour
				local _ptri_p0x = p0x
				local _ptri_p0y = p0y
				local _ptri_p0w = p0w
				local _ptri_p0u = p0u
				local _ptri_p0v = p0v
				local _ptri_p1x = p1x
				local _ptri_p1y = p1y
				local _ptri_p1w = p1w
				local _ptri_p1u = p1u
				local _ptri_p1v = p1v
				local _ptri_p2x = p2x
				local _ptri_p2y = p2y
				local _ptri_p2w = p2w
				local _ptri_p2u = p2u
				local _ptri_p2v = p2v
				-- #marker RASTERIZE_TRIANGLE_SOURCE
			end
		end
	end
end
]]

local function create_pipeline(options)
	local opt_pixel_aspect_ratio = options.pixel_aspect_ratio or 1
	local opt_layout = options.layout
	local opt_position_attribute = options.position_attribute or 'position'
	local opt_interpolate_attribute = options.interpolate_attribute
	local opt_colour_attribute = options.colour_attribute
	local opt_cull_face = options.cull_face == nil and v3d.CULL_BACK_FACE or options.cull_face
	local opt_depth_store = options.depth_store == nil or options.depth_store
	local opt_depth_test = options.depth_test == nil or options.depth_test
	local opt_fragment_shader = options.fragment_shader or nil

	local pipeline = {}
	local uniforms = {}

	local pipeline_source = RENDER_GEOMETRY_SOURCE
		:gsub('-- #marker RASTERIZE_TRIANGLE_SOURCE', RASTERIZE_TRIANGLE_SOURCE)
		:gsub('-- #marker RASTERIZE_FLAT_TRIANGLE_SOURCE', RASTERIZE_FLAT_TRIANGLE_SOURCE)

	do -- opt_pixel_aspect_ratio
		pipeline_source = pipeline_source:gsub('opt_pixel_aspect_ratio', opt_pixel_aspect_ratio)
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

	if opt_interpolate_attribute then -- INTERPOLATE_ASSIGNMENT
		local uv_base_offset = opt_layout:get_attribute(opt_interpolate_attribute).offset
		pipeline_source = pipeline_source:gsub(
			'-- #marker INTERPOLATE_ASSIGNMENT',
			'local p0u=geometry[vertex_offset+' .. (uv_base_offset + 1) .. ']\n' ..
			'local p0v=geometry[vertex_offset+' .. (uv_base_offset + 2) .. ']\n' ..
			'local p1u=geometry[vertex_offset+' .. (uv_base_offset + opt_layout.vertex_stride + 1) .. ']\n' ..
			'local p1v=geometry[vertex_offset+' .. (uv_base_offset + opt_layout.vertex_stride + 2) .. ']\n' ..
			'local p2u=geometry[vertex_offset+' .. (uv_base_offset + opt_layout.vertex_stride * 2 + 1) .. ']\n' ..
			'local p2v=geometry[vertex_offset+' .. (uv_base_offset + opt_layout.vertex_stride * 2 + 2) .. ']\n'
		)
	else
		pipeline_source = pipeline_source:gsub('-- #marker INTERPOLATE_ASSIGNMENT', '')
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

	do -- *_offset
		pipeline_source = pipeline_source:gsub(
			'-- #marker INCREMENT_OFFSETS',
			'vertex_offset = vertex_offset + ' .. (opt_layout.vertex_stride * 3) .. '\n' ..
			'face_offset = face_offset + ' .. opt_layout.face_stride)
	end

	if opt_cull_face then
		pipeline_source = pipeline_source:gsub(
			'-- #marker FACE_CULLING',
			'local d1x = p1x - p0x\n' ..
			'local d1y = p1y - p0y\n' ..
			'local d1z = p1z - p0z\n' ..
			'local d2x = p2x - p0x\n' ..
			'local d2y = p2y - p0y\n' ..
			'local d2z = p2z - p0z\n' ..
			'local cx = d1y*d2z - d1z*d2y\n' ..
			'local cy = d1z*d2x - d1x*d2z\n' ..
			'local cz = d1x*d2y - d1y*d2x\n' ..
			'local d = cx * p0x + cy * p0y + cz * p0z\n' ..
			'cull_face = d * ' .. opt_cull_face .. ' > 0\n')
	else
		pipeline_source = pipeline_source:gsub('-- #marker FACE_CULLING', 'cull_face = false')
	end

	do -- VERTEX_ORDERING
		local result

		if opt_interpolate_attribute then
			result = 'if _ptri_p0y > _ptri_p1y then _ptri_p0x, _ptri_p0y, _ptri_p0w, _ptri_p0u, _ptri_p0v, _ptri_p1x, _ptri_p1y, _ptri_p1w, _ptri_p1u, _ptri_p1v = _ptri_p1x, _ptri_p1y, _ptri_p1w, _ptri_p1u, _ptri_p1v, _ptri_p0x, _ptri_p0y, _ptri_p0w, _ptri_p0u, _ptri_p0v end\n' ..
			         'if _ptri_p1y > _ptri_p2y then _ptri_p1x, _ptri_p1y, _ptri_p1w, _ptri_p1u, _ptri_p1v, _ptri_p2x, _ptri_p2y, _ptri_p2w, _ptri_p2u, _ptri_p2v = _ptri_p2x, _ptri_p2y, _ptri_p2w, _ptri_p2u, _ptri_p2v, _ptri_p1x, _ptri_p1y, _ptri_p1w, _ptri_p1u, _ptri_p1v end\n' ..
			         'if _ptri_p0y > _ptri_p1y then _ptri_p0x, _ptri_p0y, _ptri_p0w, _ptri_p0u, _ptri_p0v, _ptri_p1x, _ptri_p1y, _ptri_p1w, _ptri_p1u, _ptri_p1v = _ptri_p1x, _ptri_p1y, _ptri_p1w, _ptri_p1u, _ptri_p1v, _ptri_p0x, _ptri_p0y, _ptri_p0w, _ptri_p0u, _ptri_p0v end\n'
		elseif opt_depth_store or opt_depth_test then
			result = 'if _ptri_p0y > _ptri_p1y then _ptri_p0x, _ptri_p0y, _ptri_p0w, _ptri_p1x, _ptri_p1y, _ptri_p1w = _ptri_p1x, _ptri_p1y, _ptri_p1w, _ptri_p0x, _ptri_p0y, _ptri_p0w end\n' ..
			         'if _ptri_p1y > _ptri_p2y then _ptri_p1x, _ptri_p1y, _ptri_p1w, _ptri_p2x, _ptri_p2y, _ptri_p2w = _ptri_p2x, _ptri_p2y, _ptri_p2w, _ptri_p1x, _ptri_p1y, _ptri_p1w end\n' ..
			         'if _ptri_p0y > _ptri_p1y then _ptri_p0x, _ptri_p0y, _ptri_p0w, _ptri_p1x, _ptri_p1y, _ptri_p1w = _ptri_p1x, _ptri_p1y, _ptri_p1w, _ptri_p0x, _ptri_p0y, _ptri_p0w end\n'
		else
			result = 'if _ptri_p0y > _ptri_p1y then _ptri_p0x, _ptri_p0y, _ptri_p1x, _ptri_p1y = _ptri_p1x, _ptri_p1y, _ptri_p0x, _ptri_p0y end\n' ..
			         'if _ptri_p1y > _ptri_p2y then _ptri_p1x, _ptri_p1y, _ptri_p2x, _ptri_p2y = _ptri_p2x, _ptri_p2y, _ptri_p1x, _ptri_p1y end\n' ..
			         'if _ptri_p0y > _ptri_p1y then _ptri_p0x, _ptri_p0y, _ptri_p1x, _ptri_p1y = _ptri_p1x, _ptri_p1y, _ptri_p0x, _ptri_p0y end\n'
		end

		pipeline_source = pipeline_source:gsub('-- #marker VERTEX_ORDERING', result)
	end

	do -- MIDPOINT_CALCULATION, MIDPOINT_SWAP
		local calculation = ''
		local swap = ''

		if opt_depth_test or opt_depth_store or opt_interpolate_attribute then
			calculation = calculation .. 'local pMw = _ptri_p0w * (1 - f) + _ptri_p2w * f\n'
			swap = swap .. 'pMw, _ptri_p1w = _ptri_p1w, pMw\n'
		end

		if opt_interpolate_attribute then
			calculation = calculation .. 'local pMu = (_ptri_p0u * _ptri_p0w * (1 - f) + _ptri_p2u * _ptri_p2w * f) / pMw\n'
			calculation = calculation .. 'local pMv = (_ptri_p0v * _ptri_p0w * (1 - f) + _ptri_p2v * _ptri_p2w * f) / pMw\n'
			swap = swap .. 'pMu, _ptri_p1u = _ptri_p1u, pMu\n'
			swap = swap .. 'pMv, _ptri_p1v = _ptri_p1v, pMv\n'
		end

		pipeline_source = pipeline_source:gsub('-- #marker MIDPOINT_CALCULATION', calculation)
		                                 :gsub('-- #marker MIDPOINT_SWAP', swap)
	end

	do -- ROW_CALCULATIONS
		local calculations = ''

		if opt_depth_test or opt_depth_store or opt_interpolate_attribute then
			calculations = calculations .. 'local rowTotalDeltaX = _pflat_triRightX - _pflat_triLeftX + 1\n'
			                            .. 'local rowDeltaW = (_pflat_triRightW - _pflat_triLeftW) / rowTotalDeltaX\n'
			                            .. 'local rowLeftW = _pflat_triLeftW + (columnMinX - _pflat_triLeftX) * rowDeltaW\n'
		end

		if opt_interpolate_attribute then
			calculations = calculations .. 'local rowDeltaU = (_pflat_triRightUW - _pflat_triLeftUW) / rowTotalDeltaX\n'
			                            .. 'local rowLeftU = _pflat_triLeftUW + (columnMinX - _pflat_triLeftX) * rowDeltaU\n'
			                            .. 'local rowDeltaV = (_pflat_triRightVW - _pflat_triLeftVW) / rowTotalDeltaX\n'
			                            .. 'local rowLeftV = _pflat_triLeftVW + (columnMinX - _pflat_triLeftX) * rowDeltaV\n'
		end

		pipeline_source = pipeline_source:gsub('-- #marker ROW_CALCULATIONS', calculations)
	end

	do -- PIXEL_DRAW_ADVANCE
		local pda = ''

		if opt_interpolate_attribute then
			pda = pda .. 'local u = rowLeftU / rowLeftW\n'
			          .. 'local v = rowLeftV / rowLeftW\n'
		else
			pda = pda .. 'local u, v = 0, 0\n'
		end

		if opt_depth_test then
			pda = pda .. 'if rowLeftW > fb_depth[index] then\n'
		end

		if opt_fragment_shader then
			pda = pda .. 'local fs_colour = opt_fragment_shader(uniforms, u, v)\n'
			          .. 'if fs_colour ~= nil then\n'
			          .. 'fb_colour[index] = fs_colour\n'
		else
			pda = pda .. 'fb_colour[index] = colour\n'
		end

		if opt_depth_store then
			pda = pda .. 'fb_depth[index] = rowLeftW\n'
		end

		if opt_fragment_shader then
			pda = pda .. 'end\n'
		end

		if opt_depth_test then
			pda = pda .. 'end\n'
		end

		if opt_depth_test or opt_depth_store or opt_interpolate_attribute then
			pda = pda .. 'rowLeftW = rowLeftW + rowDeltaW\n'
		end

		if opt_interpolate_attribute then
			pda = pda .. 'rowLeftU = rowLeftU + rowDeltaU\n'
			          .. 'rowLeftV = rowLeftV + rowDeltaV\n'
		end

		pipeline_source = pipeline_source:gsub('-- #marker PIXEL_DRAW_ADVANCE', pda)
	end

	do -- ROW_ADVANCE
		local ra = ''

		if opt_depth_test or opt_depth_store or opt_interpolate_attribute then
			ra = ra .. '_pflat_triLeftW = _pflat_triLeftW + _pflat_triLeftGradientW\n'
			        .. '_pflat_triRightW = _pflat_triRightW + _pflat_triRightGradientW\n'
		end

		if opt_interpolate_attribute then
			ra = ra .. '_pflat_triLeftUW = _pflat_triLeftUW + _pflat_triLeftGradientUW\n'
			        .. '_pflat_triRightUW = _pflat_triRightUW + _pflat_triRightGradientUW\n'
			        .. '_pflat_triLeftVW = _pflat_triLeftVW + _pflat_triLeftGradientVW\n'
			        .. '_pflat_triRightVW = _pflat_triRightVW + _pflat_triRightGradientVW\n'
		end

		pipeline_source = pipeline_source:gsub('-- #marker ROW_ADVANCE', ra)
	end

	do -- TOP_HALF_CALCULATIONS
		local thc = ''

		if opt_depth_test or opt_depth_store or opt_interpolate_attribute then
			thc = thc .. 'local _pflat_triLeftGradientW = (pMw - _ptri_p0w) / tri_delta_y\n'
			          .. 'local _pflat_triRightGradientW = (_ptri_p1w - _ptri_p0w) / tri_delta_y\n'
			          .. 'local _pflat_triLeftW = _ptri_p0w + _pflat_triLeftGradientW * tri_projection\n'
			          .. 'local _pflat_triRightW = _ptri_p0w + _pflat_triRightGradientW * tri_projection\n'
		end

		if opt_interpolate_attribute then
			thc = thc .. 'local _pflat_triLeftGradientUW = (pMu * pMw - _ptri_p0u * _ptri_p0w) / tri_delta_y\n'
			          .. 'local _pflat_triRightGradientUW = (_ptri_p1u * _ptri_p1w - _ptri_p0u * _ptri_p0w) / tri_delta_y\n'
			          .. 'local _pflat_triLeftGradientVW = (pMv * pMw - _ptri_p0v * _ptri_p0w) / tri_delta_y\n'
			          .. 'local _pflat_triRightGradientVW = (_ptri_p1v * _ptri_p1w - _ptri_p0v * _ptri_p0w) / tri_delta_y\n'
			          .. 'local _pflat_triLeftUW = _ptri_p0u * _ptri_p0w + _pflat_triLeftGradientUW * tri_projection\n'
			          .. 'local _pflat_triRightUW = _ptri_p0u * _ptri_p0w + _pflat_triRightGradientUW * tri_projection\n'
			          .. 'local _pflat_triLeftVW = _ptri_p0v * _ptri_p0w + _pflat_triLeftGradientVW * tri_projection\n'
			          .. 'local _pflat_triRightVW = _ptri_p0v * _ptri_p0w + _pflat_triRightGradientVW * tri_projection\n'
		end

		pipeline_source = pipeline_source:gsub('-- #marker TOP_HALF_CALCULATIONS', thc)
	end

	do -- BOTTOM_HALF_CALCULATIONS
		local bhc = ''

		if opt_depth_test or opt_depth_store or opt_interpolate_attribute then
			bhc = bhc .. 'local _pflat_triLeftGradientW = (_ptri_p2w - pMw) / tri_delta_y\n'
			          .. 'local _pflat_triRightGradientW = (_ptri_p2w - _ptri_p1w) / tri_delta_y\n'
			          .. 'local _pflat_triLeftW = pMw + _pflat_triLeftGradientW * tri_projection\n'
			          .. 'local _pflat_triRightW = _ptri_p1w + _pflat_triRightGradientW * tri_projection\n'
		end

		if opt_interpolate_attribute then
			bhc = bhc .. 'local _pflat_triLeftGradientUW = (_ptri_p2u * _ptri_p2w - pMu * pMw) / tri_delta_y\n'
			          .. 'local _pflat_triRightGradientUW = (_ptri_p2u * _ptri_p2w - _ptri_p1u * _ptri_p1w) / tri_delta_y\n'
			          .. 'local _pflat_triLeftGradientVW = (_ptri_p2v * _ptri_p2w - pMv * pMw) / tri_delta_y\n'
			          .. 'local _pflat_triRightGradientVW = (_ptri_p2v * _ptri_p2w - _ptri_p1v * _ptri_p1w) / tri_delta_y\n'
			          .. 'local _pflat_triLeftUW = pMu * pMw + _pflat_triLeftGradientUW * tri_projection\n'
			          .. 'local _pflat_triRightUW = _ptri_p1u * _ptri_p1w + _pflat_triRightGradientUW * tri_projection\n'
			          .. 'local _pflat_triLeftVW = pMv * pMw + _pflat_triLeftGradientVW * tri_projection\n'
			          .. 'local _pflat_triRightVW = _ptri_p1v * _ptri_p1w + _pflat_triRightGradientVW * tri_projection\n'
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
