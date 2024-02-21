
--- @type V3D
local v3d = require 'v3d'

local model_transforms = {}

--- @param mode 'rgb' | 'rgb_exp' | 'hsl' | 'hsl_exp'
local function rgb_to_xyz(r, g, b, mode)
	local x, y, z = r, g, b
	if mode == 'rgb_exp' then
		x = math.sqrt(r)
		y = math.sqrt(g)
		z = math.sqrt(b)
	elseif mode == 'hsl' then
		x, y, z = v3d.rgb_to_hsl(r, g, b)
	elseif mode == 'hsl_exp' then
		x, y, z = v3d.rgb_to_hsl(r, g, b)
		z = math.sqrt(z)
	end
	return x - 0.5, y - 0.5, z - 0.5
end

--- @param p V3DPalette
--- @param mode 'rgb' | 'rgb_exp' | 'hsl' | 'hsl_exp'
local function set_palette(p, mode)
	model_transforms = {}

	for i = 1, p.n_colours do
		local r, g, b = table.unpack(v3d.palette_get_colour_rgb(p, i - 1, false))
		r = math.max(0, math.min(1, r))
		g = math.max(0, math.min(1, g))
		b = math.max(0, math.min(1, b))

		local x, y, z = rgb_to_xyz(r, g, b, mode)

		model_transforms[i] = v3d.translate(x, y, z) * v3d.scale_all(0.03)
		term.setPaletteColour(i - 1, r, g, b)
	end
end

local palettes = {
	v3d.create_rgb_grid_palette {
		red_divisions = 6,
		green_divisions = 6,
		blue_divisions = 6,
		red_exp = 2.2,
		green_exp = 2.2,
		blue_exp = 2,
	},
	v3d.create_rgb_grid_palette {
		red_divisions = 6,
		green_divisions = 6,
		blue_divisions = 6,
		red_exp = 1,
		green_exp = 1,
		blue_exp = 1,
	},
	v3d.create_hsl_grid_palette {
		hue_divisions = 12,
		saturation_divisions = 3,
		lightness_divisions = 7,
		hue_exp = 1,
		saturation_exp = 1,
		lightness_exp = 1.5,
		lightness_range = 0.8,
		hue_bias = 0,
		lightness_bias = 0.2,
	},
	v3d.create_hsl_grid_palette {
		hue_divisions = 12,
		saturation_divisions = 3,
		lightness_divisions = 7,
		hue_exp = 1,
		saturation_exp = 1,
		lightness_exp = 1,
	},
}

do
	-- local diamond_palette_colours = {}

	-- local k1 = 0.1
	-- local k2 = 0.3

	-- diamond_palette_colours[1] = { 0, 0, 0 }
	-- diamond_palette_colours[2] = { 0 + k1, 0 + k1, 0 + k1 }
	-- diamond_palette_colours[3] = { 0 + k1, 0 + k1, 1 - k1 }
	-- diamond_palette_colours[4] = { 0 + k1, 1 - k1, 0 + k1 }
	-- diamond_palette_colours[5] = { 0 + k1, 1 - k1, 1 - k1 }
	-- diamond_palette_colours[6] = { 1 - k1, 0 + k1, 0 + k1 }
	-- diamond_palette_colours[7] = { 1 - k1, 0 + k1, 1 - k1 }
	-- diamond_palette_colours[8] = { 1 - k1, 1 - k1, 0 + k1 }
	-- diamond_palette_colours[9] = { 1 - k1, 1 - k1, 1 - k1 }

	-- diamond_palette_colours[10] = { 0.5 - k2, 0.5, 0.5 }
	-- diamond_palette_colours[11] = { 0.5 + k2, 0.5, 0.5 }
	-- diamond_palette_colours[12] = { 0.5, 0.5 - k2, 0.5 }
	-- diamond_palette_colours[13] = { 0.5, 0.5 + k2, 0.5 }
	-- diamond_palette_colours[14] = { 0.5, 0.5, 0.5 - k2 }
	-- diamond_palette_colours[15] = { 0.5, 0.5, 0.5 + k2 }

	-- diamond_palette_colours[16] = { 0.5, 0.5, 0.5 }

	-- table.insert(palette_colours, diamond_palette_colours)
end

term.setGraphicsMode(2)
set_palette(palettes[1], 'rgb')

local geometry = v3d.debug_cuboid():build()
local image_views = v3d.create_fullscreen_image_views { colour_mode = 'palette', size_mode = 'graphics' }

local pixel_shader = v3d.shader {
	source_format = geometry.vertex_format,
	image_formats = v3d.image_formats_of(image_views),
	code = [[
		if v3d_src_depth > v3d_dst.depth then
			v3d_dst.colour = v3d_external.colour
			v3d_dst.depth = v3d_src_depth
		end
	]],
}
local renderer = v3d.compile_renderer { pixel_shader = pixel_shader }

local background_model = v3d.debug_cuboid {
	include_indices = 'face',
}:build()
local background_renderer = v3d.compile_renderer {
	pixel_shader = v3d.shader {
		source_format = geometry.vertex_format,
		face_format = background_model.face_format,
		image_formats = v3d.image_formats_of(image_views),
		code = [[
			-- TODO: implement and use v3d _dst_pos here instead
			-- if v3d _dst_pos.x % 2 == v3d _dst_pos.y % 2 then
			if _v3d_shader_dst_base_offset_colour % 2 == math.floor(_v3d_shader_dst_base_offset_colour / (v3d_image.colour).width) % 2 then
				if v3d_face.index < 2 then
					v3d_dst.colour = v3d_external.blue_colour
				elseif v3d_face.index < 4 then
					v3d_dst.colour = v3d_external.red_colour
				else
					v3d_dst.colour = v3d_external.green_colour
				end
			end
		]],
	},
	cull_faces = 'front',
}

local camera_rx, camera_ry = 0, 0
local modes = { 'rgb', 'rgb_exp', 'hsl', 'hsl_exp' }
local mouse_x, mouse_y = 0, 0
local timer = os.startTimer(0)
local sample_rgb = { 0, 0, 0 }
local sample_rgb_model = v3d.debug_cuboid {
	width = 0.05,
	height = 0.05,
	depth = 0.05,
}:build()
while true do
	local ev = { os.pullEvent() }

	if ev[1] == 'mouse_click' then
		mouse_x, mouse_y = ev[3], ev[4]
	elseif ev[1] == 'mouse_drag' then
		camera_ry = camera_ry - (ev[3] - mouse_x) * 0.005
		camera_rx = math.max(-math.pi / 2, math.min(math.pi / 2, camera_rx - (ev[4] - mouse_y) * 0.005))
		mouse_x, mouse_y = ev[3], ev[4]
	elseif ev[1] == 'key' and ev[2] == keys.tab then
		table.insert(modes, table.remove(modes, 1))
		set_palette(palettes[1], modes[1])
	elseif ev[1] == 'key' and ev[2] == keys.right then
		table.insert(palettes, table.remove(palettes, 1))
		set_palette(palettes[1], modes[1])
	elseif ev[1] == 'key' and ev[2] == keys.left then
		table.insert(palettes, 1, table.remove(palettes))
		set_palette(palettes[1], modes[1])
	elseif ev[1] == 'key' and ev[2] == keys.space then
		sample_rgb = { math.random(), math.random(), math.random() }
	elseif ev[1] == 'timer' and ev[2] == timer then
		local camera = v3d.camera {
			x = 2 * math.sin(camera_ry) * math.cos(camera_rx),
			y = 2 * -math.sin(camera_rx),
			z = 2 * math.cos(camera_ry) * math.cos(camera_rx),
			pitch = camera_rx,
			yaw = camera_ry,
		}

		v3d.enter_debug_region('clear')
		image_views.colour:fill(0)
		image_views.depth:fill(0)
		v3d.exit_debug_region('clear')

		v3d.enter_debug_region('render')
		background_renderer.pixel_shader:set_variable('red_colour', v3d.palette_lookup(palettes[1], 0.7, 0, 0))
		background_renderer.pixel_shader:set_variable('green_colour', v3d.palette_lookup(palettes[1], 0, 0.7, 0))
		background_renderer.pixel_shader:set_variable('blue_colour', v3d.palette_lookup(palettes[1], 0, 0, 0.7))
		-- background_renderer:render(background_model, image_views, camera)

		for i = 1, #model_transforms do
			local model_transform = model_transforms[i]

			v3d.enter_debug_region('render ' .. i)
			renderer.pixel_shader:set_variable('colour', i - 1)
			renderer:render(geometry, image_views, camera, model_transform)
			v3d.exit_debug_region('render ' .. i)
		end

		local sample_transform = v3d.translate(rgb_to_xyz(sample_rgb[1], sample_rgb[2], sample_rgb[3], modes[1]))
		local sample_index = v3d.palette_lookup(palettes[1], sample_rgb[1], sample_rgb[2], sample_rgb[3])
		renderer.pixel_shader:set_variable('colour', sample_index)
		renderer:render(sample_rgb_model, image_views, camera, sample_transform)
		v3d.exit_debug_region('render')

		v3d.enter_debug_region('present')
		image_views.colour:present_graphics(term, false)
		v3d.exit_debug_region('present')

		timer = os.startTimer(0.01)
	end
end
