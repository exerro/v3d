
local v3d_internal = require '_internal'
local v3d_text = require 'text'
local v3d_vsl = require 'vsl'

local v3d_effect = {}

--------------------------------------------------------------------------------
--[[ v3d.EffectOptions ]]-----------------------------------------------------
--------------------------------------------------------------------------------

do
	--- Effect options describe the settings used to create an effect. Different
	--- combinations of options will affect the performance of geometry drawn
	--- with this pipeline.
	--- @class v3d.EffectOptions
	--- TODO
	--- @field layout v3d.Layout
	--- Lua code which will run for every pixel in the framebuffer. This code
	--- is entirely responsible for writing values to framebuffer layers and
	--- implementing any custom logic.
	--- @field pixel_shader v3d.vsl.PixelShaderCode
	--- Lua code which will run once before any blocks have been processed.
	--- @field pixel_shader_init v3d.vsl.Code | nil
	--- Lua code which will run before every row of blocks is processed.
	--- @field pixel_shader_row_start v3d.vsl.Code | nil
	--- Lua code which will run after every row of blocks is processed.
	--- @field pixel_shader_row_finish v3d.vsl.Code | nil
	--- TODO
	--- @field template_context v3d.text.TemplateContext | nil
	--- TODO
	--- @field statistics boolean | nil
end

--------------------------------------------------------------------------------
--[[ v3d.Effect ]]------------------------------------------------------------
--------------------------------------------------------------------------------

do
	--- TODO
	--- @class v3d.Effect: v3d.vsl.Accelerated
	--- Options that the effect is using. Note that this differs to the ones
	--- it was created with, as these options will have defaults applied etc.
	--- @field options v3d.EffectOptions
	v3d_effect.Effect = {}

	--- We disable diagnostics here since render_geometry is compiled for us
	--- upon creation. This function here does nothing.
	--- @diagnostic disable missing-return, unused-local

	--- Draw geometry to the framebuffer using the transforms given.
	--- @param framebuffer v3d.Framebuffer Framebuffer to use.
	--- @param width integer | nil
	--- @param height integer | nil
	--- @param dx integer | nil
	--- @param dy integer | nil
	--- @return v3d.EffectStatistics
	function v3d_effect.Effect:apply(framebuffer, width, height, dx, dy) end

	--- @diagnostic enable missing-return, unused-local
end

--------------------------------------------------------------------------------
--[[ Constructor ]]-------------------------------------------------------------
--------------------------------------------------------------------------------

do
	local APPLY_SOURCE = [[
local _v3d_upvalue_uniforms = ...
return function(_, _v3d_fb, _v3d_width, _v3d_height, _v3d_dx, _v3d_dy)
	local _v3d_math_ceil = math.ceil
	local _v3d_math_floor = math.floor
	local _v3d_fb_width = _v3d_fb.width
	local _v3d_fb_width_m1 = _v3d_fb_width - 1
	local _v3d_fb_height = _v3d_fb.height
	local _v3d_fb_height_m1 = _v3d_fb_height - 1

	_v3d_width = _v3d_width or _v3d_fb_width
	_v3d_height = _v3d_height or _v3d_fb_height
	_v3d_dx = _v3d_dx or 0
	_v3d_dy = _v3d_dy or 0

	if _v3d_dx < 0 then
		_v3d_width = _v3d_width + _v3d_dx
		_v3d_dx = 0
	end

	if _v3d_dy < 0 then
		_v3d_height = _v3d_height + _v3d_dy
		_v3d_dy = 0
	end

	if _v3d_width > _v3d_fb_width - _v3d_dx then
		_v3d_width = _v3d_fb_width - _v3d_dx
	end

	if _v3d_height > _v3d_fb_height - _v3d_dy then
		_v3d_height = _v3d_fb_height - _v3d_dy
	end

	{% for _, name in ipairs(pixel_shader.uniforms_accessed) do %}
	local {= get_uniform_name(name) =}
	{% end %}
	{% if #pixel_shader.uniforms_accessed > 0 then %}
	do
		local _v3d_uniforms = _v3d_upvalue_uniforms
		{% for _, name in ipairs(pixel_shader.uniforms_accessed) do %}
		{= get_uniform_name(name) =} = _v3d_uniforms['{= name =}']
		{% end %}
	end
	{% end %}

	{% for _, layer in ipairs(pixel_shader.layers_accessed) do %}
	local _v3d_layer_{= layer.name =} = _v3d_fb.layer_data['{= layer.name =}']
	{% end %}

	local _v3d_index_offset = _v3d_fb_width * _v3d_dy + _v3d_dx
	local _v3d_jump_base = _v3d_fb_width - _v3d_width
	{% for _, layer_size in ipairs(pixel_shader.layer_sizes_accessed) do %}
	local _v3d_fb_layer_index{= layer_size =} = _v3d_index_offset * {= layer_size =} + 1
	local _v3d_fb_layer_jump{= layer_size =} = _v3d_jump_base * {= layer_size =}
	{% end %}

	{% if opt_statistics then %}
		{% for _, counter_name in ipairs(pixel_shader.event_counters_written_to) do %}
	local _v3d_event_counter_{= counter_name =} = 0
		{% end %}
	{% end %}

	--#vsl_embed_start pixel_shader_init
	{! PIXEL_SHADER_INIT_EMBED !}
	--#vsl_embed_end pixel_shader_init

	{% if pixel_shader.framebuffer_x_accessed then %}
	local _v3d_iterator_x0 = _v3d_dx
	local _v3d_iterator_x1 = _v3d_dx + _v3d_width - 1
	{% else %}
	local _v3d_iterator_x0 = _v3d_dx + 1
	local _v3d_iterator_x1 = _v3d_dx + _v3d_width
	{% end %}

	{% if pixel_shader.framebuffer_y_accessed then %}
	for _v3d_fb_y0 = _v3d_dy, _v3d_dy + _v3d_height - 1 do
	{% else %}
	for _v3d_fb_y1 = _v3d_dy + 1, _v3d_dy + _v3d_height do
	{% end %}
		{% if pixel_shader.framebuffer_y_accessed and pixel_shader.framebuffer_y1_accessed then %}
		local _v3d_fb_y1 = _v3d_fb_y0 + 1
		{% end %}

		--#vsl_embed_start pixel_shader_row_start
		{! PIXEL_SHADER_ROW_START_EMBED !}
		--#vsl_embed_end pixel_shader_row_start

		for _v3d_fb_x0 = _v3d_iterator_x0, _v3d_iterator_x1 do
			{% if pixel_shader.framebuffer_x_accessed and pixel_shader.framebuffer_x1_accessed then %}
			local _v3d_fb_x1 = _v3d_fb_x0 + 1
			{% end %}

			--#vsl_embed_start pixel_shader
			{! PIXEL_SHADER_EMBED !}
			--#vsl_embed_end pixel_shader

			{% for _, layer_size in ipairs(pixel_shader.layer_sizes_accessed) do %}
			_v3d_fb_layer_index{= layer_size =} = _v3d_fb_layer_index{= layer_size =} + {= layer_size =}
			{% end %}
		end

		--#vsl_embed_start pixel_shader_row_finish
		{! PIXEL_SHADER_ROW_FINISH_EMBED !}
		--#vsl_embed_end pixel_shader_row_finish

		{% for _, layer_size in ipairs(pixel_shader.layer_sizes_accessed) do %}
		_v3d_fb_layer_index{= layer_size =} = _v3d_fb_layer_index{= layer_size =} + _v3d_fb_layer_jump{= layer_size =}
		{% end %}
	end

	{% if #pixel_shader.uniforms_written_to > 0 then %}
	do
		local _v3d_uniforms = _v3d_upvalue_uniforms
		{% for _, name in ipairs(pixel_shader.uniforms_written_to) do %}
		_v3d_uniforms['{= name =}'] = {= get_uniform_name(name) =}
		{% end %}
	end
	{% end %}

	return {
		events = {
			{% for _, counter_name in ipairs(pixel_shader.event_counters_written_to) do %}
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

	--- @diagnostic enable missing-return, unused-local

	--- Create a [[@v3d.Effect]] with the given options.
	--- @param options v3d.EffectOptions Immutable options for the effect.
	--- @param label string | nil Optional label for debugging
	--- @return v3d.Effect
	--- @nodiscard
	function v3d_effect.create_effect(options, label)
		local opt_layout = options.layout
		local opt_pixel_shader = options.pixel_shader
		local opt_pixel_shader_init = options.pixel_shader_init
		local opt_pixel_shader_row_start = options.pixel_shader_row_start
		local opt_pixel_shader_row_finish = options.pixel_shader_row_finish
		local opt_template_context = options.template_context or {}
		local opt_statistics = options.statistics or false

		opt_pixel_shader = opt_pixel_shader and v3d_text.unindent(opt_pixel_shader)
		opt_pixel_shader_init = opt_pixel_shader_init and v3d_text.unindent(opt_pixel_shader_init)
		opt_pixel_shader_row_start = opt_pixel_shader_row_start and v3d_text.unindent(opt_pixel_shader_row_start)
		opt_pixel_shader_row_finish = opt_pixel_shader_row_finish and v3d_text.unindent(opt_pixel_shader_row_finish)

		local effect = {}

		effect.sources = {}
		effect.uniforms = {}
		effect.options = {
			layout = opt_layout,
			pixel_shader = opt_pixel_shader,
			opt_pixel_shader_init,
			opt_pixel_shader_row_start,
			opt_pixel_shader_row_finish,
			statistics = opt_statistics,
		}

		local pixel_shader_context, pixel_shader_code = v3d_vsl.process_pixel_shader(
			opt_layout, v3d_text.generate_template(opt_pixel_shader, opt_template_context))

		local _, pixel_shader_init_code, pixel_shader_row_start_code, pixel_shader_row_finish_code = nil, '', '', ''
		
		if opt_pixel_shader_init then
			_, pixel_shader_init_code = v3d_vsl.process_default_shader(
				v3d_text.generate_template(opt_pixel_shader_init, opt_template_context), pixel_shader_context)
		end

		if opt_pixel_shader_row_start then
			_, pixel_shader_row_start_code = v3d_vsl.process_default_shader(
				v3d_text.generate_template(opt_pixel_shader_row_start, opt_template_context), pixel_shader_context)
		end

		if opt_pixel_shader_row_finish then
			_, pixel_shader_row_finish_code = v3d_vsl.process_default_shader(
				v3d_text.generate_template(opt_pixel_shader_row_finish, opt_template_context), pixel_shader_context)
		end

		local template_context = {
			opt_layout = opt_layout,
			opt_statistics = opt_statistics,

			PIXEL_SHADER_EMBED = pixel_shader_code,
			PIXEL_SHADER_INIT_EMBED = pixel_shader_init_code,
			PIXEL_SHADER_ROW_START_EMBED = pixel_shader_row_start_code,
			PIXEL_SHADER_ROW_FINISH_EMBED = pixel_shader_row_finish_code,

			pixel_shader = pixel_shader_context,

			ref_framebuffer_x = '_v3d_fb_x0',
			ref_framebuffer_y = '_v3d_fb_y0',
			ref_framebuffer_x_plus_one = '_v3d_fb_x1',
			ref_framebuffer_y_plus_one = '_v3d_fb_y1',
		}

		function template_context.get_uniform_name(name)
			return '_v3d_uniform_' .. name
		end

		function template_context.increment_event_counter(name, amount)
			return '{% if opt_statistics then %}_v3d_event_counter_' .. name .. ' = _v3d_event_counter_' .. name .. ' + ' .. amount .. '{% end %}'
		end

		function template_context.get_layer(name)
			return '_v3d_layer_' .. name
		end

		function template_context.get_layer_index(components, component)
			if component == 1 then
				return '_v3d_fb_layer_index' .. components
			else
				return '(_v3d_fb_layer_index' .. components .. ' + ' .. (component - 1) .. ')'
			end
		end

		local effect_source = v3d_text.generate_template(APPLY_SOURCE, template_context)
		local f, err = load(effect_source, 'effect source')

		if not f then -- TODO: aaa bad validation no, but also until v3debug I need this for my sanity
			f = v3d_internal.internal_error('Failed to compile effect apply function: ' .. err, effect_source)
		end

		for k, v in pairs(v3d_vsl.Accelerated) do
			effect[k] = v
		end

		for k, v in pairs(v3d_effect.Effect) do
			effect[k] = v
		end

		effect.apply = f(effect.uniforms)

		effect:add_source('pixel_shader', opt_pixel_shader, effect_source)
		effect:add_source('pixel_shader_init', opt_pixel_shader, effect_source)
		effect:add_source('pixel_shader_row_start', opt_pixel_shader, effect_source)
		effect:add_source('pixel_shader_row_finish', opt_pixel_shader, effect_source)
		effect:add_source('apply', nil, effect_source)

		return effect
	end
end

return v3d_effect
