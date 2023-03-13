
-- Patterns
--
-- 0
--  aa
--  aa
--  aa
--
-- 1
--  bb
--  aa
--  aa
--
-- 2
--  bb
--  bb
--  aa
--
-- 3
--  cc
--  bb
--  aa
--
-- 4
--  bb
--  bb
--  ba
--
-- 5
--  cc
--  bb
--  ba
--
-- 6
--  cc
--  cc
--  ba
--
-- 7
--  dd
--  cc
--  ba
--
-- 8
--  ba
--  aa
--  aa
--
-- 9
--  cb
--  aa
--  aa
--
-- 10
--  cb
--  bb
--  aa
--
-- 11
--  dc
--  bb
--  aa
--
-- 12
--  cb
--  bb
--  ba
--
-- 13
--  dc
--  bb
--  ba
--
-- 14
--  dc
--  cc
--  ba
--
-- 15
--  ed
--  cc
--  ba
--
-- 16
--  bb
--  ba
--  aa
--
-- 17
--  cc
--  ba
--  aa
--
-- 18
--  cc
--  cb
--  aa
--
-- 19
--  dd
--  cb
--  aa
--
-- 20
--  cc
--  cb
--  ba
--
-- 21
--  dd
--  dc
--  ba
--
-- 22
--  dd
--  cb
--  ba
--
-- 23
--  ee
--  dc
--  ba
--
-- 24
--  cb
--  ba
--  aa
--
-- 25
--  dc
--  ba
--  aa
--
-- 26
--  dc
--  cb
--  aa
--
-- 27
--  ed
--  cb
--  aa
--
-- 28
--  dc
--  cb
--  ba
--
-- 29
--  ed
--  cb
--  ba
--
-- 30
--  ed
--  dc
--  ba
--
-- 31
--  fe
--  dc
--  ba

-- I've gone through these manually, looking at the pattern and converting that
-- into code that checks it with comparisons. It was painful and could've been
-- automated. Fml.
local pattern_validators = {
	[0] = function(v0, v1, v2, v3, v4, v5)
		return v1 == v0 and v2 == v0 and v3 == v0 and v4 == v0 and v5 == v0
	end,
	[1] = function(v0, v1, v2, v3, v4, v5)
		return v1 == v0 and v2 ~= v0 and v3 == v2 and v4 == v2 and v5 == v2
	end,
	[2] = function(v0, v1, v2, v3, v4, v5)
		return v1 == v0 and v2 == v0 and v3 == v2 and v4 ~= v2 and v5 == v4
	end,
	[3] = function(v0, v1, v2, v3, v4, v5)
		return v1 == v0 and v2 ~= v0 and v3 == v2 and v4 ~= v0 and v4 ~= v2 and v5 == v4
	end,
	[4] = function(v0, v1, v2, v3, v4, v5)
		return v1 == v0 and v2 == v0 and v3 == v2 and v4 == v2 and v5 ~= v2
	end,
	[5] = function(v0, v1, v2, v3, v4, v5)
		return v1 == v0 and v2 ~= v0 and v3 == v2 and v4 == v2 and v5 ~= v0 and v5 ~= v2
	end,
	[6] = function(v0, v1, v2, v3, v4, v5)
		return v1 == v0 and v2 == v0 and v3 == v2 and v4 ~= v2 and v5 ~= v0 and v5 ~= v4
	end,
	[7] = function(v0, v1, v2, v3, v4, v5)
		return v1 == v0 and v2 ~= v0 and v3 == v2 and v4 ~= v0 and v4 ~= v2 and v5 ~= v0 and v5 ~= v2 and v5 ~= v4
	end,
	[8] = function(v0, v1, v2, v3, v4, v5)
		return v1 ~= v0 and v2 == v1 and v3 == v1 and v4 == v1 and v5 == v1
	end,
	[9] = function(v0, v1, v2, v3, v4, v5)
		return v1 ~= v0 and v2 ~= v0 and v2 ~= v1 and v3 == v2 and v4 == v2 and v5 == v2
	end,
	[10] = function(v0, v1, v2, v3, v4, v5)
		return v1 ~= v0 and v2 == v1 and v3 == v1 and v4 ~= v0 and v4 ~= v1 and v5 == v4
	end,
	[11] = function(v0, v1, v2, v3, v4, v5)
		return v1 ~= v0 and v2 ~= v0 and v2 ~= v1 and v3 == v2 and v4 ~= v0 and v4 ~= v1 and v4 ~= v2 and v5 == v4
	end,
	[12] = function(v0, v1, v2, v3, v4, v5)
		return v1 ~= v0 and v2 == v1 and v3 == v1 and v4 == v1 and v5 ~= v0 and v5 ~= v1
	end,
	[13] = function(v0, v1, v2, v3, v4, v5)
		return v1 ~= v0 and v2 ~= v0 and v2 ~= v1 and v3 == v2 and v4 == v2 and v5 ~= v0 and v5 ~= v1 and v5 ~= v2
	end,
	[14] = function(v0, v1, v2, v3, v4, v5)
		return v1 ~= v0 and v2 == v1 and v3 == v1 and v4 ~= v0 and v4 ~= v1 and v5 ~= v0 and v5 ~= v1 and v5 ~= v4
	end,
	[15] = function(v0, v1, v2, v3, v4, v5)
		return v1 ~= v0 and v2 ~= v0 and v2 ~= v1 and v3 == v2 and v4 ~= v0 and v4 ~= v1 and v4 ~= v2 and v5 ~= v0 and v5 ~= v1 and v5 ~= v2 and v5 ~= v4
	end,
	[16] = function(v0, v1, v2, v3, v4, v5)
		return v1 == v0 and v2 == v0 and v3 ~= v0 and v4 == v3 and v5 == v3
	end,
	[17] = function(v0, v1, v2, v3, v4, v5)
		return v1 == v0 and v2 ~= v0 and v3 ~= v0 and v3 ~= v2 and v4 == v3 and v5 == v3
	end,
	[18] = function(v0, v1, v2, v3, v4, v5)
		return v1 == v0 and v2 == v0 and v3 ~= v0 and v4 ~= v0 and v4 ~= v3 and v5 == v4
	end,
	[19] = function(v0, v1, v2, v3, v4, v5)
		return v1 == v0 and v2 ~= v0 and v3 ~= v0 and v3 ~= v2 and v4 ~= v0 and v4 ~= v2 and v4 ~= v3 and v5 == v4
	end,
	[20] = function(v0, v1, v2, v3, v4, v5)
		return v1 == v0 and v2 == v0 and v3 ~= v0 and v4 == v3 and v5 ~= v0 and v5 ~= v3
	end,
	[21] = function(v0, v1, v2, v3, v4, v5)
		return v1 == v0 and v2 == v0 and v3 ~= v0 and v4 ~= v0 and v4 ~= v3 and v5 ~= v0 and v5 ~= v3 and v5 ~= v4
	end,
	[22] = function(v0, v1, v2, v3, v4, v5)
		return v1 == v0 and v2 ~= v0 and v3 ~= v0 and v3 ~= v2 and v4 == v3 and v5 ~= v0 and v5 ~= v2 and v5 ~= v3
	end,
	[23] = function(v0, v1, v2, v3, v4, v5)
		return v1 == v0 and v2 ~= v0 and v3 ~= v0 and v3 ~= v2 and v4 ~= v0 and v4 ~= v2 and v4 ~= v3 and v5 ~= v0 and v5 ~= v2 and v5 ~= v3 and v5 ~= v4
	end,
	[24] = function(v0, v1, v2, v3, v4, v5)
		return v1 ~= v0 and v2 == v1 and v3 ~= v0 and v3 ~= v1 and v4 == v3 and v5 == v3
	end,
	[25] = function(v0, v1, v2, v3, v4, v5)
		return v1 ~= v0 and v2 ~= v0 and v2 ~= v1 and v3 ~= v0 and v3 ~= v1 and v3 ~= v2 and v4 == v3 and v5 == v3
	end,
	[26] = function(v0, v1, v2, v3, v4, v5)
		return v1 ~= v0 and v2 == v1 and v3 ~= v0 and v3 ~= v1 and v4 ~= v0 and v4 ~= v1 and v4 ~= v3 and v5 == v4
	end,
	[27] = function(v0, v1, v2, v3, v4, v5)
		return v1 ~= v0 and v2 ~= v0 and v2 ~= v1 and v3 ~= v0 and v3 ~= v1 and v3 ~= v2 and v4 ~= v0 and v4 ~= v1 and v4 ~= v2 and v4 ~= v3 and v5 == v4
	end,
	[28] = function(v0, v1, v2, v3, v4, v5)
		return v1 ~= v0 and v2 == v1 and v3 ~= v0 and v3 ~= v1 and v4 == v3 and v5 ~= v0 and v5 ~= v1 and v5 ~= v3
	end,
	[29] = function(v0, v1, v2, v3, v4, v5)
		return v1 ~= v0 and v2 ~= v0 and v2 ~= v1 and v3 ~= v0 and v3 ~= v1 and v3 ~= v2 and v4 == v3 and v5 ~= v0 and v5 ~= v1 and v5 ~= v2 and v5 ~= v3
	end,
	[30] = function(v0, v1, v2, v3, v4, v5)
		return v1 ~= v0 and v2 == v1 and v3 ~= v0 and v3 ~= v1 and v4 ~= v0 and v4 ~= v1 and v4 ~= v3 and v5 ~= v0 and v5 ~= v1 and v5 ~= v3 and v5 ~= v4
	end,
	[31] = function(v0, v1, v2, v3, v4, v5)
		return v1 ~= v0 and v2 ~= v0 and v2 ~= v1 and v3 ~= v0 and v3 ~= v1 and v3 ~= v2 and v4 ~= v0 and v4 ~= v1 and v4 ~= v2 and v4 ~= v3 and v5 ~= v0 and v5 ~= v1 and v5 ~= v2 and v5 ~= v3 and v5 ~= v4
	end,
}

local function calculate_pattern(v0, v1, v2, v3, v4, v5)
	if v2 == v3 then
		if v0 == v1 then
			if v4 == v5 then
				if v3 == v5 then
					if v0 == v2 then
						return 0
					else
						return 1
					end
				else
					if v0 == v2 then
						return 2
					else
						return 3
					end
				end
			else
				if v2 == v4 then
					if v0 == v2 then
						return 4
					else
						return 5
					end
				else
					if v0 == v2 then
						return 6
					else
						return 7
					end
				end
			end
		else
			if v4 == v5 then
				if v3 == v5 then
					if v1 == v3 then
						return 8
					else
						return 9
					end
				else
					if v1 == v3 then
						return 10
					else
						return 11
					end
				end
			else
				if v2 == v4 then
					if v1 == v3 then
						return 12
					else
						return 13
					end
				else
					if v1 == v3 then
						return 14
					else
						return 15
					end
				end
			end
		end
	else
		if v0 == v1 then
			if v4 == v5 then
				if v3 == v5 then
					if v0 == v2 then
						return 16
					else
						return 17
					end
				else
					if v0 == v2 then
						return 18
					else
						return 19
					end
				end
			else
				if v0 == v2 then
					if v3 == v4 then
						return 20
					else
						return 21
					end
				else
					if v3 == v4 then
						return 22
					else
						return 23
					end
				end
			end
		else
			if v4 == v5 then
				if v3 == v5 then
					if v1 == v2 then
						return 24
					else
						return 25
					end
				else
					if v1 == v2 then
						return 26
					else
						return 27
					end
				end
			else
				if v3 == v4 then
					if v1 == v2 then
						return 28
					else
						return 29
					end
				else
					if v1 == v2 then
						return 30
					else
						return 31
					end
				end
			end
		end
	end
end

--- @nodiscard
local function pattern_to_string(v0, v1, v2, v3, v4, v5)
	local s = ''
	s = s .. v0 .. v1
	s = s .. v2 .. v3
	s = s .. v4 .. v5
	return '-- ' .. s:gsub('\n', '\n--  ') .. ': ' .. calculate_pattern(v0, v1, v2, v3, v4, v5)
end

local function split(permutations, a, b)
	local yes = {}
	local no = {}

	for i = 1, #permutations do
		local r = permutations[i]
		if r[a] == r[b] then
			table.insert(yes, r)
		else
			table.insert(no, r)
		end
	end

	return yes, no
end

local function find_best_split(permutations)
	local max_result = nil
	local max_count = 0

	for a = 1, 5 do
		for b = a + 1, 6 do
			local yes = 0
			local no = 0

			for i = 1, #permutations do
				local r = permutations[i]
				if r[a] == r[b] then
					yes = yes + 1
				else
					no = no + 1
				end
			end

			local count = math.min(yes, no)

			if count > max_count then
				max_count = count
				max_result = { a, b }
			end
		end
	end

	return max_result
end

local function generate_decision_tree(permutations)
	if #permutations == 1 then
		return permutations[1].index
	end

	local indices = find_best_split(permutations)
	local split_yes, split_no = split(permutations, indices[1], indices[2])

	return {
		split = indices,
		generate_decision_tree(split_yes),
		generate_decision_tree(split_no),
	}
end

local chars = { 'a', 'b', 'c', 'd', 'e', 'f' }
local permutations = {}
local permutation_index = 0

for v0 = 1, 6 do
	for v1 = 1, 6 do
		for v2 = 1, 6 do
			for v3 = 1, 6 do
				for v4 = 1, 6 do
					for v5 = 1, 6 do
						local ok = true

						local lookup = { [v0] = true, [v1] = true, [v2] = true, [v3] = true, [v4] = true, [v5] = true }
						local max = math.max(v0, v1, v2, v3, v4, v5)
						for i = 1, max do
							if not lookup[i] then
								ok = false
								break
							end
						end

						local seen = {}
						local order = {}
						for _, c in ipairs { v0, v1, v2, v3, v4, v5 } do
							if not seen[c] then
								seen[c] = true
								table.insert(order, c)
							end
						end

						for i = 2, #order do
							if order[i] < order[i - 1] then
								ok = false
							end
						end

						if ok then
							local r = { index = permutation_index, chars[v0], chars[v1], chars[v2], chars[v3], chars[v4], chars[v5] }
							permutation_index = permutation_index + 1
							table.insert(permutations, r)
						end
					end
				end
			end
		end
	end
end

print(#permutations .. ' permutations')

local or_less = { 0, 0, 0, 0, 0, 0 }
local or_more = { 0, 0, 0, 0, 0, 0 }

for i = 1, #permutations do
	local seen = {}
	local count = 0

	for j = 1, #permutations[i] do
		if not seen[permutations[i][j]] then
			seen[permutations[i][j]] = true
			count = count + 1
		end
	end
	
	for j = count, 6 do
		or_less[j] = or_less[j] + 1
	end
	
	for j = 1, count do
		or_more[j] = or_more[j] + 1
	end

	if count == 5 then
		print(pattern_to_string(table.unpack(permutations[i])))
	end
end

for i = 1, 6 do
	print(i .. ' or more: ' .. or_more[i] .. ' :: or less: ' .. or_less[i])
end

local function decision_tree_to_string(decision_tree, depth)
	if type(decision_tree) == 'number' then
		return tostring(decision_tree)
	end

	return string.format(
		'if (v%d == v%d) #%d {\n\t%s\n}\nelse {\n\t%s\n}',
		decision_tree.split[1] - 1,
		decision_tree.split[2] - 1,
		depth or 1,
		decision_tree_to_string(decision_tree[1], (depth or 1) + 1):gsub('\n', '\n\t'),
		decision_tree_to_string(decision_tree[2], (depth or 1) + 1):gsub('\n', '\n\t')
	)
end

local h = assert(io.open('/.subpixel-patterns.txt', 'w'))
local permutation_strings = {}

for i = 1, #permutations do
	table.insert(permutation_strings, pattern_to_string(table.unpack(permutations[i])))
end

h:write(table.concat(permutation_strings, '\n'))
h:write '\n'
h:write(decision_tree_to_string(generate_decision_tree(permutations)))
h:close()

-- Validate that, for all the permutations, they evaluate to a pattern and don't
-- then match against any other pattern.
for i = 1, #permutations do
	local pattern = calculate_pattern(table.unpack(permutations[i]))

	for j = 0, 31 do
		assert(pattern_validators[j](table.unpack(permutations[i])) == (pattern == j), i .. ', ' .. pattern .. ', ' .. j)
	end
end

-- Validate that, for all combinations of 6 colours, they evaluate to a pattern
-- and match the validation for that pattern.
for c0 = 0, 15 do
	for c1 = 0, 15 do
		for c2 = 0, 15 do
			for c3 = 0, 15 do
				for c4 = 0, 15 do
					for c5 = 0, 15 do
						local pattern = calculate_pattern(c0, c1, c2, c3, c4, c5)
						assert(pattern_validators[pattern](c0, c1, c2, c3, c4, c5), pattern .. ': ' .. table.concat({ c0, c1, c2, c3, c4, c5 }, ', '))
					end
				end
			end
		end
	end
end
