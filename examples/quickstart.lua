
-- Import the library.
local v3d = require '/v3d'

-- Create a framebuffer to draw to.
local width, height = term.getSize()
local framebuffer = v3d.create_framebuffer_subpixel(width, height, 'Screen buffer')

-- Create a camera.
local camera = v3d.create_camera(nil, 'Camera')

-- Move the camera to Z=2 so we are looking at the origin from a distance.
camera:set_position(0, 0, 2)

-- TODO
local layout = v3d.create_layout()
	:add_attribute('position', 3, 'vertex', true)
	:add_attribute('uv', 2, 'vertex', true)
	:add_attribute('colour', 3, 'face', false)

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

-- Track when we want to draw the next frame.
local next_frame_time = os.clock()

-- Store the target framerate.
local target_framerate = _HOST and _HOST:find 'Accelerated' and 100000 or 20

-- Track when we last updated so we can rotate geometry at a fixed rate.
local last_update_time = os.clock()

-- Run a loop to repeatedly draw.
while true do
	-- Clear the framebuffer to black
	framebuffer:clear(colours.black)

	-- Render the outer cube using the transparent pipeline so it's textured
	-- using the window image we defined above.
	transparent_pipeline:render_geometry(cube1, framebuffer, camera)

	-- Draw the cube again but using the effect pipeline to draw expanding
	-- circles in the transparent section of the glass.
	effect_pipeline:render_geometry(cube1, framebuffer, camera)

	-- Render the inner cube using the default pipeline so it's textured with
	-- a unique colour per triangle.
	default_pipeline:render_geometry(cube2, framebuffer, camera)

	-- Draw the framebuffer to the screen.
	framebuffer:blit_subpixel(term, 0, 0)

	-- Wait a short amount of time.
	sleep(next_frame_time - os.clock())
	next_frame_time = math.max(os.clock(), next_frame_time + 1 / target_framerate)

	-- Rotate the cubes.
	local now = os.clock()
	local dt = now - last_update_time
	last_update_time = now
	-- cube1:rotate_y(1.0 * dt)
	-- cube2:rotate_y(0.8 * dt)
	-- cube2:rotate_z(0.6 * dt)
	
	-- Update the time uniform for the effect pipeline.
	local new_time = effect_pipeline:get_uniform 'u_time' + dt

	-- If we've gone past a second, reset the animation from a new centre point.
	if new_time >= 1 then
		effect_pipeline:set_uniform('u_centre_x', math.random(1, 9) / 10)
		effect_pipeline:set_uniform('u_centre_y', math.random(1, 9) / 10)
		new_time = new_time % 1
	end

	-- Set the time uniform.
	effect_pipeline:set_uniform('u_time', new_time)

	-- Update the palette colour for the effect so we get a gradient transition
	-- over time.
	term.setPaletteColour(colours.lightGrey, 0.3 * new_time + 0.3 * (1 - new_time), 0.6 * new_time + 0.9 * (1 - new_time), 0.9 * new_time + 0.3 * (1 - new_time))
end
