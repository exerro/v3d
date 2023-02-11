
local v3d = require '/v3d'

local fb = v3d.create_framebuffer_subpixel(term.getSize())
local camera = v3d.create_camera(math.pi / 4)
local pipeline = v3d.create_pipeline {
	layout = v3d.UV_LAYOUT,
	interpolate_attribute = 'uv',
	cull_face = false,
	fragment_shader = function(_, u, v)
		return 2 ^ (math.min(math.floor(u * 4), 3) * 4 + math.min(math.floor(v * 4), 3))
	end,
}

-- here we define a quad by manually specifying all the attributes
-- don't worry too much about this - the point is that it generates a quad with
-- a gap between the triangles, and gives each corner of the quad UVs
local cube = v3d.create_geometry_builder(v3d.UV_LAYOUT)
	:append_data('position', { -1.1, 1, 0, -1.1, -1, 0, 0.9, -1, 0 })
	:append_data('position', { -0.9, 1, 0, 1.1, -1, 0, 1.1, 1, 0 })
	:set_data('uv', { 0, 0, 0, 1, 1, 1, 0, 0, 1, 1, 1, 0 })
	:build()

for y = 0, 3 do
	for x = 0, 3 do
		term.setPaletteColour(2 ^ (y * 4 + x), x / 3, y / 3, 0)
	end
end

pcall(function()
	while true do
		camera:set_rotation(camera.xRotation, camera.yRotation + 0.05, camera.zRotation)
		camera:set_position(math.sin(camera.yRotation) * 2, 0, math.cos(camera.yRotation) * 2)
		fb:clear(1)
		pipeline:render_geometry(cube, fb, camera)
		fb:blit_subpixel(term)
		sleep(0.05)
	end
end)

for i = 0, 15 do
	term.setPaletteColour(2 ^ i, term.nativePaletteColour(2 ^ i))
end
