
local v3d = require '/v3d'

local framebuffer = v3d.create_framebuffer_subpixel(term.getSize())
local camera = v3d.create_camera()
local pipeline = v3d.create_pipeline {
	layout = v3d.UV_LAYOUT,
	cull_face = false,
	attributes = { 'uv' },
	pack_attributes = false,
    fragment_shader = v3d.create_texture_sampler(),
}
local cube = v3d.create_debug_cube():cast(v3d.UV_LAYOUT):build()

local image = paintutils.loadImage 'transparent_example.nfp'
pipeline:set_uniform('u_texture', image)
pipeline:set_uniform('u_texture_width', #image[1])
pipeline:set_uniform('u_texture_height', #image)

while true do
	camera.yRotation = camera.yRotation + 0.04
	local s = math.sin(camera.yRotation)
	local c = math.cos(camera.yRotation)
	local distance = 2
	camera.x = s * distance
	camera.z = c * distance
	framebuffer:clear(colours.white)
	pipeline:render_geometry(cube, framebuffer, camera)
	framebuffer:blit_subpixel(term)
	sleep(0.05)
end
