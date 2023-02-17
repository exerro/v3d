
local simplex = require 'util.simplex'

--- @type { [integer]: Model, [string]: Model }
local models = {}

local cube_polygons -- defined at bottom of file

--- @class Model
--- @field id string
--- @field name string
--- * 'flat' format means 3 (X,Y,Z) tuples followed by a colour repeated in a
---   table, e.g. { x00, y00, z00, x01, y01, z01, x02, y02, z02, c0, x10, y10, z10, x11, y11, z11, x12, y12, z12, c0, ... }
--- * 'named-struct-*' are both a list of { x0, y0, z0, x1, y1, z1, x2, y2, z2,
---   colour } tables. The suffix denotes what is "right", "up" and "forward".
--- @field format 'flat' | 'named-struct-X+Y+Z-' | 'named-struct-Z+Y+X+'
--- TODO
--- @field default_details { [integer]: integer }
--- Function to create a model, given values for the parameters. Should return
--- data according to the format.
--- @field create_model fun(...): { [integer]: ModelNamedStructPolygon | number }

--- @class ModelNamedStructPolygon 3 vertex positions and a colour
--- @field x0 number World space X coordinate of the first triangle vertex
--- @field y0 number World space Y coordinate of the first triangle vertex
--- @field z0 number World space Z coordinate of the first triangle vertex
--- @field x1 number World space X coordinate of the second triangle vertex
--- @field y1 number World space Y coordinate of the second triangle vertex
--- @field z1 number World space Z coordinate of the second triangle vertex
--- @field x2 number World space X coordinate of the third triangle vertex
--- @field y2 number World space Y coordinate of the third triangle vertex
--- @field z2 number World space Z coordinate of the third triangle vertex
--- @field colour integer CC colour e.g. colours.red or 2^14

--------------------------------------------------------------------------------

table.insert(models, {
	id = 'box',
	name = 'Box',
	format = 'flat',
	default_details = { 4, 8, 25 },
	create_model = function(detail)
		local data = {}

		local z = -5
		local dz = -z * 2 / detail

		local dy = dz

		for _ = 1, detail do
			local x = -5
			local dx = -x * 2 / detail
	
			for _ = 1, detail do
				for i = 1, #cube_polygons, 10 do
					table.insert(data, cube_polygons[i + 0] * dx + x)
					table.insert(data, cube_polygons[i + 1] * dy)
					table.insert(data, cube_polygons[i + 2] * dz + z)
					table.insert(data, cube_polygons[i + 3] * dx + x)
					table.insert(data, cube_polygons[i + 4] * dy)
					table.insert(data, cube_polygons[i + 5] * dz + z)
					table.insert(data, cube_polygons[i + 6] * dx + x)
					table.insert(data, cube_polygons[i + 7] * dy)
					table.insert(data, cube_polygons[i + 8] * dz + z)
					table.insert(data, cube_polygons[i + 9])
				end

				x = x + dx
			end

			z = z + dz
		end

		return data
	end
})

--------------------------------------------------------------------------------

table.insert(models, {
	id = 'land',
	name = 'Land',
	format = 'flat',
	default_details = { 4, 8, 16 },
	create_model = function(detail)
		local data = {}
		local xs = 5 / detail
		local zs = 5 / detail
		local ns = 1 / 3

		for z = -detail, detail - 1 do
			for x = -detail, detail - 1 do
				local h00 = simplex.Noise2D((x + 0) * ns * xs, (z + 0) * ns * zs)
				local h01 = simplex.Noise2D((x + 0) * ns * xs, (z + 1) * ns * zs)
				local h10 = simplex.Noise2D((x + 1) * ns * xs, (z + 0) * ns * zs)
				local h11 = simplex.Noise2D((x + 1) * ns * xs, (z + 1) * ns * zs)

				for _, v in ipairs {
					(x + 0) * xs, h00, (z + 0) * zs,
					(x + 0) * xs, h01, (z + 1) * zs,
					(x + 1) * xs, h11, (z + 1) * zs,
					colours.lime,
					(x + 0) * xs, h00, (z + 0) * zs,
					(x + 1) * xs, h11, (z + 1) * zs,
					(x + 1) * xs, h10, (z + 0) * zs,
					colours.green,
				} do
					table.insert(data, v)
				end
			end
		end

		return data
	end,
})

--------------------------------------------------------------------------------

cube_polygons = {
	-- front (ignored for visibility)
	--  0,  0.5,  1,  0, -0.5,  1,  1,  0.5,  1, colours.blue,
	--  0, -0.5,  1,  1, -0.5,  1,  1,  0.5,  1, colours.cyan,
	-- back
	 1,  0.5,  0,  1, -0.5,  0,  0,  0.5,  0, colours.brown,
	 1, -0.5,  0,  0, -0.5,  0,  0,  0.5,  0, colours.yellow,
	-- left
	 0,  0.5,  0,  0, -0.5,  0,  0,  0.5,  1, colours.lightBlue,
	 0, -0.5,  0,  0, -0.5,  1,  0,  0.5,  1, colours.pink,
	-- right
	 1,  0.5,  1,  1, -0.5,  1,  1,  0.5,  0, colours.red,
	 1, -0.5,  1,  1, -0.5,  0,  1,  0.5,  0, colours.orange,
	-- top
	 0,  0.5,  0,  0,  0.5,  1,  1,  0.5,  0, colours.green,
	 0,  0.5,  1,  1,  0.5,  1,  1,  0.5,  0, colours.lime,
	-- bottom
	 1, -0.5,  0,  1, -0.5,  1,  0, -0.5,  0, colours.purple,
	 1, -0.5,  1,  0, -0.5,  1,  0, -0.5,  0, colours.magenta,
}

--------------------------------------------------------------------------------

for i = 1, #models do
	models[models[i].id] = models[i]
end

return models
