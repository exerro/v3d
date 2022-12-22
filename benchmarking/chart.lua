
--- @class Chart
--- @field datapoints { [integer]: ChartDatapoint }

--- @alias ChartDatapoint { [any]: any }

--- @class ChartOptions
--- @field title string | nil
--- @field filter (fun(datapoint: ChartDatapoint): boolean) | nil
--- @field filter_values ChartDatapoint | nil
--- @field aggregate fun(values: { [integer]: ChartDatapoint }): ChartDatapoint
--- @field column_key string
--- @field column_key_writer (fun(key_value: any, datapoint: ChartDatapoint): string) | nil
--- @field column_sorter (fun(a: ChartDatapoint, b: ChartDatapoint): boolean) | nil
--- @field row_key string
--- @field row_key_writer (fun(key_value: any, datapoint: ChartDatapoint): string) | nil
--- @field row_sorter (fun(a: ChartDatapoint, b: ChartDatapoint): boolean) | nil
--- @field value_keys { [integer]: string }
--- @field value_format string
--- @field value_writers { [string]: fun(datapoint_value: any, datapoint: ChartDatapoint): any } | nil

--- @class chart_lib
local chart = {}

--- @returns Chart
function chart.new()
	return { datapoints = {} }
end

--- @param chart Chart
--- @param values table
function chart.add_data(chart, values)
	table.insert(chart.datapoints, values)
end

--- @param chart Chart
--- @param options ChartOptions
--- @return string
function chart.to_string(chart, options)
	local datapoints = {}

	local function aggregate_many(values)
		if #values == 1 then
			return values[1]
		end
		return options.aggregate(values)
	end

	for i = 1, #chart.datapoints do
		local ok = true
		local dp = chart.datapoints[i]

		if options.filter and not options.filter(dp) then
			ok = false
		end

		if ok and options.filter_values then
			for k, v in pairs(options.filter_values) do
				if dp[k] ~= v then
					ok = false
					break
				end
			end
		end

		if ok then
			table.insert(datapoints, dp)
		end
	end

	local rows = {}
	local row_index_lookup = {}

	for i = 1, #datapoints do
		local dp = datapoints[i]
		local row_value = dp[options.row_key]

		if row_index_lookup[row_value] == nil then
			row_index_lookup[row_value] = #rows + 1
			table.insert(rows, { dp })
		else
			table.insert(rows[row_index_lookup[row_value]], dp)
		end
	end

	if options.row_sorter then
		local rowAgg = {}

		for i = 1, #rows do
			rowAgg[i] = { aggregate = aggregate_many(rows[i]), values = rows[i] }
		end

		table.sort(rowAgg, function(a, b)
			return options.row_sorter(a.aggregate, b.aggregate)
		end)

		for i = 1, #rowAgg do
			rows[i] = rowAgg[i].values
		end
	end

	local columns = {}
	local column_index_lookup = {}

	for i = 1, #datapoints do
		local dp = datapoints[i]
		local column_value = dp[options.column_key]

		if column_index_lookup[column_value] == nil then
			column_index_lookup[column_value] = #columns + 1
			table.insert(columns, { dp })
		else
			table.insert(columns[column_index_lookup[column_value]], dp)
		end
	end

	if options.column_sorter then
		local columnAgg = {}

		for j = 1, #columns do
			columnAgg[j] = { aggregate = aggregate_many(columns[j]), values = columns[j] }
		end

		table.sort(columnAgg, function(a, b)
			return options.column_sorter(a.aggregate, b.aggregate)
		end)

		for j = 1, #columnAgg do
			columns[j] = columnAgg[j].values
		end
	end

	column_index_lookup = {}

	for j = 1, #columns do
		column_index_lookup[columns[j][1][options.column_key]] = j
	end

	local cells = {}

	for i = 1, #rows do
		local row = rows[i]
		local rowCells = {}

		cells[i] = rowCells

		for j = 1, #columns do
			rowCells[j] = {}
		end

		for k = 1, #row do
			local dp = row[k]
			local column_index = column_index_lookup[dp[options.column_key]]
			table.insert(rowCells[column_index], dp)
		end
	end

	for i = 1, #rows do
		for j = 1, #columns do
			local cell_value = aggregate_many(cells[i][j])
			local format_values = {}

			for i = 1, #options.value_keys do
				local k = options.value_keys[i]
				local v = cell_value[k]
				local w = options.value_writers and options.value_writers[k]

				if w then
					format_values[i] = w(v, cell_value)
				else
					format_values[i] = v
				end
			end

			--- @diagnostic disable-next-line: deprecated
			cells[i][j] = options.value_format:format(table.unpack(format_values))
		end
	end

	local column_labels = {}
	local row_labels = {}

	for j = 1, #columns do
		local column_value = columns[j][1]
		column_labels[j] = options.column_key_writer and options.column_key_writer(column_value[options.column_key], column_value) or tostring(column_value[options.column_key])
	end

	for i = 1, #rows do
		local row_value = rows[i][1]
		row_labels[i] = options.row_key_writer and options.row_key_writer(row_value[options.row_key], row_value) or tostring(row_value[options.row_key])
	end

	local string_cells = {}

	for i = 1, #rows + 1 do
		string_cells[i] = {}
		for j = 1, #columns + 1 do
			if i == 1 and j == 1 then
				string_cells[i][j] = options.title or "Chart"
			elseif i == 1 then
				string_cells[i][j] = column_labels[j - 1]
			elseif j == 1 then
				string_cells[i][j] = row_labels[i - 1]
			else
				string_cells[i][j] = cells[i - 1][j - 1]
			end
		end
	end

	local column_max = {}

	for j = 1, #string_cells[1] do
		local max = 0
		for i = 1, #string_cells do
			max = math.max(max, #string_cells[i][j])
		end
		column_max[j] = max
	end

	local result = ""

	for i = 1, #string_cells do
		if i ~= 1 then
			result = result .. '\n'
		end
		for j = 1, #string_cells[i] do
			if j ~= 1 then
				result = result .. ' | '
			end
			local v = string_cells[i][j]
			result = result .. (' '):rep(column_max[j] - #v) .. v
		end
	end

	return result
end

return chart
