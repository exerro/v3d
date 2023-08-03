
local v3d = require '/v3d'

local framebuffer = v3d.create_framebuffer_subpixel(v3d.COLOUR_DEPTH_FORMAT, term.getSize())
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

local rotation = 0
while true do
    rotation = rotation + 0.04
    local s = math.sin(rotation)
    local c = math.cos(rotation)
    local distance = 2
    local transform = v3d.camera(s * distance, 0, c * distance, rotation)
	framebuffer:clear('colour', colours.white)
	framebuffer:clear('depth')
	pipeline:render_geometry(cube, framebuffer, transform)
	framebuffer:blit_term_subpixel(term, 'colour')
	sleep(0.05)
end
