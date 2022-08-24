
local TextureFormat = require "lib.TextureFormat"
local unique = require "lib.unique"

local texture = {}

local SUBPIXEL_WIDTH = 2
local SUBPIXEL_HEIGHT = 3

texture.__type = unique "Texture"

function texture.create(format, width, height)
	assert(type(width) == "number", "width not a number")
	assert(type(height) == "number", "height not a number")

	local tx = {
		__type = texture.__type,
		format = format,
		size = width * height,
		width = width,
		height = height,
		pixel_size = 1,
	}

	if format == TextureFormat.Idx1 then
		tx.pixel_size = 1
	elseif format == TextureFormat.Rgb1 then
		tx.pixel_size = 3
	elseif format == TextureFormat.Dpt1 then
		tx.pixel_size = 1
	end

	for i = 1, width * height * tx.pixel_size do
		tx[i] = 0
	end

	return tx
end

function texture.createSubpixel(format, width, height)
	assert(type(width) == "number", "width not a number")
	assert(type(height) == "number", "height not a number")

	return texture.create(format, width * SUBPIXEL_WIDTH, height * SUBPIXEL_HEIGHT)
end

return texture
