
-- #remove
-- This file simply defines the V3D library, including all the functions and
-- types. There is no practical code here - that's defined in
-- `implementation.lua`. The two files are combined and minified during the
-- build process (see
-- https://github.com/exerro/v3d/wiki/Installation#build-from-source).
-- #end

-- TODO: make pipelines use new V3DGeometry and layouts with ~existing interface
-- TODO: allow pipelines to interpolate arbitrary attributes and pass arbitrary
--       face attributes in to fragment shaders by runtime-loading function
--       strings with pipeline-local modifications
-- TODO: use V3DTransform instead of V3DCamera


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
--- TODO
--- @field DEFAULT_LAYOUT V3DLayout
local v3d = {}

--- Create an empty [[@V3DFramebuffer]] of exactly `width` x `height` pixels.
---
--- Note, for using subpixel rendering (you probably are), use
--- `create_framebuffer_subpixel` instead.
--- @param width integer
--- @param height integer
--- @param label string | nil Optional label for debugging
--- @return V3DFramebuffer
function v3d.create_framebuffer(width, height, label) end

--- Create an empty [[@V3DFramebuffer]] of exactly `width * 2` x `height * 3`
--- pixels, suitable for rendering subpixels.
--- @param width integer
--- @param height integer
--- @param label string | nil Optional label for debugging
--- @return V3DFramebuffer
function v3d.create_framebuffer_subpixel(width, height, label) end

--- Create an empty [[@V3DLayout]].
--- @param label string | nil Optional label for debugging
--- @return V3DLayout
function v3d.create_layout(label) end

--- Create an empty [[@V3DGeometryBuilder]] with the given layout.
--- @param layout V3DLayout
--- @return V3DGeometryBuilder
function v3d.create_geometry_builder(layout) end

--- Create a [[@V3DCamera]] with the given field of view. FOV defaults to 30
--- degrees.
--- @param fov number | nil
--- @param label string | nil Optional label for debugging
--- @return V3DCamera
function v3d.create_camera(fov, label) end

--- Create an empty [[@V3DGeometry]] with no triangles.
--- @param type V3DGeometryType
--- @param label string | nil Optional label for debugging
--- @return V3DGeometry
function v3d.create_geometry(type, label) end

--- Create a [[@V3DGeometry]] cube containing coloured triangles with UVs.
--- @param cx number | nil Centre X coordinate of the cube.
--- @param cy number | nil Centre Y coordinate of the cube.
--- @param cz number | nil Centre Z coordinate of the cube.
--- @param size number | nil Distance between opposide faces of the cube.
--- @param label string | nil Optional label for debugging
--- @return V3DGeometry
function v3d.create_debug_cube(cx, cy, cz, size, label) end

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
--- @param label string | nil Optional label for debugging
--- @return V3DPipeline
function v3d.create_pipeline(options, label) end


--- TODO
--- @param texture_uniform string | nil TODO
--- @param width_uniform string | nil TODO
--- @param height_uniform string | nil TODO
--- @return V3DFragmentShader
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
--- @param type 'vertex' | 'face'
--- @param is_numeric true | false
--- @return V3DLayout
function V3DLayout:add_attribute(name, size, type, is_numeric) end

--- TODO
--- @param name string
--- @return boolean
function V3DLayout:has_attribute(name) end

--- TODO
--- @param name string
--- @return V3DLayoutAttribute | nil
function V3DLayout:get_attribute(name) end


--------------------------------------------------------------------------------
--[ Geometry ]------------------------------------------------------------------
--------------------------------------------------------------------------------


--- TODO
--- @class V3DGeometry2: { [integer]: any }
--- TODO
--- @field layout V3DLayout
--- TODO
--- @field vertices integer
--- TODO
--- @field faces integer
--- TODO
--- @field vertex_offset integer
local V3DGeometry2 = {}

--- TODO
--- @return V3DGeometryBuilder
function V3DGeometry2:to_builder() end


----------------------------------------------------------------


--- TODO
--- @class V3DGeometryBuilder
--- TODO
--- @field layout V3DLayout
--- TODO
--- @field vertices integer
--- TODO
--- @field faces integer
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
function V3DGeometryBuilder:build(label) end


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

--- Set the position of the camera.
--- @param x number | nil New X value, defaults to current value if nil.
--- @param y number | nil New Y value, defaults to current value if nil.
--- @param z number | nil New Z value, defaults to current value if nil.
--- @return nil
function V3DCamera:set_position(x, y, z) end

--- Set the rotation of the camera.
--- @param x number | nil New X rotation, defaults to current rotation if nil.
--- @param y number | nil New Y rotation, defaults to current rotation if nil.
--- @param z number | nil New Z rotation, defaults to current rotation if nil.
--- @return nil
function V3DCamera:set_rotation(x, y, z) end

--- Set the field of view of the camera.
--- @param fov number
--- @return nil
function V3DCamera:set_fov(fov) end


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

--- Pseudo-class listing the engine-provided uniform values for shaders.
--- @class V3DUniforms: { [string]: unknown }
--- Index of the geometry object currently being drawn.
--- @field u_instanceID integer
--- Index of the triangle within the geometry currently being drawn.
--- @field u_faceID integer
--- Colour of the face being drawn, if provided.
--- @field u_face_colour integer | nil
local V3DUniforms = {}

-- TODO: support returning depth as 2nd param
-- TODO: screen X/Y, depth (new & old)
--- A fragment shader runs for every pixel being drawn, accepting the
--- interpolated UV coordinates of that pixel if UV interpolation is enabled in
--- the pipeline settings.
--- The shader should return a value to be written directly to the framebuffer.
--- Note: if `nil` is returned, no pixel is written, and the depth value is not
--- updated for that pixel.
---
--- `uniforms` is a table containing the values for all user-set uniforms, plus
--- certain special values listed under [[@V3DUniforms]].
--- @alias V3DFragmentShader fun(uniforms: V3DUniforms, u: number, v: number): integer | nil

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
