
local v3d = require '/v3d'

local framebuffer = v3d.create_framebuffer_subpixel(v3d.COLOUR_DEPTH_FORMAT, term.getSize())
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
        local cx = 0.5 + math.sin(-uniforms.t * 3) * 0.2
        local cy = 0.5 + math.cos(-uniforms.t * 3) * 0.2
        if (math.sqrt((u - cx) ^ 2 + (v - cy) ^ 2) - uniforms.t / 5) % 0.2 < 0.1 then
            -- here, we're not inside the circle, so discard the pixel
            return nil
        end

        return 2 ^ (1 + math.floor(fi / 2))
    end,
}
local cube = v3d.create_debug_cube():cast(layout):build()
pipeline:set_uniform('t', 0.1)

local rotation = 0
while true do
    rotation = rotation + 0.04
    local s = math.sin(rotation)
    local c = math.cos(rotation)
    local distance = 2
    local transform = v3d.camera(s * distance, 0, c * distance, rotation)
    framebuffer:clear('colour', colours.white)
	framebuffer:clear('depth')
    pipeline:render_geometry(cube, framebuffer, transform)
    framebuffer:blit_term_subpixel(term)
    pipeline:set_uniform('t', pipeline:get_uniform 't' + 0.05)
    sleep(0.05)
end
