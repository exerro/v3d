
-- conclusion: ifs faster by about a factor of 4

local iter_count = 1000000000
local n_inrange = 5.1
local n_outrange = 10.2
local lower_bound = 4.3
local upper_bound = 8.4

local math_min = math.min
local math_max = math.max

local result

local t_start_minmax_inrange = os.clock()
for i = 1, iter_count do
	result = math_max(lower_bound, math_min(upper_bound, n_inrange))
	result = math_max(lower_bound, math_min(upper_bound, n_inrange))
	result = math_max(lower_bound, math_min(upper_bound, n_inrange))
	result = math_max(lower_bound, math_min(upper_bound, n_inrange))
	result = math_max(lower_bound, math_min(upper_bound, n_inrange))

	result = math_max(lower_bound, math_min(upper_bound, n_inrange))
	result = math_max(lower_bound, math_min(upper_bound, n_inrange))
	result = math_max(lower_bound, math_min(upper_bound, n_inrange))
	result = math_max(lower_bound, math_min(upper_bound, n_inrange))
	result = math_max(lower_bound, math_min(upper_bound, n_inrange))

	result = math_max(lower_bound, math_min(upper_bound, n_inrange))
	result = math_max(lower_bound, math_min(upper_bound, n_inrange))
	result = math_max(lower_bound, math_min(upper_bound, n_inrange))
	result = math_max(lower_bound, math_min(upper_bound, n_inrange))
	result = math_max(lower_bound, math_min(upper_bound, n_inrange))

	result = math_max(lower_bound, math_min(upper_bound, n_inrange))
	result = math_max(lower_bound, math_min(upper_bound, n_inrange))
	result = math_max(lower_bound, math_min(upper_bound, n_inrange))
	result = math_max(lower_bound, math_min(upper_bound, n_inrange))
	result = math_max(lower_bound, math_min(upper_bound, n_inrange))

	result = math_max(lower_bound, math_min(upper_bound, n_inrange))
	result = math_max(lower_bound, math_min(upper_bound, n_inrange))
	result = math_max(lower_bound, math_min(upper_bound, n_inrange))
	result = math_max(lower_bound, math_min(upper_bound, n_inrange))
	result = math_max(lower_bound, math_min(upper_bound, n_inrange))

	result = math_max(lower_bound, math_min(upper_bound, n_inrange))
	result = math_max(lower_bound, math_min(upper_bound, n_inrange))
	result = math_max(lower_bound, math_min(upper_bound, n_inrange))
	result = math_max(lower_bound, math_min(upper_bound, n_inrange))
	result = math_max(lower_bound, math_min(upper_bound, n_inrange))

	result = math_max(lower_bound, math_min(upper_bound, n_inrange))
	result = math_max(lower_bound, math_min(upper_bound, n_inrange))
	result = math_max(lower_bound, math_min(upper_bound, n_inrange))
	result = math_max(lower_bound, math_min(upper_bound, n_inrange))
	result = math_max(lower_bound, math_min(upper_bound, n_inrange))

	result = math_max(lower_bound, math_min(upper_bound, n_inrange))
	result = math_max(lower_bound, math_min(upper_bound, n_inrange))
	result = math_max(lower_bound, math_min(upper_bound, n_inrange))
	result = math_max(lower_bound, math_min(upper_bound, n_inrange))
	result = math_max(lower_bound, math_min(upper_bound, n_inrange))
end
local t_minmax_inrange = os.clock() - t_start_minmax_inrange

local t_start_minmax_outrange = os.clock()
for i = 1, iter_count do
	result = math_max(lower_bound, math_min(upper_bound, n_outrange))
	result = math_max(lower_bound, math_min(upper_bound, n_outrange))
	result = math_max(lower_bound, math_min(upper_bound, n_outrange))
	result = math_max(lower_bound, math_min(upper_bound, n_outrange))
	result = math_max(lower_bound, math_min(upper_bound, n_outrange))

	result = math_max(lower_bound, math_min(upper_bound, n_outrange))
	result = math_max(lower_bound, math_min(upper_bound, n_outrange))
	result = math_max(lower_bound, math_min(upper_bound, n_outrange))
	result = math_max(lower_bound, math_min(upper_bound, n_outrange))
	result = math_max(lower_bound, math_min(upper_bound, n_outrange))

	result = math_max(lower_bound, math_min(upper_bound, n_outrange))
	result = math_max(lower_bound, math_min(upper_bound, n_outrange))
	result = math_max(lower_bound, math_min(upper_bound, n_outrange))
	result = math_max(lower_bound, math_min(upper_bound, n_outrange))
	result = math_max(lower_bound, math_min(upper_bound, n_outrange))

	result = math_max(lower_bound, math_min(upper_bound, n_outrange))
	result = math_max(lower_bound, math_min(upper_bound, n_outrange))
	result = math_max(lower_bound, math_min(upper_bound, n_outrange))
	result = math_max(lower_bound, math_min(upper_bound, n_outrange))
	result = math_max(lower_bound, math_min(upper_bound, n_outrange))

	result = math_max(lower_bound, math_min(upper_bound, n_outrange))
	result = math_max(lower_bound, math_min(upper_bound, n_outrange))
	result = math_max(lower_bound, math_min(upper_bound, n_outrange))
	result = math_max(lower_bound, math_min(upper_bound, n_outrange))
	result = math_max(lower_bound, math_min(upper_bound, n_outrange))

	result = math_max(lower_bound, math_min(upper_bound, n_outrange))
	result = math_max(lower_bound, math_min(upper_bound, n_outrange))
	result = math_max(lower_bound, math_min(upper_bound, n_outrange))
	result = math_max(lower_bound, math_min(upper_bound, n_outrange))
	result = math_max(lower_bound, math_min(upper_bound, n_outrange))

	result = math_max(lower_bound, math_min(upper_bound, n_outrange))
	result = math_max(lower_bound, math_min(upper_bound, n_outrange))
	result = math_max(lower_bound, math_min(upper_bound, n_outrange))
	result = math_max(lower_bound, math_min(upper_bound, n_outrange))
	result = math_max(lower_bound, math_min(upper_bound, n_outrange))

	result = math_max(lower_bound, math_min(upper_bound, n_outrange))
	result = math_max(lower_bound, math_min(upper_bound, n_outrange))
	result = math_max(lower_bound, math_min(upper_bound, n_outrange))
	result = math_max(lower_bound, math_min(upper_bound, n_outrange))
	result = math_max(lower_bound, math_min(upper_bound, n_outrange))
end
local t_minmax_outrange = os.clock() - t_start_minmax_outrange

local t_start_ifs_inrange = os.clock()
for i = 1, iter_count do
	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end

	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end

	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end

	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end

	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end

	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end

	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end

	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_inrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
end
local t_ifs_inrange = os.clock() - t_start_ifs_inrange

local t_start_ifs_outrange = os.clock()
for i = 1, iter_count do
	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end

	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end

	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end

	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end

	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end

	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end

	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end

	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
	result = n_outrange
	if result > upper_bound then result = upper_bound
	elseif result < lower_bound then result = lower_bound end
end
local t_ifs_outrange = os.clock() - t_start_ifs_outrange

print('min()/max() in  : ' .. t_minmax_inrange * 1000 .. 'ms')
print('min()/max() out : ' .. t_minmax_outrange * 1000 .. 'ms')
print('if in           : ' .. t_ifs_inrange * 1000 .. 'ms')
print('if out          : ' .. t_ifs_outrange * 1000 .. 'ms')
