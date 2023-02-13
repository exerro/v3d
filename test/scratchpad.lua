
shell.run '/v3d/build'

local v3d = require '/v3d'

-- local framebuffer = v3d.create_framebuffer_subpixel(term.getSize())
-- local camera = v3d.create_camera()
-- local layout = v3d.UV_LAYOUT
--     :add_vertex_attribute('b', 4, true)
--     :add_face_attribute('face_index', 1)
--     :add_face_attribute('colour', 1)
--     -- :add_face_attribute('colour', 1)
-- local pipeline = v3d.create_pipeline {
--     -- cull_face = v3d.CULL_FRONT_FACE,
--     -- depth_test = false,
--     layout = layout,
--     position_attribute = 'position',
--     attributes = { 'face_index', 'uv', 'colour' },
--     pack_attributes = true,
--     -- colour_attribute = 'colour',
--     fragment_shader = function(_, attr)
--         if attr.face_index[1] % 2 == 1 then
--             return attr.colour[1]
--         end
--         local index = 1
--         local b = attr.uv
--         for i = 2, 2 do
--             if b[i] > b[index] then
--                 index = i
--             end
--         end
--         return ({ colours.red, colours.green, colours.blue, colours.yellow })[index]
-- 	end,
-- }
-- local h = assert(io.open('/v3d/build/pipeline_source.lua', 'w'))
-- h:write(pipeline.source)
-- h:close()
-- if not pipeline.render_geometry then
--     error(pipeline.source_error)
-- end
-- local geometry = v3d.create_debug_cube()
--     :cast(layout)
--     :set_data('b', { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 })
--     :build()

-- while true do
--     -- Rotate the camera every frame.
--     camera.yRotation = camera.yRotation + 0.04

--     -- Position the camera every frame so it's looking at the centre.
--     local s = math.sin(camera.yRotation)
--     local c = math.cos(camera.yRotation)
--     local distance = 2

--     camera.x = s * distance
--     camera.z = c * distance

--     framebuffer:clear(colours.white)
--     pipeline:render_geometry(geometry, framebuffer, camera)
--     framebuffer:blit_term_subpixel(term)
--     sleep(0.05)
-- end

-- Create a framebuffer to draw to.
term.setGraphicsMode(1)
local width, height = term.getSize(2)
local framebuffer = v3d.create_framebuffer(width, height, 'Screen buffer')

-- Create a camera.
local camera = v3d.create_camera(nil, 'Camera')

-- Move the camera to Z=2 so we are looking at the origin from a distance.
camera:set_position(0, 0, 2)

-- TODO
local layout = v3d.create_layout()
	:add_vertex_attribute('position', 3, true)
	:add_vertex_attribute('uv', 2, true)
	:add_face_attribute('colour', 1)

-- Create a large cube at the origin.
local cube1 = v3d.create_debug_cube(0, 0, 0, 1):cast(layout):build('Large cube')

-- Create a small cube at the origin.
local cube2 = v3d.create_debug_cube(0, 0, 0, 0.5):cast(layout):build('Small cube')

-- Rotate the small cube pi radians.
-- cube2:rotate_y(math.pi)

-- Create a default pipeline to draw the inner cube without using any shaders.
local default_pipeline = v3d.create_pipeline {
	layout = layout,
	colour_attribute = 'colour',
}

-- Create a second pipeline to draw the outer cube using a texture sampler
-- shader.
local transparent_pipeline = v3d.create_pipeline {
	layout = layout,
	-- Disable face culling so we can see the rear faces as well as the front
	-- ones.
	cull_face = false,
	-- Instruct V3D to interpolate UV values for every pixel drawn.
	attributes = { 'uv' },
	pack_attributes = false,
	-- Provide a texture sampler as the fragment shader for this pipeline - each
	-- pixel will be drawn by asking the texture sampler for the colour at the
	-- corresponding UV value in the texture. The texture is set below.
	fragment_shader = v3d.create_texture_sampler()
}

local h = assert(io.open('/v3d/build/pipeline_source.lua', 'w'))
h:write(transparent_pipeline.source)
h:close()

-- Create a third pipeline to render an effect over the outer cube using a
-- fragment shader.
local effect_pipeline = v3d.create_pipeline {
	layout = layout,
	-- Disable face culling for the same reason as above.
	cull_face = false,
	-- We need UVs to compute the effect.
	attributes = { 'uv' },
	pack_attributes = false,
	-- We define the effect in a custom fragment shader.
	fragment_shader = function(uniforms, u, v)
		local distance = math.sqrt((u - uniforms.u_centre_x) ^ 2 + (v - uniforms.u_centre_y) ^ 2)

		if (distance - uniforms.u_time) % 1 < 0.9 then
			return nil
		end

		return colours.lightGrey
	end,
}

-- Define a 'window' texture which we'll need to load and then assign to the
-- second pipeline.
local transparent_image_content = [[
7777777777777777
77   7    7   77
7   7      7   7
7  7        7  7
7 7          7 7
77        0   77
7        0     7
7              7
7              7
7     0        7
77   0        77
7 7          7 7
7  7        7  7
7   7      7   7
77   7    7   77
7777777777777777]]

-- Load the image.
local transparent_image = paintutils.parseImage(transparent_image_content)

-- Set the image by assigning uniform variables in the second pipeline.
transparent_pipeline:set_uniform('u_texture', transparent_image)
transparent_pipeline:set_uniform('u_texture_width', 16)
transparent_pipeline:set_uniform('u_texture_height', 16)

-- Set the initial uniforms for the effect shader.
effect_pipeline:set_uniform('u_time', 0)
effect_pipeline:set_uniform('u_centre_x', 0.3)
effect_pipeline:set_uniform('u_centre_y', 0.4)

local next_frame_time = os.clock()
local target_framerate = _HOST and _HOST:find 'Accelerated' and 100000 or 20
local last_update_time = os.clock()
local t = 0

local ok, err

while true do
	local n = 3
	local s = 2

	framebuffer:clear(colours.black)

	for z = 0, n do
	for x = -z, z do
		for y = -math.max(0, z - 1), math.max(0, z - 1) do
				local this_camera = v3d.create_camera(camera.fov)
				this_camera:set_position(camera.x + x * s, camera.y + y * s, camera.z + z * s)
				this_camera:set_rotation(camera.xRotation, camera.yRotation, camera.zRotation)

				transparent_pipeline:render_geometry(cube1, framebuffer, this_camera)
				effect_pipeline:render_geometry(cube1, framebuffer, this_camera)
				default_pipeline:render_geometry(cube2, framebuffer, this_camera)
			end
		end
	end

	ok, err = pcall(function()
		framebuffer:blit_graphics(term.native(), 0, 0)
		-- framebuffer:blit_graphics_depth(term.native(), 0, 0)
	end)
	if not ok then break end

	if not pcall(sleep, next_frame_time - os.clock()) then
		break
	end

	next_frame_time = math.max(os.clock(), next_frame_time + 1 / target_framerate)

	local now = os.clock()
	local dt = now - last_update_time
	last_update_time = now
	local new_time = effect_pipeline:get_uniform 'u_time' + dt

	t = t + dt
	camera:set_rotation(0, math.cos(t * 3) * 0.3, math.sin(t * 2) * 0.2)
	camera:set_position(math.sin(camera.yRotation) * 2, 0, math.cos(camera.yRotation) * 2)

	if new_time >= 1 then
		effect_pipeline:set_uniform('u_centre_x', math.random(1, 9) / 10)
		effect_pipeline:set_uniform('u_centre_y', math.random(1, 9) / 10)
		new_time = new_time % 1
	end

	effect_pipeline:set_uniform('u_time', new_time)
	term.setPaletteColour(colours.lightGrey, 0.3 * new_time + 0.3 * (1 - new_time), 0.6 * new_time + 0.9 * (1 - new_time), 0.9 * new_time + 0.3 * (1 - new_time))
end

term.setGraphicsMode(false)

for i = 0, 15 do
	term.setPaletteColour(2 ^ i, term.nativePaletteColour(2 ^ i))
end

if not ok then
	error(err)
end
