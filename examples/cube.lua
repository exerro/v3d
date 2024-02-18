
--- @type V3D
local v3d = require 'v3d'

local geometry = v3d.debug_cuboid():build()
local image_views = v3d.create_fullscreen_image_views()
local camera = v3d.camera { z = 1 }
local model_transform = v3d.translate(0, 0, -1) * v3d.rotate_y(math.pi * 0.3)

local pixel_shader = v3d.shader {
	source_format = geometry.vertex_format,
	image_formats = v3d.image_formats_of(image_views),
	code = [[
		if v3d_src_depth > v3d_dst.depth then
			v3d_dst.colour = colours.white
			v3d_dst.depth = v3d_src_depth
		end
	]],
}
local renderer = v3d.compile_renderer { pixel_shader = pixel_shader }

renderer:render(geometry, image_views, camera, model_transform)
image_views.colour:present_term_subpixel(term)
