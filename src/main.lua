
local ccgl3d = require "lib.ccgl3d"

print("Using CCGL3D v" .. ccgl3d.version)

local w, h = term.getSize()
local camera = ccgl3d.camera.createPerspective(30)
local dirty_texture = ccgl3d.texture.create(ccgl3d.TextureFormat.BFC1, w, h)
local texture = ccgl3d.texture.createSubpixel(ccgl3d.TextureFormat.Col1, w, h)
local viewport = ccgl3d.viewport.create(texture)
local fallback_table = ccgl3d.fallback_table.create(term)
local buffer = ccgl3d.buffer.create(ccgl3d.BufferFormat.Pos3Col1) {
	-- left
	-0.5, 0.5, 0.5,
	-0.5, 0.5, -0.5,
	-0.5, -0.5, -0.5,
	colours.lightBlue,
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
	colours.red,
	-- front
	-0.5, 0.5, 0.5,
	-0.5, -0.5, 0.5,
	0.5, -0.5, 0.5,
	colours.blue,
	-0.5, 0.5, 0.5,
	0.5, -0.5, 0.5,
	0.5, 0.5, 0.5,
	colours.blue,
	-- back
	-0.5, 0.5, -0.5,
	0.5, -0.5, -0.5,
	-0.5, -0.5, -0.5,
	colours.yellow,
	-0.5, 0.5, -0.5,
	0.5, 0.5, -0.5,
	0.5, -0.5, -0.5,
	colours.yellow,
	-- top
	0.5, 0.5, -0.5,
	-0.5, 0.5, -0.5,
	-0.5, 0.5, 0.5,
	colours.green,
	0.5, 0.5, -0.5,
	-0.5, 0.5, 0.5,
	0.5, 0.5, 0.5,
	colours.green,
	-- bottom
	0.5, -0.5, -0.5,
	-0.5, -0.5, 0.5,
	-0.5, -0.5, -0.5,
	colours.magenta,
	0.5, -0.5, -0.5,
	0.5, -0.5, 0.5,
	-0.5, -0.5, 0.5,
	colours.magenta,
}

-- local bc = #buffer
-- for i = 1, bc do
-- 	for n = 1, 9 do
-- 		buffer[bc * n + i] = buffer[i]
-- 	end
-- end

-- buffer.size = #buffer

-- error(#buffer / 10)

local t0 = os.clock()
local count = 200

while true do
	local ft0 = os.clock()
	local t = ft0 - t0
	local model_draws = 0
	ccgl3d.render.clear(texture)

	for z = -1, 0 do
		for y = -1, 1, 0.5 do
			for x = -2, 2, 0.5 do
				ccgl3d.render.draw_triangles(buffer, texture, camera, viewport, {
					model_transform = ccgl3d.transform
						-- :translate_to(x, y, z - 2)
						:translate_to(0, 0, -2)
						:rotate_x_to(t + x * 2)
						:rotate_z_to(math.sin(t + y * 2))
						:rotate_y_to(t * 2 + z * 2)
						:scale_to(0.75, 0.75, 0.75),
						-- :scale_to(0.25, 0.25, 0.25),
					-- model_transform = ccgl3d.transform:translate_to((i / count * 2) - 1, 0, -1),
					-- view_transform = ccgl3d.transform:translate_to(-1, 0, 0),
					-- cull_back_face = true,
				})
				model_draws = model_draws + 1
			end
		end
	end

	local rt = os.clock() - ft0

	-- term.setBackgroundColour(colours.black)
	-- term.clear()
	-- ccgl3d.blit(texture, term, fallback_table)
	ccgl3d.blit(texture, term, fallback_table, dirty_texture)

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
	term.setCursorPos(1, 4)
	term.write("load:  " .. model_draws .. " models, " .. buffer.size / 10 * model_draws .. " triangles")
	term.setCursorPos(1, 5)
	term.write("size:  (" .. w .. ", " .. h .. ") terminal, (" .. texture.width .. ", " .. texture.height .. ") texture")

	local e = tostring {}
	sleep(0.05)
end

print("~" .. math.floor(count / (os.clock() - t0)) .. "fps")
