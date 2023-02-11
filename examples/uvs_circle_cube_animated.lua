
local v3d = require '/v3d'

local framebuffer = v3d.create_framebuffer_subpixel(term.getSize())
local camera = v3d.create_camera()
local pipeline = v3d.create_pipeline {
    layout = v3d.UV_LAYOUT,
    cull_face = v3d.CULL_FRONT_FACE,
    -- instruct V3D to interpolate the UV values
    -- without this, they will always equal 0
    interpolate_attribute = 'uv',
    fragment_shader = function(uniforms, u, v)
        local cx = 0.5 + math.sin(-uniforms.t * 3) * 0.2
        local cy = 0.5 + math.cos(-uniforms.t * 3) * 0.2
        if (math.sqrt((u - cx) ^ 2 + (v - cy) ^ 2) - uniforms.t / 5) % 0.2 < 0.1 then
            -- here, we're not inside the circle, so discard the pixel
            return nil
        end

        return 2 ^ (1 + math.floor(uniforms.t) % 10)
    end,
}
local cube = v3d.create_debug_cube():cast(v3d.UV_LAYOUT):build()
pipeline:set_uniform('t', 0.1)

while true do
    camera.yRotation = camera.yRotation + 0.04
    local s = math.sin(camera.yRotation)
    local c = math.cos(camera.yRotation)
    local distance = 2
    camera.x = s * distance
    camera.z = c * distance
    framebuffer:clear(colours.white)
    pipeline:render_geometry(cube, framebuffer, camera)
    framebuffer:blit_subpixel(term)
    pipeline:set_uniform('t', pipeline:get_uniform 't' + 0.05)
    sleep(0.05)
end
