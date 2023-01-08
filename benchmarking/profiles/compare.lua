
local common = require 'common'
local libraries = require 'libraries'
local standard_models = require 'standard_models'

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

profile.chart_selectors = {}
profile.row_selectors = { 'screen_size', 'model', 'triangles' }
profile.column_selectors = { 'library', 'library_flags' }

function profile.chart_formatter()
	return "Model &lightGrey;(polys) /&white; dimensions"
end

function profile.row_formatter(rd)
	local fmt = "%s &lightGrey;(%4d) /&white; %3dx%2d"
	return fmt:format(rd.model.name, rd.triangles, rd.screen_size.width, rd.screen_size.height)
end

function profile.column_formatter(cd)
	return cd.library.name
end

function profile.chart_sorter(cd1, cd2)
	return false
end

function profile.row_sorter(rd1, rd2)
	local w1, h1 = rd1.screen_size.width, rd1.screen_size.height
	local w2, h2 = rd2.screen_size.width, rd2.screen_size.height
	local s1, s2 = w1 * h1 * h1, w2 * h2 * h2
	return rd1.triangles < rd2.triangles or rd1.triangles == rd2.triangles and s1 < s2
end

function profile.column_sorter(cd1, cd2)
	return cd1.library.name < cd2.library.name
end

--------------------------------------------------------------------------------

return profile
