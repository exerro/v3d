
local BufferFormat = require "lib.BufferFormat"
local TextureFormat = require "lib.TextureFormat"
local libtexture = require "lib.texture"

local math_ceil = math.ceil
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local math_tan = math.tan
local table_unpack = table.unpack

local function clear(texture)
	assert(type(texture) == "table" and texture.__type == libtexture.__type, "Expected texture")

	local clearValue = 0

	if texture.format == TextureFormat.Col1 then
		clearValue = 1
	end

	for i = 1, texture.width * texture.height * texture.pixel_size do
		texture[i] = clearValue
	end
end

local function draw_triangles(buffer, texture, camera, viewport, options)
	local nearClip = -0.01
	local tanFOV = math_tan(camera.fov)
	local xPerspectiveMult = 1 / (viewport.width / viewport.height) / tanFOV
	local yPerspectiveMult = 1 / tanFOV

	local modelTransform = options and options.model_transform
	local viewTransform = options and options.view_transform
	local cullBackFace = options and options.cull_back_face
	local mtfxx, mtfxy, mtfxz, mtfyx, mtfyy, mtfyz, mtfzx, mtfzy, mtfzz, mtfdx, mtfdy, mtfdz
	local vtixx, vtixy, vtixz, vtiyx, vtiyy, vtiyz, vtizx, vtizy, vtizz, vtidx, vtidy, vtidz

	if modelTransform then
		mtfxx, mtfxy, mtfxz, mtfyx, mtfyy, mtfyz, mtfzx, mtfzy, mtfzz = modelTransform:get_multipliers()
		mtfdx, mtfdy, mtfdz = modelTransform.dx, modelTransform.dy, modelTransform.dz
	end

	if viewTransform then
		vtixx, vtixy, vtixz, vtiyx, vtiyy, vtiyz, vtizx, vtizy, vtizz = viewTransform:get_inverse_multipliers()
		mtfdx, mtfdy, mtfdz = viewTransform.dx, viewTransform.dy, viewTransform.dz
	end

	assert(buffer.format == BufferFormat.Pos3Col1)

	local i = 1
	local buffer_size = buffer.size

	-- pre-fill the buffer with a lot of data in a few instructions to minimise array resize overhead on the JVM side
	local raster_edges = { table_unpack(buffer) }
	local raster_edge_index = 1

	-- raster_edges format is:
	-- (yMin, yMax)
	-- (xLeft, dxLeft, zLeft, dzLeft)
	-- (xRight, dxRight, zRight, dzRight)
	-- colour

	while i < buffer_size do repeat
		local x0, y0, z0 = buffer[i], buffer[i + 1], buffer[i + 2]
		local x1, y1, z1 = buffer[i + 3], buffer[i + 4], buffer[i + 5]
		local x2, y2, z2 = buffer[i + 6], buffer[i + 7], buffer[i + 8]
		local colour = buffer[i + 9]
		i = i + 10

		-- model transform
		if modelTransform then
			x0, y0, z0
				= mtfxx * x0 + mtfxy * y0 + mtfxz * z0 + mtfdx
				, mtfyx * x0 + mtfyy * y0 + mtfyz * z0 + mtfdy
				, mtfzx * x0 + mtfzy * y0 + mtfzz * z0 + mtfdz
			x1, y1, z1
				= mtfxx * x1 + mtfxy * y1 + mtfxz * z1 + mtfdx
				, mtfyx * x1 + mtfyy * y1 + mtfyz * z1 + mtfdy
				, mtfzx * x1 + mtfzy * y1 + mtfzz * z1 + mtfdz
			x2, y2, z2
				= mtfxx * x2 + mtfxy * y2 + mtfxz * z2 + mtfdx
				, mtfyx * x2 + mtfyy * y2 + mtfyz * z2 + mtfdy
				, mtfzx * x2 + mtfzy * y2 + mtfzz * z2 + mtfdz
		end

		-- view transform
		if viewTransform then
			x0, y0, z0 = x0 - vtidx, y0 - vtidy, z0 - vtidz
			x1, y1, z1 = x1 - vtidx, y1 - vtidy, z1 - vtidz
			x2, y2, z2 = x2 - vtidx, y2 - vtidy, z2 - vtidz
			x0, y0, z0
				= vtixx * x0 + vtixy * y0 + vtixz * z0
				, vtiyx * x0 + vtiyy * y0 + vtiyz * z0
				, vtizx * x0 + vtizy * y0 + vtizz * z0
			x1, y1, z1
				= vtixx * x1 + vtixy * y1 + vtixz * z1
				, vtiyx * x1 + vtiyy * y1 + vtiyz * z1
				, vtizx * x1 + vtizy * y1 + vtizz * z1
			x2, y2, z2
				= vtixx * x2 + vtixy * y2 + vtixz * z2
				, vtiyx * x2 + vtiyy * y2 + vtiyz * z2
				, vtizx * x2 + vtizy * y2 + vtizz * z2
		end

		-- perspective transform
		x0 = x0 * xPerspectiveMult; y0 = y0 * yPerspectiveMult
		x1 = x1 * xPerspectiveMult; y1 = y1 * yPerspectiveMult
		x2 = x2 * xPerspectiveMult; y2 = y2 * yPerspectiveMult

		-- compute depth values
		local d0 = -z0
		local d1 = -z1
		local d2 = -z2

		-- depth divide for X/Y components
		-- Y flip for screen coordinates
		x0 = x0 / d0; y0 = -y0 / d0
		x1 = x1 / d1; y1 = -y1 / d1
		x2 = x2 / d2; y2 = -y2 / d2

		-- backface culling
		if cullBackFace then
			local dx0, dy0 = x1 - x0, y1 - y0
			local dx1, dy1 = x2 - x0, y2 - y0
			local cz = dx0*dy1 - dy0*dx1 -- cross product z component

			if cz >= 0 then -- cull the face
				break -- this is actually a continue
			end
		end

		-- do Z clipping to prevent weird artifacts when triangles are behind the camera
		if z0 < nearClip and z1 < nearClip and z2 < nearClip then -- all vertices are valid
			-- note: we don't care about Z values from here on
			-- order vertices so: y0 < y1 < y2
			if y0 > y1 then x0, y0, d0, x1, y1, d1 = x1, y1, d1, x0, y0, d0 end
			if y1 > y2 then x1, y1, d1, x2, y2, d2 = x2, y2, d2, x1, y1, d1 end
			if y0 > y1 then x0, y0, d0, x1, y1, d1 = x1, y1, d1, x0, y0, d0 end

			-- TODO: handle y0 = y1 = y2
		
			-- calculate point on P0->P2 edge intersecting with P1y
			local dy01 = y1 - y0
			local dy01inv = 1 / dy01
			local dy12 = y2 - y1
			local dy12inv = 1 / dy12
			local d = dy01 / (y2 - y0)
			local xP = x0 + (x2 - x0) * d
			local yP = y0 + (y2 - y0) * d

			-- append top section (if non empty)
			if y0 ~= y1 then
				raster_edges[raster_edge_index] = y0
				raster_edges[raster_edge_index + 1] = y1
				raster_edges[raster_edge_index + 2] = x0
				raster_edges[raster_edge_index + 6] = x0

				if x1 < xP then
					raster_edges[raster_edge_index + 3] = (x1 - x0) * dy01inv
					raster_edges[raster_edge_index + 7] = (xP - x0) * dy01inv
				else
					raster_edges[raster_edge_index + 3] = (xP - x0) * dy01inv
					raster_edges[raster_edge_index + 7] = (x1 - x0) * dy01inv
				end

				raster_edges[raster_edge_index + 10] = colour
				raster_edge_index = raster_edge_index + 11
			end

			-- append bottom section (if non empty)
			if y1 ~= y2 then
				raster_edges[raster_edge_index] = y1
				raster_edges[raster_edge_index + 1] = y2

				if x1 < xP then
					raster_edges[raster_edge_index + 2] = x1
					raster_edges[raster_edge_index + 3] = (x2 - x1) * dy12inv
					raster_edges[raster_edge_index + 6] = xP
					raster_edges[raster_edge_index + 7] = (x2 - xP) * dy12inv
				else
					raster_edges[raster_edge_index + 2] = xP
					raster_edges[raster_edge_index + 3] = (x2 - xP) * dy12inv
					raster_edges[raster_edge_index + 6] = x1
					raster_edges[raster_edge_index + 7] = (x2 - x1) * dy12inv
				end
			
				raster_edges[raster_edge_index + 10] = colour
				raster_edge_index = raster_edge_index + 11
			end
		else
			-- order vertices so: z0 < z1 < z2
			if z0 > z1 then x0, y0, z0, x1, y1, z1 = x1, y1, z1, x0, y0, z0 end
			if z1 > z2 then x1, y1, z1, x2, y2, z2 = x2, y2, z2, x1, y1, z1 end
			if z0 > z1 then x0, y0, z0, x1, y1, z1 = x1, y1, z1, x0, y0, z0 end
		
			if z1 < nearClip then -- P2 vertex should be clipped
				-- note: we don't care about Z values from here on
				-- @queue quad p0, p1 quad (split twice at mid Ys)
				error "TODO"
			elseif z0 < nearClip then -- P1 and P2 vertices should be clipped
				-- note: we don't care about Z values from here on
				-- @queue p0 sub-triangle (split at mid Y)
				error "TODO"
			else -- all vertices clipped, triangle ignored
				-- do nothing
			end
		end
	until true end

	for i = 1, raster_edge_index - 1, 11 do
		local yMin, yMax, xLeft, dxLeft, zLeft, dzLeft, xRight, dxRight, zRight, dzRight, colour =
			raster_edges[i], raster_edges[i + 1], raster_edges[i + 2], raster_edges[i + 3], raster_edges[i + 4], raster_edges[i + 5], raster_edges[i + 6], raster_edges[i + 7], raster_edges[i + 8], raster_edges[i + 9], raster_edges[i + 10]

		local yMinPixel = math_floor((1 + yMin) * (viewport.height - 1) * 0.5 + 0.5)
		local yMaxPixel = math_ceil((1 + yMax) * (viewport.height - 1) * 0.5 - 0.5)
		
		local vw1half = (viewport.width - 1) * 0.5

		local xAbsoluteMin = math_max(-1, math_min(xLeft, xLeft + (yMax - yMin) * dxLeft))
		local xAbsoluteMax = math_min(1, math_max(xRight, xRight + (yMax - yMin) * dxRight))
		local xAbsoluteMinPixel = math_floor((1 + xAbsoluteMin) * vw1half + 0.5)
		local xAbsoluteMaxPixel = math_ceil((1 + xAbsoluteMax) * vw1half - 0.5)
		local dyScale = 2 / (viewport.height - 1)

		for yPixel = math_max(0, yMinPixel), math_min(viewport.height, yMaxPixel) do
			local baseIndex = yPixel * texture.width + 1
			local xRowLeft = xLeft + dxLeft * (yPixel - yMinPixel) * dyScale
			local xRowRight = xRight + dxRight * (yPixel - yMinPixel) * dyScale
			local xLeftPixel = math_floor((1 + xRowLeft) * vw1half + 0.5)
			local xRightPixel = math_ceil((1 + xRowRight) * vw1half - 0.5)

			for x = math_max(xLeftPixel, xAbsoluteMinPixel), math_min(xRightPixel, xAbsoluteMaxPixel) do
				texture[baseIndex + x] = colour
			end
		end
	end
end

return {
	clear = clear,
	draw_triangles = draw_triangles,
}
