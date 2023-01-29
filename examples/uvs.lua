
-- shell.run '/v3d/build'
local v3d = require '/v3d'

local w, h = term.getSize()
local fb = v3d.create_framebuffer_subpixel(math.min(60, w), math.min(30, h - 2))
local camera = v3d.create_camera(math.pi / 4)
local geometry = v3d.create_geometry(v3d.GEOMETRY_COLOUR_UV)
local pipeline = v3d.create_pipeline {
	interpolate_uvs = true,
	cull_face = false,
	fragment_shader = v3d.create_texture_sampler(),
}

local image = paintutils.loadImage 'image.nfp'
pipeline:set_uniform('u_texture', image)
pipeline:set_uniform('u_texture_width', #image[1])
pipeline:set_uniform('u_texture_height', #image)

camera.z = 2

geometry:add_colour_uv_triangle(-1,  1, 0, 0, 0, -1, -1, 0, 0, 1,  1, -1, 0, 1, 1, colours.blue)
geometry:add_colour_uv_triangle(-1,  1, 0, 0, 0,  1, -1, 0, 1, 1,  1,  1, 0, 1, 0, colours.cyan)

for i = 1, 100 do
	geometry:rotate_y(0.05)
	fb:clear(1)
	pipeline:render_geometry({ geometry }, fb, camera)
	fb:blit_subpixel(term)
	sleep(0.05)
end
