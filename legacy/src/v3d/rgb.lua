
local v3d = require 'core'

require 'effect'

v3d.rgb = {}

--------------------------------------------------------------------------------
--[[ v3d.Palette ]]-------------------------------------------------------------
--------------------------------------------------------------------------------

do
	--- TODO
	--- @class v3d.rgb.Palette
	--- @field private n_colours integer
	--- @field private colours number[]
	v3d.rgb.Palette = {}

	--- TODO: remove palette from these names!
	--- @return integer
	--- @nodiscard
	function v3d.rgb.Palette:count()
		return self.n_colours
	end

	--- Return the red, green, and blue components of the specified palette
	--- index. The palette index should be an integer ranging between 1 and the
	--- number of colours in this palette.
	--- @param palette_index integer
	--- @return number red, number blue, number green
	--- @nodiscard
	function v3d.rgb.Palette:get_colour(palette_index)
		local idx = palette_index * 3
		local colours = self.colours

		return colours[idx - 2], colours[idx - 1], colours[idx]
	end

	--- Return all the palette colours flattened into a single table. Colours
	--- are laid out sequentially, i.e. `r1, g1, b1, r2, g2, b2, ...`. The order
	--- of colours within this table will always match palette indices, i.e.
	--- palette index 2 will always begin at index 4 in this table, palette
	--- index 3 will always begin at index 7 in this table, and so on (3i - 2).
	--- @return number[]
	--- @nodiscard
	function v3d.rgb.Palette:get_all_colours()
		return self.colours
	end

	--- We programmatically assign these functions (see create_palette below) so
	--- we don't need to define it here.
	--- @diagnostic disable missing-return

	--- @param red number
	--- @param green number
	--- @param blue number
	--- @return integer palette_index, number red, number green, number blue
	--- @nodiscard
	function v3d.rgb.Palette:lookup_closest(red, green, blue) end

	--- @param in_self string
	--- @param in_red string
	--- @param in_green string
	--- @param in_blue string
	--- @param out_palette_index string | nil
	--- @param out_red string | nil
	--- @param out_green string | nil
	--- @param out_blue string | nil
	--- @return string code, { name: string, value: string, global: boolean }[] cache
	--- @nodiscard
	function v3d.rgb.Palette:embed_lookup_algorithm(
		in_self,
		in_red,
		in_green,
		in_blue,
		out_palette_index,
		out_red,
		out_green,
		out_blue
	) end

	--- @diagnostic enable missing-return
end

--------------------------------------------------------------------------------
--[[ Palette types ]]-----------------------------------------------------------
--------------------------------------------------------------------------------

do
	local function create_palette(base, colours, embed_lookup_algorithm)
		local palette = {}

		for k, v in pairs(v3d.rgb.Palette) do
			palette[k] = v
		end

		for k, v in pairs(base) do
			palette[k] = v
		end

		local lookup_code, lookup_cache = embed_lookup_algorithm(
			palette, 'self', 'red', 'green', 'blue',
			'out_idx', 'out_red', 'out_green', 'out_blue')
		local lookup_closest_source = 'local upvalue_math_floor = math.floor\n'
		                           .. 'local upvalue_math_ceil = math.ceil\n'
		                           .. 'return function(self, red, green, blue)\n'

		for i = 1, #lookup_cache do
			if lookup_cache[i].global then
				lookup_closest_source = 'local ' .. lookup_cache[i].name .. ' = ' .. lookup_cache[i].value .. '\n' .. lookup_closest_source
			else
				lookup_closest_source = lookup_closest_source .. '\tlocal ' .. lookup_cache[i].name .. ' = ' .. lookup_cache[i].value .. '\n'
			end
		end

		lookup_closest_source = lookup_closest_source
		                     .. '\tlocal out_idx, out_red, out_green, out_blue\n'
		                     .. '\t' .. lookup_code:gsub('\n', '\n\t') .. '\n'
		                     .. '\treturn out_idx, out_red, out_green, out_blue\n'
		                     .. 'end'

		local fn, err = load(lookup_closest_source, 'v3d.rgb.Palette:lookup_closest', nil, _ENV)

		if not fn then
			v3d.internal_error(err, lookup_closest_source)
		end

		palette.n_colours = #colours / 3
		palette.colours = colours
		palette.embed_lookup_algorithm = embed_lookup_algorithm
		--- @diagnostic disable-next-line: need-check-nil
		palette.lookup_closest = fn()

		return palette
	end

	--- Create a palette which distributes colours within the unit cube.
	--- This is a default option for palettes as it provides very quick lookup
	--- times with a decent spread of colours to account for all cases.
	--- The number of samples controls how many distinct values for a colour
	--- there are, which can be controlled for all components or for each
	--- component individually.
	--- Saturation controls how close the outer generated palette colours will
	--- be to the edge of the cube, where a saturation of 1 will include "pure"
	--- colours, and a saturation of 0 leaves an equal spacing between the edges
	--- of the cube and adjacent colours in the palette.
	--- Gamma controls a frequency curve which favours a higher concentration
	--- of colours towards certain areas. A high gamma value (e.g. 2) will
	--- concentrate palette colours towards the high end, e.g. you'll have more
	--- variation in the red area than in the black area. A low gamma (e.g. 0.5)
	--- will do the opposite, concentrating palette colours towards black.
	--- TODO: investigate and explain the skew issue I saw.
	--- @param samples integer | { red: integer, green: integer, blue: integer }
	--- @param saturation number | { red: number, green: number, blue: number } | nil
	--- @param gamma number | { red: number, green: number, blue: number } | nil
	--- @return v3d.rgb.Palette
	--- @nodiscard
	function v3d.rgb.grid_palette(samples, saturation, gamma)
		local red_samples = samples
		local green_samples = samples
		local blue_samples = samples
		local red_saturation = saturation or 0.5
		local green_saturation = red_saturation
		local blue_saturation = red_saturation
		local red_gamma = gamma or 1
		local green_gamma = red_gamma
		local blue_gamma = red_gamma

		if type(samples) == 'table' then
			red_samples = samples.red
			green_samples = samples.green
			blue_samples = samples.blue
		end

		if type(saturation) == 'table' then
			red_saturation = saturation.red
			green_saturation = saturation.green
			blue_saturation = saturation.blue
		end

		if type(gamma) == 'table' then
			red_gamma = gamma.red
			green_gamma = gamma.green
			blue_gamma = gamma.blue
		end

		local red_delta = red_samples == 1 and 0 or 1 / (red_samples - 2 * red_saturation + 1)
		local green_delta = green_samples == 1 and 0 or 1 / (green_samples - 2 * green_saturation + 1)
		local blue_delta = blue_samples == 1 and 0 or 1 / (blue_samples - 2 * blue_saturation + 1)

		local red_offset = (1 - (red_samples - 1) * red_delta) * 0.5
		local green_offset = (1 - (green_samples - 1) * green_delta) * 0.5
		local blue_offset = (1 - (blue_samples - 1) * blue_delta) * 0.5

		local colours = {}

		for i = 0, red_samples * green_samples * blue_samples - 1 do
			local red_index = math.floor(i / green_samples / blue_samples)
			local green_index = math.floor(i / blue_samples) % green_samples
			local blue_index = i % blue_samples

			local red = (red_index * red_delta + red_offset) ^ (1 / red_gamma)
			local green = (green_index * green_delta + green_offset) ^ (1 / green_gamma)
			local blue = (blue_index * blue_delta + blue_offset) ^ (1 / blue_gamma)

			table.insert(colours, red)
			table.insert(colours, green)
			table.insert(colours, blue)
		end

		return create_palette(
			{ red_samples, green_samples, blue_samples, red_offset, green_offset, blue_offset, red_delta, green_delta, blue_delta, red_gamma, green_gamma, blue_gamma },
			colours,
			function(self, in_self, in_red, in_green, in_blue, out_palette_index, out_red, out_green, out_blue)
				local function channel(in_var, idx)
					if self[idx] == 1 then
						return ''
					end

					local s = 'local scaled' .. idx .. ' = ' .. in_var

					if math.abs(self[9 + idx] - 1) > 0.001 then
						s = s .. ' ^ ' .. self[9 + idx]
					end

					if self[3 + idx] > 0.001 then
						s = s .. ' - ' .. self[3 + idx]
					end

					s = s .. '\nlocal index' .. idx .. ' = v3d_palette_var_math_floor(scaled' .. idx

					if math.abs(self[6 + idx] - 1) > 0.001 then
						s = s .. ' * ' .. 1/self[6 + idx]
					end

					s = s .. ' + 0.5)\n'
					s = s .. 'if index' .. idx .. ' >= ' .. self[idx] .. ' then index' .. idx .. ' = ' .. (self[idx] - 1) .. ' end\n'
					s = s .. 'if index' .. idx .. ' < 0 then index' .. idx .. ' = 0 end\n'

					return s
				end

				local cache = {
					{ name = 'v3d_palette_var_math_floor', value = 'math.floor', global = true },
				}

				local s = channel(in_red, 1)
				       .. channel(in_green, 2)
				       .. channel(in_blue, 3)

				local parts = {}

				if self[1] > 1 then
					table.insert(parts, 'index1 * ' .. self[2] * self[3])
				end

				if self[2] > 1 then
					table.insert(parts, 'index2 * ' .. self[3])
				end

				if self[3] > 1 then
					table.insert(parts, 'index3')
				end

				if self[1] == 1 and self[2] == 1 and self[3] == 1 then
					table.insert(parts, '0')
				end

				if not out_palette_index then
					out_palette_index = 'palette_index'
					s = s .. 'local '
				end

				s = s .. out_palette_index .. ' = 1 + ' .. table.concat(parts, ' + ')

				if out_red or out_green or out_blue then
					cache[2] = { name = 'v3d_palette_var_colours', value = in_self .. '.colours', global = false }
					s = s .. '\nlocal colour_base_index = ' .. out_palette_index .. ' * 3'
				end

				if out_red then
					s = s .. '\n' .. out_red .. ' = v3d_palette_var_colours[colour_base_index - 2]'
				end

				if out_green then
					s = s .. '\n' .. out_green .. ' = v3d_palette_var_colours[colour_base_index - 1]'
				end

				if out_blue then
					s = s .. '\n' .. out_blue .. ' = v3d_palette_var_colours[colour_base_index]'
				end

				return s, cache
			end
		)
	end

	--- TODO
	--- @return v3d.rgb.Palette
	--- @nodiscard
	function v3d.rgb.hypercube_palette(saturation)
		local colours = {}

		local red_saturation = saturation or 0.5
		local green_saturation = red_saturation
		local blue_saturation = red_saturation

		if type(saturation) == 'table' then
			red_saturation = saturation.red
			green_saturation = saturation.green
			blue_saturation = saturation.blue
		end

		local red_octant_offset = 1 / (5 - red_saturation * 2)
		local red_octant_scale = 2 * red_octant_offset
		local green_octant_offset = 1 / (5 - green_saturation * 2)
		local green_octant_scale = 2 * green_octant_offset
		local blue_octant_offset = 1 / (5 - blue_saturation * 2)
		local blue_octant_scale = 2 * blue_octant_offset

		local i = 1
		for s = 0, 1 do
			for b = 1, -1, -2 do
				for g = 1, -1, -2 do
					for r = 1, -1, -2 do
						colours[i    ] = 0.5 + r * (red_octant_offset + red_octant_scale * s) / 2
						colours[i + 1] = 0.5 + g * (green_octant_offset + green_octant_scale * s) / 2
						colours[i + 2] = 0.5 + b * (blue_octant_offset + blue_octant_scale * s) / 2
						i = i + 3
					end
				end
			end
		end

		return create_palette(
			{ red_octant_offset, green_octant_offset, blue_octant_offset },
			colours,
			function(self, in_self, in_red, in_green, in_blue, out_palette_index, out_red, out_green, out_blue)
				local cache = {
					{ name = 'v3d_palette_var_math_floor', value = 'math.floor', global = true },
				}

				local red_octant_offset = self[1]
				local green_octant_offset = self[2]
				local blue_octant_offset = self[3]
				local scale = 1 / math.min(red_octant_offset, green_octant_offset, blue_octant_offset)

				if red_octant_offset == green_octant_offset then
					scale = 1 / red_octant_offset
				elseif red_octant_offset == blue_octant_offset then
					scale = 1 / red_octant_offset
				elseif green_octant_offset == blue_octant_offset then
					scale = 1 / green_octant_offset
				end

				local red_plane = red_octant_offset * scale
				local green_plane = green_octant_offset * scale
				local blue_plane = blue_octant_offset * scale
				local palette_index_def = out_palette_index

				if not out_palette_index then
					out_palette_index = 'palette_index'
					palette_index_def = 'local ' .. out_palette_index
				end

				local s = v3d.text.unindent([[
					local red = ]] .. in_red .. [[ - 0.5
					local green = ]] .. in_green .. [[ - 0.5
					local blue = ]] .. in_blue .. [[ - 0.5
					]] .. palette_index_def .. [[ = 1

					if red < 0 then
						]] .. out_palette_index .. [[ = ]] .. out_palette_index .. [[ + 1
						red = -red
					end

					if green < 0 then
						]] .. out_palette_index .. [[ = ]] .. out_palette_index .. [[ + 2
						green = -green
					end

					if blue < 0 then
						]] .. out_palette_index .. [[ = ]] .. out_palette_index .. [[ + 4
						blue = -blue
					end

					if red]] .. (math.abs(red_plane - 1) > 0.001 and ' * ' .. red_plane or '') .. [[ 
					 + green]] .. (math.abs(green_plane - 1) > 0.001 and ' * ' .. green_plane or '') .. [[ 
					 + blue]] .. (math.abs(blue_plane - 1) > 0.001 and ' * ' .. blue_plane or '') .. [[ 
					 > ]] .. (red_plane * red_plane + green_plane * green_plane + blue_plane * blue_plane) / scale .. [[ then
						]] .. out_palette_index .. [[ = ]] .. out_palette_index .. [[ + 8
					end
				]])

				if out_red or out_green or out_blue then
					table.insert(cache, { name = 'v3d_palette_var_colours', value = in_self .. '.colours', global = false })
					s = s .. '\nlocal colour_base_index = ' .. out_palette_index .. ' * 3'
				end

				if out_red then
					s = s .. '\n' .. out_red .. ' = v3d_palette_var_colours[colour_base_index - 2]'
				end

				if out_green then
					s = s .. '\n' .. out_green .. ' = v3d_palette_var_colours[colour_base_index - 1]'
				end

				if out_blue then
					s = s .. '\n' .. out_blue .. ' = v3d_palette_var_colours[colour_base_index]'
				end

				return s, cache
			end
		)
	end

	--- Create a palette which internally uses a k/d tree lookup to find the
	--- closest colour.
	--- @param count integer
	--- @param colours number[]
	--- @param do_fast_lookups boolean | nil
	--- @return v3d.rgb.Palette
	--- @nodiscard
	function v3d.rgb.kd_tree_palette(count, colours, do_fast_lookups)
		-- TODO: fast lookups

		local math_abs = math.abs
		local math_huge = math.huge

		local tree
		do -- build the tree
			--- is_leaf, r, g, b, index, all_colours (build), max_distance (build), field_selector (build), normal_r, normal_g, normal_b
			--- @alias KDTreeLeaf { [1]: true, [2]: number, [3]: number, [4]: number, [5]: integer, [6]: number[], [7]: number | false, [8]: 1 | 2 | 3, [9]: number, [10]: number, [11]: number }
			--- is_leaf, tree_lt, tree_gt, min_dst_lt, min_dst_gt, mid_r, mid_g, mid_b, normal_r, normal_g, normal_b
			--- @alias KDTreeBranch { [1]: false, [2]: KDTreeNode, [3]: KDTreeNode, [4]: number, [5]: number, [6]: number, [7]: number, [8]: number, [9]: number, [10]: number, [11]: number }
			--- @alias KDTreeNode KDTreeLeaf | KDTreeBranch

			tree = { true, 0, 0, 0, 0, colours, false, 0, 0, 0, 0 }
			--- @type KDTreeNode[]
			local candidates = { tree }

			-- iteratively split the largest bounded leaf
			for n_candidates = 1, count - 1 do
				local max_distance = 0
				local max_distance_candidate_index

				-- find the candidate with the largest range in any dimension
				-- note: this also calculates that range for leaves lazily
				for i = 1, n_candidates do
					local candidate = candidates[i]
					local c_max_distance = candidate[7]
					local c_colours = candidate[6]

					-- if we've not computed this candidate's maximum distance
					-- yet, do that now
					if not c_max_distance then
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
								candidate[8] = 1
								candidate[9] = 1
								candidate[10] = 0
								candidate[11] = 0

							else
								c_max_distance = dst_b
								candidate[8] = 3
								candidate[9] = 0
								candidate[10] = 0
								candidate[11] = 1
							end
						else
							if dst_g > dst_b then
								c_max_distance = dst_g
								candidate[8] = 2
								candidate[9] = 0
								candidate[10] = 1
								candidate[11] = 0
							else
								c_max_distance = dst_b
								candidate[8] = 3
								candidate[9] = 0
								candidate[10] = 0
								candidate[11] = 1
							end
						end

						candidate[7] = c_max_distance
					end

					-- if this leaf is splittable (more than 1 colour) and has a
					-- larger range than current, update to split this
					if c_max_distance > max_distance and #c_colours > 3 then
						max_distance = c_max_distance
						max_distance_candidate_index = i
					end
				end

				-- e.g. aiming for count=256 with only 10 colours - can't split
				if not max_distance_candidate_index then
					break
				end

				local candidate = candidates[max_distance_candidate_index]
				local c_colours = candidate[6]
				local c_field_selector = candidate[8]
				local c_normal_r = candidate[9]
				local c_normal_g = candidate[10]
				local c_normal_b = candidate[11]
				local num_colours = #c_colours

				-- compute the sum of the midpoint value for all the colours in
				-- this leaf
				-- note: starting j at the field selector (1|2|3) will offset
				--       the index to get the right colour component during the
				--       iteration
				local sum_midpoint = 0
				for j = c_field_selector, num_colours, 3 do
					sum_midpoint = sum_midpoint + c_colours[j]
				end

				local avg_midpoint = sum_midpoint * 3 / num_colours
				local mid_r = avg_midpoint * c_normal_r
				local mid_g = avg_midpoint * c_normal_g
				local mid_b = avg_midpoint * c_normal_b

				-- divide all the colours into two halves based on whether it
				-- lies on the "greater than" side of the plane we're splitting
				-- this leaf in
				local lt_filtered = {}
				local gt_filtered = {}
				local lt_filtered_index = 1
				local gt_filtered_index = 1
				local min_dst_lt = math_huge
				local min_dst_gt = math_huge
				local threshold = c_field_selector == 1 and mid_r or c_field_selector == 2 and mid_g or mid_b
				for j = 0, num_colours - 1, 3 do
					local r = c_colours[j + 1]
					local g = c_colours[j + 2]
					local b = c_colours[j + 3]

					-- signed distance from split plane
					local delta = c_colours[j + c_field_selector] - threshold
					local delta_abs = math_abs(delta)

					if delta > 0 then
						gt_filtered[gt_filtered_index] = r
						gt_filtered[gt_filtered_index + 1] = g
						gt_filtered[gt_filtered_index + 2] = b
						gt_filtered_index = gt_filtered_index + 3
						if delta_abs < min_dst_gt then min_dst_gt = delta_abs end
					else
						lt_filtered[lt_filtered_index] = r
						lt_filtered[lt_filtered_index + 1] = g
						lt_filtered[lt_filtered_index + 2] = b
						lt_filtered_index = lt_filtered_index + 3
						if delta_abs < min_dst_lt then min_dst_lt = delta_abs end
					end
				end

				local lt_tree = { true, 0, 0, 0, 0, lt_filtered, false, 0, 0, 0, 0 }
				local gt_tree = { true, 0, 0, 0, 0, gt_filtered, false, 0, 0, 0, 0 }

				-- update the node from a leaf to a branch:
				candidate[1] = false -- is_leaf
				candidate[2] = lt_tree -- tree_lt
				candidate[3] = gt_tree -- tree_gt
				candidate[4] = min_dst_lt
				candidate[5] = min_dst_gt
				candidate[6] = mid_r
				candidate[7] = mid_g
				candidate[8] = mid_b
				-- note: we don't need to update fields 9-11 (normal_*) since
				--       these fields already line up with the leaf node

				candidates[max_distance_candidate_index] = lt_tree
				candidates[n_candidates + 1] = gt_tree
			end

			-- here, candidates contains all the leaf nodes we have but they've
			-- not been set up fully with the r, g, b, index components, so we
			-- need to calculate that by calculating the average colour
			for i = 1, #candidates do
				local candidate = candidates[i]
				local c_colours = candidate[6]
				local num_colours = #c_colours
				local sum_r = 0
				local sum_g = 0
				local sum_b = 0

				for j = 1, num_colours, 3 do
					sum_r = sum_r + c_colours[j]
					sum_g = sum_g + c_colours[j + 1]
					sum_b = sum_b + c_colours[j + 2]
				end

				local sum_to_avg = num_colours == 0 and 0 or 3 / num_colours

				candidate[2] = sum_r * sum_to_avg
				candidate[3] = sum_g * sum_to_avg
				candidate[4] = sum_b * sum_to_avg
				candidate[5] = i
			end
		end

		local used_colours
		-- in this case, we know every leaf in the tree corresponds exactly to a
		-- colour so we use the existing colours and find derive the indices in
		-- reverse
		if count * 3 >= #colours then
			used_colours = colours

			local function update_tree(tree, r, g, b, index)
				if tree[1] then
					if tree[2] == r and tree[3] == g and tree[4] == b then
						tree[5] = index
						return true
					else
						return false
					end
				else
					if update_tree(tree[2], r, g, b, index) then
						return true
					else
						return update_tree(tree[3], r, g, b, index)
					end
				end
			end

			for i = 1, #colours / 3 do
				local index = (i - 1) * 3
				update_tree(tree, colours[index + 1], colours[index + 2], colours[index + 3], i)
			end
		else
			used_colours = {}

			local fringe = { tree }
			local fringe_n = 1

			while fringe_n > 0 do
				local f = fringe[fringe_n]
				fringe_n = fringe_n - 1
				if f[1] then
					local base_index = (f[5] - 1) * 3
					used_colours[base_index + 1] = f[2]
					used_colours[base_index + 2] = f[3]
					used_colours[base_index + 3] = f[4]
				else
					fringe[fringe_n + 1] = f[2]
					fringe[fringe_n + 2] = f[3]
					fringe_n = fringe_n + 2
				end
			end
		end

		return create_palette(
			tree,
			used_colours,
			function(_, in_self, in_red, in_green, in_blue, out_palette_index, out_red, out_green, out_blue)
				local cache = {
					{ name = 'v3d_palette_var_fringe_trees', value = '{}', global = true },
					{ name = 'v3d_palette_var_fringe_min_distance_squared', value = '{}', global = true },
					{ name = 'v3d_palette_var_math_huge', value = 'math.huge', global = true },
				}

				local prefix = ''

				if in_red:find '[^%w_]' then
					prefix = prefix .. 'local red = ' .. in_red .. '\n'
					in_red = 'red'
				end

				if in_green:find '[^%w_]' then
					prefix = prefix .. 'local green = ' .. in_green .. '\n'
					in_green = 'green'
				end

				if in_green:find '[^%w_]' then
					prefix = prefix .. 'local green = ' .. in_green .. '\n'
					in_green = 'green'
				end

				local content = prefix .. v3d.text.unindent([[
					local best_distance_squared = v3d_palette_var_math_huge
					local best_tree = nil

					local fringe_n = 1
					v3d_palette_var_fringe_trees[fringe_n] = ]] .. in_self .. [[ 
					v3d_palette_var_fringe_min_distance_squared[fringe_n] = 0

					while fringe_n > 0 do
						local tree = v3d_palette_var_fringe_trees[fringe_n]
						local min_distance_squared = v3d_palette_var_fringe_min_distance_squared[fringe_n]

						fringe_n = fringe_n - 1

						if min_distance_squared < best_distance_squared then
							if tree[1] then
								local delta_r = tree[2] - ]] .. in_red .. [[
								local delta_g = tree[3] - ]] .. in_green .. [[
								local delta_b = tree[4] - ]] .. in_blue .. [[
								local distance_squared = delta_r * delta_r + delta_g * delta_g + delta_b * delta_b

								if distance_squared < best_distance_squared then
									best_distance_squared = distance_squared
									best_tree = tree
								end
							else
								local dst = (]] .. in_red .. [[ - tree[6]) * tree[9] + (]] .. in_green .. [[ - tree[7]) * tree[10] + (]] .. in_blue .. [[ - tree[8]) * tree[11]
								local next_idx = fringe_n + 2
								local after_idx = fringe_n + 1
								local pos_delta = tree[5] - dst
								local neg_delta = tree[4] + dst

								if dst > 0 then
									v3d_palette_var_fringe_trees[next_idx] = tree[3]
									v3d_palette_var_fringe_min_distance_squared[next_idx] = pos_delta * pos_delta

									v3d_palette_var_fringe_trees[after_idx] = tree[2]
									v3d_palette_var_fringe_min_distance_squared[after_idx] = neg_delta * neg_delta
								else
									v3d_palette_var_fringe_trees[next_idx] = tree[2]
									v3d_palette_var_fringe_min_distance_squared[next_idx] = neg_delta * neg_delta

									v3d_palette_var_fringe_trees[after_idx] = tree[3]
									v3d_palette_var_fringe_min_distance_squared[after_idx] = pos_delta * pos_delta
								end

								fringe_n = next_idx
							end
						end
					end
				]])

				if out_palette_index then
					content = content .. '\n' .. out_palette_index .. ' = best_tree[5]'
				end

				if out_red then
					content = content .. '\n' .. out_red .. ' = best_tree[2]'
				end

				if out_green then
					content = content .. '\n' .. out_green .. ' = best_tree[3]'
				end

				if out_blue then
					content = content .. '\n' .. out_blue .. ' = best_tree[4]'
				end

				return content, cache
			end
		)
	end
end

--------------------------------------------------------------------------------
--[[ RGB to palette index effect ]]---------------------------------------------
--------------------------------------------------------------------------------

do
	local default_ordered_dithering_kernel = {
		{  0,  8,  2, 10 },
		{ 12,  4, 14,  6 },
		{  3, 11,  1,  9 },
		{ 15,  7, 13,  5 },
	}

	--- TODO
	--- @class v3d.rgb.PalettizeOptions
	--- TODO
	--- @field layout v3d.Layout
	--- TODO
	--- @field rgb_layer v3d.LayerName
	--- TODO
	--- @field index_layer v3d.LayerName
	--- TODO
	--- @field exponential_indices boolean
	--- TODO
	--- @field palette v3d.rgb.Palette
	--- TODO
	--- @field dynamic_palette boolean | nil
	--- TODO
	--- @field ordered_dithering_r number | nil
	--- TODO
	--- @field ordered_dithering_amount number | nil
	--- TODO
	--- @field ordered_dithering_dynamic_amount boolean | nil
	--- TODO
	--- @field ordered_dithering_kernel number[][] | nil
	--- TODO
	--- @field normalise_ordered_dithering_kernel boolean | nil
	-- TODO: error diffusion

	--- @param options v3d.rgb.PalettizeOptions
	--- @param label string | nil
	--- @return v3d.Effect
	function v3d.rgb.palettize_effect(options, label)
		local any_ordered_dithering = options.ordered_dithering_amount
		                           or options.ordered_dithering_r
		                           or options.normalise_ordered_dithering_kernel
		local opt_ordered_dithering_amount = options.ordered_dithering_amount
		                                  or (any_ordered_dithering and 1 or 0)
		local opt_ordered_dithering_r = options.ordered_dithering_r or 0.15
		local opt_ordered_dithering_kernel = options.ordered_dithering_kernel
		                                  or default_ordered_dithering_kernel
		local opt_normalise_ordered_dithering_kernel = options.normalise_ordered_dithering_kernel ~= false

		local lookup_code, cache

		if options.dynamic_palette then
			lookup_code = 'out_idx = lookup_closest(v3d_read_uniform(\'palette\'), px_red, px_green, px_blue)'
			cache = { { name = 'lookup_closest', value = 'v3d_read_uniform(\'palette\').lookup_closest' } }
		else
			lookup_code, cache = options.palette:embed_lookup_algorithm(
				'v3d_read_uniform(\'palette\')',
				'px_red', 'px_green', 'px_blue',
				'out_idx'
			)
		end

		local cache_lines = {}
		for i = 1, #cache do
			table.insert(cache_lines, 'local ' .. cache[i].name .. ' = ' .. cache[i].value)
		end

		if opt_ordered_dithering_amount > 0.001 or options.ordered_dithering_dynamic_amount then
			table.insert(cache_lines, 'local math_min = math.min')
			table.insert(cache_lines, 'local math_max = math.max')
		end

		local ordered_dithering_kernel = {}
		local ordered_dithering_kernel_width = #opt_ordered_dithering_kernel[1]
		local ordered_dithering_kernel_height = #opt_ordered_dithering_kernel
		local ordered_dithering_kernel_divisor = 1 / ordered_dithering_kernel_width / ordered_dithering_kernel_width
		local i = 1
		for y = 1, ordered_dithering_kernel_height do
			for x = 1, ordered_dithering_kernel_width do
				local value = not opt_normalise_ordered_dithering_kernel and opt_ordered_dithering_kernel[y][x]
				           or (opt_ordered_dithering_kernel[y][x] + 1)
				            * ordered_dithering_kernel_divisor - 1/2
				ordered_dithering_kernel[i] = value
				i = i + 1
			end
		end

		local effect = v3d.create_effect({
			layout = options.layout,
			pixel_shader = [[
				local px_red = v3d_read_layer(']] .. options.rgb_layer .. [[', 1)
				local px_green = v3d_read_layer(']] .. options.rgb_layer .. [[', 2)
				local px_blue = v3d_read_layer(']] .. options.rgb_layer .. [[', 3)
				local out_idx

				{% if ordered_dithering_amount > 0.001 or ordered_dithering_dynamic_amount then %}
				local od_index = v3d_framebuffer_position('y')
				               % ${ordered_dithering_kernel_height}
				               * ${ordered_dithering_kernel_width}
				               + v3d_framebuffer_position('x')
				               % ${ordered_dithering_kernel_width}
				               + 1
				local od_scalar = v3d_read_uniform('ordered_dithering_kernel')[od_index]
				{% if ordered_dithering_dynamic_amount then %}
				                * ${ordered_dithering_r} * v3d_read_uniform('ordered_dithering_amount')
				{% else %}
				                * ${ordered_dithering_amount * ordered_dithering_r}
				{% end %}

				-- TODO: maybe make this switchable: might see better performance on some platforms
				-- px_red = px_red + od_scalar
				-- px_green = px_green + od_scalar
				-- px_blue = px_blue + od_scalar
				--
				-- if px_red > 1 then px_red = 1
				-- elseif px_red < 0 then px_red = 0
				-- end
				-- if px_green > 1 then px_green = 1
				-- elseif px_green < 0 then px_green = 0
				-- end
				-- if px_blue > 1 then px_blue = 1
				-- elseif px_blue < 0 then px_blue = 0
				-- end

				px_red = math_max(0, math_min(1, px_red + od_scalar))
				px_green = math_max(0, math_min(1, px_green + od_scalar))
				px_blue = math_max(0, math_min(1, px_blue + od_scalar))
				{% end %}

				{! lookup_code !}

				{% if exponential_indices then %}
				v3d_write_layer(']] .. options.index_layer .. [[', 2 ^ (out_idx - 1))
				{% else %}
				v3d_write_layer(']] .. options.index_layer .. [[', out_idx - 1)
				{% end %}
			]],
			pixel_shader_init = table.concat(cache_lines, '\n'),
			template_context = {
				ordered_dithering_amount = opt_ordered_dithering_amount,
				ordered_dithering_dynamic_amount = options.ordered_dithering_dynamic_amount,
				ordered_dithering_r = opt_ordered_dithering_r,
				ordered_dithering_kernel = opt_ordered_dithering_kernel,
				ordered_dithering_kernel_width = ordered_dithering_kernel_width,
				ordered_dithering_kernel_height = ordered_dithering_kernel_height,
				lookup_code = lookup_code,
				exponential_indices = options.exponential_indices,
			}
		}, label)

		effect:set_uniform('palette', options.palette)
		effect:set_uniform('ordered_dithering_kernel', ordered_dithering_kernel)

		if options.ordered_dithering_dynamic_amount then
			effect:set_uniform('ordered_dithering_amount', opt_ordered_dithering_amount)
		end

		return effect
	end
end
