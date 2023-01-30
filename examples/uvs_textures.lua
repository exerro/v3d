
local v3d = require '/v3d'

local framebuffer = v3d.create_framebuffer_subpixel(term.getSize())
local camera = v3d.create_camera()
local pipeline = v3d.create_pipeline {
    interpolate_uvs = true,
    fragment_shader = v3d.create_texture_sampler(),
}
local geometry_list = {}
geometry_list[1] = v3d.create_debug_cube()

term.setPaletteColour(colours.lightGrey, 0.4, 0.3, 0.2)
term.setPaletteColour(colours.grey, 0.4, 0.33, 0.24)

local image = paintutils.loadImage 'example.nfp'
pipeline:set_uniform('u_texture', image)
pipeline:set_uniform('u_texture_width', #image[1])
pipeline:set_uniform('u_texture_height', #image)

pcall(function()
	while true do
		camera.yRotation = camera.yRotation + 0.04
		local s = math.sin(camera.yRotation)
		local c = math.cos(camera.yRotation)
		local distance = 2
		camera.x = s * distance
		camera.z = c * distance
		framebuffer:clear(colours.white)
		pipeline:render_geometry(geometry_list, framebuffer, camera)
		framebuffer:blit_subpixel(term)
		sleep(0.05)
	end
end)

term.setPaletteColour(colours.lightGrey, term.nativePaletteColour(colours.lightGrey))
term.setPaletteColour(colours.grey, term.nativePaletteColour(colours.grey))
