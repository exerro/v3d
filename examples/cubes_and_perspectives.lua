
local v3d = require '/v3d'

local framebuffer = v3d.create_framebuffer_subpixel(51, 19)
local camera = v3d.create_camera()
local pipeline = v3d.create_pipeline()
local geometry_list = {}

-- Create two cubes, one large central one, and a smaller one to the side.
geometry_list[1] = v3d.create_debug_cube()
geometry_list[2] = v3d.create_debug_cube(-2, 0, 0, 0.5)

while true do
    -- Rotate the camera every frame.
    camera.yRotation = camera.yRotation + 0.04

    -- Position the camera every frame so it's looking at the centre.
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
