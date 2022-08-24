
local TextureFormat = require "lib.TextureFormat"
local libtexture = require "lib.texture"
local unique = require "lib.unique"

local viewport = {}

viewport.__type = unique "Viewport"

function viewport.create(texture)
	assert(type(texture) == "table" and texture.__type == libtexture.__type, "Expected texture")

	local vp = {
		__type = viewport.__type,
		dx = 0,
		dy = 0,
		di = 0,
		width = texture.width,
		height = texture.height,
	}

	return vp
end

return viewport
