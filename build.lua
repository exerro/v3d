
local path = shell and (shell.getRunningProgram():match '.+/' or '') or 'v3d/'
local sections = { {} }

local function permute(flags)
	local r = { {} }

	for i = 1, #flags do
		local rr = {}
		for j = 1, #r do
			for v = 0, 1 do
				local rc = {}
				for k, v in pairs(r[j]) do
					rc[k] = v
				end
				rc[flags[i]] = v == 1
				table.insert(rr, rc)
			end
		end
		r = rr
	end

	return r
end

--- @param r string[]
--- @param ri integer
--- @param variable string
--- @param function_base string
--- @param params { [1]: string, [2]: string }[]
--- @param i integer
--- @return integer
local function select_permutations(r, ri, variable, function_base, params, i)
	if i > #params then
		table.insert(r, ri, variable .. " = " .. function_base)
		return ri + 1
	end

	table.insert(r, ri, "if " .. variable .. "_" .. params[i][1] .. " then")
	ri = select_permutations(r, ri + 1, variable, function_base .. "_" .. params[i][1], params, i + 1)
	table.insert(r, ri, "else")
	ri = select_permutations(r, ri + 1, variable, function_base, params, i + 1)
	table.insert(r, ri, "end")
	return ri + 1
end

local function generate_section_selections(section)
	local i = 1

	while i <= #section do
		if section[i]:find '^%s*%-%-%s*#select' then
			local variable, function_base = section[i]:match '^%s*%-%-%s*#select%s+([%w_]+)%s+([%w_]+)'
			local params = {}

			while true do
				i = i + 1
				if not section[i]:find '%s*%-%-%s*#select%-param' then
					break
				end
				local param, condition = section[i]:match '^%s*%-%-%s*#select%-param%s+([%w_]+)%s+(.+)$'
				table.insert(params, { param, condition })
			end

			for j = 1, #params do
				table.insert(section, i, "local " .. variable .. "_" .. params[j][1] .. " = " .. params[j][2])
				i = i + 1
			end

			i = select_permutations(section, i, variable, function_base, params, 1)
		else
			i = i + 1
		end
	end
end

local function generate_section_permutations(section, flagset)
	local r = {}
	local ifs = { [0] = true }

	for _, line in ipairs(section) do
		if line:find '^%s*%-%-%s*#if' then
			local enabled = false
			for part in line:gsub('^%s*%-%-%s*#if', ''):gmatch '[%w_]+' do
				if flagset[part] then
					enabled = true
					break
				end
			end
			table.insert(ifs, ifs[#ifs] and enabled)
			table.insert(r, line)
		elseif line:find '^%s*%-%-%s*#elseif' then
			local enabled = false
			for part in line:gsub('^%s*%-%-%s*#elseif', ''):gmatch '[%w_]+' do
				if flagset[part] then
					enabled = true
					break
				end
			end
			ifs[#ifs] = ifs[#ifs - 1] and not ifs[#ifs] and enabled
			table.insert(r, line)
		elseif line:find '^%s*%-%-%s*#else' then
			ifs[#ifs] = ifs[#ifs - 1] and not ifs[#ifs]
			table.insert(r, line)
		elseif line:find '^%s*%-%-%s*#end' then
			table.remove(ifs, #ifs)
			table.insert(r, line)
		elseif ifs[#ifs] then
			table.insert(r, line)
		end
	end

	return r
end

for line in io.lines(path .. 'src/v3d.lua') do
	if line:find '^%-%- #section [%w_ ]+$' then
		local flags = {}
		for flag in line:sub(12):gmatch "[%w_]+" do
			table.insert(flags, flag)
		end
		assert(#flags > 0, 'Section with no flags')
		table.insert(sections[#sections], line)
		table.insert(sections, { flags = flags })
	elseif line:find '^%-%- #endsection' then
		table.insert(sections, {})
		table.insert(sections[#sections], line)
	else
		table.insert(sections[#sections], line)
	end
end

local blocks = {}

for _, section in ipairs(sections) do
	generate_section_selections(section)

	if section.flags then
		local function_name = section[1]:match 'function ([%w_]+)'

		for _, flagset in ipairs(permute(section.flags)) do
			local this_function_name = function_name

			if function_name then
				for i = 1, #section.flags do
					if flagset[section.flags[i]] then
						this_function_name = this_function_name .. '_' .. section.flags[i]
					end
				end
			end

			local s = generate_section_permutations(section, flagset)

			if function_name then
				s[1] = s[1]:gsub('function ' .. function_name, 'function ' .. this_function_name)
			end

			table.insert(s, 1, '-- section-flags: ')

			for i = 1, #section.flags do
				if i > 1 then
					s[1] = s[1] .. ', '
				end
				s[1] = s[1] .. section.flags[i] .. ': ' .. tostring(flagset[section.flags[i]])
			end

			table.insert(blocks, table.concat(s, '\n'))
		end
	else
		table.insert(blocks, table.concat(section, '\n'))
	end
end

local h = assert(io.open('v3d.lua', 'w'))
h:write(table.concat(blocks, '\n'))
h:close()
