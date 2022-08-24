
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
		pixel_size = 1, -- updated later
	}

	local pixel_data

	if format == TextureFormat.Idx1 then
		pixel_data = { 15 }
	elseif format == TextureFormat.Col1 then
		pixel_data = { 2^15 }
	elseif format == TextureFormat.RGB1 then
		pixel_data = { 0, 0, 0 }
	elseif format == TextureFormat.Dpt1 then
		pixel_data = { math.huge }
	elseif format == TextureFormat.BFC1 then
		pixel_data = { -1, -1, "" }
	else
		error("Unknown format '" .. tostring(format) .. "'", 2)
	end

	tx.pixel_size = #pixel_data

	for i = 1, width * height * tx.pixel_size do
		tx[i] = pixel_data[(i - 1) % tx.pixel_size + 1]
	end

	return tx
end

function texture.createSubpixel(format, width, height)
	assert(type(width) == "number", "width not a number")
	assert(type(height) == "number", "height not a number")

	return texture.create(format, width * SUBPIXEL_WIDTH, height * SUBPIXEL_HEIGHT)
end

return texture
