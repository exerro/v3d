local v3d = require '/v3d'

local framebuffer = v3d.create_framebuffer_subpixel(term.getSize())
local geometry = v3d.create_debug_cube():build()
local transform = v3d.camera(0, 0, 2, 0, math.pi / 2)
local pipeline = v3d.create_pipeline {
	layout = v3d.DEBUG_CUBE_LAYOUT,
	colour_attribute = 'colour',
}

while true do
    transform = transform * v3d.rotate(0, 0.05, 0)
    framebuffer:clear(colours.black)
    pipeline:render_geometry(geometry, framebuffer, transform)
    framebuffer:blit_term_subpixel(term)
    sleep(0.05)
end