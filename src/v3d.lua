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

local fb = v3d.create_framebuffer_subpixel(term.getSize())
local camera = v3d.create_camera(math.pi / 7)
local geometry = v3d.load_model('mymodel.obj'):expect_uvs()
local texture = v3d.load_texture('myimage.idk')
local pipeline = v3d.create_pipeline {
	cull_face = v3d.CULL_BACK_FACE,
	interpolate_uvs = true,
	fragment_shader = v3d.create_texture_shader 'u_texture',
}

pipeline:set_uniform('u_texture', texture)
pipeline:render_geometry(geometry, fb, camera)
fb:blit_subpixel(term)
]]

-- #remove
-- note: this code will be stripped out during the build process, thus removing
--       the error
error 'Cannot use v3d source code, must use built library'
-- #end


-- Note, this section just declares all the functions so the top of this file
-- can be used as an API reference. The implementations are below.
--- @diagnostic disable: missing-return, unused-local

--------------------------------------------------------------------------------
--[ V3D ]-----------------------------------------------------------------------
--------------------------------------------------------------------------------


--- V3D library instance. Used to create all objects for rendering, and refer to
--- enum values.
--- @class v3d
--- Specify to cull (not draw) the front face (facing towards the camera).
--- @field CULL_FRONT_FACE V3DCullFace
--- Specify to cull (not draw) the back face (facing away from the camera).
--- @field CULL_BACK_FACE V3DCullFace
--- Type of geometry that only has colour information and no UV coordinates.
--- @field GEOMETRY_COLOUR V3DGeometryType
--- Type of geometry that only has UV coordinates and no colour information.
--- @field GEOMETRY_UV V3DGeometryType
--- Type of geometry that has both colour information and UV coordinates.
--- @field GEOMETRY_COLOUR_UV V3DGeometryType
local v3d = {
	CULL_FRONT_FACE = -1,
	CULL_BACK_FACE = 1,
	GEOMETRY_COLOUR = 1,
	GEOMETRY_UV = 2,
	GEOMETRY_COLOUR_UV = 3,
}

--- Create an empty [[@V3DFramebuffer]] of exactly `width` x `height` pixels.
---
--- Note, for using subpixel rendering (you probably are), use
--- `create_framebuffer_subpixel` instead.
--- @param width integer
--- @param height integer
--- @return V3DFramebuffer
function v3d.create_framebuffer(width, height) end

--- Create an empty [[@V3DFramebuffer]] of exactly `width * 2` x `height * 3`
--- pixels, suitable for rendering subpixels.
--- @param width integer
--- @param height integer
--- @return V3DFramebuffer
function v3d.create_framebuffer_subpixel(width, height) end

--- Create a [[@V3DCamera]] with the given field of view. FOV defaults to 30
--- degrees.
--- @param fov number | nil
--- @return V3DCamera
function v3d.create_camera(fov) end

--- Create an empty [[@V3DGeometry]] with no triangles.
--- @param type V3DGeometryType
--- @return V3DGeometry
function v3d.create_geometry(type) end

--- Create a [[@V3DGeometry]] cube containing coloured triangles with UVs.
--- @param cx number | nil Centre X coordinate of the cube.
--- @param cy number | nil Centre Y coordinate of the cube.
--- @param cz number | nil Centre Z coordinate of the cube.
--- @param size number | nil Distance between opposide faces of the cube.
--- @return V3DGeometry
function v3d.create_debug_cube(cx, cy, cz, size) end

--- Create a [[@V3DPipeline]] with the given options. Options can be omitted to
--- use defaults, and any field within the options can also be omitted to use
--- defaults.
---
--- Example usage:
--- ```lua
--- local pipeline = v3d.create_pipeline {
--- 	cull_face = false,
--- }
--- ```
--- @param options V3DPipelineOptions | nil
--- @return V3DPipeline
function v3d.create_pipeline(options) end


--------------------------------------------------------------------------------
--[ Framebuffers ]--------------------------------------------------------------
--------------------------------------------------------------------------------


--- Stores the colour and depth of rendered triangles.
--- @class V3DFramebuffer
--- Width of the framebuffer in pixels. Note, if you're using subpixel
--- rendering, this includes the subpixels, e.g. a 51x19 screen would have a
--- width of 102 pixels in its framebuffer.
--- @field width integer
--- Height of the framebuffer in pixels. Note, if you're using subpixel
--- rendering, this includes the subpixels, e.g. a 51x19 screen would have a
--- height of 57 pixels in its framebuffer.
--- @field height integer
--- Stores the colour value of every pixel that's been drawn.
--- @field colour integer[]
--- Stores `1/Z` for every pixel drawn (when depth storing is enabled)
--- @field depth number[]
local V3DFramebuffer = {}

--- Clears the entire framebuffer to the provided colour and resets the depth
--- values.
--- @param colour integer | nil Colour to set every pixel to. Defaults to 1 (colours.white)
--- @return nil
function V3DFramebuffer:clear(colour) end

--- Render the framebuffer to the terminal, drawing a high resolution image
--- using subpixel conversion.
--- @param term table CC term API, e.g. 'term', or a window object you want to draw to.
--- @param dx integer | nil Horizontal integer pixel offset when drawing. 0 (default) means no offset.
--- @param dy integer | nil Vertical integer pixel offset when drawing. 0 (default) means no offset.
--- @return nil
function V3DFramebuffer:blit_subpixel(term, dx, dy) end

--- Similar to `blit_subpixel` but draws the depth instead of colour.
--- @param term table CC term API, e.g. 'term', or a window object you want to draw to.
--- @param dx integer | nil Horizontal integer pixel offset when drawing. 0 (default) means no offset.
--- @param dy integer | nil Vertical integer pixel offset when drawing. 0 (default) means no offset.
--- @param update_palette boolean | nil Whether to update the term palette to better show depth. Defaults to true.
--- @return nil
function V3DFramebuffer:blit_subpixel_depth(term, dx, dy, update_palette) end


--------------------------------------------------------------------------------
--[ Cameras ]-------------------------------------------------------------------
--------------------------------------------------------------------------------


--- Contains information for the view transform when rasterizing geometry.
--- @class V3DCamera
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
--- Counter-clockwise rotation of the camera in radians around the Y axis.
--- Increasing this value will make the camera look "to the left". Decreasing it
--- will make the camera look "to the right".
--- @field yRotation number
--- Counter-clockwise rotation of the camera in radians around the X axis.
--- Increasing this value will make the camera look "up". Decreasing it will
--- make the camera look "down".
--- @field xRotation number
--- Counter-clockwise rotation of the camera in radians around the Z axis.
--- Increasing this value will make the camera tilt "to the left". Decreasing it
--- will make the camera tilt "to the right".
--- @field zRotation number
local V3DCamera = {}


--------------------------------------------------------------------------------
--[ Geometry ]------------------------------------------------------------------
--------------------------------------------------------------------------------


--- Describes whether geometry contains colour information, UV information, or
--- both.
--- @see v3d.GEOMETRY_COLOUR
--- @see v3d.GEOMETRY_UV
--- @see v3d.GEOMETRY_COLOUR_UV
--- @alias V3DGeometryType 1 | 2 | 3


--- Contains triangles.
--- @class V3DGeometry
--- Structure of the triangles contained within this geometry. This is fixed
--- upon creation and affects the kind of triangles you can add to the geometry.
--- @field type V3DGeometryType
--- Number of triangles contained within this geometry
--- @field triangles integer
local V3DGeometry = {}

--- Add a triangle to this geometry using the 3 corner coordinates and a block
--- colour for the whole triangle.
---
--- Must only be used with [[@v3d.GEOMETRY_COLOUR]] typed geometry objects.
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
function V3DGeometry:add_colour_triangle(p0x, p0y, p0z, p1x, p1y, p1z, p2x, p2y, p2z, colour) end

--- Add a triangle to this geometry using the 3 corner coordinates with UVs.
---
--- Must only be used with [[@v3d.GEOMETRY_UV]] typed geometry objects.
--- @param p0x number
--- @param p0y number
--- @param p0z number
--- @param p0u number
--- @param p0v number
--- @param p1x number
--- @param p1y number
--- @param p1z number
--- @param p1u number
--- @param p1v number
--- @param p2x number
--- @param p2y number
--- @param p2z number
--- @param p2u number
--- @param p2v number
--- @return nil
function V3DGeometry:add_uv_triangle(p0x, p0y, p0z, p0u, p0v, p1x, p1y, p1z, p1u, p1v, p2x, p2y, p2z, p2u, p2v) end

--- Add a triangle to this geometry using the 3 corner coordinates with UVs and
--- a block colour for the whole triangle.
---
--- Must only be used with [[@v3d.GEOMETRY_COLOUR_UV]] typed geometry objects.
--- @param p0x number
--- @param p0y number
--- @param p0z number
--- @param p0u number
--- @param p0v number
--- @param p1x number
--- @param p1y number
--- @param p1z number
--- @param p1u number
--- @param p1v number
--- @param p2x number
--- @param p2y number
--- @param p2z number
--- @param p2u number
--- @param p2v number
--- @param colour integer
--- @return nil
function V3DGeometry:add_colour_uv_triangle(p0x, p0y, p0z, p0u, p0v, p1x, p1y, p1z, p1u, p1v, p2x, p2y, p2z, p2u, p2v, colour) end

--- Rotate every vertex position within this geometry counter-clockwise by theta
--- radians around the Y axis.
--- @param theta number
--- @return nil
function V3DGeometry:rotate_y(theta) end

--- Rotate every vertex position within this geometry counter-clockwise by theta
--- radians around the Z axis.
--- @param theta number
--- @return nil
function V3DGeometry:rotate_z(theta) end


--------------------------------------------------------------------------------
--[ Pipelines ]-----------------------------------------------------------------
--------------------------------------------------------------------------------


--- A pipeline is an optimised object used to draw [[@V3DGeometry]] to a
--- [[@V3DFramebuffer]] using a [[@V3DCamera]]. It is created using
--- [[@V3DPipelineOptions]] which cannot change. To configure the pipeline after
--- creation, uniforms can be used alongside shaders. Alternatively, multiple
--- pipelines can be created or re-created at will according to the needs of the
--- application.
--- @class V3DPipeline
local V3DPipeline = {}

--- Specifies which face to cull, either the front or back face.
--- @see v3d.CULL_BACK_FACE
--- @see v3d.CULL_FRONT_FACE
--- @alias V3DCullFace 1 | -1

--- A fragment shader runs for every pixel being drawn, accepting the
--- interpolated UV coordinates of that pixel if UV interpolation is enabled in
--- the pipeline settings.
--- The shader should return a value to be written directly to the framebuffer.
--- Note: if `nil` is returned, no pixel is written, and the depth value is not
--- updated for that pixel.
--- @alias V3DFragmentShader fun(uniforms: { [string]: unknown }, u: number, v: number): integer

--- TODO: Currently unused.
--- @alias V3DVertexShader function

--- Pipeline options describe the settings used to create a pipeline. Every
--- field is optional and has a sensible default. Not using or disabling
--- features may lead to a performance gain, for example disabling depth testing
--- or not using shaders.
--- @class V3DPipelineOptions
--- Specify a face to cull (not draw), or false to disable face culling.
--- Defaults to [[@v3d.CULL_BACK_FACE]]. This is a technique to improve
--- performance and should only be changed from the default when doing something
--- weird. For example, to not draw faces facing towards the camera, use
--- `cull_face = v3d.CULL_FRONT_FACE`.
--- @field cull_face V3DCullFace | false | nil
--- Whether to write the depth of drawn pixels to the depth buffer. Defaults to
--- true.
--- Slight performance gain if both this and `depth_test` are disabled.
--- Defaults to `true`.
--- @field depth_store boolean | nil
--- Whether to test the depth of candidate pixels, and only draw ones that are
--- closer to the camera than what's been drawn already.
--- Slight performance gain if both this and `depth_store` are disabled.
--- Defaults to `true`.
--- @field depth_test boolean | nil
--- Function to run for every pixel being drawn that determines the colour of
--- the pixel.
--- Note: for the UV values passed to the fragment shader to be correct, you
--- need to enable UV interpolation using the `interpolate_uvs` setting.
--- Slight performance loss when using fragment shaders.
--- @field fragment_shader V3DFragmentShader | nil
--- Whether to interpolate UV values across polygons being drawn. Only useful
--- when using fragment shaders, and has a slight performance loss when used.
--- Defaults to `false`.
--- @field interpolate_uvs boolean | nil
--- Aspect ratio of the pixels being drawn. For square pixels, this should be 1.
--- For non-square pixels, like the ComputerCraft non-subpixel characters, this
--- should be their width/height, for example 2/3 for non-subpixel characters.
--- Defaults to `1`.
--- @field pixel_aspect_ratio number | nil
--- TODO: Currently unused.
--- @field vertex_shader V3DVertexShader | nil
local V3DPipelineOptions = {}

--- Draw a list of geometry objects to the framebuffer using the camera given.
--- @param geometries V3DGeometry[] List of geometry to draw.
--- @param fb V3DFramebuffer Framebuffer to draw to.
--- @param camera V3DCamera Camera from whose perspective objects should be drawn.
--- @param offset integer | nil Index of the first geometry in the list to draw. Defaults to 1.
--- @param count integer | nil Number of geometry objects to draw. Defaults to ~'all remaining'.
--- @return nil
function V3DPipeline:render_geometry(geometries, fb, camera, offset, count) end

--- Set a uniform value which can be accessed from shaders.
--- @param name string Name of the uniform. Shaders can access using `uniforms[name]`
--- @param value any Any value to pass to the shader.
--- @return nil
function V3DPipeline:set_uniform(name, value) end

--- Get a uniform value that's been set with `set_uniform`.
--- @param name string Name of the uniform.
--- @return unknown
function V3DPipeline:get_uniform(name) end


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
--[ Camera functions ]----------------------------------------------------------
--------------------------------------------------------------------------------


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

	return camera
end


--------------------------------------------------------------------------------
--[ Geometry functions ]--------------------------------------------------------
--------------------------------------------------------------------------------


local function geometry_poly_size(type)
	if type == v3d.GEOMETRY_UV then
		return 15
	elseif type == v3d.GEOMETRY_COLOUR_UV then
		return 16
	else
		return 10
	end
end

local function geometry_poly_pos_stride(type)
	if type == v3d.GEOMETRY_UV then
		return 5
	elseif type == v3d.GEOMETRY_COLOUR_UV then
		return 5
	else
		return 3
	end
end

local function geometry_add_triangle(geometry, ...)
	local data = { ... }
	local n = geometry_poly_size(geometry.type)

	assert(n == #data, "Wrong data for adding triangle: " .. #data .. " ~= " .. n)

	local idx = geometry.triangles * n
	geometry.triangles = geometry.triangles + 1

	for i = 1, n do
		geometry[idx + i] = data[i]
	end
end

local function geometry_rotate_z(geometry, theta)
	local poly_stride = geometry_poly_size(geometry.type)
	local pos_stride = geometry_poly_pos_stride(geometry.type)

	local sT = math.sin(theta)
	local cT = math.cos(theta)

	for i = 1, geometry.triangles * poly_stride, poly_stride do
		local x0, y0 = geometry[i], geometry[i + 1]
		local x1, y1 = geometry[i + pos_stride], geometry[i + pos_stride + 1]
		local x2, y2 = geometry[i + pos_stride * 2], geometry[i + pos_stride * 2 + 1]
		geometry[i], geometry[i + 1] = x0 * cT - y0 * sT, x0 * sT + y0 * cT
		geometry[i + pos_stride], geometry[i + pos_stride + 1] = x1 * cT - y1 * sT, x1 * sT + y1 * cT
		geometry[i + pos_stride * 2], geometry[i + pos_stride * 2 + 1] = x2 * cT - y2 * sT, x2 * sT + y2 * cT
	end
end

local function geometry_rotate_y(geometry, theta)
	local poly_stride = geometry_poly_size(geometry.type)
	local pos_stride = geometry_poly_pos_stride(geometry.type)

	local sT = math.sin(theta)
	local cT = math.cos(theta)

	for i = 1, geometry.triangles * poly_stride, poly_stride do
		local x0, z0 = geometry[i], geometry[i + 2]
		local x1, z1 = geometry[i + pos_stride], geometry[i + pos_stride + 2]
		local x2, z2 = geometry[i + pos_stride * 2], geometry[i + pos_stride * 2 + 2]
		geometry[i], geometry[i + 2] = x0 * cT - z0 * sT, x0 * sT + z0 * cT
		geometry[i + pos_stride], geometry[i + pos_stride + 2] = x1 * cT - z1 * sT, x1 * sT + z1 * cT
		geometry[i + pos_stride * 2], geometry[i + pos_stride * 2 + 2] = x2 * cT - z2 * sT, x2 * sT + z2 * cT
	end
end

local function create_geometry(type)
	--- @type V3DGeometry
	local geometry = {}

	geometry.type = type
	geometry.triangles = 0
	geometry.rotate_y = geometry_rotate_y
	geometry.rotate_z = geometry_rotate_z

	if type == v3d.GEOMETRY_COLOUR then
		geometry.add_colour_triangle = geometry_add_triangle
	elseif type == v3d.GEOMETRY_UV then
		geometry.add_uv_triangle = geometry_add_triangle
	elseif type == v3d.GEOMETRY_COLOUR_UV then
		geometry.add_colour_uv_triangle = geometry_add_triangle
	end

	return geometry
end

local function create_debug_cube(cx, cy, cz, size)
	local geometry = create_geometry(v3d.GEOMETRY_COLOUR_UV)
	local s2 = (size or 1) / 2

	cx = cx or 0
	cy = cy or 0
	cz = cz or 0

	-- front
	geometry:add_colour_uv_triangle(
		-s2,  s2,  s2, 0, 0, -s2, -s2,  s2, 0, 1,  s2,  s2,  s2, 1, 0, colours.blue)
	geometry:add_colour_uv_triangle(
		-s2, -s2,  s2, 0, 1,  s2, -s2,  s2, 1, 1,  s2,  s2,  s2, 1, 0, colours.cyan)

	-- back
	geometry:add_colour_uv_triangle(
		 s2,  s2, -s2, 0, 0,  s2, -s2, -s2, 0, 1, -s2,  s2, -s2, 1, 0, colours.brown)
	geometry:add_colour_uv_triangle(
		 s2, -s2, -s2, 0, 1, -s2, -s2, -s2, 1, 1, -s2,  s2, -s2, 1, 0, colours.yellow)

	-- left
	geometry:add_colour_uv_triangle(
		-s2,  s2, -s2, 0, 0, -s2, -s2, -s2, 0, 1, -s2,  s2,  s2, 1, 0, colours.lightBlue)
	geometry:add_colour_uv_triangle(
		-s2, -s2, -s2, 0, 1, -s2, -s2,  s2, 1, 1, -s2,  s2,  s2, 1, 0, colours.pink)

	-- right
	geometry:add_colour_uv_triangle(
		 s2,  s2,  s2, 0, 0,  s2, -s2,  s2, 0, 1,  s2,  s2, -s2, 1, 0, colours.red)
	geometry:add_colour_uv_triangle(
		 s2, -s2,  s2, 0, 1,  s2, -s2, -s2, 1, 1,  s2,  s2, -s2, 1, 0, colours.orange)

	-- top
	geometry:add_colour_uv_triangle(
		-s2,  s2, -s2, 0, 0, -s2,  s2,  s2, 0, 1,  s2,  s2, -s2, 1, 0, colours.green)
	geometry:add_colour_uv_triangle(
		-s2,  s2,  s2, 0, 1,  s2,  s2,  s2, 1, 1,  s2,  s2, -s2, 1, 0, colours.lime)

	-- bottom
	geometry:add_colour_uv_triangle(
		 s2, -s2, -s2, 0, 0,  s2, -s2,  s2, 0, 1, -s2, -s2, -s2, 1, 0, colours.purple)
	geometry:add_colour_uv_triangle(
		 s2, -s2,  s2, 0, 1, -s2, -s2,  s2, 1, 1, -s2, -s2, -s2, 1, 0, colours.magenta)

	for i = 1, #geometry, 16 do
		for j = i, i + 10, 5 do
			geometry[j] = geometry[j] + cx
			geometry[j + 1] = geometry[j + 1] + cy
			geometry[j + 2] = geometry[j + 2] + cz
		end
	end

	return geometry
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

--- @param options V3DPipelineOptions
local function create_pipeline(options)
	options = options or {}

	local opt_pixel_aspect_ratio = options.pixel_aspect_ratio or 1
	local opt_cull_face = options.cull_face == nil and v3d.CULL_BACK_FACE or options.cull_face
	-- used by the #select below
	--- @diagnostic disable-next-line: unused-local
	local opt_depth_store = options.depth_store == nil or options.depth_store
	-- used by the #select below
	--- @diagnostic disable-next-line: unused-local
	local opt_depth_test = options.depth_test == nil or options.depth_test
	local opt_fragment_shader = options.fragment_shader or nil
	local opt_interpolate_uvs = options.interpolate_uvs and opt_fragment_shader or false
	local opt_vertex_shader = options.vertex_shader or nil

	--- @type V3DPipeline
	local pipeline = {}

	local uniforms = {}

	local rasterize_triangle_fn = rasterize_triangle
	-- #select rasterize_triangle_fn rasterize_triangle
	-- #select-param depth_test opt_depth_test
	-- #select-param depth_store opt_depth_store
	-- #select-param interpolate_uvs opt_interpolate_uvs
	-- #select-param enable_fs opt_fragment_shader

	-- magical hacks to get around the language server!
	select(1, pipeline).render_geometry = function(_, geometries, fb, camera, offset, count)
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

		offset = offset or 1
		count = count or #geometries - offset + 1

		for j = offset, offset + count - 1 do
			local geometry = geometries[j]
			if opt_interpolate_uvs and geometry.type == v3d.GEOMETRY_COLOUR then
				error("Invalid geometry type: expected uvs for this pipeline", 2)
				return
			end
			local poly_stride = geometry_poly_size(geometry.type)
			local poly_pos_stride = geometry_poly_pos_stride(geometry.type)
			for i = 1, geometry.triangles * poly_stride, poly_stride do
				local p0x = geometry[i]
				local p0y = geometry[i + 1]
				local p0z = geometry[i + 2]
				local p1x = geometry[i + poly_pos_stride]
				local p1y = geometry[i + poly_pos_stride + 1]
				local p1z = geometry[i + poly_pos_stride + 2]
				local p2x = geometry[i + poly_pos_stride + poly_pos_stride]
				local p2y = geometry[i + poly_pos_stride + poly_pos_stride + 1]
				local p2z = geometry[i + poly_pos_stride + poly_pos_stride + 2]
				local colour = geometry[i + poly_pos_stride * 3]

				local p0u, p0v, p1u, p1v, p2u, p2v

				if opt_interpolate_uvs then
					p0u = geometry[i + 3]
					p0v = geometry[i + 4]
					p1u = geometry[i + 8]
					p1v = geometry[i + 9]
					p2u = geometry[i + 13]
					p2v = geometry[i + 14]
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

						rasterize_triangle_fn(fb_colour, fb_depth, fb_width, fb_height_m1, p0x, p0y, p0w, p0u, p0v, p1x, p1y, p1w, p1u, p1v, p2x, p2y, p2w, p2u, p2v, colour, opt_fragment_shader, uniforms)
					end
				end
			end
		end
	end

	select(1, pipeline).set_uniform = function(_, name, value)
		uniforms[name] = value
	end

	select(1, pipeline).get_uniform = function(_, name)
		return uniforms[name]
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
	local c = v3d
	c[name] = fn
end

set_function('create_framebuffer', create_framebuffer)
set_function('create_framebuffer_subpixel', create_framebuffer_subpixel)
set_function('create_camera', create_camera)
set_function('create_geometry', create_geometry)
set_function('create_debug_cube', create_debug_cube)
set_function('create_pipeline', create_pipeline)

return v3d
