
local v3d = require '/v3d'

local framebuffer = v3d.create_framebuffer_subpixel(term.getSize())
local camera = v3d.create_camera()
local pipeline = v3d.create_pipeline {
    layout = v3d.DEFAULT_LAYOUT,
    cull_face = false,
    colour_attribute = 'colour',
    fragment_shader = function(uniforms)
        if uniforms.u_faceID % 2 == 1 then
            return nil
        end
        return uniforms.u_face_colour * 2 ^ uniforms.u_instanceID
    end,
}
local large_cube = v3d.create_debug_cube():cast(v3d.DEFAULT_LAYOUT):build()
local small_cube = v3d.create_debug_cube(-2, 0, 0, 0.5):cast(v3d.DEFAULT_LAYOUT):build()

while true do
    camera.yRotation = camera.yRotation + 0.04
    local s = math.sin(camera.yRotation)
    local c = math.cos(camera.yRotation)
    local distance = 2
    camera.x = s * distance
    camera.z = c * distance
    framebuffer:clear(colours.white)
    pipeline:set_uniform('u_instanceID', 0)
    pipeline:render_geometry(large_cube, framebuffer, camera)
    pipeline:set_uniform('u_instanceID', 1)
    pipeline:render_geometry(small_cube, framebuffer, camera)
    framebuffer:blit_subpixel(term)
    sleep(0.05)
end
