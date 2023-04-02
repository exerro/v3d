
local v3d = require 'core'

--------------------------------------------------------------------------------
--[[ v3d.Transform ]]-----------------------------------------------------------
--------------------------------------------------------------------------------

do
	--- A transform is an object representing a transformation which can be applied
	--- to 3D positions and directions. Transforms are capable of things like
	--- translation, rotation, and scaling. Internally, they represent the first 3
	--- rows of a row-major 4x4 matrix. The last row is dropped for performance
	--- reasons, but is assumed to equal `[0, 0, 0, 1]` at all times.
	--- @class v3d.Transform
	--- @operator mul (v3d.Transform): v3d.Transform
	v3d.Transform = {}

	--- Combine this transform with another, returning a transform which first
	--- applies the 2nd transform, and then this one.
	---
	--- ```lua
	--- local result = transform_a:combine(transform_b)
	--- -- result is a transform which will first apply transform_b, then
	--- -- transform_a
	--- ```
	---
	--- Note: you can also use the `*` operator to combine transforms:
	---
	--- ```lua
	--- local result = transform_a * transform_b
	--- ```
	--- @param transform v3d.Transform Other transform which will be applied first.
	--- @return v3d.Transform
	--- @nodiscard
	function v3d.Transform:combine(transform)
		local t = v3d.identity()

		t[ 1] = self[ 1] * transform[1] + self[ 2] * transform[5] + self[ 3] * transform[ 9]
		t[ 2] = self[ 1] * transform[2] + self[ 2] * transform[6] + self[ 3] * transform[10]
		t[ 3] = self[ 1] * transform[3] + self[ 2] * transform[7] + self[ 3] * transform[11]
		t[ 4] = self[ 1] * transform[4] + self[ 2] * transform[8] + self[ 3] * transform[12] + self[ 4]

		t[ 5] = self[ 5] * transform[1] + self[ 6] * transform[5] + self[ 7] * transform[ 9]
		t[ 6] = self[ 5] * transform[2] + self[ 6] * transform[6] + self[ 7] * transform[10]
		t[ 7] = self[ 5] * transform[3] + self[ 6] * transform[7] + self[ 7] * transform[11]
		t[ 8] = self[ 5] * transform[4] + self[ 6] * transform[8] + self[ 7] * transform[12] + self[ 8]

		t[ 9] = self[ 9] * transform[1] + self[10] * transform[5] + self[11] * transform[ 9]
		t[10] = self[ 9] * transform[2] + self[10] * transform[6] + self[11] * transform[10]
		t[11] = self[ 9] * transform[3] + self[10] * transform[7] + self[11] * transform[11]
		t[12] = self[ 9] * transform[4] + self[10] * transform[8] + self[11] * transform[12] + self[12]

		return t
	end

	--- Apply this transformation to the data provided, returning a new table with
	--- the modified X, Y, and Z position components.
	--- @param data number[] Data to be transformed.
	--- @param translate boolean Whether to apply translation. If false, only linear transformations like scaling and rotation will be applied.
	--- @param offset integer | nil Offset within the data to transform the vertex. 0 means no offset. Defaults to 0.
	--- @return number, number, number
	--- @nodiscard
	function v3d.Transform:transform(data, translate, offset)
		offset = offset or 0

		local d1 = data[offset + 1]
		local d2 = data[offset + 2]
		local d3 = data[offset + 3]

		local r1 = self[1] * d1 + self[ 2] * d2 + self[ 3] * d3
		local r2 = self[5] * d1 + self[ 6] * d2 + self[ 7] * d3
		local r3 = self[9] * d1 + self[10] * d2 + self[11] * d3

		if translate then
			r1 = r1 + self[ 4]
			r2 = r2 + self[ 8]
			r3 = r3 + self[12]
		end

		return r1, r2, r3
	end

	--- TODO
	--- @return v3d.Transform
	--- @nodiscard
	function v3d.Transform:inverse()
		-- TODO: untested!
		local tr_xx = self[1]
		local tr_xy = self[2]
		local tr_xz = self[3]
		local tr_yx = self[5]
		local tr_yy = self[6]
		local tr_yz = self[7]
		local tr_zx = self[9]
		local tr_zy = self[10]
		local tr_zz = self[11]

		local inverse_det = 1/(tr_xx*(tr_yy*tr_zz-tr_zy*tr_yz)
							-tr_xy*(tr_yx*tr_zz-tr_yz*tr_zx)
							+tr_xz*(tr_yx*tr_zy-tr_yy*tr_zx))
		local inverse_xx =  (tr_yy*tr_zz-tr_zy*tr_yz) * inverse_det
		local inverse_xy = -(tr_xy*tr_zz-tr_xz*tr_zy) * inverse_det
		local inverse_xz =  (tr_xy*tr_yz-tr_xz*tr_yy) * inverse_det
		local inverse_yx = -(tr_yx*tr_zz-tr_yz*tr_zx) * inverse_det
		local inverse_yy =  (tr_xx*tr_zz-tr_xz*tr_zx) * inverse_det
		local inverse_yz = -(tr_xx*tr_yz-tr_yx*tr_xz) * inverse_det
		local inverse_zx =  (tr_yx*tr_zy-tr_zx*tr_yy) * inverse_det
		local inverse_zy = -(tr_xx*tr_zy-tr_zx*tr_xy) * inverse_det
		local inverse_zz =  (tr_xx*tr_yy-tr_yx*tr_xy) * inverse_det

		return v3d.translate(-self[4], -self[8], -self[12]):combine {
			inverse_xx, inverse_xy, inverse_xz, 0,
			inverse_yx, inverse_yy, inverse_yz, 0,
			inverse_zx, inverse_zy, inverse_zz, 0,
		}
	end
end

--------------------------------------------------------------------------------
--[[ Constructors ]]------------------------------------------------------------
--------------------------------------------------------------------------------

do
	v3d.Transform.metatable = { __mul = v3d.Transform.combine }

	--- Create a [[@v3d.Transform]] which has no effect.
	--- @return v3d.Transform
	--- @nodiscard
	function v3d.identity()
		local t = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0 }

		for k, v in pairs(v3d.Transform) do
			t[k] = v
		end
	
		return setmetatable(t, v3d.Transform.metatable)
	end

	--- Create a [[@v3d.Transform]] which translates points by `(dx, dy, dz)` units.
	--- Note: the `translate` parameter of [[@v3d.Transform.transform]] must be true
	--- for this to have any effect.
	--- @param dx number Delta X.
	--- @param dy number Delta Y.
	--- @param dz number Delta Z.
	--- @return v3d.Transform
	--- @nodiscard
	function v3d.translate(dx, dy, dz)
		local t = { 1, 0, 0, dx, 0, 1, 0, dy, 0, 0, 1, dz }

		for k, v in pairs(v3d.Transform) do
			t[k] = v
		end
	
		return setmetatable(t, v3d.Transform.metatable)
	end

	--- Create a [[@v3d.Transform]] which scales (multiplies) points by
	--- `(sx, sy, sz)` units.
	--- @param sx number Scale X.
	--- @param sy number Scale Y.
	--- @param sz number Scale Z.
	--- @overload fun(sx: number, sy: number, sz: number): v3d.Transform
	--- @overload fun(scale: number): v3d.Transform
	--- @return v3d.Transform
	--- @nodiscard
	function v3d.scale(sx, sy, sz)
		local t = { sx, 0, 0, 0, 0, sy or sx, 0, 0, 0, 0, sz or sx, 0 }

		for k, v in pairs(v3d.Transform) do
			t[k] = v
		end

		return setmetatable(t, v3d.Transform.metatable)
	end

	--- Create a [[@v3d.Transform]] which rotates points by `(tx, ty, tz)` radians
	--- around `(0, 0, 0)`. The order of rotation is ZXY, that is it rotates Y
	--- first, then X, then Z.
	--- @param tx number Amount to rotate around the X axis, in radians.
	--- @param ty number Amount to rotate around the Y axis, in radians.
	--- @param tz number Amount to rotate around the Z axis, in radians.
	--- @return v3d.Transform
	--- @nodiscard
	function v3d.rotate(tx, ty, tz)
		local math_sin = math.sin
		local math_cos = math.cos
		local sin_x = math_sin(tx)
		local sin_y = math_sin(ty)
		local sin_z = math_sin(tz)
		local cos_x = math_cos(tx)
		local cos_y = math_cos(ty)
		local cos_z = math_cos(tz)
		local fxx = cos_y*cos_z - sin_x*sin_y*sin_z
		local fxy = cos_x*sin_z
		local fxz = sin_y*cos_z + sin_x*cos_y*sin_z
		local fyx = -cos_y*sin_z - sin_x*sin_y*cos_z
		local fyy = cos_x*cos_z
		local fyz = -sin_y*sin_z + sin_x*cos_y*cos_z
		local fzx = -cos_x*sin_y
		local fzy = -sin_x
		local fzz = cos_x*cos_y
		local t = { fxx, fxy, fxz, 0, fyx, fyy, fyz, 0, fzx, fzy, fzz, 0 }

		for k, v in pairs(v3d.Transform) do
			t[k] = v
		end

		return setmetatable(t, v3d.Transform.metatable)
	end

	--- Create a [[@v3d.Transform]] which simulates a camera. The various overloads
	--- of this function allow you to specify the position, rotation, and FOV of the
	--- camera. The resultant transform will apply the inverse translation and
	--- rotation before scaling to apply the FOV.
	---
	--- Rotation is ZXY ordered, i.e. the inverse Y is applied first, then X, then
	--- Z. This corresponds to pan, tilt, and roll.
	--- @param x number X coordinate of the origin of the viewing frustum.
	--- @param y number Y coordinate of the origin of the viewing frustum.
	--- @param z number Z coordinate of the origin of the viewing frustum.
	--- @param x_rotation number Rotation of the viewing frustum about the X axis.
	--- @param y_rotation number Rotation of the viewing frustum about the Y axis.
	--- @param z_rotation number Rotation of the viewing frustum about the Z axis.
	--- @param fov number | nil Vertical field of view, i.e. the angle between the top and bottom planes of the viewing frustum. Defaults to PI / 3 (60 degrees).
	--- @overload fun(x: number, y: number, z: number, x_rotation: number, y_rotation: number, z_rotation: number, fov: number | nil): v3d.Transform
	--- @overload fun(x: number, y: number, z: number, y_rotation: number, fov: number | nil): v3d.Transform
	--- @overload fun(x: number, y: number, z: number): v3d.Transform
	--- @overload fun(fov: number | nil): v3d.Transform
	--- @return v3d.Transform
	--- @nodiscard
	function v3d.camera(x, y, z, x_rotation, y_rotation, z_rotation, fov)
		if not y then
			fov = x
			x = 0
		end
	
		if not z_rotation then
			fov = y_rotation
			y_rotation = x_rotation
			x_rotation = 0
		end
	
		fov = fov or math.pi / 3
		x_rotation = x_rotation or 0
		y_rotation = y_rotation or 0
		z_rotation = z_rotation or 0
		x = x or 0
		y = y or 0
		z = z or 0
	
		local tan_inverse = 1 / math.tan(fov / 2)

		return v3d.Transform.combine(
			v3d.Transform.combine(
				{ tan_inverse, 0, 0, 0, 0, tan_inverse, 0, 0, 0, 0, 1, 0 },
				v3d.rotate(-x_rotation, -y_rotation, -z_rotation)
			),
			{ 1, 0, 0, -x, 0, 1, 0, -y, 0, 0, 1, -z }
		)
	end
end
