
local dir = fs.getDir(fs.getDir(shell.getRunningProgram()))

shell.run(dir .. '/build')
--- @type v3d
local v3d = require '/v3d'

local function assertEquals(expected, actual)
	if expected ~= actual then
		error('Assertion failed: ' .. textutils.serialize(actual) .. ' ~= expected ' .. textutils.serialize(expected), 2)
	end
end

--------------------------------------------------------------------------------
--[[ Layouts ]]-----------------------------------------------------------------
--------------------------------------------------------------------------------

local layout = v3d.create_layout()

layout = layout:add_face_attribute('a', 2)
assertEquals(true, layout:has_attribute 'a')
assertEquals('a', layout:get_attribute 'a' .name)
assertEquals(2, layout:get_attribute 'a' .size)
assertEquals('face', layout:get_attribute 'a' .type)
assertEquals(false, layout:get_attribute 'a' .is_numeric)
assertEquals(0, layout:get_attribute 'a' .offset)
assertEquals(0, layout.vertex_stride)
assertEquals(2, layout.face_stride)
assertEquals(layout:get_attribute 'a', layout.attributes[1])

layout = layout:add_face_attribute('b', 3)
assertEquals(true, layout:has_attribute 'b')
assertEquals('b', layout:get_attribute 'b' .name)
assertEquals(3, layout:get_attribute 'b' .size)
assertEquals('face', layout:get_attribute 'b' .type)
assertEquals(false, layout:get_attribute 'b' .is_numeric)
assertEquals(2, layout:get_attribute 'b' .offset)
assertEquals(0, layout.vertex_stride)
assertEquals(5, layout.face_stride)
assertEquals(layout:get_attribute 'b', layout.attributes[2])

layout = layout:add_vertex_attribute('c', 4, true)
assertEquals(true, layout:has_attribute 'c')
assertEquals('c', layout:get_attribute 'c' .name)
assertEquals(4, layout:get_attribute 'c' .size)
assertEquals('vertex', layout:get_attribute 'c' .type)
assertEquals(true, layout:get_attribute 'c' .is_numeric)
assertEquals(0, layout:get_attribute 'c' .offset)
assertEquals(4, layout.vertex_stride)
assertEquals(5, layout.face_stride)
assertEquals(layout:get_attribute 'c', layout.attributes[3])

--------------------------------------------------------------------------------
--[[ Geometry ]]----------------------------------------------------------------
--------------------------------------------------------------------------------

local layout = v3d.create_layout()
	:add_vertex_attribute('position', 3, true)
	:add_vertex_attribute('uv', 2, true)
	:add_face_attribute('colour', 1)
	:add_face_attribute('object_name', 1)

local gb = v3d.create_geometry_builder(layout)

gb:set_data('position', { 1, 2, 3, 4, 5, 6, 7, 8, 9 })
gb:set_data('uv', { 11, 12, 14, 15, 17, 18 })
gb:set_data('colour', { 64, 128 })
gb:set_data('object_name', { 'a', 'b' })

local geometry = gb:build()
local expected_data = { 64, 'a', 128, 'b', 1, 2, 3, 11, 12, 4, 5, 6, 14, 15, 7, 8, 9, 17, 18 }

for i = 1, #expected_data do
	assertEquals(expected_data[i], geometry[i])
end

assertEquals(layout, geometry.layout)
assertEquals(3, geometry.vertices)
assertEquals(2, geometry.faces)
assertEquals(4, geometry.vertex_offset)

-- map
-- insert
-- cast
