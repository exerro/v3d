
shell.run '/v3d/build'

local v3d = require '/v3d'

local framebuffer = v3d.create_framebuffer_subpixel(term.getSize())
local camera = v3d.create_camera()
local layout = v3d.UV_LAYOUT
    :add_vertex_attribute('b', 4, true)
    :add_face_attribute('face_index', 1)
    :add_face_attribute('colour', 1)
    -- :add_face_attribute('colour', 1)
local pipeline = v3d.create_pipeline {
    -- cull_face = v3d.CULL_FRONT_FACE,
    -- depth_test = false,
    layout = layout,
    position_attribute = 'position',
    attributes = { 'face_index', 'uv', 'colour' },
    pack_attributes = true,
    -- colour_attribute = 'colour',
    fragment_shader = function(_, attr)
        if attr.face_index[1] % 2 == 1 then
            return attr.colour[1]
        end
        local index = 1
        local b = attr.uv
        for i = 2, 2 do
            if b[i] > b[index] then
                index = i
            end
        end
        return ({ colours.red, colours.green, colours.blue, colours.yellow })[index]
	end,
}
local h = assert(io.open('/v3d/build/pipeline_source.lua', 'w'))
h:write(pipeline.source)
h:close()
if not pipeline.render_geometry then
    error(pipeline.source_error)
end
local geometry = v3d.create_debug_cube()
    :cast(layout)
    :set_data('b', { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 })
    :build()

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
    pipeline:render_geometry(geometry, framebuffer, camera)
    framebuffer:blit_subpixel(term)
    sleep(0.05)
end
