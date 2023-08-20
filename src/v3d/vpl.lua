
-- This approach sucks.
-- Instead, put stuff in environments/<env>.lua
-- Should define stuff with normal Lua syntax and use magic docstring parsing to
-- ASTify it
-- The functions can return their macro expansion or nil otherwise
-- We can embed everything in the executable

local vpl = {}
vpl.environments = {}
vpl.contexts = {}

local function define(environment, name)
	return function(fn_info)
		environment[name] = fn_info
	end
end

local function macro_type(typename)
	return setmetatable({}, {
		__call = function(name)
			return setmetatable({ name = name, type = typename }, { __call = function(s, v)
				s.default_value = v
				return s
			end })
		end
	})
end

local any_type = macro_type 'any'
local integer_type = macro_type 'number'
local number_type = macro_type 'number'
local string_type = macro_type 'string'
local V3DImage_type = macro_type 'V3DImage'

--------------------------------------------------------------------------------
--- Fragment environment -------------------------------------------------------
do -----------------------------------------------------------------------------

vpl.environments.fragment = {}

define(vpl.environments.fragment, 'v3d_vertex') {
	string_type 'lens',
	returns = any_type,
}

define(vpl.environments.fragment, 'v3d_face') {
	string_type 'lens',
	returns = any_type,
}

end ----------------------------------------------------------------------------

--------------------------------------------------------------------------------
--- Framebuffer environment ----------------------------------------------------
do -----------------------------------------------------------------------------


	-- * `v3d_layer(name)`
	-- * `v3d_layer_index(lens, x, y, z)`
	-- * `v3d_layer(lens, x, y, z)`
	-- * `v3d_layer_unpacked(lens, x, y, z)`
	-- * `v3d_layer(lens, index)`
	-- * `v3d_layer_unpacked(lens, index)`
	-- * `v3d_set_layer(lens, x, y, z, value)`
	-- * `v3d_set_layer_unpacked(lens, x, y, z, values...)`
	-- * `v3d_set_layer(lens, index, value)`
	-- * `v3d_set_layer_unpacked(lens, index, values...)`
	

vpl.environments.framebuffer = {}

define(vpl.environments.framebuffer, 'v3d_layer') {
	string_type 'lens',
	returns = V3DImage_type,
}

define(vpl.environments.framebuffer, 'v3d_layer_index') {
	string_type 'lens',
	number_type 'x',
	number_type 'y',
	number_type 'z',
	returns = integer_type,
}

end ----------------------------------------------------------------------------

return vpl
