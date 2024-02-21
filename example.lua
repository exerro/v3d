
--- @type V3D
local v3d = require 'v3d'

local geometry = v3d.debug_cuboid {
	include_uvs = true,
	include_face_name = true,
} :build()

term.setGraphicsMode(2)

-- local image_width, image_height = 2 * term_width, 3 * term_height
local image_width, image_height = term.getSize(2)
local colour_image = v3d.create_image(v3d.uinteger(), image_width, image_height, 1, colours.black)
local depth_image = v3d.create_image(v3d.number(), image_width, image_height, 1, 0)
local views = {
	colour = v3d.image_view(colour_image),
	depth = v3d.image_view(depth_image),
}

local camera = v3d.camera { z = 2 }

local model1_transform = v3d.rotate_y(math.pi / 8)

local paintutils_image_str = [[
dddddddddddddddd
d5d55d5dd5d55d5d
5d55d5d5d55d55d5
87c887c887c7c878
c878c87c7c88787c
7c8c77c87887cc87
87c7c878878c87c8
c7c87c78cc7c878c
878c87c7c87887c8
c8c77c87878cc87c
7c78c78878c87c88
77cc7c78cc7c8787
878787c7c87887c8
c8887c87887cc87c
7c7c87887cc87c88
8c7c87c887c7c878]]

local paintutils_image = paintutils.parseImage(paintutils_image_str)

local test_image = v3d.create_image(v3d.uinteger(), #paintutils_image[1], #paintutils_image, 1, 0)
local test_image_view = v3d.image_view(test_image)
for y = 1, test_image.height do
	for x = 1, test_image.width do
		local c = paintutils_image[y][x]
		v3d.image_view_set_pixel(test_image_view, x - 1, y - 1, 0, math.floor(math.log(c + 0.5, 2)))
	end
end

local image_formats = {
	colour = colour_image.format,
	depth = depth_image.format,
}
local renderer = v3d.compile_renderer {
	image_formats = image_formats,
	pixel_shader = v3d.shader {
		source_format = geometry.vertex_format,
		face_format = geometry.face_format,
		image_formats = image_formats,
		code = [[
			if v3d_src_depth > v3d_dst.depth and v3d_face.name == 'front' then
				local u, v = v3d_src.uv
				u = u * 3 - 1
				v = v * 3 - 1

				v3d_dst.colour = v3d_constant.sampler:sample(v3d_external.image, u, v)
				v3d_dst.depth = v3d_src_depth
			end
		]],
		constants = {
			sampler = v3d.create_sampler2D {
				format = v3d.uinteger(),
				interpolate = 'nearest',
				wrap_u = 'mirror',
				wrap_v = 'repeat',
			},
		}
	},
	position_lens = v3d.format_lens(geometry.vertex_format, '.position'),
	record_statistics = true,
}

renderer.used_options.pixel_shader:set_variable('image', test_image)

-- for _ = 1, 300 do
-- 	v3d.renderer_render(renderer, geometry, views, camera, model1_transform)
-- end
-- local t0 = os.clock()
-- for _ = 1, 3000 do
-- 	v3d.renderer_render(renderer, geometry, views, camera, model1_transform)
-- end
-- print('render time:', os.clock() - t0)
-- do return end

-- local n = 6
-- for i = 0, 255 do
-- 	local r = math.floor(i / n / n) % n
-- 	local g = math.floor(i / n) % n
-- 	local b = i % n
-- 	term.setPaletteColour(i, r / (n - 1), g / (n - 1), b / (n - 1))
-- end

-- for i = 0, 255 do
-- 	local r = math.floor(i / 16)
-- 	local g = i % 16
-- 	term.setPaletteColour(i, r / 15, g / 15, 0.5)
-- end

-- for i = 0, 255 do
-- 	term.setPaletteColour(i, i / 255, i / 255, i / 255)
-- end
-- term.setPaletteColour(0, 80/255, 160/255, 240/255)

for i = 0, 15 do
	term.setPaletteColour(i, term.nativePaletteColour(2 ^ i))
end
term.setPaletteColour(math.floor(math.log(colours.lightGrey + 0.5, 2)), 0.4, 0.3, 0.2)
term.setPaletteColour(math.floor(math.log(colours.grey + 0.5, 2)), 0.4, 0.33, 0.24)

for i = 1, 1005 do
	v3d.enter_debug_region 'clear'
	v3d.image_view_fill(v3d.image_view(colour_image), 0)
	v3d.image_view_fill(v3d.image_view(depth_image), 0)
	v3d.exit_debug_region 'clear'

	v3d.enter_debug_region 'render'
	v3d.renderer_render(renderer, geometry, views, camera, model1_transform)
	v3d.exit_debug_region 'render'

	v3d.enter_debug_region 'present'
	-- v3d.image_view_present_term_subpixel(v3d.image_view(colour_image), term.current())
	-- v3d.image_view_present_graphics(v3d.image_view(colour_image), term.current(), true)
	term.setFrozen(true)
	v3d.image_view_present_graphics(v3d.image_view(colour_image), term.current(), false)
	term.setFrozen(false)
	-- v3d.exit_debug_region 'present'

	-- local _, button = os.pullEvent 'mouse_click'
	-- if button == 2 then
	-- 	model1_transform = model1_transform * v3d.rotate_y(-0.1)
	-- else
	-- 	model1_transform = model1_transform * v3d.rotate_y(0.1)
	-- end

	sleep(0.02)
	model1_transform = v3d.rotate_y(math.sin(i / 10))
end

term.setGraphicsMode(false)
