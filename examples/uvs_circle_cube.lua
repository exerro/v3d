
local v3d = require '/v3d'

local framebuffer = v3d.create_framebuffer_subpixel(term.getSize())
local camera = v3d.create_camera()
local pipeline = v3d.create_pipeline {
    cull_face = false,
    -- instruct V3D to interpolate the UV values
    -- without this, they will always equal 0
    interpolate_uvs = true,
    fragment_shader = function(uniforms, u, v)
        if math.sqrt((u - 0.3) ^ 2 + (v - 0.3) ^ 2) % 0.2 < 0.1 then
            -- here, we're not inside the circle, so discard the pixel
            return nil
        end

        return 2 ^ (1 + math.floor(uniforms.u_faceID / 2 + 0.5))
    end,
}
local geometry_list = {}
geometry_list[1] = v3d.create_debug_cube()

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
