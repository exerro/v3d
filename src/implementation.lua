
local v3d2 = require '/v3d/gen/v3dtest'

-- #remove
-- note: this code will be stripped out during the build process, thus removing
--       the error
error 'Cannot use v3d source code, must build the library'
-- #end
--- @type v3d
local v3d = {}


--- @return any
local function v3d_internal_error(message, context)
	local traceback
	pcall(function()
		traceback = debug and debug.traceback and debug.traceback()
	end)
	local error_message = 'V3D INTERNAL ERROR: '
	                   .. tostring(message == nil and '' or message)
	                   .. (traceback and '\n' .. traceback or '')
	pcall(function()
		local h = io.open('.v3d_crash_dump.txt', 'w')
		if h then
			h:write(context and context .. '\n' .. error_message or error_message)
			h:close()
		end
	end)
	error(error_message, 0)
end


--------------------------------------------------------------------------------
--[ Rasterization functions ]---------------------------------------------------
--------------------------------------------------------------------------------


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
		{! FRAGMENT_SHADER_EMBED !}
		
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

local function v3d_create_pipeline(options)
	--- @type v3d.Layout
	local opt_layout = options.layout
	--- @type v3d.Format
	local opt_format = options.format
	local opt_position_attribute = options.position_attribute
	local opt_cull_face = options.cull_face == nil and v3d.CULL_BACK_FACE or options.cull_face
	local opt_fragment_shader = options.fragment_shader
	local opt_pixel_aspect_ratio = options.pixel_aspect_ratio or 1
	local opt_statistics = options.statistics or false

	local pipeline = {}
	local uniforms = {}

	-- format incoming shader code to unindent it
	do
		opt_fragment_shader = opt_fragment_shader:gsub('%s+$', '')

		local lines = {}
		local min_line_length = math.huge
		local matching_indentation_length = 0

		for line in opt_fragment_shader:gmatch '[^\n]+' do
			if line:find '%S' then
				line = line:match '^%s*'
				table.insert(lines, line)
				min_line_length = math.min(min_line_length, #line)
			end
		end

		if lines[1] then
			for i = 1, min_line_length do
				local c = lines[1]:sub(i, i)
				local ok = true
				for j = 2, #lines do
					if lines[j]:sub(i, i) ~= c then
						ok = false
						break
					end
				end
				if not ok then
					break
				end
				matching_indentation_length = i
			end

			opt_fragment_shader = opt_fragment_shader
				:gsub('^' .. lines[1]:sub(1, matching_indentation_length), '')
				:gsub('\n' .. lines[1]:sub(1, matching_indentation_length), '\n')
		end
	end

	--- @type V3DPipelineOptions
	pipeline.options = {
		layout = opt_layout,
		format = opt_format,
		position_attribute = opt_position_attribute,
		cull_face = opt_cull_face,
		fragment_shader = opt_fragment_shader,
		pixel_aspect_ratio = opt_pixel_aspect_ratio,
		statistics = opt_statistics,
	}

	local fragment_shader_context, fragment_shader_code = v3d2.vsl.process_fragment_shader(opt_layout, opt_format, opt_fragment_shader)

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

	local pipeline_source = v3d2.text.generate_template(RENDER_GEOMETRY_SOURCE, template_context)

	v3d2.vsl.process(setmetatable({}, { __index = function(_, fn)
		v3d2.internal_error('Unexpanded macro \'' .. fn .. '\'', pipeline_source)
	end }), {}, pipeline_source)

	local f, err = load(pipeline_source, 'pipeline source')

	if not f then
		f = v3d_internal_error('Failed to compile pipeline render_geometry function: ' .. err, pipeline_source)
	end

	pipeline.source = pipeline_source
	pipeline.render_geometry = f(uniforms)

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

	set_library('create_pipeline', v3d_create_pipeline)
	set_library('create_texture_sampler', create_texture_sampler)

	set_library('CULL_FRONT_FACE', -1)
	set_library('CULL_BACK_FACE', 1)
end

return v3d
