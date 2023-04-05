
if not shell.execute '/v3d/tools/build' then return end

local v3d = require '/v3d.gen.v3dtest'

--- @type 'effect-hypercube' | 'effect-slow' | 'effect-fast' | 'slow'
local palettization = 'effect-hypercube'

local images = {}
do
	for _, image_name in ipairs(fs.list('/v3d/gen/images/')) do
		local h = assert(io.open('/v3d/gen/images/' .. image_name))
		local content = h:read '*a'
		h:close()

		local w, h
		local image = {}
		local i = 1

		for part in content:gmatch '%d+' do
			if not w then w = tonumber(part)
			elseif not h then h = tonumber(part)
			else image[i] = tonumber(part) / 255; i = i + 1
			end
		end

		image.name = image_name:gsub('%.%w+$', '', 1)
		image.width = w
		image.height = h
		table.insert(images, image)
	end
end

local t = 0

local fixed_palette_size = 16

local use_legacy_cc = false
local use_standard_cc = false

if use_legacy_cc then
	fixed_palette_size = 16
	use_standard_cc = true
end

local do_fast_dither = true
local dithering_factor = 1.0
local hatch_dither_factor = 0.15

local n_cubes = 1000
local cube_saturation = 0.9
local cube_height_variation = n_cubes / 200

local ambient_lighting = 1.0

local do_lighting = true

local value_exp = 2.2

if use_standard_cc then
	value_exp = 1
	do_fast_dither = false
	dithering_factor = 0.5
	hatch_dither_factor = 0.0
end

local hue_counts = {
	{  1 },
	{  1,  4 },
	{  1,  4,  8 },
	{  1,  4,  8, 12 },
	{  1,  4,  8, 12, 18 },
	{  1,  4,  8, 12, 18, 24 },
	{  1,  4,  8, 12, 18, 24, 32 },
}

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
	local value = math.floor(v ^ (1/value_exp) * MAX_VALUE)
	local saturation = math.floor(s * MAX_SATURATION + 0.5)
	local hue = math.floor(h * (MAX_HUE_COUNT - 1) + 0.5)

	return index_lookups[value + 1][saturation + 1][hue + 1]
end

local function fast_rgb_to_idx(r, g, b)
	return fast_hsv_to_idx(rgb_to_hsv(r, g, b))
end

local i = 0

term.native().setGraphicsMode(use_standard_cc and 0 or 2)

-- compute rgb_lookup
local rgb_lookup = {}
for value = 0, MAX_VALUE do
	local v = (value / MAX_VALUE) ^ value_exp

	for chroma = 0, value do
		local s = value == 0 and 0 or chroma / value
		local hue_count = hue_counts[value + 1][chroma + 1]

		for hue = 0, hue_count - 1 do
			local h = hue / hue_count
			local r, g, b = hsv_to_rgb(h, s, v)

			i = i + 1
			rgb_lookup[i] = { r, g, b }
		end
	end
end

local rgb_lookup_flattened = {}
for i = 1, #rgb_lookup do
	rgb_lookup_flattened[i * 3 - 2] = rgb_lookup[i][1]
	rgb_lookup_flattened[i * 3 - 1] = rgb_lookup[i][2]
	rgb_lookup_flattened[i * 3 - 0] = rgb_lookup[i][3]
end

local grid_palette = v3d.rgb.grid_palette({ red = 2, green = 4, blue = 2 }, 0.6)
local kd_palette = v3d.rgb.kd_tree_palette(fixed_palette_size, rgb_lookup_flattened)
-- local kd_palette = v3d.rgb.kd_tree_palette(fixed_palette_size, v3d.rgb.grid_palette({ red = 2, green = 2, blue = 2 }, 0.5, 1):get_all_colours())
local hypercube_palette = v3d.rgb.hypercube_palette(0.2)
local palette = palettization == 'effect-hypercube' and hypercube_palette or palettization == 'effect-slow' and kd_palette or grid_palette

if palettization ~= 'slow' then
	for i = 1, palette:count() do
		local r, g, b = palette:get_colour(i)
		term.native().setPaletteColour(use_standard_cc and 2 ^ (i - 1) or i - 1, r, g, b)
	end
else
	for i = 1, #rgb_lookup do
		term.native().setPaletteColour(i - 1, rgb_lookup[i][1], rgb_lookup[i][2], rgb_lookup[i][3])
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

local function rgba_to_index_colour(width, height, albedo_buffer, index_colour_buffer, use_fast_palette)
	local albedo_index = 1
	local math_min = math.min
	local math_max = math.max
	local math_floor = math.floor
	local math_abs = math.abs

	-- local dithering_factor = (math.sin(t * 3) + 1) / 2
	local alg_r = dithering_factor * hatch_dither_factor

	local sum_n = 0

	local ordered_dithering_map_size = #ordered_dithering_map

	local fringe_trees = {}
	local fringe_min_distance_squared = {}

	for index_colour_index_base = 0, width * height - 1, width do
		for index_colour_index = index_colour_index_base + 1, index_colour_index_base + width do
			local r = albedo_buffer[albedo_index]
			local g = albedo_buffer[albedo_index + 1]
			local b = albedo_buffer[albedo_index + 2]

			local x = (index_colour_index - 1) % width
			local y = (index_colour_index - x - 1) / width
			local Mij1 = ordered_dithering_map[y % ordered_dithering_map_size + 1][x % ordered_dithering_map_size + 1]
			-- local Mij2 = ordered_dithering_map[ordered_dithering_map_size - y % ordered_dithering_map_size][x % ordered_dithering_map_size + 1]
			-- local Mij3 = ordered_dithering_map[y % ordered_dithering_map_size + 1][ordered_dithering_map_size - x % ordered_dithering_map_size]

			r = math_max(0, math_min(1, r + alg_r * Mij1))
			g = math_max(0, math_min(1, g + alg_r * Mij1))
			b = math_max(0, math_min(1, b + alg_r * Mij1))
			-- g = math_max(0, math_min(1, g + alg_r * Mij2))
			-- b = math_max(0, math_min(1, b + alg_r * Mij3))

			local sample_r = r
			local sample_g = g
			local sample_b = b

			-- local sample_r = math_max(0, math_min(1, r + alg_r * Mij1))
			-- local sample_g = math_max(0, math_min(1, g + alg_r * Mij2))
			-- local sample_b = math_max(0, math_min(1, b + alg_r * Mij3))

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
			local value = math_floor(v ^ (1/value_exp) * MAX_VALUE + 0.5)
			local saturation = math_floor(s * MAX_SATURATION + 0.5)
			local hue = math_floor(h * (MAX_HUE_COUNT - 1) + 0.5)
		
			local index = index_lookups[value + 1][saturation + 1][hue + 1]
			--end

			local pal_rgb = rgb_lookup[index + 1]
			local pal_red = pal_rgb[1]
			local pal_green = pal_rgb[2]
			local pal_blue = pal_rgb[3]

			local albedo_stride = 3

			if not do_fast_dither then
				local error_r = r - pal_red
				local error_g = g - pal_green
				local error_b = b - pal_blue

				if error_r > 0.05 then error_r = 0.05 end
				if error_g > 0.05 then error_g = 0.05 end
				if error_b > 0.05 then error_b = 0.05 end

				if x % 8 ~= 7 and albedo_index + albedo_stride < width * height * albedo_stride then
					albedo_buffer[albedo_index + albedo_stride] = albedo_buffer[albedo_index + albedo_stride] + error_r * 7/16 * dithering_factor
					albedo_buffer[albedo_index + albedo_stride + 1] = albedo_buffer[albedo_index + albedo_stride + 1] + error_g * 7/16 * dithering_factor
					albedo_buffer[albedo_index + albedo_stride + 1] = albedo_buffer[albedo_index + albedo_stride + 1] + error_b * 7/16 * dithering_factor
				end

				if y % 8 ~= 7 and albedo_index + width * albedo_stride < width * height * albedo_stride then
					albedo_buffer[albedo_index + (width - 1) * albedo_stride] = albedo_buffer[albedo_index + (width - 1) * albedo_stride] + error_r * 3/16 * dithering_factor
					albedo_buffer[albedo_index + (width - 1) * albedo_stride + 1] = albedo_buffer[albedo_index + (width - 1) * albedo_stride + 1] + error_g * 3/16 * dithering_factor
					albedo_buffer[albedo_index + (width - 1) * albedo_stride + 2] = albedo_buffer[albedo_index + (width - 1) * albedo_stride + 2] + error_b * 3/16 * dithering_factor
					albedo_buffer[albedo_index + width * albedo_stride] = albedo_buffer[albedo_index + width * albedo_stride] + error_r * 5/16 * dithering_factor
					albedo_buffer[albedo_index + width * albedo_stride + 1] = albedo_buffer[albedo_index + width * albedo_stride + 1] + error_g * 5/16 * dithering_factor
					albedo_buffer[albedo_index + width * albedo_stride + 2] = albedo_buffer[albedo_index + width * albedo_stride + 2] + error_b * 5/16 * dithering_factor
				end

				if x % 8 ~= 7 and y % 8 ~= 7 and albedo_index + width * albedo_stride + albedo_stride < width * height * albedo_stride then
					albedo_buffer[albedo_index + (width + 1) * albedo_stride] = albedo_buffer[albedo_index + (width + 1) * albedo_stride] + error_r * 1/16 * dithering_factor
					albedo_buffer[albedo_index + (width + 1) * albedo_stride + 1] = albedo_buffer[albedo_index + (width + 1) * albedo_stride + 1] + error_g * 1/16 * dithering_factor
					albedo_buffer[albedo_index + (width + 1) * albedo_stride + 2] = albedo_buffer[albedo_index + (width + 1) * albedo_stride + 2] + error_b * 1/16 * dithering_factor
				end
			end

			if use_standard_cc then
				index = 2 ^ index
			end

			index_colour_buffer[index_colour_index] = index
			albedo_index = albedo_index + albedo_stride
		end
		index_colour_index_base = index_colour_index_base + width
	end

	-- error(sum_n / (width * height))
end

local layout = v3d.create_layout()
	:add_layer('index_colour', 'any-numeric', 1)
	:add_layer('albedo', 'any-numeric', 3)
	:add_layer('position', 'any-numeric', 3)
	:add_layer('depth', 'depth-reciprocal', 1)
local framebuffer
if use_legacy_cc then
	framebuffer = v3d.create_framebuffer_subpixel(layout, 51, 19)
elseif use_standard_cc then
	framebuffer = v3d.create_framebuffer_subpixel(layout, term.getSize())
else
	framebuffer = v3d.create_framebuffer(layout, term.getSize(2))
end

local grid_palettize_effect = v3d.rgb.palettize_effect {
	layout = layout,
	rgb_layer = 'albedo',
	index_layer = 'index_colour',
	palette = grid_palette,
	ordered_dithering_amount = 0,
	ordered_dithering_r = 0.15,
	exponential_indices = use_standard_cc,
	dynamic_palette = false,
	ordered_dithering_dynamic_amount = true,
}

local kd_palettize_effect = v3d.rgb.palettize_effect {
	layout = layout,
	rgb_layer = 'albedo',
	index_layer = 'index_colour',
	palette = kd_palette,
	ordered_dithering_amount = 0,
	ordered_dithering_r = 0.15,
	exponential_indices = use_standard_cc,
	dynamic_palette = false,
	ordered_dithering_dynamic_amount = true,
}

local hypercube_palettize_effect = v3d.rgb.palettize_effect {
	layout = layout,
	rgb_layer = 'albedo',
	index_layer = 'index_colour',
	palette = hypercube_palette,
	ordered_dithering_amount = 0,
	ordered_dithering_r = 0.15,
	exponential_indices = use_standard_cc,
	dynamic_palette = false,
	ordered_dithering_dynamic_amount = true,
}

local palettize_effect = v3d.rgb.palettize_effect {
	layout = layout,
	rgb_layer = 'albedo',
	index_layer = 'index_colour',
	palette = palette,
	ordered_dithering_amount = 0,
	ordered_dithering_r = 0.15,
	exponential_indices = use_standard_cc,
	dynamic_palette = false,
	ordered_dithering_dynamic_amount = true,
}

local camera_x, camera_y, camera_z, camera_rotation, camera_pitch = 10, 20, 10, math.pi / 6, math.pi / 4
local geometry = v3d.create_debug_cube():build()
local pipeline = v3d.create_pipeline {
	layout = layout,
	format = v3d.support.DEBUG_CUBE_FORMAT,
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

			if v3d_read_uniform('image') then
				local image = v3d_read_uniform('image')
				local u = v3d_read_attribute('uv', 1)
				local v = v3d_read_attribute('uv', 2)
				local ix = _v3d_math_floor(u * (image.width - 1))
				local iy = _v3d_math_floor(v * (image.height - 1))
				local idx = (iy * image.width + ix) * 3
				write_r = (image[idx + 1] or 1)
				write_g = (image[idx + 2] or 1)
				write_b = (image[idx + 3] or 1)
			end

			-- local x, y, z = v3d_fragment_world_position()
			-- local normal_r, normal_g, normal_b = v3d_face_world_normal()

			-- for i = 1, #u_lights do
			-- 	local light = u_lights[i]
			-- 	local dx = light[1] - x
			-- 	local dy = light[2] - y
			-- 	local dz = light[3] - z
			-- 	local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
			-- 	local dot = math.max(0, (normal_r * dx + normal_g * dy + normal_b * dz) / distance)
			-- 	local k = dot / (1 + distance)

			-- 	write_r = write_r + r * light[4] * k
			-- 	write_g = write_g + g * light[5] * k
			-- 	write_b = write_b + b * light[6] * k
			-- end

			-- local current_r, current_g, current_b, _ = v3d_read_layer_values('albedo')

			-- local alpha = v3d_read_uniform('alpha')
			-- write_r = current_r * (1 - alpha) + write_r * alpha
			-- write_g = current_g * (1 - alpha) + write_g * alpha
			-- write_b = current_b * (1 - alpha) + write_b * alpha

			v3d_write_layer_values('albedo', write_r, write_g, write_b)
			-- v3d_write_layer_values('albedo', normal_r, normal_g, normal_b)
			-- v3d_write_layer_values('albedo', x / -25, y, z / -25)
			-- v3d_write_layer('index_colour', rgb_to_idx(write_r, write_g, write_b))
			v3d_write_layer('depth', v3d_fragment_depth())
			v3d_count_event('fragment_drawn')
		end
	]],
	statistics = true,
}

local scene = {}
local object_colours = {}

-- table.insert(scene, v3d.translate(50, 0, -50) * v3d.scale(100, 0.1, 100))
table.insert(scene, v3d.translate(-50, -1, -50) * v3d.scale(100, 0.1, 100))
object_colours[1] = { 1, 1, 1 }

if true then
	for _ = 1, n_cubes do
		local scale_value = math.random(10, 30) / 10
		local position = v3d.translate(math.random(-100, 0), cube_height_variation and math.random(0, cube_height_variation) or -1 + scale_value / 2, math.random(-100, 0))
		local rotation = v3d.rotate(0, math.random() * math.pi * 2, 0)
		local scale = v3d.scale(scale_value)
		table.insert(scene, position * rotation * scale)
	end

	for i = 2, #scene do
		object_colours[i] = { hsv_to_rgb(math.random(), cube_saturation, 1) }
	end
end

for i = 1, grid_palette:count() do
	local r, g, b = grid_palette:get_colour(i)
	table.insert(scene, v3d.translate(r * 25 - 25, g * 25, b * 25 - 25))
	table.insert(object_colours, { r, g, b })
end

local lights = {}

if do_lighting then
	table.insert(lights, { -50, 5, -50, 0, 0, 20 })
	table.insert(lights, { -25, 5, -25, 3, 10, 3 })
	table.insert(lights, { 0, 5, -25, 10, 4, 4 })
end

pipeline:set_uniform('rgb_to_idx', fast_rgb_to_idx)
pipeline:set_uniform('lights', lights)
pipeline:set_uniform('ambient', do_lighting and ambient_lighting or 1)
pipeline:set_uniform('alpha', 1)

local effect = v3d.create_effect({
	layout = layout,
	pixel_shader = [[
		{% for i = 1, 3 do %}
		do
			local value = v3d_read_layer('albedo', ${i})
			v3d_write_layer('albedo', ${i}, 1 - value)
		end
		{% end %}
	]],
})

local h = assert(io.open('/.v3d_crash_dump.txt', 'w'))
-- h:write(effect:get_shaders()['apply'].compiled)
h:write 'do '
h:write(pipeline:get_shaders()['render_geometry'].compiled)
h:write ' end\ndo '
h:write(pipeline:get_shaders()['fragment_shader'].compiled)
h:write ' end\n'
h:write(palettize_effect:get_shaders()['apply'].compiled)
h:close()

local statistics

local camera_move_fwd = 0
local camera_move_strafe = 0
local camera_move_up = 0
local camera_delta_rotation = 0
local camera_delta_pitch = 0

local paused = false

local ordered_dithering_amount = use_standard_cc and 0.2 or 1

local fps = 0
local palettize_time = 0
local render_time = 0
local stat_convergence = 0.5
local last_frame_time = os.clock()

while true do
	local transform = v3d.camera(camera_x, camera_y, camera_z, camera_pitch, camera_rotation, 0, math.pi / 2)

	local t_render_start = os.clock()
	-- transform = transform * v3d.rotate(0, 0.05, 0)
	framebuffer:clear('index_colour', 1)
	framebuffer:clear_values('albedo', { hsv_to_rgb(t / 6, 0.5, 1) })
	framebuffer:clear('depth')

	if do_lighting then
		lights[1][1] = math.sin(t) * -25 - 25
	end

	statistics = nil

	for i = #scene, 1, -1 do
		pipeline:set_uniform('red', object_colours[i][1])
		pipeline:set_uniform('green', object_colours[i][2])
		pipeline:set_uniform('blue', object_colours[i][3])
		pipeline:set_uniform('image', images[(i - 1) % #images + 1])
		local this_statistics = pipeline:render_geometry(framebuffer, geometry, transform, scene[i])

		if statistics then
			for k, v in pairs(this_statistics) do
				if type(v) == 'number' then
					statistics[k] = statistics[k] + v
				else
					for kk, vv in pairs(v) do
						statistics[k][kk] = statistics[k][kk] + vv
					end
				end
			end
		else
			statistics = this_statistics
		end
	end

	render_time = render_time * (1 - stat_convergence) + (os.clock() - t_render_start) * stat_convergence

	-- effect:apply(framebuffer)
	-- effect:apply(framebuffer, 120, 200, 400, 150)

	local t0 = os.clock()
	if palettization == 'effect-slow' then
		kd_palettize_effect:set_uniform('ordered_dithering_amount', ordered_dithering_amount)
		kd_palettize_effect:apply(framebuffer)
	elseif palettization == 'effect-fast' then
		grid_palettize_effect:set_uniform('ordered_dithering_amount', ordered_dithering_amount)
		grid_palettize_effect:apply(framebuffer)
	elseif palettization == 'effect-hypercube' then
		hypercube_palettize_effect:set_uniform('ordered_dithering_amount', ordered_dithering_amount)
		hypercube_palettize_effect:apply(framebuffer)
	elseif palettization == 'slow' then
		rgba_to_index_colour(framebuffer.width, framebuffer.height, framebuffer:get_buffer('albedo'), framebuffer:get_buffer('index_colour'), use_fast_palette)
	else
		error(palettization)
	end
	palettize_time = palettize_time * (1 - stat_convergence) + (os.clock() - t0) * stat_convergence

	if use_standard_cc then
		framebuffer:blit_term_subpixel(term, 'index_colour')
	else
		framebuffer:blit_graphics(term, 'index_colour')
	end

	if use_standard_cc and not use_legacy_cc then
		term.setCursorPos(1, 1)
		term.setBackgroundColour(colours.black)
		term.setTextColour(colours.white)
		print(textutils.serialize(statistics))
	end
	-- local timer = os.startTimer(last_frame_time + 0.05 - os.clock())
	local timer = os.startTimer(0)

	if not pcall(function()
		repeat
			local event = { os.pullEvent() }
			if event[1] == 'key' and not event[3] then
				if event[2] == keys.w then
					camera_move_fwd = camera_move_fwd + 1
				elseif event[2] == keys.s then
					camera_move_fwd = camera_move_fwd - 1
				elseif event[2] == keys.a then
					camera_move_strafe = camera_move_strafe + 1
				elseif event[2] == keys.d then
					camera_move_strafe = camera_move_strafe - 1
				elseif event[2] == keys.space then
					camera_move_up = camera_move_up + 1
				elseif event[2] == keys.leftShift then
					camera_move_up = camera_move_up - 1
				elseif event[2] == keys.left then
					camera_delta_rotation = camera_delta_rotation + 1
				elseif event[2] == keys.right then
					camera_delta_rotation = camera_delta_rotation - 1
				elseif event[2] == keys.up then
					camera_delta_pitch = camera_delta_pitch - 1
				elseif event[2] == keys.down then
					camera_delta_pitch = camera_delta_pitch + 1
				elseif event[2] == keys.e then
					ordered_dithering_amount = ordered_dithering_amount + 0.1
				elseif event[2] == keys.q then
					ordered_dithering_amount = ordered_dithering_amount - 0.1
				elseif event[2] == keys.p then
					paused = not paused
				end
			elseif event[1] == 'key_up' then
				if event[2] == keys.w then
					camera_move_fwd = camera_move_fwd - 1
				elseif event[2] == keys.s then
					camera_move_fwd = camera_move_fwd + 1
				elseif event[2] == keys.a then
					camera_move_strafe = camera_move_strafe - 1
				elseif event[2] == keys.d then
					camera_move_strafe = camera_move_strafe + 1
				elseif event[2] == keys.space then
					camera_move_up = camera_move_up - 1
				elseif event[2] == keys.leftShift then
					camera_move_up = camera_move_up + 1
				elseif event[2] == keys.left then
					camera_delta_rotation = camera_delta_rotation - 1
				elseif event[2] == keys.right then
					camera_delta_rotation = camera_delta_rotation + 1
				elseif event[2] == keys.up then
					camera_delta_pitch = camera_delta_pitch + 1
				elseif event[2] == keys.down then
					camera_delta_pitch = camera_delta_pitch - 1
				end
			end
		until event[1] == 'timer' and event[2] == timer
	end) then break end
	local dt = os.clock() - last_frame_time
	last_frame_time = os.clock()

	fps = fps * (1 - stat_convergence) + stat_convergence / dt

	camera_x = camera_x - (math.sin(camera_rotation) * camera_move_fwd + math.cos(camera_rotation) * camera_move_strafe) * dt * 20
	camera_y = camera_y + camera_move_up
	camera_z = camera_z - (math.cos(camera_rotation) * camera_move_fwd - math.sin(camera_rotation) * camera_move_strafe) * dt * 20
	camera_rotation = camera_rotation + camera_delta_rotation * dt * 1
	camera_pitch = camera_pitch + camera_delta_pitch * dt * 1

	if paused then
		dt = 0
	end

	for i = 2, #scene do
		-- scene[i] = v3d.translate(0, math.random() - 0.5, 0) * scene[i] * v3d.rotate(0, math.random() * 0.1, 0)
		scene[i] = scene[i] * v3d.rotate(0, math.random() * dt, 0)
	end

	t = t + dt
end

term.native().setGraphicsMode(0)
term.native().setCursorPos(1, 1)
term.native().setBackgroundColour(colours.black)
term.native().setTextColour(colours.white)
term.clear()
print('Resolution:', framebuffer.width, framebuffer.height)
print(textutils.serialize(statistics))
print('FPS:', math.floor(fps))
print('Palettize:', math.floor(palettize_time * 1000) .. 'ms')
print('Render:', math.floor(render_time * 1000) .. 'ms')

for i = 0, 15 do
	term.native().setPaletteColour(2 ^ i, term.nativePaletteColour(2 ^ i))
end
