
local transform_index = {}
local transform_mt = { __index = transform_index }

local math_sin = math.sin
local math_cos = math.cos

-- TODO: scaling
local function createTransform(dx, dy, dz, ry, rx, rz, sx, sy, sz)
	local transform = {
		dx = dx, dy = dy, dz = dz,
		ry = ry, rx = rx, rz = rz,
		sx = sx, sy = sy, sz = sz,
		has_forward_multipliers = false,
		fxx = nil, fxy = nil, fxz = nil, -- to get X
		fyx = nil, fyy = nil, fyz = nil, -- to get Y
		fzx = nil, fzy = nil, fzz = nil, -- to get Z
		has_inverse_multipliers = false,
		ixx = nil, ixy = nil, ixz = nil, -- to get X
		iyx = nil, iyy = nil, iyz = nil, -- to get Y
		izx = nil, izy = nil, izz = nil, -- to get Z
	}

	return setmetatable(transform, transform_mt)
end

function transform_index:get_multipliers()
	if not self.has_forward_multipliers then
		local cX, sX = math_cos(self.rx), math_sin(self.rx)
		local cY, sY = math_cos(self.ry), math_sin(self.ry)
		local cZ, sZ = math_cos(self.rz), math_sin(self.rz)
		local scx, scy, scz = self.sx, self.sy, self.sz

		self.fxx, self.fxy, self.fxz = (cY*cZ + sX*sY*sZ)*scx, (cZ*sX*sY - cY*sZ)*scy, (cX*sY)*scz
		self.fyx, self.fyy, self.fyz = (cX*sZ)*scx, (cX*cZ)*scy, (-sX)*scz
		self.fzx, self.fzy, self.fzz = (-cZ*sY + cY*sX*sZ)*scx, (cY*cZ*sX + sY*sZ)*scy, (cX*cY)*scz

		self.has_forward_multipliers = true
	end

	return self.fxx, self.fxy, self.fxz, self.fyx, self.fyy, self.fyz, self.fzx, self.fzy, self.fzz
end

function transform_index:get_inverse_multipliers()
	if not self.has_inverse_multipliers then
		error "TODO"

		self.has_inverse_multipliers = true
	end

	return self.ixx, self.ixy, self.ixz, self.iyx, self.iyy, self.iyz, self.izx, self.izy, self.izz
end

function transform_index:translate_by(dx, dy, dz)
	return createTransform(self.dx + dx, self.dy + dy, self.dz + dz, self.ry, self.rx, self.rz, self.sx, self.sy, self.sz)
end

function transform_index:rotate_y_by(theta)
	return createTransform(self.dx, self.dy, self.dz, self.ry + theta, self.rx, self.rz, self.sx, self.sy, self.sz)
end

function transform_index:rotate_x_by(theta)
	return createTransform(self.dx, self.dy, self.dz, self.ry, self.rx + theta, self.rz, self.sx, self.sy, self.sz)
end

function transform_index:rotate_z_by(theta)
	return createTransform(self.dx, self.dy, self.dz, self.ry, self.rx, self.rz + theta, self.sx, self.sy, self.sz)
end

function transform_index:scale_by(sx, sy, sz)
	return createTransform(self.dx, self.dy, self.dz, self.ry, self.rx, self.rz, self.sx * sx, self.sy * sy, self.sz * sz)
end

function transform_index:translate_to(dx, dy, dz)
	return createTransform(dx, dy, dz, self.ry, self.rx, self.rz, self.sx, self.sy, self.sz)
end

function transform_index:rotate_y_to(theta)
	return createTransform(self.dx, self.dy, self.dz, theta, self.rx, self.rz, self.sx, self.sy, self.sz)
end

function transform_index:rotate_x_to(theta)
	return createTransform(self.dx, self.dy, self.dz, self.ry, theta, self.rz, self.sx, self.sy, self.sz)
end

function transform_index:rotate_z_to(theta)
	return createTransform(self.dx, self.dy, self.dz, self.ry, self.rx, theta, self.sx, self.sy, self.sz)
end

function transform_index:scale_to(sx, sy, sz)
	return createTransform(self.dx, self.dy, self.dz, self.ry, self.rx, self.rz, sx, sy, sz)
end

return createTransform(0, 0, 0, 0, 0, 0, 1, 1, 1)
