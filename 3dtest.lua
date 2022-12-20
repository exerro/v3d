
local model_from_points -- functions defined later
local rendering_lib -- set later
local simplex = {} -- simplex noise lib, defined later - use simplex.NoiseND e.g. simplex.Noise2D

--------------------------------------------------------------------------------

--- @param model BenchmarkModel
--- @param width integer
--- @param height integer
local function model_to_functions(model, width, height)
	local term = term

	if rendering_lib == 'ccgl3d' then
		local ccgl3d = require 'ccgl3d'
		local fb = ccgl3d.create_framebuffer_subpixel(width, height)
		local geom = ccgl3d.create_geometry()
		local camera = ccgl3d.create_perspective_camera()
		local ccgl3d_present = ccgl3d.present_framebuffer
		local ccgl3d_render = ccgl3d.render_geometry

		camera.xRotation = 0.3
		camera.z = 3
		camera.y = 3

		for i = 1, model.triangles do
			local t = model[i]
			ccgl3d.add_triangle(geom, t.x0, t.y0, t.z0, t.x1, t.y1, t.z1, t.x2, t.y2, t.z2, t.colour)
		end

		local function clear_fn()
			ccgl3d.clear_framebuffer(fb, colours.white)
			ccgl3d.rotate_geometry_z(geom, 0.01)
		end

		local function draw_fn()
			ccgl3d_render(fb, geom, camera)
		end

		local function present_fn()
			ccgl3d_present(fb, term, 0, 0)
		end

		return clear_fn, draw_fn, present_fn
	else
		error('Unknown rendering library \'' .. rendering_lib .. '\'')
	end
end

--------------------------------------------------------------------------------

--- @class Benchmark
--- @field name string
--- @field warmup_iterations integer
--- @field min_iterations integer
--- @field min_duration number
--- @field create_functions fun(width: integer, height: integer): BenchmarkClear, BenchmarkDraw, BenchmarkPresent

--- @alias BenchmarkClear fun()
--- @alias BenchmarkDraw fun()
--- @alias BenchmarkPresent fun()

--- @type { [integer]: Benchmark }
local benchmarks = {}

--- Model composed of a list of triangles, each with its own vertex positions
--- and colour
--- @alias BenchmarkModel { triangles: integer, [integer]: BenchmarkTriangle }

--- +X = right
--- @class BenchmarkTriangle 3 vertex positions and a colour
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

--- @type { [integer]: { name: string, width: integer, height: integer } }
local sizes = {
	{ name = 'Small',   width = 10,  height =   5 },
	{ name = 'Turtle',  width = 39,  height =  13 },
	{ name = 'Pocket',  width = 26,  height =  20 },
	{ name = 'Normal',  width = 51,  height =  19 },
	{ name = 'Monitor', width = 162, height =  80 },
	{ name = '540p',    width = 260, height = 120 }, -- divide by (2, 3) to account for subpixels
}

table.insert(benchmarks, {
	name = 'Simple box (10t)',
	warmup_iterations = 50,
	min_iterations = 10,
	min_duration = 0.5,
	create_functions = function(width, height)
		return model_to_functions(model_from_points {
			-- front (ignored for visibility)
			-- -1,  1, -1, -1, -1, -1,  1,  1, -1, colours.blue,
			-- -1, -1, -1,  1, -1, -1,  1,  1, -1, colours.cyan,
			-- back
			 1,  1, -3,  1, -1, -3, -1,  1, -3, colours.brown,
			 1, -1, -3, -1, -1, -3, -1,  1, -3, colours.yellow,
			-- left
			-1,  1, -3, -1, -1, -3, -1,  1, -1, colours.lightBlue,
			-1, -1, -3, -1, -1, -1, -1,  1, -1, colours.pink,
			-- right
			 1,  1, -1,  1, -1, -1,  1,  1, -3, colours.red,
			 1, -1, -1,  1, -1, -3,  1,  1, -3, colours.orange,
			-- top
			-1,  1, -3, -1,  1, -1,  1,  1, -3, colours.green,
			-1,  1, -1,  1,  1, -1,  1,  1, -3, colours.lime,
			-- bottom
			 1, -1, -3,  1, -1, -1, -1, -1, -3, colours.purple,
			 1, -1, -1, -1, -1, -1, -1, -1, -3, colours.magenta,
		}, width, height)
	end,
})

local function create_noise(n)
	table.insert(benchmarks, {
		name = 'Noisey terrain (' .. 4 * n * n .. 't)',
		warmup_iterations = 50,
		min_iterations = 10,
		min_duration = 0.5,
		create_functions = function(width, height)
			local data = {}
			local xs = 5 / n
			local zs = 5 / n
			local ns = 1 / 3
			local z0 = -5

			for x = -n, n - 1 do
				for z = -n, n - 1 do
					local h00 = simplex.Noise2D((x + 0) * ns * xs, (z + 0) * ns * zs)
					local h01 = simplex.Noise2D((x + 0) * ns * xs, (z + 1) * ns * zs)
					local h10 = simplex.Noise2D((x + 1) * ns * xs, (z + 0) * ns * zs)
					local h11 = simplex.Noise2D((x + 1) * ns * xs, (z + 1) * ns * zs)

					for _, v in ipairs {
						(x + 0) * xs, h00, (z + 0) * zs + z0,
						(x + 0) * xs, h01, (z + 1) * zs + z0,
						(x + 1) * xs, h11, (z + 1) * zs + z0,
						colours.lime,
						(x + 0) * xs, h00, (z + 0) * zs + z0,
						(x + 1) * xs, h11, (z + 1) * zs + z0,
						(x + 1) * xs, h10, (z + 0) * zs + z0,
						colours.green,
					} do
						table.insert(data, v)
					end
				end
			end

			return model_to_functions(model_from_points(data), width, height)
		end,
	})
end

create_noise(10)
create_noise(25)

--------------------------------------------------------------------------------

local args = { ... }

-- TODO: use these
local specific_benchmark = nil
local show_results = false
local test_only = false

while true do
	if args[1] == '-b' then
		specific_benchmark = table.remove(args, 2)
		table.remove(args, 1)
	elseif args[1] == 'd' then
		show_results = true
		table.remove(args, 1)
	elseif args[1] == '-t' then
		test_only = true
		table.remove(args, 1)
	else
		break
	end
end

rendering_lib = table.remove(args, 1)

if args[1] then
	return error("Unexpected arguments: " .. table.concat(args))
end

print("Benchmarking " .. rendering_lib)

if specific_benchmark then
	print("Running benchmark: " .. specific_benchmark)
else
	print("Running all benchmarks")
end

if show_results then
	print("Showing results")
end

--------------------------------------------------------------------------------

local function benchmark(clear_fn, draw_fn, present_fn, warmup_iterations, min_iterations, min_duration)
	local clock = os.clock

	for i = 1, warmup_iterations do
		clear_fn()
		draw_fn()
		present_fn()
	end

	local iterations = 0
	local ttd = 0
	local ttp = 0
	local t0 = clock()
	repeat
		clear_fn()
		local t0d = clock()
		draw_fn()
		ttd = ttd + clock() - t0d
		local t0p = clock()
		present_fn()
		ttp = ttp + clock() - t0p
		iterations = iterations + 1
		if clock() - t0 > 0.5 then
			os.queueEvent 'benchmark_yield'
			coroutine.yield 'benchmark_yield'
			t0 = clock()
		end
	until iterations >= min_iterations and ttd + ttp >= min_duration

	return iterations, ttd, ttp
end

function model_from_points(t)
	local r = { triangles = #t / 10 }

	for i = 1, #t, 10 do
		local s = {}
		s.x0 = t[i]
		s.y0 = t[i + 1]
		s.z0 = t[i + 2]
		s.x1 = t[i + 3]
		s.y1 = t[i + 4]
		s.z1 = t[i + 5]
		s.x2 = t[i + 6]
		s.y2 = t[i + 7]
		s.z2 = t[i + 8]
		s.colour = t[i + 9]
		table.insert(r, s)
	end

	return r
end

--------------------------------------------------------------------------------
-----------------------------------------------
---Simplex Noise
-- Original Java Source: http://staffwww.itn.liu.se/~stegu/simplexnoise/simplexnoise.pdf
-- (most) Original comments included
-----------------------------------------------

local math = math
local table = table
local tonumber = tonumber
local ipairs = ipairs
local error = error
local bit = require("bit")

simplex.DIR_X = 0
simplex.DIR_Y = 1
simplex.DIR_Z = 2
simplex.DIR_W = 3
simplex.internalCache = false


local Gradients3D = {{1,1,0},{-1,1,0},{1,-1,0},{-1,-1,0},
{1,0,1},{-1,0,1},{1,0,-1},{-1,0,-1},
{0,1,1},{0,-1,1},{0,1,-1},{0,-1,-1}};
local Gradients4D = {{0,1,1,1}, {0,1,1,-1}, {0,1,-1,1}, {0,1,-1,-1},
{0,-1,1,1}, {0,-1,1,-1}, {0,-1,-1,1}, {0,-1,-1,-1},
{1,0,1,1}, {1,0,1,-1}, {1,0,-1,1}, {1,0,-1,-1},
{-1,0,1,1}, {-1,0,1,-1}, {-1,0,-1,1}, {-1,0,-1,-1},
{1,1,0,1}, {1,1,0,-1}, {1,-1,0,1}, {1,-1,0,-1},
{-1,1,0,1}, {-1,1,0,-1}, {-1,-1,0,1}, {-1,-1,0,-1},
{1,1,1,0}, {1,1,-1,0}, {1,-1,1,0}, {1,-1,-1,0},
{-1,1,1,0}, {-1,1,-1,0}, {-1,-1,1,0}, {-1,-1,-1,0}};
local p = {151,160,137,91,90,15,
131,13,201,95,96,53,194,233,7,225,140,36,103,30,69,142,8,99,37,240,21,10,23,
190, 6,148,247,120,234,75,0,26,197,62,94,252,219,203,117,35,11,32,57,177,33,
88,237,149,56,87,174,20,125,136,171,168, 68,175,74,165,71,134,139,48,27,166,
77,146,158,231,83,111,229,122,60,211,133,230,220,105,92,41,55,46,245,40,244,
102,143,54, 65,25,63,161, 1,216,80,73,209,76,132,187,208, 89,18,169,200,196,
135,130,116,188,159,86,164,100,109,198,173,186, 3,64,52,217,226,250,124,123,
5,202,38,147,118,126,255,82,85,212,207,206,59,227,47,16,58,17,182,189,28,42,
223,183,170,213,119,248,152, 2,44,154,163, 70,221,153,101,155,167, 43,172,9,
129,22,39,253, 19,98,108,110,79,113,224,232,178,185, 112,104,218,246,97,228,
251,34,242,193,238,210,144,12,191,179,162,241, 81,51,145,235,249,14,239,107,
49,192,214, 31,181,199,106,157,184, 84,204,176,115,121,50,45,127, 4,150,254,
138,236,205,93,222,114,67,29,24,72,243,141,128,195,78,66,215,61,156,180};

-- To remove the need for index wrapping, double the permutation table length

for i=1,#p do
	p[i-1] = p[i]
	p[i] = nil
end

for i=1,#Gradients3D do
	Gradients3D[i-1] = Gradients3D[i]
	Gradients3D[i] = nil
end

for i=1,#Gradients4D do
	Gradients4D[i-1] = Gradients4D[i]
	Gradients4D[i] = nil
end

local perm = {}

for i=0,255 do
	perm[i] = p[i]
	perm[i+256] = p[i]
end

-- A lookup table to traverse the sim around a given point in 4D.
-- Details can be found where this table is used, in the 4D noise method.

local sim = {
{0,1,2,3},{0,1,3,2},{0,0,0,0},{0,2,3,1},{0,0,0,0},{0,0,0,0},{0,0,0,0},{1,2,3,0},
{0,2,1,3},{0,0,0,0},{0,3,1,2},{0,3,2,1},{0,0,0,0},{0,0,0,0},{0,0,0,0},{1,3,2,0},
{0,0,0,0},{0,0,0,0},{0,0,0,0},{0,0,0,0},{0,0,0,0},{0,0,0,0},{0,0,0,0},{0,0,0,0},
{1,2,0,3},{0,0,0,0},{1,3,0,2},{0,0,0,0},{0,0,0,0},{0,0,0,0},{2,3,0,1},{2,3,1,0},
{1,0,2,3},{1,0,3,2},{0,0,0,0},{0,0,0,0},{0,0,0,0},{2,0,3,1},{0,0,0,0},{2,1,3,0},
{0,0,0,0},{0,0,0,0},{0,0,0,0},{0,0,0,0},{0,0,0,0},{0,0,0,0},{0,0,0,0},{0,0,0,0},
{2,0,1,3},{0,0,0,0},{0,0,0,0},{0,0,0,0},{3,0,1,2},{3,0,2,1},{0,0,0,0},{3,1,2,0},
{2,1,0,3},{0,0,0,0},{0,0,0,0},{0,0,0,0},{3,1,0,2},{0,0,0,0},{3,2,0,1},{3,2,1,0}};

local function Dot2D(tbl, x, y)
	return tbl[1]*x + tbl[2]*y; 
end

local function Dot3D(tbl, x, y, z)
	return tbl[1]*x + tbl[2]*y + tbl[3]*z
end

local function Dot4D( tbl, x,y,z,w) 
	return tbl[1]*x + tbl[2]*y + tbl[3]*z + tbl[3]*w;
end

local Prev2D = {}


-- 2D simplex noise

function simplex.Noise2D(xin, yin)
	if simplex.internalCache and Prev2D[xin] and Prev2D[xin][yin] then return Prev2D[xin][yin] end 

	local n0, n1, n2; -- Noise contributions from the three corners
	-- Skew the input space to determine which simplex cell we're in
	local F2 = 0.5*(math.sqrt(3.0)-1.0);
	local s = (xin+yin)*F2; -- Hairy factor for 2D
	local i = math.floor(xin+s);
	local j = math.floor(yin+s);
	local G2 = (3.0-math.sqrt(3.0))/6.0;
	
	local t = (i+j)*G2;
	local X0 = i-t; -- Unskew the cell origin back to (x,y) space
	local Y0 = j-t;
	local x0 = xin-X0; -- The x,y distances from the cell origin
	local y0 = yin-Y0;
	
	-- For the 2D case, the simplex shape is an equilateral triangle.
	-- Determine which simplex we are in.
	local i1, j1; -- Offsets for second (middle) corner of simplex in (i,j) coords
	if(x0>y0) then 
		i1=1 
		j1=0  -- lower triangle, XY order: (0,0)->(1,0)->(1,1)
	else
		i1=0
		j1=1 -- upper triangle, YX order: (0,0)->(0,1)->(1,1)
	end
	
	-- A step of (1,0) in (i,j) means a step of (1-c,-c) in (x,y), and
	-- a step of (0,1) in (i,j) means a step of (-c,1-c) in (x,y), where
	-- c = (3-sqrt(3))/6

	local x1 = x0 - i1 + G2; -- Offsets for middle corner in (x,y) unskewed coords
	local y1 = y0 - j1 + G2;
	local x2 = x0 - 1.0 + 2.0 * G2; -- Offsets for last corner in (x,y) unskewed coords
	local y2 = y0 - 1.0 + 2.0 * G2;

	-- Work out the hashed gradient indices of the three simplex corners
	local ii = bit.band(i , 255)
	local jj = bit.band(j , 255)
	local gi0 = perm[ii+perm[jj]] % 12;
	local gi1 = perm[ii+i1+perm[jj+j1]] % 12;
	local gi2 = perm[ii+1+perm[jj+1]] % 12;

	-- Calculate the contribution from the three corners
	local t0 = 0.5 - x0*x0-y0*y0;
	if t0<0 then 
		n0 = 0.0;
	else
		t0 = t0 * t0
		n0 = t0 * t0 * Dot2D(Gradients3D[gi0], x0, y0); -- (x,y) of Gradients3D used for 2D gradient
	end
	
	local t1 = 0.5 - x1*x1-y1*y1;
	if (t1<0) then
		n1 = 0.0;
	else
		t1 = t1*t1
		n1 = t1 * t1 * Dot2D(Gradients3D[gi1], x1, y1);
	end
	
	local t2 = 0.5 - x2*x2-y2*y2;
	if (t2<0) then
		n2 = 0.0;
	else
		t2 = t2*t2
		n2 = t2 * t2 * Dot2D(Gradients3D[gi2], x2, y2);
	end

	
	-- Add contributions from each corner to get the final noise value.
	-- The result is scaled to return values in the localerval [-1,1].
	
	local retval = 70.0 * (n0 + n1 + n2)
	
	if simplex.internalCache then
		if not Prev2D[xin] then Prev2D[xin] = {} end
		Prev2D[xin][yin] = retval
	end
	
	return retval;
end

local Prev3D = {}

-- 3D simplex noise
function simplex.Noise3D(xin, yin, zin)
	
	if simplex.internalCache and Prev3D[xin] and Prev3D[xin][yin] and Prev3D[xin][yin][zin] then return Prev3D[xin][yin][zin] end
	
	local n0, n1, n2, n3; -- Noise contributions from the four corners
	
	-- Skew the input space to determine which simplex cell we're in
	local F3 = 1.0/3.0;
	local s = (xin+yin+zin)*F3; -- Very nice and simple skew factor for 3D
	local i = math.floor(xin+s);
	local j = math.floor(yin+s);
	local k = math.floor(zin+s);
	
	local G3 = 1.0/6.0; -- Very nice and simple unskew factor, too
	local t = (i+j+k)*G3;
	
	local X0 = i-t; -- Unskew the cell origin back to (x,y,z) space
	local Y0 = j-t;
	local Z0 = k-t;
	
	local x0 = xin-X0; -- The x,y,z distances from the cell origin
	local y0 = yin-Y0;
	local z0 = zin-Z0;
	
	-- For the 3D case, the simplex shape is a slightly irregular tetrahedron.
	-- Determine which simplex we are in.
	local i1, j1, k1; -- Offsets for second corner of simplex in (i,j,k) coords
	local i2, j2, k2; -- Offsets for third corner of simplex in (i,j,k) coords
	
	if (x0>=y0) then
		if (y0>=z0) then
			i1=1; j1=0; k1=0; i2=1; j2=1; k2=0; -- X Y Z order
		elseif (x0>=z0) then
			i1=1; j1=0; k1=0; i2=1; j2=0; k2=1; -- X Z Y order
		else 
			i1=0; j1=0; k1=1; i2=1; j2=0; k2=1;  -- Z X Y order
		end
	else -- x0<y0
		if (y0<z0) then 
			i1=0; j1=0; k1=1; i2=0; j2=1; k2=1; -- Z Y X order
		elseif (x0<z0) then 
			i1=0; j1=1; k1=0; i2=0; j2=1; k2=1; -- Y Z X order
		else 
			i1=0; j1=1; k1=0; i2=1; j2=1; k2=0; -- Y X Z order
		end
	end
	
	-- A step of (1,0,0) in (i,j,k) means a step of (1-c,-c,-c) in (x,y,z),
	-- a step of (0,1,0) in (i,j,k) means a step of (-c,1-c,-c) in (x,y,z), and
	-- a step of (0,0,1) in (i,j,k) means a step of (-c,-c,1-c) in (x,y,z), where
	-- c = 1/6.
	
	local x1 = x0 - i1 + G3; -- Offsets for second corner in (x,y,z) coords
	local y1 = y0 - j1 + G3;
	local z1 = z0 - k1 + G3;
	
	local x2 = x0 - i2 + 2.0*G3; -- Offsets for third corner in (x,y,z) coords
	local y2 = y0 - j2 + 2.0*G3;
	local z2 = z0 - k2 + 2.0*G3;
	
	local x3 = x0 - 1.0 + 3.0*G3; -- Offsets for last corner in (x,y,z) coords
	local y3 = y0 - 1.0 + 3.0*G3;
	local z3 = z0 - 1.0 + 3.0*G3;
	
	-- Work out the hashed gradient indices of the four simplex corners
	local ii = bit.band(i , 255)
	local jj = bit.band(j , 255)
	local kk = bit.band(k , 255)
	
	local gi0 = perm[ii+perm[jj+perm[kk]]] % 12;
	local gi1 = perm[ii+i1+perm[jj+j1+perm[kk+k1]]] % 12;
	local gi2 = perm[ii+i2+perm[jj+j2+perm[kk+k2]]] % 12;
	local gi3 = perm[ii+1+perm[jj+1+perm[kk+1]]] % 12;
	
	-- Calculate the contribution from the four corners
	local t0 = 0.5 - x0*x0 - y0*y0 - z0*z0;
	
	if (t0<0) then
		n0 = 0.0;
	else 
		t0 = t0*t0;
		n0 = t0 * t0 * Dot3D(Gradients3D[gi0], x0, y0, z0);
	end
	
	local t1 = 0.5 - x1*x1 - y1*y1 - z1*z1;
	
	if (t1<0) then 
		n1 = 0.0;
	else
		t1 = t1*t1;
		n1 = t1 * t1 * Dot3D(Gradients3D[gi1], x1, y1, z1);
	end
	
	local t2 = 0.5 - x2*x2 - y2*y2 - z2*z2;
	
	if (t2<0) then 
		n2 = 0.0;
	else
		t2 = t2*t2;
		n2 = t2 * t2 * Dot3D(Gradients3D[gi2], x2, y2, z2);
	end
	
	local t3 = 0.5 - x3*x3 - y3*y3 - z3*z3;
	
	if (t3<0) then 
		n3 = 0.0;
	else
		t3 = t3*t3;
		n3 = t3 * t3 * Dot3D(Gradients3D[gi3], x3, y3, z3);
	end
	
	
	-- Add contributions from each corner to get the final noise value.
	-- The result is scaled to stay just inside [-1,1]
	local retval = 32.0*(n0 + n1 + n2 + n3)
	
	if simplex.internalCache then
		if not Prev3D[xin] then Prev3D[xin] = {} end
		if not Prev3D[xin][yin] then Prev3D[xin][yin] = {} end
		Prev3D[xin][yin][zin] = retval
	end
	
	return retval;
end

local Prev4D = {}

-- 4D simplex noise
function simplex.Noise4D(x,y,z,w)

	if simplex.internalCache and Prev4D[x] and Prev4D[x][y] and Prev4D[x][y][z] and Prev4D[x][y][z][w] then return Prev4D[x][y][z][w] end
	
	-- The skewing and unskewing factors are hairy again for the 4D case
	local F4 = (math.sqrt(5.0)-1.0)/4.0;
	local G4 = (5.0-math.sqrt(5.0))/20.0;
	local n0, n1, n2, n3, n4; -- Noise contributions from the five corners
	-- Skew the (x,y,z,w) space to determine which cell of 24 simplices we're in
	local s = (x + y + z + w) * F4; -- Factor for 4D skewing
	local i = math.floor(x + s);
	local j = math.floor(y + s);
	local k = math.floor(z + s);
	local l = math.floor(w + s);
	local t = (i + j + k + l) * G4; -- Factor for 4D unskewing
	local X0 = i - t; -- Unskew the cell origin back to (x,y,z,w) space
	local Y0 = j - t;
	local Z0 = k - t;
	local W0 = l - t;
	local x0 = x - X0; -- The x,y,z,w distances from the cell origin
	local y0 = y - Y0;
	local z0 = z - Z0;
	local w0 = w - W0;
	-- For the 4D case, the simplex is a 4D shape I won't even try to describe.
	-- To find out which of the 24 possible simplices we're in, we need to
	-- determine the magnitude ordering of x0, y0, z0 and w0.
	-- The method below is a good way of finding the ordering of x,y,z,w and
	-- then find the correct traversal order for the simplex were in.
	-- First, six pair-wise comparisons are performed between each possible pair
	-- of the four coordinates, and the results are used to add up binary bits
	-- for an localeger index.
	local c1 = (x0 > y0) and 32 or 1;
	local c2 = (x0 > z0) and 16 or 1;
	local c3 = (y0 > z0) and 8 or 1;
	local c4 = (x0 > w0) and 4 or 1;
	local c5 = (y0 > w0) and 2 or 1;
	local c6 = (z0 > w0) and 1 or 1;
	local c = c1 + c2 + c3 + c4 + c5 + c6;
	local i1, j1, k1, l1; -- The localeger offsets for the second simplex corner
	local i2, j2, k2, l2; -- The localeger offsets for the third simplex corner
	local i3, j3, k3, l3; -- The localeger offsets for the fourth simplex corner
	
	-- sim[c] is a 4-vector with the numbers 0, 1, 2 and 3 in some order.
	-- Many values of c will never occur, since e.g. x>y>z>w makes x<z, y<w and x<w
	-- impossible. Only the 24 indices which have non-zero entries make any sense.
	-- We use a thresholding to set the coordinates in turn from the largest magnitude.
	-- The number 3 in the "sim" array is at the position of the largest coordinate.
	
	i1 = sim[c][1]>=3 and 1 or 0;
	j1 = sim[c][2]>=3 and 1 or 0;
	k1 = sim[c][3]>=3 and 1 or 0;
	l1 = sim[c][4]>=3 and 1 or 0;
	-- The number 2 in the "sim" array is at the second largest coordinate.
	i2 = sim[c][1]>=2 and 1 or 0;
	j2 = sim[c][2]>=2 and 1 or 0;
	k2 = sim[c][3]>=2 and 1 or 0;
	l2 = sim[c][4]>=2 and 1 or 0;
	-- The number 1 in the "sim" array is at the second smallest coordinate.
	i3 = sim[c][1]>=1 and 1 or 0;
	j3 = sim[c][2]>=1 and 1 or 0;
	k3 = sim[c][3]>=1 and 1 or 0;
	l3 = sim[c][4]>=1 and 1 or 0;
	-- The fifth corner has all coordinate offsets = 1, so no need to look that up.
	local x1 = x0 - i1 + G4; -- Offsets for second corner in (x,y,z,w) coords
	local y1 = y0 - j1 + G4;
	local z1 = z0 - k1 + G4;
	local w1 = w0 - l1 + G4;
	local x2 = x0 - i2 + 2.0*G4; -- Offsets for third corner in (x,y,z,w) coords
	local y2 = y0 - j2 + 2.0*G4;
	local z2 = z0 - k2 + 2.0*G4;
	local w2 = w0 - l2 + 2.0*G4;
	local x3 = x0 - i3 + 3.0*G4; -- Offsets for fourth corner in (x,y,z,w) coords
	local y3 = y0 - j3 + 3.0*G4;
	local z3 = z0 - k3 + 3.0*G4;
	local w3 = w0 - l3 + 3.0*G4;
	local x4 = x0 - 1.0 + 4.0*G4; -- Offsets for last corner in (x,y,z,w) coords
	local y4 = y0 - 1.0 + 4.0*G4;
	local z4 = z0 - 1.0 + 4.0*G4;
	local w4 = w0 - 1.0 + 4.0*G4;
	
	-- Work out the hashed gradient indices of the five simplex corners
	local ii = bit.band(i , 255)
	local jj = bit.band(j , 255)
	local kk = bit.band(k , 255)
	local ll = bit.band(l , 255)
	local gi0 = perm[ii+perm[jj+perm[kk+perm[ll]]]] % 32;
	local gi1 = perm[ii+i1+perm[jj+j1+perm[kk+k1+perm[ll+l1]]]] % 32;
	local gi2 = perm[ii+i2+perm[jj+j2+perm[kk+k2+perm[ll+l2]]]] % 32;
	local gi3 = perm[ii+i3+perm[jj+j3+perm[kk+k3+perm[ll+l3]]]] % 32;
	local gi4 = perm[ii+1+perm[jj+1+perm[kk+1+perm[ll+1]]]] % 32;
	
	
	-- Calculate the contribution from the five corners
	local t0 = 0.5 - x0*x0 - y0*y0 - z0*z0 - w0*w0;
	if (t0<0) then
		n0 = 0.0;
	else
		t0 = t0*t0;
		n0 = t0 * t0 * Dot4D(Gradients4D[gi0], x0, y0, z0, w0);
	end
	
	local t1 = 0.5 - x1*x1 - y1*y1 - z1*z1 - w1*w1;
	if (t1<0) then
		n1 = 0.0;
	else 
		t1 = t1*t1;
		n1 = t1 * t1 * Dot4D(Gradients4D[gi1], x1, y1, z1, w1);
	end
	
	local t2 = 0.5 - x2*x2 - y2*y2 - z2*z2 - w2*w2;
	if (t2<0) then
		n2 = 0.0;
	else
		t2 = t2*t2;
		n2 = t2 * t2 * Dot4D(Gradients4D[gi2], x2, y2, z2, w2);
	end
	
	local t3 = 0.5 - x3*x3 - y3*y3 - z3*z3 - w3*w3;
	if (t3<0) then
		n3 = 0.0;
	else 
		t3 = t3*t3;
		n3 = t3 * t3 * Dot4D(Gradients4D[gi3], x3, y3, z3, w3);
	end
	
	local t4 = 0.5 - x4*x4 - y4*y4 - z4*z4 - w4*w4;
	if (t4<0) then
		n4 = 0.0;
	else
		t4 = t4*t4;
		n4 = t4 * t4 * Dot4D(Gradients4D[gi4], x4, y4, z4, w4);
	end
	
	-- Sum up and scale the result to cover the range [-1,1]
	
	local retval = 27.0 * (n0 + n1 + n2 + n3 + n4)
	
	if simplex.internalCache then
		if not Prev4D[x] then Prev4D[x] = {} end
		if not Prev4D[x][y] then Prev4D[x][y] = {} end
		if not Prev4D[x][y][z] then Prev4D[x][y][z] = {} end
		Prev4D[x][y][z][w] = retval
	end
	
	return retval;


end 

local e = 2.71828182845904523536

local PrevBlur2D = {}

function simplex.GBlur2D(x,y,stdDev)
	if simplex.internalCache and PrevBlur2D[x] and PrevBlur2D[x][y] and PrevBlur2D[x][y][stdDev] then return PrevBlur2D[x][y][stdDev] end
	local pwr = ((x^2+y^2)/(2*(stdDev^2)))*-1
	local ret = (1/(2*math.pi*(stdDev^2)))*(e^pwr)
	
	if simplex.internalCache then
		if not PrevBlur2D[x] then PrevBlur2D[x] = {} end
		if not PrevBlur2D[x][y] then PrevBlur2D[x][y] = {} end
		PrevBlur2D[x][y][stdDev] = ret
	end
	return ret
end 

local PrevBlur1D = {}

function simplex.GBlur1D(x,stdDev)
	if simplex.internalCache and PrevBlur1D[x] and PrevBlur1D[x][stdDev] then return PrevBlur1D[x][stdDev] end
	local pwr = (x^2/(2*stdDev^2))*-1
	local ret = (1/(math.sqrt(2*math.pi)*stdDev))*(e^pwr)

	if simplex.internalCache then
		if not PrevBlur1D[x] then PrevBlur1D[x] = {} end
		PrevBlur1D[x][stdDev] = ret
	end
	return ret
end

function simplex.FractalSum(func, iter, ...)
    local ret = func(...)
    for i=1,iter do
        local power = 2^iter
        local s = power/i
        
        local scaled = {}
        for elem in ipairs({...}) do
            table.insert(scaled, elem*s)
        end
        ret = ret + (i/power)*(func(unpack(scaled)))
    end
    return ret
end

function simplex.FractalSumAbs(func, iter, ...)
    local ret = math.abs(func(...))
    for i=1,iter do
        local power = 2^iter
        local s = power/i
        
        local scaled = {}
        for elem in ipairs({...}) do
            table.insert(scaled, elem*s)
        end
        ret = ret + (i/power)*(math.abs(func(unpack(scaled))))
    end
    return ret
end

function simplex.Turbulence(func, direction, iter, ...)
    local ret = math.abs(func(...))
    for i=1,iter do
        local power = 2^iter
        local s = power/i
        
        local scaled = {}
        for elem in ipairs({...}) do
            table.insert(scaled, elem*s)
        end
        ret = ret + (i/power)*(math.abs(func(unpack(scaled))))
    end
    local args = {...}
    local dir_component = args[direction+1]
    return math.sin(dir_component+ret)
end

--------------------------------------------------------------------------------

if test_only then
	for bi = 1, #benchmarks do
		local b = benchmarks[bi]
		if not specific_benchmark or specific_benchmark == b.name then
			local clear_fn, draw_fn, present_fn = b.create_functions(term.getSize())
			for _ = 1, 1 do clear_fn() end -- TODO
			draw_fn()
			present_fn()
			os.pullEvent 'key'
		end
	end
	return
end

--------------------------------------------------------------------------------

local results = {}

for i = 1, #sizes + 1 do
	results[i] = { { i == 1 and "Size" or ("%s (%dx%d)"):format(sizes[i - 1].name, sizes[i - 1].width, sizes[i - 1].height) } }
end

for i = 1, #benchmarks do
	if not specific_benchmark or specific_benchmark == benchmarks[i].name then
		table.insert(results[1], { benchmarks[i].name })
	end
end

for bi = 1, #benchmarks do
	for si = 1, #sizes do
		local s = sizes[si]
		local b = benchmarks[bi]

		if not specific_benchmark or specific_benchmark == b.name then
			local clear_fn, draw_fn, present_fn = b.create_functions(s.width, s.height)

			local it, ttd, ttp = benchmark(clear_fn, draw_fn, present_fn, b.warmup_iterations, b.min_iterations, b.min_duration)

			local fps = math.floor(it / (ttd + ttp) + 0.5)
			local us = math.floor((ttd + ttp) / it * 10000000 + 0.5) / 10
			local rd = math.floor(ttd / (ttd + ttp) * 100 + 0.5)

			table.insert(results[si + 1], { ("%4dfps (%5.0fus, %2d:%2d)"):format(fps, us, rd, 100 - rd) })
		end
	end
end

local rowMax = {}
local columnMax = {}

for i = 1, #results do
	local max = 0
	for j = 1, #results[i] do
		max = math.max(max, #results[i][j])
	end
	rowMax[i] = max
end

for j = 1, #results[1] do
	local max = 0
	for i = 1, #results do
		for l = 1, #results[i][j] do
			max = math.max(max, #results[i][j][l])
		end
	end
	columnMax[j] = max
end

for i = 1, #results do
	for j = 1, #results[i] do
		for l = 1, #results[i][j] do
			results[i][j][l] = (" "):rep(columnMax[j] - #results[i][j][l]) .. results[i][j][l]
		end
		for _ = #results[i][j] + 1, rowMax[i] do
			table.insert(results[i][j], 1, "")
		end
	end
end

term.setCursorPos(1, 1)
term.clear()
for i = 1, #results do
	for l = 1, #results[i][1] do
		local values = {}
		for j = 1, #results[i] do
			if j ~= 1 then
				table.insert(values, ' | ')
			end
			table.insert(values, results[i][j][l])
		end
		print(table.concat(values))
	end
end
