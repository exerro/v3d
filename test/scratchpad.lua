
local t = 0

local fixed_palette_size = 256

local use_fast_palette = not fixed_palette_size or fixed_palette_size == 255

local use_standard_cc = fixed_palette_size <= 16

local do_fast_dither = true
local dithering_factor = 0.9
local hatch_dither_factor = 0.1

local n_cubes = 10000
local cube_saturation = 0.9

local ambient_lighting = 0.5

local do_lighting = true

local value_exp = 2.2

--- @class KDTreeNodeConstructorLeaf
--- @field is_leaf true
--- @field colours { [integer]: number }
--- @field max_distance number | nil
--- @field field_selector integer | nil 1 .. 3
--- @field normal_r number | nil
--- @field normal_g number | nil
--- @field normal_b number | nil

--- @class KDTreeNodeConstructorBranch: { [integer]: number }
--- @field is_leaf false
--- @field lt KDTreeNodeConstructor
--- @field gt KDTreeNodeConstructor
--- @field lt_dst number
--- @field gt_dst number
--- @field mid_r number
--- @field mid_g number
--- @field mid_b number
--- @field normal_r number
--- @field normal_g number
--- @field normal_b number

--- @alias KDTreeNodeBranch { is_leaf: false, [1]: KDTreeNode, [2]: KDTreeNode, [3]: number, [4]: number, [5]: number, [6]: number, [7]: number, [8]: number, [9]: number, [10]: number }

--- @alias KDTreeNodeConstructor KDTreeNodeConstructorLeaf | KDTreeNodeConstructorBranch
--- @alias KDTreeNode { is_leaf: true, [1]: number, [2]: number, [3]: number, [4]: integer } | KDTreeNodeBranch

--- @param nodes integer
--- @param colours number[]
--- @return KDTreeNode
local function build_tree(nodes, colours)
	local tree = { is_leaf = true, colours = colours }
	--- @type KDTreeNodeConstructor[]
	local candidates = { tree }
	
	local math_abs = math.abs
	local math_huge = math.huge

	-- repeatedly split candidates
	for n_candidates = 1, nodes - 1 do
		local max_distance = 0
		--- @type integer
		local max_distance_candidate_index

		for i = 1, n_candidates do
			local candidate = candidates[i]
			local c_max_distance = candidate.max_distance

			if not c_max_distance then
				local c_colours = candidate.colours
				local min_r = c_colours[1]
				local min_g = c_colours[2]
				local min_b = c_colours[3]
				local max_r = min_r
				local max_g = min_g
				local max_b = min_b

				for idx = 4, #c_colours, 3 do
					local r = c_colours[idx]
					local g = c_colours[idx + 1]
					local b = c_colours[idx + 2]

					if r < min_r then min_r = r
					elseif r > max_r then max_r = r
					end

					if g < min_g then min_g = g
					elseif g > max_g then max_g = g
					end

					if b < min_b then min_b = b
					elseif b > max_b then max_b = b
					end
				end

				local dst_r = max_r - min_r
				local dst_g = max_g - min_g
				local dst_b = max_b - min_b

				if dst_r > dst_g then
					if dst_r > dst_b then
						c_max_distance = dst_r
						candidate.normal_r = 1
						candidate.normal_g = 0
						candidate.normal_b = 0
						candidate.field_selector = 1
						
					else
						c_max_distance = dst_b
						candidate.normal_r = 0
						candidate.normal_g = 0
						candidate.normal_b = 1
						candidate.field_selector = 3
					end
				else
					if dst_g > dst_b then
						c_max_distance = dst_g
						candidate.normal_r = 0
						candidate.normal_g = 1
						candidate.normal_b = 0
						candidate.field_selector = 2
					else
						c_max_distance = dst_b
						candidate.normal_r = 0
						candidate.normal_g = 0
						candidate.normal_b = 1
						candidate.field_selector = 3
					end
				end

				candidate.max_distance = c_max_distance
			end

			if c_max_distance > max_distance and #candidate.colours > 3 then
				max_distance = c_max_distance
				max_distance_candidate_index = i
			end
		end

		if not max_distance_candidate_index then
			break
		end

		local candidate = candidates[max_distance_candidate_index]
		local c_colours = candidate.colours
		local c_field_selector = candidate.field_selector
		local c_normal_r = candidate.normal_r
		local c_normal_g = candidate.normal_g
		local c_normal_b = candidate.normal_b
		local sum_distance = 0
		local num_colours = #c_colours

		for j = c_field_selector, num_colours, 3 do
			sum_distance = sum_distance + c_colours[j]
		end

		local avg_distance = sum_distance * 3 / num_colours
		local mid_r = avg_distance * c_normal_r
		local mid_g = avg_distance * c_normal_g
		local mid_b = avg_distance * c_normal_b
		local threshold = c_field_selector == 1 and mid_r or c_field_selector == 2 and mid_g or mid_b

		local lt_filtered = {}
		local gt_filtered = {}
		local lt_filtered_index = 1
		local gt_filtered_index = 1
		local lt_min_dst = math_huge
		local gt_min_dst = math_huge

		for j = 0, num_colours - 1, 3 do
			local r = c_colours[j + 1]
			local g = c_colours[j + 2]
			local b = c_colours[j + 3]
			local delta = c_colours[j + c_field_selector] - threshold
			local delta_abs = math_abs(delta)

			if delta > 0 then
				gt_filtered[gt_filtered_index] = r
				gt_filtered[gt_filtered_index + 1] = g
				gt_filtered[gt_filtered_index + 2] = b
				gt_filtered_index = gt_filtered_index + 3
				if delta_abs < gt_min_dst then gt_min_dst = delta_abs end
			else
				lt_filtered[lt_filtered_index] = r
				lt_filtered[lt_filtered_index + 1] = g
				lt_filtered[lt_filtered_index + 2] = b
				lt_filtered_index = lt_filtered_index + 3
				if delta_abs < lt_min_dst then lt_min_dst = delta_abs end
			end
		end

		candidate.is_leaf = false
		candidate.lt = { is_leaf = true, colours = lt_filtered }
		candidate.gt = { is_leaf = true, colours = gt_filtered }
		candidate.lt_dst = lt_min_dst
		candidate.gt_dst = gt_min_dst
		candidate.mid_r = mid_r
		candidate.mid_g = mid_g
		candidate.mid_b = mid_b
		candidate.normal_r = c_normal_r
		candidate.normal_g = c_normal_g
		candidate.normal_b = c_normal_b

		candidates[max_distance_candidate_index] = candidate.lt
		candidates[n_candidates + 1] = candidate.gt
	end

	-- compute average colour for each leaf
	for i = 1, #candidates do
		local candidate = candidates[i]
		local c_colours = candidate.colours
		local num_colours = #c_colours
		local sum_r = 0
		local sum_g = 0
		local sum_b = 0

		for j = 1, num_colours, 3 do
			sum_r = sum_r + c_colours[j]
			sum_g = sum_g + c_colours[j + 1]
			sum_b = sum_b + c_colours[j + 2]
		end

		local multiplier = num_colours == 0 and 0 or 3 / num_colours

		candidate[1] = sum_r * multiplier
		candidate[2] = sum_g * multiplier
		candidate[3] = sum_b * multiplier
		candidate[4] = i
	end

	-- convert branches to flat structure
	local fringe = { tree }
	while fringe[1] do
		local f = table.remove(fringe, 1)
		if not f.is_leaf then
			f[1] = f.lt
			f[2] = f.gt
			f[3] = f.lt_dst
			f[4] = f.gt_dst
			f[5] = f.mid_r
			f[6] = f.mid_g
			f[7] = f.mid_b
			f[8] = f.normal_r
			f[9] = f.normal_g
			f[10] = f.normal_b
			table.insert(fringe, f.lt)
			table.insert(fringe, f.gt)
		end
	end

	return tree
end

local math_sqrt = math.sqrt
local math_min = math.min

--- @param tree KDTreeNode
local function tree_find(tree, r, g, b, best_distance)
	if tree.is_leaf then
		local tree_r = tree[1]
		local tree_g = tree[2]
		local tree_b = tree[3]
		local delta_r = tree_r - r
		local delta_g = tree_g - g
		local delta_b = tree_b - b
		return tree_r, tree_g, tree_b, tree[4], math_sqrt(delta_r * delta_r + delta_g * delta_g + delta_b * delta_b), 1
	end

	--- @cast tree KDTreeNodeBranch
	local dst = (r - tree[5]) * tree[8] + (g - tree[6]) * tree[9] + (b - tree[7]) * tree[10]

	if dst > 0 then
		local result_r, result_g, result_b, result_idx, result_dst, result_n = tree_find(tree[2], r, g, b, best_distance)

		best_distance = math_min(best_distance, result_dst)

		if best_distance > tree[3] + dst then -- might be in other half of tree... gotta search
			local alt_r, alt_g, alt_b, alt_idx, alt_dst, alt_n = tree_find(tree[1], r, g, b, best_distance)
			if alt_dst < result_dst then
				result_r = alt_r
				result_g = alt_g
				result_b = alt_b
				result_idx = alt_idx
				result_dst = alt_dst
			end
			result_n = result_n + alt_n
		end

		return result_r, result_g, result_b, result_idx, result_dst, result_n
	else
		local result_r, result_g, result_b, result_idx, result_dst, result_n = tree_find(tree[1], r, g, b, best_distance)

		best_distance = math_min(best_distance, result_dst)

		if best_distance > tree[4] - dst then -- might be in other half of tree... gotta search
			local alt_r, alt_g, alt_b, alt_idx, alt_dst, alt_n = tree_find(tree[2], r, g, b, best_distance)
			if alt_dst < result_dst then
				result_r = alt_r
				result_g = alt_g
				result_b = alt_b
				result_idx = alt_idx
				result_dst = alt_dst
			end
			result_n = result_n + alt_n
		end

		return result_r, result_g, result_b, result_idx, result_dst, result_n
	end
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

-- build palette kd tree
local rgb_lookup_flattened = {}
for i = 1, #rgb_lookup do
	rgb_lookup_flattened[i * 3 - 2] = rgb_lookup[i][1]
	rgb_lookup_flattened[i * 3 - 1] = rgb_lookup[i][2]
	rgb_lookup_flattened[i * 3 - 0] = rgb_lookup[i][3]
end
local palette_kd_tree = build_tree(fixed_palette_size or #rgb_lookup, rgb_lookup_flattened)

-- set the palette
--- @param tree KDTreeNode
local function fix_palette_indices(tree)
	if tree.is_leaf then
		local found = false
		for i = 1, #rgb_lookup do
			if tree[1] == rgb_lookup[i][1] and tree[2] == rgb_lookup[i][2] and tree[3] == rgb_lookup[i][3] then
				tree[4] = i - 1
				found = true
				break
			end
		end
		if not found then
			error('fuck')
		end
	else
		fix_palette_indices(tree[1])
		fix_palette_indices(tree[2])
	end
end
--- @param tree KDTreeNode
local function set_palette_indices(tree)
	if tree.is_leaf then
		term.native().setPaletteColour(use_standard_cc and 2 ^ (tree[4] - 1) or tree[4] - 1, tree[1], tree[2], tree[3])
	else
		set_palette_indices(tree[1])
		set_palette_indices(tree[2])
	end
end
if not use_fast_palette then
	for i = fixed_palette_size, use_standard_cc and 15 or 255 do
		term.native().setPaletteColour(i, 0, 0, 0)
	end

	set_palette_indices(palette_kd_tree)
else
	for i = 1, #rgb_lookup do
		term.native().setPaletteColour(i - 1, rgb_lookup[i][1], rgb_lookup[i][2], rgb_lookup[i][3])
	end
	fix_palette_indices(palette_kd_tree)
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
	local math_huge = math.huge

	-- local dithering_factor = (math.sin(t * 3) + 1) / 2
	local alg_r = dithering_factor * hatch_dither_factor

	local sum_n = 0

	for index_colour_index_base = 0, width * height - 1, width do
		for index_colour_index = index_colour_index_base + 1, index_colour_index_base + width do
			local r = albedo_buffer[albedo_index]
			local g = albedo_buffer[albedo_index + 1]
			local b = albedo_buffer[albedo_index + 2]

			local x = (index_colour_index - 1) % width
			local y = (index_colour_index - x - 1) / width
			local Mij1 = ordered_dithering_map[y % #ordered_dithering_map + 1][x % #ordered_dithering_map[1] + 1]
			local Mij2 = ordered_dithering_map[#ordered_dithering_map - y % #ordered_dithering_map][x % #ordered_dithering_map[1] + 1]
			local Mij3 = ordered_dithering_map[y % #ordered_dithering_map + 1][#ordered_dithering_map[1] - x % #ordered_dithering_map[1]]

			r = math_max(0, math_min(1, r + alg_r * Mij1))
			g = math_max(0, math_min(1, g + alg_r * Mij2))
			b = math_max(0, math_min(1, b + alg_r * Mij3))

			local sample_r = r
			local sample_g = g
			local sample_b = b

			-- local sample_r = math_max(0, math_min(1, r + alg_r * Mij1))
			-- local sample_g = math_max(0, math_min(1, g + alg_r * Mij2))
			-- local sample_b = math_max(0, math_min(1, b + alg_r * Mij3))

			local pal_red, pal_green, pal_blue, index
			if use_fast_palette then
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
			
				index = index_lookups[value + 1][saturation + 1][hue + 1]
				--end

				local pal_rgb = rgb_lookup[index + 1]
				pal_red = pal_rgb[1]
				pal_green = pal_rgb[2]
				pal_blue = pal_rgb[3]
			else
				local _, n
				pal_red, pal_green, pal_blue, index, _, n = tree_find(palette_kd_tree, r, g, b, math_huge)
				sum_n = sum_n + n
				index = index - 1
			end

			local albedo_stride = 3

			if not do_fast_dither then
				local error_r = r - pal_red
				local error_g = g - pal_green
				local error_b = b - pal_blue

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

if false then
	local size = 4
	local lines = {}

	i = 0

	for value = 0, MAX_VALUE do
		for chroma = 0, value do
			local hue_count = hue_counts[value + 1][chroma + 1]

			table.insert(lines, "")

			for _ = 1, hue_count do
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

	for r = 0, 1, 0.1 do
		local line = ""
		for b = 0, 1, 0.25 do
			for g = 0, 1, 0.1 do
				line = line .. string.char((select(4, tree_find(palette_kd_tree, r, g, b, math.huge)))):rep(size)
			end
		end
		table.insert(lines, line)
	end

	for g = 0, 1, 0.1 do
		local line = ""
		for r = 0, 1, 0.25 do
			for b = 0, 1, 0.1 do
				line = line .. string.char((select(4, tree_find(palette_kd_tree, r, g, b, math.huge)))):rep(size)
			end
		end
		table.insert(lines, line)
	end

	for r = 0, 1, 0.1 do
		local line = ""
		for g = 0, 1, 0.25 do
			for b = 0, 1, 0.1 do
				line = line .. string.char((select(4, tree_find(palette_kd_tree, r, g, b, math.huge)))):rep(size)
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
local framebuffer
if use_standard_cc then
	framebuffer = v3d.create_framebuffer_subpixel(layout, term.getSize())
else
	framebuffer = v3d.create_framebuffer(layout, term.getSize(2))
end

local camera_x, camera_y, camera_z, camera_rotation, camera_pitch = 10, 20, 10, math.pi / 6, math.pi / 4
local geometry = v3d.create_debug_cube():build()
local pipeline = v3d.create_pipeline {
	layout = layout,
	format = v3d.DEBUG_CUBE_FORMAT,
	position_attribute = 'position',
	-- cull_face = false,
	-- fragment_shader = [[
	-- 	if v3d_compare_depth(v3d_fragment_depth(), v3d_read_layer('depth')) then
	-- 		-- local r, g, b = v3d_read_attribute_values('position')
	-- 		-- r = r + 0.5
	-- 		-- g = g + 0.5
	-- 		-- b = b + 0.5
	-- 		-- local rgb_to_idx = v3d_read_uniform('rgb_to_idx')
	-- 		local r = v3d_read_uniform('red')
	-- 		local g = v3d_read_uniform('green')
	-- 		local b = v3d_read_uniform('blue')
	-- 		local u_lights = v3d_read_uniform('lights')

	-- 		local write_r = r * v3d_read_uniform('ambient')
	-- 		local write_g = g * v3d_read_uniform('ambient')
	-- 		local write_b = b * v3d_read_uniform('ambient')

	-- 		local x, y, z = v3d_fragment_world_position()
	-- 		local normal_r, normal_g, normal_b = v3d_face_world_normal()

	-- 		for i = 1, #u_lights do
	-- 			local light = u_lights[i]
	-- 			local dx = light[1] - x
	-- 			local dy = light[2] - y
	-- 			local dz = light[3] - z
	-- 			local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
	-- 			local dot = math.max(0, (normal_r * dx + normal_g * dy + normal_b * dz) / distance)
	-- 			local k = dot / (1 + distance)

	-- 			write_r = write_r + r * light[4] * k
	-- 			write_g = write_g + g * light[5] * k
	-- 			write_b = write_b + b * light[6] * k
	-- 		end

	-- 		-- local current_r, current_g, current_b, _ = v3d_read_layer_values('albedo')

	-- 		-- local alpha = v3d_read_uniform('alpha')
	-- 		-- write_r = current_r * (1 - alpha) + write_r * alpha
	-- 		-- write_g = current_g * (1 - alpha) + write_g * alpha
	-- 		-- write_b = current_b * (1 - alpha) + write_b * alpha

	-- 		v3d_write_layer_values('albedo', write_r, write_g, write_b)
	-- 		-- v3d_write_layer_values('albedo', normal_r, normal_g, normal_b)
	-- 		-- v3d_write_layer_values('albedo', x / -25, y, z / -25)
	-- 		-- v3d_write_layer('index_colour', rgb_to_idx(write_r, write_g, write_b))
	-- 		v3d_write_layer('depth', v3d_fragment_depth())
	-- 		v3d_count_event('fragment_drawn')
	-- 	end
	-- ]],
	fragment_shader = [[
		if v3d_compare_depth(v3d_fragment_depth(), v3d_read_layer('depth')) then
			local write_r = v3d_read_uniform('red') * v3d_read_uniform('ambient')
			local write_g = v3d_read_uniform('green') * v3d_read_uniform('ambient')
			local write_b = v3d_read_uniform('blue') * v3d_read_uniform('ambient')
		
			local x, y, z = v3d_fragment_world_position()
			local normal_r, normal_g, normal_b = v3d_face_world_normal()
		
			for i = 1, #v3d_read_uniform('lights') do
				local light = v3d_read_uniform('lights')[i]
				local dx = light[1] - x
				local dy = light[2] - y
				local dz = light[3] - z
				local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
				local dot = math.max(0, (normal_r * dx + normal_g * dy + normal_b * dz) / distance)
				local k = dot / (1 + distance)
		
				write_r = write_r + v3d_read_uniform('red') * light[4] * k
				write_g = write_g + v3d_read_uniform('green') * light[5] * k
				write_b = write_b + v3d_read_uniform('blue') * light[6] * k
			end
		
			v3d_write_layer_values('albedo', write_r, write_g, write_b)
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

--- @param tree KDTreeNode
local function visualise_kd(tree, depth, min_x, min_y, min_z, max_x, max_y, max_z)
	if tree.is_leaf then
		table.insert(scene, v3d.scale(25, 25, 25) * v3d.translate(tree[1] - 1, tree[2], tree[3] - 1) * v3d.scale(0.02))
		table.insert(object_colours, { tree[1], tree[2], tree[3] })
	else
		local cx = (min_x + max_x) / 2 * (1 - tree[8]) + tree[5]
		local cy = (min_y + max_y) / 2 * (1 - tree[9]) + tree[6]
		local cz = (min_z + max_z) / 2 * (1 - tree[10]) + tree[7]
		if depth <= 5 then
			table.insert(scene, v3d.translate(-25, 0, -25) * v3d.scale(25) * v3d.translate(cx, cy, cz) * v3d.scale((1 - tree[8]) * (max_x - min_x), (1 - tree[9]) * (max_y - min_y), (1 - tree[10]) * (max_z - min_z)))
			table.insert(object_colours, { hsv_to_rgb(depth / 5, 0.5, 1) })
		end
		visualise_kd(tree[1], depth + 1, min_x, min_y, min_z, max_x * (1 - tree[8]) + cx * tree[8], max_y * (1 - tree[9]) + cy * tree[9], max_z * (1 - tree[10]) + cz * tree[10])
		visualise_kd(tree[2], depth + 1, min_x * (1 - tree[8]) + cx * tree[8], min_y * (1 - tree[9]) + cy * tree[9], min_z * (1 - tree[10]) + cz * tree[10], max_x, max_y, max_z)
	end
end

if false then
	visualise_kd(palette_kd_tree, 1, 0, 0, 0, 1, 1, 1)
	
	local o = {}
	for i = 1, #scene do
		o[i] = { scene[i], object_colours[i] }
	end
	table.sort(o, function(a, b) return a[1][4] + a[1][12] * 0.5 < b[1][4] + b[1][12] * 0.5 end)
	for i = 1, #o do
		scene[i] = o[i][1]
		object_colours[i] = o[i][2]
	end
end

for _ = 1, n_cubes do
	local scale_value = math.random(10, 30) / 10
	local position = v3d.translate(math.random(-100, 0), -1 + scale_value / 2, math.random(-100, 0))
	local rotation = v3d.rotate(0, math.random() * math.pi * 2, 0)
	local scale = v3d.scale(scale_value)
	table.insert(scene, position * rotation * scale)
end

for i = 2, #scene do
	object_colours[i] = { hsv_to_rgb(math.random(), cube_saturation, 1) }
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

local h = assert(io.open('/.v3d_crash_dump.txt', 'w'))
h:write(pipeline.source)
h:close()

local statistics

local camera_move_fwd = 0
local camera_move_strafe = 0
local camera_delta_rotation = 0
local camera_delta_pitch = 0

while true do
	local transform = v3d.camera(camera_x, camera_y, camera_z, camera_pitch, camera_rotation, 0, math.pi / 2)

	-- transform = transform * v3d.rotate(0, 0.05, 0)
	framebuffer:clear('index_colour', 0)
	framebuffer:clear('albedo', 0)
	framebuffer:clear('depth')

	if do_lighting then
		lights[1][1] = math.sin(t) * -25 - 25
	end

	statistics = nil

	for i = #scene, 1, -1 do
		pipeline:set_uniform('red', object_colours[i][1])
		pipeline:set_uniform('green', object_colours[i][2])
		pipeline:set_uniform('blue', object_colours[i][3])
		local this_statistics = pipeline:render_geometry(geometry, framebuffer, transform, scene[i])

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

	for i = 2, #scene do
		scene[i] = v3d.translate(0, math.random() - 0.5, 0) * scene[i] * v3d.rotate(0, math.random() * 0.1, 0)
	end

	rgba_to_index_colour(framebuffer.width, framebuffer.height, framebuffer:get_buffer('albedo'), framebuffer:get_buffer('index_colour'), use_fast_palette)

	if use_standard_cc then
		framebuffer:blit_term_subpixel(term, 'index_colour')
	else
		framebuffer:blit_graphics(term, 'index_colour')
	end
	term.setCursorPos(1, 1)
	term.setBackgroundColour(colours.black)
	term.setTextColour(colours.white)
	print(textutils.serialize(statistics))
	local timer = os.startTimer(0.05)
	local start = os.clock()

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
				elseif event[2] == keys.left then
					camera_delta_rotation = camera_delta_rotation + 1
				elseif event[2] == keys.right then
					camera_delta_rotation = camera_delta_rotation - 1
				elseif event[2] == keys.up then
					camera_delta_pitch = camera_delta_pitch - 1
				elseif event[2] == keys.down then
					camera_delta_pitch = camera_delta_pitch + 1
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
	local dt = os.clock() - start

	camera_x = camera_x - (math.sin(camera_rotation) * camera_move_fwd + math.cos(camera_rotation) * camera_move_strafe) * dt * 20
	camera_z = camera_z - (math.cos(camera_rotation) * camera_move_fwd - math.sin(camera_rotation) * camera_move_strafe) * dt * 20
	camera_rotation = camera_rotation + camera_delta_rotation * dt * 1
	camera_pitch = camera_pitch + camera_delta_pitch * dt * 1

	t = t + dt
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
