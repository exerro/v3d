
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
--[[ Framebuffers ]]------------------------------------------------------------
--------------------------------------------------------------------------------

local fb = v3d.create_framebuffer(5, 3)

assertEquals(5, fb.width)
assertEquals(3, fb.height)
assertEquals(15, #fb.colour)
assertEquals(15, #fb.depth)

for i = 1, 15 do
	assertEquals(1, fb.colour[i])
	assertEquals(0, fb.depth[i])
end

fb:clear()

for i = 1, 15 do
	assertEquals(1, fb.colour[i])
	assertEquals(0, fb.depth[i])
end

fb:clear(2)

for i = 1, 15 do
	assertEquals(2, fb.colour[i])
	assertEquals(0, fb.depth[i])
end

fb:clear_depth(0.5)

for i = 1, 15 do
	assertEquals(2, fb.colour[i])
	assertEquals(0.5, fb.depth[i])
end

fb:clear(4, false)

for i = 1, 15 do
	assertEquals(4, fb.colour[i])
	assertEquals(0.5, fb.depth[i])
end

fb:clear(8, true)

for i = 1, 15 do
	assertEquals(8, fb.colour[i])
	assertEquals(0, fb.depth[i])
end

local fb2 = v3d.create_framebuffer_subpixel(2, 2)

assertEquals(4, fb2.width)
assertEquals(6, fb2.height)

-- (1, 0) all orange
fb2.colour[3] = 2
fb2.colour[4] = 2
fb2.colour[7] = 2
fb2.colour[8] = 2
fb2.colour[11] = 2
fb2.colour[12] = 2
-- (0, 1) mixed two colours
fb2.colour[13] = 4
fb2.colour[14] = 8
fb2.colour[17] = 8
fb2.colour[18] = 4
fb2.colour[21] = 4
fb2.colour[22] = 8
-- (1, 1) mixed 3 colours  abcdcc
fb2.colour[15] = 16
fb2.colour[16] = 32
fb2.colour[19] = 64
fb2.colour[20] = 128
fb2.colour[23] = 128
fb2.colour[24] = 128

local actions = {
	{ 'setCursorPos', 2, 3 },
	{ 'blit', string.char(32, 32), '00', '01' },
	{ 'setCursorPos', 2, 4 },
	{ 'blit', string.char(153, 135), '26', '37' },
}

local fake_term = setmetatable({}, {
	__index = function(_, fn_name)
		return function(...)
			local expected = table.remove(actions, 1)
			local params = { ... }
			assertEquals(expected[1], fn_name)
			assertEquals(#expected - 1, #params)

			for i = 1, #params do
				assertEquals(expected[i + 1], params[i])
			end
		end
	end
})

fb2:blit_subpixel(fake_term, 1, 2)
fb2:blit_subpixel(term)

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
