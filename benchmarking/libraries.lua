
--- @class Library
--- @field name string
--- @field library any
--- @field setup_fn fun(library: any, shape: Shape, width: integer, height: integer): ClearFn, DrawFn, PresentFn

--- @alias Shape { triangles: integer, [integer]: ShapeTriangle }

--- @class ShapeTriangle
--- @field x0 number
--- @field y0 number
--- @field z0 number
--- @field x1 number
--- @field y1 number
--- @field z1 number
--- @field x2 number
--- @field y2 number
--- @field z2 number
--- @field colour integer

--- @alias ClearFn fun()
--- @alias DrawFn fun()
--- @alias PresentFn fun()

--- @type { [integer]: Library }
local libraries = {}

local oldPath = package.path
package.path = '/?.lua;/?/?.lua;' .. package.path

local function try_load_library(name, library, setup_fn)
	local ok, lib = pcall(require, library)
	if not ok then
		print('Failed to load ' .. library)
	end

	table.insert(libraries, {
		name = name,
		library = lib,
		setup_fn = setup_fn,
	})
end

--------------------------------------------------------------------------------

try_load_library('CCGL3D', 'ccgl3d', function(ccgl3d, model_data, width, height)
	local fb = ccgl3d.create_framebuffer_subpixel(width, height)
	local geom = ccgl3d.create_geometry()
	local camera = ccgl3d.create_perspective_camera()
	local ccgl3d_present = ccgl3d.present_framebuffer
	local ccgl3d_render = ccgl3d.render_geometry
	local aspect = 1

	camera.fov = 0.6
	camera.xRotation = 0.3
	camera.z = 15
	camera.y = 3

	for i = 1, model_data.triangles do
		local t = model_data[i]
		ccgl3d.add_triangle(geom, t.x0, t.y0, t.z0, t.x1, t.y1, t.z1, t.x2, t.y2, t.z2, t.colour)
	end

	local function clear_fn()
		ccgl3d.clear_framebuffer(fb, 1)
		-- ccgl3d.rotate_geometry_z(geom, 0.01)
	end

	local function draw_fn()
		ccgl3d_render(fb, geom, camera, aspect)
	end

	local function present_fn()
		ccgl3d_present(fb, term, 0, 0)
	end

	return clear_fn, draw_fn, present_fn
end)

try_load_library('Pine3D', 'Pine3D', function(Pine3D, model_data, width, height)
	local frame, objects
	local function clear_fn()
		objects = {}

		frame = Pine3D.newFrame(1, 1, width, height)
		frame:setBackgroundColor(1)
		frame:setFoV(100)

		frame.camera[1] = -15
		frame.camera[2] = 3
		frame.camera[3] = 0
		frame.camera[6] = -0.3

		local fullModel = {}

		for i = 1, model_data.triangles do
			local polygon = model_data[i]
			local r = {}
			r.x3 = -polygon.z2
			r.y3 = polygon.y2
			r.z3 = polygon.x2
			r.x2 = -polygon.z1
			r.y2 = polygon.y1
			r.z2 = polygon.x1
			r.x1 = -polygon.z0
			r.y1 = polygon.y0
			r.z1 = polygon.x0
			r.c = polygon.colour
			r.forceRender = true
			fullModel[#fullModel+1] = r
		end

		local object = frame:newObject(fullModel, 0, 0, 0) -- p2 replaced with 0
		table.insert(objects, object)
	end

	local function draw_fn()
		frame:drawObjects(objects)
	end

	local function present_fn()
		frame:drawBuffer(true)
	end

	return clear_fn, draw_fn, present_fn
end)

--------------------------------------------------------------------------------

package.path = oldPath

return libraries
