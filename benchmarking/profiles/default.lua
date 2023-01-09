
local common = require 'common'
local libraries = require 'libraries'
local standard_models = require 'standard_models'

--- @type Profile
local profile = {}

--------------------------------------------------------------------------------

profile.uses_screen_size = true

----------------------------------------------------------------

profile.benchmark_options = common.create_dataset()

profile.benchmark_options:add_datapoint {}
profile.benchmark_options:add_permutation('model', standard_models)

for i = 1, #standard_models do
	profile.benchmark_options:add_permutation('model_detail', standard_models[i].default_details,
		function(o) return o.model.id == standard_models[i].id end)
end

profile.benchmark_options:add_permutation('library', libraries)
profile.benchmark_options:add_permutation('library_flags', { {} })

----------------------------------------------------------------

profile.chart_selectors = { 'library', 'library_flags' }
profile.row_selectors = { 'screen_size' }
profile.column_selectors = { 'model', 'triangles' }

function profile.chart_formatter(cd)
	local title = cd.library.name

	for k, v in pairs(cd.library_flags) do
		title = title .. "\n" .. k .. ": " .. tostring(v)
	end

	return title
end

function profile.row_formatter(rd)
	return rd.screen_size.width .. 'x' .. rd.screen_size.height
end

function profile.column_formatter(cd)
	return cd.model.name .. " (" .. cd.triangles .. ")"
end

function profile.chart_sorter(cd1, cd2)
	return cd1.library.name < cd2.library.name
end

function profile.row_sorter(rd1, rd2)
	local w1, h1 = rd1.screen_size.width, rd1.screen_size.height
	local w2, h2 = rd2.screen_size.width, rd2.screen_size.height
	return w1 * h1 * h1 < w2 * h2 * h2
end

function profile.column_sorter(cd1, cd2)
	return cd1.triangles < cd2.triangles
end

--------------------------------------------------------------------------------

return profile
