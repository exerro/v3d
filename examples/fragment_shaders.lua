
local v3d = require '/v3d'

local framebuffer = v3d.create_framebuffer_subpixel(term.getSize())
local camera = v3d.create_camera()
local pipeline = v3d.create_pipeline {
    cull_face = false,
    fragment_shader = function(uniforms)
        if uniforms.u_faceID % 2 == 1 then
            return nil
        end
        return 2 ^ (1 + uniforms.u_faceID / 2)
    end,
}
local geometry_list = {}
geometry_list[1] = v3d.create_debug_cube()
geometry_list[2] = v3d.create_debug_cube(-2, 0, 0, 0.5)

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
