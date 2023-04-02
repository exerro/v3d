
-- #remove
-- This file simply defines the V3D library, including all the functions and
-- types. There is no practical code here - that's defined in
-- `implementation.lua`. The two files are combined and minified during the
-- build process (see
-- https://github.com/exerro/v3d/wiki/Installation#build-from-source).
-- #end

-- TODO: make V3DGeometryBuilder be able to splice attributes


--- @diagnostic disable: missing-return, unused-local

--------------------------------------------------------------------------------
--[ V3D ]-----------------------------------------------------------------------
--------------------------------------------------------------------------------

--- @class v3d
local v3d = {}

--- Specify to cull (not draw) the front face (facing towards the camera).
--- / CULL_FRONT_FACE V3DCullFace

--- Specify to cull (not draw) the back face (facing away from the camera).
--- / CULL_BACK_FACE V3DCullFace

--------------------------------------------------------------------------------
--[ Pipelines ]-----------------------------------------------------------------
--------------------------------------------------------------------------------

-- TODO: v3d.shaders.write_constant()
-- TODO: v3d.shaders.write_attribute()
-- TODO: v3d.shaders.write_uniform()
-- TODO: v3d.shaders.depth_test()
-- TODO: v3d.shaders.combine()

--- Create a [[@V3DPipeline]] with the given options.
--- @param options V3DPipelineOptions Immutable options for the pipeline.
--- @param label string | nil Optional label for debugging
--- @return V3DPipeline
--- @nodiscard
function v3d.create_pipeline(options, label) end

do -- V3DCullFace
	--- Specifies which face to cull, either the front or back face.
	---
	--- See also: [[@v3d.CULL_FRONT_FACE]], [[@v3d.CULL_BACK_FACE]]
	--- @alias V3DCullFace 1 | -1
end

do -- V3DUniforms
	--- Pseudo-class listing the engine-provided uniform values for shaders.
	--- @alias V3DUniforms { [string]: unknown }
end

do -- VFSL
	--- V3D fragment shader language.
	--- Normal Lua code, with some macros and constraints on variable names.
	--- * Variable names beginning with `_v3d` should strictly not be used.
	--- * Variable names beginning with `v3d` should not be used besides using
	---   the macros listed below.
	---
	--- ### Macros
	---
	--- v3d_pixel_aspect_ratio()
	--- v3d_transform()
	--- v3d_model_transform()
	---
	--- v3d_read_attribute_values(string-literal)
	--- v3d_read_attribute(string-literal)
	--- v3d_read_attribute(string-literal, integer-literal)
	---
	--- v3d_read_attribute_gradient(string-literal)
	--- v3d_read_attribute_gradient(string-literal, integer-literal)
	---
	--- v3d_write_layer_values(string-literal, any...)
	--- v3d_write_layer(string-literal, any)
	--- v3d_write_layer(string-literal, integer-literal, any)
	--- v3d_read_layer_values(string-literal)
	--- v3d_read_layer(string-literal)
	--- v3d_read_layer(string-literal, integer-literal)
	--- v3d_was_layer_written(string-literal)
	--- v3d_was_layer_written()
	---
	--- v3d_write_uniform(string-literal, any)
	--- v3d_read_uniform(string-literal)
	--- 
	--- v3d_framebuffer_size('width' | 'height' | 'width-1' | 'height-1')
	--- v3d_framebuffer_width()
	--- v3d_framebuffer_height()
	---
	--- v3d_face_row_bounds()
	--- v3d_face_row_bounds('min' | 'max')
	--- v3d_row_column_bounds()
	--- v3d_row_column_bounds('min' | 'max')
	---
	--- v3d_face_world_normal()
	--- v3d_face_world_normal('x' | 'y' | 'z')
	---
	--- v3d_face_was_clipped()
	---
	--- v3d_fragment_polygon_section()
	---
	--- v3d_fragment_is_face_front_facing()
	---
	--- v3d_fragment_depth()
	---
	--- v3d_fragment_screen_position()
	--- v3d_fragment_screen_position('x' | 'y')
	---
	--- v3d_fragment_view_position()
	--- v3d_fragment_view_position('x' | 'y' | 'z')
	---
	--- v3d_fragment_world_position()
	--- v3d_fragment_world_position('x' | 'y' | 'z')
	---
	--- v3d_discard_fragment()
	--- v3d_was_fragment_discarded()
	---
	--- v3d_compare_depth(any, any)
	---
	--- v3d_count_event(string-literal)
	--- v3d_count_event(string-literal, any)
	---
	--- TODO:
	--- To write a value to a layer in the framebuffer, use
	--- `v3d_write_layer(layer, values...)`, for example
	--- `v3d_write_layer('rgb_colour', r, g, b)`, or
	--- `v3d_write_layer('colour', sample_texture(u_texture, uv0, uv1))`. Note
	--- that calls to this 'function' are actually expanded into assignment
	--- expressions. As a result, don't call this 'function' in an expression
	--- context.
	--- E.g. `v3d_write_layer(...)` is fine, but `v = v3d_write_layer(...)` is
	--- not.
	---
	--- To read a value from a layer in the framebuffer, use
	--- `v3d_read_layer(layer)`, for example
	--- `local r, g, b = v3d_read_layer('rgb_colour')`.
	--- @class VFSL
end

do -- VFSLString
	--- A string containing [[@VFSL]] (v3d fragment shader language) code.
	--- @alias VFSLString string
end

do -- V3DStatistics*
	--- TODO
	--- @class V3DStatistics
	--- TODO
	--- @field total_time number
	--- TODO
	--- @field rasterize_time number
	--- TODO
	--- @field candidate_faces integer
	--- TODO
	--- @field drawn_faces integer
	--- TODO
	--- @field culled_faces integer
	--- TODO
	--- @field clipped_faces integer
	--- TODO
	--- @field discarded_faces integer
	--- TODO
	--- @field candidate_fragments integer
	--- TODO
	--- @field timers { [string]: number }
	--- TODO
	--- @field events { [string]: integer }
end

do -- V3DPipelineOptions
	--- Pipeline options describe the settings used to create a pipeline. Most
	--- fields are optional and have a sensible default. Different combinations
	--- of options will affect the performance of geometry drawn with this
	--- pipeline.
	--- @class V3DPipelineOptions
	--- TODO
	--- @field layout v3d.Layout
	--- Format of the [[@v3d.Geometry]] that this pipeline is compatible with. A
	--- pipeline cannot draw geometry of other formats, and cannot change its
	--- format. This parameter is not optional.
	--- @field format v3d.Format
	--- Specify which attribute vertex positions are stored in. Must be a
	--- numeric, 3 component vertex attribute.
	--- @field position_attribute v3d.AttributeName
	--- Specify a face to cull (not draw), or false to disable face culling.
	--- Defaults to [[@v3d.CULL_BACK_FACE]]. This is a technique to improve
	--- performance and should only be changed from the default when doing something
	--- weird. For example, to not draw faces facing towards the camera, use
	--- `cull_face = v3d.CULL_FRONT_FACE`.
	--- @field cull_face V3DCullFace | false | nil
	--- Lua code which will run for every candidate pixel of a polygon. This
	--- code is entirely responsible for writing values to framebuffer layers
	--- and implementing any custom logic.
	--- @field fragment_shader VFSLString
	--- Aspect ratio of the pixels being drawn. For square pixels, this should be 1.
	--- For non-square pixels, like the ComputerCraft non-subpixel characters, this
	--- should be their width/height, for example 2/3 for non-subpixel characters.
	--- Defaults to `1`.
	--- @field pixel_aspect_ratio number | nil
	--- TODO
	--- @field statistics boolean | nil
end

do -- V3DPipeline
	--- A pipeline is an optimised object used to draw [[@v3d.Geometry]] to a
	--- [[@v3d.Framebuffer]] using a [[@v3d.Transform]]. It is created using
	--- [[@V3DPipelineOptions]] which cannot change. To configure the pipeline after
	--- creation, uniforms can be used alongside shaders. Alternatively, multiple
	--- pipelines can be created or re-created at will according to the needs of the
	--- application.
	--- @class V3DPipeline
	--- Options that the pipeline is using. Note that this differs to the ones it
	--- was created with, as these options will have defaults applied etc.
	--- @field options V3DPipelineOptions
	--- Source code used to load the pipeline's `render_geometry` function.
	--- @field source string
	local V3DPipeline = {}

	--- Draw geometry to the framebuffer using the transforms given.
	--- @param geometry v3d.Geometry List of geometry to draw.
	--- @param framebuffer v3d.Framebuffer Framebuffer to draw to.
	--- @param transform v3d.Transform Transform applied to all vertices.
	--- @param model_transform v3d.Transform | nil Transform applied to all vertices before `transform`, if specified.
	--- @return V3DStatistics
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
end

--------------------------------------------------------------------------------
-- We're now done with the declarations!
--- @diagnostic enable: missing-return, unused-local
--------------------------------------------------------------------------------

-- #remove
return v3d
-- #end
