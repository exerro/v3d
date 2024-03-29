
--- @module 'src.v3d'

--- @class Library
--- @field id string
--- @field name string
--- @field library any
--- @field setup_fn fun(library: any, shape: Shape, width: integer, height: integer, flags: table): ClearFn, DrawFn, PresentFn

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

--- @type { [integer]: Library, [string]: Library }
local libraries = {}

local oldPath = package.path
package.path = '/?.lua;/?/?.lua;' .. package.path

local function try_load_library(name, library, setup_fn)
	local ok, lib = pcall(require, library)
	if not ok then
		print('Warning: Failed to load ' .. library)
		return
	end
	local l = {
		id = library,
		name = name,
		library = lib,
		setup_fn = setup_fn,
	}

	table.insert(libraries, l)
	libraries[l.id] = l
end

--------------------------------------------------------------------------------

local SETTING_CAMERA_X = 6
local SETTING_CAMERA_Y = 4
local SETTING_CAMERA_Z = 12
local SETTING_CAMERA_H_FOV = math.pi / 4
local SETTING_CAMERA_X_ROTATION = math.pi / 6
local SETTING_CAMERA_Y_ROTATION = math.pi / 6

--------------------------------------------------------------------------------

--- @param v3d v3d
try_load_library('V3D', 'v3d', function(v3d, model_data, width, height, flags)
	local fb = v3d.create_framebuffer_subpixel(v3d.COLOUR_DEPTH_LAYOUT, width, height)
	local gb = v3d.create_geometry_builder(v3d.DEFAULT_FORMAT)
	local transform = v3d.camera()
	local pipeline = v3d.create_pipeline {
		layout = v3d.DEFAULT_FORMAT,
		colour_attribute = not flags.fragment_shader and 'colour' or nil,
		cull_face = flags.cull_face == nil and v3d.CULL_BACK_FACE or flags.cull_face,
		depth_test = flags.depth_test,
		depth_store = flags.depth_test,
		attributes = flags.fragment_shader and { 'position' } or nil,
		pack_attributes = false,
		fragment_shader = flags.fragment_shader and function(_, x, y, z)
			if y > 0 then
				return nil
			end
			local idx = math.floor(x) % 4 * 4 + (math.floor(z) + math.floor(y)) % 4
			return 2 ^ idx
		end,
		statistics = flags.statistics and {
			measure_total_time = true,
			measure_rasterize_time = true,
			count_candidate_faces = true,
			count_drawn_faces = true,
			count_culled_faces = true,
			count_clipped_faces = true,
			count_discarded_faces = true,
			count_candidate_fragments = true,
			count_fragments_occluded = true,
			count_fragments_shaded = true,
			count_fragments_discarded = true,
			count_fragments_drawn = true,
		} or nil,
	}
	local v3d_present = fb.blit_term_subpixel
	local v3d_render = pipeline.render_geometry
	local aspect = fb.width / fb.height

	if flags.front_facing then
		transform = v3d.camera(0, 0, 0, 0, 0, 0, math.tan(SETTING_CAMERA_H_FOV) / aspect * 2)
	else
		transform = v3d.camera(SETTING_CAMERA_X, SETTING_CAMERA_Y, SETTING_CAMERA_Z, SETTING_CAMERA_X_ROTATION, SETTING_CAMERA_Y_ROTATION, 0, math.tan(SETTING_CAMERA_H_FOV) / aspect * 2)
	end

	for i = 1, model_data.triangles do
		local t = model_data[i]
		gb:append_data('position', { t.x0, t.y0, t.z0, t.x1, t.y1, t.z1, t.x2, t.y2, t.z2 })
		gb:append_data('colour', { t.colour })
	end

	local geom = gb:build()

	local function clear_fn()
		fb:clear('colour', 1)
		-- geom:rotate_z(0.01)
	end

	local function draw_fn()
		return v3d_render(pipeline, geom, fb, transform)
	end

	local function present_fn()
		return v3d_present(fb, term.current(), 'colour', 0, 0)
	end

	return clear_fn, draw_fn, present_fn
end)

try_load_library('Pine3D', 'Pine3D', function(Pine3D, model_data, width, height)
	local frame, objects
	local function clear_fn()
		objects = {}

		frame = Pine3D.newFrame(1, 1, width, height)
		frame:setBackgroundColor(1)
		frame:setFoV(SETTING_CAMERA_H_FOV * 180 / math.pi * 2)

		frame.camera[6] = -SETTING_CAMERA_X_ROTATION
		frame.camera[5] = -SETTING_CAMERA_Y_ROTATION
		frame.camera[3] = SETTING_CAMERA_X
		frame.camera[2] = SETTING_CAMERA_Y
		frame.camera[1] = -SETTING_CAMERA_Z

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
