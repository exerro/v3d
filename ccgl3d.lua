
--- @class cc_term_lib
--- @field blit function
--- @field setCursorPos function

--------------------------------------------------------------------------------

local CH_SPACE = string.byte ' '
local CH_0 = string.byte '0'
local CH_A = string.byte 'a'
local ch_lookup = {}
local string_char = string.char
local table_unpack = table.unpack

for i = 0, 15 do
	ch_lookup[2 ^ i] = i < 10 and CH_0 + i or CH_A + (i - 10)
end

--- @class ccFramebuffer
--- @field width integer
--- @field height integer
--- @field front table
--- @field back table

--- @param width integer
--- @param height integer
--- @return ccFramebuffer
local function create_framebuffer(width, height)
	local fb = {}

	fb.width = width
	fb.height = height
	fb.front = {}
	fb.back = {}

	for i = 1, width * height do
		fb.front[i] = 1
		fb.back[i] = 1
	end

	return fb
end

--- @param width integer
--- @param height integer
--- @return ccFramebuffer
local function create_framebuffer_subpixel(width, height)
	return create_framebuffer(width * 2, height * 3) -- multiply by subpixel dimensions
end

--- @param fb ccFramebuffer
--- @param colour integer
local function clear_framebuffer(fb, colour)
	local fb_front = fb.front
	for i = 1, fb.width * fb.height do
		fb_front[i] = colour
	end
end

local function create_proximity_list(term)
	local rgbLookup = {}
	local distances = {}

	for i = 0, 15 do
		rgbLookup[2 ^ i] = { term.getPaletteColour(2 ^ i) }
		distances[2 ^ i] = {}
	end

	for i = 0, 15 do
		local i0 = 2 ^ i
		local rgb0 = rgbLookup[i0]
		for j = i + 1, 15 do
			local i1 = 2 ^ j
			local rgb1 = rgbLookup[i1]
			local dr = rgb1[1] - rgb0[1]
			local dg = rgb1[2] - rgb0[2]
			local db = rgb1[3] - rgb0[3]
			local distance = dr * dr + dg * dg + db * db
			table.insert(distances[i0], { i1, distance })
			table.insert(distances[i1], { i0, distance })
		end
	end
	
	for i = 0, 15 do
		local t = distances[2 ^ i]
		table.sort(t, function(a, b) return a[2] < b[2] end)
		
		for i = 1, #t do
			t[i] = t[i][1]
		end
	end

	return distances
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

	local front, back = fb.front, fb.back
	fb.front, fb.back = back, front -- swap buffers

	local xBlit = 1 + dx
	local yBlit = 1 + dy

	local palette_proximity_list -- lateinit

	-- TODO: optimise this
	for y = 0, fb.height - 1, SUBPIXEL_HEIGHT do
		local ch_t = {}
		local fg_t = {}
		local bg_t = {}
		local ix = 1

		for x = 1, fb.width, SUBPIXEL_WIDTH do
			local i0 = y * fb.width + x
			local i1, i2 = i0 + fb.width, i0 + fb.width * 2
			local c00, c10 = front[i0], front[i0 + 1]
			local c01, c11 = front[i1], front[i1 + 1]
			local c02, c12 = front[i2], front[i2 + 1]
			local votes = { [c00] = 1 }
			local max1c, max1n = c00, 1
			local max2c, max2n = nil, 0
			local colours = { c00, c10, c01, c11, c02, c12 }
			local start = 2

			for i = start, 6 do
				local c = colours[i]
				if c ~= max1c then
					max2c = c
					max2n = 1
					votes[c] = 1
					start = 3
					break
				end
			end

			if max2n == 0 then
				ch_t[ix] = CH_SPACE
				fg_t[ix] = CH_0
				bg_t[ix] = ch_lookup[max1c]
			else
				for i = start, 6 do
					local c = colours[i]
					local cVotes = (votes[c] or 0) + 1
					votes[c] = cVotes
					if c == max1c then
						max1n = cVotes
					elseif c == max2c then
						max2n = cVotes
						if max2n > max1n then
							max1c, max1n, max2c, max2n = max2c, max2n, max1c, max1n
						end
					elseif cVotes > max1n then
						max1c, max1n, max2c, max2n = c, cVotes, max1c, max1n
					elseif cVotes > max2n then
						max2c, max2n = c, cVotes
					end
				end

				if max1n + max2n < 6 then
					-- TODO: switch to spatial proximity
					palette_proximity_list = palette_proximity_list or create_proximity_list(term)

					for i = 1, 6 do
						local c = colours[i]
						if c ~= max1c and c ~= max2c then
							local p = palette_proximity_list[c]
							for j = 1, #p do
								local pp = p[j]
								if pp == max1c then
									colours[i] = max1c
									break
								elseif pp == max2c then
									colours[i] = max2c
									break
								end
							end
						end
					end
				end

				-- max1c will be foreground colour
				-- subpixels require 6th colour to be background colour
				if colours[6] == max1c then
					max1c, max2c = max2c, max1c
				end

				local subpixel_value = 0
				for i = 5, 1, -1 do
					subpixel_value = subpixel_value * 2
					if colours[i] == max1c then
						subpixel_value = subpixel_value + 1
					end
				end

				ch_t[ix] = 128 + subpixel_value
				fg_t[ix] = ch_lookup[max1c]
				bg_t[ix] = ch_lookup[max2c]
			end

			ix = ix + 1
		end

		term.setCursorPos(xBlit, yBlit)
		term.blit(string_char(table_unpack(ch_t)), string_char(table_unpack(fg_t)), string_char(table_unpack(bg_t)))
		yBlit = yBlit + 1
	end
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
local function rasterize_flat_triangle(
	fb_front,
	fb_width, fb_height,
	y0, y1,
	lx, lxt,
	rx, rxt,
	xmin, xmax,
	colour)
	-- p*x, p*y are pixel coordinates
	local y0i = math.max(0, math.min(math.floor(y0 + 0.5), fb_height - 1))
	local y1i = math.max(0, math.min(math.floor(y1 + 0.5), fb_height - 1))
	local y0Error = (y0i - math.floor(y0 + 0.5)) / (y1 - y0)
	local y1Error = (math.floor(y1 + 0.5) - y1i) / (y1 - y0)

	lx = lx + (lxt - lx) * y0Error
	rx = rx + (rxt - rx) * y0Error
	lxt = lxt - (lxt - lx) * y1Error
	rxt = rxt - (rxt - rx) * y1Error

	local ldd = (lxt - lx) / (y1i - y0i)
	local rdd = (rxt - rx) / (y1i - y0i)

	for y = y0i, y1i do
		local yi = y * fb_width + 1
		local lxi = math.max(xmin, math.min(xmax, math.floor(lx + 0.5)))
		local rxi = math.max(xmin, math.min(xmax, math.floor(rx + 0.5)))
		for x = lxi, rxi do
			fb_front[yi + x] = colour
		end
		lx = lx + ldd
		rx = rx + rdd
	end
end

--- @private
local function rasterize_triangle(
	fb_front,
	fb_width, fb_height,
	pxd, pyd,
	pxs, pys,
	p0x, p0y,
	p1x, p1y,
	p2x, p2y,
	colour)
	-- p*x, p*y are normalised -1 to 1 in a box centred on the centre of the
	-- screen whose height corresponds to the screen height
	if p0y > p1y then
		p0x, p0y, p1x, p1y = p1x, p1y, p0x, p0y
	end

	if p1y > p2y then
		p1x, p1y, p2x, p2y = p2x, p2y, p1x, p1y
	end

	if p0y > p1y then
		p0x, p0y, p1x, p1y = p1x, p1y, p0x, p0y
	end

	-- p0, p1, p2 are in height order top -> bottom

	-- convert to screen coordinates
	p0x, p0y = pxd + p0x * pxs, pyd + p0y * pys
	p1x, p1y = pxd + p1x * pxs, pyd + p1y * pys
	p2x, p2y = pxd + p2x * pxs, pyd + p2y * pys
	-- note, p0, p1, p2 are now height order bottom -> top

	if p0y == p2y then
		return -- skip early if we have a perfectly flat triangle
	end

	local midpointX = p0x + (p2x - p0x) * (p1y - p0y) / (p2y - p0y)

	if midpointX == p1x then
		return -- skip early if we have a perfectly flat triangle
	end

	local lx, rx = midpointX, p1x

	if rx < lx then
		lx, rx = rx, lx
	end

	if p0y ~= p1y then
		local xmin = math.max(0, math.floor(math.min(lx, p0x) + 0.5))
		local xmax = math.min(fb_width - 1, math.floor(math.max(rx, p0x) + 0.5))
		rasterize_flat_triangle(fb_front, fb_width, fb_height, p1y, p0y, lx, p0x, rx, p0x, xmin, xmax, colour)
	end

	if p1y ~= p2y then
		local xmin = math.max(0, math.floor(math.min(lx, p2x) + 0.5))
		local xmax = math.min(fb_width - 1, math.floor(math.max(rx, p2x) + 0.5))
		rasterize_flat_triangle(fb_front, fb_width, fb_height, p2y, p1y, p2x, lx, p2x, rx, xmin, xmax, colour)
	end
end

--- @param fb ccFramebuffer
--- @param geometry ccGeometry
--- @param camera ccCamera
local function render_geometry(fb, geometry, camera, aspect_ratio)
	local DATA_PER_TRIANGLE = 10
	local clipping_plane = -0.0001
	local pxd = (fb.width - 1) / 2
	local pyd = (fb.height - 1) / 2
	local pxs = pyd
	local pys = -pyd

	aspect_ratio = aspect_ratio or fb.width / fb.height

	local sinX = math.sin(-camera.xRotation)
	local sinY = math.sin(-camera.yRotation)
	local sinZ = math.sin(-camera.zRotation)
	local cosX = math.cos(-camera.xRotation)
	local cosY = math.cos(-camera.yRotation)
	local cosZ = math.cos(-camera.zRotation)
	local scale_y = 1 / math.tan(camera.fov)
	local scale_x = scale_y * aspect_ratio

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

		p0x = fxx * p0x + fxy * p0y + fxz * p0z
		p0y = fyx * p0x + fyy * p0y + fyz * p0z
		p0z = fzx * p0x + fzy * p0y + fzz * p0z

		p1x = fxx * p1x + fxy * p1y + fxz * p1z
		p1y = fyx * p1x + fyy * p1y + fyz * p1z
		p1z = fzx * p1x + fzy * p1y + fzz * p1z

		p2x = fxx * p2x + fxy * p2y + fxz * p2z
		p2y = fyx * p2x + fyy * p2y + fyz * p2z
		p2z = fzx * p2x + fzy * p2y + fzz * p2z

		p0x = p0x * scale_x
		p0y = p0y * scale_y
		p1x = p1x * scale_x
		p1y = p1y * scale_y
		p2x = p2x * scale_x
		p2y = p2y * scale_y

		-- TODO: backface culling

		if p0z <= clipping_plane and p1z <= clipping_plane and p2z <= clipping_plane then
			local p0d = -1 / p0z
			local p1d = -1 / p1z
			local p2d = -1 / p2z
			rasterize_triangle(fb.front, fb.width, fb.height, pxd, pyd, pxs, pys, p0x * p0d, p0y * p0d, p1x * p1d, p1y * p1d, p2x * p2d, p2y * p2d, colour)
		end
	end
end

--------------------------------------------------------------------------------

return {
	create_framebuffer = create_framebuffer,
	create_framebuffer_subpixel = create_framebuffer_subpixel,
	clear_framebuffer = clear_framebuffer,
	present_framebuffer = present_framebuffer,
	create_geometry = create_geometry,
	add_triangle = add_triangle,
	rotate_geometry_z = rotate_geometry_z,
	create_perspective_camera = create_perspective_camera,
	rasterize_triangle = rasterize_triangle,
	render_geometry = render_geometry,
}
