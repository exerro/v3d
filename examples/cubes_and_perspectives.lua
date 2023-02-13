
local v3d = require '/v3d'

local framebuffer = v3d.create_framebuffer_subpixel(term.getSize())
local pipeline = v3d.create_pipeline {
    layout = v3d.DEFAULT_LAYOUT,
    colour_attribute = 'colour',
}

-- Create two cubes, one large central one, and a smaller one to the side.
local large_cube = v3d.create_debug_cube():cast(v3d.DEFAULT_LAYOUT):build()
local small_cube = v3d.create_debug_cube(-2, 0, 0, 0.5):cast(v3d.DEFAULT_LAYOUT):build()

-- Track rotation over time - we'll update this every frame.
local rotation = 0

while true do
    rotation = rotation + 0.04

    -- Calculate a transform every frame that's rotating and looking at the
    -- centre.
    local s = math.sin(rotation)
    local c = math.cos(rotation)
    local distance = 2
    local transform = v3d.camera(s * distance, 0, c * distance, rotation)

    framebuffer:clear(colours.white)
    pipeline:render_geometry(large_cube, framebuffer, transform)
    pipeline:render_geometry(small_cube, framebuffer, transform)
    framebuffer:blit_term_subpixel(term)
    sleep(0.05)
end
