
--- @type V3D
local v3d = require 'v3d'

local geometry = v3d.geometry_builder_build(v3d.debug_cuboid())

local camera = v3d.camera { z = 1 }

local rotation_transform = v3d.identity()
local transforms = {}
local count = 5
local depth_count = 200

for x = -count, count do
	for y = -count, count do
		for z = -depth_count, 0 do
			table.insert(transforms, v3d.scale_all(0.2) * v3d.translate(x, y, z) * v3d.scale_all(0.5))
		end
	end
end

term.setGraphicsMode(2)

local image_width, image_height = term.getSize(2)
local colour_image = v3d.create_image(v3d.uinteger(), image_width, image_height, 1, 15)
local depth_image = v3d.create_image(v3d.number(), image_width, image_height, 1, 0)

local image_views = {
	colour = v3d.image_view(colour_image),
	depth = v3d.image_view(depth_image),
}

local pixel_shader = v3d.shader {
	source_format = geometry.vertex_format,
	image_formats = {
		colour = colour_image.format,
		depth = depth_image.format,
	},
	code = [[
		if v3d_src_depth > v3d_dst.depth then
			local x = v3d_src.position.x
			v3d_dst.colour = math.max(0, math.min(255, math.floor(10 + x * 10)))
			v3d_dst.depth = v3d_src_depth
		end
	]],
}
local renderer = v3d.compile_renderer { pixel_shader = pixel_shader }

local frame_time = os.clock()
while true do
	v3d.enter_debug_region('clear')
	v3d.image_view_fill(image_views.colour, 15)
	v3d.image_view_fill(image_views.depth, 0)
	v3d.exit_debug_region('clear')

	v3d.enter_debug_region('render')
	for i = 1, #transforms do
		v3d.renderer_render(renderer, geometry, image_views, camera, transforms[i] * rotation_transform)
	end
	v3d.exit_debug_region('render')

	v3d.enter_debug_region('present')
	v3d.image_view_present_graphics(image_views.colour, term, false)
	v3d.exit_debug_region('present')

	v3d.enter_debug_region('sleep')
	os.queueEvent 'yield'
	os.pullEvent 'yield'
	while os.clock() - frame_time < 0.05 do end
	frame_time = os.clock()
	v3d.exit_debug_region('sleep')

	v3d.enter_debug_region('rotate')
	rotation_transform = rotation_transform * v3d.rotate_y(0.05)
	v3d.exit_debug_region('rotate')
end
