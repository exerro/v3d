
local v3d_internal = require '_internal'
local v3d_framebuffer = require '_framebuffer'
local v3d_geometry = require '_geometry'
local v3d_text = require 'text'

local v3d_vsl = {}

--------------------------------------------------------------------------------
--[[ v3d.vsl.UniformName ]]-----------------------------------------------------
--------------------------------------------------------------------------------

do
	--- Name of a uniform. Should be a string matching the following Lua
	--- pattern:
	--- `[a-zA-Z][a-zA-Z0-9_]*`.
	--- @alias v3d.vsl.UniformName string
end

--------------------------------------------------------------------------------
--[[ v3d.vsl.Code ]]------------------------------------------------------------
--------------------------------------------------------------------------------

do
	--- TODO
	--- V3D shader language code.
	---
	--- Normal Lua code, with some macros and constraints on variable names.
	--- * Variable names beginning with `_v3d` should strictly not be used.
	--- * Variable names beginning with `v3d` are always function-style macros
	---   expanded by V3D into inline code. The specific type of code should
	---   inform you of which macros are accessible for your use case. All VSL
	---   code has the following macros:
	---
	--- v3d_compare_depth(any, any)
	--- v3d_count_event(string-literal)
	--- v3d_count_event(string-literal, any)
	---
	--- v3d_read_uniform(string-literal)
	--- v3d_write_uniform(string-literal, any)
	--- @alias v3d.vsl.Code string
end

--------------------------------------------------------------------------------
--[[ v3d.vsl.FramebufferBoundCode ]]--------------------------------------------
--------------------------------------------------------------------------------

do
	--- TODO
	---
	--- v3d_framebuffer_index()
	--- v3d_framebuffer_index(components: integer-literal)
	--- v3d_framebuffer_index(components: integer-literal, component: integer-literal)
	--- v3d_framebuffer_index_offset(dx: integer-literal, dy: integer-literal)
	--- v3d_framebuffer_index_offset(components: integer-literal, dx: integer-literal, dy: integer-literal)
	--- v3d_framebuffer_index_offset(components: integer-literal, component: integer-literal, dx: integer-literal, dy: integer-literal)
	--- v3d_framebuffer_layer(string-literal)
	--- v3d_framebuffer_position()
	--- v3d_framebuffer_position('x' | 'y')
	--- v3d_framebuffer_size()
	--- v3d_framebuffer_size('width' | 'height' | 'width-1' | 'height-1')
	--- v3d_read_layer_values(string-literal)
	--- v3d_read_layer(string-literal)
	--- v3d_read_layer(string-literal, integer-literal)
	--- v3d_write_layer_values(string-literal, any...)
	--- v3d_write_layer(string-literal, any)
	--- v3d_write_layer(string-literal, integer-literal, any)
	--- @alias v3d.vsl.FramebufferBoundCode v3d.vsl.Code
end

--------------------------------------------------------------------------------
--[[ v3d.vsl.FragmentShaderCode ]]----------------------------------------------
--------------------------------------------------------------------------------

do
	--- TODO
	--- v3d_pixel_aspect_ratio()
	--- v3d_transform()
	--- v3d_model_transform()
	---
	--- v3d_read_attribute_values(string-literal)
	--- v3d_read_attribute(string-literal)
	--- v3d_read_attribute(string-literal, integer-literal)
	---
	--- v3d_face_attribute_max_pixel_delta(string-literal, integer-literal)
	---
	--- v3d_face_row_bounds()
	--- v3d_face_row_bounds('min' | 'max')
	---
	--- v3d_face_world_normal()
	--- v3d_face_world_normal('x' | 'y' | 'z')
	---
	--- v3d_face_was_clipped()
	---
	--- v3d_row_column_bounds()
	--- v3d_row_column_bounds('min' | 'max')
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
	--- @alias v3d.vsl.FragmentShaderCode v3d.vsl.FramebufferBoundCode
end

--------------------------------------------------------------------------------
--[[ v3d.vsl.PixelShaderCode ]]----------------------------------------------
--------------------------------------------------------------------------------

do
	--- TODO
	--- @alias v3d.vsl.PixelShaderCode v3d.vsl.FramebufferBoundCode
end

--------------------------------------------------------------------------------
--[[ Macro sets ]]--------------------------------------------------------------
--------------------------------------------------------------------------------

local macro_sets, create_macro_set, register_generic

do
	macro_sets = {}

	--- @return { [string]: string | v3d.vsl.MacroHandler }
	function create_macro_set(...)
		local macros = {}

		for _, extends in ipairs { ... } do
			for k, v in pairs(extends) do
				macros[k] = v
			end
		end

		return macros
	end

	function register_generic(context, list, name, value)
		if not list then v3d_internal.internal_error('Missing list (' .. tostring(name) .. ')', 2) end

		context.__internal_lookups = context.__internal_lookups or {}
		context.__internal_lookups[list] = context.__internal_lookups[list] or {}

		local lookup = context.__internal_lookups[list]

		if not lookup[name] then
			table.insert(list, value == nil and name or value)
			lookup[name] = true
			return true
		end

		return false
	end
end

do -- default
	macro_sets.default = create_macro_set()

	function macro_sets.default:v3d_compare_depth(_, append_line, parameters)
		append_line(parameters[1] .. ' > ' .. parameters[2])
	end

	--- @param context v3d.vsl.FragmentShaderMacroContext
	function macro_sets.default:v3d_count_event(context, append_line, parameters)
		local name = v3d_text.unquote(parameters[1])
		register_generic(context, context.event_counters_written_to, name)
		append_line('{! increment_event_counter(\'' .. name .. '\', ' .. (parameters[2] or '1') .. ') !}')
	end

	--- @param context v3d.vsl.FragmentShaderMacroContext
	function macro_sets.default:v3d_read_uniform(context, append_line, parameters)
		local name = v3d_text.unquote(parameters[1])
		register_generic(context, context.uniforms_accessed, name)
		append_line('{= get_uniform_name(\'' .. name .. '\') =}')
	end

	--- @param context v3d.vsl.FragmentShaderMacroContext
	function macro_sets.default:v3d_write_uniform(context, append_line, parameters)
		local name = v3d_text.unquote(parameters[1])
		register_generic(context, context.uniforms_accessed, name)
		register_generic(context, context.uniforms_written_to, name)
		append_line('{= get_uniform_name(\'' .. name .. '\') =} = ' .. parameters[2])
	end
end

do -- framebuffer_bound
	macro_sets.framebuffer_bound = create_macro_set()

	--- @param context v3d.vsl.FramebufferBoundMacroContext
	local function register_layer(context, name)
		local layer = context.layout:get_layer(name) or v3d_internal.contextual_error('Unknown layer \'' .. name .. '\'')

		register_generic(context, context.layers_accessed, name, layer)
		register_generic(context, context.layer_sizes_accessed, layer.components)

		return layer
	end

	--- @param context v3d.vsl.FramebufferBoundMacroContext
	function macro_sets.framebuffer_bound:v3d_framebuffer_index(context, append_line, parameters)
		local components = parameters[1] or '1'
		local component = parameters[2] or '1'

		register_generic(context, context.layer_sizes_accessed, tonumber(components))
		append_line('{! get_layer_index(' .. components .. ', ' .. component .. ') !}')
	end

	function macro_sets.framebuffer_bound:v3d_framebuffer_index_offset(_, append_line, parameters)
		local components = 1
		local component = 1
		local dx, dy = tonumber(parameters[1]), tonumber(parameters[2])

		if parameters[3] then
			components = dx
			dx = dy
			dy = tonumber(parameters[3])
		end

		if parameters[4] then
			component = dx
			dx = dy
			dy = tonumber(parameters[4])
		end

		local prefix = dy == 0 and '' or '('
		local suffix = dy == 0 and '' or ' + v3d_framebuffer_size(\'width\', ' .. components * dy .. '))'

		append_line(prefix .. 'v3d_framebuffer_index(' .. components .. ', ' .. component + dx * components .. ')' .. suffix)
	end

	--- @param context v3d.vsl.FramebufferBoundMacroContext
	function macro_sets.framebuffer_bound:v3d_framebuffer_layer(context, append_line, parameters)
		local name = v3d_text.unquote(parameters[1])
		local layer = context.layout:get_layer(name) or error('Unknown layer \'' .. name .. '\'')

		register_generic(context, context.layers_accessed, name, layer)

		append_line('{! get_layer(\'' .. name .. '\') !}')
	end

	--- @param context v3d.vsl.FramebufferBoundMacroContext
	function macro_sets.framebuffer_bound:v3d_framebuffer_position(context, append_line, parameters)
		if not parameters[1] then
			append_line('v3d_framebuffer_position(\'x\'), v3d_framebuffer_size(\'y\')')
			return
		end

		local attr = v3d_text.unquote(parameters[1])

		if attr == 'x' then
			context.framebuffer_x_accessed = true
			append_line('{! ref_framebuffer_x !}')
		elseif attr == 'y' then
			context.framebuffer_y_accessed = true
			append_line('{! ref_framebuffer_y !}')
		elseif attr == 'x+1' then
			context.framebuffer_x1_accessed = true
			append_line('{! ref_framebuffer_x_plus_one !}')
		elseif attr == 'y+1' then
			context.framebuffer_y1_accessed = true
			append_line('{! ref_framebuffer_y_plus_one !}')
		end
	end

	function macro_sets.framebuffer_bound:v3d_framebuffer_size(_, append_line, parameters)
		if not parameters[1] then
			append_line('v3d_framebuffer_size(\'width\'), v3d_framebuffer_size(\'height\')')
			return
		end

		local attr = v3d_text.unquote(parameters[1])
		local scale = parameters[2] or '1'
		local prefix = scale == '1' and '' or '('
		local suffix = scale == '1' and '' or ' * ' .. scale .. ')'

		-- TODO: track what we're using
		if attr == 'width' then
			append_line(prefix .. '_v3d_fb_width' .. suffix) -- TODO: hardcoded ref
		elseif attr == 'height' then
			append_line('(' .. prefix .. '_v3d_fb_height_m1' .. suffix .. ' + ' .. scale .. ')') -- TODO: hardcoded ref
		elseif attr == 'width-1' then
			append_line(prefix .. '_v3d_fb_width_m1' .. suffix) -- TODO: hardcoded ref
		elseif attr == 'height-1' then
			append_line(prefix .. '_v3d_fb_height_m1' .. suffix) -- TODO: hardcoded ref
		end
	end

	--- @param context v3d.vsl.FramebufferBoundMacroContext
	function macro_sets.framebuffer_bound:v3d_read_layer_values(context, append_line, parameters)
		local layer = register_layer(context, v3d_text.unquote(parameters[1]))
		local parts = {}

		for i = 1, layer.components do
			table.insert(parts, 'v3d_framebuffer_layer(\'' .. layer.name .. '\')[v3d_framebuffer_index(' .. layer.components .. ', ' .. i .. ')]')
		end

		append_line(table.concat(parts, ', '))
	end

	--- @param context v3d.vsl.FramebufferBoundMacroContext
	function macro_sets.framebuffer_bound:v3d_read_layer(context, append_line, parameters)
		local i = tonumber(parameters[2] or '1')
		local layer = register_layer(context, v3d_text.unquote(parameters[1]))

		append_line('v3d_framebuffer_layer(\'' .. layer.name .. '\')[v3d_framebuffer_index(' .. layer.components .. ', ' .. i .. ')]')
	end

	--- @param context v3d.vsl.FramebufferBoundMacroContext
	function macro_sets.framebuffer_bound:v3d_write_layer_values(context, append_line, parameters)
		local layer = register_layer(context, v3d_text.unquote(parameters[1]))

		for i = 1, layer.components do
			append_line('v3d_framebuffer_layer(\'' .. layer.name .. '\')[v3d_framebuffer_index(' .. layer.components .. ', ' .. i .. ')] = ' .. parameters[i + 1])
		end
	end

	--- @param context v3d.vsl.FramebufferBoundMacroContext
	function macro_sets.framebuffer_bound:v3d_write_layer(context, append_line, parameters)
		local i = tonumber(parameters[3] and parameters[2] or '1')
		local layer = register_layer(context, v3d_text.unquote(parameters[1]))

		append_line('v3d_framebuffer_layer(\'' .. layer.name .. '\')[v3d_framebuffer_index(' .. layer.components .. ', ' .. i .. ')] = ' .. (parameters[3] or parameters[2]))
	end
end

--------------------------------------------------------------------------------
--[[ v3d.vsl.MacroContext ]]----------------------------------------------------
--------------------------------------------------------------------------------

local init_context = {}

do
	--- TODO
	--- @class v3d.vsl.MacroContext: { [string]: any }
	--- TODO
	--- @field event_counters_written_to string[]
	--- Names of all the uniform variables which are accessed (read/write).
	--- @field uniforms_accessed string[]
	--- Names of all the uniform variables which are explicitly written to.
	--- @field uniforms_written_to string[]
end

--------------------------------------------------------------------------------
--[[ v3d.vsl.DefaultMacroContext ]]---------------------------------------------
--------------------------------------------------------------------------------

do
	--- TODO
	--- @class v3d.vsl.DefaultMacroContext: v3d.vsl.MacroContext
	--- TODO
	--- @field event_counters_written_to string[]
	--- TODO
	--- @field uniforms_accessed v3d.vsl.UniformName[]
	--- TODO
	--- @field uniforms_written_to v3d.vsl.UniformName[]

	function init_context:default()
		self.event_counters_written_to = {}
		self.uniforms_accessed = {}
		self.uniforms_written_to = {}
	end
end

--------------------------------------------------------------------------------
--[[ v3d.vsl.FramebufferBoundMacroContext ]]------------------------------------
--------------------------------------------------------------------------------

do
	--- TODO
	--- @class v3d.vsl.FramebufferBoundMacroContext: v3d.vsl.DefaultMacroContext
	--- TODO
	--- @field layout v3d.Layout
	--- Ordered set of sizes of layers written to.
	--- @field layer_sizes_accessed integer[]
	--- Names of all the layers written to by the shader.
	--- @field layers_accessed v3d.LayerName[]
	--- TODO
	--- @field framebuffer_x_accessed boolean
	--- TODO
	--- @field framebuffer_y_accessed boolean
	--- TODO
	--- @field framebuffer_x1_accessed boolean
	--- TODO
	--- @field framebuffer_y1_accessed boolean

	--- @param layout v3d.Layout
	function init_context:framebuffer_bound(layout)
		self.layout = layout
		self.layer_sizes_accessed = {}
		self.layers_accessed = {}
		self.framebuffer_x_accessed = false
		self.framebuffer_y_accessed = false
		self.framebuffer_x1_accessed = false
		self.framebuffer_y1_accessed = false
	end
end

--------------------------------------------------------------------------------
--[[ v3d.vsl.FragmentShaderMacroContext ]]--------------------------------------
--------------------------------------------------------------------------------

do
	--- TODO
	--- @class v3d.vsl.FragmentShaderMacroContext: v3d.vsl.FramebufferBoundMacroContext
	--- @field private internal { [string]: any }
	--- TODO
	--- @field format v3d.Format
	--- TODO
	--- @field face_attributes_accessed v3d.Attribute[]
	--- TODO
	--- @field face_attribute_max_pixel_deltas { name: string, component: integer }[]
	--- TODO
	--- @field interpolate_attribute_components { name: string, component: integer }[]
	--- TODO
	--- @field is_called_face_world_normal boolean
	--- TODO
	--- @field is_called_fragment_depth boolean
	--- TODO
	--- @field is_called_fragment_world_position boolean
	--- TODO
	--- @field is_called_is_fragment_discarded boolean
	--- TODO
	--- @field vertex_attributes_accessed v3d.Attribute[]

	--- @param format v3d.Format
	function init_context:fragment_shader(format)
		self.format = format
		self.face_attributes_accessed = {}
		self.face_attribute_max_pixel_deltas = {}
		self.interpolate_attribute_components = {}
		self.is_called_face_world_normal = false
		self.is_called_fragment_depth = false
		self.is_called_fragment_world_position = false
		self.is_called_is_fragment_discarded = false
		self.vertex_attributes_accessed = {}
	end
end

--------------------------------------------------------------------------------
--[[ v3d.vsl.PixelShaderMacroContext ]]-----------------------------------------
--------------------------------------------------------------------------------

do
	--- TODO
	--- @class v3d.vsl.PixelShaderMacroContext: v3d.vsl.FramebufferBoundMacroContext

	function init_context:pixel_shader()
		
	end
end

--------------------------------------------------------------------------------
--[[ v3d.vsl.MacroHandler ]]----------------------------------------------------
--------------------------------------------------------------------------------

do
	--- TODO
	--- @alias v3d.vsl.MacroHandler fun (local_context: v3d.vsl.MacroContext, context: v3d.vsl.MacroContext, append_line: fun (line: string), parameters: string[])
end

--------------------------------------------------------------------------------
--[[ v3d.vsl.Accelerated ]]-----------------------------------------------------
--------------------------------------------------------------------------------

do
	--- TODO
	--- @class v3d.vsl.Accelerated
	--- @field private sources { [string]: { source: v3d.vsl.Code | nil, compiled: string } }
	--- @field private uniforms table
	v3d_vsl.Accelerated = {}

	--- @private
	function v3d_vsl.Accelerated:add_source(name, source_code, compiled_block)
		local _, s = compiled_block:find('%-%-%-?%s*#%s*vsl_embed_start%s+' .. name)
		local f = compiled_block:find('%-%-%-?%s*#%s*vsl_embed_end%s+' .. name)

		self.sources[name] = {
			source = source_code,
			compiled = s and f and v3d_text.trim(v3d_text.unindent(compiled_block:sub(s + 1, f - 1))) or compiled_block,
		}
	end

	--- TODO
	 -- TODO: Should be somewhere else?
	--- @return { [string]: { source: v3d.vsl.Code, compiled: string } }
	--- @nodiscard
	function v3d_vsl.Accelerated:get_shaders()
		return self.sources
	end
	
	--- Set a uniform value which can be accessed from shaders.
	--- @param name v3d.vsl.UniformName Name of the uniform. Shaders can access using `uniforms[name]`
	--- @param value any Any value to pass to the shader.
	--- @return nil
	function v3d_vsl.Accelerated:set_uniform(name, value)
		self.uniforms[name] = value
	end

	--- Get a uniform value that's been set with `set_uniform`.
	--- @param name v3d.vsl.UniformName Name of the uniform.
	--- @return unknown
	--- @nodiscard
	function v3d_vsl.Accelerated:get_uniform(name)
		return self.uniforms[name]
	end

	--- Get a list of uniform names that have been set with `set_uniform`.
	--- @return v3d.vsl.UniformName[]
	--- @nodiscard
	function v3d_vsl.Accelerated:list_uniforms()
		local names = {}
		for k in pairs(self.uniforms) do
			table.insert(names, k)
		end
		return names
	end
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
	function v3d_vsl.process(macros, context, code)
		local changed
		local table_insert = table.insert
		local local_contexts = {}

		repeat
			changed = false
			code = ('\n' .. code):gsub('(\n[ \t]*)([^\n]-)([%w_]*v3d_[%w_]+)(%b())', function(w, c, f, p)
				local params = _parse_parameters(p:sub(2, -2))
				local result = {}

				if f:sub(1, 4) ~= 'v3d_' then
					return w .. c .. f .. p
				end

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
					v3d_internal.contextual_error('Tried to pass parameters to a string replacement')
				end

				changed = true

				return w .. c .. table.concat(result, w)
			end):sub(2)
		until not changed

		return code
	end
end

--------------------------------------------------------------------------------
--[[ v3d.vsl.process_default_shader ]]-----------------------------------------
--------------------------------------------------------------------------------

do
	--- @diagnostic disable: invisible

	--- TODO
	--- @param shader_code v3d.vsl.FragmentShaderCode
	--- @param context v3d.vsl.MacroContext | nil
	--- @return v3d.vsl.FragmentShaderMacroContext, string
	function v3d_vsl.process_default_shader(shader_code, context)
		if not context then
			context = {}

			init_context.default(context)
		end

		local code = v3d_vsl.process(macro_sets.default, context, shader_code)

		table.sort(context.layer_sizes_accessed)

		return context, code
	end

	--- @diagnostic enable: invisible
end

--------------------------------------------------------------------------------
--[[ v3d.vsl.process_fragment_shader ]]-----------------------------------------
--------------------------------------------------------------------------------

do
	local fragment_shader_macros = create_macro_set(macro_sets.default, macro_sets.framebuffer_bound)

	--- @diagnostic disable: invisible

	--- @param context v3d.vsl.FragmentShaderMacroContext
	local function register_attribute(context, name)
		local attr = context.format:get_attribute(name) or v3d_internal.contextual_error('Unknown attribute \'' .. name .. '\'')

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

	fragment_shader_macros.v3d_pixel_aspect_ratio = '{= opt_pixel_aspect_ratio =}'
	-- TODO: hardcoded ref
	fragment_shader_macros.v3d_transform = '_v3d_transform'
	fragment_shader_macros.v3d_model_transform = '_v3d_model_transform'

	--- @param context v3d.vsl.FragmentShaderMacroContext
	function fragment_shader_macros:v3d_read_attribute_values(context, append_line, parameters)
		local attr = register_attribute(context, v3d_text.unquote(parameters[1]))
		local parts = {}

		for i = 1, attr.components do
			table.insert(parts, '{= get_interpolated_attribute_component_name(\'' .. attr.name .. '\', ' .. i .. ') =}')
		end

		append_line(table.concat(parts, ', '))
	end

	--- @param context v3d.vsl.FragmentShaderMacroContext
	function fragment_shader_macros:v3d_read_attribute(context, append_line, parameters)
		local i = tonumber(parameters[2] or '1')
		local attr = register_attribute(context, v3d_text.unquote(parameters[1]))

		append_line('{= get_interpolated_attribute_component_name(\'' .. attr.name .. '\', ' .. i .. ') =}')
	end

	--- @param context v3d.vsl.FragmentShaderMacroContext
	function fragment_shader_macros:v3d_face_attribute_max_pixel_delta(context, append_line, parameters)
		-- TODO: make this not necessarily interpolate the attribute
		local i = tonumber(parameters[2])
		local attr = register_attribute(context, v3d_text.unquote(parameters[1]))

		-- TODO: make this not double insert
		table.insert(context.face_attribute_max_pixel_deltas, { name = attr.name, component = i })

		append_line('{= get_face_attribute_max_pixel_delta(\'' .. attr.name .. '\', ' .. i .. ') =}')
	end

	--- @param context v3d.vsl.FragmentShaderMacroContext
	function fragment_shader_macros:v3d_fragment_depth(context, append_line, _)
		context.is_called_fragment_depth = true
		append_line('{= ref_fragment_depth =}')
	end

	--- @param context v3d.vsl.FragmentShaderMacroContext
	function fragment_shader_macros:v3d_fragment_world_position(context, append_line, parameters)
		local component = parameters[1] and v3d_text.unquote(parameters[1])

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
		local component = parameters[1] and v3d_text.unquote(parameters[1])

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

	--- TODO
	--- @param layout v3d.Layout
	--- @param format v3d.Format
	--- @param fragment_shader_code v3d.vsl.FragmentShaderCode
	--- @return v3d.vsl.FragmentShaderMacroContext, string
	function v3d_vsl.process_fragment_shader(layout, format, fragment_shader_code)
		--- @type v3d.vsl.FragmentShaderMacroContext
		local context = {}

		init_context.default(context)
		init_context.framebuffer_bound(context, layout)
		init_context.fragment_shader(context, format)

		context.internal = {}
		
		local code = v3d_vsl.process(fragment_shader_macros, context, fragment_shader_code)

		table.sort(context.layer_sizes_accessed)

		return context, code
	end

	--- @diagnostic enable: invisible
end

--------------------------------------------------------------------------------
--[[ v3d.vsl.process_pixel_shader ]]-----------------------------------------
--------------------------------------------------------------------------------

do
	local pixel_shader_macros = create_macro_set(macro_sets.default, macro_sets.framebuffer_bound)

	--- @diagnostic disable: invisible

	--- TODO
	--- @param layout v3d.Layout
	--- @param pixel_shader_code v3d.vsl.FragmentShaderCode
	--- @return v3d.vsl.FragmentShaderMacroContext, string
	function v3d_vsl.process_pixel_shader(layout, pixel_shader_code)
		--- @type v3d.vsl.FragmentShaderMacroContext
		local context = {}

		init_context.default(context)
		init_context.framebuffer_bound(context, layout)
		init_context.pixel_shader(context)

		local code = v3d_vsl.process(pixel_shader_macros, context, pixel_shader_code)

		table.sort(context.layer_sizes_accessed)

		return context, code
	end

	--- @diagnostic enable: invisible
end

return v3d_vsl
