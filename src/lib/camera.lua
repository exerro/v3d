
local unique = require "lib.unique"

local camera = {}

camera.__type = unique "Camera"
camera.Perspective = unique "Perspective"
camera.Orthogonal = unique "Orthogonal"

function camera.createPerspective(fov)
	assert(type(fov) == "number", "FOV not a number")
	return {
		__type = camera.__type,
		mode = camera.Perspective,
		fov = fov * math.pi / 180,
		x = 0,
		y = 0,
		z = 0,
		pan = 0,
		tilt = 0,
	}
end

return camera
