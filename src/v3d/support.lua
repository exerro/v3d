
local v3d_framebuffer = require '_framebuffer'
local v3d_geometry = require '_geometry'

local v3d_support = {}

--------------------------------------------------------------------------------
--[[ Support layouts ]]---------------------------------------------------------
--------------------------------------------------------------------------------

do
	--- Framebuffer layout with just a colour layer.
	--- @type v3d.Layout
	v3d_support.COLOUR_LAYOUT = v3d_framebuffer.create_layout()
		:add_layer('colour', 'exp-palette-index', 1)

	--- Framebuffer layout with colour and depth layers.
	--- @type v3d.Layout
	v3d_support.COLOUR_DEPTH_LAYOUT = v3d_framebuffer.create_layout()
		:add_layer('colour', 'exp-palette-index', 1)
		:add_layer('depth', 'depth-reciprocal', 1)
end

--------------------------------------------------------------------------------
--[[ Support formats ]]---------------------------------------------------------
--------------------------------------------------------------------------------

do
	--- A default format containing just position and colour attributes.
	--- @type v3d.Format
	v3d_support.DEFAULT_FORMAT = v3d_geometry.create_format()
		:add_vertex_attribute('position', 3, true)
		:add_face_attribute('colour', 1)

	--- A format containing just position and UV attributes, useful for textures or
	--- other UV based rendering.
	--- @type v3d.Format
	v3d_support.UV_FORMAT = v3d_geometry.create_format()
		:add_vertex_attribute('position', 3, true)
		:add_vertex_attribute('uv', 2, true)

	--- The format used by [[@v3d.create_debug_cube]], containing the following
	--- attributes:
	--- * `position` - numeric vertex attribute - 3 components
	--- * `uv` - numeric vertex attribute - 2 components
	--- * `colour` - face attribute - 1 components
	--- * `face_normal` - face attribute - 3 components
	--- * `face_index` - face attribute - 1 components
	--- * `side_index` - face attribute - 1 components
	--- * `side_name` - face attribute - 1 components
	--- @type v3d.Format
	v3d_support.DEBUG_CUBE_FORMAT = v3d_geometry.create_format()
		:add_vertex_attribute('position', 3, true)
		:add_vertex_attribute('uv', 2, true)
		:add_face_attribute('colour', 1)
		:add_face_attribute('face_normal', 3)
		:add_face_attribute('face_index', 1)
		:add_face_attribute('side_index', 1)
		:add_face_attribute('side_name', 1)
end

--------------------------------------------------------------------------------
--[[ v3d.support.create_debug_cube ]]-------------------------------------------
--------------------------------------------------------------------------------

do
	--- Create a [[@v3d.GeometryBuilder]] cube in the [[@v3d.DEBUG_CUBE_FORMAT]]
	--- format.
	--- @param cx number | nil Centre X coordinate of the cube.
	--- @param cy number | nil Centre Y coordinate of the cube.
	--- @param cz number | nil Centre Z coordinate of the cube.
	--- @param size number | nil Distance between opposide faces of the cube.
	--- @return v3d.GeometryBuilder
	--- @nodiscard
	function v3d_support.create_debug_cube(cx, cy, cz, size)
		local s2 = (size or 1) / 2

		cx = cx or 0
		cy = cy or 0
		cz = cz or 0

		return v3d_geometry.create_geometry_builder(v3d_support.DEBUG_CUBE_FORMAT)
			:set_data('position', {
				-s2,  s2,  s2, -s2, -s2,  s2,  s2,  s2,  s2, -- front 1
				-s2, -s2,  s2,  s2, -s2,  s2,  s2,  s2,  s2, -- front 2
					s2,  s2, -s2,  s2, -s2, -s2, -s2,  s2, -s2, -- back 1
					s2, -s2, -s2, -s2, -s2, -s2, -s2,  s2, -s2, -- back 2
				-s2,  s2, -s2, -s2, -s2, -s2, -s2,  s2,  s2, -- left 1
				-s2, -s2, -s2, -s2, -s2,  s2, -s2,  s2,  s2, -- left 2
					s2,  s2,  s2,  s2, -s2,  s2,  s2,  s2, -s2, -- right 1
					s2, -s2,  s2,  s2, -s2, -s2,  s2,  s2, -s2, -- right 2
				-s2,  s2, -s2, -s2,  s2,  s2,  s2,  s2, -s2, -- top 1
				-s2,  s2,  s2,  s2,  s2,  s2,  s2,  s2, -s2, -- top 2
					s2, -s2, -s2,  s2, -s2,  s2, -s2, -s2, -s2, -- bottom 1
					s2, -s2,  s2, -s2, -s2,  s2, -s2, -s2, -s2, -- bottom 2
			})
			:set_data('uv', {
				0, 0, 0, 1, 1, 0, -- front 1
				0, 1, 1, 1, 1, 0, -- front 2
				0, 0, 0, 1, 1, 0, -- back 1
				0, 1, 1, 1, 1, 0, -- back 2
				0, 0, 0, 1, 1, 0, -- left 1
				0, 1, 1, 1, 1, 0, -- left 2
				0, 0, 0, 1, 1, 0, -- right 1
				0, 1, 1, 1, 1, 0, -- right 2
				0, 0, 0, 1, 1, 0, -- top 1
				0, 1, 1, 1, 1, 0, -- top 2
				0, 0, 0, 1, 1, 0, -- bottom 1
				0, 1, 1, 1, 1, 0, -- bottom 2
			})
			:set_data('colour', {
				2048, 512, -- front (blue, cyan)
				4096, 16, -- back (brown, yellow)
				8, 64, -- left (lightBlue, pink)
				16384, 2, -- right (red, orange)
				8192, 32, -- top (green, lime)
				1024, 4, -- bottom (purple, magenta)
			})
			:set_data('face_normal', {
					0,  0,  1,  0,  0,  1, -- front
					0,  0,  1,  0,  0, -1, -- back
				-1,  0,  0, -1,  0,  0, -- left
					1,  0,  0,  1,  0,  0, -- right
					0,  1,  0,  0,  1,  0, -- top
					0, -1,  0,  0, -1,  0, -- bottom
			})
			:set_data('face_index', { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 })
			:set_data('side_index', { 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5 })
			:set_data('side_name', {
				'front', 'front',
				'back', 'back',
				'left', 'left',
				'right', 'right',
				'top', 'top',
				'bottom', 'bottom',
			})
			:map('position', function(d)
				return { d[1] + cx, d[2] + cy, d[3] + cz }
			end)
	end
end

return v3d_support
