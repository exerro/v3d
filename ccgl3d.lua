
--- @class cc_term_lib
--- @field blit function
--- @field setCursorPos function

--------------------------------------------------------------------------------

local CH_SPACE = string.byte ' '
local CH_0 = string.byte '0'
local CH_A = string.byte 'a'
local CH_SUBPIXEL_NOISEY = 149
local colour_lookup_byte = {}
local subpixel_code_ch_lookup = {}
local subpixel_code_fg_lookup = {}
local subpixel_code_bg_lookup = {}

for i = 0, 15 do
	colour_lookup_byte[2 ^ i] = i < 10 and CH_0 + i or CH_A + (i - 10)
end

local function subpixel_byte_value(v0, v1, v2, v3, v4, v5)
	local b0 = v0 == v5 and 0 or 1
	local b1 = v1 == v5 and 0 or 1
	local b2 = v2 == v5 and 0 or 1
	local b3 = v3 == v5 and 0 or 1
	local b4 = v4 == v5 and 0 or 1

	return 128 + b0 + b1 * 2 + b2 * 4 + b3 * 8 + b4 * 16
end

local function eval_subpixel_lookups(ci0, ci1, ci2, ci3, ci4, ci5, subpixel_code)
	local colour_count = { [ci0] = 1 }
	local unique_colour_values = { ci0 }
	local unique_colours = 1

	for _, c in ipairs { ci1, ci2, ci3, ci4, ci5 } do
		if colour_count[c] then
			colour_count[c] = colour_count[c] + 1
		else
			colour_count[c] = 1
			unique_colours = unique_colours + 1
			unique_colour_values[unique_colours] = c
		end
	end

	table.sort(unique_colour_values, function(a, b)
		return colour_count[a] > colour_count[b]
	end)

	if unique_colours == 1 then -- these should never be used!
		subpixel_code_ch_lookup[subpixel_code] = false
		subpixel_code_fg_lookup[subpixel_code] = false
		subpixel_code_bg_lookup[subpixel_code] = false
		return
	end

	local colour_indices = { ci0, ci1, ci2, ci3, ci4, ci5 }
	local modal1_colour_index = unique_colour_values[1]
	local modal2_colour_index = unique_colour_values[2]
	local modal1_index = 0
	local modal2_index = 0

	for i = 1, 6 do
		if colour_indices[i] == modal1_colour_index then
			modal1_index = i
		end
		if colour_indices[i] == modal2_colour_index then
			modal2_index = i
		end
	end

	-- spatially map pixels!
	ci0 = (ci0 == modal1_colour_index or ci0 == modal2_colour_index) and ci0 or (ci1 == modal1_colour_index or ci1 == modal2_colour_index) and ci1 or ci2
	ci1 = (ci1 == modal1_colour_index or ci1 == modal2_colour_index) and ci1 or (ci0 == modal1_colour_index or ci0 == modal2_colour_index) and ci0 or ci3
	ci2 = (ci2 == modal1_colour_index or ci2 == modal2_colour_index) and ci2 or (ci3 == modal1_colour_index or ci3 == modal2_colour_index) and ci3 or ci4
	ci3 = (ci3 == modal1_colour_index or ci3 == modal2_colour_index) and ci3 or (ci2 == modal1_colour_index or ci2 == modal2_colour_index) and ci2 or ci5
	ci4 = (ci4 == modal1_colour_index or ci4 == modal2_colour_index) and ci4 or (ci5 == modal1_colour_index or ci5 == modal2_colour_index) and ci5 or ci2
	ci5 = (ci5 == modal1_colour_index or ci5 == modal2_colour_index) and ci5 or (ci4 == modal1_colour_index or ci4 == modal2_colour_index) and ci4 or ci3
	subpixel_code_ch_lookup[subpixel_code] = subpixel_byte_value(ci0, ci1, ci2, ci3, ci4, ci5)
	subpixel_code_fg_lookup[subpixel_code] = ci5 == modal1_colour_index and modal2_index or modal1_index
	subpixel_code_bg_lookup[subpixel_code] = ci5 == modal1_colour_index and modal1_index or modal2_index
end

local subpixel_code = 0
for c5 = 0, 3 do
	for c4 = 0, 3 do
		for c3 = 0, 3 do
			for c2 = 0, 3 do
				for c1 = 0, 3 do
					for c0 = 0, 3 do
						eval_subpixel_lookups(c0, c1, c2, c3, c4, c5, subpixel_code)
						subpixel_code = subpixel_code + 1
					end
				end
			end
		end
	end
end

--- @class ccFramebuffer
--- @field width integer
--- @field height integer
--- @field front table
--- @field depth { [integer]: number } Stores 1/Z for every pixel drawn (if enabled)

--- @param fb ccFramebuffer
--- @param colour integer
local function clear_framebuffer(fb, colour)
	local fb_front = fb.front
	local fb_depth = fb.depth
	for i = 1, fb.width * fb.height do
		fb_front[i] = colour
		fb_depth[i] = 0
	end
end

--- @param width integer
--- @param height integer
--- @return ccFramebuffer
local function create_framebuffer(width, height)
	local fb = {}

	fb.width = width
	fb.height = height
	fb.front = {}
	fb.depth = {}

	clear_framebuffer(fb, 0)

	return fb
end

--- @param width integer
--- @param height integer
--- @return ccFramebuffer
local function create_framebuffer_subpixel(width, height)
	return create_framebuffer(width * 2, height * 3) -- multiply by subpixel dimensions
end

--- Render a framebuffer to the screen, swapping its buffers, and handling
--- subpixel conversion
--- @param fb ccFramebuffer
--- @param term cc_term_lib
--- @param dx integer | nil
--- @param dy integer | nil
local function present_framebuffer(fb, term, dx, dy)
	dx = dx or 0
	dy = dy or 0

	local SUBPIXEL_WIDTH = 2
	local SUBPIXEL_HEIGHT = 3

	local fb_front, fb_width = fb.front, fb.width

	local xBlit = 1 + dx

	local string_char = string.char
	local table_unpack = table.unpack
	local term_blit = term.blit
	local term_setCursorPos = term.setCursorPos

	local i0 = 1
	local ch_t = {}
	local fg_t = {}
	local bg_t = {}

	local ixMax = fb_width / SUBPIXEL_WIDTH

	for yBlit = 1 + dy, fb.height / SUBPIXEL_HEIGHT + dy do
		for ix = 1, ixMax do
			local i1 = i0 + fb_width
			local i2 = i1 + fb_width
			local c00, c10 = fb_front[i0], fb_front[i0 + 1]
			local c01, c11 = fb_front[i1], fb_front[i1 + 1]
			local c02, c12 = fb_front[i2], fb_front[i2 + 1]

			-- TODO: make this a massive decision tree?
			-- if two middle pixels are equal, that's a guaranteed colour

			local unique_colour_lookup = { [c00] = 0 }
			local unique_colours = 1

			if c01 ~= c00 then
				unique_colour_lookup[c01] = unique_colours
				unique_colours = unique_colours + 1
			end
			if not unique_colour_lookup[c02] then
				unique_colour_lookup[c02] = unique_colours
				unique_colours = unique_colours + 1
			end
			if not unique_colour_lookup[c10] then
				unique_colour_lookup[c10] = unique_colours
				unique_colours = unique_colours + 1
			end
			if not unique_colour_lookup[c11] then
				unique_colour_lookup[c11] = unique_colours
				unique_colours = unique_colours + 1
			end
			if not unique_colour_lookup[c12] then
				unique_colour_lookup[c12] = unique_colours
				unique_colours = unique_colours + 1
			end

			if unique_colours == 2 then
				local other_colour = c02

				    if c00 ~= c12 then other_colour = c00
				elseif c10 ~= c12 then other_colour = c10
				elseif c01 ~= c12 then other_colour = c01
				elseif c11 ~= c12 then other_colour = c11
				end

				local subpixel_ch = 128

				if c00 ~= c12 then subpixel_ch = subpixel_ch + 1 end
				if c10 ~= c12 then subpixel_ch = subpixel_ch + 2 end
				if c01 ~= c12 then subpixel_ch = subpixel_ch + 4 end
				if c11 ~= c12 then subpixel_ch = subpixel_ch + 8 end
				if c02 ~= c12 then subpixel_ch = subpixel_ch + 16 end

				ch_t[ix] = subpixel_ch
				fg_t[ix] = colour_lookup_byte[other_colour]
				bg_t[ix] = colour_lookup_byte[c12]
			elseif unique_colours == 1 then
				ch_t[ix] = CH_SPACE
				fg_t[ix] = CH_0
				bg_t[ix] = colour_lookup_byte[c00]
			elseif unique_colours > 4 then -- so random that we're gonna just give up lol
				ch_t[ix] = CH_SUBPIXEL_NOISEY
				fg_t[ix] = colour_lookup_byte[c01]
				bg_t[ix] = colour_lookup_byte[c00]
			else
				local colours = { c00, c10, c01, c11, c02, c12 }
				local subpixel_code = unique_colour_lookup[c12] * 1024
				                    + unique_colour_lookup[c02] * 256
				                    + unique_colour_lookup[c11] * 64
				                    + unique_colour_lookup[c01] * 16
				                    + unique_colour_lookup[c10] * 4
				                    + unique_colour_lookup[c00]

				ch_t[ix] = subpixel_code_ch_lookup[subpixel_code]
				fg_t[ix] = colour_lookup_byte[colours[subpixel_code_fg_lookup[subpixel_code]]]
				bg_t[ix] = colour_lookup_byte[colours[subpixel_code_bg_lookup[subpixel_code]]]
			end

			i0 = i0 + SUBPIXEL_WIDTH
		end

		term_setCursorPos(xBlit, yBlit)
		term_blit(string_char(table_unpack(ch_t)), string_char(table_unpack(fg_t)), string_char(table_unpack(bg_t)))
		i0 = i0 + fb_width * 2
	end
end

local function present_framebuffer_depth(fb, term, dx, dy, update_palette)
	local math_floor = math.floor

	if update_palette then
		for i = 0, 15 do
			term.setPaletteColour(2 ^ i, i / 15, i / 15, i / 15)
		end
	end

	-- we're gonna do a hack to swap out the buffers and draw it like normal
	local fb_depth = fb.depth
	local old_front = fb.front
	local new_front = {}
	local min = fb_depth[1]
	local max = fb_depth[1]

	for i = 2, #fb_depth do
		local a = fb_depth[i]
		if a < min then min = a end
		if a > max then max = a end
	end

	local delta = max - min

	if min == max then
		delta = 1
	end

	for i = 1, #fb_depth do
		local a = (fb_depth[i] - min) / delta
		local b = math_floor(a * 16)
		if b == 16 then b = 15 end
		new_front[i] = 2 ^ b
	end

	fb.front = new_front
	present_framebuffer(fb, term, dx, dy)
	fb.front = old_front
end

--------------------------------------------------------------------------------

--- @class ccGeometry: table
--- @field triangles integer

--- @returns ccGeometry
local function create_geometry()
	return { triangles = 0 }
end

--- @param geometry ccGeometry
--- @param p0x number
--- @param p0y number
--- @param p0z number
--- @param p1x number
--- @param p1y number
--- @param p1z number
--- @param p2x number
--- @param p2y number
--- @param p2z number
--- @param colour integer
--- @return nil
local function add_triangle(geometry, p0x, p0y, p0z, p1x, p1y, p1z, p2x, p2y, p2z, colour)
	local DATA_PER_TRIANGLE = 10
	local idx = geometry.triangles * DATA_PER_TRIANGLE

	geometry.triangles = geometry.triangles + 1
	geometry[idx + 1] = p0x
	geometry[idx + 2] = p0y
	geometry[idx + 3] = p0z
	geometry[idx + 4] = p1x
	geometry[idx + 5] = p1y
	geometry[idx + 6] = p1z
	geometry[idx + 7] = p2x
	geometry[idx + 8] = p2y
	geometry[idx + 9] = p2z
	geometry[idx + 10] = colour
end

----------------------------------------------------------------

local function rotate_geometry_z(geometry, theta, cx, cy)
	local DATA_PER_TRIANGLE = 10

	cx = cx or 0
	cy = cy or 0

	local sT = math.sin(theta)
	local cT = math.cos(theta)

	for i = 1, geometry.triangles * DATA_PER_TRIANGLE, DATA_PER_TRIANGLE do
		local x0, y0 = geometry[i], geometry[i + 1]
		local x1, y1 = geometry[i + 3], geometry[i + 4]
		local x2, y2 = geometry[i + 6], geometry[i + 7]
		geometry[i], geometry[i + 1] = x0 * cT - y0 * sT, x0 * sT + y0 * cT
		geometry[i + 3], geometry[i + 4] = x1 * cT - y1 * sT, x1 * sT + y1 * cT
		geometry[i + 6], geometry[i + 7] = x2 * cT - y2 * sT, x2 * sT + y2 * cT
	end
end

--------------------------------------------------------------------------------

--- @class ccCamera
--- @field fov number
--- @field x number
--- @field y number
--- @field z number
--- @field yRotation number
--- @field xRotation number
--- @field zRotation number

--- @param fov number | nil
--- @return ccCamera
local function create_perspective_camera(fov)
	local camera = {}

	camera.fov = fov or math.pi / 3
	camera.x = 0
	camera.y = 0
	camera.z = 0
	camera.yRotation = 0
	camera.xRotation = 0
	camera.zRotation = 0

	return camera
end

--------------------------------------------------------------------------------

--- @private
local function rasterize_triangle_nodepth(
	fb_front,
	_,
	fb_width, fb_height_m1,
	p0x, p0y, _,
	p1x, p1y, _,
	p2x, p2y, _,
	colour)
	local math_ceil = math.ceil
	local math_floor = math.floor
	local fb_width_m1 = fb_width - 1

	-- see: https://github.com/exerro/ccgl3d/blob/main/raster_visuals/src/main/kotlin/me/exerro/raster_visuals/rasterize.kt
	-- there's an explanation of the algorithm there
	-- this code has been heavily microoptimised so won't perfectly resemble that

	if p0y > p1y then p0x, p0y, p1x, p1y = p1x, p1y, p0x, p0y end
	if p1y > p2y then p1x, p1y, p2x, p2y = p2x, p2y, p1x, p1y end
	if p0y > p1y then p0x, p0y, p1x, p1y = p1x, p1y, p0x, p0y end
	if p0y == p2y then return end -- skip early if we have a perfectly flat triangle

	local f = (p1y - p0y) / (p2y - p0y)
	local pMx = p0x * (1 - f) + p2x * f

	if pMx > p1x then
		pMx, p1x = p1x, pMx
	end

	local rowTopMin = math_floor(p0y + 0.5)
	local rowBottomMin = math_floor(p1y + 0.5)
	local rowTopMax = rowBottomMin - 1
	local rowBottomMax = math_ceil(p2y - 0.5)

	if rowTopMin < 0 then rowTopMin = 0 end
	if rowBottomMin < 0 then rowBottomMin = 0 end
	if rowTopMax > fb_height_m1 then rowTopMax = fb_height_m1 end
	if rowBottomMax > fb_height_m1 then rowBottomMax = fb_height_m1 end

	if rowTopMin <= rowTopMax then
		local topDeltaY = p1y - p0y
		local topLeftGradient = (pMx - p0x) / topDeltaY
		local topRightGradient = (p1x - p0x) / topDeltaY

		local topProjection = rowTopMin + 0.5 - p0y
		local topLeftX = p0x + topLeftGradient * topProjection - 0.5
		local topRightX = p0x + topRightGradient * topProjection - 1.5

		for baseIndex = rowTopMin * fb_width + 1, rowTopMax * fb_width + 1, fb_width do
			local columnMin = math_ceil(topLeftX)
			local columnMax = math_ceil(topRightX)

			if columnMin < 0 then columnMin = 0 end
			if columnMax > fb_width_m1 then columnMax = fb_width_m1 end

			for x = columnMin, columnMax do
				fb_front[baseIndex + x] = colour
			end

			topLeftX = topLeftX + topLeftGradient
			topRightX = topRightX + topRightGradient
		end
	end

	if rowBottomMin <= rowBottomMax then
		local bottomDeltaY = p2y - p1y
		local bottomLeftGradient = (p2x - pMx) / bottomDeltaY
		local bottomRightGradient = (p2x - p1x) / bottomDeltaY

		local bottomProjection = rowBottomMin + 0.5 - p1y
		local bottomLeftX = pMx + bottomLeftGradient * bottomProjection - 0.5
		local bottomRightX = p1x + bottomRightGradient * bottomProjection - 1.5

		for baseIndex = rowBottomMin * fb_width + 1, rowBottomMax * fb_width + 1, fb_width do
			local columnMin = math_ceil(bottomLeftX)
			local columnMax = math_ceil(bottomRightX)

			if columnMin < 0 then columnMin = 0 end
			if columnMax > fb_width_m1 then columnMax = fb_width_m1 end

			for x = columnMin, columnMax do
				fb_front[baseIndex + x] = colour
			end

			bottomLeftX = bottomLeftX + bottomLeftGradient
			bottomRightX = bottomRightX + bottomRightGradient
		end
	end
end

--- @private
local function rasterize_triangle_depth(
	fb_front, fb_depth,
	fb_width, fb_height_m1,
	p0x, p0y, p0w,
	p1x, p1y, p1w,
	p2x, p2y, p2w,
	colour)
	local math_ceil = math.ceil
	local math_floor = math.floor
	local fb_width_m1 = fb_width - 1

	-- see: https://github.com/exerro/ccgl3d/blob/main/raster_visuals/src/main/kotlin/me/exerro/raster_visuals/rasterize.kt
	-- there's an explanation of the algorithm there
	-- this code has been heavily microoptimised so won't perfectly resemble that

	if p0y > p1y then p0x, p0y, p0w, p1x, p1y, p1w = p1x, p1y, p1w, p0x, p0y, p0w end
	if p1y > p2y then p1x, p1y, p1w, p2x, p2y, p2w = p2x, p2y, p2w, p1x, p1y, p1w end
	if p0y > p1y then p0x, p0y, p0w, p1x, p1y, p1w = p1x, p1y, p1w, p0x, p0y, p0w end
	if p0y == p2y then return end -- skip early if we have a perfectly flat triangle

	local f = (p1y - p0y) / (p2y - p0y)
	local pMx = p0x * (1 - f) + p2x * f
	local pMw = p0w * (1 - f) + p2w * f

	if pMx > p1x then
		pMx, p1x = p1x, pMx
		pMw, p1w = p1w, pMw
	end

	local rowTopMin = math_floor(p0y + 0.5)
	local rowBottomMin = math_floor(p1y + 0.5)
	local rowTopMax = rowBottomMin - 1
	local rowBottomMax = math_ceil(p2y - 0.5)

	if rowTopMin < 0 then rowTopMin = 0 end
	if rowBottomMin < 0 then rowBottomMin = 0 end
	if rowTopMax > fb_height_m1 then rowTopMax = fb_height_m1 end
	if rowBottomMax > fb_height_m1 then rowBottomMax = fb_height_m1 end

	if rowTopMin <= rowTopMax then
		local topDeltaY = p1y - p0y
		local topLeftGradientX = (pMx - p0x) / topDeltaY
		local topRightGradientX = (p1x - p0x) / topDeltaY
		local topLeftGradientW = (pMw - p0w) / topDeltaY
		local topRightGradientW = (p1w - p0w) / topDeltaY

		local topProjection = rowTopMin + 0.5 - p0y
		local topLeftX = p0x + topLeftGradientX * topProjection - 0.5
		local topRightX = p0x + topRightGradientX * topProjection - 1.5
		local topLeftW = p0w + topLeftGradientW * topProjection
		local topRightW = p0w + topRightGradientW * topProjection

		for baseIndex = rowTopMin * fb_width + 1, rowTopMax * fb_width + 1, fb_width do
			local columnMinX = math_ceil(topLeftX)
			local columnMaxX = math_ceil(topRightX)
			local rowTotalDeltaX = topRightX - topLeftX + 1 -- 'cause of awkward optimisations above
			local rowDeltaW = (topRightW - topLeftW) / rowTotalDeltaX
			local rowLeftW = topLeftW + (columnMinX - topLeftX) * rowDeltaW

			if columnMinX < 0 then columnMinX = 0 end
			if columnMaxX > fb_width_m1 then columnMaxX = fb_width_m1 end

			for x = columnMinX, columnMaxX do
				local index = baseIndex + x

				if rowLeftW > fb_depth[index] then
					fb_front[index] = colour
					fb_depth[index] = rowLeftW
				end

				rowLeftW = rowLeftW + rowDeltaW
			end

			topLeftX = topLeftX + topLeftGradientX
			topRightX = topRightX + topRightGradientX
			topLeftW = topLeftW + topLeftGradientW
			topRightW = topRightW + topRightGradientW
		end
	end

	if rowBottomMin <= rowBottomMax then
		local bottomDeltaY = p2y - p1y
		local bottomLeftGradientX = (p2x - pMx) / bottomDeltaY
		local bottomRightGradientX = (p2x - p1x) / bottomDeltaY
		local bottomLeftGradientW = (p2w - pMw) / bottomDeltaY
		local bottomRightGradientW = (p2w - p1w) / bottomDeltaY

		local bottomProjection = rowBottomMin + 0.5 - p1y
		local bottomLeftX = pMx + bottomLeftGradientX * bottomProjection - 0.5
		local bottomRightX = p1x + bottomRightGradientX * bottomProjection - 1.5
		local bottomLeftW = pMw + bottomLeftGradientW * bottomProjection
		local bottomRightW = p1w + bottomRightGradientW * bottomProjection

		for baseIndex = rowBottomMin * fb_width + 1, rowBottomMax * fb_width + 1, fb_width do
			local columnMinX = math_ceil(bottomLeftX)
			local columnMaxX = math_ceil(bottomRightX)
			local rowTotalDeltaX = bottomRightX - bottomLeftX + 1 -- 'cause of awkward optimisations above
			local rowDeltaW = (bottomRightW - bottomLeftW) / rowTotalDeltaX
			local rowLeftW = bottomLeftW + (columnMinX - bottomLeftX) * rowDeltaW

			if columnMinX < 0 then columnMinX = 0 end
			if columnMaxX > fb_width_m1 then columnMaxX = fb_width_m1 end

			for x = columnMinX, columnMaxX do
				local index = baseIndex + x

				if rowLeftW > fb_depth[index] then
					fb_front[index] = colour
					fb_depth[index] = rowLeftW
				end

				rowLeftW = rowLeftW + rowDeltaW
			end

			bottomLeftX = bottomLeftX + bottomLeftGradientX
			bottomRightX = bottomRightX + bottomRightGradientX
			bottomLeftW = bottomLeftW + bottomLeftGradientW
			bottomRightW = bottomRightW + bottomRightGradientW
		end
	end
end

--- @param fb ccFramebuffer
--- @param geometry ccGeometry
--- @param camera ccCamera
local function render_geometry(fb, geometry, camera, aspect_ratio, cull_back_faces, depth_test)
	local DATA_PER_TRIANGLE = 10
	local clipping_plane = -0.0001
	local pxd = (fb.width - 1) / 2
	local pyd = (fb.height - 1) / 2
	local pxs = pyd
	local pys = -pyd
	local fb_front, fb_width = fb.front, fb.width
	local fb_depth = fb.depth
	local fb_height_m1 = fb.height - 1
	local math_sin, math_cos = math.sin, math.cos

	aspect_ratio = aspect_ratio or fb.width / fb.height
	cull_back_faces = cull_back_faces or 0

	local rasterize_triangle_fn = depth_test ~= false and rasterize_triangle_depth or rasterize_triangle_nodepth

	local sinX = math_sin(-camera.xRotation)
	local sinY = math_sin(camera.yRotation)
	local sinZ = math_sin(-camera.zRotation)
	local cosX = math_cos(-camera.xRotation)
	local cosY = math_cos(camera.yRotation)
	local cosZ = math_cos(-camera.zRotation)
	local scale_y = 1 / math.tan(camera.fov)
	local scale_x = scale_y * aspect_ratio

	scale_x = scale_x * pxs
	scale_y = scale_y * pys

	local fxx = cosY*cosZ+sinX*sinY*sinZ
	local fxy = cosX*sinZ
	local fxz = -sinY*cosZ + sinX*cosY*sinZ
	local fyx = -cosY*sinZ + sinX*sinY*cosZ
	local fyy = cosX*cosZ
	local fyz = sinY*sinZ + sinX*cosY*cosZ
	local fzx = cosX*sinY
	local fzy = -sinX
	local fzz = cosX*cosY
	local fdx = -camera.x
	local fdy = -camera.y
	local fdz = -camera.z

	for i = 1, geometry.triangles * DATA_PER_TRIANGLE, DATA_PER_TRIANGLE do
		local p0x = geometry[i]
		local p0y = geometry[i + 1]
		local p0z = geometry[i + 2]
		local p1x = geometry[i + 3]
		local p1y = geometry[i + 4]
		local p1z = geometry[i + 5]
		local p2x = geometry[i + 6]
		local p2y = geometry[i + 7]
		local p2z = geometry[i + 8]
		local colour = geometry[i + 9]

		p0x = p0x + fdx
		p0y = p0y + fdy
		p0z = p0z + fdz

		p1x = p1x + fdx
		p1y = p1y + fdy
		p1z = p1z + fdz

		p2x = p2x + fdx
		p2y = p2y + fdy
		p2z = p2z + fdz

		local cull_face = false

		if cull_back_faces ~= 0 then
			local d1x = p1x - p0x
			local d1y = p1y - p0y
			local d1z = p1z - p0z
			local d2x = p2x - p0x
			local d2y = p2y - p0y
			local d2z = p2z - p0z
			local cx = d1y*d2z - d1z*d2y
			local cy = d1z*d2x - d1x*d2z
			local cz = d1x*d2y - d1y*d2x
			local d = cx * p0x + cy * p0y + cz * p0z
			cull_face = d * cull_back_faces > 0
		end

		if not cull_face then
			p0x, p0y, p0z = fxx * p0x + fxy * p0y + fxz * p0z
			              , fyx * p0x + fyy * p0y + fyz * p0z
			              , fzx * p0x + fzy * p0y + fzz * p0z

			p1x, p1y, p1z = fxx * p1x + fxy * p1y + fxz * p1z
			              , fyx * p1x + fyy * p1y + fyz * p1z
			              , fzx * p1x + fzy * p1y + fzz * p1z

			p2x, p2y, p2z = fxx * p2x + fxy * p2y + fxz * p2z
			              , fyx * p2x + fyy * p2y + fyz * p2z
			              , fzx * p2x + fzy * p2y + fzz * p2z

			-- TODO: make this split polygons
			if p0z <= clipping_plane and p1z <= clipping_plane and p2z <= clipping_plane then
				local p0w = -1 / p0z
				local p1w = -1 / p1z
				local p2w = -1 / p2z

				p0x = pxd + p0x * scale_x * p0w
				p0y = pyd + p0y * scale_y * p0w
				p1x = pxd + p1x * scale_x * p1w
				p1y = pyd + p1y * scale_y * p1w
				p2x = pxd + p2x * scale_x * p2w
				p2y = pyd + p2y * scale_y * p2w

				rasterize_triangle_fn(fb_front, fb_depth, fb_width, fb_height_m1, p0x, p0y, p0w, p1x, p1y, p1w, p2x, p2y, p2w, colour)
			end
		end
	end
end

--------------------------------------------------------------------------------

return {
	create_framebuffer = create_framebuffer,
	create_framebuffer_subpixel = create_framebuffer_subpixel,
	clear_framebuffer = clear_framebuffer,
	present_framebuffer = present_framebuffer,
	present_framebuffer_depth = present_framebuffer_depth,
	create_geometry = create_geometry,
	add_triangle = add_triangle,
	rotate_geometry_z = rotate_geometry_z,
	create_perspective_camera = create_perspective_camera,
	render_geometry = render_geometry,
}
