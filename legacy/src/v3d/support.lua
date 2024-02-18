
local v3d = require 'core'

require 'framebuffer'
require 'geometry'

v3d.support = {}

--------------------------------------------------------------------------------
--[[ Support layouts ]]---------------------------------------------------------
--------------------------------------------------------------------------------

do
	--- Framebuffer layout with just a colour layer.
	--- @type v3d.Layout
	v3d.support.COLOUR_LAYOUT = v3d.create_layout()
		:add_layer('colour', 'exp-palette-index', 1)

	--- Framebuffer layout with colour and depth layers.
	--- @type v3d.Layout
	v3d.support.COLOUR_DEPTH_LAYOUT = v3d.create_layout()
		:add_layer('colour', 'exp-palette-index', 1)
		:add_layer('depth', 'depth-reciprocal', 1)
end

--------------------------------------------------------------------------------
--[[ Support formats ]]---------------------------------------------------------
--------------------------------------------------------------------------------

do
	--- A default format containing just position and colour attributes.
	--- @type v3d.Format
	v3d.support.DEFAULT_FORMAT = v3d.create_format()
		:add_vertex_attribute('position', 3, true)
		:add_face_attribute('colour', 1)

	--- A format containing just position and UV attributes, useful for textures or
	--- other UV based rendering.
	--- @type v3d.Format
	v3d.support.UV_FORMAT = v3d.create_format()
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
	v3d.support.DEBUG_CUBE_FORMAT = v3d.create_format()
		:add_vertex_attribute('position', 3, true)
		:add_vertex_attribute('uv', 2, true)
		:add_face_attribute('colour', 1)
		:add_face_attribute('face_normal', 3)
		:add_face_attribute('face_index', 1)
		:add_face_attribute('side_index', 1)
		:add_face_attribute('side_name', 1)
end
