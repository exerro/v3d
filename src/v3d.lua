-- MIT License
--
-- Copyright (c) 2022-2023 Benedict Allen (aka shady_duck, exerro)
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.


--[[ TODO: example library usage

local fb = verta.create_framebuffer_subpixel(term.getSize())
local camera = verta.create_perspective_camera(math.pi / 7)
local geometry = verta.load_model('mymodel.obj'):expect_uvs()
local texture = verta.load_texture('myimage.idk')
local pipeline = verta.create_pipeline {
	cull_face = verta.CULL_BACK_FACE,
	interpolate_uvs = true,
	fragment_shader = verta.create_texture_shader 'u_texture',
}

pipeline:set_uniform('u_texture', texture)
pipeline:render_geometry(geometry, fb, camera)
fb:blit_subpixel(term)
]]


-- Note, this section just declares all the functions so the top of this file
-- can be used as documentation. The implementations are below.
--- @diagnostic disable: missing-return, unused-local

--------------------------------------------------------------------------------
--[ Verta ]---------------------------------------------------------------------
--------------------------------------------------------------------------------


--- @class VertaLibrary
local verta = {}

--- @type VertaCullFace
verta.CULL_FRONT_FACE = -1

--- @type VertaCullFace
verta.CULL_BACK_FACE = 1

--- @type VertaProjection
verta.NO_PROJECTION = 0

--- @type VertaProjection
verta.PERSPECTIVE_PROJECTION = 1

--- @type VertaProjection
verta.ORTHOGRAPHIC_PROJECTION = 2

--- Create an empty framebuffer of exactly `width` x `height` pixels.
---
--- Note, for using subpixel rendering (you probably are), use
--- `create_framebuffer_subpixel` instead.
--- @param width integer
--- @param height integer
--- @return VertaFramebuffer
function verta.create_framebuffer(width, height) end

--- Create an empty framebuffer of exactly `width * 2` x `height * 3` pixels,
--- suitable for rendering subpixels.
--- @param width integer
--- @param height integer
--- @return VertaFramebuffer
function verta.create_framebuffer_subpixel(width, height) end

--- TODO
--- @param fov number | nil
--- @return VertaCamera
function verta.create_perspective_camera(fov) end

--- Create some empty geometry with no triangles.
--- @return VertaGeometry
function verta.create_geometry() end

-- TODO: create_pipeline_builder():set_blah():build()?
--- TODO
--- @param options VertaPipelineOptions | nil
--- @return VertaPipeline
function verta.create_pipeline(options) end


--------------------------------------------------------------------------------
--[ Framebuffers ]--------------------------------------------------------------
--------------------------------------------------------------------------------


--- Stores the colour and depth of rendered triangles.
--- @class VertaFramebuffer
--- Width of the framebuffer in pixels. Note, if you're using subpixel
--- rendering, this includes the subpixels, e.g. a 51x19 screen would have a
--- width of 102 pixels in its framebuffer.
--- @field width integer
--- Height of the framebuffer in pixels. Note, if you're using subpixel
--- rendering, this includes the subpixels, e.g. a 51x19 screen would have a
--- height of 57 pixels in its framebuffer.
--- @field height integer
--- Stores the colour value of every pixel that's been drawn.
--- @field front any[]
--- Stores `1/Z` for every pixel drawn (when depth testing is enabled)
--- @field depth number[]
local VertaFramebuffer = {}

--- Clears the entire framebuffer to the provided colour.
--- @param colour integer | nil Colour to set every pixel to. Defaults to 1 (colours.white)
--- @return nil
function VertaFramebuffer:clear(colour) end

--- Render the framebuffer to the terminal, drawing a high resolution using
--- subpixel conversion.
--- @param term table CC term API, e.g. 'term', or a window object you want to draw to.
--- @param dx integer | nil Horizontal integer pixel offset when drawing. 0 (default) means no offset.
--- @param dy integer | nil Vertical integer pixel offset when drawing. 0 (default) means no offset.
--- @return nil
function VertaFramebuffer:blit_subpixel(term, dx, dy) end

--- Similar to `blit_subpixel` but draws the depth instead of colour.
--- @param term table CC term API, e.g. 'term', or a window object you want to draw to.
--- @param dx integer | nil Horizontal integer pixel offset when drawing. 0 (default) means no offset.
--- @param dy integer | nil Vertical integer pixel offset when drawing. 0 (default) means no offset.
--- @param update_palette boolean | nil Whether to update the term palette to better show depth. Defaults to true.
--- @return nil
function VertaFramebuffer:blit_subpixel_depth(term, dx, dy, update_palette) end


--------------------------------------------------------------------------------
--[ Cameras ]-------------------------------------------------------------------
--------------------------------------------------------------------------------


--- Contains information for the view transform when rasterizing geometry.
--- @class VertaCamera
--- Angle between the centre and the topmost pixel of the screen, in radians.
--- @field fov number
--- Centre X coordinate of the camera, where geometry is drawn relative to.
--- A positive value moves the camera to the right in world space.
--- @field x number
--- Centre Y coordinate of the camera, where geometry is drawn relative to.
--- A positive value moves the camera upwards in world space.
--- @field y number
--- Centre Z coordinate of the camera, where geometry is drawn relative to.
--- A positive value moves the camera 'backwards' (away from where it's looking
--- by default) in world space.
--- @field z number
--- TODO
--- @field yRotation number
--- TODO
--- @field xRotation number
--- TODO
--- @field zRotation number
local VertaCamera = {}


--------------------------------------------------------------------------------
--[ Geometry ]------------------------------------------------------------------
--------------------------------------------------------------------------------


--- Contains triangles.
--- @class VertaGeometry
--- Number of triangles contained within this geometry
--- @field triangles integer
local VertaGeometry = {}

--- TODO
--- @param p0x number
--- @param p0y number
--- @param p0z number
--- @param p1x number
--- @param p1y number
--- @param p1z number
--- @param p2x number
--- @param p2y number
--- @param p2z number
--- @param colour integer
--- @return nil
function VertaGeometry:add_coloured_triangle(p0x, p0y, p0z, p1x, p1y, p1z, p2x, p2y, p2z, colour) end

--- TODO
--- @param theta number
--- @param cx number | nil
--- @param cy number | nil
--- @return nil
function VertaGeometry:rotate_z(theta, cx, cy) end


--------------------------------------------------------------------------------
--[ Pipelines ]-----------------------------------------------------------------
--------------------------------------------------------------------------------


--- TODO
--- @class VertaPipeline
local VertaPipeline = {}

--- TODO
--- @enum VertaCullFace
local VertaCullFace = {
	BACK_FACE = 1,
	FRONT_FACE = -1,
}

--- TODO
--- @enum VertaProjection
local VertaProjection = {
	NONE = 0,
	PERSPECTIVE = 1,
	ORTHOGRAPHIC = 2,
}

--- TODO
--- @class VertaPipelineOptions
--- @field cull_face VertaCullFace | false | nil
--- @field depth_store boolean | nil
--- @field depth_test boolean | nil
--- @field fragment_shader function TODO(type)
--- @field interpolate_uvs boolean | nil
--- @field pixel_aspect_ratio number | nil
--- @field projection VertaProjection | nil
--- @field vertex_shader function TODO(type)
local VertaPipelineOptions = {}

-- TODO: list of geometry instead? with count and offset options
--- TODO
--- @param geometry VertaGeometry
--- @param fb VertaFramebuffer
--- @param camera VertaCamera
--- @return nil
function VertaPipeline:render_geometry(geometry, fb, camera) end


--------------------------------------------------------------------------------
-- We're now done with the declarations!
--- @diagnostic enable: missing-return, unused-local
--------------------------------------------------------------------------------


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
	local fb_front = fb.front
	local fb_depth = fb.depth
	for i = 1, fb.width * fb.height do
		fb_front[i] = colour
		fb_depth[i] = 0
	end
end

local function framebuffer_blit_subpixel(fb, term, dx, dy)
	dx = dx or 0
	dy = dy or 0

	local SUBPIXEL_WIDTH = 2
	local SUBPIXEL_HEIGHT = 3

	local fb_front, fb_width = fb.front, fb.width

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
			local c00, c10 = fb_front[i0], fb_front[i0 + 1]
			local c01, c11 = fb_front[i1], fb_front[i1 + 1]
			local c02, c12 = fb_front[i2], fb_front[i2 + 1]

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
	local old_front = fb.front
	local new_front = {}
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
		new_front[i] = 2 ^ b
	end

	fb.front = new_front
	framebuffer_blit_subpixel(fb, term, dx, dy)
	fb.front = old_front
end

local function create_framebuffer(width, height)
	--- @type VertaFramebuffer
	local fb = {}

	fb.width = width
	fb.height = height
	fb.front = {}
	fb.depth = {}
	fb.clear = framebuffer_clear
	fb.blit_subpixel = framebuffer_blit_subpixel
	fb.blit_subpixel_depth = framebuffer_blit_subpixel_depth

	framebuffer_clear(fb, 0)

	return fb
end

local function create_framebuffer_subpixel(width, height)
	return create_framebuffer(width * 2, height * 3) -- multiply by subpixel dimensions
end


--------------------------------------------------------------------------------
--[ Camera functions ]----------------------------------------------------------
--------------------------------------------------------------------------------


local function create_perspective_camera(fov)
	--- @type VertaCamera
	local camera = {}

	camera.fov = fov or math.pi / 3
	camera.x = 0
	camera.y = 0
	camera.z = 0
	camera.yRotation = 0
	camera.xRotation = 0
	camera.zRotation = 0

	return camera
end


--------------------------------------------------------------------------------
--[ Geometry functions ]--------------------------------------------------------
--------------------------------------------------------------------------------


local function geometry_add_coloured_triangle(geometry, p0x, p0y, p0z, p1x, p1y, p1z, p2x, p2y, p2z, colour)
	local DATA_PER_TRIANGLE = 10
	local idx = geometry.triangles * DATA_PER_TRIANGLE

	geometry.triangles = geometry.triangles + 1
	geometry[idx + 1] = p0x
	geometry[idx + 2] = p0y
	geometry[idx + 3] = p0z
	geometry[idx + 4] = p1x
	geometry[idx + 5] = p1y
	geometry[idx + 6] = p1z
	geometry[idx + 7] = p2x
	geometry[idx + 8] = p2y
	geometry[idx + 9] = p2z
	geometry[idx + 10] = colour
end

local function geometry_rotate_z(geometry, theta, cx, cy)
	local DATA_PER_TRIANGLE = 10

	--- TODO: use cx and cy
	cx = cx or 0
	cy = cy or 0

	local sT = math.sin(theta)
	local cT = math.cos(theta)

	for i = 1, geometry.triangles * DATA_PER_TRIANGLE, DATA_PER_TRIANGLE do
		local x0, y0 = geometry[i], geometry[i + 1]
		local x1, y1 = geometry[i + 3], geometry[i + 4]
		local x2, y2 = geometry[i + 6], geometry[i + 7]
		geometry[i], geometry[i + 1] = x0 * cT - y0 * sT, x0 * sT + y0 * cT
		geometry[i + 3], geometry[i + 4] = x1 * cT - y1 * sT, x1 * sT + y1 * cT
		geometry[i + 6], geometry[i + 7] = x2 * cT - y2 * sT, x2 * sT + y2 * cT
	end
end

local function create_geometry()
	--- @type VertaGeometry
	local geometry = {}

	geometry.triangles = 0
	geometry.add_coloured_triangle = geometry_add_coloured_triangle
	geometry.rotate_z = geometry_rotate_z

	return geometry
end


--------------------------------------------------------------------------------
--[ Rasterization functions ]---------------------------------------------------
--------------------------------------------------------------------------------


-- #section depth_test depth_store
local function rasterize_triangle(
	fb_front, fb_depth,
	fb_width, fb_height_m1,
	p0x, p0y, p0w,
	p1x, p1y, p1w,
	p2x, p2y, p2w,
	colour)
	local math_ceil = math.ceil
	local math_floor = math.floor
	local fb_width_m1 = fb_width - 1

	-- see: https://github.com/exerro/verta/blob/main/raster_visuals/src/main/kotlin/me/exerro/raster_visuals/rasterize.kt
	-- there's an explanation of the algorithm there
	-- this code has been heavily microoptimised so won't perfectly resemble that

	-- #if depth_test depth_store
	if p0y > p1y then p0x, p0y, p0w, p1x, p1y, p1w = p1x, p1y, p1w, p0x, p0y, p0w end
	if p1y > p2y then p1x, p1y, p1w, p2x, p2y, p2w = p2x, p2y, p2w, p1x, p1y, p1w end
	if p0y > p1y then p0x, p0y, p0w, p1x, p1y, p1w = p1x, p1y, p1w, p0x, p0y, p0w end
	-- #else
	if p0y > p1y then p0x, p0y, p1x, p1y = p1x, p1y, p0x, p0y end
	if p1y > p2y then p1x, p1y, p2x, p2y = p2x, p2y, p1x, p1y end
	if p0y > p1y then p0x, p0y, p1x, p1y = p1x, p1y, p0x, p0y end
	-- #end
	if p0y == p2y then return end -- skip early if we have a perfectly flat triangle

	local f = (p1y - p0y) / (p2y - p0y)
	local pMx = p0x * (1 - f) + p2x * f
	-- #if depth_test depth_store
	local pMw = p0w * (1 - f) + p2w * f
	-- #end

	if pMx > p1x then
		pMx, p1x = p1x, pMx
		-- #if depth_test depth_store
		pMw, p1w = p1w, pMw
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

	if rowTopMin <= rowTopMax then
		local topDeltaY = p1y - p0y
		local topLeftGradientX = (pMx - p0x) / topDeltaY
		local topRightGradientX = (p1x - p0x) / topDeltaY
		-- #if depth_test depth_store
		local topLeftGradientW = (pMw - p0w) / topDeltaY
		local topRightGradientW = (p1w - p0w) / topDeltaY
		-- #end

		local topProjection = rowTopMin + 0.5 - p0y
		local topLeftX = p0x + topLeftGradientX * topProjection - 0.5
		local topRightX = p0x + topRightGradientX * topProjection - 1.5
		-- #if depth_test depth_store
		local topLeftW = p0w + topLeftGradientW * topProjection
		local topRightW = p0w + topRightGradientW * topProjection
		-- #end

		for baseIndex = rowTopMin * fb_width + 1, rowTopMax * fb_width + 1, fb_width do
			local columnMinX = math_ceil(topLeftX)
			local columnMaxX = math_ceil(topRightX)
			-- #if depth_test depth_store
			local rowTotalDeltaX = topRightX - topLeftX + 1 -- 'cause of awkward optimisations above
			local rowDeltaW = (topRightW - topLeftW) / rowTotalDeltaX
			local rowLeftW = topLeftW + (columnMinX - topLeftX) * rowDeltaW
			-- #end

			if columnMinX < 0 then columnMinX = 0 end
			if columnMaxX > fb_width_m1 then columnMaxX = fb_width_m1 end

			for x = columnMinX, columnMaxX do
				local index = baseIndex + x
				
				-- #if depth_test
				if rowLeftW > fb_depth[index] then
					fb_front[index] = colour
					-- #if depth_store
					fb_depth[index] = rowLeftW
					-- #end
				end
				-- #else
				fb_front[index] = colour
				-- #if depth_store
				fb_depth[index] = rowLeftW
				-- #end
				-- #end

				-- #if depth_test depth_store
				rowLeftW = rowLeftW + rowDeltaW
				-- #end
			end

			topLeftX = topLeftX + topLeftGradientX
			topRightX = topRightX + topRightGradientX
			-- #if depth_test depth_store
			topLeftW = topLeftW + topLeftGradientW
			topRightW = topRightW + topRightGradientW
			-- #end
		end
	end

	if rowBottomMin <= rowBottomMax then
		local bottomDeltaY = p2y - p1y
		local bottomLeftGradientX = (p2x - pMx) / bottomDeltaY
		local bottomRightGradientX = (p2x - p1x) / bottomDeltaY
		-- #if depth_test depth_store
		local bottomLeftGradientW = (p2w - pMw) / bottomDeltaY
		local bottomRightGradientW = (p2w - p1w) / bottomDeltaY
		-- #end

		local bottomProjection = rowBottomMin + 0.5 - p1y
		local bottomLeftX = pMx + bottomLeftGradientX * bottomProjection - 0.5
		local bottomRightX = p1x + bottomRightGradientX * bottomProjection - 1.5
		-- #if depth_test depth_store
		local bottomLeftW = pMw + bottomLeftGradientW * bottomProjection
		local bottomRightW = p1w + bottomRightGradientW * bottomProjection
		-- #end

		for baseIndex = rowBottomMin * fb_width + 1, rowBottomMax * fb_width + 1, fb_width do
			local columnMinX = math_ceil(bottomLeftX)
			local columnMaxX = math_ceil(bottomRightX)
			-- #if depth_test depth_store
			local rowTotalDeltaX = bottomRightX - bottomLeftX + 1 -- 'cause of awkward optimisations above
			local rowDeltaW = (bottomRightW - bottomLeftW) / rowTotalDeltaX
			local rowLeftW = bottomLeftW + (columnMinX - bottomLeftX) * rowDeltaW
			-- #end

			if columnMinX < 0 then columnMinX = 0 end
			if columnMaxX > fb_width_m1 then columnMaxX = fb_width_m1 end

			for x = columnMinX, columnMaxX do
				local index = baseIndex + x

				-- #if depth_test
				if rowLeftW > fb_depth[index] then
					fb_front[index] = colour
					-- #if depth_store
					fb_depth[index] = rowLeftW
					-- #end
				end
				-- #else
				fb_front[index] = colour
				-- #if depth_store
				fb_depth[index] = rowLeftW
				-- #end
				-- #end

				-- #if depth_test depth_store
				rowLeftW = rowLeftW + rowDeltaW
				-- #end
			end

			bottomLeftX = bottomLeftX + bottomLeftGradientX
			bottomRightX = bottomRightX + bottomRightGradientX
			-- #if depth_test depth_store
			bottomLeftW = bottomLeftW + bottomLeftGradientW
			bottomRightW = bottomRightW + bottomRightGradientW
			-- #end
		end
	end
end
-- #endsection

--- @param options VertaPipelineOptions
local function create_pipeline(options)
	options = options or {}

	local opt_pixel_aspect_ratio = options.pixel_aspect_ratio or 1
	local opt_cull_face = options.cull_face == nil and verta.CULL_BACK_FACE or options.cull_face
	local opt_depth_store = options.depth_store == nil or options.depth_store
	local opt_depth_test = options.depth_test == nil or options.depth_test
	local opt_interpolate_uvs = options.interpolate_uvs or false
	local opt_fragment_shader = options.fragment_shader or nil
	local opt_vertex_shader = options.vertex_shader or nil
	local opt_projection = options.projection or VertaProjection.PERSPECTIVE

	--- @type VertaPipeline
	local pipeline = {}

	local rasterize_triangle_fn = rasterize_triangle
	-- #select rasterize_triangle_fn rasterize_triangle
	-- #select-param depth_test opt_depth_test
	-- #select-param depth_store opt_depth_store

	-- magical hacks to get around the language server!
	select(1, pipeline).render_geometry = function(_, geometry, fb, camera)
		local DATA_PER_TRIANGLE = 10
		local clipping_plane = -0.0001
		local pxd = (fb.width - 1) / 2
		local pyd = (fb.height - 1) / 2
		local pxs = pyd
		local pys = -pyd
		local fb_front, fb_width = fb.front, fb.width
		local fb_depth = fb.depth
		local fb_height_m1 = fb.height - 1
		local math_sin, math_cos = math.sin, math.cos

		local cull_back_faces = opt_cull_face or 0

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

		for i = 1, geometry.triangles * DATA_PER_TRIANGLE, DATA_PER_TRIANGLE do
			local p0x = geometry[i]
			local p0y = geometry[i + 1]
			local p0z = geometry[i + 2]
			local p1x = geometry[i + 3]
			local p1y = geometry[i + 4]
			local p1z = geometry[i + 5]
			local p2x = geometry[i + 6]
			local p2y = geometry[i + 7]
			local p2z = geometry[i + 8]
			local colour = geometry[i + 9]

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

			if cull_back_faces ~= 0 then
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
				cull_face = d * cull_back_faces > 0
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

					rasterize_triangle_fn(fb_front, fb_depth, fb_width, fb_height_m1, p0x, p0y, p0w, p1x, p1y, p1w, p2x, p2y, p2w, colour)
				end
			end
		end
	end

	return pipeline
end


--------------------------------------------------------------------------------
--[ Library export ]------------------------------------------------------------
--------------------------------------------------------------------------------


-- This purely exists to bypass the language server being too clever for itself.
-- It's here so the LS can't work out what's going on so we keep the types and
-- docstrings from the top of the file rather than adding weird shit from here.
local function set_function(name, fn)
	local c = verta
	c[name] = fn
end

set_function('create_framebuffer', create_framebuffer)
set_function('create_framebuffer_subpixel', create_framebuffer_subpixel)
set_function('create_perspective_camera', create_perspective_camera)
set_function('create_geometry', create_geometry)
set_function('create_pipeline', create_pipeline)

return verta
