
local v3d = require '/v3d'

local framebuffer = v3d.create_framebuffer_subpixel(term.getSize())
local camera = v3d.create_camera()
local layout = v3d.create_layout()
    :add_vertex_attribute('position', 3, true)
    :add_vertex_attribute('uv', 2, true)
    :add_face_attribute('face_index', 1)
local pipeline = v3d.create_pipeline {
    layout = layout,
    cull_face = false,
    -- instruct V3D to interpolate the UV values
    -- without this, they will always equal 0
	attributes = { 'uv', 'face_index' },
	pack_attributes = false,
    fragment_shader = function(uniforms, u, v, fi)
        if math.sqrt((u - 0.3) ^ 2 + (v - 0.3) ^ 2) % 0.2 < 0.1 then
            -- here, we're not inside the circle, so discard the pixel
            return nil
        end

        return 2 ^ (1 + math.floor(fi / 2))
    end,
}
local cube = v3d.create_debug_cube():cast(layout):build()

while true do
    camera.yRotation = camera.yRotation + 0.04
    local s = math.sin(camera.yRotation)
    local c = math.cos(camera.yRotation)
    local distance = 2
    camera.x = s * distance
    camera.z = c * distance
    framebuffer:clear(colours.white)
    pipeline:render_geometry(cube, framebuffer, camera)
    framebuffer:blit_term_subpixel(term)
    sleep(0.05)
end
