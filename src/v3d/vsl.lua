
local v3d = require 'core'

require 'framebuffer'
require 'geometry'
require 'text'

v3d.vsl = {}

--------------------------------------------------------------------------------
--[[ v3d.vsl.Code ]]------------------------------------------------------------
--------------------------------------------------------------------------------

do
	--- TODO
	--- @alias v3d.vsl.Code string
end

--------------------------------------------------------------------------------
--[[ v3d.vsl.FragmentShaderCode ]]----------------------------------------------
--------------------------------------------------------------------------------

do
	--- TODO
	--- @alias v3d.vsl.FragmentShaderCode v3d.vsl.Code
end

--------------------------------------------------------------------------------
--[[ v3d.vsl.MacroContext ]]----------------------------------------------------
--------------------------------------------------------------------------------

do
	--- TODO
	--- @alias v3d.vsl.MacroContext { [string]: any }
end

--------------------------------------------------------------------------------
--[[ v3d.vsl.FragmentShaderMacroContext ]]--------------------------------------
--------------------------------------------------------------------------------

do
	--- TODO
	--- @class v3d.vsl.FragmentShaderMacroContext
	--- @field private internal { [string]: any }
	--- @field private layout v3d.Layout
	--- @field private format v3d.Format
	--- TODO
	--- @field event_counters_written_to string[]
	--- TODO
	--- @field face_attributes_accessed v3d.Attribute[]
	--- TODO
	--- @field interpolate_attribute_components { name: string, component: integer }[]
	--- Tracks whether `v3d_layer_was_written()` was called with no layer name.
	--- @field is_called_any_layer_was_written boolean
	--- TODO
	--- @field is_called_face_world_normal boolean
	--- TODO
	--- @field is_called_fragment_depth boolean
	--- TODO
	--- @field is_called_fragment_world_position boolean
	--- TODO
	--- @field is_called_is_fragment_discarded boolean
	--- Map of layer names to a boolean, tracking whether
	--- `v3d_layer_was_written()` was called for that layer name.
	--- @field is_called_layer_was_written { [v3d.LayerName]: true | nil }
	--- Ordered set of sizes of layers written to.
	--- @field layer_sizes_accessed integer[]
	--- Names of all the layers written to by the shader.
	--- @field layers_accessed v3d.LayerName[]
	--- Names of all the uniform variables which are accessed (read/write).
	--- @field uniforms_accessed string[]
	--- Names of all the uniform variables which are explicitly written to.
	--- @field uniforms_written_to string[]
	--- TODO
	--- @field vertex_attributes_accessed v3d.Attribute[]
end

--------------------------------------------------------------------------------
--[[ v3d.vsl.MacroHandler ]]----------------------------------------------------
--------------------------------------------------------------------------------

do
	--- TODO
	--- @alias v3d.vsl.MacroHandler fun (local_context: v3d.vsl.MacroContext, context: v3d.vsl.MacroContext, append_line: fun (line: string), parameters: string[])
end

--------------------------------------------------------------------------------
--[[ v3d.vsl.process ]]---------------------------------------------------------
--------------------------------------------------------------------------------

do
	local function _parse_parameters(s)
		local params = {}
		local i = 1
		local start = 1
		local in_string = nil

		while i <= #s do
			local char = s:sub(i, i)

			if (char == '\'' or char == '"') and not in_string then
				in_string = char
				i = i + 1
			elseif char == in_string then
				in_string = nil
				i = i + 1
			elseif char == '\\' then
				i = i + (in_string and 2 or 1)
			elseif in_string then
				i = select(2, assert(s:find('[^\\\'"]+', i))) + 1
			elseif char == '(' or char == '{' or char == '[' then
				local close = char == '(' and ')' or char == '{' and '}' or ']'
				i = select(2, assert(s:find('%b' .. char .. close, i))) + 1
			elseif char == ',' then
				table.insert(params, s:sub(start, i - 1))
				start = i + 1
				i = i + 1
			else
				i = select(2, assert(s:find('[^\\\'"(){}%[%],]+', i))) + 1
			end
		end

		if i > start then
			table.insert(params, s:sub(start))
		end

		for i = 1, #params do
			params[i] = params[i]:gsub('^%s+', '', 1):gsub('%s+$', '', 1)
		end

		return params
	end

	--- TODO
	--- @param macros { [string]: string | v3d.vsl.MacroContext }
	--- @param context v3d.vsl.MacroContext
	--- @param code v3d.vsl.Code
	--- @return string
	--- @nodiscard
	function v3d.vsl.process(macros, context, code)
		local changed
		local table_insert = table.insert
		local local_contexts = {}

		repeat
			changed = false
			code = ('\n' .. code):gsub('(\n[ \t]*)([^\n]-[^_])(v3d_[%w_]+)(%b())', function(w, c, f, p)
				local params = _parse_parameters(p:sub(2, -2))
				local result = {}

				if c:find '%-%-' then
					return w .. c .. f .. p
				end

				local replace = macros[f]

				if not replace then
					return w .. c .. f .. p
				end

				if not c:find "[^ \t]" then
					w = w .. c
					c = ''
				end

				if type(replace) == 'function' then
					local local_context = local_contexts[f]
					if not local_context then
						local_context = {}
						local_contexts[f] = local_context
					end

					replace(local_context, context, function(line) table_insert(result, line) end, params)
				elseif #params == 0 then
					result[1] = replace
				else
					error('Tried to pass parameters to a string replacement')
				end

				changed = true

				return w .. c .. table.concat(result, w)
			end):sub(2)
		until not changed

		return code
	end
end

--------------------------------------------------------------------------------
--[[ v3d.vsl.process_fragment_shader ]]-----------------------------------------
--------------------------------------------------------------------------------

do
	local fragment_shader_macros = {}

	--- @diagnostic disable: invisible

	local function register_generic(context, list, name)
		context.internal[list] = context.internal[list] or {}

		local lookup = context.internal[list]

		if not lookup[name] then
			table.insert(list, name)
			lookup[name] = true
		end
	end

	--- @param context v3d.vsl.FragmentShaderMacroContext
	local function register_attribute(context, name)
		local attr = context.format:get_attribute(name) or error('Unknown attribute \'' .. name .. '\'')

		context.internal.attribute_names_lookup = context.internal.attribute_names_lookup or {}

		if context.internal.attribute_names_lookup[name] then
			return attr
		end

		context.internal.attribute_names_lookup[name] = true

		if attr.type == 'vertex' then
			table.insert(context.vertex_attributes_accessed, attr)

			for i = 1, attr.components do
				table.insert(context.interpolate_attribute_components, { name = attr.name, component = i })
			end
		else
			table.insert(context.face_attributes_accessed, attr)
		end

		return attr
	end

	--- @param context v3d.vsl.FragmentShaderMacroContext
	local function register_layer(context, name)
		local layer = context.layout:get_layer(name) or error('Unknown layer \'' .. name .. '\'')

		context.internal.layer_names_lookup = context.internal.layer_names_lookup or {}
		context.internal.layer_sizes_lookup = context.internal.layer_sizes_lookup or {}

		if not context.internal.layer_names_lookup[name] then
			table.insert(context.layers_accessed, layer)
			context.internal.layer_names_lookup[name] = true
		end

		if not context.internal.layer_sizes_lookup[layer.components] then
			table.insert(context.layer_sizes_accessed, layer.components)
			context.internal.layer_sizes_lookup[layer.components] = true
		end

		return layer
	end

	local function layer_index(layer, i)
		if i == 1 then -- TODO: hardcoded ref
			return '_v3d_fragment_layer_index' .. layer.components
		else
			return '_v3d_fragment_layer_index' .. layer.components .. ' + ' .. i - 1
		end
	end

	fragment_shader_macros.v3d_pixel_aspect_ratio = '{= opt_pixel_aspect_ratio =}'
	-- TODO: hardcoded ref
	fragment_shader_macros.v3d_transform = '_v3d_transform'
	fragment_shader_macros.v3d_model_transform = '_v3d_model_transform'
	fragment_shader_macros.v3d_framebuffer_width = '_v3d_fb_width'
	fragment_shader_macros.v3d_framebuffer_height = '_v3d_fb_height'

	--- @param context v3d.vsl.FragmentShaderMacroContext
	function fragment_shader_macros:v3d_read_uniform(context, append_line, parameters)
		local name = v3d.text.unquote(parameters[1])
		register_generic(context, context.uniforms_accessed, name)
		append_line('{= get_uniform_name(\'' .. name .. '\') =}')
	end

	--- @param context v3d.vsl.FragmentShaderMacroContext
	function fragment_shader_macros:v3d_write_uniform(context, append_line, parameters)
		local name = v3d.text.unquote(parameters[1])
		register_generic(context, context.uniforms_accessed, name)
		register_generic(context, context.uniforms_written_to, name)
		append_line('{= get_uniform_name(\'' .. name .. '\') =} = ' .. parameters[2])
	end

	--- @param context v3d.vsl.FragmentShaderMacroContext
	function fragment_shader_macros:v3d_write_layer_values(context, append_line, parameters)
		local layer = register_layer(context, v3d.text.unquote(parameters[1]))

		for i = 1, layer.components do
			append_line('_v3d_layer_' .. layer.name .. '[' .. layer_index(layer, i) .. '] = ' .. tostring(parameters[i + 1])) -- TODO: hardcoded ref
		end

		append_line('{! notify_any_layer_written() !}')
		append_line('{! notify_specific_layer_written(\'' .. layer.name .. '\') !}')
	end

	--- @param context v3d.vsl.FragmentShaderMacroContext
	function fragment_shader_macros:v3d_write_layer(context, append_line, parameters)
		local i = tonumber(parameters[3] and parameters[2] or '1')
		local layer = register_layer(context, v3d.text.unquote(parameters[1]))

		append_line('_v3d_layer_' .. layer.name .. '[' .. layer_index(layer, i) .. '] = ' .. parameters[i + 1]) -- TODO: hardcoded ref
		append_line('{! notify_any_layer_written() !}')
		append_line('{! notify_specific_layer_written(\'' .. layer.name .. '\') !}')
	end

	--- @param context v3d.vsl.FragmentShaderMacroContext
	function fragment_shader_macros:v3d_read_layer_values(context, append_line, parameters)
		local layer = register_layer(context, v3d.text.unquote(parameters[1]))
		local parts = {}

		for i = 1, layer.components do
			table.insert(parts, '_v3d_layer_' .. layer.name .. '[' .. layer_index(layer, i) .. ']') -- TODO: hardcoded ref
		end

		append_line(table.concat(parts, ', '))
	end

	--- @param context v3d.vsl.FragmentShaderMacroContext
	function fragment_shader_macros:v3d_read_layer(context, append_line, parameters)
		local i = tonumber(parameters[2] or '1')
		local layer = register_layer(context, v3d.text.unquote(parameters[1]))

		append_line('_v3d_layer_' .. layer.name .. '[' .. layer_index(layer, i) .. ']') -- TODO: hardcoded ref
	end

	--- @param context v3d.vsl.FragmentShaderMacroContext
	function fragment_shader_macros:v3d_was_layer_written(context, append_line, parameters)
		if parameters[1] then
			local name = v3d.text.unquote(parameters[1])
			context.is_called_layer_was_written[name] = true
			append_line('_v3d_specific_layer_written_' .. name) -- TODO: hardcoded ref
		else
			context.is_called_any_layer_was_written = true
			append_line('_v3d_any_layer_written') -- TODO: hardcoded ref
		end
	end

	--- @param context v3d.vsl.FragmentShaderMacroContext
	function fragment_shader_macros:v3d_read_attribute_values(context, append_line, parameters)
		local attr = register_attribute(context, v3d.text.unquote(parameters[1]))
		local parts = {}

		for i = 1, attr.components do
			table.insert(parts, '{= get_interpolated_attribute_component_name(\'' .. attr.name .. '\', ' .. i .. ') =}')
		end

		append_line(table.concat(parts, ', '))
	end

	--- @param context v3d.vsl.FragmentShaderMacroContext
	function fragment_shader_macros:v3d_read_attribute(context, append_line, parameters)
		local i = tonumber(parameters[2] or '1')
		local attr = register_attribute(context, v3d.text.unquote(parameters[1]))

		append_line('{= get_interpolated_attribute_component_name(\'' .. attr.name .. '\', ' .. i .. ') =}')
	end

	--- @param context v3d.vsl.FragmentShaderMacroContext
	function fragment_shader_macros:v3d_fragment_depth(context, append_line, _)
		context.is_called_fragment_depth = true
		append_line('{= ref_fragment_depth =}')
	end

	--- @param context v3d.vsl.FragmentShaderMacroContext
	function fragment_shader_macros:v3d_fragment_world_position(context, append_line, parameters)
		local component = parameters[1] and v3d.text.unquote(parameters[1])

		context.is_called_fragment_world_position = true

		local parts = {}

		for i = 1, 3 do
			if not component or (i == 1 and component == 'x' or i == 2 and component == 'y' or i == 3 and component == 'z') then
				if not self[i] then
					table.insert(context.interpolate_attribute_components, { name = '_v3d_fragment_world_position', component = i })
					self[i] = true
				end
				table.insert(parts, '{= get_interpolated_attribute_component_name(\'_v3d_fragment_world_position\', ' .. i .. ') =}')
			end
		end

		append_line(table.concat(parts, ', '))
	end

	--- @param context v3d.vsl.FragmentShaderMacroContext
	function fragment_shader_macros:v3d_face_world_normal(context, append_line, parameters)
		local component = parameters[1] and v3d.text.unquote(parameters[1])

		context.is_called_face_world_normal = true

		local parts = {}

		for i = 1, 3 do
			if not component or (i == 1 and component == 'x' or i == 2 and component == 'y' or i == 3 and component == 'z') then
				table.insert(parts, '_v3d_face_world_normal' .. i - 1) -- TODO: hardcoded ref
			end
		end

		append_line(table.concat(parts, ', '))
	end

	function fragment_shader_macros:v3d_discard_fragment(_, append_line, _)
		append_line('{= fragment_shader.is_called_fragment_discarded and builtin_fragment_discarded .. \' = true\' or \'\' =}')
	end

	--- @param context v3d.vsl.FragmentShaderMacroContext
	function fragment_shader_macros:v3d_is_fragment_discarded(context, append_line, _)
		context.is_called_is_fragment_discarded = true
		append_line('{= builtin_fragment_discarded =}')
	end

	--- @param context v3d.vsl.FragmentShaderMacroContext
	function fragment_shader_macros:v3d_count_event(context, append_line, parameters)
		local name = v3d.text.unquote(parameters[1])
		register_generic(context, context.event_counters_written_to, name)
		append_line('{! increment_event_counter(\'' .. name .. '\', ' .. (parameters[2] or '1') .. ') !}')
	end

	function fragment_shader_macros:v3d_compare_depth(_, append_line, parameters)
		append_line(parameters[1] .. ' > ' .. parameters[2])
	end

	--- TODO
	--- @param layout v3d.Layout
	--- @param format v3d.Format
	--- @param fragment_shader_code v3d.vsl.FragmentShaderCode
	--- @return v3d.vsl.FragmentShaderMacroContext, string
	function v3d.vsl.process_fragment_shader(layout, format, fragment_shader_code)
		--- @type v3d.vsl.FragmentShaderMacroContext
		local context = {}

		context.event_counters_written_to = {}
		context.face_attributes_accessed = {}
		context.format = format
		context.internal = {}
		context.interpolate_attribute_components = {}
		context.is_called_any_layer_was_written = false
		context.is_called_face_world_normal = false
		context.is_called_fragment_depth = false
		context.is_called_fragment_world_position = false
		context.is_called_is_fragment_discarded = false
		context.is_called_layer_was_written = {}
		context.layer_sizes_accessed = {}
		context.layers_accessed = {}
		context.layout = layout
		context.uniforms_accessed = {}
		context.uniforms_written_to = {}
		context.vertex_attributes_accessed = {}
		
		local code = v3d.vsl.process(fragment_shader_macros, context, fragment_shader_code)

		table.sort(context.layer_sizes_accessed)

		return context, code
	end

	--- @diagnostic enable: invisible
end
