
--- @type V3D
local v3d = require 'v3d'

local geometry = v3d.geometry_builder_build(v3d.debug_cuboid())
local image_views = v3d.create_fullscreen_image_views { size_mode = 'graphics' }
local camera = v3d.camera { z = 1 }
local model_transform = v3d.translate(0, 0, -1) * v3d.rotate_y(math.pi * 0.3)

local pixel_shader = v3d.shader {
	source_format = geometry.vertex_format,
	image_formats = v3d.image_formats_of(image_views),
	code = [[
		if v3d_src_depth > v3d_dst.depth then
			local x, y, z = v3d_src_pos
			v3d_dst.colour = math.max(1, 2 ^ math.floor((x + 1) * 10))
			v3d_dst.depth = v3d_src_depth
		end
	]],
}
local renderer = v3d.compile_renderer { pixel_shader = pixel_shader }

term.setGraphicsMode(2)

while true do
	v3d.image_view_fill(image_views.colour, colours.black)
	v3d.image_view_fill(image_views.depth, 0)
	v3d.renderer_render(renderer, geometry, image_views, camera, model_transform)
	v3d.image_view_present_graphics(image_views.colour, term, true)
	sleep(0.05)
	model_transform = model_transform * v3d.rotate_y(0.03)
end
