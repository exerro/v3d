
shell.run '/v3d/build'
package.path = "/?.lua;" .. package.path
local v3d = require 'v3d'

local w, h = term.getSize()
local fb = v3d.create_framebuffer_subpixel(math.min(60, w), math.min(30, h - 2))
local camera = v3d.create_perspective_camera(math.pi / 4)
local geometry = v3d.create_geometry()
local pipeline = v3d.create_pipeline {
	interpolate_uvs = true,
	fragment_shader = function(uniforms, u, v)
		-- return uniforms.colour
		if math.random(1, 10) <= 3 then
			return 0
		end
		return 2 ^ math.random(2, 4)
	end,
}

pipeline:set_uniform('colour', colours.purple)

geometry:add_coloured_triangle(-1,  1, -2, -1, -1, -2, 1, -1, -2, colours.blue)
geometry:add_coloured_triangle(-1,  1, -2, 1, -1, -2, 1,  1, -2, colours.cyan)

pipeline:render_geometry(geometry, fb, camera)
fb:blit_subpixel(term)
