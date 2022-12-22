
--- @class Profile
--- @field warmup_iterations integer
--- @field min_iterations integer
--- @field min_duration integer
--- @field include_libraries { [integer]: string } | nil
--- @field include_models { [integer]: string } | nil
--- @field model_parameters { [string]: { [string]: { [integer]: any } } } | nil
--- @field min_width integer | nil
--- @field max_width integer | nil
--- @field min_height integer | nil
--- @field max_height integer | nil
--- @field min_pixels integer | nil
--- @field max_pixels integer | nil
--- @field post_run function | nil
--- @field suppress_present boolean | nil
--- @field flags table | nil
--- @field get_charts fun(): { [integer]: ChartOptions }

--- @type { [integer]: Profile }
local profiles = {}

--------------------------------------------------------------------------------

--- @param t ChartOptions
--- @return ChartOptions
local function default_options(t)
	t.aggregate = t.aggregate or function(t)
		local n = #t
		local r = { iterations = n, draw_time = 0, present_time = 0, total_time = 0, fps = 0 }

		for i = 1, n do
			r.draw_time = r.draw_time + t[i].draw_time / n
			r.present_time = r.present_time + t[i].present_time / n
		end

		r.total_time = r.draw_time + r.present_time
		r.fps = 1 / r.total_time
		r.triangles = t[1].triangles

		return r
	end
	t.column_key = t.column_key or 'model_triangles'
	t.column_sorter = t.column_sorter or function(a, b)
		return a.triangles < b.triangles
	end
	t.row_key = t.row_key or 'screen_size'
	t.row_key_writer = t.row_key_writer or function (screen_size)
		return screen_size.name .. ' (' .. screen_size.width .. 'x' .. screen_size.height .. ')'
	end
	t.row_sorter = t.row_sorter or function(a, b)
		return a.fps > b.fps
	end
	return t
end

--------------------------------------------------------------------------------

profiles.ccgl_test = {
	warmup_iterations = 0,
	min_iterations = 1,
	min_duration = 0,
	include_libraries = { 'ccgl3d' },
	include_models = { 'box' },
	min_pixels = 100*50,
	max_pixels = 100*50,
	flags = { depth_test = true },
	get_charts = function() return {} end,
	post_run = function() os.pullEvent 'mouse_click' end,
}

--------------------------------------------------------------------------------

profiles.p3d_test = {
	warmup_iterations = 0,
	min_iterations = 1,
	min_duration = 0,
	include_libraries = { 'Pine3D' },
	include_models = { 'box' },
	min_pixels = 100*50,
	max_pixels = 100*50,
	flags = { depth_test = true },
	get_charts = function() return {} end,
	post_run = function() os.pullEvent 'mouse_click' end,
}

--------------------------------------------------------------------------------

profiles.ccgl_fps_fast = {
	warmup_iterations = 20,
	min_iterations = 50,
	min_duration = 0.5,
	include_libraries = { 'ccgl3d' },
	include_models = nil,
	min_pixels = 10,
	max_pixels = 5000,
	flags = { depth_test = true },
	get_charts = function()
		return { default_options {
			title = "CCGL3D Quick FPS",
			value_keys = { 'fps', 'draw_time', 'present_time', 'ratio' },
			value_format = '%4d fps (%2.1fms %2.1fms %s)',
			value_writers = {
				draw_time = function(t)
					return t * 1000
				end,
				present_time = function(t)
					return t * 1000
				end,
				ratio = function(_, dp)
					local dpd = dp.draw_time / dp.total_time
					dpd = math.floor(dpd * 100 + 0.5)
					return string.format('%2d%%', dpd)
				end,
			},
		} }
	end
}

--------------------------------------------------------------------------------

profiles.ccgl = {
	warmup_iterations = 40,
	min_iterations = 50,
	min_duration = 0.5,
	include_libraries = { 'ccgl3d' },
	include_models = nil,
	model_parameters = {
		box = {
			count = { 4, 16, 32 }
		},
		noise = {
			resolution = { 4, 16, 32 }
		},
	},
	min_pixels = 51,
	max_pixels = 13000,
	flags = { depth_test = true },
	get_charts = function()
		return { default_options {
			title = "CCGL3D Benchmark",
			value_keys = { 'fps', 'draw_time', 'present_time', 'ratio' },
			value_format = '%4d fps (%2.1fms %2.1fms %s)',
			value_writers = {
				draw_time = function(t)
					return t * 1000
				end,
				present_time = function(t)
					return t * 1000
				end,
				ratio = function(_, dp)
					local dpd = dp.draw_time / dp.total_time
					dpd = math.floor(dpd * 100 + 0.5)
					return string.format('%2d%%', dpd)
				end,
			},
		} }
	end
}

--------------------------------------------------------------------------------

profiles.quick_compare = {
	warmup_iterations = 30,
	min_iterations = 80,
	min_duration = 0.6,
	include_libraries = nil,
	include_models = nil,
	min_width = 20,
	min_height = 10,
	max_width = 200,
	max_height = 80,
	flags = { depth_test = true },
	get_charts = function()
		local options = {}

		for _, library_name in ipairs { 'CCGL3D', 'Pine3D' } do
			table.insert(options, default_options {
				title = library_name,
				filter = function(dp)
					return dp.library.name == library_name
				end,
				value_keys = { 'fps' },
				value_format = '%3d fps',
			})
		end

		return options
	end
}

--------------------------------------------------------------------------------

profiles.complete_render = {
	warmup_iterations = 50,
	min_iterations = 30,
	min_duration = 0.5,
	include_libraries = nil,
	include_models = nil,
	model_parameters = {
		box = {
			count = { 4, 32 }
		},
		noise = {
			resolution = { 4, 32 }
		},
	},
	suppress_present = true,
	flags = { depth_test = true },
	get_charts = function()
		local options = {}

		for _, library_name in ipairs { 'CCGL3D', 'Pine3D' } do
			table.insert(options, default_options {
				title = library_name,
				filter = function(dp)
					return dp.library.name == library_name
				end,
				value_keys = { 'fps', 'draw_time' },
				value_format = '%4d fps (%2.02fms)',
				value_writers = {
					fps = function(_, dp)
						return 1 / dp.draw_time
					end,
					draw_time = function(t)
						return t * 1000
					end,
				},
			})
		end

		return options
	end,
}

--------------------------------------------------------------------------------

profiles.complete_all = {
	warmup_iterations = 50,
	min_iterations = 30,
	min_duration = 0.5,
	include_libraries = nil,
	include_models = nil,
	model_parameters = {
		box = {
			count = { 4, 16, 32 }
		},
		noise = {
			resolution = { 4, 16, 32 }
		},
	},
	flags = { depth_test = true },
	get_charts = function()
		local options = {}

		for _, library_name in ipairs { 'CCGL3D', 'Pine3D' } do
			table.insert(options, default_options {
				title = library_name,
				filter = function(dp)
					return dp.library.name == library_name
				end,
				value_keys = { 'fps', 'draw_time', 'present_time', 'ratio' },
				value_format = '%4d fps (%2.1fms %2.1fms %s)',
				value_writers = {
					draw_time = function(t)
						return t * 1000
					end,
					present_time = function(t)
						return t * 1000
					end,
					ratio = function(_, dp)
						local dpd = dp.draw_time / dp.total_time
						dpd = math.floor(dpd * 100 + 0.5)
						return string.format('%2d%%', dpd)
					end,
				},
			})
		end

		return options
	end,
}

--------------------------------------------------------------------------------

return profiles
