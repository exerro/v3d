
shell.run '/v3d/build'
package.path = "/?.lua;" .. package.path
local v3d = require 'v3d'

local w, h = term.getSize()
local fb = v3d.create_framebuffer_subpixel(math.min(60, w), math.min(30, h - 2))
local camera = v3d.create_perspective_camera(math.pi / 4)
local geometry = v3d.create_geometry(v3d.GEOMETRY_COLOUR_UV)
local pipeline = v3d.create_pipeline {
	interpolate_uvs = true,
	cull_face = false,
	fragment_shader = function(uniforms, u, v)
		local a = math.floor(u * 6) % 2 == 1
		local b = math.floor(v * 6) % 2 == 1
		return a and (b and colours.purple or colours.blue) or (b and colours.cyan or colours.lightBlue)
	end,
}

camera.z = 2

pipeline:set_uniform('colour', colours.purple)

geometry:add_triangle(-1,  1, 0, 0, 0, -1, -1, 0, 0, 1,  1, -1, 0, 1, 1, colours.blue)
geometry:add_triangle(-1,  1, 0, 0, 0,  1, -1, 0, 1, 1,  1,  1, 0, 1, 0, colours.cyan)

for _ = 1, 20 do
	geometry:rotate_y(0.05)
	fb:clear(1)
	pipeline:render_geometry(geometry, fb, camera)
	fb:blit_subpixel(term)
	sleep(0.05)
end
