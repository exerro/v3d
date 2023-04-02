
local v3d = require 'core'

require 'framebuffer'
require 'geometry'
require 'text'
require 'transform'
require 'vsl'

--------------------------------------------------------------------------------
--[[ v3d.CullFace ]]------------------------------------------------------------
--------------------------------------------------------------------------------

do
	--- Specifies which face to cull, either the front or back face.
	---
	--- See also: [[@v3d.CULL_FRONT_FACE]], [[@v3d.CULL_BACK_FACE]]
	--- @alias v3d.CullFace 1 | -1

	--- Specify to cull (not draw) the front face (facing towards the camera).
	--- @type v3d.CullFace
	v3d.CULL_FRONT_FACE = -1

	--- Specify to cull (not draw) the back face (facing away from the camera).
	--- @type v3d.CullFace
	v3d.CULL_BACK_FACE = 1
end

--------------------------------------------------------------------------------
--[[ v3d.PipelineOptions ]]-----------------------------------------------------
--------------------------------------------------------------------------------

do
	--- Pipeline options describe the settings used to create a pipeline. Most
	--- fields are optional and have a sensible default. Different combinations
	--- of options will affect the performance of geometry drawn with this
	--- pipeline.
	--- @class v3d.PipelineOptions
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
	--- @field cull_face v3d.CullFace | false | nil
	--- Lua code which will run for every candidate pixel of a polygon. This
	--- code is entirely responsible for writing values to framebuffer layers
	--- and implementing any custom logic.
	--- @field fragment_shader v3d.vsl.FragmentShaderCode
	--- Aspect ratio of the pixels being drawn. For square pixels, this should be 1.
	--- For non-square pixels, like the ComputerCraft non-subpixel characters, this
	--- should be their width/height, for example 2/3 for non-subpixel characters.
	--- Defaults to `1`.
	--- @field pixel_aspect_ratio number | nil
	--- TODO
	--- @field statistics boolean | nil
end

--------------------------------------------------------------------------------
--[[ v3d.PipelineStatistics ]]--------------------------------------------------
--------------------------------------------------------------------------------

do
	--- TODO
	--- @class v3d.PipelineStatistics
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

--------------------------------------------------------------------------------
--[[ v3d.Pipeline ]]------------------------------------------------------------
--------------------------------------------------------------------------------

do
	--- A pipeline is an optimised object used to draw [[@v3d.Geometry]] to a
	--- [[@v3d.Framebuffer]] using a [[@v3d.Transform]]. It is created using
	--- [[@V3DPipelineOptions]] which cannot change. To configure the pipeline
	--- after creation, uniforms can be used alongside shaders. Alternatively,
	--- multiple pipelines can be created or re-created at will according to the
	--- needs of the application.
	--- @class v3d.Pipeline: v3d.vsl.Accelerated
	--- Options that the pipeline is using. Note that this differs to the ones
	--- it was created with, as these options will have defaults applied etc.
	--- @field options v3d.PipelineOptions
	v3d.Pipeline = {}

	--- We disable diagnostics here since render_geometry is compiled for us
	--- upon creation. This function here does nothing.
	--- @diagnostic disable missing-return, unused-local

	--- Draw geometry to the framebuffer using the transforms given.
	--- @param geometry v3d.Geometry List of geometry to draw.
	--- @param framebuffer v3d.Framebuffer Framebuffer to draw to.
	--- @param transform v3d.Transform Transform applied to all vertices.
	--- @param model_transform v3d.Transform | nil Transform applied to all vertices before `transform`, if specified.
	--- @return v3d.PipelineStatistics
	function v3d.Pipeline:render_geometry(geometry, framebuffer, transform, model_transform) end
end

--------------------------------------------------------------------------------
--[[ Constructor ]]-------------------------------------------------------------
--------------------------------------------------------------------------------

do
	local RENDER_GEOMETRY_SOURCE = [[
local _v3d_upvalue_uniforms = ...
return function(_, _v3d_geometry, _v3d_fb, _v3d_transform, _v3d_model_transform)
	local _v3d_math_ceil = math.ceil
	local _v3d_math_floor = math.floor
	local _v3d_fb_width = _v3d_fb.width
	local _v3d_fb_width_m1 = _v3d_fb_width - 1
	local _v3d_fb_height_m1 = _v3d_fb.height - 1
	local _v3d_screen_dx = (_v3d_fb.width - 1) / 2
	local _v3d_screen_dy = (_v3d_fb.height - 1) / 2
	local _v3d_screen_sy = -(_v3d_screen_dy - 0.5)
	local _v3d_screen_sx = {= opt_pixel_aspect_ratio =} * (_v3d_screen_dy - 0.5)

	{% for _, name in ipairs(fragment_shader.uniforms_accessed) do %}
	local {= get_uniform_name(name) =}
	{% end %}
	{% if #fragment_shader.uniforms_accessed > 0 then %}
	do
		local _v3d_uniforms = _v3d_upvalue_uniforms
		{% for _, name in ipairs(fragment_shader.uniforms_accessed) do %}
		{= get_uniform_name(name) =} = _v3d_uniforms['{= name =}']
		{% end %}
	end
	{% end %}

	{% for _, layer in ipairs(fragment_shader.layers_accessed) do %}
	local _v3d_layer_{= layer.name =} = _v3d_fb.layer_data['{= layer.name =}']
	{% end %}
	{% if opt_statistics then %}
		{% for _, counter_name in ipairs(fragment_shader.event_counters_written_to) do %}
	local _v3d_event_counter_{= counter_name =} = 0
		{% end %}
	{% end %}

	local _v3d_stat_total_time = 0
	local _v3d_stat_rasterize_time = 0
	local _v3d_stat_candidate_faces = 0
	local _v3d_stat_drawn_faces = 0
	local _v3d_stat_culled_faces = 0
	local _v3d_stat_clipped_faces = 0
	local _v3d_stat_discarded_faces = 0
	local _v3d_stat_candidate_fragments = 0

	{% if needs_fragment_world_position then %}
	local _v3d_model_transform_xx = _v3d_model_transform[ 1]
	local _v3d_model_transform_xy = _v3d_model_transform[ 2]
	local _v3d_model_transform_xz = _v3d_model_transform[ 3]
	local _v3d_model_transform_dx = _v3d_model_transform[ 4]
	local _v3d_model_transform_yx = _v3d_model_transform[ 5]
	local _v3d_model_transform_yy = _v3d_model_transform[ 6]
	local _v3d_model_transform_yz = _v3d_model_transform[ 7]
	local _v3d_model_transform_dy = _v3d_model_transform[ 8]
	local _v3d_model_transform_zx = _v3d_model_transform[ 9]
	local _v3d_model_transform_zy = _v3d_model_transform[10]
	local _v3d_model_transform_zz = _v3d_model_transform[11]
	local _v3d_model_transform_dz = _v3d_model_transform[12]
	{% else %}
	-- TODO: implement this properly
	if _v3d_model_transform then
		_v3d_transform = _v3d_transform:combine(_v3d_model_transform)
	end
	{% end %}
	
	local _v3d_transform_xx = _v3d_transform[ 1]
	local _v3d_transform_xy = _v3d_transform[ 2]
	local _v3d_transform_xz = _v3d_transform[ 3]
	local _v3d_transform_dx = _v3d_transform[ 4]
	local _v3d_transform_yx = _v3d_transform[ 5]
	local _v3d_transform_yy = _v3d_transform[ 6]
	local _v3d_transform_yz = _v3d_transform[ 7]
	local _v3d_transform_dy = _v3d_transform[ 8]
	local _v3d_transform_zx = _v3d_transform[ 9]
	local _v3d_transform_zy = _v3d_transform[10]
	local _v3d_transform_zz = _v3d_transform[11]
	local _v3d_transform_dz = _v3d_transform[12]

	{% if needs_world_face_normal then %}
	local _v3d_math_sqrt = math.sqrt
	{% end %}

	local _v3d_vertex_offset = _v3d_geometry.vertex_offset
	local _v3d_face_offset = 0

	for _ = 1, _v3d_geometry.vertices, 3 do
		local _v3d_transformed_p0x, _v3d_transformed_p0y, _v3d_transformed_p0z,
				_v3d_transformed_p1x, _v3d_transformed_p1y, _v3d_transformed_p1z,
				_v3d_transformed_p2x, _v3d_transformed_p2y, _v3d_transformed_p2z

		{% if needs_fragment_world_position then %}
		local _v3d_world_transformed_p0x, _v3d_world_transformed_p0y, _v3d_world_transformed_p0z,
				_v3d_world_transformed_p1x, _v3d_world_transformed_p1y, _v3d_world_transformed_p1z,
				_v3d_world_transformed_p2x, _v3d_world_transformed_p2y, _v3d_world_transformed_p2z
		{% end %}
		{% if needs_world_face_normal then %}
		local _v3d_face_world_normal0, _v3d_face_world_normal1, _v3d_face_world_normal2
		{% end %}
		do
			{% local position_base_offset = opt_format:get_attribute(opt_position_attribute).offset %}
			local _v3d_p0x=_v3d_geometry[_v3d_vertex_offset + {= position_base_offset + 1 =}]
			local _v3d_p0y=_v3d_geometry[_v3d_vertex_offset + {= position_base_offset + 2 =}]
			local _v3d_p0z=_v3d_geometry[_v3d_vertex_offset + {= position_base_offset + 3 =}]
			local _v3d_p1x=_v3d_geometry[_v3d_vertex_offset + {= position_base_offset + opt_format.vertex_stride + 1 =}]
			local _v3d_p1y=_v3d_geometry[_v3d_vertex_offset + {= position_base_offset + opt_format.vertex_stride + 2 =}]
			local _v3d_p1z=_v3d_geometry[_v3d_vertex_offset + {= position_base_offset + opt_format.vertex_stride + 3 =}]
			local _v3d_p2x=_v3d_geometry[_v3d_vertex_offset + {= position_base_offset + opt_format.vertex_stride * 2 + 1 =}]
			local _v3d_p2y=_v3d_geometry[_v3d_vertex_offset + {= position_base_offset + opt_format.vertex_stride * 2 + 2 =}]
			local _v3d_p2z=_v3d_geometry[_v3d_vertex_offset + {= position_base_offset + opt_format.vertex_stride * 2 + 3 =}]

			{% if needs_fragment_world_position then %}
			_v3d_world_transformed_p0x = _v3d_model_transform_xx * _v3d_p0x + _v3d_model_transform_xy * _v3d_p0y + _v3d_model_transform_xz * _v3d_p0z + _v3d_model_transform_dx
			_v3d_world_transformed_p0y = _v3d_model_transform_yx * _v3d_p0x + _v3d_model_transform_yy * _v3d_p0y + _v3d_model_transform_yz * _v3d_p0z + _v3d_model_transform_dy
			_v3d_world_transformed_p0z = _v3d_model_transform_zx * _v3d_p0x + _v3d_model_transform_zy * _v3d_p0y + _v3d_model_transform_zz * _v3d_p0z + _v3d_model_transform_dz
			
			_v3d_world_transformed_p1x = _v3d_model_transform_xx * _v3d_p1x + _v3d_model_transform_xy * _v3d_p1y + _v3d_model_transform_xz * _v3d_p1z + _v3d_model_transform_dx
			_v3d_world_transformed_p1y = _v3d_model_transform_yx * _v3d_p1x + _v3d_model_transform_yy * _v3d_p1y + _v3d_model_transform_yz * _v3d_p1z + _v3d_model_transform_dy
			_v3d_world_transformed_p1z = _v3d_model_transform_zx * _v3d_p1x + _v3d_model_transform_zy * _v3d_p1y + _v3d_model_transform_zz * _v3d_p1z + _v3d_model_transform_dz
			
			_v3d_world_transformed_p2x = _v3d_model_transform_xx * _v3d_p2x + _v3d_model_transform_xy * _v3d_p2y + _v3d_model_transform_xz * _v3d_p2z + _v3d_model_transform_dx
			_v3d_world_transformed_p2y = _v3d_model_transform_yx * _v3d_p2x + _v3d_model_transform_yy * _v3d_p2y + _v3d_model_transform_yz * _v3d_p2z + _v3d_model_transform_dy
			_v3d_world_transformed_p2z = _v3d_model_transform_zx * _v3d_p2x + _v3d_model_transform_zy * _v3d_p2y + _v3d_model_transform_zz * _v3d_p2z + _v3d_model_transform_dz
			
			_v3d_transformed_p0x = _v3d_transform_xx * _v3d_world_transformed_p0x + _v3d_transform_xy * _v3d_world_transformed_p0y + _v3d_transform_xz * _v3d_world_transformed_p0z + _v3d_transform_dx
			_v3d_transformed_p0y = _v3d_transform_yx * _v3d_world_transformed_p0x + _v3d_transform_yy * _v3d_world_transformed_p0y + _v3d_transform_yz * _v3d_world_transformed_p0z + _v3d_transform_dy
			_v3d_transformed_p0z = _v3d_transform_zx * _v3d_world_transformed_p0x + _v3d_transform_zy * _v3d_world_transformed_p0y + _v3d_transform_zz * _v3d_world_transformed_p0z + _v3d_transform_dz
			
			_v3d_transformed_p1x = _v3d_transform_xx * _v3d_world_transformed_p1x + _v3d_transform_xy * _v3d_world_transformed_p1y + _v3d_transform_xz * _v3d_world_transformed_p1z + _v3d_transform_dx
			_v3d_transformed_p1y = _v3d_transform_yx * _v3d_world_transformed_p1x + _v3d_transform_yy * _v3d_world_transformed_p1y + _v3d_transform_yz * _v3d_world_transformed_p1z + _v3d_transform_dy
			_v3d_transformed_p1z = _v3d_transform_zx * _v3d_world_transformed_p1x + _v3d_transform_zy * _v3d_world_transformed_p1y + _v3d_transform_zz * _v3d_world_transformed_p1z + _v3d_transform_dz
			
			_v3d_transformed_p2x = _v3d_transform_xx * _v3d_world_transformed_p2x + _v3d_transform_xy * _v3d_world_transformed_p2y + _v3d_transform_xz * _v3d_world_transformed_p2z + _v3d_transform_dx
			_v3d_transformed_p2y = _v3d_transform_yx * _v3d_world_transformed_p2x + _v3d_transform_yy * _v3d_world_transformed_p2y + _v3d_transform_yz * _v3d_world_transformed_p2z + _v3d_transform_dy
			_v3d_transformed_p2z = _v3d_transform_zx * _v3d_world_transformed_p2x + _v3d_transform_zy * _v3d_world_transformed_p2y + _v3d_transform_zz * _v3d_world_transformed_p2z + _v3d_transform_dz
			{% else %}
			_v3d_transformed_p0x = _v3d_transform_xx * _v3d_p0x + _v3d_transform_xy * _v3d_p0y + _v3d_transform_xz * _v3d_p0z + _v3d_transform_dx
			_v3d_transformed_p0y = _v3d_transform_yx * _v3d_p0x + _v3d_transform_yy * _v3d_p0y + _v3d_transform_yz * _v3d_p0z + _v3d_transform_dy
			_v3d_transformed_p0z = _v3d_transform_zx * _v3d_p0x + _v3d_transform_zy * _v3d_p0y + _v3d_transform_zz * _v3d_p0z + _v3d_transform_dz

			_v3d_transformed_p1x = _v3d_transform_xx * _v3d_p1x + _v3d_transform_xy * _v3d_p1y + _v3d_transform_xz * _v3d_p1z + _v3d_transform_dx
			_v3d_transformed_p1y = _v3d_transform_yx * _v3d_p1x + _v3d_transform_yy * _v3d_p1y + _v3d_transform_yz * _v3d_p1z + _v3d_transform_dy
			_v3d_transformed_p1z = _v3d_transform_zx * _v3d_p1x + _v3d_transform_zy * _v3d_p1y + _v3d_transform_zz * _v3d_p1z + _v3d_transform_dz

			_v3d_transformed_p2x = _v3d_transform_xx * _v3d_p2x + _v3d_transform_xy * _v3d_p2y + _v3d_transform_xz * _v3d_p2z + _v3d_transform_dx
			_v3d_transformed_p2y = _v3d_transform_yx * _v3d_p2x + _v3d_transform_yy * _v3d_p2y + _v3d_transform_yz * _v3d_p2z + _v3d_transform_dy
			_v3d_transformed_p2z = _v3d_transform_zx * _v3d_p2x + _v3d_transform_zy * _v3d_p2y + _v3d_transform_zz * _v3d_p2z + _v3d_transform_dz
			{% end %}
			
			{% if needs_world_face_normal then %}
			local _v3d_face_normal_d1x = _v3d_world_transformed_p1x - _v3d_world_transformed_p0x
			local _v3d_face_normal_d1y = _v3d_world_transformed_p1y - _v3d_world_transformed_p0y
			local _v3d_face_normal_d1z = _v3d_world_transformed_p1z - _v3d_world_transformed_p0z
			local _v3d_face_normal_d2x = _v3d_world_transformed_p2x - _v3d_world_transformed_p0x
			local _v3d_face_normal_d2y = _v3d_world_transformed_p2y - _v3d_world_transformed_p0y
			local _v3d_face_normal_d2z = _v3d_world_transformed_p2z - _v3d_world_transformed_p0z
			_v3d_face_world_normal0 = _v3d_face_normal_d1y*_v3d_face_normal_d2z - _v3d_face_normal_d1z*_v3d_face_normal_d2y
			_v3d_face_world_normal1 = _v3d_face_normal_d1z*_v3d_face_normal_d2x - _v3d_face_normal_d1x*_v3d_face_normal_d2z
			_v3d_face_world_normal2 = _v3d_face_normal_d1x*_v3d_face_normal_d2y - _v3d_face_normal_d1y*_v3d_face_normal_d2x
			local _v3d_face_normal_divisor = 1 / _v3d_math_sqrt(_v3d_face_world_normal0 * _v3d_face_world_normal0 + _v3d_face_world_normal1 * _v3d_face_world_normal1 + _v3d_face_world_normal2 * _v3d_face_world_normal2)
			_v3d_face_world_normal0 = _v3d_face_world_normal0 * _v3d_face_normal_divisor
			_v3d_face_world_normal1 = _v3d_face_world_normal1 * _v3d_face_normal_divisor
			_v3d_face_world_normal2 = _v3d_face_world_normal2 * _v3d_face_normal_divisor
			{% end %}
		end

		{% for _, attr in ipairs(fragment_shader.vertex_attributes_accessed) do %}
			{% for i = 1, attr.components do %}
		local _v3d_p0_va_{= attr.name .. i =} = _v3d_geometry[_v3d_vertex_offset + {= attr.offset + i =}]
		local _v3d_p1_va_{= attr.name .. i =} = _v3d_geometry[_v3d_vertex_offset + {= attr.offset + opt_format.vertex_stride + i =}]
		local _v3d_p2_va_{= attr.name .. i =} = _v3d_geometry[_v3d_vertex_offset + {= attr.offset + opt_format.vertex_stride * 2 + i =}]
			{% end %}
		{% end %}

		{% for _, attr in ipairs(fragment_shader.face_attributes_accessed) do %}
			{% for i = 1, attr.components do %}
		local _v3d_attr_{= attr.name =} = _v3d_geometry[_v3d_face_offset + {= attr.offset + i =}]
			{% end %}
		{% end %}

		{! increment_statistic 'candidate_faces' !}

		{% if opt_cull_face then %}
		local _v3d_cull_face

		do
			local _v3d_d1x = _v3d_transformed_p1x - _v3d_transformed_p0x
			local _v3d_d1y = _v3d_transformed_p1y - _v3d_transformed_p0y
			local _v3d_d1z = _v3d_transformed_p1z - _v3d_transformed_p0z
			local _v3d_d2x = _v3d_transformed_p2x - _v3d_transformed_p0x
			local _v3d_d2y = _v3d_transformed_p2y - _v3d_transformed_p0y
			local _v3d_d2z = _v3d_transformed_p2z - _v3d_transformed_p0z
			local _v3d_cx = _v3d_d1y*_v3d_d2z - _v3d_d1z*_v3d_d2y
			local _v3d_cy = _v3d_d1z*_v3d_d2x - _v3d_d1x*_v3d_d2z
			local _v3d_cz = _v3d_d1x*_v3d_d2y - _v3d_d1y*_v3d_d2x
			{% local cull_face_comparison_operator = opt_cull_face == v3d.CULL_FRONT_FACE and '<' or '>' %}
			_v3d_cull_face = _v3d_cx * _v3d_transformed_p0x + _v3d_cy * _v3d_transformed_p0y + _v3d_cz * _v3d_transformed_p0z {= cull_face_comparison_operator =} 0
		end

		if not _v3d_cull_face then
		{% end %}

			-- TODO: make this split polygons
			{% local clipping_plane = 0.0001 %}
			if _v3d_transformed_p0z <= {= clipping_plane =} and _v3d_transformed_p1z <= {= clipping_plane =} and _v3d_transformed_p2z <= {= clipping_plane =} then
				local _v3d_rasterize_p0_w = -1 / _v3d_transformed_p0z
				local _v3d_rasterize_p0_x = _v3d_screen_dx + _v3d_transformed_p0x * _v3d_rasterize_p0_w * _v3d_screen_sx
				local _v3d_rasterize_p0_y = _v3d_screen_dy + _v3d_transformed_p0y * _v3d_rasterize_p0_w * _v3d_screen_sy
				local _v3d_rasterize_p1_w = -1 / _v3d_transformed_p1z
				local _v3d_rasterize_p1_x = _v3d_screen_dx + _v3d_transformed_p1x * _v3d_rasterize_p1_w * _v3d_screen_sx
				local _v3d_rasterize_p1_y = _v3d_screen_dy + _v3d_transformed_p1y * _v3d_rasterize_p1_w * _v3d_screen_sy
				local _v3d_rasterize_p2_w = -1 / _v3d_transformed_p2z
				local _v3d_rasterize_p2_x = _v3d_screen_dx + _v3d_transformed_p2x * _v3d_rasterize_p2_w * _v3d_screen_sx
				local _v3d_rasterize_p2_y = _v3d_screen_dy + _v3d_transformed_p2y * _v3d_rasterize_p2_w * _v3d_screen_sy

				{% for _, attr in ipairs(fragment_shader.interpolate_attribute_components) do %}
					{% if attr.name == '_v3d_fragment_world_position' then %}
						{% local name = attr.component == 1 and 'x' or attr.component == 2 and 'y' or 'z' %}
				local _v3d_rasterize_p0_va_{= attr.name .. attr.component =} = _v3d_world_transformed_p0{= name =}
				local _v3d_rasterize_p1_va_{= attr.name .. attr.component =} = _v3d_world_transformed_p1{= name =}
				local _v3d_rasterize_p2_va_{= attr.name .. attr.component =} = _v3d_world_transformed_p2{= name =}
					{% else %}
				local _v3d_rasterize_p0_va_{= attr.name .. attr.component =} = _v3d_p0_va_{= attr.name .. attr.component =}
				local _v3d_rasterize_p1_va_{= attr.name .. attr.component =} = _v3d_p1_va_{= attr.name .. attr.component =}
				local _v3d_rasterize_p2_va_{= attr.name .. attr.component =} = _v3d_p2_va_{= attr.name .. attr.component =}
					{% end %}
				{% end %}

				{! TRIANGLE_RASTERIZATION_EMBED !}
				{! increment_statistic 'drawn_faces' !}
			else
				{! increment_statistic 'discarded_faces' !}
			end

		{% if opt_cull_face then %}
		else
			{! increment_statistic 'culled_faces' !}
		end
		{% end %}
	
		_v3d_vertex_offset = _v3d_vertex_offset + {= opt_format.vertex_stride * 3 =}
		_v3d_face_offset = _v3d_face_offset + {= opt_format.face_stride =}
	end

	{% if #fragment_shader.uniforms_written_to > 0 then %}
	do
		local _v3d_uniforms = _v3d_upvalue_uniforms
		{% for _, name in ipairs(fragment_shader.uniforms_written_to) do %}
		_v3d_uniforms['{= name =}'] = {= get_uniform_name(name) =}
		{% end %}
	end
	{% end %}

	return {
		total_time = _v3d_stat_total_time,
		rasterize_time = _v3d_stat_rasterize_time,
		candidate_faces = _v3d_stat_candidate_faces,
		drawn_faces = _v3d_stat_drawn_faces,
		culled_faces = _v3d_stat_culled_faces,
		clipped_faces = _v3d_stat_clipped_faces,
		discarded_faces = _v3d_stat_discarded_faces,
		candidate_fragments = _v3d_stat_candidate_fragments,
		events = {
			{% for _, counter_name in ipairs(fragment_shader.event_counters_written_to) do %}
				{% if opt_statistics then %}
			{= counter_name =} = _v3d_event_counter_{= counter_name =},
				{% else %}
			{= counter_name =} = 0,
				{% end %}
			{% end %}
		},
	}
end
]]

	local TRIANGLE_RASTERIZATION_EMBED = [[
{%
-- TODO: review this! could probs be written nicer with templates
local to_swap = { '_v3d_rasterize_pN_x', '_v3d_rasterize_pN_y' }

if needs_interpolated_depth then
	table.insert(to_swap, '_v3d_rasterize_pN_w')
end

for _, attr in ipairs(fragment_shader.interpolate_attribute_components) do
	table.insert(to_swap, '_v3d_rasterize_pN_va_' .. attr.name .. attr.component)
end

local function swap_test(a, b)
	local result = 'if _v3d_rasterize_pA_y > _v3d_rasterize_pB_y then\n'

	for i = 1, #to_swap do
		local sA = to_swap[i]:gsub('N', 'A')
		local sB = to_swap[i]:gsub('N', 'B')
		result = result .. '\t' .. sA .. ', ' .. sB .. ' = ' .. sB .. ', ' .. sA .. '\n'
	end

	return (result .. 'end'):gsub('A', a):gsub('B', b)
end
%}

{= swap_test(0, 1) =}
{= swap_test(1, 2) =}
{= swap_test(0, 1) =}

local _v3d_midpoint_scalar = (_v3d_rasterize_p1_y - _v3d_rasterize_p0_y) / (_v3d_rasterize_p2_y - _v3d_rasterize_p0_y)
local _v3d_rasterize_pM_x = _v3d_rasterize_p0_x * (1 - _v3d_midpoint_scalar) + _v3d_rasterize_p2_x * _v3d_midpoint_scalar

{% if needs_interpolated_depth then %}
local _v3d_rasterize_pM_w = _v3d_rasterize_p0_w * (1 - _v3d_midpoint_scalar) + _v3d_rasterize_p2_w * _v3d_midpoint_scalar
{% end %}

{% for _, attr in ipairs(fragment_shader.interpolate_attribute_components) do %}
	{% local s = attr.name .. attr.component %}
local _v3d_rasterize_pM_va_{= s =} = (_v3d_rasterize_p0_va_{= s =} * _v3d_rasterize_p0_w * (1 - _v3d_midpoint_scalar) + _v3d_rasterize_p2_va_{= s =} * _v3d_rasterize_p2_w * _v3d_midpoint_scalar) / _v3d_rasterize_pM_w
{% end %}

if _v3d_rasterize_pM_x > _v3d_rasterize_p1_x then
	_v3d_rasterize_pM_x, _v3d_rasterize_p1_x = _v3d_rasterize_p1_x, _v3d_rasterize_pM_x

	{% if needs_interpolated_depth then %}
	_v3d_rasterize_pM_w, _v3d_rasterize_p1_w = _v3d_rasterize_p1_w, _v3d_rasterize_pM_w
	{% end %}

	{% for _, attr in ipairs(fragment_shader.interpolate_attribute_components) do %}
		{% local s = attr.name .. attr.component %}
	_v3d_rasterize_pM_va_{= s =}, _v3d_rasterize_p1_va_{= s =} = _v3d_rasterize_p1_va_{= s =}, _v3d_rasterize_pM_va_{= s =}
	{% end %}
end

local _v3d_row_top_min = _v3d_math_floor(_v3d_rasterize_p0_y + 0.5)
local _v3d_row_top_max = _v3d_math_floor(_v3d_rasterize_p1_y - 0.5)
local _v3d_row_bottom_min = _v3d_row_top_max + 1
local _v3d_row_bottom_max = _v3d_math_ceil(_v3d_rasterize_p2_y - 0.5)

if _v3d_row_top_min < 0 then _v3d_row_top_min = 0 end
if _v3d_row_bottom_min < 0 then _v3d_row_bottom_min = 0 end
if _v3d_row_top_max > _v3d_fb_height_m1 then _v3d_row_top_max = _v3d_fb_height_m1 end
if _v3d_row_bottom_max > _v3d_fb_height_m1 then _v3d_row_bottom_max = _v3d_fb_height_m1 end

if _v3d_row_top_min <= _v3d_row_top_max then
	local _v3d_tri_dy = _v3d_rasterize_p1_y - _v3d_rasterize_p0_y
	if _v3d_tri_dy > 0 then
		local _v3d_row_min_index = _v3d_row_top_min * _v3d_fb_width
		local _v3d_row_max_index = _v3d_row_top_max * _v3d_fb_width

		{%
		local flat_triangle_name = 'top'
		local flat_triangle_top_left = 'p0'
		local flat_triangle_top_right = 'p0'
		local flat_triangle_bottom_left = 'pM'
		local flat_triangle_bottom_right = 'p1'
		%}

		{! FLAT_TRIANGLE_RASTERIZATION_EMBED !}
	end
end

if _v3d_row_bottom_min <= _v3d_row_bottom_max then
	local _v3d_tri_dy = _v3d_rasterize_p2_y - _v3d_rasterize_p1_y

	if _v3d_tri_dy > 0 then
		local _v3d_row_min_index = _v3d_row_bottom_min * _v3d_fb_width
		local _v3d_row_max_index = _v3d_row_bottom_max * _v3d_fb_width

		{%
		local flat_triangle_name = 'bottom'
		local flat_triangle_top_left = 'pM'
		local flat_triangle_top_right = 'p1'
		local flat_triangle_bottom_left = 'p2'
		local flat_triangle_bottom_right = 'p2'
		%}

		{! FLAT_TRIANGLE_RASTERIZATION_EMBED !}
	end
end
]]

	local FLAT_TRIANGLE_RASTERIZATION_EMBED = [[
local _v3d_tri_y_correction = _v3d_row_{= flat_triangle_name =}_min + 0.5 - _v3d_rasterize_{= flat_triangle_top_right =}_y
local _v3d_tri_left_dx_dy = (_v3d_rasterize_{= flat_triangle_bottom_left =}_x - _v3d_rasterize_{= flat_triangle_top_left =}_x) / _v3d_tri_dy
local _v3d_tri_right_dx_dy = (_v3d_rasterize_{= flat_triangle_bottom_right =}_x - _v3d_rasterize_{= flat_triangle_top_right =}_x) / _v3d_tri_dy
local _v3d_tri_left_x = _v3d_rasterize_{= flat_triangle_top_left =}_x + _v3d_tri_left_dx_dy * _v3d_tri_y_correction - 0.5
local _v3d_tri_right_x = _v3d_rasterize_{= flat_triangle_top_right =}_x + _v3d_tri_right_dx_dy * _v3d_tri_y_correction - 1.5

{% if needs_interpolated_depth then %}
local _v3d_tri_left_dw_dy = (_v3d_rasterize_{= flat_triangle_bottom_left =}_w - _v3d_rasterize_{= flat_triangle_top_left =}_w) / _v3d_tri_dy
local _v3d_tri_right_dw_dy = (_v3d_rasterize_{= flat_triangle_bottom_right =}_w - _v3d_rasterize_{= flat_triangle_top_right =}_w) / _v3d_tri_dy
local _v3d_tri_left_w = _v3d_rasterize_{= flat_triangle_top_left =}_w + _v3d_tri_left_dw_dy * _v3d_tri_y_correction
local _v3d_tri_right_w = _v3d_rasterize_{= flat_triangle_top_right =}_w + _v3d_tri_right_dw_dy * _v3d_tri_y_correction
{% end %}

{% for _, attr in ipairs(fragment_shader.interpolate_attribute_components) do %}
	{% local s = attr.name .. attr.component %}
local _v3d_tri_left_va_d{= s =}w_dy = (_v3d_rasterize_{= flat_triangle_bottom_left =}_va_{= s =} * _v3d_rasterize_{= flat_triangle_bottom_left =}_w - _v3d_rasterize_{= flat_triangle_top_left =}_va_{= s =} * _v3d_rasterize_{= flat_triangle_top_left =}_w) / _v3d_tri_dy
local _v3d_tri_right_va_d{= s =}w_dy = (_v3d_rasterize_{= flat_triangle_bottom_right =}_va_{= s =} * _v3d_rasterize_{= flat_triangle_bottom_right =}_w - _v3d_rasterize_{= flat_triangle_top_right =}_va_{= s =} * _v3d_rasterize_{= flat_triangle_top_right =}_w) / _v3d_tri_dy
local _v3d_tri_left_va_{= s =}_w = _v3d_rasterize_{= flat_triangle_top_left =}_va_{= s =} * _v3d_rasterize_{= flat_triangle_top_left =}_w + _v3d_tri_left_va_d{= s =}w_dy * _v3d_tri_y_correction
local _v3d_tri_right_va_{= s =}_w = _v3d_rasterize_{= flat_triangle_top_right =}_va_{= s =} * _v3d_rasterize_{= flat_triangle_top_right =}_w + _v3d_tri_right_va_d{= s =}w_dy * _v3d_tri_y_correction
{% end %}

for _v3d_base_index = _v3d_row_min_index, _v3d_row_max_index, _v3d_fb_width do
	local _v3d_row_min_column = _v3d_math_ceil(_v3d_tri_left_x)
	local _v3d_row_max_column = _v3d_math_ceil(_v3d_tri_right_x)

	if _v3d_row_min_column < 0 then _v3d_row_min_column = 0 end
	if _v3d_row_max_column > _v3d_fb_width_m1 then _v3d_row_max_column = _v3d_fb_width_m1 end

	{% if needs_interpolated_depth then %}
	local _v3d_row_x_correction = _v3d_row_min_column - _v3d_tri_left_x
	local _v3d_row_dx = _v3d_tri_right_x - _v3d_tri_left_x + 1 -- TODO: + 1 ???
	local _v3d_row_dw_dx = (_v3d_tri_right_w - _v3d_tri_left_w) / _v3d_row_dx
	local _v3d_row_w = _v3d_tri_left_w + _v3d_row_dw_dx * _v3d_row_x_correction
	{% end %}

	{% for _, attr in ipairs(fragment_shader.interpolate_attribute_components) do %}
		{% local s = attr.name .. attr.component %}
	local _v3d_row_va_d{= s =}w_dx = (_v3d_tri_right_va_{= s =}_w - _v3d_tri_left_va_{= s =}_w) / _v3d_row_dx
	local _v3d_row_va_{= s =}_w = _v3d_tri_left_va_{= s =}_w + _v3d_row_va_d{= s =}w_dx * _v3d_row_x_correction
	{% end %}

	{% if #fragment_shader.layer_sizes_accessed ~= 1 then %}
	for _v3d_x = _v3d_row_min_column, _v3d_row_max_column do
	{% else %}
		{%
		local min_bound = '_v3d_base_index + _v3d_row_min_column'
		local max_bound = '_v3d_base_index + _v3d_row_max_column'
	
		if fragment_shader.layer_sizes_accessed[1] ~= 1 then
			min_bound = '(' .. min_bound .. ') * ' .. fragment_shader.layer_sizes_accessed[1]
			max_bound = '(' .. max_bound .. ') * ' .. fragment_shader.layer_sizes_accessed[1]
		end
		%}
	for _v3d_fragment_layer_index{= fragment_shader.layer_sizes_accessed[1] =} = {= min_bound =} + 1, {= max_bound =} + 1, {= fragment_shader.layer_sizes_accessed[1] =} do
	{% end %}
		{% if fragment_shader.is_called_any_layer_was_written then %}
		local _v3d_any_layer_written = false
		{% end %}
		{% for layer in pairs(fragment_shader.is_called_layer_was_written) do %}
		local _v3d_specific_layer_written_{= layer =} = false
		{% end %}

		{% if #fragment_shader.layer_sizes_accessed > 1 then %}
			{% for _, i in ipairs(fragment_shader.layer_sizes_accessed) do %}
		local _v3d_fragment_layer_index{= i =} = (_v3d_base_index + _v3d_x) * {= i =} + 1
			{% end %}
		{% end %}
		{! increment_statistic 'candidate_fragments' !}

		{% for _, attr in ipairs(fragment_shader.interpolate_attribute_components) do %}
		local {= get_interpolated_attribute_component_name(attr.name, attr.component) =} = _v3d_row_va_{= attr.name .. attr.component =}_w / _v3d_row_w
		{% end %}

		{= fragment_shader.is_called_is_fragment_discarded and 'local _v3d_builtin_fragment_discarded = false' or '' =}
		--#vsl_embed_start fragment_shader
		{! FRAGMENT_SHADER_EMBED !}
		--#vsl_embed_end fragment_shader
		
		{% if needs_interpolated_depth then %}
		_v3d_row_w = _v3d_row_w + _v3d_row_dw_dx
		{% end %}

		{% for _, attr in ipairs(fragment_shader.interpolate_attribute_components) do %}
			{% local s = attr.name .. attr.component %}
		_v3d_row_va_{= s =}_w = _v3d_row_va_{= s =}_w + _v3d_row_va_d{= s =}w_dx
		{% end %}
	end

	_v3d_tri_left_x = _v3d_tri_left_x + _v3d_tri_left_dx_dy
	_v3d_tri_right_x = _v3d_tri_right_x + _v3d_tri_right_dx_dy
	
	{% if needs_interpolated_depth then %}
	_v3d_tri_left_w = _v3d_tri_left_w + _v3d_tri_left_dw_dy
	_v3d_tri_right_w = _v3d_tri_right_w + _v3d_tri_right_dw_dy
	{% end %}

	{% for _, attr in ipairs(fragment_shader.interpolate_attribute_components) do %}
		{% local s = attr.name .. attr.component %}
	_v3d_tri_left_va_{= s =}_w = _v3d_tri_left_va_{= s =}_w + _v3d_tri_left_va_d{= s =}w_dy
	_v3d_tri_right_va_{= s =}_w = _v3d_tri_right_va_{= s =}_w + _v3d_tri_right_va_d{= s =}w_dy
	{% end %}
end
]]

	--- @diagnostic enable missing-return, unused-local

	--- Create a [[@V3DPipeline]] with the given options.
	--- @param options v3d.PipelineOptions Immutable options for the pipeline.
	--- @param label string | nil Optional label for debugging
	--- @return v3d.Pipeline
	--- @nodiscard
	function v3d.create_pipeline(options, label)
		local opt_layout = options.layout
		local opt_format = options.format
		local opt_position_attribute = options.position_attribute
		local opt_cull_face = options.cull_face == nil and v3d.CULL_BACK_FACE or options.cull_face
		local opt_fragment_shader = v3d.text.unindent(options.fragment_shader)
		local opt_pixel_aspect_ratio = options.pixel_aspect_ratio or 1
		local opt_statistics = options.statistics or false

		local pipeline = {}

		pipeline.sources = {}
		pipeline.uniforms = {}
		pipeline.options = {
			layout = opt_layout,
			format = opt_format,
			position_attribute = opt_position_attribute,
			cull_face = opt_cull_face,
			fragment_shader = opt_fragment_shader,
			pixel_aspect_ratio = opt_pixel_aspect_ratio,
			statistics = opt_statistics,
		}

		local fragment_shader_context, fragment_shader_code = v3d.vsl.process_fragment_shader(opt_layout, opt_format, opt_fragment_shader)

		local template_context = {
			v3d = v3d,

			opt_layout = opt_layout,
			opt_format = opt_format,
			opt_position_attribute = opt_position_attribute,
			opt_cull_face = opt_cull_face,
			opt_pixel_aspect_ratio = opt_pixel_aspect_ratio,
			opt_statistics = opt_statistics,

			FLAT_TRIANGLE_RASTERIZATION_EMBED = FLAT_TRIANGLE_RASTERIZATION_EMBED,
			TRIANGLE_RASTERIZATION_EMBED = TRIANGLE_RASTERIZATION_EMBED,
			FRAGMENT_SHADER_EMBED = fragment_shader_code,

			fragment_shader = fragment_shader_context,

			builtin_fragment_discarded = '_v3d_builtin_fragment_discarded',

			ref_fragment_depth = '_v3d_row_w',

			needs_fragment_world_position = fragment_shader_context.is_called_fragment_world_position
										 or fragment_shader_context.is_called_face_world_normal,
			needs_interpolated_depth = fragment_shader_context.is_called_fragment_depth
									or #fragment_shader_context.interpolate_attribute_components > 0,
			needs_world_face_normal = fragment_shader_context.is_called_face_world_normal,
		}

		function template_context.get_uniform_name(name)
			return '_v3d_uniform_' .. name
		end

		function template_context.get_interpolated_attribute_component_name(name, component)
			return '_v3d_interp_' .. name .. component
		end

		function template_context.increment_event_counter(name, amount)
			return '{% if opt_statistics then %}_v3d_event_counter_' .. name .. ' = _v3d_event_counter_' .. name .. ' + ' .. amount .. '{% end %}'
		end

		function template_context.increment_statistic(name)
			return '{% if opt_statistics then %}_v3d_stat_' .. name .. ' = _v3d_stat_' .. name .. ' + 1{% end %}'
		end

		function template_context.notify_any_layer_written()
			return '_v3d_any_layer_written = true'
		end

		function template_context.notify_specific_layer_written(name)
			return fragment_shader_context.is_called_layer_was_written[name] and '_v3d_specific_layer_written_' .. name .. ' = true' or ''
		end

		local pipeline_source = v3d.text.generate_template(RENDER_GEOMETRY_SOURCE, template_context)
		local f, err = load(pipeline_source, 'pipeline source')

		if not f then -- TODO: aaa bad validation no, but also until v3debug I need this for my sanity
			f = v3d.internal_error('Failed to compile pipeline render_geometry function: ' .. err, pipeline_source)
		end

		for k, v in pairs(v3d.vsl.Accelerated) do
			pipeline[k] = v
		end

		for k, v in pairs(v3d.Pipeline) do
			pipeline[k] = v
		end

		pipeline.render_geometry = f(pipeline.uniforms)

		pipeline:add_source('fragment_shader', opt_fragment_shader, pipeline_source)
		pipeline:add_source('render_geometry', nil, pipeline_source)

		return pipeline
	end
end
