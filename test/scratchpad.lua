
local hue_counts = {
	{  1 },
	{  1,  4 },
	{  1,  4,  8 },
	{  1,  4,  8, 12 },
	{  1,  4,  8, 12, 18 },
	{  1,  4,  8, 12, 18, 24 },
	{  1,  4,  8, 12, 18, 24, 32 },
}

local rgb_lookup = {}

local MAX_VALUE = #hue_counts - 1
local MAX_SATURATION = #hue_counts[#hue_counts] - 1
local MAX_HUE_COUNT = hue_counts[#hue_counts][#hue_counts[#hue_counts]]

local index_lookups = {}
do
	local i = 0

	for value = 0, MAX_VALUE do
		index_lookups[value + 1] = {}

		for saturation = 0, MAX_SATURATION do
			local s = saturation / MAX_SATURATION
			local chroma = math.floor(s * (#hue_counts[value + 1] - 1) + 0.5)

			index_lookups[value + 1][saturation + 1] = {}

			for hue = 0, MAX_HUE_COUNT - 1 do
				local h = hue / MAX_HUE_COUNT
				local hue_count = hue_counts[value + 1][chroma + 1]
				local index = i

				for j = 1, chroma do
					index = index + hue_counts[value + 1][j]
				end

				index = index + math.floor(h * hue_count + 0.5)

				table.insert(index_lookups[value + 1][saturation + 1], index)
			end
		end

		for j = 1, #hue_counts[value + 1] do
			i = i + hue_counts[value + 1][j]
		end
	end
end

local function hsv_to_rgb(h, s, v)
	local k1 = v*(1-s)
	local k2 = v - k1
	local r = math.min (math.max (3*math.abs ((h*2)%2-1)-1, 0), 1)
	local g = math.min (math.max (3*math.abs ((h*2-120/180)%2-1)-1, 0), 1)
	local b = math.min (math.max (3*math.abs ((h*2+120/180)%2-1)-1, 0), 1)
	return k1 + k2 * r, k1 + k2 * g, k1 + k2 * b
end

local function rgb_to_hsv(r, g, b)
	local max, min = math.max(r, g, b), math.min(r, g, b)
	local d = max - min
	local h
	local s = max == 0 and 0 or d / max
	local v = max

	if max == min then -- achromatic
		h = 0
	else
		if max == r then
			h = (g - b) / d
			if g < b then h = h + 6 end
		elseif max == g then h = (b - r) / d + 2
		elseif max == b then h = (r - g) / d + 4
		end
		h = h / 6
	end

	return h, s, v
end

local function fast_hsv_to_idx(h, s, v)
	local value = math.floor(v ^ (1/2.2) * MAX_VALUE)
	local saturation = math.floor(s * MAX_SATURATION + 0.5)
	local hue = math.floor(h * (MAX_HUE_COUNT - 1) + 0.5)

	return index_lookups[value + 1][saturation + 1][hue + 1]
end

local function fast_rgb_to_idx(r, g, b)
	return fast_hsv_to_idx(rgb_to_hsv(r, g, b))
end

local i = 0

term.native().setGraphicsMode(2)

for value = 0, MAX_VALUE do
	local v = (value / MAX_VALUE) ^ 2.2

	for chroma = 0, value do
		local s = value == 0 and 0 or chroma / value
		local hue_count = hue_counts[value + 1][chroma + 1]

		for hue = 0, hue_count - 1 do
			local h = hue / hue_count
			local r, g, b = hsv_to_rgb(h, s, v)

			term.native().setPaletteColour(i, r, g, b)
			i = i + 1
			rgb_lookup[i] = { r, g, b }
		end
	end
end

local ordered_dithering_map = {
	{  0,  8,  2, 10 },
	{ 12,  4, 14,  6 },
	{  3, 11,  1,  9 },
	{ 15,  7, 13,  5 },
}

for y = 1, #ordered_dithering_map do
	for x = 1, #ordered_dithering_map[y] do
		ordered_dithering_map[y][x] = (ordered_dithering_map[y][x] + 1) / #ordered_dithering_map / #ordered_dithering_map[y] - 1/2
	end
end

local function rgb_to_index_colour(width, height, albedo_buffer, index_colour_buffer)
	local albedo_index = 1
	local math_min = math.min
	local math_max = math.max
	local math_floor = math.floor
	local math_abs = math.abs

	for index_colour_index_base = 0, width * height - 1, width do
		for index_colour_index = index_colour_index_base + 1, index_colour_index_base + width do
			local r = albedo_buffer[albedo_index]
			local g = albedo_buffer[albedo_index + 1]
			local b = albedo_buffer[albedo_index + 2]

			local alg_r = 0.15
			local x = (index_colour_index - 1) % width
			local y = (index_colour_index - x - 1) / width
			local Mij = ordered_dithering_map[y % #ordered_dithering_map + 1][x % #ordered_dithering_map[1] + 1]

			-- r = math_max(0, math_min(1, r + alg_r * Mij))
			-- g = math_max(0, math_min(1, g + alg_r * Mij))
			-- b = math_max(0, math_min(1, b + alg_r * Mij))

			local sample_r = math_max(0, math_min(1, r + alg_r * Mij))
			local sample_g = math_max(0, math_min(1, g + alg_r * Mij))
			local sample_b = math_max(0, math_min(1, b + alg_r * Mij))

			-- local sample_r = math_max(0, math_min(1, r))
			-- local sample_g = math_max(0, math_min(1, g))
			-- local sample_b = math_max(0, math_min(1, b))

			-- rgb_to_hsv
			local max = math_max(sample_r, sample_g, sample_b)
			local min = math_min(sample_r, sample_g, sample_b)
			local d = max - min
			local h
			local s = max == 0 and 0 or d / max
			local v = max

			if math_abs(max - min) < 0.0001 then -- achromatic
				h = 0
			else
				if max == sample_r then
					h = (sample_g - sample_b) / d
					if sample_g < sample_b then h = h + 6 end
				elseif max == sample_g then h = (sample_b - sample_r) / d + 2
				elseif max == sample_b then h = (sample_r - sample_g) / d + 4
				elseif math_abs(max - sample_r) < 0.0001 then
					h = (sample_g - sample_b) / d
					if sample_g < sample_b then h = h + 6 end
				elseif math_abs(max - sample_g) < 0.0001 then h = (sample_b - sample_r) / d + 2
				elseif math_abs(max - sample_b) < 0.0001 then h = (sample_r - sample_g) / d + 4
				else
					error('wat ' .. max .. sample_r .. sample_g .. sample_b)
				end
				h = h / 6
			end
			--end

			-- fast_hsv_to_idx
			local value = math_floor(v ^ 0.454545455 * MAX_VALUE + 0.5)
			local saturation = math_floor(s * MAX_SATURATION + 0.5)
			local hue = math_floor(h * (MAX_HUE_COUNT - 1) + 0.5)
		
			local index = index_lookups[value + 1][saturation + 1][hue + 1]
			--end

			local pal_rgb = rgb_lookup[index + 1]
			local error_r = r - pal_rgb[1]
			local error_g = g - pal_rgb[2]
			local error_b = b - pal_rgb[3]

			if x % 8 ~= 7 and albedo_index + 3 < width * height * 3 then
				albedo_buffer[albedo_index + 3] = albedo_buffer[albedo_index + 3] + error_r * 7/16
				albedo_buffer[albedo_index + 4] = albedo_buffer[albedo_index + 4] + error_g * 7/16
				albedo_buffer[albedo_index + 5] = albedo_buffer[albedo_index + 5] + error_b * 7/16
			end

			if y % 8 ~= 7 and albedo_index + width * 3 < width * height * 3 then
				albedo_buffer[albedo_index + width * 3 - 3] = albedo_buffer[albedo_index + width * 3 - 3] + error_r * 3/16
				albedo_buffer[albedo_index + width * 3 - 2] = albedo_buffer[albedo_index + width * 3 - 2] + error_g * 3/16
				albedo_buffer[albedo_index + width * 3 - 1] = albedo_buffer[albedo_index + width * 3 - 1] + error_b * 3/16
				albedo_buffer[albedo_index + width * 3] = albedo_buffer[albedo_index + width * 3] + error_r * 5/16
				albedo_buffer[albedo_index + width * 3 + 1] = albedo_buffer[albedo_index + width * 3 + 1] + error_g * 5/16
				albedo_buffer[albedo_index + width * 3 + 2] = albedo_buffer[albedo_index + width * 3 + 2] + error_b * 5/16
			end

			if x % 8 ~= 7 and y % 8 ~= 7 and albedo_index + width * 3 + 3 < width * height * 3 then
				albedo_buffer[albedo_index + width * 3 + 3] = albedo_buffer[albedo_index + width * 3 + 3] + error_r * 1/16
				albedo_buffer[albedo_index + width * 3 + 4] = albedo_buffer[albedo_index + width * 3 + 4] + error_g * 1/16
				albedo_buffer[albedo_index + width * 3 + 5] = albedo_buffer[albedo_index + width * 3 + 5] + error_b * 1/16
			end

			index_colour_buffer[index_colour_index] = index
			albedo_index = albedo_index + 3
		end
		index_colour_index_base = index_colour_index_base + width
	end
end

if false then
	local size = 4
	local lines = {}

	for value = 0, MAX_VALUE do
		local v = (value / MAX_VALUE) ^ 2.2

		for chroma = 0, value do
			local s = chroma / value
			local hue_count = hue_counts[value + 1][chroma + 1]

			table.insert(lines, "")

			for hue = 0, hue_count - 1 do
				local h = hue / hue_count

				term.native().setPaletteColour(i, hsv_to_rgb(h, s, v))
				lines[#lines] = lines[#lines] .. string.char(i):rep(size)
				i = i + 1
			end
		end
	end

	for i = 1, #lines do
		lines[i] = lines[i] .. lines[i]
	end

	for r = 0, 1, 0.1 do
		local line = ""
		for b = 0, 1, 0.25 do
			for g = 0, 1, 0.1 do
				line = line .. string.char(fast_rgb_to_idx(r, g, b)):rep(size)
			end
		end
		table.insert(lines, line)
	end

	for g = 0, 1, 0.1 do
		local line = ""
		for r = 0, 1, 0.25 do
			for b = 0, 1, 0.1 do
				line = line .. string.char(fast_rgb_to_idx(r, g, b)):rep(size)
			end
		end
		table.insert(lines, line)
	end

	for r = 0, 1, 0.1 do
		local line = ""
		for g = 0, 1, 0.25 do
			for b = 0, 1, 0.1 do
				line = line .. string.char(fast_rgb_to_idx(r, g, b)):rep(size)
			end
		end
		table.insert(lines, line)
	end

	for i = #lines, 1, -1 do
		for _ = 1, size do
			table.insert(lines, i, lines[i])
		end
	end

	term.native().setBackgroundColour(0)
	term.native().clear()
	term.native().drawPixels(0, 0, lines)

	os['pullEvent'] 'mouse_click'

	return
end

shell.run '/v3d/tools/build'

local v3d = require '/v3d'

local layout = v3d.create_layout()
	:add_layer('index_colour', 'any-numeric', 1)
	:add_layer('albedo', 'any-numeric', 3)
	:add_layer('position', 'any-numeric', 3)
	:add_layer('depth', 'depth-reciprocal', 1)
local framebuffer = v3d.create_framebuffer(layout, term.getSize(2))
local geometry = v3d.create_debug_cube():build()
local transform = v3d.camera(10, 20, 10, math.pi / 4, math.pi / 6, 0, math.pi / 2)
local pipeline = v3d.create_pipeline {
	layout = layout,
	format = v3d.DEBUG_CUBE_FORMAT,
	position_attribute = 'position',
	-- cull_face = false,
	fragment_shader = [[
		if v3d_compare_depth(v3d_fragment_depth(), v3d_read_layer('depth')) then
			-- local r, g, b = v3d_read_attribute_values('position')
			-- r = r + 0.5
			-- g = g + 0.5
			-- b = b + 0.5
			-- local rgb_to_idx = v3d_read_uniform('rgb_to_idx')
			local r = v3d_read_uniform('red')
			local g = v3d_read_uniform('green')
			local b = v3d_read_uniform('blue')
			local u_lights = v3d_read_uniform('lights')

			local write_r = r * v3d_read_uniform('ambient')
			local write_g = g * v3d_read_uniform('ambient')
			local write_b = b * v3d_read_uniform('ambient')

			local x, y, z = v3d_fragment_world_position()
			local nx, ny, nz = v3d_face_world_normal()

			for i = 1, #u_lights do
				local light = u_lights[i]
				local dx = light[1] - x
				local dy = light[2] - y
				local dz = light[3] - z
				local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
				local dot = math.max(0, (nx * dx + ny * dy + nz * dz) / distance)
				local k = dot / (1 + distance)

				write_r = write_r + r * light[4] * k
				write_g = write_g + g * light[5] * k
				write_b = write_b + b * light[6] * k
			end

			v3d_write_layer_values('albedo', write_r, write_g, write_b)
			-- v3d_write_layer_values('albedo', nx, ny, nz)
			-- v3d_write_layer('index_colour', rgb_to_idx(write_r, write_g, write_b))
			v3d_write_layer('depth', v3d_fragment_depth())
			v3d_count_event('fragment_drawn')
		end
	]],
	statistics = true,
}

local lights = {}

table.insert(lights, { -50, 5, -50, 0, 0, 20 })
table.insert(lights, { -25, 5, -25, 3, 10, 3 })
table.insert(lights, { 0, 5, -25, 10, 4, 4 })

local scene = {}
local object_colours = {}

-- table.insert(scene, v3d.translate(50, 0, -50) * v3d.scale(100, 0.1, 100))
table.insert(scene, v3d.translate(-50, -1, -50) * v3d.scale(100, 0.1, 100))

for _ = 1, 200 do
	local scale_value = math.random(10, 30) / 10
	local position = v3d.translate(math.random(-100, 0), -1 + scale_value / 2, math.random(-100, 0))
	local rotation = v3d.rotate(0, math.random() * math.pi * 2, 0)
	local scale = v3d.scale(scale_value)
	table.insert(scene, position * rotation * scale)
end

object_colours[1] = { 1, 1, 1 }

for i = 2, #scene do
	object_colours[i] = { hsv_to_rgb(math.random(), 0.3, 1) }
end

pipeline:set_uniform('rgb_to_idx', fast_rgb_to_idx)
pipeline:set_uniform('lights', lights)
pipeline:set_uniform('ambient', 0.3)

local h = assert(io.open('/.v3d_crash_dump.txt', 'w'))
h:write(pipeline.source)
h:close()

local statistics

local t = 0

while true do
	-- transform = transform * v3d.rotate(0, 0.05, 0)
	framebuffer:clear('index_colour', 0)
	framebuffer:clear('albedo', 0)
	framebuffer:clear('depth')

	lights[1][1] = math.sin(t) * -25 - 25

	for i = 1, #scene do
		pipeline:set_uniform('red', object_colours[i][1])
		pipeline:set_uniform('green', object_colours[i][2])
		pipeline:set_uniform('blue', object_colours[i][3])
		statistics = pipeline:render_geometry(geometry, framebuffer, transform, scene[i])
	end

	for i = 2, #scene do
		scene[i] = v3d.translate(0, math.random() - 0.5, 0) * scene[i] * v3d.rotate(0, math.random() * 0.1, 0)
	end

	rgb_to_index_colour(framebuffer.width, framebuffer.height, framebuffer:get_buffer('albedo'), framebuffer:get_buffer('index_colour'))

	framebuffer:blit_graphics(term, 'index_colour')
	term.setCursorPos(1, 1)
	term.setBackgroundColour(colours.black)
	term.setTextColour(colours.white)
	print(textutils.serialize(statistics))
	if not pcall(sleep, 0.05) then break end
	t = t + 0.05
end

term.native().setGraphicsMode(0)
term.native().setCursorPos(1, 1)
term.native().setBackgroundColour(colours.black)
term.native().setTextColour(colours.white)
term.clear()
print(framebuffer.width, framebuffer.height)
print(textutils.serialize(statistics))

for i = 0, 15 do
	term.native().setPaletteColour(2 ^ i, term.nativePaletteColour(2 ^ i))
end
