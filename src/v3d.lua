
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

--- V3D library instance. Used to create all objects for rendering, and refer to
--- enum values.
--- @class v3d
--- Specify to cull (not draw) the front face (facing towards the camera).
--- @field CULL_FRONT_FACE V3DCullFace
--- Specify to cull (not draw) the back face (facing away from the camera).
--- @field CULL_BACK_FACE V3DCullFace
--- Framebuffer format with just a colour attachment.
--- @field COLOUR_FORMAT V3DFormat
--- Framebuffer format with colour and depth attachments.
--- @field COLOUR_DEPTH_FORMAT V3DFormat
--- A default layout containing just position and colour attributes.
--- @field DEFAULT_LAYOUT V3DLayout
--- A layout containing just position and UV attributes, useful for textures or
--- other UV based rendering.
--- @field UV_LAYOUT V3DLayout
--- The layout used by [[@v3d.create_debug_cube]], containing the following
--- attributes:
--- * `position` - numeric vertex attribute - 3 components
--- * `uv` - numeric vertex attribute - 2 components
--- * `colour` - face attribute - 1 components
--- * `face_normal` - face attribute - 3 components
--- * `face_index` - face attribute - 1 components
--- * `side_index` - face attribute - 1 components
--- * `side_name` - face attribute - 1 components
--- @field DEBUG_CUBE_LAYOUT V3DLayout
local v3d = {}

do
	--- Create a [[@V3DGeometryBuilder]] cube in the [[@v3d.DEBUG_CUBE_LAYOUT]]
	--- layout.
	--- @param cx number | nil Centre X coordinate of the cube.
	--- @param cy number | nil Centre Y coordinate of the cube.
	--- @param cz number | nil Centre Z coordinate of the cube.
	--- @param size number | nil Distance between opposide faces of the cube.
	--- @return V3DGeometryBuilder
	--- @nodiscard
	function v3d.create_debug_cube(cx, cy, cz, size) end

	--- TODO
	--- @param texture_uniform string | nil TODO
	--- @param width_uniform string | nil TODO
	--- @param height_uniform string | nil TODO
	--- @return V3DFragmentShader
	--- @nodiscard
	function v3d.create_texture_sampler(texture_uniform, width_uniform, height_uniform) end
end

--------------------------------------------------------------------------------
--[ Framebuffers ]--------------------------------------------------------------
--------------------------------------------------------------------------------

--- Create an empty [[@V3DFormat]].
--- See also: [[@v3d.COLOUR]], [[@v3d.COLOUR_DEPTH_FORMAT]]
--- @return V3DFormat
--- @nodiscard
function v3d.create_format() end

--- Create an empty [[@V3DFramebuffer]] of exactly `width` x `height` pixels.
---
--- Note, for using subpixel rendering (you probably are), use
--- `create_framebuffer_subpixel` instead.
--- @param format V3DFormat Format of the framebuffer, i.e. what data it contains.
--- @param width integer Width of the framebuffer in pixels
--- @param height integer Height of the framebuffer in pixels
--- @param label string | nil Optional label for debugging
--- @return V3DFramebuffer
--- @nodiscard
function v3d.create_framebuffer(format, width, height, label) end

--- Create an empty [[@V3DFramebuffer]] of exactly `width * 2` x `height * 3`
--- pixels, suitable for rendering subpixels.
--- @param format V3DFormat Format of the framebuffer, i.e. what data it contains.
--- @param width integer Width of the framebuffer in full screen pixels
--- @param height integer Height of the framebuffer in full screen pixels
--- @param label string | nil Optional label for debugging
--- @return V3DFramebuffer
--- @nodiscard
function v3d.create_framebuffer_subpixel(format, width, height, label) end

do -- V3DAttachmentName
	--- Name of an attachment. Should be a string matching the following Lua
	--- pattern: `[a-zA-Z][a-zA-Z0-9_]*`.
	--- @alias V3DAttachmentName string
end

do -- V3DAttachmentType
	--- TODO
	--- @alias V3DAttachmentType 'palette-index' | 'exp-palette-index' | 'depth-reciprocal' | 'any-numeric' | 'any'
end

do -- V3DAttachment
	--- TODO
	--- @class V3DAttachment
	--- TODO
	--- @field name V3DAttachmentName
	--- TODO
	--- @field type V3DAttachmentType
	--- TODO
	--- @field components integer
end

do -- V3DFormat
	--- TODO
	--- @class V3DFormat
	--- TODO
	--- @field attachments V3DAttachment[]
	--- TODO
	--- @field private attachment_lookup { [V3DAttachmentName]: integer | nil }
	local V3DFormat = {}

	--- TODO
	--- @param name V3DAttachmentName
	--- @param type V3DAttachmentType
	--- @param components integer
	--- @return V3DFormat
	--- @nodiscard
	function V3DFormat:add_attachment(name, type, components) end

	--- TODO
	--- @param attachment V3DAttachmentName | V3DAttachment
	--- @return V3DFormat
	--- @nodiscard
	function V3DFormat:drop_attachment(attachment) end

	--- TODO
	--- @param attachment V3DAttachmentName | V3DAttachment
	--- @return boolean
	function V3DFormat:has_attachment(attachment) end

	--- TODO
	--- @param name V3DAttachmentName
	--- @return V3DAttachment | nil
	function V3DFormat:get_attachment(name) end
end

do -- CCTermAPI
	--- ComputerCraft native terminal objects, for example `term` or `window`
	--- objects.
	--- @alias CCTermAPI {}
end

do -- V3DFramebuffer
	--- Stores the per-pixel data for rendered triangles.
	--- @class V3DFramebuffer
	--- Format of the framebuffer which determines which data the framebuffer
	--- stores.
	--- @field format V3DFormat
	--- Width of the framebuffer in pixels. Note, if you're using subpixel
	--- rendering, this includes the subpixels, e.g. a 51x19 screen would have a
	--- width of 102 pixels in its framebuffer.
	--- @field width integer
	--- Height of the framebuffer in pixels. Note, if you're using subpixel
	--- rendering, this includes the subpixels, e.g. a 51x19 screen would have a
	--- height of 57 pixels in its framebuffer.
	--- @field height integer
	--- @field private attachment_data { [V3DAttachmentName]: unknown[] }
	local V3DFramebuffer = {}

	--- Get the data for a given attachment
	--- @param attachment V3DAttachmentName
	--- @return unknown[]
	--- @nodiscard
	function V3DFramebuffer:get_buffer(attachment) end

	--- Sets the data for the entire attachment to a particular value. If `value` is
	--- nil, a default value based on the attachment's type will be used, as
	--- follows:
	--- Type | Default
	--- -|-
	--- `palette-index` | `0`
	--- `exp-palette-index` | `1`
	--- `depth-reciprocal` | `0`
	--- `any-numeric` | `0`
	--- `any` | `false`
	--- @param attachment V3DAttachmentName
	--- @param value any | nil
	--- @return nil
	function V3DFramebuffer:clear(attachment, value) end

	--- Render the framebuffer to the terminal, drawing a high resolution image
	--- using subpixel conversion.
	--- @param term CCTermAPI CC term API, e.g. 'term', or a window object you want to draw to.
	--- @param attachment V3DAttachmentName TODO
	--- @param dx integer | nil Horizontal integer pixel offset when drawing. 0 (default) means no offset.
	--- @param dy integer | nil Vertical integer pixel offset when drawing. 0 (default) means no offset.
	--- @return nil
	function V3DFramebuffer:blit_term_subpixel(term, attachment, dx, dy) end

	-- TODO: remove this
	--- Similar to `blit_subpixel` but draws the depth instead of colour.
	--- @param term CCTermAPI CC term API, e.g. 'term', or a window object you want to draw to.
	--- @param dx integer | nil Horizontal integer pixel offset when drawing. 0 (default) means no offset.
	--- @param dy integer | nil Vertical integer pixel offset when drawing. 0 (default) means no offset.
	--- @param update_palette boolean | nil Whether to update the term palette to better show depth. Defaults to true.
	--- @return nil
	function V3DFramebuffer:blit_term_subpixel_depth(term, dx, dy, update_palette) end

	--- TODO
	--- @param term CCTermAPI CC term API, e.g. 'term', or a window object you want to draw to.
	--- @param attachment V3DAttachmentName TODO
	--- @param dx integer | nil Horizontal integer pixel offset when drawing. 0 (default) means no offset.
	--- @param dy integer | nil Vertical integer pixel offset when drawing. 0 (default) means no offset.
	--- @return nil
	function V3DFramebuffer:blit_graphics(term, attachment, dx, dy) end

	-- TODO: remove this
	--- TODO
	--- @param term CCTermAPI CC term API, e.g. 'term', or a window object you want to draw to.
	--- @param dx integer | nil Horizontal integer pixel offset when drawing. 0 (default) means no offset.
	--- @param dy integer | nil Vertical integer pixel offset when drawing. 0 (default) means no offset.
	--- @param update_palette boolean | nil Whether to update the term palette to better show depth. Defaults to true.
	--- @return nil
	function V3DFramebuffer:blit_graphics_depth(term, dx, dy, update_palette) end
end

--------------------------------------------------------------------------------
--[ Geometry ]------------------------------------------------------------------
--------------------------------------------------------------------------------

--- Create an empty [[@V3DLayout]].
--- @return V3DLayout
--- @nodiscard
function v3d.create_layout() end

--- Create an empty [[@V3DGeometryBuilder]] with the given layout.
--- @param layout V3DLayout Initial layout, which can be changed with [[@V3DGeometryBuilder.cast]].
--- @return V3DGeometryBuilder
--- @nodiscard
function v3d.create_geometry_builder(layout) end

do -- V3DAttributeName
	--- Name of an attribute. Should be a string matching the following Lua pattern:
	--- `[a-zA-Z][a-zA-Z0-9_]*`.
	--- @alias V3DAttributeName string
end

do -- V3DAttribute
	--- An attribute in a layout. Attributes represent a unit of data that can form
	--- vertices or faces of geometry. For example, "position" might be an
	--- attribute, as well as "colour" or "uv". Attributes have a number of fields
	--- that describe how much information is stored, and how it may be used.
	--- @class V3DAttribute
	--- Name of the attribute.
	--- @field name V3DAttributeName
	--- Number of components in this attribute, e.g. 3D position would have a size
	--- of `3`.
	--- @field size integer
	--- Whether this attribute has data stored per-vertex or per-face. Per-vertex
	--- attributes can have a unique for each vertex of every triangle in geometry.
	--- Per-face attributes have a single value for each triangle in geometry.
	--- @field type 'vertex' | 'face'
	--- Applies only to vertex attributes. Numeric vertex attributes can be
	--- transformed and interpolated by the library.
	---
	--- Note, this isn't enforced by the library, i.e. there is no explicit type
	--- checking or validation applied by default. This is a flag that can be used
	--- by debuggers and validators.
	--- @field is_numeric boolean
	--- Sum of the sizes of previous attributes of the same type.
	--- @field offset integer
end

do -- V3DLayout
	--- TODO
	--- @class V3DLayout
	--- TODO
	--- @field attributes V3DAttribute[]
	--- TODO
	--- @field private attribute_lookup { [string]: integer | nil }
	--- TODO
	--- @field vertex_stride integer
	--- TODO
	--- @field face_stride integer
	local V3DLayout = {}

	--- TODO
	--- @param name V3DAttributeName
	--- @param size integer
	--- @param is_numeric true | false
	--- @return V3DLayout
	--- @nodiscard
	function V3DLayout:add_vertex_attribute(name, size, is_numeric) end

	--- TODO
	--- @param name V3DAttributeName
	--- @param size integer
	--- @return V3DLayout
	--- @nodiscard
	function V3DLayout:add_face_attribute(name, size) end

	--- TODO
	--- @param attribute V3DAttributeName | V3DAttribute
	--- @return V3DLayout
	--- @nodiscard
	function V3DLayout:drop_attribute(attribute) end

	--- TODO
	--- @param attribute V3DAttributeName | V3DAttribute
	--- @return boolean
	function V3DLayout:has_attribute(attribute) end

	--- TODO
	--- @param name V3DAttributeName
	--- @return V3DAttribute | nil
	function V3DLayout:get_attribute(name) end
end

do -- V3DGeometry
	--- [[@V3DGeometry]] stores the data for shapes and triangles in an optimised
	--- format determined by its `layout`. Data is stored as a contiguous array of
	--- unpacked attribute components. [[@V3DPipeline]]s are then specifically
	--- compiled to draw geometry of a specific layout as quickly as possible.
	---
	--- Use [[@V3DGeometryBuilder.build]] to create a geometry instance.
	--- @class V3DGeometry
	--- [[@V3DLayout]] of this geometry, which defines the format data is stored in.
	--- @field layout V3DLayout
	--- Number of vertices contained within this geometry.
	--- @field vertices integer
	--- Number of faces contained within this geometry.
	--- @field faces integer
	--- Offset of the first vertex data. An offset of `0` would mean the first
	--- vertex starts from index `1`.
	--- @field vertex_offset integer
	local V3DGeometry = {}

	--- Convert this geometry back into a builder so it can be modified or
	--- transformed.
	--- @return V3DGeometryBuilder
	function V3DGeometry:to_builder() end
end

do -- V3DGeometryBuilder
	--- Object used to build [[@V3DGeometry]] instances. [[@V3DGeometry]] is stored
	--- in an optimised format which depends on its layout and is an implementation
	--- detail of the library. As a result, we use geometry builders to pass data
	--- for our geometry with a well-defined interface, and then build that to bake
	--- it into the optimised format.
	---
	--- Geometry builders let us set data for individual attributes, or append
	--- vertices and faces in one go.
	---
	--- See [[@V3DGeometryBuilder.set_data]], [[@V3DGeometryBuilder.cast]],
	--- [[@V3DGeometryBuilder.build]].
	--- @class V3DGeometryBuilder
	--- Layout of this geometry builder, used when building the geometry using
	--- [[@V3DGeometryBuilder.build]]. Can be changed with
	--- [[@V3DGeometryBuilder.cast]].
	--- @field layout V3DLayout
	--- @field private attribute_data { [V3DAttributeName]: any[] }
	local V3DGeometryBuilder = {}

	--- Set the data for an attribute, replacing any existing data.
	---
	--- See also: [[@V3DGeometryBuilder.append_data]]
	--- @param attribute_name V3DAttributeName Name of the attribute to set the data for.
	--- @param data any[] New data, which replaces any existing data.
	--- @return V3DGeometryBuilder
	function V3DGeometryBuilder:set_data(attribute_name, data) end

	--- Append data to the end of the existing data for an attribute.
	---
	--- See also: [[@V3DGeometryBuilder.set_data]]
	--- @param attribute_name V3DAttributeName Name of the attribute to append data to.
	--- @param data any[] New data to append.
	--- @return V3DGeometryBuilder
	function V3DGeometryBuilder:append_data(attribute_name, data) end

	-- TODO: append_vertex
	-- TODO: append_face

	--- Map a function to the data for an attribute. The table returned replaces the
	--- existing data for the attribute.
	---
	--- Note, it's fine to return the same table and mutate it (and arguably more
	--- performant if you do that).
	--- @param attribute_name V3DAttributeName Name of the attribute to apply `fn` to.
	--- @param fn fun(data: any[]): any[] Function called with the data for this attribute, which should return the new data.
	--- @return V3DGeometryBuilder
	function V3DGeometryBuilder:map(attribute_name, fn) end

	--- Transform the data for `attribute_name` using the transform provided.
	--- @param attribute_name V3DAttributeName Name of the numeric, 3 component vertex attribute to transform.
	--- @param transform V3DTransform Transformation to apply.
	--- @param translate boolean | nil Whether vertices should be translated. Defaults to true unless a 4-component attribute is given, in which case vertices are translated if the 4th component is equal to 1.
	--- @return V3DGeometryBuilder
	function V3DGeometryBuilder:transform(attribute_name, transform, translate) end

	--- Copy the data from `other` into this geometry builder. The layout of the
	--- other builder and this must be identical, and only data that is part of the
	--- layout will be copied.
	--- @param other V3DGeometryBuilder Geometry builder to copy data from.
	--- @return V3DGeometryBuilder
	function V3DGeometryBuilder:insert(other) end

	--- Change the layout of this geometry builder to `layout`. There are no
	--- requirements on the `layout` provided, and this function can be called as
	--- many times as necessary.
	---
	--- Note, the layout of a geometry builder affects how geometry is constructed
	--- when using [[@V3DGeometryBuilder.build]], as well as other functions.
	--- @param layout V3DLayout Any layout to change to.
	--- @return V3DGeometryBuilder
	function V3DGeometryBuilder:cast(layout) end

	--- Construct a [[@V3DGeometry]] instance using the data set in this builder.
	--- The resultant [[@V3DGeometry]] will have the same layout as this builder;
	--- consider using [[@V3DGeometryBuilder.cast]] to change layouts if necessary.
	--- @param label string | nil Optional label for the constructed [[@V3DGeometry]] instance.
	--- @return V3DGeometry
	--- @nodiscard
	function V3DGeometryBuilder:build(label) end
end

--------------------------------------------------------------------------------
--[ Transforms ]----------------------------------------------------------------
--------------------------------------------------------------------------------

--- Create a [[@V3DTransform]] which has no effect.
--- @return V3DTransform
--- @nodiscard
function v3d.identity() end

--- Create a [[@V3DTransform]] which translates points by `(dx, dy, dz)` units.
--- Note: the `translate` parameter of [[@V3DTransform.transform]] must be true
--- for this to have any effect.
--- @param dx number Delta X.
--- @param dy number Delta Y.
--- @param dz number Delta Z.
--- @return V3DTransform
--- @nodiscard
function v3d.translate(dx, dy, dz) end

--- Create a [[@V3DTransform]] which scales (multiplies) points by
--- `(sx, sy, sz)` units.
--- @param sx number Scale X.
--- @param sy number Scale Y.
--- @param sz number Scale Z.
--- @overload fun(sx: number, sy: number, sz: number): V3DTransform
--- @overload fun(scale: number): V3DTransform
--- @return V3DTransform
--- @nodiscard
function v3d.scale(sx, sy, sz) end

--- Create a [[@V3DTransform]] which rotates points by `(tx, ty, tz)` radians
--- around `(0, 0, 0)`. The order of rotation is ZXY, that is it rotates Y
--- first, then X, then Z.
--- @param tx number Amount to rotate around the X axis, in radians.
--- @param ty number Amount to rotate around the Y axis, in radians.
--- @param tz number Amount to rotate around the Z axis, in radians.
--- @return V3DTransform
--- @nodiscard
function v3d.rotate(tx, ty, tz) end

--- Create a [[@V3DTransform]] which simulates a camera. The various overloads
--- of this function allow you to specify the position, rotation, and FOV of the
--- camera. The resultant transform will apply the inverse translation and
--- rotation before scaling to apply the FOV.
---
--- Rotation is ZXY ordered, i.e. the inverse Y is applied first, then X, then
--- Z. This corresponds to pan, tilt, and roll.
--- @param x number X coordinate of the origin of the viewing frustum.
--- @param y number Y coordinate of the origin of the viewing frustum.
--- @param z number Z coordinate of the origin of the viewing frustum.
--- @param x_rotation number Rotation of the viewing frustum about the X axis.
--- @param y_rotation number Rotation of the viewing frustum about the Y axis.
--- @param z_rotation number Rotation of the viewing frustum about the Z axis.
--- @param fov number | nil Vertical field of view, i.e. the angle between the top and bottom planes of the viewing frustum. Defaults to PI / 3 (60 degrees).
--- @overload fun(x: number, y: number, z: number, x_rotation: number, y_rotation: number, z_rotation: number, fov: number | nil): V3DTransform
--- @overload fun(x: number, y: number, z: number, y_rotation: number, fov: number | nil): V3DTransform
--- @overload fun(x: number, y: number, z: number): V3DTransform
--- @overload fun(fov: number | nil): V3DTransform
--- @return V3DTransform
--- @nodiscard
function v3d.camera(x, y, z, x_rotation, y_rotation, z_rotation, fov) end

do -- V3DTransform
	--- A transform is an object representing a transformation which can be applied
	--- to 3D positions and directions. Transforms are capable of things like
	--- translation, rotation, and scaling. Internally, they represent the first 3
	--- rows of a row-major 4x4 matrix. The last row is dropped for performance
	--- reasons, but is assumed to equal `[0, 0, 0, 1]` at all times.
	---
	--- Note, there are numerous constructors for [[@V3DTransform]]:
	--- * [[@v3d.identity]]
	--- * [[@v3d.translate]]
	--- * [[@v3d.scale]]
	--- * [[@v3d.rotate]]
	--- * [[@v3d.camera]]
	--- @class V3DTransform
	--- @operator mul (V3DTransform): V3DTransform
	local V3DTransform = {}

	--- Combine this transform with another, returning a transform which first
	--- applies the 2nd transform, and then this one.
	---
	--- ```lua
	--- local result = transform_a:combine(transform_b)
	--- -- result is a transform which will first apply transform_b, then
	--- -- transform_a
	--- ```
	---
	--- Note: you can also use the `*` operator to combine transforms:
	---
	--- ```lua
	--- local result = transform_a * transform_b
	--- ```
	--- @param transform V3DTransform Other transform which will be applied first.
	--- @return V3DTransform
	--- @nodiscard
	function V3DTransform:combine(transform) end

	-- TODO: do we want more efficient versions of this?
	--       e.g. add an offset parameter to transform large sets of data
	--- Apply this transformation to the data provided, returning a new table with
	--- the modified X, Y, and Z position components.
	--- @param data { [1]: number, [2]: number, [3]: number } Data to be transformed.
	--- @param translate boolean Whether to apply translation. If false, only linear transformations like scaling and rotation will be applied.
	--- @return { [1]: number, [2]: number, [3]: number }
	--- @nodiscard
	function V3DTransform:transform(data, translate) end

	--- TODO
	--- @return V3DTransform
	--- @nodiscard
	function V3DTransform:inverse() end
end

--------------------------------------------------------------------------------
--[ Pipelines ]-----------------------------------------------------------------
--------------------------------------------------------------------------------

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
--- @param options V3DPipelineOptions Immutable options for the pipeline.
--- @param label string | nil Optional label for debugging
--- @return V3DPipeline
--- @nodiscard
function v3d.create_pipeline(options, label) end

--- Create a [[@V3DPipeline]] with the given options. Options can be omitted to
--- use defaults, and any field within the options can also be omitted to use
--- defaults.
---
--- Example usage:
--- ```lua
--- TODO
--- ```
--- @param options V3DShadedPipelineOptions Immutable options for the pipeline.
--- @param label string | nil Optional label for debugging
--- @return V3DPipeline
--- @nodiscard
function v3d.create_shaded_pipeline(options, label) end

--- Create a [[@V3DPipeline]] with the given options. Options can be omitted to
--- use defaults, and any field within the options can also be omitted to use
--- defaults.
---
--- Example usage:
--- ```lua
--- TODO
--- ```
--- @param options V3DFlatPipelineOptions Immutable options for the pipeline.
--- @param label string | nil Optional label for debugging
--- @return V3DPipeline
--- @nodiscard
function v3d.create_flat_pipeline(options, label) end

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

do -- V3D*FragmentShader
	--- Variant of [[@V3DFragmentShader]] which accepts geometry attributes as an
	--- unpacked list of parameters.
	--- @alias V3DPackedFragmentShader fun(uniforms: V3DUniforms, ...: unknown): integer | nil

	--- Variant of [[@V3DFragmentShader]] which accepts geometry attributes as a
	--- packed string-keyed table of parameters.
	--- @alias V3DUnpackedFragmentShader fun(uniforms: V3DUniforms, attr_values: { [string]: unknown[] }): integer | nil

	-- TODO: screen X/Y, depth (new & old), face index
	--- A fragment shader runs for every pixel being drawn, accepting the
	--- interpolated attributes for that pixel. See
	--- [[@V3DPipelineOptions.attributes]] and
	--- [[@V3DPipelineOptions.pack_attributes]].
	--- The shader should return a value to be written directly to the framebuffer.
	--- Note: if `nil` is returned, no pixel is written, and the depth value is not
	--- updated for that pixel.
	---
	--- `uniforms` is a table containing the values for all user-set uniforms, plus
	--- certain special values listed under [[@V3DUniforms]].
	---
	--- See: [[@V3DPackedFragmentShader]], [[@V3DUnpackedFragmentShader]]
	--- @alias V3DFragmentShader V3DPackedFragmentShader | V3DUnpackedFragmentShader
end

do -- V3DStatistics*
	--- @class V3DStatisticsOptions
	--- @field measure_total_time boolean | nil
	--- @field measure_rasterize_time boolean | nil
	--- @field count_candidate_faces boolean | nil
	--- @field count_drawn_faces boolean | nil
	--- @field count_culled_faces boolean | nil
	--- @field count_clipped_faces boolean | nil
	--- @field count_discarded_faces boolean | nil
	--- @field count_candidate_fragments boolean | nil
	--- @field count_fragments_occluded boolean | nil
	--- @field count_fragments_shaded boolean | nil
	--- @field count_fragments_discarded boolean | nil
	--- @field count_fragments_drawn boolean | nil

	--- @class V3DStatistics
	--- @field total_time number
	--- @field rasterize_time number
	--- @field candidate_faces integer
	--- @field drawn_faces integer
	--- @field culled_faces integer
	--- @field clipped_faces integer
	--- @field discarded_faces integer
	--- @field candidate_fragments integer
	--- @field fragments_occluded integer
	--- @field fragments_shaded integer
	--- @field fragments_discarded integer
	--- @field fragments_drawn integer
end

do -- V3D*PipelineOptions
	--- Pipeline options describe the settings used to create a pipeline. Most
	--- fields are optional and have a sensible default. Not using or disabling
	--- features may lead to a performance gain, for example disabling depth testing
	--- or not using shaders.
	--- @class V3DPipelineOptions
	--- Layout of the [[@V3DGeometry]] that this pipeline is compatible with. A
	--- pipeline cannot draw geometry of other layouts, and cannot change its
	--- layout. This parameter is not optional.
	--- @field layout V3DLayout
	--- Names of the attributes to interpolate values across polygons being drawn.
	--- Only useful when using fragment shaders, and has a slight performance loss
	--- when used. Defaults to `nil`.
	--- @field attributes V3DAttributeName[] | nil
	--- Optional attribute to specify which attribute vertex positions are stored
	--- in. Must be a numeric, 3 component vertex attribute. Defaults to
	--- `'position'`.
	--- @field position_attribute V3DAttributeName | nil
	--- If specified, this option tells v3d to use the given attribute as a "colour"
	--- attribute to draw a fixed colour per polygon. Note: this should not be used
	--- with fragment shaders, as it will do nothing.
	---
	--- Defaults to `nil`, meaning the fragment shader or 'white' is used to draw
	--- pixels.
	--- @field colour_attribute V3DAttributeName | nil
	--- Whether the fragment shader should receive attributes packed in a table.
	--- Defaults to `true`.
	---
	--- When packed, the 2nd parameter to the fragment shader is a table where the
	--- attribute name is the key to a list of attribute component values. For
	--- example, to access UVs, you might use `attr.uv[1]` and `attr.uv[2]`.
	---
	--- When unpacked, each component of each attribute is passed as an individual
	--- parameter, based on the order the attributes are specified in `attributes`.
	--- For example, to access UVs and colour with `attributes = { 'colour', 'uv' }`
	--- you would have the parameters `(uniforms, colour1, uv1, uv2)` for your
	--- fragment shader.
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
	--- @field statistics V3DStatisticsOptions | nil

	--- Pipeline options describe the settings used to create a pipeline. Most
	--- fields are optional and have a sensible default. Not using or disabling
	--- features may lead to a performance gain, for example disabling depth testing
	--- or not using shaders.
	--- @class V3DCommonPipelineOptions
	--- TODO
	--- @field format V3DFormat
	--- Layout of the [[@V3DGeometry]] that this pipeline is compatible with. A
	--- pipeline cannot draw geometry of other layouts, and cannot change its
	--- layout. This parameter is not optional.
	--- @field layout V3DLayout
	--- Optional attribute to specify which attribute vertex positions are stored
	--- in. Must be a numeric, 3 component vertex attribute. Defaults to
	--- `'position'`.
	--- @field position_attribute V3DAttributeName
	--- Specify a face to cull (not draw), or false to disable face culling.
	--- Defaults to [[@v3d.CULL_BACK_FACE]]. This is a technique to improve
	--- performance and should only be changed from the default when doing something
	--- weird. For example, to not draw faces facing towards the camera, use
	--- `cull_face = v3d.CULL_FRONT_FACE`.
	--- @field cull_face V3DCullFace | false | nil
	--- TODO
	--- @field depth_attachment V3DAttachmentName
	--- Whether to test the depth of candidate pixels, and only draw ones that are
	--- closer to the camera than what's been drawn already.
	--- Slight performance gain if both this and `depth_store` are disabled.
	--- Defaults to `true`.
	--- @field depth_test boolean | nil
	--- Whether to write the depth of drawn pixels to the depth buffer. Defaults to
	--- true.
	--- Slight performance gain if both this and `depth_test` are disabled.
	--- Defaults to `true`.
	--- @field depth_store boolean | nil
	--- Aspect ratio of the pixels being drawn. For square pixels, this should be 1.
	--- For non-square pixels, like the ComputerCraft non-subpixel characters, this
	--- should be their width/height, for example 2/3 for non-subpixel characters.
	--- Defaults to `1`.
	--- @field pixel_aspect_ratio number | nil
	--- @field statistics V3DStatisticsOptions | nil

	--- @class V3DShadedPipelineOptions: V3DCommonPipelineOptions
	--- @field attachments V3DAttachmentName[] | nil
	--- Names of the attributes to interpolate values across polygons being drawn.
	--- Only useful when using fragment shaders, and has a slight performance loss
	--- when used. Defaults to `nil`.
	--- @field attributes V3DAttributeName[] | nil
	--- Whether the fragment shader should receive attributes packed in a table.
	--- Defaults to `true`.
	---
	--- When packed, the 2nd parameter to the fragment shader is a table where the
	--- attribute name is the key to a list of attribute component values. For
	--- example, to access UVs, you might use `attr.uv[1]` and `attr.uv[2]`.
	---
	--- When unpacked, each component of each attribute is passed as an individual
	--- parameter, based on the order the attributes are specified in `attributes`.
	--- For example, to access UVs and colour with `attributes = { 'colour', 'uv' }`
	--- you would have the parameters `(uniforms, colour1, uv1, uv2)` for your
	--- fragment shader.
	---
	--- Note, this attribute corresponds to which of [[@V3DPackedFragmentShader]] or
	--- [[@V3DUnpackedFragmentShader]] should be used when creating a pipeline.
	--- @field pack_attributes boolean | nil
	--- Function to run for every pixel being drawn that determines the colour of
	--- the pixel.
	--- Note: for the UV values passed to the fragment shader to be correct, you
	--- need to enable UV interpolation using the `interpolate_uvs` setting.
	--- Slight performance loss when using fragment shaders.
	--- @field fragment_shader V3DFragmentShader

	--- @class V3DFlatPipelineOptions: V3DCommonPipelineOptions
	--- @field colour_attachment V3DAttachmentName
	--- If specified, this option tells v3d to use the given attribute as a "colour"
	--- attribute to draw a fixed colour per polygon.
	--- @field colour_attribute V3DAttributeName
end

do -- V3DPipeline
	--- A pipeline is an optimised object used to draw [[@V3DGeometry]] to a
	--- [[@V3DFramebuffer]] using a [[@V3DTransform]]. It is created using
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
	--- @param geometry V3DGeometry List of geometry to draw.
	--- @param framebuffer V3DFramebuffer Framebuffer to draw to.
	--- @param transform V3DTransform Transform applied to all vertices.
	--- @param model_transform V3DTransform | nil Transform applied to all vertices before `transform`, if specified.
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
