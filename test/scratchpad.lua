
shell.run '/v3d/build'

local v3d = require '/v3d'

term.setGraphicsMode(1)
local width, height = term.getSize(2)
local framebuffer = v3d.create_framebuffer(width, height, 'Screen buffer')

local layout = v3d.create_layout()
	:add_vertex_attribute('position', 3, true)
	:add_vertex_attribute('uv', 2, true)
	:add_face_attribute('colour', 1)

local cube1 = v3d.create_debug_cube(0, 0, 0, 1):cast(layout):build('Large cube')

local cube2 = v3d.create_debug_cube(0, 0, 0, 0.5):cast(layout):build('Small cube')

local default_pipeline = v3d.create_pipeline {
	layout = layout,
	colour_attribute = 'colour',
}

local transparent_pipeline = v3d.create_pipeline {
	layout = layout,
	cull_face = false,
	attributes = { 'uv' },
	pack_attributes = false,
	fragment_shader = v3d.create_texture_sampler()
}

local h = assert(io.open('/v3d/build/pipeline_source.lua', 'w'))
h:write(transparent_pipeline.source)
h:close()

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
local t = 0

local ok, err

while true do
	local n = 3
	local s = 2

	framebuffer:clear(colours.black)
	local r1 = math.cos(t * 3) * 0.3
	local r2 = math.sin(t * 2) * 0.2
	local base_transform = v3d.camera(0, 0, 2, 0, r1, r2)

	for z = 0, n do
	for x = -z, z do
		for y = -math.max(0, z - 1), math.max(0, z - 1) do
				local transform = base_transform
				                * v3d.translate(-x * s, -y * s, -z * s)

				transparent_pipeline:render_geometry(cube1, framebuffer, transform)
				effect_pipeline:render_geometry(cube1, framebuffer, transform)
				default_pipeline:render_geometry(cube2, framebuffer, transform)
			end
		end
	end

	ok, err = pcall(function()
		-- framebuffer:blit_graphics(term.native(), 0, 0)
		framebuffer:blit_graphics_depth(term.native(), 0, 0)
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
