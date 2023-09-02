
--- @type V3D
local v3d = require 'v3d'

local geometry_builder = v3d.debug_cube {
	-- include_normals = 'vertex',
	include_indices = 'face',
}

local geometry = v3d.geometry_builder_build(geometry_builder)

local my_pixel_shader = [[
	if v3d_compare_depth(v3d_pixel('depth'), v3d_fragment_depth()) then
		v3d_write_pixel('colour', v3d_vertex('index'))
		v3d_write_pixel('depth', v3d_fragment_depth())
	end
]]

local term_width, term_height = term.getSize()

local image_width, image_height = 2 * term_width, 3 * term_height
local colour_image = v3d.create_image(v3d.uinteger(), image_width, image_height, 1, colours.black)

local camera = v3d.camera {
	z = 2,
	y = 1,
}

local render_pipeline = v3d.compile_pipeline {
	image_formats = { colour = v3d.integer() },
	vertex_format = geometry.vertex_format,
	face_format = geometry.face_format,
	cull_face = 'back',
	sources = { pixel = my_pixel_shader },
	position_lens = v3d.format_lens(geometry.vertex_format, '.position'),
	record_statistics = true,
}

for i = 1, 100 do
	v3d.image_view_fill(v3d.image_view(colour_image), colours.black)
	-- pipeline, geometry, views, transform, model_transform, viewport
	v3d.enter_debug_region('draw')
	v3d.pipeline_render(render_pipeline, geometry, { colour = v3d.image_view(colour_image) }, camera)
	v3d.exit_debug_region('draw')
	v3d.image_view_present_term_subpixel(v3d.image_view(colour_image), term.current())
	sleep(0.05)
	camera = camera * v3d.rotate_y(0.05) * v3d.translate(0, math.sin(i / 10) * 0.1, 0)
end

do return end

-- local viewport = {
-- 	x = 0, y = 0, z = 0,
-- 	width = image_width, height = image_height, depth = 1,
-- }

-- render_pipeline:render(geometry, framebuffer, camera, viewport)

local image = v3d.create_image(v3d.uinteger(), term_width, term_height, 1)
local image_view = v3d.image_view(image)
local smaller_image_view = v3d.image_view(image, {
	x = 2, y = 3, z = 0,
	width = 10, height = 10, depth = 1,
})

term.setGraphicsMode(1)

for _ = 1, 100 do
	v3d.image_view_fill(image_view, colours.white)
	v3d.image_view_fill(smaller_image_view, 2 ^ math.random(1, 15))

	v3d.image_view_present_graphics(image_view, term.current(), true)
	sleep(0.1)
end

sleep(1)
term.setGraphicsMode(false)
