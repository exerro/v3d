
local v3d = require '/v3d'

local framebuffer = v3d.create_framebuffer_subpixel(v3d.COLOUR_DEPTH_FORMAT, term.getSize())
local pipeline = v3d.create_pipeline {
    layout = v3d.DEBUG_CUBE_LAYOUT,
    cull_face = false,
    attributes = { 'colour', 'face_index' },
    colour_attribute = 'colour',
    pack_attributes = false,
    fragment_shader = function(uniforms, colour, face_index)
        if face_index % 2 == 0 then
            return nil
        end
        return colour * 2 ^ uniforms.u_instanceID
    end,
}
local large_cube = v3d.create_debug_cube():cast(v3d.DEBUG_CUBE_LAYOUT):build()
local small_cube = v3d.create_debug_cube(-2, 0, 0, 0.5):cast(v3d.DEBUG_CUBE_LAYOUT):build()

local rotation = 0
while true do
    rotation = rotation + 0.04
    local s = math.sin(rotation)
    local c = math.cos(rotation)
    local distance = 2
    local transform = v3d.camera(s * distance, 0, c * distance, rotation)
    framebuffer:clear('colour', colours.white)
	framebuffer:clear('depth')
    pipeline:set_uniform('u_instanceID', 0)
    pipeline:render_geometry(large_cube, framebuffer, transform)
    pipeline:set_uniform('u_instanceID', 1)
    pipeline:render_geometry(small_cube, framebuffer, transform)
    framebuffer:blit_term_subpixel(term)
    sleep(0.05)
end
