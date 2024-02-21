
local v3d = require 'v3d'

local function _eq(a, b)
	if type(a) ~= type(b) then
		return false
	end
	if type(a) == 'table' then
		if #a ~= #b then
			return false
		end
		for i = 1, #a do
			if not _eq(a[i], b[i]) then
				return false
			end
		end
		for k, v in pairs(a) do
			if not _eq(b[k], v) then
				return false
			end
		end
		for k, v in pairs(b) do
			if not _eq(a[k], v) then
				return false
			end
		end
		return true
	end
	return a == b
end

--------------------------------------------------------------------------------
-- Method generation -----------------------------------------------------------
do -----------------------------------------------------------------------------

	v3d.enter_debug_region 'Method generation'

	local instance1 = v3d.integer()
	local instance2 = v3d.create_image(instance1, 1, 1, 1)

	--- @diagnostic disable: undefined-field
	assert(instance1:is_compatible_with(v3d.integer()))
	assert(instance1:n_tuple(3):is_compatible_with(v3d.n_tuple(v3d.integer(), 3)))

	assert(instance2:copy())
	--- @diagnostic enable: undefined-field

	v3d.exit_debug_region 'Method generation'

end ----------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Metamethod generation -------------------------------------------------------
do -----------------------------------------------------------------------------
	assert(v3d.format_is_compatible_with(v3d.integer() * 3, v3d.n_tuple(v3d.integer(), 3)))
	assert(v3d.integer() == v3d.integer())
end ----------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Formats ---------------------------------------------------------------------
do -----------------------------------------------------------------------------

local tuple_fields_1 = {
	v3d.string(),
	v3d.number(),
}

local tuple_fields_2 = {
	v3d.integer(),
	v3d.tuple {
		v3d.character(),
		v3d.boolean(),
	},
}

local struct_fields_1 = {
	x = v3d.number(),
	y = v3d.number(),
}

local struct_fields_2 = {
	name = v3d.string(),
	nested = v3d.tuple {
		v3d.character(),
		v3d.boolean(),
	},
}

local ordered_struct_fields_1 = {
	{ name = 'x', format = v3d.number() },
	{ name = 'y', format = v3d.number() },
}

local ordered_struct_fields_2 = {
	{ name = 'name', format = v3d.string() },
	{ name = 'nested', format = v3d.tuple {
		v3d.character(),
		v3d.boolean(),
	} },
}

-- Test values of the correct type are seen as instances of that type.
assert(v3d.format_is_instance(v3d.boolean(), true))
assert(v3d.format_is_instance(v3d.integer(), 1))
assert(v3d.format_is_instance(v3d.uinteger(), 1))
assert(v3d.format_is_instance(v3d.number(), 1.5))
assert(v3d.format_is_instance(v3d.character(), 'a'))
assert(v3d.format_is_instance(v3d.string(), 'abc'))
assert(v3d.format_is_instance(v3d.tuple(tuple_fields_1), { 'abc', 1.5 }))
assert(v3d.format_is_instance(v3d.tuple(tuple_fields_1), { 'abc', 1.5, 'ignored' }))
assert(v3d.format_is_instance(v3d.tuple(tuple_fields_2), { 1, { 'a', true } }))
assert(v3d.format_is_instance(v3d.tuple(tuple_fields_2), { 1, { 'a', true, 'ignored' }, 'ignored' }))
assert(v3d.format_is_instance(v3d.n_tuple(v3d.integer(), 3), { 1, 2, 3 }))
assert(v3d.format_is_instance(v3d.struct(struct_fields_1), { x = 1, y = 2 }))
assert(v3d.format_is_instance(v3d.struct(struct_fields_2), { name = 'abc', nested = { 'a', true } }))
assert(v3d.format_is_instance(v3d.ordered_struct(ordered_struct_fields_1), { x = 1, y = 2 }))
assert(v3d.format_is_instance(v3d.ordered_struct(ordered_struct_fields_2), { name = 'abc', nested = { 'a', true } }))

-- Test values of the wrong type are not seen as instances of that type.
assert(not v3d.format_is_instance(v3d.boolean(), 1))
assert(not v3d.format_is_instance(v3d.boolean(), 'true'))
assert(not v3d.format_is_instance(v3d.integer(), 1.5))
assert(not v3d.format_is_instance(v3d.integer(), '1'))
assert(not v3d.format_is_instance(v3d.uinteger(), 1.5))
assert(not v3d.format_is_instance(v3d.uinteger(), -1))
assert(not v3d.format_is_instance(v3d.number(), '1.5'))
assert(not v3d.format_is_instance(v3d.character(), 1))
assert(not v3d.format_is_instance(v3d.character(), 'ab'))
assert(not v3d.format_is_instance(v3d.string(), 1))
assert(not v3d.format_is_instance(v3d.string(), { 'a', 'b' }))
assert(not v3d.format_is_instance(v3d.tuple(tuple_fields_1), { 'abc', 'def' }))
assert(not v3d.format_is_instance(v3d.tuple(tuple_fields_1), { 'abc' }))
assert(not v3d.format_is_instance(v3d.tuple(tuple_fields_2), { 1, { 'a', 1 } }))
assert(not v3d.format_is_instance(v3d.tuple(tuple_fields_2), { 1, 'a', 1 }))
assert(not v3d.format_is_instance(v3d.n_tuple(v3d.integer(), 3), { 1, 2 }))
assert(not v3d.format_is_instance(v3d.n_tuple(v3d.integer(), 3), { 1, 2, 3.5 }))
assert(not v3d.format_is_instance(v3d.struct(struct_fields_1), { x = 1, y = false, z = 3 }))
assert(not v3d.format_is_instance(v3d.struct(struct_fields_1), { x = 1 }))
assert(not v3d.format_is_instance(v3d.struct(struct_fields_2), { name = 'abc', nested = { 'a', 1 } }))
assert(not v3d.format_is_instance(v3d.struct(struct_fields_2), { name = 'abc' }))
assert(not v3d.format_is_instance(v3d.ordered_struct(ordered_struct_fields_1), { x = 1, y = false, z = 3 }))
assert(not v3d.format_is_instance(v3d.ordered_struct(ordered_struct_fields_1), { x = 1 }))
assert(not v3d.format_is_instance(v3d.ordered_struct(ordered_struct_fields_2), { name = 'abc', nested = { 'a', 1 } }))
assert(not v3d.format_is_instance(v3d.ordered_struct(ordered_struct_fields_2), { name = 'abc' }))

-- Test everything equals itself
assert(v3d.format_equals(v3d.boolean(), v3d.boolean()))
assert(v3d.format_equals(v3d.integer(), v3d.integer()))
assert(v3d.format_equals(v3d.uinteger(), v3d.uinteger()))
assert(v3d.format_equals(v3d.number(), v3d.number()))
assert(v3d.format_equals(v3d.character(), v3d.character()))
assert(v3d.format_equals(v3d.string(), v3d.string()))
assert(v3d.format_equals(v3d.tuple(tuple_fields_1), v3d.tuple(tuple_fields_1)))
assert(v3d.format_equals(v3d.tuple(tuple_fields_2), v3d.tuple(tuple_fields_2)))
assert(v3d.format_equals(v3d.n_tuple(v3d.integer(), 3), v3d.n_tuple(v3d.integer(), 3)))
assert(v3d.format_equals(v3d.struct(struct_fields_1), v3d.struct(struct_fields_1)))
assert(v3d.format_equals(v3d.struct(struct_fields_2), v3d.struct(struct_fields_2)))
assert(v3d.format_equals(v3d.ordered_struct(ordered_struct_fields_1), v3d.ordered_struct(ordered_struct_fields_1)))
assert(v3d.format_equals(v3d.ordered_struct(ordered_struct_fields_2), v3d.ordered_struct(ordered_struct_fields_2)))

-- Test tuples of different field types are not equal.
assert(not v3d.format_equals(v3d.tuple { v3d.integer(), v3d.character() }, v3d.tuple { v3d.number(), v3d.string() }))
assert(not v3d.format_equals(v3d.tuple { v3d.integer(), v3d.character() }, v3d.tuple { v3d.string(), v3d.number() }))

-- Test n_tuples of different sizes are not equal.
assert(not v3d.format_equals(v3d.n_tuple(v3d.integer(), 3), v3d.n_tuple(v3d.integer(), 4)))

-- Test structs of different field types are not equal.
assert(not v3d.format_equals(v3d.struct { x = v3d.integer(), y = v3d.character() }, v3d.struct { x = v3d.number(), y = v3d.string() }))

-- Test structs with different fields are not equal.
assert(not v3d.format_equals(v3d.struct { x = v3d.integer(), y = v3d.character() }, v3d.struct { x = v3d.integer(), z = v3d.character() }))
assert(not v3d.format_equals(v3d.struct { x = v3d.integer(), y = v3d.character() }, v3d.struct { x = v3d.integer() }))

-- Test ordered structs of different field types are not equal.
assert(not v3d.format_equals(v3d.ordered_struct { { name = 'x', format = v3d.integer() }, { name = 'y', format = v3d.character() } }, v3d.ordered_struct { { name = 'x', format = v3d.number() }, { name = 'y', format = v3d.string() } }))
assert(not v3d.format_equals(v3d.ordered_struct { { name = 'x', format = v3d.integer() }, { name = 'y', format = v3d.character() } }, v3d.ordered_struct { { name = 'x', format = v3d.integer() }, { name = 'z', format = v3d.character() } }))
assert(not v3d.format_equals(v3d.ordered_struct { { name = 'x', format = v3d.integer() }, { name = 'y', format = v3d.character() } }, v3d.ordered_struct { { name = 'x', format = v3d.integer() } }))

-- Test ordered structs with different fields are not equal.
assert(not v3d.format_equals(v3d.ordered_struct { { name = 'x', format = v3d.integer() }, { name = 'y', format = v3d.character() } }, v3d.ordered_struct { { name = 'x', format = v3d.integer() }, { name = 'z', format = v3d.character() } }))
assert(not v3d.format_equals(v3d.ordered_struct { { name = 'x', format = v3d.integer() }, { name = 'y', format = v3d.character() } }, v3d.ordered_struct { { name = 'x', format = v3d.integer() } }))
assert(not v3d.format_equals(v3d.ordered_struct { { name = 'x', format = v3d.integer() } }, v3d.ordered_struct { { name = 'x', format = v3d.integer() }, { name = 'y', format = v3d.character() } }))

-- Test everything is compatible with itself.
assert(v3d.format_is_compatible_with(v3d.boolean(), v3d.boolean()))
assert(v3d.format_is_compatible_with(v3d.integer(), v3d.integer()))
assert(v3d.format_is_compatible_with(v3d.uinteger(), v3d.uinteger()))
assert(v3d.format_is_compatible_with(v3d.number(), v3d.number()))
assert(v3d.format_is_compatible_with(v3d.character(), v3d.character()))
assert(v3d.format_is_compatible_with(v3d.string(), v3d.string()))
assert(v3d.format_is_compatible_with(v3d.tuple(tuple_fields_1), v3d.tuple(tuple_fields_1)))
assert(v3d.format_is_compatible_with(v3d.tuple(tuple_fields_2), v3d.tuple(tuple_fields_2)))
assert(v3d.format_is_compatible_with(v3d.n_tuple(v3d.integer(), 3), v3d.n_tuple(v3d.integer(), 3)))
assert(v3d.format_is_compatible_with(v3d.struct(struct_fields_1), v3d.struct(struct_fields_1)))
assert(v3d.format_is_compatible_with(v3d.struct(struct_fields_2), v3d.struct(struct_fields_2)))
assert(v3d.format_is_compatible_with(v3d.ordered_struct(ordered_struct_fields_1), v3d.ordered_struct(ordered_struct_fields_1)))
assert(v3d.format_is_compatible_with(v3d.ordered_struct(ordered_struct_fields_2), v3d.ordered_struct(ordered_struct_fields_2)))

-- Test primitive type non-identity compatibility rules
assert(v3d.format_is_compatible_with(v3d.integer(), v3d.number()))
assert(v3d.format_is_compatible_with(v3d.uinteger(), v3d.integer()))
assert(v3d.format_is_compatible_with(v3d.uinteger(), v3d.number()))
assert(v3d.format_is_compatible_with(v3d.character(), v3d.string()))

-- Test tuples of different field types are compatible when the field types are compatible.
assert(v3d.format_is_compatible_with(v3d.tuple { v3d.integer(), v3d.character() }, v3d.tuple { v3d.number(), v3d.string() }))

-- Test n_tuples are bi-compatible with similar ordinary tuples.
assert(v3d.format_is_compatible_with(v3d.tuple { v3d.integer(), v3d.integer(), v3d.integer() }, v3d.n_tuple(v3d.integer(), 3)))
assert(v3d.format_is_compatible_with(v3d.n_tuple(v3d.integer(), 3), v3d.tuple { v3d.integer(), v3d.integer(), v3d.integer() }))

-- Test structs of different field types are compatible when the field types are compatible.
assert(v3d.format_is_compatible_with(v3d.struct { x = v3d.integer(), y = v3d.character() }, v3d.struct { x = v3d.number(), y = v3d.string() }))

-- Test ordered structs of different field types are compatible when the field types are compatible.
assert(v3d.format_is_compatible_with(v3d.ordered_struct { { name = 'x', format = v3d.integer() }, { name = 'y', format = v3d.character() } }, v3d.ordered_struct { { name = 'x', format = v3d.number() }, { name = 'y', format = v3d.string() } }))

-- Test that structs and ordered structs are compatible with each other.
assert(v3d.format_is_compatible_with(v3d.struct(struct_fields_1), v3d.ordered_struct(ordered_struct_fields_1)))
assert(v3d.format_is_compatible_with(v3d.struct(struct_fields_2), v3d.ordered_struct(ordered_struct_fields_2)))
assert(v3d.format_is_compatible_with(v3d.ordered_struct(ordered_struct_fields_1), v3d.struct(struct_fields_1)))
assert(v3d.format_is_compatible_with(v3d.ordered_struct(ordered_struct_fields_2), v3d.struct(struct_fields_2)))

-- Test primitive type non-compatibility rules
assert(not v3d.format_is_compatible_with(v3d.integer(), v3d.uinteger()))
assert(not v3d.format_is_compatible_with(v3d.integer(), v3d.character()))
assert(not v3d.format_is_compatible_with(v3d.integer(), v3d.string()))

assert(not v3d.format_is_compatible_with(v3d.uinteger(), v3d.character()))
assert(not v3d.format_is_compatible_with(v3d.uinteger(), v3d.string()))

assert(not v3d.format_is_compatible_with(v3d.number(), v3d.integer()))
assert(not v3d.format_is_compatible_with(v3d.number(), v3d.uinteger()))
assert(not v3d.format_is_compatible_with(v3d.number(), v3d.character()))
assert(not v3d.format_is_compatible_with(v3d.number(), v3d.string()))

assert(not v3d.format_is_compatible_with(v3d.character(), v3d.integer()))
assert(not v3d.format_is_compatible_with(v3d.character(), v3d.uinteger()))
assert(not v3d.format_is_compatible_with(v3d.character(), v3d.number()))

assert(not v3d.format_is_compatible_with(v3d.string(), v3d.integer()))
assert(not v3d.format_is_compatible_with(v3d.string(), v3d.uinteger()))
assert(not v3d.format_is_compatible_with(v3d.string(), v3d.number()))
assert(not v3d.format_is_compatible_with(v3d.string(), v3d.character()))

-- Test that tuples of different field types are not compatible when the field types are not compatible.
assert(not v3d.format_is_compatible_with(v3d.tuple { v3d.integer(), v3d.character() }, v3d.tuple { v3d.string(), v3d.number() }))

-- Test that tuples of different sizes are not compatible.
assert(not v3d.format_is_compatible_with(v3d.tuple { v3d.integer(), v3d.character() }, v3d.tuple { v3d.integer(), v3d.character(), v3d.integer() }))
assert(not v3d.format_is_compatible_with(v3d.tuple { v3d.integer(), v3d.character(), v3d.integer() }, v3d.tuple { v3d.integer(), v3d.character() }))

-- Test that tuples with differently ordered fields are not compatible.
assert(not v3d.format_is_compatible_with(v3d.tuple { v3d.integer(), v3d.character() }, v3d.tuple { v3d.character(), v3d.integer() }))

-- Test that n_tuples of different field types are not compatible when the field types are not compatible.
assert(not v3d.format_is_compatible_with(v3d.n_tuple(v3d.integer(), 3), v3d.n_tuple(v3d.string(), 3)))

-- Test that n_tuples of different sizes are not compatible.
assert(not v3d.format_is_compatible_with(v3d.n_tuple(v3d.integer(), 3), v3d.n_tuple(v3d.integer(), 4)))
assert(not v3d.format_is_compatible_with(v3d.n_tuple(v3d.integer(), 4), v3d.n_tuple(v3d.integer(), 3)))

-- Test that structs of different field types are not compatible when the field types are not compatible.
assert(not v3d.format_is_compatible_with(v3d.struct { x = v3d.integer(), y = v3d.character() }, v3d.struct { x = v3d.string(), y = v3d.number() }))

-- Test that structs with different fields are not compatible.
assert(not v3d.format_is_compatible_with(v3d.struct { x = v3d.integer(), y = v3d.character() }, v3d.struct { x = v3d.integer(), z = v3d.character() }))
assert(not v3d.format_is_compatible_with(v3d.struct { x = v3d.integer(), y = v3d.character() }, v3d.struct { x = v3d.integer() }))
assert(not v3d.format_is_compatible_with(v3d.struct { x = v3d.integer() }, v3d.struct { x = v3d.integer(), y = v3d.character() }))

-- Test that ordered structs of different field types are not compatible when the field types are not compatible.
assert(not v3d.format_is_compatible_with(v3d.ordered_struct { { name = 'x', format = v3d.integer() }, { name = 'y', format = v3d.character() } }, v3d.ordered_struct { { name = 'x', format = v3d.string() }, { name = 'y', format = v3d.number() } }))

-- Test that ordered structs with different fields are not compatible.
assert(not v3d.format_is_compatible_with(v3d.ordered_struct { { name = 'x', format = v3d.integer() }, { name = 'y', format = v3d.character() } }, v3d.ordered_struct { { name = 'x', format = v3d.integer() }, { name = 'z', format = v3d.character() } }))
assert(not v3d.format_is_compatible_with(v3d.ordered_struct { { name = 'x', format = v3d.integer() }, { name = 'y', format = v3d.character() } }, v3d.ordered_struct { { name = 'x', format = v3d.integer() } }))
assert(not v3d.format_is_compatible_with(v3d.ordered_struct { { name = 'x', format = v3d.integer() } }, v3d.ordered_struct { { name = 'x', format = v3d.integer() }, { name = 'y', format = v3d.character() } }))

-- Test that ordered structs with differently ordered fields are not compatible.
assert(not v3d.format_is_compatible_with(v3d.ordered_struct { { name = 'x', format = v3d.integer() }, { name = 'y', format = v3d.character() } }, v3d.ordered_struct { { name = 'y', format = v3d.character() }, { name = 'x', format = v3d.integer() } }))

-- Test that struct order is deterministic and alphabetical.
assert(v3d.format_is_compatible_with(v3d.struct { x = v3d.integer(), y = v3d.character() }, v3d.struct { y = v3d.character(), x = v3d.integer() }))
assert(v3d.format_is_compatible_with(v3d.struct { x = v3d.integer(), y = v3d.character() }, v3d.ordered_struct { { name = 'x', format = v3d.integer() }, { name = 'y', format = v3d.character() } }))
assert(not v3d.format_is_compatible_with(v3d.struct { x = v3d.integer(), y = v3d.character() }, v3d.ordered_struct { { name = 'y', format = v3d.character() }, { name = 'x', format = v3d.integer() } }))

-- Test that buffering a primitive type returns the same type.
assert(#v3d.format_buffer_into(v3d.boolean(), true) == 1)
assert(v3d.format_buffer_into(v3d.boolean(), true)[1] == true)
assert(#v3d.format_buffer_into(v3d.integer(), 31) == 1)
assert(v3d.format_buffer_into(v3d.integer(), 31)[1] == 31)
assert(#v3d.format_buffer_into(v3d.uinteger(), 31) == 1)
assert(v3d.format_buffer_into(v3d.uinteger(), 31)[1] == 31)
assert(#v3d.format_buffer_into(v3d.number(), 31.5) == 1)
assert(v3d.format_buffer_into(v3d.number(), 31.5)[1] == 31.5)
assert(#v3d.format_buffer_into(v3d.character(), 'a') == 1)
assert(v3d.format_buffer_into(v3d.character(), 'a')[1] == 'a')
assert(#v3d.format_buffer_into(v3d.string(), 'abc') == 1)
assert(v3d.format_buffer_into(v3d.string(), 'abc')[1] == 'abc')

local data

-- Test that buffering a primitive with a buffer and offset returns the same
-- buffer with the value written to the correct index.
data = { 'ignored' }
assert(v3d.format_buffer_into(v3d.boolean(), true, data, 1) == data)
assert(v3d.format_buffer_into(v3d.boolean(), true, data, 1)[2] == true)
assert(v3d.format_buffer_into(v3d.integer(), 31, data, 1) == data)
assert(v3d.format_buffer_into(v3d.integer(), 31, data, 1)[2] == 31)
assert(v3d.format_buffer_into(v3d.uinteger(), 31, data, 1) == data)
assert(v3d.format_buffer_into(v3d.uinteger(), 31, data, 1)[2] == 31)
assert(v3d.format_buffer_into(v3d.number(), 31.5, data, 1) == data)
assert(v3d.format_buffer_into(v3d.number(), 31.5, data, 1)[2] == 31.5)
assert(v3d.format_buffer_into(v3d.character(), 'a', data, 1) == data)
assert(v3d.format_buffer_into(v3d.character(), 'a', data, 1)[2] == 'a')
assert(v3d.format_buffer_into(v3d.string(), 'abc', data, 1) == data)
assert(v3d.format_buffer_into(v3d.string(), 'abc', data, 1)[2] == 'abc')

-- Test that buffering a tuple type returns a valid buffer
assert(#v3d.format_buffer_into(v3d.tuple(tuple_fields_1), { 'abc', 123 }) == 2)
assert(_eq(v3d.format_buffer_into(v3d.tuple(tuple_fields_1), { 'abc', 123 }), { 'abc', 123 }))
assert(#v3d.format_buffer_into(v3d.tuple(tuple_fields_2), { 123, { 'a', false } }) == 3)
assert(_eq(v3d.format_buffer_into(v3d.tuple(tuple_fields_2), { 123, { 'a', false } }), { 123, 'a', false }))

-- Test that buffering a tuple with a buffer and offset returns the same buffer
-- with the values written to the correct indices.
data = { 'ignored' }
assert(v3d.format_buffer_into(v3d.tuple(tuple_fields_1), { 'abc', 123 }, data, 1) == data)
assert(_eq(v3d.format_buffer_into(v3d.tuple(tuple_fields_1), { 'abc', 123 }, data, 1), { 'ignored', 'abc', 123 }))
assert(v3d.format_buffer_into(v3d.tuple(tuple_fields_2), { 123, { 'a', false } }, data, 1) == data)
assert(_eq(v3d.format_buffer_into(v3d.tuple(tuple_fields_2), { 123, { 'a', false } }, data, 1), { 'ignored', 123, 'a', false }))

-- Test that buffering an n_tuple type returns a valid buffer
assert(#v3d.format_buffer_into(v3d.n_tuple(v3d.integer(), 3), { 1, 2, 3 }) == 3)
assert(_eq(v3d.format_buffer_into(v3d.n_tuple(v3d.integer(), 3), { 1, 2, 3 }), { 1, 2, 3 }))

-- Test that buffering an n_tuple with a buffer and offset returns the same
-- buffer with the values written to the correct indices.
data = { 'ignored' }
assert(v3d.format_buffer_into(v3d.n_tuple(v3d.integer(), 3), { 1, 2, 3 }, data, 1) == data)
assert(_eq(v3d.format_buffer_into(v3d.n_tuple(v3d.integer(), 3), { 1, 2, 3 }, data, 1), { 'ignored', 1, 2, 3 }))

-- Test that buffering a struct type returns a valid buffer
assert(#v3d.format_buffer_into(v3d.struct(struct_fields_1), { x = 1, y = 2 }) == 2)
assert(_eq(v3d.format_buffer_into(v3d.struct(struct_fields_1), { x = 1, y = 2 }), { 1, 2 }))
assert(#v3d.format_buffer_into(v3d.struct(struct_fields_2), { name = 'abc', nested = { 'a', false } }) == 3)
assert(_eq(v3d.format_buffer_into(v3d.struct(struct_fields_2), { name = 'abc', nested = { 'a', false } }), { 'abc', 'a', false }))
assert(#v3d.format_buffer_into(v3d.struct(struct_fields_2), { nested = { 'a', false }, name = 'abc' }) == 3)
assert(_eq(v3d.format_buffer_into(v3d.struct(struct_fields_2), { nested = { 'a', false }, name = 'abc' }), { 'abc', 'a', false }))

data = { 'ignored' }
-- Test that buffering a struct type with a buffer and offset returns the same
-- buffer with the values written to the correct indices.
assert(v3d.format_buffer_into(v3d.struct(struct_fields_1), { x = 1, y = 2 }, data, 1) == data)
assert(_eq(v3d.format_buffer_into(v3d.struct(struct_fields_1), { x = 1, y = 2 }, data, 1), { 'ignored', 1, 2 }))

-- Test that buffering an ordered_struct type returns a valid buffer
assert(#v3d.format_buffer_into(v3d.ordered_struct(ordered_struct_fields_1), { x = 1, y = 2 }) == 2)
assert(_eq(v3d.format_buffer_into(v3d.ordered_struct(ordered_struct_fields_1), { x = 1, y = 2 }), { 1, 2 }))
assert(#v3d.format_buffer_into(v3d.ordered_struct(ordered_struct_fields_2), { name = 'abc', nested = { 'a', false } }) == 3)
assert(_eq(v3d.format_buffer_into(v3d.ordered_struct(ordered_struct_fields_2), { name = 'abc', nested = { 'a', false } }), { 'abc', 'a', false }))
assert(#v3d.format_buffer_into(v3d.ordered_struct(ordered_struct_fields_2), { nested = { 'a', false }, name = 'abc' }) == 3)
assert(_eq(v3d.format_buffer_into(v3d.ordered_struct(ordered_struct_fields_2), { nested = { 'a', false }, name = 'abc' }), { 'abc', 'a', false }))

-- Test that buffering an ordered_struct type with a buffer and offset returns
-- the same buffer with the values written to the correct indices.
data = { 'ignored' }
assert(v3d.format_buffer_into(v3d.ordered_struct(ordered_struct_fields_1), { x = 1, y = 2 }, data, 1) == data)
assert(_eq(v3d.format_buffer_into(v3d.ordered_struct(ordered_struct_fields_1), { x = 1, y = 2 }, data, 1), { 'ignored', 1, 2 }))
assert(v3d.format_buffer_into(v3d.ordered_struct(ordered_struct_fields_2), { name = 'abc', nested = { 'a', false } }, data, 1) == data)
assert(_eq(v3d.format_buffer_into(v3d.ordered_struct(ordered_struct_fields_2), { name = 'abc', nested = { 'a', false } }, data, 1), { 'ignored', 'abc', 'a', false }))

-- Test that unbuffering a primitive type returns the same value.
assert(v3d.format_unbuffer_from(v3d.boolean(), { true }) == true)
assert(v3d.format_unbuffer_from(v3d.integer(), { 31 }) == 31)
assert(v3d.format_unbuffer_from(v3d.uinteger(), { 31 }) == 31)
assert(v3d.format_unbuffer_from(v3d.number(), { 31.5 }) == 31.5)
assert(v3d.format_unbuffer_from(v3d.character(), { 'a' }) == 'a')
assert(v3d.format_unbuffer_from(v3d.string(), { 'abc' }) == 'abc')

-- Test that unbuffering a primitive type with an offset returns the same value.
assert(v3d.format_unbuffer_from(v3d.boolean(), { 'ignored', true }, 1) == true)
assert(v3d.format_unbuffer_from(v3d.integer(), { 'ignored', 31 }, 1) == 31)
assert(v3d.format_unbuffer_from(v3d.uinteger(), { 'ignored', 31 }, 1) == 31)
assert(v3d.format_unbuffer_from(v3d.number(), { 'ignored', 31.5 }, 1) == 31.5)
assert(v3d.format_unbuffer_from(v3d.character(), { 'ignored', 'a' }, 1) == 'a')
assert(v3d.format_unbuffer_from(v3d.string(), { 'ignored', 'abc' }, 1) == 'abc')

-- Test that unbuffering a tuple type returns a valid table.
assert(_eq(v3d.format_unbuffer_from(v3d.tuple(tuple_fields_1), { 'abc', 123 }), { 'abc', 123 }))
assert(_eq(v3d.format_unbuffer_from(v3d.tuple(tuple_fields_2), { 123, 'a', 456 }), { 123, { 'a', 456 } }))

-- Test that unbuffering a tuple type with an offset returns a valid table.
assert(_eq(v3d.format_unbuffer_from(v3d.tuple(tuple_fields_1), { 'ignored', 'abc', 123 }, 1), { 'abc', 123 }))
assert(_eq(v3d.format_unbuffer_from(v3d.tuple(tuple_fields_2), { 'ignored', 123, 'a', 456 }, 1), { 123, { 'a', 456 } }))

-- Test that unbuffering an n_tuple type returns a valid table.
assert(_eq(v3d.format_unbuffer_from(v3d.n_tuple(v3d.integer(), 3), { 1, 2, 3 }), { 1, 2, 3 }))

-- Test that unbuffering an n_tuple type with an offset returns a valid table.
assert(_eq(v3d.format_unbuffer_from(v3d.n_tuple(v3d.integer(), 3), { 'ignored', 1, 2, 3 }, 1), { 1, 2, 3 }))

-- Test that unbuffering a struct type returns a valid table.
assert(_eq(v3d.format_unbuffer_from(v3d.struct(struct_fields_1), { 1, 2 }), { x = 1, y = 2 }))
assert(_eq(v3d.format_unbuffer_from(v3d.struct(struct_fields_2), { 'abc', 'a', 123 }), { name = 'abc', nested = { 'a', 123 } }))

-- Test that unbuffering a struct type with an offset returns a valid table.
assert(_eq(v3d.format_unbuffer_from(v3d.struct(struct_fields_1), { 'ignored', 1, 2 }, 1), { x = 1, y = 2 }))
assert(_eq(v3d.format_unbuffer_from(v3d.struct(struct_fields_2), { 'ignored', 'abc', 'a', 123 }, 1), { name = 'abc', nested = { 'a', 123 } }))

-- Test that unbuffering an ordered_struct type returns a valid table.
assert(_eq(v3d.format_unbuffer_from(v3d.ordered_struct(ordered_struct_fields_1), { 1, 2 }), { x = 1, y = 2 }))
assert(_eq(v3d.format_unbuffer_from(v3d.ordered_struct(ordered_struct_fields_2), { 'abc', 'a', 123 }), { name = 'abc', nested = { 'a', 123 } }))

-- Test that unbuffering an ordered_struct type with an offset returns a valid
-- table.
assert(_eq(v3d.format_unbuffer_from(v3d.ordered_struct(ordered_struct_fields_1), { 'ignored', 1, 2 }, 1), { x = 1, y = 2 }))
assert(_eq(v3d.format_unbuffer_from(v3d.ordered_struct(ordered_struct_fields_2), { 'ignored', 'abc', 'a', 123 }, 1), { name = 'abc', nested = { 'a', 123 } }))

-- Test that primitive types have a size of 1.
assert(v3d.format_size(v3d.boolean()) == 1)
assert(v3d.format_size(v3d.integer()) == 1)
assert(v3d.format_size(v3d.uinteger()) == 1)
assert(v3d.format_size(v3d.number()) == 1)
assert(v3d.format_size(v3d.character()) == 1)
assert(v3d.format_size(v3d.string()) == 1)

-- Test that tuple types have a size equal to the sum of the sizes of their
-- fields.
assert(v3d.format_size(v3d.tuple(tuple_fields_1)) == 2)
assert(v3d.format_size(v3d.tuple(tuple_fields_2)) == 3)

-- Test that n_tuple types have a size equal to the size of their field times
-- the number of fields.
assert(v3d.format_size(v3d.n_tuple(v3d.integer(), 3)) == 3)

-- Test that struct types have a size equal to the sum of the sizes of their
-- fields.
assert(v3d.format_size(v3d.struct(struct_fields_1)) == 2)
assert(v3d.format_size(v3d.struct(struct_fields_2)) == 3)

-- Test that ordered_struct types have a size equal to the sum of the sizes of
-- their fields.
assert(v3d.format_size(v3d.ordered_struct(ordered_struct_fields_1)) == 2)
assert(v3d.format_size(v3d.ordered_struct(ordered_struct_fields_2)) == 3)

-- Test the default value of primitive types.
assert(v3d.format_default_value(v3d.boolean()) == false)
assert(v3d.format_default_value(v3d.integer()) == 0)
assert(v3d.format_default_value(v3d.uinteger()) == 0)
assert(v3d.format_default_value(v3d.number()) == 0)
assert(v3d.format_default_value(v3d.character()) == '\0')
assert(v3d.format_default_value(v3d.string()) == '')

-- Test the default value of tuple types.
assert(_eq(v3d.format_default_value(v3d.tuple(tuple_fields_1)), { '', 0 }))
assert(_eq(v3d.format_default_value(v3d.tuple(tuple_fields_2)), { 0, { '\0', false } }))

-- Test the default value of n_tuple types.
assert(_eq(v3d.format_default_value(v3d.n_tuple(v3d.integer(), 3)), { 0, 0, 0 }))

-- Test the default value of struct types.
assert(_eq(v3d.format_default_value(v3d.struct(struct_fields_1)), { x = 0, y = 0 }))
assert(_eq(v3d.format_default_value(v3d.struct(struct_fields_2)), { name = '', nested = { '\0', false } }))

-- Test the default value of ordered_struct types.
assert(_eq(v3d.format_default_value(v3d.ordered_struct(ordered_struct_fields_1)), { x = 0, y = 0 }))
assert(_eq(v3d.format_default_value(v3d.ordered_struct(ordered_struct_fields_2)), { name = '', nested = { '\0', false } }))

-- Test that the multiplication operator works on types.
assert(v3d.format_equals(v3d.integer() * 3, v3d.n_tuple(v3d.integer(), 3)))

-- Test that the equals operator works on types.
assert(v3d.integer() == v3d.integer())
assert(v3d.integer() ~= v3d.string())

end ----------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Images ----------------------------------------------------------------------
do -----------------------------------------------------------------------------

v3d.enter_debug_region 'Images'

-- Test image fields are properly initialised.
local image_format = v3d.struct { a = v3d.integer(), b = v3d.string() }
local image = v3d.create_image(image_format, 2, 3, 4)
assert(image.format == image_format)
assert(image.width == 2)
assert(image.height == 3)
assert(image.depth == 4)

-- Test image contents are default-initialised to the correct value.
assert(#image == 2 * 3 * 4 * 2)
for i = 1, #image do
	assert(image[i] == (i % 2 == 1 and 0 or ''))
end

-- Test image contents are initialised to the correct value when passing a
-- custom value.
local image2 = v3d.create_image(image_format, 2, 3, 4, { a = 31, b = 'abc' })
assert(#image2 == 2 * 3 * 4 * 2)
for i = 1, #image2 do
	assert(image2[i] == (i % 2 == 1 and 31 or 'abc'))
end

-- Test that a copied image is equal to the original.
local image_copy = v3d.image_copy(image)
assert(image_copy.format == image.format)
assert(image_copy.width == image.width)
assert(image_copy.height == image.height)
assert(image_copy.depth == image.depth)
assert(#image_copy == #image)

for i = 1, #image do
	assert(image_copy[i] == image[i])
end

v3d.exit_debug_region 'Images'

end ----------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Image views -----------------------------------------------------------------
do -----------------------------------------------------------------------------

v3d.enter_debug_region 'Image views'

local image_format = v3d.struct { a = v3d.integer(), b = v3d.string() }
local image = v3d.create_image(image_format, 2, 3, 4)
local image_view = v3d.image_view(image)
local sub_image_view = v3d.image_view(image, { x = 1, y = 1, z = 1, width = 1, height = 2, depth = 2 })

-- Test image view filling works with no region.
v3d.image_view_fill(image_view, { a = 31, b = 'abc' })
assert(#image == 2 * 3 * 4 * 2)
for i = 1, #image do
	assert(image[i] == (i % 2 == 1 and 31 or 'abc'))
end

-- Test image view filling returns the same image view.
assert(v3d.image_view_fill(image_view, { a = 31, b = 'abc' }) == image_view)

-- Test image view filling works with a region.
v3d.image_view_fill(sub_image_view, { a = 32, b = 'abcd' })
local index = 1
for z = 1, image.depth do
	for y = 1, image.height do
		for x = 1, image.width do
			for i = 1, v3d.format_size(image.format) do
				local is_updated_pixel = x > 1 and y > 1 and z > 1 and z < 4

				if is_updated_pixel then
					assert(image[index] == (i % 2 == 1 and 32 or 'abcd'))
				else
					assert(image[index] == (i % 2 == 1 and 31 or 'abc'))
				end

				index = index + 1
			end
		end
	end
end

-- Test image get_pixel returns the correct value for in-bounds coordinates.
assert(_eq(v3d.image_view_get_pixel(image_view, 0, 0, 0), { a = 31, b = 'abc' }))
assert(_eq(v3d.image_view_get_pixel(image_view, 1, 2, 2), { a = 32, b = 'abcd' }))

-- Test image view get_pixel returns nil for out-of-bounds coordinates.
assert(v3d.image_view_get_pixel(image_view, -1, 0, 0) == nil)
assert(v3d.image_view_get_pixel(image_view, 0, -1, 0) == nil)
assert(v3d.image_view_get_pixel(image_view, 0, 0, -1) == nil)
assert(v3d.image_view_get_pixel(image_view, image.width, 0, 0) == nil)
assert(v3d.image_view_get_pixel(image_view, 0, image.height, 0) == nil)
assert(v3d.image_view_get_pixel(image_view, 0, 0, image.depth) == nil)

-- Test image set_pixel writes the correct values for in-bounds coordinates.
v3d.image_view_set_pixel(image_view, 0, 0, 0, { a = 33, b = 'abcde' })
assert(image[1] == 33)
assert(image[2] == 'abcde')
v3d.image_view_set_pixel(image_view, 1, 2, 2, { a = 34, b = 'abcdef' })
assert(image[35] == 34)
assert(image[36] == 'abcdef')

-- Test image set_pixel does not error for out-of-bounds coordinates.
v3d.image_view_set_pixel(image_view, -1, 0, 0, { a = 35, b = 'abcdefg' })
v3d.image_view_set_pixel(image_view, 0, -1, 0, { a = 35, b = 'abcdefg' })
v3d.image_view_set_pixel(image_view, 0, 0, -1, { a = 35, b = 'abcdefg' })
v3d.image_view_set_pixel(image_view, image.width, 0, 0, { a = 35, b = 'abcdefg' })
v3d.image_view_set_pixel(image_view, 0, image.height, 0, { a = 35, b = 'abcdefg' })
v3d.image_view_set_pixel(image_view, 0, 0, image.depth, { a = 35, b = 'abcdefg' })

-- Test image view set_pixel returns the same image.
assert(v3d.image_view_set_pixel(image_view, 0, 0, 0, { a = 35, b = 'abcdefg' }) == image_view)

-- Test image view buffer into returns the correct buffer with no buffer or
-- offset.
v3d.image_view_fill(image_view, { a = 31, b = 'abc' })
v3d.image_view_fill(sub_image_view, { a = 32, b = 'abcd' })
local buffer = v3d.image_view_buffer_into(image_view)
assert(#buffer == image.width * image.height * image.depth)

local index = 1
for z = 1, image.depth do
	for y = 1, image.height do
		for x = 1, image.width do
			local is_updated_pixel = x > 1 and y > 1 and z > 1 and z < 4
			assert(_eq(buffer[index], { a = is_updated_pixel and 32 or 31, b = is_updated_pixel and 'abcd' or 'abc' }))
			index = index + 1
		end
	end
end

-- Test image view buffer into returns the correct buffer with a buffer and an
-- offset.
buffer[1] = 'ignored'
assert(v3d.image_view_buffer_into(image_view, buffer, 1) == buffer)
assert(buffer[1] == 'ignored')
local index = 2
for z = 1, image.depth do
	for y = 1, image.height do
		for x = 1, image.width do
			local is_updated_pixel = x > 1 and y > 1 and z > 1 and z < 4
			assert(_eq(buffer[index], { a = is_updated_pixel and 32 or 31, b = is_updated_pixel and 'abcd' or 'abc' }))
			index = index + 1
		end
	end
end

-- Test image view unbuffer from loads the correct values into the image with no
-- offset.
buffer = {}
v3d.image_view_fill(image_view, { a = 0, b = '' })

for i = 1, image.width * image.height * image.depth do
	buffer[i] = { a = i, b = tostring(i) }
end

v3d.image_view_unbuffer_from(image_view, buffer)

local index = 1
for z = 1, image.depth do
	for y = 1, image.height do
		for x = 1, image.width do
			assert(_eq(v3d.image_view_get_pixel(image_view, x - 1, y - 1, z - 1), buffer[index]))
			index = index + 1
		end
	end
end

-- Test image unbuffer loads the correct values into the image with an offset
-- but no region.
buffer = {}
v3d.image_view_fill(image_view, { a = 0, b = '' })
buffer[1] = 'ignored'

for i = 1, image.width * image.height * image.depth do
	buffer[i + 1] = { a = i, b = tostring(i) }
end

v3d.image_view_unbuffer_from(image_view, buffer, 1)

local index = 1
for z = 1, image.depth do
	for y = 1, image.height do
		for x = 1, image.width do
			assert(_eq(v3d.image_view_get_pixel(image_view, x - 1, y - 1, z - 1), buffer[index + 1]))
			index = index + 1
		end
	end
end

v3d.exit_debug_region 'Image views'

end ----------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Samplers --------------------------------------------------------------------
do -----------------------------------------------------------------------------

v3d.enter_debug_region 'Samplers'

v3d.exit_debug_region 'Samplers'

end ----------------------------------------------------------------------------
