
local ccgl3d = require "lib.ccgl3d"

print("Using CCGL3D v" .. ccgl3d.version)

local camera = ccgl3d.camera.createPerspective(30)
local texture = ccgl3d.texture.createSubpixel(ccgl3d.TextureFormat.Col1, 102, 38)
local viewport = ccgl3d.viewport.create(texture)
local fallback_table = ccgl3d.fallback_table.create(term)
local buffer = ccgl3d.buffer.create(ccgl3d.BufferFormat.Pos3Col1) {
	-- left
	-0.5, 0.5, 0.5,
	-0.5, 0.5, -0.5,
	-0.5, -0.5, -0.5,
	colours.pink,
	-0.5, 0.5, 0.5,
	-0.5, -0.5, -0.5,
	-0.5, -0.5, 0.5,
	colours.lightBlue,
	-- right
	0.5, 0.5, 0.5,
	0.5, -0.5, -0.5,
	0.5, 0.5, -0.5,
	colours.red,
	0.5, 0.5, 0.5,
	0.5, -0.5, 0.5,
	0.5, -0.5, -0.5,
	colours.orange,
	-- front
	-0.5, 0.5, 0.5,
	-0.5, -0.5, 0.5,
	0.5, -0.5, 0.5,
	colours.blue,
	-0.5, 0.5, 0.5,
	0.5, -0.5, 0.5,
	0.5, 0.5, 0.5,
	colours.cyan,
	-- back
	-0.5, 0.5, -0.5,
	0.5, -0.5, -0.5,
	-0.5, -0.5, -0.5,
	colours.yellow,
	-0.5, 0.5, -0.5,
	0.5, 0.5, -0.5,
	0.5, -0.5, -0.5,
	colours.brown,
	-- top
	0.5, 0.5, -0.5,
	-0.5, 0.5, -0.5,
	-0.5, 0.5, 0.5,
	colours.green,
	0.5, 0.5, -0.5,
	-0.5, 0.5, 0.5,
	0.5, 0.5, 0.5,
	colours.lime,
	-- bottom
	0.5, -0.5, -0.5,
	-0.5, -0.5, 0.5,
	-0.5, -0.5, -0.5,
	colours.purple,
	0.5, -0.5, -0.5,
	0.5, -0.5, 0.5,
	-0.5, -0.5, 0.5,
	colours.magenta,
}

local bc = #buffer
for i = 1, bc do
	for n = 1, 9 do
		buffer[bc * n + i] = buffer[i]
	end
end

buffer.size = #buffer

-- error(#buffer / 10)

local t0 = os.clock()
local count = 200

while true do
	local ft0 = os.clock()
	local t = ft0 - t0
	ccgl3d.render.clear(texture)
	ccgl3d.render.draw_triangles(buffer, texture, camera, viewport, {
		model_transform = ccgl3d.transform
			:translate_to(0, 0, -2)
			:rotate_x_to(t)
			:rotate_z_to(math.sin(t))
			:rotate_y_to(t * 2),
		-- model_transform = ccgl3d.transform:translate_to((i / count * 2) - 1, 0, -1),
		-- view_transform = ccgl3d.transform:translate_to(-1, 0, 0),
		cull_back_face = true,
	})

	local rt = os.clock() - ft0

	ccgl3d.blit(texture, term, fallback_table)

	local dt = os.clock() - ft0
	local bt = dt - rt

	term.setBackgroundColour(colours.black)
	term.setTextColour(colours.white)
	term.setCursorPos(1, 1)
	term.write("total: " .. math.floor(dt * 1000 + 0.5) .. "ms (" .. math.floor(1/dt) .. "fps)")
	term.setCursorPos(1, 2)
	term.write("blit:  " .. math.floor(bt * 1000 + 0.5) .. "ms (" .. math.floor(1/bt) .. "fps)")
	term.setCursorPos(1, 3)
	term.write("draw:  " .. math.floor(rt * 1000 + 0.5) .. "ms (" .. math.floor(1/rt) .. "fps)")

	local e = tostring {}
	sleep(0.05)
end

print("~" .. math.floor(count / (os.clock() - t0)) .. "fps")
