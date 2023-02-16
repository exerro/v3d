
-- #remove
-- This file simply defines the V3D library, including all the functions and
-- types. There is no practical code here - that's defined in
-- `implementation.lua`. The two files are combined and minified during the
-- build process (see
-- https://github.com/exerro/v3d/wiki/Installation#build-from-source).
-- #end

-- TODO: statistics with render_geometry!
-- TODO: make V3DGeometryBuilder be able to splice attributes


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
--- TODO
--- @field DEFAULT_LAYOUT V3DLayout
--- TODO
--- @field UV_LAYOUT V3DLayout
--- TODO
--- @field DEBUG_CUBE_LAYOUT V3DLayout
local v3d = {}

--- Create an empty [[@V3DFramebuffer]] of exactly `width` x `height` pixels.
---
--- Note, for using subpixel rendering (you probably are), use
--- `create_framebuffer_subpixel` instead.
--- @param width integer Width of the framebuffer in pixels
--- @param height integer Height of the framebuffer in pixels
--- @param label string | nil Optional label for debugging
--- @return V3DFramebuffer
--- @nodiscard
function v3d.create_framebuffer(width, height, label) end

--- Create an empty [[@V3DFramebuffer]] of exactly `width * 2` x `height * 3`
--- pixels, suitable for rendering subpixels.
--- @param width integer Width of the framebuffer in full screen pixels
--- @param height integer Height of the framebuffer in full screen pixels
--- @param label string | nil Optional label for debugging
--- @return V3DFramebuffer
--- @nodiscard
function v3d.create_framebuffer_subpixel(width, height, label) end

--- Create an empty [[@V3DLayout]].
--- @return V3DLayout
--- @nodiscard
function v3d.create_layout() end

--- Create an empty [[@V3DGeometryBuilder]] with the given layout.
--- @param layout V3DLayout
--- @return V3DGeometryBuilder
--- @nodiscard
function v3d.create_geometry_builder(layout) end

--- Create a [[@V3DGeometryBuilder]] cube in the [[@v3d.DEBUG_CUBE_LAYOUT]]
--- layout.
--- @param cx number | nil Centre X coordinate of the cube.
--- @param cy number | nil Centre Y coordinate of the cube.
--- @param cz number | nil Centre Z coordinate of the cube.
--- @param size number | nil Distance between opposide faces of the cube.
--- @return V3DGeometryBuilder
--- @nodiscard
function v3d.create_debug_cube(cx, cy, cz, size) end

--- Create a [[@V3DTransform]] which has no effect.
--- @return V3DTransform
--- @nodiscard
function v3d.identity() end

--- Create a [[@V3DTransform]] which translates points by `(dx, dy, dz)` units.
--- Note: the `translate` parameter of [[@V3DTransform.transform]] must be true
--- for this to have any effect.
--- @param dx number
--- @param dy number
--- @param dz number
--- @return V3DTransform
--- @nodiscard
function v3d.translate(dx, dy, dz) end

--- Create a [[@V3DTransform]] which scales (multiplies) points by
--- `(sx, sy, sz)` units.
--- @param sx number
--- @param sy number
--- @param sz number
--- @overload fun(sx: number, sy: number, sz: number): V3DTransform
--- @overload fun(scale: number): V3DTransform
--- @return V3DTransform
--- @nodiscard
function v3d.scale(sx, sy, sz) end

--- Create a [[@V3DTransform]] which rotates points by `(tx, ty, tz)` radians
--- around `(0, 0, 0)`. The order of rotation is ZXY, that is it rotates Y
--- first, then X, then Z.
--- @param tx number
--- @param ty number
--- @param tz number
--- @return V3DTransform
--- @nodiscard
function v3d.rotate(tx, ty, tz) end

--- TODO
--- @param x number
--- @param y number
--- @param z number
--- @param x_rotation number
--- @param y_rotation number
--- @param z_rotation number
--- @param fov number | nil
--- @overload fun(x: number, y: number, z: number, x_rotation: number, y_rotation: number, z_rotation: number, fov: number | nil): V3DTransform
--- @overload fun(x: number, y: number, z: number, y_rotation: number, fov: number | nil): V3DTransform
--- @overload fun(x: number, y: number, z: number): V3DTransform
--- @overload fun(fov: number | nil): V3DTransform
--- @return V3DTransform
--- @nodiscard
function v3d.camera(x, y, z, x_rotation, y_rotation, z_rotation, fov) end

--- Create a [[@V3DPipeline]] with the given options. Options can be omitted to
--- use defaults, and any field within the options can also be omitted to use
--- defaults.
---
--- Example usage:
--- ```lua
--- local pipeline = v3d.create_pipeline {
--- 	layout = v3d.DEFAULT_LAYOUT,
--- 	cull_face = false,
--- }
--- ```
--- @param options V3DPipelineOptions
--- @param label string | nil Optional label for debugging
--- @return V3DPipeline
--- @nodiscard
function v3d.create_pipeline(options, label) end


--- TODO
--- @param texture_uniform string | nil TODO
--- @param width_uniform string | nil TODO
--- @param height_uniform string | nil TODO
--- @return V3DFragmentShader
--- @nodiscard
function v3d.create_texture_sampler(texture_uniform, width_uniform, height_uniform) end


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

--- Sets every pixel's colour to the provided colour value. If `clear_depth` is
--- not false, this resets the depth values to `0` as well.
--- @param colour integer | nil Defaults to 1 (colours.white)
--- @param clear_depth boolean | nil Whether to clear the depth values. Defaults to `true`.
--- @return nil
function V3DFramebuffer:clear(colour, clear_depth) end

--- Sets every pixel's depth to the provided depth value. Note: the value
--- representing "infinite" depth when nothing has been drawn is 0. The value
--- stored in this buffer should be 1/depth, so something 2 units away will have
--- 0.5 in the depth buffer.
--- @param depth_reciprocal number
--- @return nil
function V3DFramebuffer:clear_depth(depth_reciprocal) end

--- Render the framebuffer to the terminal, drawing a high resolution image
--- using subpixel conversion.
--- @param term table CC term API, e.g. 'term', or a window object you want to draw to.
--- @param dx integer | nil Horizontal integer pixel offset when drawing. 0 (default) means no offset.
--- @param dy integer | nil Vertical integer pixel offset when drawing. 0 (default) means no offset.
--- @return nil
function V3DFramebuffer:blit_term_subpixel(term, dx, dy) end

--- Similar to `blit_subpixel` but draws the depth instead of colour.
--- @param term table CC term API, e.g. 'term', or a window object you want to draw to.
--- @param dx integer | nil Horizontal integer pixel offset when drawing. 0 (default) means no offset.
--- @param dy integer | nil Vertical integer pixel offset when drawing. 0 (default) means no offset.
--- @param update_palette boolean | nil Whether to update the term palette to better show depth. Defaults to true.
--- @return nil
function V3DFramebuffer:blit_term_subpixel_depth(term, dx, dy, update_palette) end

--- TODO
--- @param term table CC term API, e.g. 'term', or a window object you want to draw to.
--- @param dx integer | nil Horizontal integer pixel offset when drawing. 0 (default) means no offset.
--- @param dy integer | nil Vertical integer pixel offset when drawing. 0 (default) means no offset.
--- @return nil
function V3DFramebuffer:blit_graphics(term, dx, dy) end

--- TODO
--- @param term table CC term API, e.g. 'term', or a window object you want to draw to.
--- @param dx integer | nil Horizontal integer pixel offset when drawing. 0 (default) means no offset.
--- @param dy integer | nil Vertical integer pixel offset when drawing. 0 (default) means no offset.
--- @param update_palette boolean | nil Whether to update the term palette to better show depth. Defaults to true.
--- @return nil
function V3DFramebuffer:blit_graphics_depth(term, dx, dy, update_palette) end


--------------------------------------------------------------------------------
--[ Layouts ]-------------------------------------------------------------------
--------------------------------------------------------------------------------


--- TODO
--- @class V3DLayout
--- TODO
--- @field attributes V3DLayoutAttribute[]
--- TODO
--- @field private attribute_lookup { [string]: integer | nil }
--- TODO
--- @field vertex_stride integer
--- TODO
--- @field face_stride integer
local V3DLayout = {}

--- TODO
--- @class V3DLayoutAttribute
--- TODO
--- @field name string
--- TODO
--- @field size integer
--- TODO
--- @field type 'vertex' | 'face'
--- TODO
--- @field is_numeric boolean
--- TODO
--- @field offset integer
local V3DLayoutAttribute = {}

--- TODO
--- @param name string
--- @param size integer
--- @param is_numeric true | false
--- @return V3DLayout
--- @nodiscard
function V3DLayout:add_vertex_attribute(name, size, is_numeric) end

--- TODO
--- @param name string
--- @param size integer
--- @return V3DLayout
--- @nodiscard
function V3DLayout:add_face_attribute(name, size) end

--- TODO
--- @param attribute string | V3DLayoutAttribute
--- @return V3DLayout
--- @nodiscard
function V3DLayout:drop_attribute(attribute) end

--- TODO
--- @param attribute string | V3DLayoutAttribute
--- @return boolean
function V3DLayout:has_attribute(attribute) end

--- TODO
--- @param name string
--- @return V3DLayoutAttribute | nil
function V3DLayout:get_attribute(name) end


--------------------------------------------------------------------------------
--[ Geometry ]------------------------------------------------------------------
--------------------------------------------------------------------------------


--- TODO
--- @class V3DGeometry: { [integer]: any }
--- TODO
--- @field layout V3DLayout
--- TODO
--- @field vertices integer
--- TODO
--- @field faces integer
--- TODO
--- @field vertex_offset integer
local V3DGeometry = {}

--- TODO
--- @return V3DGeometryBuilder
function V3DGeometry:to_builder() end


----------------------------------------------------------------


--- TODO
--- @class V3DGeometryBuilder
--- TODO
--- @field layout V3DLayout
--- TODO
--- @field private attribute_data { [string]: any[] }
local V3DGeometryBuilder = {}

--- TODO
--- @param attribute_name string
--- @param data any[]
--- @return V3DGeometryBuilder
function V3DGeometryBuilder:set_data(attribute_name, data) end

--- TODO
--- @param attribute_name string
--- @param data any[]
--- @return V3DGeometryBuilder
function V3DGeometryBuilder:append_data(attribute_name, data) end

--- TODO
--- @param attribute_name string
--- @param fn fun(data: any[]): any[]
--- @return V3DGeometryBuilder
function V3DGeometryBuilder:map(attribute_name, fn) end

-- TODO: implement once we have V3DTransform
--- TODO
--- @param attribute_name string
--- @param transform nil
--- @return V3DGeometryBuilder
function V3DGeometryBuilder:transform(attribute_name, transform) end

--- TODO
--- @param other V3DGeometryBuilder
--- @return V3DGeometryBuilder
function V3DGeometryBuilder:insert(other) end

--- TODO
--- @param layout V3DLayout
--- @return V3DGeometryBuilder
function V3DGeometryBuilder:cast(layout) end

--- TODO
--- @param label string | nil
--- @return V3DGeometry
--- @nodiscard
function V3DGeometryBuilder:build(label) end


--------------------------------------------------------------------------------
--[ Transforms ]----------------------------------------------------------------
--------------------------------------------------------------------------------


--- TODO
--- @class V3DTransform
--- @operator mul (V3DTransform): V3DTransform
local V3DTransform = {}

--- TODO
--- @param transform V3DTransform
--- @return V3DTransform
--- @nodiscard
function V3DTransform:combine(transform) end

--- TODO
--- @param data { [1]: number, [2]: number, [3]: number }
--- @param translate boolean
--- @return { [1]: number, [2]: number, [3]: number }
--- @nodiscard
function V3DTransform:transform(data, translate) end


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
--- TODO
--- @field source string
--- TODO
--- @field source_error string | nil
local V3DPipeline = {}

--- Specifies which face to cull, either the front or back face.
---
--- See also: [[@v3d.CULL_FRONT_FACE]], [[@v3d.CULL_BACK_FACE]]
--- @alias V3DCullFace 1 | -1

--- Pseudo-class listing the engine-provided uniform values for shaders.
--- @alias V3DUniforms { [string]: unknown }

-- TODO: support returning depth as 2nd param
-- TODO: screen X/Y, depth (new & old), face index
--- A fragment shader runs for every pixel being drawn, accepting the
--- interpolated UV coordinates of that pixel if UV interpolation is enabled in
--- the pipeline settings.
--- The shader should return a value to be written directly to the framebuffer.
--- Note: if `nil` is returned, no pixel is written, and the depth value is not
--- updated for that pixel.
---
--- `uniforms` is a table containing the values for all user-set uniforms, plus
--- certain special values listed under [[@V3DUniforms]].
--- @alias V3DFragmentShader fun(uniforms: V3DUniforms, ...: unknown): integer | nil

--- Pipeline options describe the settings used to create a pipeline. Most
--- fields are optional and have a sensible default. Not using or disabling
--- features may lead to a performance gain, for example disabling depth testing
--- or not using shaders.
--- @class V3DPipelineOptions
--- TODO
--- @field layout V3DLayout
--- TODO
--- @field position_attribute string | nil
--- TODO
--- @field colour_attribute string | nil
--- Names of the attributes to interpolate values across polygons being drawn.
--- Only useful when using fragment shaders, and has a slight performance loss
--- when used. Defaults to `nil`.
--- @field attributes string[] | nil
--- TODO
--- @field pack_attributes boolean | nil
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
--- Aspect ratio of the pixels being drawn. For square pixels, this should be 1.
--- For non-square pixels, like the ComputerCraft non-subpixel characters, this
--- should be their width/height, for example 2/3 for non-subpixel characters.
--- Defaults to `1`.
--- @field pixel_aspect_ratio number | nil
local V3DPipelineOptions = {}

--- Draw geometry to the framebuffer using the transforms given.
--- @param geometry V3DGeometry List of geometry to draw.
--- @param framebuffer V3DFramebuffer Framebuffer to draw to.
--- @param transform V3DTransform TODO
--- @param model_transform V3DTransform | nil TODO
--- @return nil
function V3DPipeline:render_geometry(geometry, framebuffer, transform, model_transform) end

--- Set a uniform value which can be accessed from shaders.
--- @param name string Name of the uniform. Shaders can access using `uniforms[name]`
--- @param value any Any value to pass to the shader.
--- @return nil
function V3DPipeline:set_uniform(name, value) end

--- Get a uniform value that's been set with `set_uniform`.
--- @param name string Name of the uniform.
--- @return unknown
function V3DPipeline:get_uniform(name) end

--- Get a list of uniform names that have been set with `set_uniform`.
--- @return string[]
function V3DPipeline:list_uniforms() end


--------------------------------------------------------------------------------
-- We're now done with the declarations!
--- @diagnostic enable: missing-return, unused-local
--------------------------------------------------------------------------------

-- #remove
return v3d
-- #end
