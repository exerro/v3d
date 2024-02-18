
--- @type V3D
local v3d = require 'v3d'

local geometry = v3d.geometry_builder_build(v3d.debug_cuboid())

local camera = v3d.camera { z = 1 }

local model_transform = v3d.translate(0, 0, -1) * v3d.rotate_y(math.pi * 0.3)

local term_width, term_height = term.getSize()
local image_width, image_height = term_width * 2, term_height * 3
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
				v3d_dst.colour = colours.white
				v3d_dst.depth = v3d_src_depth
			end
		]],
	},
	position_lens = v3d.format_lens(geometry.vertex_format, '.position'),
	image_formats = {
		colour = colour_image.format,
		depth = depth_image.format,
	},
}

v3d.renderer_render(renderer, geometry, image_views, camera, model_transform)
v3d.image_view_present_term_subpixel(image_views.colour, term)
