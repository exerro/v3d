
--- @class Options: { [integer]: table }
local Options = {}

--- @alias Datapoint { [string]: unknown }

--- @class Dataset: { [integer]: Datapoint }
local Dataset = {}

--- @class Chart
--- @field cells { [integer]: { [integer]: string } }
local Chart = {}

--- @alias ChartOptions2<R, C> { title: string, rows: R[], columns: C[], format_row: (fun(row: R): string), format_column: (fun(column: C): string), format_cell: (fun(row: R, column: C): string) }

--- @class ChartPrintOptions
--- @field x_offset integer | nil
--- @field y_offset integer | nil
--- @field active_row integer | nil
--- @field active_column integer | nil
--- @field background_colour integer
--- @field alternate_background_colour integer | nil
--- @field active_background_colour integer | nil
--- @field alternate_active_background_colour integer | nil
--- @field active_cell_background_colour integer | nil
--- @field alternate_active_cell_background_colour integer | nil
--- @field text_colour integer
--- @field alternate_text_colour integer | nil
--- @field separator string | nil
--- @field separator_colour integer | nil
--- @field alternate_separator_colour integer | nil

local common = {}

--------------------------------------------------------------------------------

--- @param t table
--- @return table
local function copy(t)
	local r = {}
	for k, v in pairs(t) do
		r[k] = v
	end
	return r
end

--------------------------------------------------------------------------------

--- @param self Options
--- @param name string
--- @param values unknown[]
--- @param filter (fun(option: table): boolean) | nil
--- @return Options
function Options:add_option(name, values, filter)
	local new_results = {}

	for i = 1, #self do
		if filter and not filter(self[i]) then
			table.insert(new_results, self[i])
		else
			for j = 1, #values do
				local t = copy(self[i])
				t[name] = values[j]
				table.insert(new_results, t)
			end
		end
	end

	for i = 1, #new_results do
		self[i] = new_results[i]
	end

	for i = #self, #new_results + 1, -1 do
		self[i] = nil
	end

	return self
end

--- @return Options
function common.create_options()
	--- @type Options
	local o = { {} }
	o.add_option = Options.add_option
	return o
end

--------------------------------------------------------------------------------

--- Add a datapoint to this dataset and return the dataset. Does not make a copy
--- of this dataset.
--- @param datapoint Datapoint
--- @return Dataset
function Dataset:add_datapoint(datapoint)
	table.insert(self, datapoint)
	return self
end

--- Return a copy of this dataset with only datapoints matching the given
--- `predicate`
--- @param predicate fun(datapoint: Datapoint): boolean
--- @return Dataset
function Dataset:filter(predicate)
	local ds = common.create_dataset()

	for i = 1, #self do
		if predicate(self[i]) then
			ds:add_datapoint(self[i])
		end
	end

	return ds
end

--- @param reducer fun(a: Datapoint, b: Datapoint, n: integer, i: integer): Datapoint
--- @param v0 Datapoint | nil
--- @return Datapoint
function Dataset:reduce(reducer, v0)
	local r = v0 or self[1]

	for i = v0 and 1 or 2, #self do
		r = reducer(r, self[i], #self, i)
	end

	return r
end

--- @param key string
--- @return unknown[]
function Dataset:distinct(key)
	local lookup = {}
	local r = {}

	for i = 1, #self do
		local v = self[i][key]
		if not lookup[v] then
			lookup[v] = true
			table.insert(r, v)
		end
	end

	return r
end

--- @return Dataset
function common.create_dataset()
	--- @type Dataset
	local dataset = {}
	dataset.add_datapoint = Dataset.add_datapoint
	dataset.filter = Dataset.filter
	dataset.reduce = Dataset.reduce
	dataset.distinct = Dataset.distinct
	return dataset
end

--------------------------------------------------------------------------------

--- @param s string
--- @return string
local function strip_colours(s)
	for k in pairs(colours) do
		s = s:gsub("&" .. k .. ";", "")
	end

	return s
end

--- @param cells { [integer]: { [integer]: string } }
--- @return { [integer]: integer }, { [integer]: integer }
local function calculate_padding(cells)
	local raw_cells = {}
	local column_lengths = {}
	local row_heights = {}

	for i = 1, #cells do
		raw_cells[i] = {}
		for j = 1, #cells[i] do
			raw_cells[i][j] = strip_colours(cells[i][j])
		end
	end

	for i = 1, #raw_cells do
		local max = 1

		for j = 1, #raw_cells[i] do
			local lines = select(2, raw_cells[i][j]:gsub("\n", "")) + 1
			max = math.max(max, lines)
		end

		row_heights[i] = max
	end

	for j = 1, #raw_cells[1] do
		local max = 0

		for i = 1, #raw_cells do
			for line in raw_cells[i][j]:gmatch "[^\n]*" do
				max = math.max(max, #line)
			end
		end

		column_lengths[j] = max
	end

	return row_heights, column_lengths
end

--- @param padding integer
--- @param cell_line string
--- @return function[]
local function cell_to_actions(padding, cell_line, background_colour, text_colour)
	local actions = {}
	local space = (" "):rep(padding - #strip_colours(cell_line) + 1)

	table.insert(actions, function()
		term.setBackgroundColour(background_colour)
		term.setTextColour(text_colour)
		term.write(space)
	end)

	local i = 1

	while i <= #cell_line do
		local s, f = cell_line:find("&%w+;", i)

		if not s then
			break
		end

		local colour = cell_line:sub(s + 1, f - 1)
		local ii = i

		table.insert(actions, function()
			term.write(cell_line:sub(ii, s - 1))
			term.setTextColour(colours[colour])
		end)

		i = f + 1
	end

	if i <= #cell_line then
		table.insert(actions, function()
			term.write(cell_line:sub(i))
		end)
	end

	table.insert(actions, function()
		term.write " "
	end)

	return actions
end

--- @param options ChartPrintOptions
function Chart:pretty_print(options)
	local active_row = options.active_row
	local active_column = options.active_column
	local background_colour = options.background_colour
	local alternate_background_colour = options.alternate_background_colour or background_colour
	local active_background_colour = options.active_background_colour or background_colour
	local alternate_active_background_colour = options.alternate_active_background_colour or active_background_colour
	local active_cell_background_colour = options.active_cell_background_colour or active_background_colour
	local alternate_active_cell_background_colour = options.alternate_active_cell_background_colour or active_cell_background_colour
	local text_colour = options.text_colour
	local alternate_text_colour = options.alternate_text_colour or text_colour
	local separator = options.separator or '|'
	local separator_colour = options.separator_colour or text_colour
	local alternate_separator_colour = options.alternate_separator_colour or separator_colour

	local row_heights, column_lengths = calculate_padding(self.cells)
	local row_actions = {}

	for i = 1, #self.cells do
		local this_row_actions = {}
		local row_is_active = active_row == i
		local is_alternate_row = i % 2 == 1

		for r = 1, row_heights[i] do
			this_row_actions[r] = {}
		end

		for j = 1, #self.cells[i] do
			local lines = {}
			local column_is_active = active_column == i

			if j ~= 1 then
				for r = 1, row_heights[i] do
					table.insert(this_row_actions[r], function()
						term.setTextColour(is_alternate_row and alternate_separator_colour or separator_colour)
						term.write(separator)
					end)
				end
			end

			for line in self.cells[i][j]:gmatch "[^\n]*" do
				table.insert(lines, line)
			end

			for r = 1, #lines do
				local any_active = row_is_active or column_is_active
				local all_active = row_is_active and column_is_active
				local cell_background_colour =
					all_active and (is_alternate_row and alternate_active_cell_background_colour or active_cell_background_colour) or
					any_active and (is_alternate_row and alternate_active_background_colour or active_background_colour)
					or (is_alternate_row and alternate_background_colour or background_colour)
				local cell_text_colour = is_alternate_row and alternate_text_colour or text_colour

				local actions = cell_to_actions(column_lengths[j], lines[r], cell_background_colour, cell_text_colour)
				for m = 1, #actions do
					table.insert(this_row_actions[r], actions[m])
				end
			end

			for r = #lines + 1, row_heights[i] do
				table.insert(this_row_actions[r], function()
					term.write((" "):rep(column_lengths[j]))
				end)
			end
		end

		for r = 1, row_heights[i] do
			table.insert(row_actions, this_row_actions[r])
		end
	end

	for i = 1, #row_actions do
		term.setCursorPos(1 + (options.x_offset or 0), i + (options.y_offset or 0))
		for j = 1, #row_actions[i] do
			row_actions[i][j]()
		end
	end
end

--- @generic R
--- @generic C
--- @param options ChartOptions2<R, C>
--- @return Chart
function common.create_chart(options)
	local chart = {}

	chart.cells = {}
	chart.cells[1] = {}
	chart.cells[1][1] = options.title

	for i = 1, #options.rows do
		chart.cells[i + 1] = { options.format_row(options.rows[i]) }
	end

	for j = 1, #options.columns do
		chart.cells[1][j + 1] = options.format_column(options.columns[j])
	end

	for i = 1, #options.rows do
		for j = 1, #options.columns do
			chart.cells[i + 1][j + 1] = options.format_cell(options.rows[i], options.columns[j])
		end
	end

	chart.pretty_print = Chart.pretty_print

	return chart
end

local data = common.create_dataset()

for i = 1, 4 do
	for j = 5, 7 do
		data:add_datapoint { x = i, y = j, value = i * i + j }
	end
end

local chart = common.create_chart {
	title = '&green;hello',
	rows = data:distinct 'y',
	columns = data:distinct 'x',
	format_row = function(r) return '&orange;r' .. r end,
	format_column = function(c) return '&cyan;c' .. c end,
	format_cell = function(r, c)
		local v = data:filter(function(it)
			return it.y == r and it.x == c
		end):reduce(function(a, b)
			return { value = a.value + b.value }
		end)

		return '&red;r' .. r .. '&blue;c' .. c .. "&white;: " .. v.value
	end,
}

chart:pretty_print {
	background_colour = colours.grey,
	alternate_background_colour = colours.black,
	text_colour = colours.white,
	separator_colour = colours.lightGrey,
}

return common
