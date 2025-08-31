
local function bench_div(a, b)
	for i = 1, 100000 do
		local r = a / b
		local r = a / b
		local r = a / b
		local r = a / b
		local r = a / b
		local r = a / b
		local r = a / b
		local r = a / b
		local r = a / b
		local r = a / b
		local r = a / b
		local r = a / b
		local r = a / b
		local r = a / b
		local r = a / b
		local r = a / b
		local r = a / b
		local r = a / b
		local r = a / b
		local r = a / b
		local r = a / b
		local r = a / b
		local r = a / b
		local r = a / b
		local r = a / b
		local r = a / b
		local r = a / b
		local r = a / b
		local r = a / b
		local r = a / b
		local r = a / b
		local r = a / b
	end
end

local function bench_div_precalc(a, b)
	for i = 1, 100000 do
		local c = 1 / b
		local r = a * c
		local r = a * c
		local r = a * c
		local r = a * c
		local r = a * c
		local r = a * c
		local r = a * c
		local r = a * c
		local r = a * c
		local r = a * c
		local r = a * c
		local r = a * c
		local r = a * c
		local r = a * c
		local r = a * c
		local r = a * c
		local r = a * c
		local r = a * c
		local r = a * c
		local r = a * c
		local r = a * c
		local r = a * c
		local r = a * c
		local r = a * c
		local r = a * c
		local r = a * c
		local r = a * c
		local r = a * c
		local r = a * c
		local r = a * c
		local r = a * c
		local r = a * c
	end
end

for _, f in ipairs { bench_div, bench_div_precalc } do
	f(8, 2)
	local t0 = os.clock()
	f(8, 2)
	print(os.clock() - t0)
end
