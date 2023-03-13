
local window_origin = { 232.5, 72.5, 93 }
local window_width = 5
local window_height = 3
local detector = peripheral.find 'playerDetector'

local v3d = require '/v3d'

local width, height = term.getSize()
local screen_framebuffer = v3d.create_framebuffer_subpixel(v3d.COLOUR_DEPTH_FORMAT, width, height)
local framebuffer = v3d.create_framebuffer(v3d.COLOUR_DEPTH_FORMAT, math.floor(200 * width / height + 0.5), 200)

local transform = v3d.translate(0, 0, -2)

local layout = v3d.create_layout()
	:add_vertex_attribute('position', 3, true)
	:add_vertex_attribute('uv', 2, true)
	:add_face_attribute('colour', 1)

local cube1 = v3d.create_debug_cube(0, 0, 0, 1):cast(layout):build()
-- local cube2 = v3d.create_debug_cube(0, 0, 0, 0.5):cast(layout):build()

local floor = v3d.create_geometry_builder(layout)
	:append_data('position', { -window_width / 2, -window_height / 2, 0, window_width / 2, -window_height / 2, 0, -window_width / 2, -window_height / 2, -2 })
	:append_data('uv', { 0, 1, 1, 1, 0, 0 })
	:append_data('colour', { colours.green })
	:append_data('position', { -window_width / 2, -window_height / 2, 0, -window_width / 2, -window_height / 2, -2, -window_width / 2, window_height / 2, 0 })
	:append_data('uv', { 0, 1, 1, 1, 0, 0 })
	:append_data('colour', { colours.red })
	:build()

local floor = v3d.create_debug_cube(0, 0, -1, 2):cast(layout):build()
local floor_transform = v3d.scale(window_width / 2, window_height / 2, 2)

local default_pipeline = v3d.create_pipeline {
	layout = layout,
	cull_face = v3d.CULL_FRONT_FACE,
	colour_attribute = 'colour',
}

local transparent_pipeline = v3d.create_pipeline {
	layout = layout,
	cull_face = false,
	attributes = { 'uv' },
	pack_attributes = false,
	fragment_shader = v3d.create_texture_sampler()
}

local effect_pipeline = v3d.create_pipeline {
	layout = layout,
	cull_face = false,
	attributes = { 'uv' },
	pack_attributes = false,
	fragment_shader = function(uniforms, u, v)
		local distance = math.sqrt((u - uniforms.u_centre_x) ^ 2 + (v - uniforms.u_centre_y) ^ 2)
		if (distance - uniforms.u_time) % 1 < 0.9 then
			return nil
		end
		return colours.lightGrey
	end,
}

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

local transparent_image = paintutils.parseImage(transparent_image_content)

transparent_pipeline:set_uniform('u_texture', transparent_image)
transparent_pipeline:set_uniform('u_texture_width', 16)
transparent_pipeline:set_uniform('u_texture_height', 16)

effect_pipeline:set_uniform('u_time', 0)
effect_pipeline:set_uniform('u_centre_x', 0.3)
effect_pipeline:set_uniform('u_centre_y', 0.4)

local next_frame_time = os.clock()
local target_framerate = _HOST and _HOST:find 'Accelerated' and 100000 or 20
local last_update_time = os.clock()

local draw_raw = false
local update_position = true
local player_pos = detector.getPlayerPos(detector.getOnlinePlayers()[1])
local rednet_player_pos = nil

parallel.waitForAny(function()
	while true do
		if update_position then
			if commands then
				local pos_str = select(2, commands.exec 'data get entity @p[limit=1,gamemode=!spectator] Pos')[1]
				local rot_str = select(2, commands.exec 'data get entity @p[limit=1,gamemode=!spectator] Rotation')[1]
				local x_str, y_str, z_str = pos_str:match '%[(%-?[%d%.]+)d,%s*(%-?[%d%.]+)d,%s*(%-?[%d%.]+)d%]'
				local yr_str, xr_str = rot_str:match '%[(%-?[%d%.]+)f,%s*(%-?[%d%.]+)f%]'

				player_pos = {
					x = tonumber(x_str), y = tonumber(y_str), z = tonumber(z_str),
					pitch = tonumber(xr_str), yaw = tonumber(yr_str), roll = 0,
					eyeHeight = 1.62,
				}
			else
				player_pos = detector.getPlayerPos(detector.getOnlinePlayers()[1])
				if rednet_player_pos then
					player_pos.x = rednet_player_pos[1]
					player_pos.y = rednet_player_pos[2] - player_pos.eyeHeight
					player_pos.z = rednet_player_pos[3]
				end
			end
		end

		local view_transform = v3d.camera(
			-(player_pos.x - window_origin[1]), player_pos.y - window_origin[2] + player_pos.eyeHeight, -(player_pos.z - window_origin[3]),
			player_pos.pitch / 180 * math.pi, -player_pos.yaw / 180 * math.pi, 0,
			70 / 180 * math.pi)
		local model_transform = view_transform * transform
		local floor_vm_transform = view_transform * floor_transform

		framebuffer:clear('colour', colours.black)
		framebuffer:clear('depth')
		transparent_pipeline:render_geometry(cube1, framebuffer, model_transform)
		effect_pipeline:render_geometry(cube1, framebuffer, model_transform)
		-- default_pipeline:render_geometry(cube2, framebuffer, model_transform)
		default_pipeline:render_geometry(floor, framebuffer, floor_vm_transform)

		if not draw_raw then
			local sf_colour = screen_framebuffer:get_buffer 'colour'
			local sf_width_1 = screen_framebuffer.width - 1
			local sf_height_1 = screen_framebuffer.height - 1
			local f_colour = framebuffer:get_buffer 'colour'
			local f_width = framebuffer.width
			local f_height = framebuffer.height
			local f_width_1_2 = (framebuffer.width - 1) / 2
			local f_height_1_2 = (framebuffer.height - 1) / 2
			local vtt = view_transform.transform
			local world_pos = { 0, 0, 0 }
			local math_floor = math.floor
			local index = 1
			local black = colours.black

			for y = 0, sf_height_1 do
				for x = 0, sf_width_1 do
					-- coords in world of pixel (relative to origin)
					world_pos[1] = (x / sf_width_1 - 0.5) * window_width
					world_pos[2] = -(y / sf_height_1 - 0.5) * window_height

					-- find pixel in framebuffer
					local v = vtt(view_transform, world_pos, true)
					local vz = v[3]

					local fx = math_floor(f_width_1_2 + v[1] / -vz * f_height_1_2)
					local fy = math_floor(f_height_1_2 - v[2] / -vz * f_height_1_2)

					if fx < 0 or fx >= f_width or fy < 0 or fy >= f_height then
						sf_colour[index] = black
					else
						sf_colour[index] = f_colour[fy * f_width + fx + 1] or black
					end

					index = index + 1
				end
			end
		end

		if draw_raw then
			framebuffer:blit_term_subpixel(term.current(), 0, 0)
		else
			screen_framebuffer:blit_term_subpixel(term.current(), 0, 0)
		end

		sleep(next_frame_time - os.clock())
		next_frame_time = math.max(os.clock(), next_frame_time + 1 / target_framerate)

		local now = os.clock()
		local dt = now - last_update_time
		last_update_time = now

		transform = transform * v3d.rotate(0.4 * dt, 0.5 * dt, 0.1 * dt)

		local new_time = effect_pipeline:get_uniform 'u_time' + dt

		if new_time >= 1 then
			effect_pipeline:set_uniform('u_centre_x', math.random(1, 9) / 10)
			effect_pipeline:set_uniform('u_centre_y', math.random(1, 9) / 10)
			new_time = new_time % 1
		end

		effect_pipeline:set_uniform('u_time', new_time)
		term.setPaletteColour(colours.lightGrey, 0.3 * new_time + 0.3 * (1 - new_time), 0.6 * new_time + 0.9 * (1 - new_time), 0.9 * new_time + 0.3 * (1 - new_time))
	end
end, function()
	local event = { os.pullEvent 'chat' }

	while true do
		if event[3] == 'raw' then
			draw_raw = not draw_raw
		elseif event[3] == 'pos' then
			update_position = not update_position
		end
		event = { os.pullEvent 'chat' }
	end
end, function()
	local event = { os.pullEvent 'rednet_message' }

	while true do
		rednet_player_pos = event[3]
		event = { os.pullEvent 'rednet_message' }
	end
end)
