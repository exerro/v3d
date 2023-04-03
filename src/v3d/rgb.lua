
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

	--- Create a palette which internally uses a k/d tree lookup to find the
	--- closest colour.
	--- @param count integer
	--- @param colours number[]
	--- @return v3d.rgb.Palette
	--- @nodiscard
	function v3d.rgb.colours_to_palette(count, colours)
		-- TODO
		error('dhajk')
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
