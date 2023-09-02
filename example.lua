
local v3d = require 'v3d'

term.setBackgroundColour(colours.black)
term.clear()
term.setCursorPos(1, 1)

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

-- local render_pipeline = v3d.compile_pipeline {
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
