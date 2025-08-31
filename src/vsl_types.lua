
local vsl_types = {}

--- @class TypeNil
--- @field type_kind "nil"

--- @class TypeBoolean
--- @field type_kind "boolean"

--- @class TypeInteger
--- @field type_kind "integer"

--- @class TypeNumber
--- @field type_kind "number"

--- @class TypeString
--- @field type_kind "string"

--- @class TypeDynamic
--- @field type_kind "dynamic"

--- @class TypeParameter
--- @field type_kind "type_parameter"
--- @field type_parameter_name string

--- @class TypeStruct
--- @field type_kind "struct"
--- @field struct_name_hint string?
--- @field struct_fields TypeStructField[]

--- @class TypeArray
--- @field type_kind "array"
--- @field array_element ValueType
--- @field array_size integer

--- @class TypeBuffer
--- @field type_kind "buffer"
--- @field buffer_element ValueType

--- @class TypeRef
--- @field type_kind "ref"
--- @field ref_element ValueType

--- @class TypeStructField
--- @field name string | integer
--- @field offset number
--- @field type ValueType

--- @type TypeNil
vsl_types.NIL_TYPE = { type_kind = "nil" }

--- @type TypeBoolean
vsl_types.BOOLEAN_TYPE = { type_kind = "boolean" }

--- @type TypeInteger
vsl_types.INTEGER_TYPE = { type_kind = "integer" }

--- @type TypeNumber
vsl_types.NUMBER_TYPE = { type_kind = "number" }

--- @type TypeString
vsl_types.STRING_TYPE = { type_kind = "string" }

--- @type TypeDynamic
vsl_types.DYNAMIC_TYPE = { type_kind = "dynamic" }

--- @type ConstantValueRef
vsl_types.NIL = { value_kind = "constant", constant_value = "nil", constant_type = vsl_types.NIL_TYPE }

--- @param type_kind "nil" | "boolean" | "integer" | "number" | "string"
function vsl_types.from_primitive_type(type_kind)
	return { type_kind = type_kind }
end

--- @param name string
--- @return TypeParameter
function vsl_types.type_parameter(name)
	return { type_kind = "type_parameter", type_parameter_name = name }
end

--- @param fields TypeStructField[]
--- @param name_hint string?
function vsl_types.struct_type(fields, name_hint)
	return { type_kind = "struct", struct_name_hint = name_hint, struct_fields = fields }
end

--- @param element_type ValueType
--- @param size integer
--- @return TypeArray
function vsl_types.array_type(element_type, size)
	return { type_kind = "array", array_element = element_type, array_size = size }
end

--- @param element_type ValueType
--- @return TypeBuffer
function vsl_types.buffer_type(element_type)
	return { type_kind = "buffer", buffer_element = element_type }
end

--- @param element_type ValueType
--- @return TypeRef
function vsl_types.ref_type(element_type)
	return { type_kind = "ref", ref_element = element_type }
end

--- @param type ValueType
--- @return string
function vsl_types.type_to_string(type)
	if type.type_kind == "nil" or type.type_kind == "boolean" or type.type_kind == "integer" or type.type_kind == "number" or type.type_kind == "string" or type.type_kind == "dynamic" then
		return type.type_kind
	elseif type.type_kind == "type_parameter" then
		return "<" .. type.type_parameter_name .. ">"
	elseif type.type_kind == "struct" then
		return type.struct_name_hint or "<struct>"
	elseif type.type_kind == "array" then
		return "array<" .. vsl_types.type_to_string(type.array_element) .. ", " .. type.array_size .. ">"
	elseif type.type_kind == "buffer" then
		return "buffer<" .. vsl_types.type_to_string(type.buffer_element) .. ">"
	elseif type.type_kind == "ref" then
		return "ref<" .. vsl_types.type_to_string(type.ref_element) .. ">"
	else
		error("unhandled type kind: " .. tostring(type.type_kind))
	end
end

--- @param src_type ValueType
--- @param dst_type ValueType
--- @return boolean
function vsl_types.is_type_assignable(src_type, dst_type)
	if src_type.type_kind == "integer" and dst_type.type_kind == "number" then
		return true
	elseif src_type.type_kind ~= dst_type.type_kind then
		return false
	end
	if src_type.type_kind == "type_parameter" then
		return src_type.type_parameter_name == dst_type.type_parameter_name
	elseif src_type.type_kind == "struct" then
		return true -- TODO
	elseif src_type.type_kind == "array" then
		return src_type.array_size == dst_type.array_size and vsl_types.is_type_assignable(src_type.array_element, dst_type.array_element)
	elseif src_type.type_kind == "buffer" then
		return vsl_types.is_type_assignable(src_type.buffer_element, dst_type.buffer_element)
	elseif src_type.type_kind == "ref" then
		return vsl_types.is_type_assignable(src_type.ref_element, dst_type.ref_element)
	else
		return true
	end
end

--- @param type ValueType
--- @return integer
function vsl_types.type_flattened_element_count(type)
	if type.type_kind == "struct" then
		local count = 0
		for _, field in ipairs(type.struct_fields) do
			count = count + vsl_types.type_flattened_element_count(field.type)
		end
		return count
	elseif type.type_kind == "array" then
		return type.array_size * vsl_types.type_flattened_element_count(type.array_element)
	elseif type.type_kind == "type_parameter" then
		error("cannot get flattened element count of a type parameter")
	else
		return 1
	end
end

return vsl_types
