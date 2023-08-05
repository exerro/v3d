
local v3d = require 'v3d'

local pineapple_image = v3d.create_image(v3d.uinteger(), 16, 15, 1)

-- Set the color of each pixel to represent the pineapple
for x = 0, 15 do
    for y = 0, 15 do
        if (x >= 6 and x <= 9) and (y >= 6 and y <= 9) then
            v3d.image_set_pixel(pineapple_image, x, y, 0, colours.yellow)
        else
            v3d.image_set_pixel(pineapple_image, x, y, 0, colours.green)
        end
    end
end

v3d.image_present_term_subpixel(pineapple_image, term.current())

local my_inner_type = v3d.struct { x = v3d.integer(), y = v3d.integer() }
local my_outer_type = v3d.struct { inner = my_inner_type }
local my_outer_lens = v3d.type_lens(my_outer_type, '.inner')
local my_inner_lens = v3d.type_lens(my_inner_type, '.y')
local my_lens = my_outer_lens .. my_inner_lens

assert(my_lens.in_type == my_outer_type)
assert(my_lens.out_type == v3d.integer())
assert(my_lens.indices[1] == 'inner')
assert(my_lens.indices[2] == 'y')
assert(my_lens.offset == 1)

local term_width, term_height = term.getSize()
local image_width, image_height = term_width * 2, term_height * 3
local colour_image = v3d.create_image(v3d.uinteger(), image_width, image_height, 1)
local depth_image = v3d.create_image(v3d.number(), image_width, image_height, 1)
local images = { colour = colour_image, depth = depth_image }

local geometry = v3d.geometry_builder_build(v3d.debug_cube())

local camera = v3d.camera { z = 1 }

local my_fragment_shader = [[
	if v3d_compare_depth(v3d_image_read_fragment('depth'), v3d_fragment_depth()) then
		v3d_image_write_fragment('colour', v3d_vertex('index'))
		v3d_image_write_fragment('depth', v3d_fragment_depth())
	end
]]

local render_pipeline = v3d.compile_render_pipeline {
	vertex_type = geometry.vertex_type,
	face_type = geometry.face_type,
	image_types = {
		colour = colour_image.type,
		depth = depth_image.type,
	},
	cull_face = 'back',
	sources = { fragment = my_fragment_shader },
	position_lens = v3d.type_lens(geometry.vertex_type, '.position'),
	pixel_aspect_ratio = 1,
}

local viewport = {
	x = 0, y = 0, z = 0,
	width = image_width, height = image_height, depth = 0,
}

render_pipeline:render(geometry, images, camera, viewport)

local image = v3d.create_image(v3d.uinteger(), term_width, term_height, 1)

v3d.image_fill(image, colours.white)
v3d.image_fill(image, colours.red, {
	x = 20, y = 20, z = 0,
	width = 100, height = 100, depth = 1,
})

term.setGraphicsMode(1)
v3d.image_present_graphics(image, term, true)

sleep(1)
term.setGraphicsMode(false)
