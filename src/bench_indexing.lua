
local function bench_index(t, k, v)
	for i = 1, 100000 do
		t[k] = v
		t[k] = v
		t[k] = v
		t[k] = v
		t[k] = v
		t[k] = v
		t[k] = v
		t[k] = v
		t[k] = v
		t[k] = v
		t[k] = v
		t[k] = v
		t[k] = v
		t[k] = v
		t[k] = v
		t[k] = v
		t[k] = v
		t[k] = v
		t[k] = v
		t[k] = v
		t[k] = v
		t[k] = v
		t[k] = v
		t[k] = v
		t[k] = v
		t[k] = v
		t[k] = v
		t[k] = v
		t[k] = v
		t[k] = v
		t[k] = v
		t[k] = v
	end
end

local function bench_rawset_local(t, k, v)
	local rawset = rawset
	local t1 = t
	local k1 = k
	local v1 = v
	for i = 1, 100000 do
		rawset(t1, k1, v1)
		rawset(t1, k1, v1)
		rawset(t1, k1, v1)
		rawset(t1, k1, v1)
		rawset(t1, k1, v1)
		rawset(t1, k1, v1)
		rawset(t1, k1, v1)
		rawset(t1, k1, v1)
		rawset(t1, k1, v1)
		rawset(t1, k1, v1)
		rawset(t1, k1, v1)
		rawset(t1, k1, v1)
		rawset(t1, k1, v1)
		rawset(t1, k1, v1)
		rawset(t1, k1, v1)
		rawset(t1, k1, v1)
		rawset(t1, k1, v1)
		rawset(t1, k1, v1)
		rawset(t1, k1, v1)
		rawset(t1, k1, v1)
		rawset(t1, k1, v1)
		rawset(t1, k1, v1)
		rawset(t1, k1, v1)
		rawset(t1, k1, v1)
		rawset(t1, k1, v1)
		rawset(t1, k1, v1)
		rawset(t1, k1, v1)
		rawset(t1, k1, v1)
		rawset(t1, k1, v1)
		rawset(t1, k1, v1)
		rawset(t1, k1, v1)
		rawset(t1, k1, v1)
	end
end

local function bench_rawset_global(t, k, v)
	for i = 1, 100000 do
		rawset(t, k, v)
		rawset(t, k, v)
		rawset(t, k, v)
		rawset(t, k, v)
		rawset(t, k, v)
		rawset(t, k, v)
		rawset(t, k, v)
		rawset(t, k, v)
		rawset(t, k, v)
		rawset(t, k, v)
		rawset(t, k, v)
		rawset(t, k, v)
		rawset(t, k, v)
		rawset(t, k, v)
		rawset(t, k, v)
		rawset(t, k, v)
		rawset(t, k, v)
		rawset(t, k, v)
		rawset(t, k, v)
		rawset(t, k, v)
		rawset(t, k, v)
		rawset(t, k, v)
		rawset(t, k, v)
		rawset(t, k, v)
		rawset(t, k, v)
		rawset(t, k, v)
		rawset(t, k, v)
		rawset(t, k, v)
		rawset(t, k, v)
		rawset(t, k, v)
		rawset(t, k, v)
		rawset(t, k, v)
	end
end

for _, f in ipairs { bench_index, bench_rawset_local, bench_rawset_global } do
	local t0 = os.clock()
	f({}, 1, "hello")
	print(os.clock() - t0)
end
