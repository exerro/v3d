
local v3d = require 'core'

--------------------------------------------------------------------------------
--[[ v3d.AttributeName ]]-------------------------------------------------------
--------------------------------------------------------------------------------

do
	--- Name of an attribute. Should be a string matching the following Lua pattern:
	--- `[a-zA-Z][a-zA-Z0-9_]*`.
	--- @alias v3d.AttributeName string
end

--------------------------------------------------------------------------------
--[[ v3d.Attribute ]]-----------------------------------------------------------
--------------------------------------------------------------------------------

do
	--- An attribute in a format. Attributes represent a unit of data that can form
	--- vertices or faces of geometry. For example, "position" might be an
	--- attribute, as well as "colour" or "uv". Attributes have a number of fields
	--- that describe how much information is stored, and how it may be used.
	--- @class v3d.Attribute
	--- Name of the attribute.
	--- @field name v3d.AttributeName
	--- Number of components in this attribute, e.g. 3D position would have a size
	--- of `3`.
	--- @field components integer
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

--------------------------------------------------------------------------------
--[[ v3d.Format ]]--------------------------------------------------------------
--------------------------------------------------------------------------------

do
	local function format_add_attribute(self, name, components, type, is_numeric)
		local attr = {}
	
		attr.name = name
		attr.components = components
		attr.type = type
		attr.is_numeric = is_numeric
		attr.offset = type == 'vertex' and self.vertex_stride or self.face_stride
	
		--- @type table
		local new_format = v3d.create_format()
	
		for i = 1, #self.attributes do
			new_format.attributes[i] = self.attributes[i]
			new_format.attribute_lookup[self.attributes[i].name] = i
		end
	
		table.insert(new_format.attributes, attr)
		new_format.attribute_lookup[name] = #new_format.attributes
	
		if type == 'vertex' then
			new_format.vertex_stride = self.vertex_stride + components
			new_format.face_stride = self.face_stride
		else
			new_format.vertex_stride = self.vertex_stride
			new_format.face_stride = self.face_stride + components
		end
	
		return new_format
	end
	
	--- TODO
	--- @class v3d.Format
	--- TODO
	--- @field attributes v3d.Attribute[]
	--- TODO
	--- @field private attribute_lookup { [string]: integer | nil }
	--- TODO
	--- @field vertex_stride integer
	--- TODO
	--- @field face_stride integer
	v3d.Format = {}

	--- TODO
	--- @param name v3d.AttributeName
	--- @param components integer
	--- @param is_numeric true | false
	--- @return v3d.Format
	--- @nodiscard
	function v3d.Format:add_vertex_attribute(name, components, is_numeric)
		return format_add_attribute(self, name, components, 'vertex', is_numeric)
	end

	--- TODO
	--- @param name v3d.AttributeName
	--- @param components integer
	--- @return v3d.Format
	--- @nodiscard
	function v3d.Format:add_face_attribute(name, components)
		return format_add_attribute(self, name, components, 'face', false)
	end

	--- TODO
	--- @param attribute v3d.AttributeName | v3d.Attribute
	--- @return v3d.Format
	--- @nodiscard
	function v3d.Format:drop_attribute(attribute)
		if not self:has_attribute(attribute) then return self end
		local attribute_name = attribute.name or attribute
	
		local new_format = v3d.create_format()
	
		for i = 1, #self.attributes do
			local attr = self.attributes[i]
			if attr.name ~= attribute_name then
				new_format = format_add_attribute(new_format, attr.name, attr.components, attr.type, attr.is_numeric)
			end
		end
	
		return new_format
	end

	--- TODO
	--- @param attribute v3d.AttributeName | v3d.Attribute
	--- @return boolean
	function v3d.Format:has_attribute(attribute)
		if attribute.name then
			local index = self.attribute_lookup[attribute.name]
			if not index then return false end
			return self.attributes[index].components == attribute.components
			   and self.attributes[index].type       == attribute.type
			   and self.attributes[index].is_numeric == attribute.is_numeric
		end

		return self.attribute_lookup[attribute] ~= nil
	end

	--- TODO
	--- @param attribute v3d.AttributeName | v3d.Attribute
	--- @return v3d.Attribute | nil
	function v3d.Format:get_attribute(attribute)
		if attribute.name then
			return attribute
		end

		local index = self.attribute_lookup[attribute]
		return index and self.attributes[index]
	end
end

--------------------------------------------------------------------------------
--[[ v3d.GeometryBuilder ]]-----------------------------------------------------
--------------------------------------------------------------------------------

do
	--- Object used to build [[@v3d.Geometry]] instances. [[@v3d.Geometry]] is stored
	--- in an optimised self which depends on its format and is an implementation
	--- detail of the library. As a result, we use geometry builders to pass data
	--- for our geometry with a well-defined interface, and then build that to bake
	--- it into the optimised format.
	---
	--- Geometry builders let us set data for individual attributes, or append
	--- vertices and faces in one go.
	---
	--- See [[@v3d.GeometryBuilder.set_data]], [[@v3d.GeometryBuilder.cast]],
	--- [[@v3d.GeometryBuilder.build]].
	--- @class v3d.GeometryBuilder
	--- Format of this geometry builder, used when building the geometry using
	--- [[@v3d.GeometryBuilder.build]]. Can be changed with
	--- [[@v3d.GeometryBuilder.cast]].
	--- @field format v3d.Format
	--- @field private attribute_data { [v3d.AttributeName]: any[] }
	v3d.GeometryBuilder = {}

	--- Set the data for an attribute, replacing any existing data.
	---
	--- See also: [[@v3d.GeometryBuilder.append_data]]
	--- @param attribute_name v3d.AttributeName Name of the attribute to set the data for.
	--- @param data any[] New data, which replaces any existing data.
	--- @return v3d.GeometryBuilder self
	function v3d.GeometryBuilder:set_data(attribute_name, data)
		self.attribute_data[attribute_name] = data

		return self
	end

	--- Append data to the end of the existing data for an attribute.
	---
	--- See also: [[@v3d.GeometryBuilder.set_data]]
	--- @param attribute_name v3d.AttributeName Name of the attribute to append data to.
	--- @param data any[] New data to append.
	--- @return v3d.GeometryBuilder self
	function v3d.GeometryBuilder:append_data(attribute_name, data)
		local existing_data = self.attribute_data[attribute_name] or {}

		self.attribute_data[attribute_name] = existing_data
	
		for i = 1, #data do
			table.insert(existing_data, data[i])
		end
	
		return self
	end

	-- TODO: append_vertex
	-- TODO: append_face

	--- Map a function to the data for an attribute. The table returned replaces the
	--- existing data for the attribute.
	---
	--- Note, it's fine to return the same table and mutate it (and arguably more
	--- performant if you do that).
	--- @param attribute_name v3d.AttributeName Name of the attribute to apply `fn` to.
	--- @param fn fun(data: any[]): any[] Function called with the data for this attribute, which should return the new data.
	--- @return v3d.GeometryBuilder self
	function v3d.GeometryBuilder:map(attribute_name, fn)
		local components = self.format:get_attribute(attribute_name).components
		local data = self.attribute_data[attribute_name]
	
		for i = 0, #data - 1, components do
			local unmapped = {}
			for j = 1, components do
				unmapped[j] = data[i + j]
			end
			local mapped = fn(unmapped)
			for j = 1, components do
				data[i + j] = mapped[j]
			end
		end
	
		return self
	end

	--- Transform the data for `attribute_name` using the transform provided.
	--- @param attribute_name v3d.AttributeName Name of the numeric, 3 component vertex attribute to transform.
	--- @param transform v3d.Transform Transformation to apply.
	--- @param translate boolean | nil Whether vertices should be translated. Defaults to true unless a 4-component attribute is given, in which case vertices are translated if the 4th component is equal to 1.
	--- @return v3d.GeometryBuilder self
	function v3d.GeometryBuilder:transform(attribute_name, transform, translate)
		local attr_components = self.format:get_attribute(attribute_name).components
		local tr_fn = transform.transform
	
		if translate == nil and attr_components ~= 4 then
			translate = true
		end
	
		local data = self.attribute_data[attribute_name]
		local vertex_data = {}
	
		for i = 1, #data, attr_components do
			local translate_this = translate == nil and data[i + 3] == 1 or translate or false
			vertex_data[1] = data[i]
			vertex_data[2] = data[i + 1]
			vertex_data[3] = data[i + 2]
			local result = tr_fn(transform, vertex_data, translate_this)
			data[i] = result[1]
			data[i + 1] = result[2]
			data[i + 2] = result[3]
		end
	
		return self
	end

	--- Copy the data from `other` into this geometry builder. The format of the
	--- other builder and this must be identical, and only data that is part of the
	--- format will be copied.
	--- @param other v3d.GeometryBuilder Geometry builder to copy data from.
	--- @return v3d.GeometryBuilder self
	function v3d.GeometryBuilder:insert(other)
		for i = 1, #self.format.attributes do
			local attr = self.format.attributes[i]
			local self_data = self.attribute_data[attr.name]
			local other_data = other.attribute_data[attr.name]
			local offset = #self_data
	
			for j = 1, #other_data do
				self_data[j + offset] = other_data[j]
			end
		end
	
		self.vertices = self.vertices + other.vertices
		self.faces = self.faces + other.faces
	
		return self
	end

	--- Change the format of this geometry builder to `format`. There are no
	--- requirements on the `format` provided, and this function can be called as
	--- many times as necessary.
	---
	--- Note, the format of a geometry builder affects how geometry is constructed
	--- when using [[@v3d.GeometryBuilder.build]], as well as other functions.
	--- @param format v3d.Format Any format to change to.
	--- @return v3d.GeometryBuilder self
	function v3d.GeometryBuilder:cast(format)
		self.format = format
		return self
	end

	--- Construct a [[@v3d.Geometry]] instance using the data set in this builder.
	--- The resultant [[@v3d.Geometry]] will have the same format as this builder;
	--- consider using [[@v3d.GeometryBuilder.cast]] to change formats if necessary.
	--- @param label string | nil Optional label for the constructed [[@v3d.Geometry]] instance.
	--- @return v3d.Geometry
	--- @nodiscard
	function v3d.GeometryBuilder:build(label)
		local geometry = {}
		local format = self.format

		geometry.format = format
		geometry.vertices = 0
		geometry.faces = 0

		for k, v in pairs(v3d.Geometry) do
			geometry[k] = v
		end

		for i = 1, #format.attributes do
			local attr = format.attributes[i]
			local data = self.attribute_data[attr.name]

			if attr.type == 'vertex' then
				geometry.vertices = #data / attr.components
			else
				geometry.faces = #data / attr.components
			end
		end

		geometry.vertex_offset = format.face_stride * geometry.faces

		for i = 1, #format.attributes do
			local attr = format.attributes[i]
			local data = self.attribute_data[attr.name]
			local base_offset = attr.offset
			local stride = 0
			local count = 0

			if attr.type == 'vertex' then
				base_offset = base_offset + geometry.vertex_offset
				stride = format.vertex_stride
				count = geometry.vertices
			else
				stride = format.face_stride
				count = geometry.faces
			end

			for j = 0, count - 1 do
				local this_offset = base_offset + stride * j
				local data_offset = attr.components * j

				for k = 1, attr.components do
					geometry[this_offset + k] = data[data_offset + k]
				end
			end
		end

		return geometry
	end
end

--------------------------------------------------------------------------------
--[[ v3d.Geometry ]]------------------------------------------------------------
--------------------------------------------------------------------------------

do
	--- [[@v3d.Geometry]] stores the data for shapes and triangles in an optimised
	--- format determined by its `format`. Data is stored as a contiguous array of
	--- unpacked attribute components. [[@v3d.Pipeline]]s are then specifically
	--- compiled to draw geometry of a specific format as quickly as possible.
	---
	--- Use [[@v3d.GeometryBuilder.build]] to create a geometry instance.
	--- @class v3d.Geometry
	--- [[@v3d.Format]] of this geometry, which defines the format data is stored in.
	--- @field format v3d.Format
	--- Number of vertices contained within this geometry.
	--- @field vertices integer
	--- Number of faces contained within this geometry.
	--- @field faces integer
	--- Offset of the first vertex data. An offset of `0` would mean the first
	--- vertex starts from index `1`.
	--- @field vertex_offset integer
	v3d.Geometry = {}

	--- Convert this geometry back into a builder so it can be modified or
	--- transformed.
	--- @return v3d.GeometryBuilder
	function v3d.Geometry:to_builder()
		local gb = v3d.create_geometry_builder(self.format)

		-- TODO
		v3d.internal_error 'NYI: v3d.Geometry:to_builder()'

		return gb
	end
end

--------------------------------------------------------------------------------
--[[ Constructors ]]------------------------------------------------------------
--------------------------------------------------------------------------------

do
	--- Create an empty [[@v3d.Format]].
	--- @return v3d.Format
	--- @nodiscard
	function v3d.create_format()
		local format = {}

		format.attributes = {}
		format.attribute_lookup = {}
		format.vertex_stride = 0
		format.face_stride = 0

		for k, v in pairs(v3d.Format) do
			format[k] = v
		end

		return format
	end

	--- Create an empty [[@v3d.GeometryBuilder]] with the given format.
	--- @param format v3d.Format Initial format, which can be changed with [[@v3d.GeometryBuilder.cast]].
	--- @return v3d.GeometryBuilder
	--- @nodiscard
	function v3d.create_geometry_builder(format)
		local gb = {}

		gb.format = format
		gb.attribute_data = {}

		for k, v in pairs(v3d.GeometryBuilder) do
			gb[k] = v
		end

		return gb
	end
end
