
--- @type V3D
local v3d = require 'v3d'

local geometry_builder = v3d.debug_cube {
	-- include_normals = 'vertex',
	include_indices = 'face',
}

local geometry = v3d.geometry_builder_build(geometry_builder)

	-- if v3d_compare_depth(v3d_pixel('depth'), v3d_fragment_depth()) then
	-- 	v3d_write_pixel('colour', v3d_vertex('index'))
	-- 	v3d_write_pixel('depth', v3d_fragment_depth())
	-- end
local my_pixel_shader = [[
	local x, y, z = v3d_vertex_flat('position')
	local index = math.floor(math.max(0, math.min(5, (x + 0.5) * 6))) * 36 + math.floor(math.max(0, math.min(5, (y + 0.5) * 6))) * 6 + math.floor(math.max(0, math.min(5, (z + 0.5) * 6)))
	index = math.max(0, math.min(255, index))
	-- v3d_set_pixel_flat('colour', 2 ^ v3d_face_flat('index'))
	v3d_set_pixel_flat('colour', index)
]]

local term_width, term_height = term.getSize()

term.setGraphicsMode(2)

-- local image_width, image_height = 2 * term_width, 3 * term_height
local image_width, image_height = term.getSize(2)
local colour_image = v3d.create_image(v3d.uinteger(), image_width, image_height, 1, colours.black)
local depth_image = v3d.create_image(v3d.number(), image_width, image_height, 1, 0)
local views = {
	colour = v3d.image_view(colour_image),
	depth = v3d.image_view(depth_image),
}

local camera = v3d.camera {
	z = 2,
	y = 0.25,
} * v3d.rotate_y(math.pi / 4 * 0)

local render_pipeline = v3d.compile_pipeline {
	image_formats = {
		colour = colour_image.format,
		depth = depth_image.format,
	},
	vertex_format = geometry.vertex_format,
	face_format = geometry.face_format,
	cull_face = 'back',
	sources = { pixel = my_pixel_shader },
	position_lens = v3d.format_lens(geometry.vertex_format, '.position'),
	record_statistics = true,
}

local n = 6
for i = 0, 255 do
	local r = math.floor(i / n / n) % n
	local g = math.floor(i / n) % n
	local b = i % n
	term.setPaletteColour(i, r / (n - 1), g / (n - 1), b / (n - 1))
end

for i = 1, 1005 do
	v3d.enter_debug_region 'clear'
	-- v3d.image_view_fill(v3d.image_view(colour_image), colours.black)
	v3d.image_view_fill(v3d.image_view(colour_image), 0)
	-- pipeline, geometry, views, transform, model_transform, viewport
	v3d.exit_debug_region 'clear'

	v3d.enter_debug_region 'render'
	v3d.pipeline_render(render_pipeline, geometry, views, camera)
	v3d.exit_debug_region 'render'

	v3d.enter_debug_region 'present'
	-- v3d.image_view_present_term_subpixel(v3d.image_view(colour_image), term.current())
	-- v3d.image_view_present_graphics(v3d.image_view(colour_image), term.current(), true)
	v3d.image_view_present_graphics(v3d.image_view(colour_image), term.current(), false)
	-- v3d.exit_debug_region 'present'

	os.pullEvent 'mouse_click'

	-- sleep(0.05)
	camera = camera * v3d.rotate_y(0.05) * v3d.translate(0, math.sin(i / 10) * 0.05, 0)
end

term.setGraphicsMode(false)

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
