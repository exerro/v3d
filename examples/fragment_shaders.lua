
-- TODO: broken, need to redo the whole guide for fragment shaders (and many
--       other things tbh)

local v3d = require '/v3d'

local framebuffer = v3d.create_framebuffer_subpixel(term.getSize())
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

local rotation = 0
while true do
    rotation = rotation + 0.04
    local s = math.sin(rotation)
    local c = math.cos(rotation)
    local distance = 2
    local transform = v3d.camera(s * distance, 0, c * distance, rotation)
    framebuffer:clear(colours.white)
    pipeline:set_uniform('u_instanceID', 0)
    pipeline:render_geometry(large_cube, framebuffer, transform)
    pipeline:set_uniform('u_instanceID', 1)
    pipeline:render_geometry(small_cube, framebuffer, transform)
    framebuffer:blit_term_subpixel(term)
    sleep(0.05)
end
