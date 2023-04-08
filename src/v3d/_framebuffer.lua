
local v3d_internal = require '_internal'

local v3d_framebuffer = {}

--------------------------------------------------------------------------------
--[[ v3d.Layer* ]]--------------------------------------------------------------
--------------------------------------------------------------------------------

do
	--- Name of a layer. Should be a string matching the following Lua pattern:
	--- `[a-zA-Z][a-zA-Z0-9_]*`.
	--- @alias v3d.LayerName string

	--- TODO
	--- @alias v3d.LayerType 'palette-index' | 'exp-palette-index' | 'depth-reciprocal' | 'any-numeric' | 'any'

	--- TODO
	--- @class v3d.Layer
	--- TODO
	--- @field name v3d.LayerName
	--- TODO
	--- @field type v3d.LayerType
	--- TODO
	--- @field components integer
end

--------------------------------------------------------------------------------
--[[ v3d.Layout ]]--------------------------------------------------------------
--------------------------------------------------------------------------------

do
	--- TODO
	--- @class v3d.Layout
	--- TODO
	--- @field layers v3d.Layer[]
	--- TODO
	--- @field private layer_lookup { [v3d.LayerName]: integer | nil }
	v3d_framebuffer.Layout = {}

	--- TODO
	--- @param name v3d.LayerName
	--- @param type v3d.LayerType
	--- @param components integer
	--- @return v3d.Layout
	--- @nodiscard
	function v3d_framebuffer.Layout:add_layer(name, type, components)
		local new_layer = {}

		new_layer.name = name
		new_layer.type = type
		new_layer.components = components

		--- @type table
		local new_layout = v3d_framebuffer.create_layout()

		for i = 1, #self.layers do
			new_layout.layers[i] = self.layers[i]
			new_layout.layer_lookup[self.layers[i].name] = i
		end

		table.insert(new_layout.layers, new_layer)
		new_layout.layer_lookup[name] = #new_layout.layers

		return new_layout
	end

	--- TODO
	--- @param layer v3d.LayerName | v3d.Layer
	--- @return v3d.Layout
	--- @nodiscard
	function v3d_framebuffer.Layout:drop_layer(layer)
		if not self:has_layer(layer) then return self end
		local layer_name = layer.name or layer

		local new_layout = v3d_framebuffer.create_layout()

		for i = 1, #self.layers do
			local existing_layer = self.layers[i]
			if existing_layer.name ~= layer_name then
				new_layout = new_layout:add_layer(existing_layer.name, existing_layer.type, existing_layer.components)
			end
		end

		return new_layout
	end

	--- TODO
	--- @param layer v3d.LayerName | v3d.Layer
	--- @return boolean
	function v3d_framebuffer.Layout:has_layer(layer)
		if type(layer) == 'table' then
			local index = self.layer_lookup[layer.name]
			if not index then return false end
			return self.layers[index].type       == layer.type
			   and self.layers[index].components == layer.components
		end

		return self.layer_lookup[layer] ~= nil
	end

	--- TODO
	--- @param layer v3d.LayerName | v3d.Layer
	--- @return v3d.Layer | nil
	function v3d_framebuffer.Layout:get_layer(layer)
		if layer.name then
			return layer
		end

		local index = self.layer_lookup[layer]
		return index and self.layers[index]
	end
end

--------------------------------------------------------------------------------
--[[ v3d.Framebuffer ]]---------------------------------------------------------
--------------------------------------------------------------------------------

do
	local layer_defaults = {
		['palette-index'] = 0,
		['exp-palette-index'] = 1,
		['depth-reciprocal'] = 0,
		['any-numeric'] = 0,
		['any'] = 0,
	}
	
	--- Stores the per-pixel data for rendered triangles.
	--- @class v3d.Framebuffer
	--- Layout of the framebuffer which determines which data the framebuffer
	--- stores.
	--- @field layout v3d.Layout
	--- Width of the framebuffer in pixels. Note, if you're using subpixel
	--- rendering, this includes the subpixels, e.g. a 51x19 screen would have a
	--- width of 102 pixels in its framebuffer.
	--- @field width integer
	--- Height of the framebuffer in pixels. Note, if you're using subpixel
	--- rendering, this includes the subpixels, e.g. a 51x19 screen would have a
	--- height of 57 pixels in its framebuffer.
	--- @field height integer
	--- @field private layer_data { [v3d.LayerName]: unknown[] }
	v3d_framebuffer.Framebuffer = {}

	--- Get the data for a given layer.
	--- @param layer v3d.LayerName
	--- @return unknown[]
	--- @nodiscard
	function v3d_framebuffer.Framebuffer:get_buffer(layer)
		return self.layer_data[layer]
	end

	--- Sets the data for the entire layer to a particular value. If `value` is
	--- nil, a default value based on the layer's type will be used, as
	--- follows:
	--- Type | Default
	--- -|-
	--- `palette-index` | `0`
	--- `exp-palette-index` | `1`
	--- `depth-reciprocal` | `0`
	--- `any-numeric` | `0`
	--- `any` | `false`
	--- @param layer v3d.LayerName
	--- @param value any | nil
	--- @return nil
	function v3d_framebuffer.Framebuffer:clear(layer, value)
		local data = self.layer_data[layer]
		local l = self.layout:get_layer(layer)

		--- @cast l v3d.Layer

		if value == nil then
			value = layer_defaults[l.type] or v3d_internal.internal_error('no default for layer type ' .. l.type)
		end

		for i = 1, self.width * self.height * l.components do
			data[i] = value
		end
	end
	--- Sets the data for the entire layer to a particular sequence of values.
	--- The number of items in `values` should match the number of components in
	--- the layer. Each value in `values` will be written to the corresponding
	--- component of every pixel in the framebuffer.
	--- @param layer v3d.LayerName
	--- @param values any[]
	--- @return nil
	function v3d_framebuffer.Framebuffer:clear_values(layer, values)
		local data = self.layer_data[layer]
		local n_components = #values

		for i = 0, self.width * self.height * n_components - 1, n_components do
			for j = 1, n_components do
				data[i + j] = values[j]
			end
		end
	end
end

--------------------------------------------------------------------------------
--[[ Constructors ]]------------------------------------------------------------
--------------------------------------------------------------------------------

do
	--- Create an empty [[@v3d.Layout]].
	--- See also: [[@v3d.COLOUR_LAYOUT]], [[@v3d.COLOUR_DEPTH_LAYOUT]]
	--- @return v3d.Layout
	--- @nodiscard
	function v3d_framebuffer.create_layout()
		local layout = {}

		layout.layers = {}
		layout.layer_lookup = {}

		for k, v in pairs(v3d_framebuffer.Layout) do
			layout[k] = v
		end

		return layout
	end

	--- Create an empty [[@v3d.Framebuffer]] of exactly `width` x `height`
	--- pixels.
	---
	--- If width_scale or height_scale are specified, the framebuffer size will
	--- multiplied by the corresponding scale factor. This is useful for
	--- situations like subpixel rendering, where you want to render to a larger
	--- framebuffer than the screen size, and then scale it down to the screen
	--- during the final blit.
	--- @param layout v3d.Layout Layout of the framebuffer, i.e. what data it contains.
	--- @param width integer Width of the framebuffer in pixels
	--- @param height integer Height of the framebuffer in pixels
	--- @param width_scale integer TODO
	--- @param height_scale integer TODO
	--- @param label string | nil Optional label for debugging
	--- @overload fun(layout: v3d.Layout, width: integer, height: integer, label: string): v3d.Framebuffer
	--- @return v3d.Framebuffer
	--- @nodiscard
	function v3d_framebuffer.create_framebuffer(layout, width, height, width_scale, height_scale, label)
		local fb = {}

		if not height_scale then
			width_scale = 1
			height_scale = 1
		end

		fb.layout = layout
		fb.width = width * width_scale
		fb.height = height * height_scale
		fb.layer_data = {}

		for k, v in pairs(v3d_framebuffer.Framebuffer) do
			fb[k] = v
		end

		for i = 1, #layout.layers do
			local layer = layout.layers[i]
			fb.layer_data[layer.name] = {}
			fb:clear(layer.name)
		end

		return fb
	end

	--- Create an empty [[@v3d.Framebuffer]] of exactly `width * 2` x `height * 3`
	--- pixels, suitable for rendering subpixels.
	--- @param layout v3d.Layout Layout of the framebuffer, i.e. what data it contains.
	--- @param width integer Width of the framebuffer in full screen pixels
	--- @param height integer Height of the framebuffer in full screen pixels
	--- @param label string | nil Optional label for debugging
	--- @return v3d.Framebuffer
	--- @nodiscard
	function v3d_framebuffer.create_framebuffer_subpixel(layout, width, height, label)
		return v3d_framebuffer.create_framebuffer(layout, 2, 3, width, height, label) -- multiply by subpixel dimensions
	end
end

return v3d_framebuffer
