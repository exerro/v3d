
--- @type V3D
local v3d = require 'v3d'

local geometry = v3d.geometry_builder_build(v3d.debug_cuboid())

local camera = v3d.camera { z = 1 }

local model_transform = v3d.translate(0, 0, -1) * v3d.rotate_y(math.pi * 0.3)

term.setGraphicsMode(2)

local image_width, image_height = term.getSize(2)
local colour_image = v3d.create_image(v3d.uinteger(), image_width, image_height, 1, colours.black)
local depth_image = v3d.create_image(v3d.number(), image_width, image_height, 1, 0)

local image_views = {
	colour = v3d.image_view(colour_image),
	depth = v3d.image_view(depth_image),
}

local renderer = v3d.compile_renderer {
	pixel_shader = v3d.shader {
		source_format = geometry.vertex_format,
		image_formats = {
			colour = colour_image.format,
			depth = depth_image.format,
		},
		code = [[
			if v3d_src_depth > v3d_dst.depth then
				local x, y, z = v3d_src_pos
				v3d_dst.colour = math.max(1, 2 ^ math.floor((x + 1) * 10))
				v3d_dst.depth = v3d_src_depth
			end
		]],
	},
	position_lens = v3d.format_lens(geometry.vertex_format, '.position'),
	image_formats = {
		colour = colour_image.format,
		depth = depth_image.format,
	},
	vertex_format = geometry.vertex_format,
}

for _ = 1, 40 do
	v3d.image_view_fill(image_views.colour, colours.black)
	v3d.image_view_fill(image_views.depth, 0)
	v3d.renderer_render(renderer, geometry, image_views, camera, model_transform)
	v3d.image_view_present_graphics(image_views.colour, term, true)
	sleep(0.05)
	model_transform = model_transform * v3d.rotate_y(0.01)
end

os['pullEvent'] 'mouse_click'
term.setGraphicsMode(false)
