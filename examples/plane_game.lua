
if fs.isDir 'v3d' then shell.run 'v3d/build' end
package.path = "/" .. fs.getDir(shell.getRunningProgram()) .. "/?.lua;" .. package.path
package.path = "/" .. fs.getDir(fs.getDir(shell.getRunningProgram())) .. "/?.lua;" .. package.path
package.path = "/?.lua;" .. package.path
local v3d = require 'v3d'
local simplex = require 'util.simplex'
--- @diagnostic disable-next-line: undefined-field
local startTimer = os.startTimer

-- constants
local REFRESH_INTERVAL = 0.05
local CHUNK_SIZE = 21
local CHUNK_TILING = 20
local CHUNK_LOG_DIVISIONS = 4
local CHUNK_MAX_HEIGHT = 15 -- kinda arbitrary, used for visibility tests
local CHUNK_MIN_HEIGHT = -5 -- kinda arbitrary, used for visibility tests
local MOUNTAIN_SCALER = 10
local PLANE_YAW_RATE = 0.15
local PLANE_PITCH_RATE = 0.4
local PLANE_ROLL_RATE = 0.8
local PLANE_ACCELERATION = 0.5
local PLANE_MIN_SPEED = 1
local PLANE_MAX_SPEED = 5
local PLANE_CAMERA_FORWARD_DISTANCE = -2
local PLANE_CAMERA_UP_DISTANCE = 1
local PLANE_CAMERA_X_ROTATION_DELTA = math.atan(PLANE_CAMERA_UP_DISTANCE / PLANE_CAMERA_FORWARD_DISTANCE)

-- set up graphics state
local screen_width, screen_height = term.getSize()
local framebuffer = v3d.create_framebuffer_subpixel(screen_width, screen_height)
local camera = v3d.create_camera(math.pi / 6)
local terrain_pipeline = v3d.create_pipeline {
	interpolate_uvs = true,
	fragment_shader = function(uniforms, u, v)
		local mountain_threshold = MOUNTAIN_SCALER / 3 + u
		if v > mountain_threshold then
			local mountain_scalar = 1 / (MOUNTAIN_SCALER - mountain_threshold)
			return 2 ^ math.min(11, math.floor(9 + (v - mountain_threshold) * mountain_scalar * 5))
		end
		return 2 ^ math.floor((u + 1) * 3)
	end,
}
local chunks = {}
local initial_palette = {}
for i = 0, 15 do
	initial_palette[i + 1] = { term.getPaletteColour(2 ^ i) }
end

term.setPaletteColour(2 ^  0, 0x26/255, 0x58/255, 0x28/255) -- green 0 (darkest)
term.setPaletteColour(2 ^  1, 0x2e/255, 0x69/255, 0x30/255) -- green 1
term.setPaletteColour(2 ^  2, 0x35/255, 0x7a/255, 0x38/255) -- green 2
term.setPaletteColour(2 ^  3, 0x3d/255, 0x8c/255, 0x40/255) -- green 3
term.setPaletteColour(2 ^  4, 0x44/255, 0x9e/255, 0x48/255) -- green 4
term.setPaletteColour(2 ^  5, 0x4c/255, 0xaf/255, 0x50/255) -- green 5 (lightest)
term.setPaletteColour(2 ^  6, 0xa6/255, 0xda/255, 0xf4/255) -- blue 0 (darkest)
term.setPaletteColour(2 ^  7, 0xc1/255, 0xe5/255, 0xf7/255) -- blue 1
term.setPaletteColour(2 ^  8, 0xdb/255, 0xf0/255, 0xfb/255) -- blue 2 (lightest)
term.setPaletteColour(2 ^  9, 0xaa/255, 0xaa/255, 0xaa/255) -- grey 0 (darkest)
term.setPaletteColour(2 ^ 10, 0xcc/255, 0xcc/255, 0xcc/255) -- grey 1
term.setPaletteColour(2 ^ 11, 0xee/255, 0xee/255, 0xee/255) -- grey 2 (lightest)
term.setPaletteColour(2 ^ 12, 1, 1, 0)
term.setPaletteColour(2 ^ 13, 1, 0.5, 0)
term.setPaletteColour(2 ^ 14, 1, 0, 0)

-- set up game state
local running = true
local update_timer = startTimer(0)
local update_time = os.clock()
local plane = {}
plane.x = 0
plane.y = MOUNTAIN_SCALER
plane.z = 10
plane.yaw = 0
plane.pitch = -math.pi / 8
plane.roll = 0
plane.speed = 2
plane.deltaYaw = 0
plane.deltaPitch = 0
plane.deltaRoll = 0
plane.deltaSpeed = 0

--- @param x number
--- @param z number
local function terrain_height(x, z)
	local texture_noise = simplex.Noise3D(x / math.pi, z / math.pi, 0.4)
	local moutain_noise = simplex.Noise3D(x / math.pi / 10, z / math.pi / 10, 1.5) ^ 2 * 4

	return texture_noise * 0.3 + moutain_noise * MOUNTAIN_SCALER
end

local function terrain_uvs(x, y, z)
	return simplex.Noise2D(x * math.pi * 0.4, z * math.pi * 0.4), y
end

--- @param cx integer
--- @param cz integer
--- @param gen_uvs fun (x: number, y: number, z: number): number, number
local function tesselate_face(cx, cz, divisions, gen_uvs)
	local minX = cx * CHUNK_TILING - 0.5 * CHUNK_SIZE
	local maxX = cx * CHUNK_TILING + 0.5 * CHUNK_SIZE
	local minZ = cz * CHUNK_TILING - 0.5 * CHUNK_SIZE
	local maxZ = cz * CHUNK_TILING + 0.5 * CHUNK_SIZE
	local deltaX = (maxX - minX) / divisions
	local deltaZ = (maxZ - minZ) / divisions

	local geometry = v3d.create_geometry(v3d.GEOMETRY_COLOUR_UV)

	local x = minX

	for _ = 1, divisions do
		local z = minZ

		for _ = 1, divisions do
			local x1 = x + deltaX
			local z1 = z + deltaZ
			local y00 = terrain_height(x, z)
			local y10 = terrain_height(x1, z)
			local y11 = terrain_height(x1, z1)
			local y01 = terrain_height(x, z1)
			local u00, v00 = gen_uvs(x, y00, z)
			local u10, v10 = gen_uvs(x1, y10, z)
			local u11, v11 = gen_uvs(x1, y11, z1)
			local u01, v01 = gen_uvs(x, y01, z1)
			geometry:add_triangle(x, y00, z, u00, v00, x, y01, z1, u01, v01, x1, y11, z1, u11, v11, colours.green)
			geometry:add_triangle(x, y00, z, u00, v00, x1, y11, z1, u11, v11, x1, y10, z, u10, v10, colours.lime)
			z = z + deltaZ
		end

		x = x + deltaX
	end

	return geometry
end

local function draw()
	local visible_chunks = {}

	local k = 2
	for cx = -k, k do
		for cz = -k, k do
			local chunkId = cx .. ';' .. cz
			local detail = math.max(math.abs(cx), math.abs(cz))

			if not chunks[chunkId] then
				local g = {}
				for i = 0, CHUNK_LOG_DIVISIONS do
					table.insert(g, tesselate_face(cx, cz, 2 ^ i, terrain_uvs))
				end
				chunks[chunkId] = g
			end

			table.insert(visible_chunks, chunks[chunkId][CHUNK_LOG_DIVISIONS + 1 - detail])
		end
	end

	framebuffer:clear(2 ^ 6)

	for i = 1, #visible_chunks do
		local g = visible_chunks[i]
		terrain_pipeline:render_geometry(g, framebuffer, camera)
	end

	framebuffer:blit_subpixel(term)
end

local function update(dt)
	plane.roll = plane.roll + plane.deltaRoll * dt * PLANE_ROLL_RATE
	plane.yaw = plane.yaw + plane.deltaYaw * math.cos(plane.roll) * dt * PLANE_YAW_RATE
	plane.pitch = plane.pitch + plane.deltaYaw * math.sin(-plane.roll) * dt * PLANE_YAW_RATE
	plane.pitch = plane.pitch + plane.deltaPitch * math.cos(plane.roll) * dt * PLANE_PITCH_RATE
	plane.yaw = plane.yaw + plane.deltaPitch * math.sin(plane.roll) * dt * PLANE_PITCH_RATE
	plane.speed = plane.speed + plane.deltaSpeed * dt * PLANE_ACCELERATION

	if plane.speed < PLANE_MIN_SPEED then plane.speed = PLANE_MIN_SPEED end
	if plane.speed > PLANE_MAX_SPEED then plane.speed = PLANE_MAX_SPEED end

	local sinYaw = math.sin(plane.yaw)
	local cosYaw = math.cos(plane.yaw)
	local sinPitch = math.sin(plane.pitch)
	local cosPitch = math.cos(plane.pitch)
	local sinRoll = math.sin(plane.roll)
	local cosRoll = math.cos(plane.roll)

	local forward_x = 0
	local forward_y = 0
	local forward_z = -1

	local up_x = 0
	local up_y = 1
	local up_z = 0

	forward_y, forward_z = forward_y * cosPitch + forward_z * -sinPitch, forward_y * sinPitch + forward_z * cosPitch
	forward_x, forward_z = forward_x * cosYaw + forward_z * sinYaw, forward_x * -sinYaw + forward_z * cosYaw

	up_x, up_y = up_x * cosRoll + up_y * -sinRoll, up_x * sinRoll + up_y * cosRoll
	up_y, up_z = up_y * cosPitch + up_z * -sinPitch, up_y * sinPitch + up_z * cosPitch
	up_x, up_z = up_x * cosYaw + up_z * sinYaw, up_x * -sinYaw + up_z * cosYaw

	local speed = plane.speed - forward_y

	plane.x = plane.x + forward_x * dt * speed
	plane.y = plane.y + forward_y * dt * speed
	plane.z = plane.z + forward_z * dt * speed

	camera.x = plane.x + forward_x * PLANE_CAMERA_FORWARD_DISTANCE + up_x * PLANE_CAMERA_UP_DISTANCE
	camera.y = plane.y + forward_y * PLANE_CAMERA_FORWARD_DISTANCE + up_y * PLANE_CAMERA_UP_DISTANCE
	camera.z = plane.z + forward_z * PLANE_CAMERA_FORWARD_DISTANCE + up_z * PLANE_CAMERA_UP_DISTANCE
	camera.yRotation = plane.yaw - PLANE_CAMERA_X_ROTATION_DELTA * math.sin(plane.roll)
	camera.xRotation = -plane.pitch - PLANE_CAMERA_X_ROTATION_DELTA * math.cos(plane.roll)
	camera.zRotation = -plane.roll
end

local function handle_event(event, ...)
	local ev_parameters = { ... }

	if event == 'timer' and ev_parameters[1] == update_timer then
		local t = os.clock()
		local dt = t - update_time
		update_time = t
		update_timer = startTimer(REFRESH_INTERVAL)
		update(dt)
		draw()
	elseif event == 'key' then
		if ev_parameters[1] == keys.left then
			plane.deltaRoll = 1
		end
		if ev_parameters[1] == keys.right then
			plane.deltaRoll = -1
		end
		if ev_parameters[1] == keys.up then
			plane.deltaPitch = 1
		end
		if ev_parameters[1] == keys.down then
			plane.deltaPitch = -1
		end
		if ev_parameters[1] == keys.a then
			plane.deltaYaw = 1
		end
		if ev_parameters[1] == keys.d then
			plane.deltaYaw = -1
		end
		if ev_parameters[1] == keys.w then
			plane.deltaSpeed = 1
		end
		if ev_parameters[1] == keys.s then
			plane.deltaSpeed = -1
		end
	elseif event == 'key_up' then
		if ev_parameters[1] == keys.left or ev_parameters[1] == keys.right then
			plane.deltaRoll = 0
		end
		if ev_parameters[1] == keys.up or ev_parameters[1] == keys.down then
			plane.deltaPitch = 0
		end
		if ev_parameters[1] == keys.a or ev_parameters[1] == keys.d then
			plane.deltaYaw = 0
		end
		if ev_parameters[1] == keys.w or ev_parameters[1] == keys.s then
			plane.deltaSpeed = 0
		end
	elseif event == 'terminate' then
		running = false
	end
end

local ok, err = pcall(function()
	while running do
		--- @diagnostic disable-next-line: undefined-field
		handle_event(os.pullEventRaw())
	end
end)

for i = 0, 15 do
	term.setPaletteColour(2 ^ i, table.unpack(initial_palette[i + 1]))
end

if not ok then
	error(err, 0)
end
