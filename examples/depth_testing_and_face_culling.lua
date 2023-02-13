
local v3d = require '/v3d'

local framebuffer = v3d.create_framebuffer_subpixel(term.getSize())
local camera = v3d.create_camera()
local pipeline = v3d.create_pipeline {
    layout = v3d.DEFAULT_LAYOUT,
    colour_attribute = 'colour',
    depth_test = false,
}

-- Create two cubes, one large central one, and a smaller one inside it.
local large_cube = v3d.create_debug_cube():cast(v3d.DEFAULT_LAYOUT):build()
local small_cube = v3d.create_debug_cube(0, 0, 0, 0.5):cast(v3d.DEFAULT_LAYOUT):build()
-- small_cube:rotate_y(math.pi) -- rotate the object 180 degrees

while true do
    camera.yRotation = camera.yRotation + 0.04
    local s = math.sin(camera.yRotation)
    local c = math.cos(camera.yRotation)
    local distance = 2
    camera.x = s * distance
    camera.z = c * distance
    framebuffer:clear(colours.white)
    pipeline:render_geometry(large_cube, framebuffer, camera)
    pipeline:render_geometry(small_cube, framebuffer, camera)
    framebuffer:blit_term_subpixel(term)
    sleep(0.05)
end
