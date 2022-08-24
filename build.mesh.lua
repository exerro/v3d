
-- Note: this has been copied and spliced with some more-up-to-date mesh stuff
-- which isn't in the repo

local MAIN_MODULE_NAME = "__main"
local LOCALMODULES = "::LOCALMODULES::"
local LOCALMODULELINES = "::LOCALMODULELINES::"

local TEMPLATE_CONTENT = [[
local __localmodules = {}
local __localmodulecache = {}
local __localmodulelines = {}
local __require = require
local function require(module)
	local f = __localmodules[module]
	if not f then return __require(module) end
	local result = __localmodulecache[module]
	if result == nil then
		__localmodulecache[module] = true
		result = f() or true
		__localmodulecache[module] = result
	end
	return result
end
]] .. LOCALMODULES .. [[

]] .. LOCALMODULELINES .. [[

-- TODO: error mapping!
return __localmodules[']] .. MAIN_MODULE_NAME .. [['](...)
]]

local function scan_requires(path)
	local requires = {}

	for line in path.lines(true) do
		local match = line:match("require%s*%(?['\"]([^'\"]*)['\"]%)?")

		if not match and line:find "%S" then
			break
		end

		table.insert(requires, match)
	end

	return requires
end

tasks["mesh::copy"] = function(self)
	print_info("Copying from '" .. tostring(self.config.from) .. "' to '" .. tostring(self.config.to) .. "'")
	self.config.from.copy_to(self.config.to)
end

tasks["mesh::copy"].config {
	from = MESH_ROOT_PATH / "src",
	to = MESH_ROOT_PATH / "build/src",
}

tasks["mesh::clean"] = function(self)
	print_info("Cleaning '" .. tostring(self.config.path) .. "'")
	self.config.path.delete()
end

tasks["mesh::clean"].config {
	path = MESH_ROOT_PATH / "build",
}

tasks["lua::run"] = function(self)
    print_info("Running script: '" .. tostring(self.config.script_path) .. "'")

    local content = self.config.script_path.read(true)
	local env = mesh_get_parent_environment()
    local f, err = load(content, tostring(self.config.script_path), nil, env)
    
    if not f then
        print_error(err)
        cancel_build()
        return
    end

	env.term.setTextColour(colours.white)

    -- TODO: run with stacktrace
    local ok, err = pcall(f, table.unpack(self.config.arguments or {}))

    if not ok then
        print_error(err)
        cancel_build()
        return
    end
end

tasks["lua::run"].config {
    script_path = MESH_ROOT_PATH / "build/main.lua",
	arguments = {},
}

tasks["lua::check_syntax"] = function(self)
	print_info("Checking files: '" .. tostring(self.config.files) .. "'")

	for file in self.config.files.find_iterator(true) do
		print_debug("Checking '" .. tostring(file) .. "'")
		local content = file.read(true)
		local ok, err = load(content, tostring(file))

		if not ok then
			print_error("File '" .. tostring(file) .. "' has a syntax error")
			print_error(err)
			cancel_build()
		end
	end
end

tasks["lua::check_syntax"].config {
	files = MESH_ROOT_PATH / "build/src/**.lua",
}

tasks["lua::minify"] = function(self)
	print_info("Minifying files: '" .. tostring(self.config.files) .. "'")
	print_warning("NOTE: Minification is not yet supported")
end

tasks["lua::minify"].config {
	files = MESH_ROOT_PATH / "build/src/**.lua",
}

tasks["lua::assemble"] = function(self)
	print_info("Assembling files in '" .. tostring(self.config.require_path) .. "', entry '" .. tostring(self.config.entry_path) .. "'")
	print_debug("Writing to '" .. tostring(self.config.output_path) .. "'")

	local queue = { { MAIN_MODULE_NAME, self.config.entry_path } }
	local files = {}
	local count = 0
	
	while #queue > 0 do
		local queued = table.remove(queue, 1)
		local name = queued[1]
		local path = queued[2]

		if not files[name] then
			files[name] = path.read(true)
			count = count + 1

			local r = scan_requires(path)

			for i = 1, #r do
				local p = r[i]:gsub("%.", "/") .. ".lua"
				table.insert(queue, { r[i], self.config.require_path / p })
			end
		end
	end

	if count == 1 then
		self.config.output_path.write(files[MAIN_MODULE_NAME])
		return
	end

	local localModuleContent = {}
	local localModuleLines = {}
	local lines = 17

	for k, v in pairs(files) do
		local s, c = v:gsub("\n", "\n")
		table.insert(localModuleContent,
			"__localmodules['" .. k .. "'] = " ..
			"function(...)\n" .. s .. "\nend")
		table.insert(localModuleLines,
			"__localmodulelines['" .. k .. "'] = " .. lines)
		lines = lines + c + 3
	end

	localModuleContent = table.concat(localModuleContent, "\n")
	localModuleLines = table.concat(localModuleLines, "\n")

	local content = TEMPLATE_CONTENT
		:gsub(LOCALMODULELINES, { [LOCALMODULELINES] = localModuleLines }, 1)
		:gsub(LOCALMODULES, { [LOCALMODULES] = localModuleContent }, 1)

	self.config.output_path.write(content)
end

tasks["lua::assemble"].config {
	require_path = MESH_ROOT_PATH / "build/src",
	output_path = MESH_ROOT_PATH / "build/out.lua",
	entry_path = MESH_ROOT_PATH / "build/src/main.lua",
}

tasks.setup:extends_from "mesh::copy"
tasks.setup.config {
	from = MESH_ROOT_PATH / "src",
	to = MESH_ROOT_PATH / "build/src",
}

tasks.check:extends_from "lua::check_syntax"
tasks.check:depends_on(tasks.setup)
tasks.check.config {
	include = MESH_ROOT_PATH / "build/src" / "**.lua",
}

tasks["build-lib"]:extends_from "lua::assemble"
tasks["build-lib"]:depends_on(tasks.check)
tasks["build-lib"].config {
	require_path = MESH_ROOT_PATH / "build/src",
	output_path = MESH_ROOT_PATH / "build/lib/ccgl3d.lua",
	entry_path = MESH_ROOT_PATH / "build/src/lib/ccgl3d.lua"
}

tasks.build:extends_from "lua::assemble"
tasks.build:depends_on(tasks.check)
tasks.build.config {
	require_path = MESH_ROOT_PATH / "build/src",
	output_path = MESH_ROOT_PATH / "build/main.lua",
	entry_path = MESH_ROOT_PATH / "build/src/main.lua"
}

tasks.run:extends_from "lua::run"
tasks.run:depends_on(tasks.build)
tasks.run.config {
	script_path = MESH_ROOT_PATH / "build/main.lua",
	arguments = { (MESH_ROOT_PATH / "build/sample").absolute_path() },
}

tasks.clean:extends_from "mesh::clean" {
	path = MESH_ROOT_PATH / "build",
}
