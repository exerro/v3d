
--- @type V3D
local v3d = require 'v3d'
local simplex = require '/v3d/util/simplex'
--- @diagnostic disable-next-line: undefined-field
local startTimer = os.startTimer

local initial_palette = {}
for i = 0, 15 do
	initial_palette[i + 1] = { term.getPaletteColour(2 ^ i) }
end
do -- set the palette
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
end

-- constants
local REFRESH_INTERVAL = 0.01
local CHUNK_SIZE = 20
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
-- term.setGraphicsMode(1)
local screen_width, screen_height = term.getSize()
screen_width = screen_width * 2
screen_height = screen_height * 3
local colour_image = v3d.create_image(v3d.uinteger(), screen_width, screen_height, 1, colours.black)
local depth_image = v3d.create_image(v3d.number(), screen_width, screen_height, 1, 0)
local image_views = {
	colour = v3d.image_view(colour_image),
	depth = v3d.image_view(depth_image),
}
local transform = v3d.camera()
local terrain_vertex_format = v3d.struct {
	position = v3d.number() * 3,
	mountainness = v3d.number(),
}
local terrain_face_format = v3d.struct {
	colour = v3d.uinteger(),
}
local terrain_texture = v3d.create_image(v3d.number(), 32, 32, 1, 0)
local terrain_texture_view = v3d.image_view(terrain_texture)
local terrain_buffer = {}

for y = 0, terrain_texture.height - 1 do
	for x = 0, terrain_texture.width - 1 do
		local noise_scale = 3
		local noise = simplex.Noise2D(
			x / (terrain_texture.width - 1) * noise_scale,
			y / (terrain_texture.height - 1) * noise_scale
		) / 2 + 0.5
		terrain_buffer[y * terrain_texture.width + x + 1] = noise
	end
end
v3d.image_view_unbuffer_from(terrain_texture_view, terrain_buffer)

-- local test_geometry = v3d.debug_cuboid { include_uvs = true }:build()
-- local test_renderer = v3d.compile_renderer {
-- 	pixel_shader = v3d.shader {
-- 		source_format = test_geometry.vertex_format,
-- 		image_formats = {
-- 			colour = colour_image.format,
-- 		},
-- 		code = [[
-- 			local u, v = v3d_src.uv
-- 			v3d_dst.colour = v3d_constant.sampler:sample(v3d_constant.texture, u, v) or 1
-- 		]],
-- 		constants = {
-- 			texture = terrain_texture,
-- 			sampler = v3d.create_sampler2D {
-- 				format = terrain_texture.format,
-- 				wrap_u = 'mirror',
-- 				wrap_v = 'mirror',
-- 			},
-- 		},
-- 	},
-- 	image_formats = {
-- 		colour = colour_image.format,
-- 	},
-- }
-- v3d.renderer_render(test_renderer, test_geometry, image_views, v3d.camera { z = 2 })
-- v3d.image_view_present_graphics(image_views.colour, term.native(), true)
-- os.pullEvent 'mouse_click'
-- do return end

local pixel_shader = v3d.shader {
	source_format = terrain_vertex_format,
	face_format = terrain_face_format,
	image_formats = {
		colour = colour_image.format,
		depth = depth_image.format,
	},
	code = [[
		if v3d_src_depth > v3d_dst.depth then
			local mountain_threshold = v3d_constant.MOUNTAIN_SCALER / 3 + v3d_src.mountainness
			if v3d_src_absolute_pos.y > mountain_threshold then
				local mountain_scalar = 1 / (v3d_constant.MOUNTAIN_SCALER - mountain_threshold)
				v3d_dst.colour = 2 ^ math.max(0, math.min(11, math.floor(9 + (v3d_src_absolute_pos.y - mountain_threshold) * mountain_scalar * 5)))
			else
				local x, y = v3d_src_absolute_pos.x, v3d_src_absolute_pos.z
				local s = 8
				x = x / s -- + v3d_src.mountainness / 4
				y = y / s -- * (1 + v3d_src.mountainness / 32)
				local noise = v3d_constant.terrain_sampler:sample(v3d_constant.terrain_texture, x, y)
				v3d_dst.colour = 2 ^ math.max(0, math.min(5, math.floor(noise * 5 + 0.5)))
			end
			v3d_dst.depth = v3d_src_depth
		end
	]],
	constants = {
		MOUNTAIN_SCALER = MOUNTAIN_SCALER,
		terrain_texture = terrain_texture,
		terrain_sampler = v3d.create_sampler2D {
			format = terrain_texture.format,
			interpolate = 'nearest',
			wrap_u = 'mirror',
			wrap_v = 'mirror',
		},
	},
}
local terrain_renderer = v3d.compile_renderer { pixel_shader = pixel_shader }
local chunks = {}

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

local function terrain_uvs(x, z)
	return simplex.Noise2D(x * math.pi * 0.4, z * math.pi * 0.4)
end

--- @param cx integer
--- @param cz integer
local function tesselate_face(cx, cz, divisions)
	local minX = cx * CHUNK_TILING - 0.5 * CHUNK_SIZE
	local maxX = cx * CHUNK_TILING + 0.5 * CHUNK_SIZE
	local minZ = cz * CHUNK_TILING - 0.5 * CHUNK_SIZE
	local maxZ = cz * CHUNK_TILING + 0.5 * CHUNK_SIZE
	local deltaX = (maxX - minX) / divisions
	local deltaZ = (maxZ - minZ) / divisions

	local geometry = v3d.create_geometry_builder(terrain_vertex_format, terrain_face_format)

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
			local u00 = terrain_uvs(x, z)
			local u10 = terrain_uvs(x1, z)
			local u11 = terrain_uvs(x1, z1)
			local u01 = terrain_uvs(x, z1)
			v3d.geometry_builder_add_vertex(geometry, {
				position = { x, y00, z },
				mountainness = u00,
			})
			v3d.geometry_builder_add_vertex(geometry, {
				position = { x, y01, z1 },
				mountainness = u01,
			})
			v3d.geometry_builder_add_vertex(geometry, {
				position = { x1, y11, z1 },
				mountainness = u11,
			})
			v3d.geometry_builder_add_face(geometry, {
				colour = colours.green,
			})
			v3d.geometry_builder_add_vertex(geometry, {
				position = { x, y00, z },
				mountainness = u00,
			})
			v3d.geometry_builder_add_vertex(geometry, {
				position = { x1, y11, z1 },
				mountainness = u11,
			})
			v3d.geometry_builder_add_vertex(geometry, {
				position = { x1, y10, z },
				mountainness = u10,
			})
			v3d.geometry_builder_add_face(geometry, {
				colour = colours.lime,
			})
			z = z + deltaZ
		end

		x = x + deltaX
	end

	return v3d.geometry_builder_build(geometry)
end

local function draw()
	--- @type V3DGeometry[]
	local visible_chunks = {}

	local k = 12
	for cx = -k, k do
		for cz = -k, k do
			local chunkId = cx .. ';' .. cz

			if not chunks[chunkId] then
				chunks[chunkId] = tesselate_face(cx, cz, 8)
			end

			table.insert(visible_chunks, chunks[chunkId])
		end
	end

	v3d.enter_debug_region('clear')
	v3d.image_view_fill(image_views.colour, 2 ^ 6)
	v3d.image_view_fill(image_views.depth, 0)
	v3d.exit_debug_region('clear')

	v3d.enter_debug_region('render')
	local n = 0
	for i = 1, #visible_chunks do
		v3d.renderer_render(terrain_renderer, visible_chunks[i], image_views, transform)
		n = n + visible_chunks[i].n_faces
	end
	v3d.exit_debug_region('render')

	v3d.enter_debug_region('present')
	-- v3d.image_view_present_graphics(image_views.colour, term.native(), true)
	v3d.image_view_present_term_subpixel(image_views.colour, term.native())
	v3d.exit_debug_region('present')
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

	transform = v3d.camera {
		x = plane.x + forward_x * PLANE_CAMERA_FORWARD_DISTANCE + up_x * PLANE_CAMERA_UP_DISTANCE,
		y = plane.y + forward_y * PLANE_CAMERA_FORWARD_DISTANCE + up_y * PLANE_CAMERA_UP_DISTANCE,
		z = plane.z + forward_z * PLANE_CAMERA_FORWARD_DISTANCE + up_z * PLANE_CAMERA_UP_DISTANCE,
		-- pitch = -plane.pitch - PLANE_CAMERA_X_ROTATION_DELTA * math.cos(plane.roll),
		pitch = plane.pitch,
		-- yaw = plane.yaw - PLANE_CAMERA_X_ROTATION_DELTA * math.sin(plane.roll),
		yaw = plane.yaw,
		-- roll = -plane.roll,
		roll = plane.roll,
	}
end

local function handle_event(event, ...)
	local ev_parameters = { ... }

	if event == 'timer' and ev_parameters[1] == update_timer then
		local t = os.clock()
		local dt = math.min(0.1, t - update_time)
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

while running do
	--- @diagnostic disable-next-line: undefined-field
	handle_event(os.pullEventRaw())
end

for i = 0, 15 do
	term.setPaletteColour(2 ^ i, table.unpack(initial_palette[i + 1]))
end
