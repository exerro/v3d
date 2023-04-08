
if not shell.execute '/v3d/tools/build' then return end

local DITHERING_HATCHING = 0.15
local PALETTE_TYPES = { 'hypercube', 'grid', 'kd-hues' }

local images = {}
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

local hue_colours_lookup = {}
do
	local index = 1

	local hue_counts = {
		{  1 },
		{  1,  4 },
		{  1,  4,  8 },
		{  1,  4,  8, 12 },
		{  1,  4,  8, 12, 18 },
		{  1,  4,  8, 12, 18, 24 },
		{  1,  4,  8, 12, 18, 24, 32 },
	}

	local function hsv_to_rgb(h, s, v)
		local k1 = v*(1-s)
		local k2 = v - k1
		local r = math.min (math.max (3*math.abs ((h*2)%2-1)-1, 0), 1)
		local g = math.min (math.max (3*math.abs ((h*2-120/180)%2-1)-1, 0), 1)
		local b = math.min (math.max (3*math.abs ((h*2+120/180)%2-1)-1, 0), 1)
		return k1 + k2 * r, k1 + k2 * g, k1 + k2 * b
	end

	local MAX_VALUE = #hue_counts - 1

	for value = 0, MAX_VALUE do
		local v = (value / MAX_VALUE) ^ 2

		for chroma = 0, value do
			local s = value == 0 and 0 or chroma / value
			local hue_count = hue_counts[value + 1][chroma + 1]

			for hue = 0, hue_count - 1 do
				local h = hue / hue_count
				local r, g, b = hsv_to_rgb(h, s, v)

				hue_colours_lookup[index] = r
				hue_colours_lookup[index + 1] = g
				hue_colours_lookup[index + 2] = b
				index = index + 3
			end
		end
	end
end

local graphics_mode_supported = false
local default_width, default_height = term.getSize()
local max_width, max_height = term.getSize()
if term.setGraphicsMode then
	term.setGraphicsMode(2)
	graphics_mode_supported = true
	max_width, max_height = term.getSize(2)
end

local app_state = {
	--- @type integer
	current_image = 1,
	--- @type 1 | 2 | 3
	palette_type = 1,
	--- @type 16 | 256
	palette_size = graphics_mode_supported and 256 or 16,
	--- @type number
	palette_saturation = 0.5,
	--- @type number
	current_dithering_amount = 0,
}

local v3d = require '/v3d/gen/v3dtest'
local layout = v3d.create_layout()
	:add_layer('pal', 'any-numeric', 1)
	:add_layer('rgb', 'any-numeric', 3)
local format = v3d.create_format()
	:add_vertex_attribute('position', 3, true)
	:add_vertex_attribute('uv', 2, true)
local graphics_framebuffer = v3d.create_framebuffer(layout, max_width, max_height)
local default_framebuffer = v3d.create_framebuffer(layout, 2, 3, default_width, default_height)
local plane = v3d.create_geometry_builder(format)
	:set_data('position', { -1, -1, 0, 1, -1, 0, 1, 1, 0, -1, -1, 0, 1, 1, 0, -1, 1, 0 })
	:set_data('uv', { 0, 1, 1, 1, 1, 0, 0, 1, 1, 0, 0, 0, })
	:build()
local transform = v3d.translate(0, 0, -1)
local pipeline = v3d.create_pipeline {
	layout = layout,
	format = format,
	position_attribute = 'position',
	cull_face = false,
	fragment_shader = [[
		local texture = v3d_read_uniform('texture')
		local u = v3d_read_attribute('uv', 1)
		local v = v3d_read_attribute('uv', 2)
		local ix = _v3d_math_floor(u * texture.width)
		local iy = _v3d_math_floor(v * texture.height)
		local idx = (iy * texture.width + ix) * 3
		local r = (texture[idx + 1] or 1)
		local g = (texture[idx + 2] or 1)
		local b = (texture[idx + 3] or 1)

		v3d_write_layer_values('rgb', r, g, b)
	]],
}
local palette
local default_palettize_effect, graphics_palettize_effect

local function redraw_texture()
	pipeline:set_uniform('texture', images[app_state.current_image])
	pipeline:render_geometry(graphics_framebuffer, plane, transform)
	pipeline:render_geometry(default_framebuffer, plane, transform)
end

local function recreate_palettization()
	local palette_type = PALETTE_TYPES[app_state.palette_type]
	local palette_size = graphics_mode_supported and app_state.palette_size or 16

	if palette_type == 'hypercube' then
		palette = v3d.rgb.hypercube_palette(app_state.palette_saturation)
	elseif palette_type == 'grid' then
		palette = v3d.rgb.grid_palette({
			red = palette_size == 16 and 2 or 6,
			green = palette_size == 16 and 3 or 6,
			blue = palette_size == 16 and 2 or 6,
		}, app_state.palette_saturation)
	else
		palette = v3d.rgb.kd_tree_palette(palette_size, hue_colours_lookup)
	end

	default_palettize_effect = v3d.rgb.palettize_effect {
		layout = layout,
		rgb_layer = 'rgb',
		index_layer = 'pal',
		palette = palette,
		ordered_dithering_amount = app_state.current_dithering_amount,
		ordered_dithering_r = DITHERING_HATCHING,
		exponential_indices = not graphics_mode_supported,
		dynamic_palette = false,
		ordered_dithering_dynamic_amount = true,
	}

	graphics_palettize_effect = v3d.rgb.palettize_effect {
		layout = layout,
		rgb_layer = 'rgb',
		index_layer = 'pal',
		palette = palette,
		ordered_dithering_amount = app_state.current_dithering_amount,
		ordered_dithering_r = DITHERING_HATCHING,
		exponential_indices = not graphics_mode_supported,
		dynamic_palette = false,
		ordered_dithering_dynamic_amount = true,
	}

	for i = 1, palette:count() do
		term.native().setPaletteColour(graphics_mode_supported and i - 1 or 2^(i-1), palette:get_colour(i))
	end
end

local function update_dithering()
	default_palettize_effect:set_uniform('ordered_dithering_amount', app_state.current_dithering_amount)
	graphics_palettize_effect:set_uniform('ordered_dithering_amount', app_state.current_dithering_amount)
end

redraw_texture()
recreate_palettization()

while true do
	local graphics_width = math.floor(graphics_framebuffer.width / 2)
	local default_width = math.floor(default_framebuffer.width / 2)

	graphics_palettize_effect:apply(graphics_framebuffer, graphics_width)
	default_palettize_effect:apply(default_framebuffer, default_framebuffer.width - default_width, nil, default_width)
	graphics_framebuffer:blit_graphics(term.native(), 'pal', 0, 0, graphics_width)
	default_framebuffer:blit_graphics(term.native(), 'pal', graphics_width, 0, default_width, nil, default_framebuffer.width - default_width, nil, 3, 3)

	local event = { os.pullEvent() }

	if event[1] == 'key' then
		if event[2] == keys.left then
			app_state.current_image = app_state.current_image - 1
			if app_state.current_image < 1 then
				app_state.current_image = #images
			end
			redraw_texture()
		elseif event[2] == keys.right then
			app_state.current_image = app_state.current_image + 1
			if app_state.current_image > #images then
				app_state.current_image = 1
			end
			redraw_texture()
		elseif event[2] == keys.p then
			app_state.palette_size = app_state.palette_size == 16 and 256 or 16
			recreate_palettization()
		elseif event[2] == keys.space then
			app_state.palette_type = app_state.palette_type + 1
			if app_state.palette_type > #PALETTE_TYPES then
				app_state.palette_type = 1
			end
			recreate_palettization()
		elseif event[2] == keys.up then
			app_state.current_dithering_amount = app_state.current_dithering_amount + 0.1
			update_dithering()
		elseif event[2] == keys.down then
			app_state.current_dithering_amount = math.max(0, app_state.current_dithering_amount - 0.1)
			update_dithering()
		end
	end
end
