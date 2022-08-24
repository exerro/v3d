
local unique = require "lib.unique"

local math_sqrt = math.sqrt

local fallback_table = {}

fallback_table.__type = unique "FallbackTable"

local function color_diff(r0, g0, b0, r1, g1, b1)
	local rd = r0 - r1
	local gd = g0 - g1
	local bd = b0 - b1

	return math_sqrt(rd * rd + gd * gd + bd * bd)
end

function fallback_table.create(term)
	local ft = {
		__type = fallback_table.__type,
	}

	for i = 0, 15 do
		local r0, g0, b0 = term.getPaletteColour(2 ^ i)
		local deltas = {}

		for j = 0, 15 do
			local r1, g1, b1 = term.getPaletteColour(2 ^ j)

			if i ~= j then
				deltas[#deltas + 1] = { j, color_diff(r0, g0, b0, r1, g1, b1) }
			end
		end

		table.sort(deltas, function(a, b) return a[2] < b[2] end)

		ft[i] = {}

		for j = 1, #deltas do
			ft[i][j] = deltas[j][1]
		end
	end

	return ft
end

return fallback_table
