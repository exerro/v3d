
local v3d = require 'v3d'

term.setBackgroundColour(colours.black)
term.clear()
term.setCursorPos(1, 1)

local image1 = v3d.create_image(v3d.uinteger(), 10, 10, 1, nil, 'Image 1')
local image2 = v3d.create_image(v3d.uinteger(), 10, 10, 1, nil, 'Image 2')

local map = v3d.compile_image_map_pipeline {
	sources = {
		main = [[
			local xy = v3d_pixel_position(source, 'xy')
			v3d_set_pixel(destination, v3d_pixel(source))
		]]
	},
	source_image_format = image1.format,
	destination_image_format = image2.format,
}

map:execute(image1, image1:full_region(), image2, image2:full_region())

do return end

--------------------------------------------------------------------------------

local term_width, term_height = term.getSize()
local image_width, image_height = term_width * 2, term_height * 3
local framebuffer = v3d.create_framebuffer(image_width, image_height, 1, {
	colour = v3d.uinteger(),
	depth = v3d.number(),
})

local geometry = v3d.geometry_builder_build(v3d.debug_cube())

local camera = v3d.camera { z = 1 }

-- local my_fragment_shader = [[
-- 	if v3d_compare_depth(v3d_pixel('depth'), v3d_fragment_depth()) then
-- 		v3d_write_pixel('colour', v3d_vertex('index'))
-- 		v3d_write_pixel('depth', v3d_fragment_depth())
-- 	end
-- ]]

-- local render_pipeline = v3d.compile_render_pipeline {
-- 	vertex_format = geometry.vertex_format,
-- 	face_format = geometry.face_format,
-- 	framebuffer_format = framebuffer.format,
-- 	cull_face = 'back',
-- 	sources = { fragment = my_fragment_shader },
-- 	position_lens = v3d.format_lens(geometry.vertex_format, '.position'),
-- }

-- local viewport = {
-- 	x = 0, y = 0, z = 0,
-- 	width = image_width, height = image_height, depth = 1,
-- }

-- render_pipeline:render(geometry, framebuffer, camera, viewport)

local image = v3d.create_image(v3d.uinteger(), term_width, term_height, 1)

term.setGraphicsMode(1)

while true do
	v3d.image_fill(image, colours.white)
	v3d.image_fill(image, colours.red, {
		x = 0, y = 0, z = 0,
		width = 10, height = 10, depth = 1,
	})

	v3d.image_present_graphics(image, term, true)
	sleep(0)
end

sleep(1)
term.setGraphicsMode(false)
