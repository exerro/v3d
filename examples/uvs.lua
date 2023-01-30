
local v3d = require '/v3d'

local fb = v3d.create_framebuffer_subpixel(term.getSize())
local camera = v3d.create_camera(math.pi / 4)
local pipeline = v3d.create_pipeline {
	interpolate_uvs = true,
	cull_face = false,
	fragment_shader = function(_, u, v)
		return 2 ^ (math.min(math.floor(u * 4), 3) * 4 + math.min(math.floor(v * 4), 3))
	end,
}

camera.z = 2

-- here we define a quad by manually specifying all the attributes
-- don't worry too much about this - the point is that it generates a quad with
-- a gap between the triangles, and gives each corner of the quad UVs
local geometry_list = {}
geometry_list[1] = v3d.create_geometry(v3d.GEOMETRY_COLOUR_UV)
geometry_list[1]:add_colour_uv_triangle(-1.1,  1, 0, 0, 0, -1.1, -1, 0, 0, 1,  0.9, -1, 0, 1, 1, colours.blue)
geometry_list[1]:add_colour_uv_triangle(-0.9,  1, 0, 0, 0,  1.1, -1, 0, 1, 1,  1.1,  1, 0, 1, 0, colours.cyan)

for y = 0, 3 do
	for x = 0, 3 do
		term.setPaletteColour(2 ^ (y * 4 + x), x / 3, y / 3, 0)
	end
end

pcall(function()
	while true do
		geometry_list[1]:rotate_y(0.05)
		fb:clear(1)
		pipeline:render_geometry(geometry_list, fb, camera)
		fb:blit_subpixel(term)
		sleep(0.05)
	end
end)

for i = 0, 15 do
	term.setPaletteColour(2 ^ i, term.nativePaletteColour(2 ^ i))
end
