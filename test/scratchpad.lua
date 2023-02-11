
shell.run '/v3d/build'

--- @type v3d
local v3d = require '/v3d'

local framebuffer = v3d.create_framebuffer_subpixel(term.getSize())
local camera = v3d.create_camera()
local layout = v3d.create_layout()
    :add_attribute('position', 3, 'vertex', true)
    -- :add_attribute('uv', 2, 'vertex', true)
    :add_attribute('colour', 1, 'face', false)
local pipeline = v3d.create_pipeline {
    cull_face = v3d.CULL_FRONT_FACE,
    -- depth_test = false,
    layout = layout,
    position_attribute = 'position',
    -- interpolate_attribute = 'uv',
    colour_attribute = 'colour',
    -- fragment_shader = function(_, u, v)
	-- 	return 2 ^ (math.min(math.floor(u * 4), 3) * 4 + math.min(math.floor(v * 4), 3))
	-- end,
}
local geometry = v3d.create_debug_cube()
    :cast(layout)
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
