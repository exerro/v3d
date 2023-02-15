
local v3d = require '/v3d'

local framebuffer = v3d.create_framebuffer_subpixel(term.getSize())
local transform = v3d.camera(0, 0, 2)
local pipeline = v3d.create_pipeline {
    layout = v3d.DEBUG_CUBE_LAYOUT,
    colour_attribute = 'colour',
}

local geometry = v3d.create_debug_cube():build()

while true do
    -- transform = transform * v3d.rotate(0.05, 0.1, 0.2)
    transform = transform * v3d.rotate(0, 0.05, 0) * v3d.scale(0.99, 1, 1)

    framebuffer:clear(colours.white)
    pipeline:render_geometry(geometry, framebuffer, transform)
    framebuffer:blit_term_subpixel(term)
    sleep(0.05)
end
