
local args = { ... }
local fps_bc = colours.black
local fps_fc = colours.white
local fps_enabled = false
local validation_enabled = true
local capture_key = keys.f12
local v3d_require_path = '/v3d'
local capture_first_frame = false

while args[1] and args[1]:sub(1, 1) == '-' do
	local arg = table.remove(args, 1)

	if arg == '--fps-bc' then
		fps_bc = table.remove(args, 1) or error('Expected colour after --fps-bc', 0)
		fps_bc = colours[fps_bc] or error('Unknown colour \'' .. fps_bc .. '\'', 0)
	elseif arg == '--fps-fc' then
		fps_fc = table.remove(args, 1) or error('Expected colour after --fps-fc', 0)
		fps_fc = colours[fps_fc] or error('Unknown colour \'' .. fps_fc .. '\'', 0)
	elseif arg == '--show-fps' or arg == '--fps' or arg == '-f' then
		fps_enabled = true
	elseif arg == '--no-validation' or arg == '-V' then
		validation_enabled = false
	elseif arg == '--capture-key' or arg == '--key' or arg == '-k' then
		capture_key = table.remove(args, 1) or error('Expected key name after --capture-key', 0)
		capture_key = keys[capture_key] or error('Unknown key name \'' .. capture_key .. '\'', 0)
	elseif arg == '--capture-first-frame' or arg == '-c' then
		capture_first_frame = true
	elseif arg == '--v3d-path' then
		v3d_require_path = table.remove(args, 1) or error('Expected path after --v3d-path', 0)
	else
		error('Unknown option \'' .. arg .. '\'', 0)
	end
end

local program = table.remove(args, 1) or error('Expected program path', 0)

--------------------------------------------------------------------------------

local program_environment = setmetatable({}, getmetatable(_ENV))
local v3dd_debug_marker = tostring {} :sub(8)
local program_fn

do
	for k, v in pairs(_ENV) do
		program_environment[k] = v
	end

	local requirelib = require '/rom.modules.main.cc.require'
	program_environment.require, program_environment.package = requirelib.make(program_environment, fs.getDir(program))

	local program_path = shell.resolveProgram(program)
	
	if not program_path then
		error('Failed to find program \'' .. program .. '\'', 0)
	end

	local program_file = io.open(program_path, 'r')
	local program_contents = ''

	if program_file then
		program_contents = program_file:read '*a'
		program_file:close()
	else
		error('Failed to read file \'' .. program_path .. '\'', 0)
	end

	local err
	program_fn, err = load(program_contents, 'v3dd@' .. v3dd_debug_marker .. ' ' .. program, nil, program_environment)

	if not program_fn then
		error('Failed to load program: ' .. err, 0)
	end
end

--------------------------------------------------------------------------------

--- @class LibraryWrapper
--- @field library table
--- @field begin_frame fun(): nil
--- @field finish_frame fun(): boolean, Tree[]

--- @class TreeNode
--- @field content string | nil
--- @field content_right string | nil
--- @field on_select function | nil

--- @class TreeBranch
--- @field content string | nil
--- @field content_right string | nil
--- @field content_expanded string | nil
--- @field content_right_expanded string | nil
--- @field default_expanded boolean | nil
--- @field children Tree[]

--- @alias Tree TreeNode | TreeBranch

--- @return LibraryWrapper
local function create_v3d_wrapper(enable_validation)
	local v3d_ok, v3d_lib = pcall(require, v3d_require_path)
	--- @cast v3d_lib v3d
	--- @type v3d
	local v3d_wrapper = {}

	if not v3d_ok then
		error('Failed to load v3d library at \'' .. v3d_require_path .. '\': ' .. v3d_lib .. '.\nUse --v3d-path to specify alternate path', 0)
	end

	--- @alias ResourceType 'Framebuffer' | 'Layout' | 'GeometryBuilder' | 'Geometry' | 'Transform' | 'Pipeline'
	--- @type { [any]: ResourceType }
	local object_types = {}
	local next_object_id = 1
	local blit_called = false
	local call_tree_children = {}
	local resource_labels = {}
	local validation_failed = false

	------------------------------------------------------------

	local function begin_validation()
		validation_failed = false
		return enable_validation
	end

	local function check_validation()
		if validation_failed then
			error('v3d validation failed: check capture for details', 0)
		end
	end

	--- @param resource any
	--- @param resource_type ResourceType
	--- @param label string | nil
	local function register_object(resource, resource_type, label)
		local suffix = resource_type .. next_object_id
		next_object_id = next_object_id + 1
		label = label and '&pink;' .. label .. '&reset; @' .. suffix or '@' .. suffix
		resource_labels[resource] = label
		object_types[resource] = resource_type
	end

	--- @param tree Tree
	local function fcall(tree)
		table.insert(call_tree_children, tree)
	end

	--- @param t Tree[]
	--- @param name string
	--- @param value string
	--- @param children Tree[] | nil
	--- @return Tree
	local function fparam(t, name, value, children)
		local r = {
			content = '&lightBlue;' .. name .. '&reset; = ' .. value,
			default_expanded = false,
			children = children,
		}
		table.insert(t, r)
		return r
	end

	local function freturn(t)
		local r = { content = '&purple;return &red;undefined&reset;' }
		table.insert(t, r)
		return r
	end

	--- @param r Tree
	--- @param v string
	--- @return Tree
	local function fcompletereturn(r, v)
		r.content = '&purple;return &reset;' .. v
		return r
	end

	local function fmtconst(v)
		if type(v) == 'number' then
			return '&orange;' .. v .. '&reset;'
		elseif type(v) == 'string' then
			return '&green;"' .. v .. '"&reset;'
		elseif v == true or v == false or v == nil then
			return '&purple;' .. tostring(v) .. '&reset;'
		else
			return tostring(v)
		end
	end

	local function fmtcolour(c)
		for k, v in pairs(colours) do
			if c == v then
				return '\'&' .. k .. ';' .. k .. '&reset;\' ' .. tostring(c)
			end
		end
		for k, v in pairs(colors) do
			if c == v then
				return '\'' .. k .. '\' ' .. tostring(c)
			end
		end
		return tostring(c)
	end

	local function fmtresource(r)
		if type(r) ~= 'table' then
			return fmtconst(r)
		end
		return resource_labels[r] or ('&lightGrey;@' .. tostring(r):sub(8) .. '&reset;')
	end

	local function vwarn(t, c, err)
		if not c then
			table.insert(t, {
				content = '&yellow;WARNING: ' .. err:gsub('&reset;', '&yellow;')
			})
		end
	end

	local function verr(t, c, err)
		if not c then
			validation_failed = true
			table.insert(t, {
				content = '&red;ERROR: ' .. err:gsub('&reset;', '&red;')
			})
		end
		return c
	end

	------------------------------------------------------------

	local function set_framebuffer_details(tree, fb)
		tree.children = tree.children or {}
		fparam(tree.children, 'width', fmtconst(fb.width))
		fparam(tree.children, 'height', fmtconst(fb.height))
	end

	local function set_layout_details(tree, ly)
		--- @cast ly V3DLayout
		tree.children = tree.children or {}
		fparam(tree.children, 'vertex_stride', fmtconst(ly.vertex_stride))
		fparam(tree.children, 'face_stride', fmtconst(ly.face_stride))
		
		for i = 1, #ly.attributes do
			local attr = ly.attributes[i]
			local attr_detail = {
				content = string.format('attribute &lightBlue;%s&reset; (&blue;%s&reset;)', attr.name, attr.type),
				children = {}
			}
			fparam(attr_detail.children, 'size', fmtconst(attr.size))
			fparam(attr_detail.children, 'offset', fmtconst(attr.offset))
			fparam(attr_detail.children, 'is_numeric', fmtconst(attr.is_numeric))
			table.insert(tree.children, attr_detail)
		end
	end

	local function set_geometry_builder_details(tree, gb)
		tree.children = tree.children or {}
		local p1 = fparam(tree.children, 'layout', fmtresource(gb.layout))
		set_layout_details(p1, gb.layout)
	end

	local function set_geometry_details(tree, gm)
		tree.children = tree.children or {}
		local p1 = fparam(tree.children, 'layout', fmtresource(gm.layout))
		fparam(tree.children, 'vertices', fmtconst(gm.vertices))
		fparam(tree.children, 'faces', fmtconst(gm.faces))
		fparam(tree.children, 'vertex_offset', fmtconst(gm.vertex_offset))
		local data = { content = 'Data', children = {} }
		table.insert(tree.children, data)

		for i = 1, #gm do
			data.children[i] = { content = '&lightGrey;[' .. i .. ']: &reset;' .. fmtconst(gm[i]) }
		end

		set_layout_details(p1, gm.layout)
	end

	local function set_transform_details(tree, tr)
		tree.children = {}

		local s = {}
		local r = {}

		for y = 1, 3 do
			s[y] = {}
			for x = 1, 4 do
				local index = (y - 1) * 4 + x
				s[y][x] = fmtconst(tr[index])
			end
		end

		for x = 1, 4 do
			r[x] = 0
			for y = 1, 3 do
				r[x] = math.max(r[x], #s[y][x])
			end
		end

		for y = 1, 3 do
			local ss = {}
			for x = 1, 4 do
				ss[x] = (' '):rep(r[x] - #s[y][x]) .. s[y][x]
			end
			table.insert(tree.children, {
				content = table.concat(ss, '  '),
			})
		end
	end

	local function set_pipeline_details(tree, pi)
		tree.children = {}
		fparam(tree.children, 'source', '...') -- TODO
		fparam(tree.children, 'source_error', fmtconst(pi.source_error))
	end

	------------------------------------------------------------

	local function complete_framebuffer(ret, label, fb)
		register_object(fb, 'Framebuffer', label)
		fcompletereturn(ret, fmtresource(fb))
		set_framebuffer_details(ret, fb)

		local clear_orig = fb.clear
		function fb:clear(colour, clear_depth)
			local children = {}
	
			local p1 = fparam(children, 'framebuffer', fmtresource(self))
			fparam(children, 'colour', fmtcolour(colour))
			fparam(children, 'clear_depth', fmtconst(clear_depth))
	
			if begin_validation() then
				-- TODO: validate self
				if verr(children, colour == nil or (type(colour) == 'number' and colour % 1 == 0), 'Colour given to clear framebuffer was not an integer or nil') then
					vwarn(children, colour == nil or (colour >= 1 and colour <= 32768 and math.log(colour, 2) % 1 == 0), 'Colour given to clear framebuffer was not a valid colour')
				end
				if verr(children, clear_depth == nil or type(clear_depth) ~= 'number', 'Clear depth given to clear framebuffer was not a number or nil') then
					verr(children, clear_depth == nil or clear_depth >= 0, 'Clear depth given to clear framebuffer was negative')
				end
			end
	
			fcall {
				content = string.format(
					'&cyan;:clear&reset;(%s, %s)',
					fmtcolour(colour),
					fmtconst(clear_depth)),
				content_expanded = '&cyan;:clear&reset;(...)',
				children = children,
			}
	
			check_validation()
			set_framebuffer_details(p1, self)
			clear_orig(self, colour, clear_depth)
		end

		-- TODO
		local clear_depth_orig = fb.clear_depth
		function fb:clear_depth(clear_depth)
			return clear_depth_orig(self, clear_depth)
		end

		local blit_term_subpixel_orig = fb.blit_term_subpixel
		function fb:blit_term_subpixel(term, dx, dy)
			local children = {}
	
			local p1 = fparam(children, 'framebuffer', fmtresource(self))
			fparam(children, 'term', fmtconst(term))
			fparam(children, 'dx', fmtconst(dx))
			fparam(children, 'dy', fmtconst(dy))
	
			if begin_validation() then
				-- TODO: validate self
				verr(children, type(term) == 'table', 'Expected table term, got ' .. type(term))
				verr(children, dx == nil or (type(dx) == 'number' and dx % 1 == 0), 'Expected integer dx, got ' .. type(dx))
				verr(children, dy == nil or (type(dy) == 'number' and dy % 1 == 0), 'Expected integer dy, got ' .. type(dy))
			end
	
			fcall {
				content = string.format(
					'&cyan;:blit_term_subpixel&reset;(%s, %s, %s)',
					fmtconst(term),
					fmtconst(dx),
					fmtconst(dy)),
				content_expanded = '&cyan;:blit_term_subpixel&reset;(...)',
				children = children,
			}
	
			check_validation()
			set_framebuffer_details(p1, self)
			blit_term_subpixel_orig(self, term, dx, dy)
			blit_called = true
		end

		-- TODO
		local blit_term_subpixel_depth_orig = fb.blit_term_subpixel_depth
		function fb:blit_term_subpixel_depth(term, dx, dy, update_palette)
			blit_term_subpixel_depth_orig(self, term, dx, dy, update_palette)
			blit_called = true
		end

		-- TODO
		local blit_graphics_orig = fb.blit_graphics
		function fb:blit_graphics(term, dx, dy)
			blit_graphics_orig(self, term, dx, dy)
			blit_called = true
		end

		-- TODO
		local blit_graphics_depth_orig = fb.blit_graphics_depth
		function fb:blit_graphics_depth(term, dx, dy, update_palette)
			blit_graphics_depth_orig(self, term, dx, dy, update_palette)
			blit_called = true
		end

		return fb
	end

	local function complete_layout(ret, label, ly)
		register_object(ly, 'Layout', label)
		fcompletereturn(ret, fmtresource(ly))
		set_layout_details(ret, ly)

		local add_vertex_attribute_orig = ly.add_vertex_attribute
		function ly:add_vertex_attribute(name, size, is_numeric)
			local children = {}
	
			local p1 = fparam(children, 'self', fmtresource(self))
			fparam(children, 'name', fmtconst(name))
			fparam(children, 'size', fmtconst(size))
			fparam(children, 'is_numeric', fmtconst(is_numeric))

			local iret = freturn(children)

			if begin_validation() then
				verr(children, object_types[self] == 'Layout', 'Expected V3DLayout for self, got ' .. type(self))
				verr(children, type(name) == 'string', 'Expected string for name, got ' .. type(name))
				verr(children, type(size) == 'number' and size % 1 == 0, 'Expected integer for size, got ' .. type(size))
				verr(children, type(is_numeric) == 'boolean', 'Expected boolean for is_numeric, got ' .. type(is_numeric))
			end
	
			fcall {
				content = string.format('&cyan;:add_vertex_attribute&reset;(%s, %s, %s)',
					fmtconst(name),
					fmtconst(size),
					fmtconst(is_numeric)),
				content_expanded = '&cyan;:add_vertex_attribute&reset;(...)',
				children = children,
			}
	
			check_validation()
			set_layout_details(p1, self)

			local result = add_vertex_attribute_orig(self, name, size, is_numeric)

			complete_layout(iret, nil, result)

			return result
		end

		local add_face_attribute_orig = ly.add_face_attribute
		function ly:add_face_attribute(name, size)
			local children = {}
	
			local p1 = fparam(children, 'self', fmtresource(self))
			fparam(children, 'name', fmtconst(name))
			fparam(children, 'size', fmtconst(size))

			local iret = freturn(children)

			if begin_validation() then
				verr(children, object_types[self] == 'Layout', 'Expected V3DLayout for self, got ' .. type(self))
				verr(children, type(name) == 'string', 'Expected string for name, got ' .. type(name))
				verr(children, type(size) == 'number' and size % 1 == 0, 'Expected integer for size, got ' .. type(size))
			end
	
			fcall {
				content = string.format('&cyan;:add_vertex_attribute&reset;(%s, %s)',
					fmtconst(name),
					fmtconst(size)),
				content_expanded = '&cyan;:add_vertex_attribute&reset;(...)',
				children = children,
			}
	
			check_validation()
			set_layout_details(p1, self)

			local result = add_face_attribute_orig(self, name, size)

			complete_layout(iret, nil, result)

			return result
		end

		local drop_attribute_orig = ly.drop_attribute
		function ly:drop_attribute(attribute)
			local children = {}
	
			local p1 = fparam(children, 'self', fmtresource(self))
			fparam(children, 'attribute', fmtconst(attribute))

			local iret = freturn(children)

			if begin_validation() then
				verr(children, object_types[self] == 'Layout', 'Expected V3DLayout for self, got ' .. type(self))
				verr(children, type(attribute) == 'string' or type(attribute) == 'table', 'Expected string or V3DLayoutAttribute for attribute, got ' .. type(attribute))
				-- TODO: improve V3DAttributeLayout check
			end
	
			fcall {
				content = string.format('&cyan;:add_vertex_attribute&reset;(%s)',
					fmtconst(attribute)),
				content_expanded = '&cyan;:add_vertex_attribute&reset;(...)',
				children = children,
			}
	
			check_validation()
			set_layout_details(p1, self)

			local result = drop_attribute_orig(self, attribute)

			complete_layout(iret, nil, result)

			return result
		end

		-- note: we don't modify has_attribute or get_attribute

		return ly
	end

	local function complete_geometry(ret, label, gm)
		register_object(gm, 'Geometry', label)
		fcompletereturn(ret, fmtresource(gm))
		set_geometry_details(ret, gm)

		-- TODO

		return gm
	end

	local function complete_geometry_builder(ret, gb)
		register_object(gb, 'GeometryBuilder', nil)
		fcompletereturn(ret, fmtresource(gb))
		set_geometry_builder_details(ret, gb)

		-- TODO
		local append_data_orig = gb.append_data
		function gb:append_data(attribute_name, data)
			return append_data_orig(self, attribute_name, data)
		end

		local build_orig = gb.build
		function gb:build(label)
			local children = {}
	
			local p1 = fparam(children, 'self', fmtresource(self))
			fparam(children, 'label', fmtconst(label))

			local iret = freturn(children)

			if begin_validation() then
				verr(children, object_types[self] == 'GeometryBuilder', 'Expected V3DGeometryBuilder for self, got ' .. type(self))
				vwarn(children, label == nil or type(label) == 'string', 'Expected nil or string for label, got ' .. type(label))
			end
	
			fcall {
				content = string.format('&cyan;:build&reset;(%s)', fmtconst(label)),
				content_expanded = '&cyan;:build&reset;(...)',
				children = children,
			}
	
			check_validation()
			set_geometry_builder_details(p1, self)

			local result = build_orig(self, label)

			complete_geometry(iret, label, result)

			return result
		end

		-- TODO
		local cast_orig = gb.cast
		function gb:cast(layout)
			return cast_orig(self, layout)
		end

		-- TODO
		local insert_orig = gb.insert
		function gb:insert(other)
			return insert_orig(self, other)
		end

		-- TODO
		local map_orig = gb.map
		function gb:map(attribute_name, fn)
			return map_orig(self, attribute_name, fn)
		end

		-- TODO
		local set_data_orig = gb.set_data
		function gb:set_data(attribute_name, data)
			return set_data_orig(self, attribute_name, data)
		end

		-- TODO
		local transform_orig = gb.transform
		function gb:transform(attribute_name, transform)
			return transform_orig(self, attribute_name, transform)
		end


		return gb
	end

	local function complete_transform(ret, tr)
		register_object(tr, 'Transform', nil)
		fcompletereturn(ret, fmtresource(tr))
		set_transform_details(ret, tr)

		local combine_orig = tr.combine
		function tr:combine(other)
			local children = {}
	
			local p1 = fparam(children, 'self', fmtresource(self))
			local p2 = fparam(children, 'other', fmtresource(other))
			local iret = freturn(children)

			if begin_validation() then
				verr(children, object_types[self] == 'Transform', 'Expected V3DTransform for self, got ' .. type(self))
				verr(children, object_types[other] == 'Transform', 'Expected V3DTransform for other, got ' .. type(other))
			end
	
			fcall {
				content = string.format('&cyan;:combine&reset;(%s)',
					fmtresource(other)),
				content_expanded = '&cyan;:combine&reset;(...)',
				children = children,
			}
	
			check_validation()
			set_transform_details(p1, self)
			set_transform_details(p2, other)

			local result = combine_orig(self, other)

			complete_transform(iret, result)

			return result
		end

		-- TODO
		local transform_orig = tr.transform
		function tr:transform(data, translate)
			return transform_orig(data, translate)
		end

		setmetatable(tr, { __mul = tr.combine })

		return tr
	end

	local function complete_pipeline(ret, label, pi)
		register_object(pi, 'Pipeline', label)
		fcompletereturn(ret, fmtresource(pi))
		set_pipeline_details(ret, pi)

		local render_geometry_orig = pi.render_geometry
		function pi:render_geometry(geometry, framebuffer, transform, model_transform)
			local children = {}
	
			local p1 = fparam(children, 'pipeline', fmtresource(self))
			local p2 = fparam(children, 'geometry', fmtresource(geometry))
			local p3 = fparam(children, 'framebuffer', fmtresource(framebuffer))
			local p4 = fparam(children, 'transform', fmtresource(transform))
			local p5 = fparam(children, 'model_transform', fmtresource(model_transform))
			local p6 = {
				content = 'Uniforms',
				children = {},
			}

			table.insert(children, p6)

			if begin_validation() then
				verr(children, object_types[self] == 'Pipeline', 'Expected V3DPipeline for pipeline, got ' .. type(self))
				verr(children, object_types[geometry] == 'Geometry', 'Expected V3DGeometry for geometry, got ' .. type(geometry))
				verr(children, object_types[framebuffer] == 'Framebuffer', 'Expected V3DFramebuffer for framebuffer, got ' .. type(framebuffer))
				verr(children, object_types[transform] == 'Transform', 'Expected V3DTransform for transform, got ' .. type(transform))
				verr(children, model_transform == nil or object_types[model_transform] == 'Transform', 'Expected nil or V3DTransform for model_transform, got ' .. type(model_transform))
			end
	
			fcall {
				content = string.format('&cyan;:render_geometry&reset;(%s, %s, %s, %s)',
					fmtresource(geometry),
					fmtresource(framebuffer),
					fmtresource(transform),
					fmtresource(model_transform)),
				content_expanded = '&cyan;:render_geometry&reset;(...)',
				children = children,
			}

			check_validation()

			for _, u in ipairs(self:list_uniforms()) do
				fparam(p6.children, u, fmtconst(self:get_uniform(u)))
			end

			if #self:list_uniforms() == 0 then
				p6.children = nil
				p6.content = '&lightGrey;No uniform values are set!'
			end

			set_pipeline_details(p1, self)
			set_geometry_details(p2, geometry)
			set_framebuffer_details(p3, framebuffer)
			set_transform_details(p4, transform)
			if model_transform then set_transform_details(p5, model_transform) end
			render_geometry_orig(self, geometry, framebuffer, transform, model_transform)
		end

		local get_uniform_orig = pi.get_uniform
		function pi:get_uniform(name)
			assert(type(name) == 'string', 'Expected string for name, got ' .. type(name))
			return get_uniform_orig(self, name)
		end

		local set_uniform_orig = pi.set_uniform
		function pi:set_uniform(name, value)
			local children = {}
	
			local p1 = fparam(children, 'pipeline', fmtresource(self))
			fparam(children, 'name', fmtconst(name))
			fparam(children, 'value', fmtconst(value))

			if begin_validation() then
				verr(children, object_types[self] == 'Pipeline', 'Expected V3DPipeline for pipeline, got ' .. type(self))
				verr(children, type(name) == 'string', 'Expected string for name, got ' .. type(name))
			end
	
			fcall {
				content = string.format('&cyan;:set_uniform&reset;(%s, %s)',
					fmtconst(name),
					fmtconst(value)),
				content_expanded = '&cyan;:set_uniform&reset;(...)',
				children = children,
			}
	
			check_validation()
			set_pipeline_details(p1, self)
			set_uniform_orig(self, name, value)
		end

		return pi
	end

	------------------------------------------------------------

	--- @diagnostic disable: duplicate-set-field

	v3d_wrapper.CULL_BACK_FACE = v3d_lib.CULL_BACK_FACE
	v3d_wrapper.CULL_FRONT_FACE = v3d_lib.CULL_FRONT_FACE

	for _, layout_name in ipairs { 'DEFAULT_LAYOUT', 'UV_LAYOUT', 'DEBUG_CUBE_LAYOUT' } do
		local s = tostring {}
		-- take a copy of the layout in a really hacky way, then wrap it
		-- we don't wanna wrap_layout the original since that would mutate it
		local ly = v3d_lib[layout_name]:add_face_attribute(s, 0):drop_attribute(s)
		complete_layout({}, layout_name, ly) -- TODO: weird {}
		v3d_wrapper[layout_name] = ly
	end

	function v3d_wrapper.create_framebuffer(width, height, label)
		local children = {}

		fparam(children, 'width', fmtconst(width))
		fparam(children, 'height', fmtconst(height))
		fparam(children, 'label', fmtconst(label))

		local ret = freturn(children)

		if begin_validation() then
			if verr(children, type(width) == 'number', 'Width given to create framebuffer was not a number') then
				verr(children, width > 0, 'Width given to create framebuffer was <= 0')
			end
			if verr(children, type(height) == 'number', 'Height given to create framebuffer was not a number') then
				verr(children, height > 0, 'Height given to create framebuffer was <= 0')
			end
			vwarn(children, label == nil or type(label) == 'string', 'Label given to create framebuffer was not a string or nil')
		end

		fcall {
			content = string.format(
				'&cyan;create_framebuffer&reset;(%s, %s)',
				fmtconst(width),
				fmtconst(height)),
			content_expanded = '&cyan;create_framebuffer&reset;(...)',
			children = children,
		}

		check_validation()

		return complete_framebuffer(ret, label, v3d_lib.create_framebuffer(width, height))
	end

	function v3d_wrapper.create_framebuffer_subpixel(width, height, label)
		local children = {}

		fparam(children, 'width', fmtconst(width))
		fparam(children, 'height', fmtconst(height))
		fparam(children, 'label', fmtconst(label))

		local ret = freturn(children)

		if begin_validation() then
			if verr(children, type(width) == 'number', 'Width given to create framebuffer was not a number') then
				verr(children, width > 0, 'Width given to create framebuffer was <= 0')
			end
			if verr(children, type(height) == 'number', 'Height given to create framebuffer was not a number') then
				verr(children, height > 0, 'Height given to create framebuffer was <= 0')
			end
			vwarn(children, label == nil or type(label) == 'string', 'Label given to create framebuffer was not a string or nil')
		end

		fcall {
			content = string.format(
				'&cyan;create_framebuffer_subpixel&reset;(%s, %s)',
				fmtconst(width),
				fmtconst(height)),
			content_expanded = '&cyan;create_framebuffer_subpixel&reset;(...)',
			children = children,
		}

		check_validation()

		return complete_framebuffer(ret, label, v3d_lib.create_framebuffer_subpixel(width, height))
	end

	function v3d_wrapper.create_layout()
		local children = {}

		local ret = freturn(children)

		fcall {
			content = '&cyan;create_layout&reset;()',
			children = children,
		}

		return complete_layout(ret, nil, v3d_lib.create_layout())
	end

	function v3d_wrapper.create_geometry_builder(layout)
		local children = {}

		local p1 = fparam(children, 'layout', fmtresource(layout))

		local ret = freturn(children)

		if begin_validation() then
			verr(children, type(layout) == 'table', 'Layout given to create geometry builder was not a layout')
			-- TODO
		end

		fcall {
			content = string.format(
				'&cyan;create_geometry_builder&reset;(%s)',
				fmtresource(layout)),
			content_expanded = '&cyan;create_geometry_builder&reset;(...)',
			children = children,
		}

		check_validation()
		set_layout_details(p1, layout)

		return complete_geometry_builder(ret, v3d_lib.create_geometry_builder(layout))
	end

	function v3d_wrapper.create_debug_cube(cx, cy, cz, size)
		local children = {}

		fparam(children, 'cx', fmtconst(cx))
		fparam(children, 'cy', fmtconst(cy))
		fparam(children, 'cz', fmtconst(cz))
		fparam(children, 'size', fmtconst(size))

		local ret = freturn(children)

		if begin_validation() then
			verr(children, cx == nil or type(cx) == 'number', 'Centre X given to create debug cube was not a number')
			verr(children, cy == nil or type(cy) == 'number', 'Centre Y given to create debug cube was not a number')
			verr(children, cz == nil or type(cz) == 'number', 'Centre Z given to create debug cube was not a number')
			if verr(children, size == nil or type(size) == 'number', 'Size given to create debug cube was not a number') then
				vwarn(children, size == nil or size >= 0, 'Size given to create debug cube was negative or zero')
			end
		end

		fcall {
			content = string.format(
				'&cyan;create_debug_cube&reset;(%s, %s, %s, %s)',
				fmtconst(cx),
				fmtconst(cy),
				fmtconst(cz),
				fmtconst(size)),
			content_expanded = '&cyan;create_debug_cube&reset;(...)',
			children = children,
		}

		check_validation()

		return complete_geometry_builder(ret, v3d_lib.create_debug_cube(cx, cy, cz, size))
	end

	function v3d_wrapper.identity()
		local children = {}

		local ret = freturn(children)

		fcall {
			content = '&cyan;identity&reset;()',
			children = children,
		}

		return complete_transform(ret, v3d_lib.identity())
	end

	function v3d_wrapper.translate(dx, dy, dz)
		local children = {}

		fparam(children, 'dx', fmtconst(dx))
		fparam(children, 'dy', fmtconst(dy))
		fparam(children, 'dz', fmtconst(dz))

		local ret = freturn(children)

		if begin_validation() then
			verr(children, type(dx) == 'number', 'Expected number for dx, got ' .. type(dx))
			verr(children, type(dy) == 'number', 'Expected number for dy, got ' .. type(dy))
			verr(children, type(dz) == 'number', 'Expected number for dz, got ' .. type(dz))
		end

		fcall {
			content = string.format(
				'&cyan;translate&reset;(%s, %s, %s)',
				fmtconst(dx),
				fmtconst(dy),
				fmtconst(dz)),
			content_expanded = '&cyan;translate&reset;(...)',
			children = children,
		}

		check_validation()

		return complete_transform(ret, v3d_lib.translate(dx, dy, dz))
	end

	-- TODO
	function v3d_wrapper.scale(sx, sy, sz)
		local children = {}

		fparam(children, 'sx', fmtconst(sx))
		fparam(children, 'sy', fmtconst(sy))
		fparam(children, 'sz', fmtconst(sz))

		local ret = freturn(children)

		-- TODO: handle overload

		if begin_validation() then
			verr(children, type(sx) == 'number', 'Expected number for sx, got ' .. type(sx))

			if sy or sz then
				verr(children, type(sy) == 'number', 'Expected number for sy, got ' .. type(sy))
				verr(children, type(sz) == 'number', 'Expected number for sz, got ' .. type(sz))
			else
				verr(children, sy == nil and sz == nil, 'Expected number for sy and sz, got ' .. type(sy) .. ' and' .. type(sz))
			end
		end

		fcall {
			content = string.format(
				'&cyan;scale&reset;(%s, %s, %s)',
				fmtconst(sx),
				fmtconst(sy),
				fmtconst(sz)),
			content_expanded = '&cyan;scale&reset;(...)',
			children = children,
		}

		check_validation()

		return complete_transform(ret, v3d_lib.scale(sx, sy, sz))
	end

	function v3d_wrapper.rotate(rx, ry, rz)
		local children = {}

		fparam(children, 'rx', fmtconst(rx))
		fparam(children, 'ry', fmtconst(ry))
		fparam(children, 'rz', fmtconst(rz))

		local ret = freturn(children)

		if begin_validation() then
			verr(children, type(rx) == 'number', 'Expected number for rx, got ' .. type(rx))
			verr(children, type(ry) == 'number', 'Expected number for ry, got ' .. type(ry))
			verr(children, type(rz) == 'number', 'Expected number for rz, got ' .. type(rz))
		end

		fcall {
			content = string.format(
				'&cyan;rotate&reset;(%s, %s, %s)',
				fmtconst(rx),
				fmtconst(ry),
				fmtconst(rz)),
			content_expanded = '&cyan;rotate&reset;(...)',
			children = children,
		}

		check_validation()

		return complete_transform(ret, v3d_lib.rotate(rx, ry, rz))
	end

	-- TODO
	function v3d_wrapper.camera(x, y, z, rx, ry, rz, fov)
		local children = {}

		-- fparam(children, 'cx', fmtconst(cx))
		-- fparam(children, 'cy', fmtconst(cy))
		-- fparam(children, 'cz', fmtconst(cz))
		-- fparam(children, 'size', fmtconst(size))

		-- TODO: handle overload

		local ret = freturn(children)

		if begin_validation() then
			
		end

		fcall {
			content = string.format(
				'&cyan;camera&reset;(%s, %s, %s, %s, %s, %s, %s)',
				fmtconst(x),
				fmtconst(y),
				fmtconst(z),
				fmtconst(rx),
				fmtconst(ry),
				fmtconst(rz),
				fmtconst(fov)),
			content_expanded = '&cyan;camera&reset;(...)',
			children = children,
		}

		check_validation()

		return complete_transform(ret, v3d_lib.camera(x, y, z, rx, ry, rz, fov))
	end

	function v3d_wrapper.create_pipeline(options, label)
		local children = {}

		local p1 = fparam(children, 'options', fmtconst(options))
		fparam(children, 'label', fmtconst(label))

		local ret = freturn(children)

		if begin_validation() then
			if verr(children, type(options) == 'table', 'Expected table options, got ' .. type(options)) then
				verr(children, options.attributes == nil or type(options.attributes) == 'table', 'Expected nil or table for options.attributes, got ' .. type(options.attributes))
				verr(children, options.colour_attribute == nil or type(options.colour_attribute) == 'string', 'Expected nil or string for options.colour_attribute, got ' .. type(options.colour_attribute))
				verr(children, options.cull_face == nil or options.cull_face == false or options.cull_face == v3d_lib.CULL_BACK_FACE or options.cull_face == v3d_lib.CULL_FRONT_FACE, 'Expected false or V3DCullFace for options.cull_face, got ' .. type(options.cull_face))
				verr(children, options.depth_store == nil or type(options.depth_store) == 'boolean', 'Expected nil or boolean for options.depth_store, got ' .. type(options.depth_store))
				verr(children, options.depth_test == nil or type(options.depth_test) == 'boolean', 'Expected nil or boolean for options.depth_test, got ' .. type(options.depth_test))
				verr(children, options.fragment_shader == nil or type(options.fragment_shader) == 'function', 'Expected nil or function for options.fragment_shader, got ' .. type(options.fragment_shader))
				verr(children, type(options.layout) == 'table', 'Expected V3DLayout for options.layout, got ' .. type(options.layout))
				verr(children, object_types[options.layout] == 'Layout', 'Expected V3DLayout for options.layout, got some other table')
				verr(children, options.pack_attributes == nil or type(options.pack_attributes) == 'boolean', 'Expected nil or boolean for options.pack_attributes, got ' .. type(options.pack_attributes))
				verr(children, options.pixel_aspect_ratio == nil or type(options.pixel_aspect_ratio) == 'number', 'Expected nil or number for options.pixel_aspect_ratio, got ' .. type(options.pixel_aspect_ratio))
				verr(children, options.position_attribute == nil or type(options.position_attribute) == 'string', 'Expected nil or string for options.position_attribute, got ' .. type(options.position_attribute))

				vwarn(children, not options.fragment_shader or not options.colour_attribute, 'Both options.colour_attribute and options.fragment_shader were set, but only one will be used')
				vwarn(children, options.fragment_shader or options.colour_attribute, 'Either options.colour_attribute or options.fragment_shader should be set')
			end

			vwarn(children, label == nil or type(label) == 'string', 'Expected nil or string for label, got ' .. type(label))
		end

		fcall {
			content = string.format(
				'&cyan;create_pipeline&reset;({...}, %s)', fmtconst(label)),
			content_expanded = '&cyan;create_pipeline&reset;(...)',
			children = children,
		}

		check_validation()

		p1.children = p1.children or {}
		set_layout_details(fparam(p1.children, 'layout', fmtresource(options.layout)), options.layout)
		fparam(p1.children, 'attributes', fmtconst(options.attributes))
		fparam(p1.children, 'colour_attribute', fmtconst(options.colour_attribute))
		fparam(p1.children, 'cull_face', fmtconst(options.cull_face))
		fparam(p1.children, 'depth_store', fmtconst(options.depth_store))
		fparam(p1.children, 'depth_test', fmtconst(options.depth_test))
		fparam(p1.children, 'fragment_shader', fmtconst(options.fragment_shader))
		fparam(p1.children, 'pack_attributes', fmtconst(options.pack_attributes))
		fparam(p1.children, 'pixel_aspect_ratio', fmtconst(options.pixel_aspect_ratio))
		fparam(p1.children, 'position_attribute', fmtconst(options.position_attribute))

		return complete_pipeline(ret, label, v3d_lib.create_pipeline(options, label))
	end

	-- TODO
	v3d_wrapper.create_texture_sampler = v3d_lib.create_texture_sampler

	--- @diagnostic enable: duplicate-set-field

	return {
		library = v3d_wrapper,
		begin_frame = function()
			blit_called = false
			call_tree_children = {}
		end,
		finish_frame = function()
			return blit_called, call_tree_children
		end,
	}
end

----------------------------------------------------------------

local v3d_wrapper = create_v3d_wrapper(validation_enabled)
program_environment.package.loaded['/v3d'] = v3d_wrapper.library
program_environment.package.loaded['v3d'] = v3d_wrapper.library
program_environment.package.loaded[v3d_require_path] = v3d_wrapper.library

--------------------------------------------------------------------------------

--- @alias RichTextSegments { text: string, colour: integer }[]

--- @class TreeItem
--- @field tree Tree
--- @field expanded boolean
--- @field previous_peer integer | nil
--- @field next_expanded integer
--- @field next_contracted integer
--- @field last_child integer
--- @field indent integer

--- @param items TreeItem[]
--- @param tree Tree
--- @param previous_peer integer | nil
--- @param indent integer
local function tree_to_items(items, tree, previous_peer, indent)
	local seq = {
		tree = tree,
		expanded = tree.default_expanded or false,
		previous_peer = previous_peer,
		next_expanded = #items + 2,
		-- note: deliberately incomplete! we finish this at the end of the function
		indent = indent,
	}
	table.insert(items, seq)
	local previous_peer = nil
	if tree.children then
		for i = 1, #tree.children do
			local next_previous_peer = #items + 1
			tree_to_items(items, tree.children[i], previous_peer, indent + 1)
			previous_peer = next_previous_peer
		end
	end
	seq.next_contracted = #items + 1
	seq.last_child = previous_peer
end

--- @param content string
--- @param initial_colour integer
--- @return RichTextSegments
local function rich_content_to_segments(content, initial_colour)
	local segments = {}
	local active_color = initial_colour

	local next_index = 1
	local s, f = content:find '&[%w_]+;'

	while s do
		table.insert(segments, { text = content:sub(next_index, s - 1), colour = active_color })

		local name = content:sub(s + 1, f - 1)

		if name == 'reset' then
			active_color = initial_colour
		else
			if not colours[name] and not colors[name] then error('Unknown colour: ' .. name) end
			active_color = colours[name] or colors[name]
		end

		next_index = f + 1
		s, f = content:find('&[%w_]+;', next_index)
	end

	table.insert(segments, { text = content:sub(next_index), colour = active_color })

	return segments
end

--- @param segments RichTextSegments
--- @return integer
local function segments_length(segments)
	local length = 0

	for i = 1, #segments do
		length = length + #segments[i].text
	end

	return length
end

--- @param segments RichTextSegments
--- @param length integer
--- @return RichTextSegments
local function trim_segments_left(segments, length)
	return segments -- TODO
end

--- @param segments RichTextSegments
--- @param length integer
--- @return RichTextSegments
local function trim_segments_right(segments, length)
	local r = {}
	local r_length = 0

	for i = 1, #segments do
		r[i] = segments[i]
		r_length = r_length + #segments[i].text

		if r_length > length then
			break
		end
	end

	if r_length > length then
		r[#r].text = r[#r].text:sub(1, #r[#r].text - r_length + length)
	end

	return r
end

--- @param trees Tree[]
local function present_capture(trees)
	local palette = {}
	do -- setup
		term.setBackgroundColour(colours.black)
		term.setTextColour(colours.white)
		term.clear()
		term.setCursorPos(1, 1)

		for i = 0, 15 do
			palette[i + 1] = { term.getPaletteColour(2 ^ i) }
		end

		for i = 0, 15 do
			term.setPaletteColour(2 ^ i, term.nativePaletteColour(2 ^ i))
		end

		term.setPaletteColour(colours.white, 0.95, 0.95, 0.95)
		term.setPaletteColour(colours.grey, 0.2, 0.2, 0.2)
		term.setPaletteColour(colours.lightGrey, 0.6, 0.6, 0.6)
		term.setPaletteColour(colours.purple, 0.45, 0.25, 0.55)
	end

	local timers_captured = {}

	--- @class CaptureViewModel
	local model = {
		items = {},
		selected_item = 1,
	}

	local previous_peer = 0
	for i = 1, #trees do
		local next_previous_peer = #model.items + 1
		tree_to_items(model.items, trees[i], previous_peer, 0)
		previous_peer = next_previous_peer
	end

	--- @param t CaptureViewModel
	local function update_model(t, m)
		m = m or model
		for k, v in pairs(t) do
			if type(v) == 'table' then
				if m[k].__value then
					m[k] = v
					v.__value = true
				else
					update_model(v, m[k])
				end
			else
				m[k] = v
			end
		end
	end

	--- @param item TreeItem
	--- @param y integer
	--- @return integer next_y, integer next_index
	local function redraw_tree_item(item, selected, x, y, w, by, bh)
		local initial_colour = colours.white
		local is_expanded = item.expanded
		local left = rich_content_to_segments(
			is_expanded and item.tree.content_expanded or item.tree.content or '',
			initial_colour)
		local right = rich_content_to_segments(
			is_expanded and item.tree.content_right_expanded or item.tree.content_right or '',
			initial_colour)
		local right_anchor = x + w
		local left_max_width = w

		if selected then
			term.setBackgroundColour(colours.black)
			term.setCursorPos(x, y)
			term.write((' '):rep(w))
		else
			term.setBackgroundColour(colours.grey)
		end

		x = x + item.indent * 2
		w = w - item.indent * 2

		if item.tree.children then
			table.insert(left, 1, { text = is_expanded and 'v ' or '> ', colour = colours.lightGrey })
		elseif item.tree.on_select then
			left_max_width = left_max_width - 2
			table.insert(left, 1, { text = '| ', colour = colours.lightGrey })
			table.insert(right, { text = ' >', colour = colours.purple })
		else
			table.insert(left, 1, { text = '| ', colour = colours.lightGrey })
		end

		if y >= by and y < by + bh then
			right = trim_segments_left(right, w)
			term.setCursorPos(right_anchor - segments_length(right), y)

			for _, segment in ipairs(right) do
				term.setTextColour(segment.colour)
				term.write(segment.text)
			end

			term.setCursorPos(x, y)
			left = trim_segments_right(left, left_max_width)

			for _, segment in ipairs(left) do
				term.setTextColour(segment.colour)
				term.write(segment.text)
			end

			y = y + 1
		end

		return y, item.expanded and item.next_expanded or item.next_contracted
	end

	local function redraw()
		local width, height = term.getSize()

		term.setBackgroundColour(colours.grey)
		term.clear()

		local y = 4
		local index = 1

		while y < height - 1 and model.items[index] do
			y, index = redraw_tree_item(model.items[index], index == model.selected_item, 2, y, width - 2, 4, height - 4)
		end
	end

	while true do
		redraw()

		local event = { coroutine.yield() }

		if event[1] == 'terminate' then
			return false, timers_captured
		elseif event[1] == 'timer' then
			table.insert(timers_captured, event[2])
		elseif event[1] == 'key' and event[2] == keys.backspace then
			break
		elseif event[1] == 'key' and (event[2] == keys.space or event[2] == keys.enter) then
			if model.items[model.selected_item].tree.children then
				model.items[model.selected_item].expanded = not model.items[model.selected_item].expanded
			elseif model.items[model.selected_item].tree.on_select then
				model.items[model.selected_item].tree.on_select()
			end
		elseif event[1] == 'key' and event[2] == keys.down then
			local current_item = model.items[model.selected_item]
			local next_index = current_item.expanded and current_item.next_expanded or current_item.next_contracted
			
			if model.items[next_index] then
				update_model { selected_item = next_index }
			end
		elseif event[1] == 'key' and event[2] == keys.up then
			local next_index = model.items[model.selected_item].previous_peer
			
			if next_index and model.items[next_index] then
				while model.items[next_index].expanded do
					next_index = model.items[next_index].last_child
				end

				update_model { selected_item = next_index }
			elseif model.items[model.selected_item - 1] then
				update_model { selected_item = model.selected_item - 1 }
			end
		elseif event[1] == 'key' and (event[2] == keys.left or event[2] == keys.right) then
			
		elseif event[1] == 'term_resize' then
			
		end
	end

	for i = 0, 15 do
		term.setPaletteColour(2 ^ i, table.unpack(palette[i + 1]))
	end

	return true, timers_captured
end

--------------------------------------------------------------------------------

local currentTime = os.clock

if ccemux then
	function currentTime()
		return ccemux.nanoTime() / 1000000000
	end
end

local event_queue = {}
local event = args
local filter = nil
local program_co = coroutine.create(program_fn)
local last_frame = currentTime()
local fps_avg = 0
local frame_time_avg = 0
local avg_samples = 10
local last_capture_trees = nil

local function begin_frame()
	v3d_wrapper.begin_frame()
end

local function finish_frame()
	return v3d_wrapper.finish_frame()
end

while true do
	if filter == nil or event[1] == filter then
		begin_frame()
		local start_time = currentTime()
		local ok, err = coroutine.resume(program_co, table.unpack(event))
		local this_frame = currentTime()
		local delta_time = this_frame - last_frame
		last_frame = this_frame

		local did_blit, lct = finish_frame()
		last_capture_trees = lct

		if did_blit then
			fps_avg = (fps_avg * avg_samples + 1 / delta_time) / (avg_samples + 1)
			frame_time_avg = (frame_time_avg * avg_samples + this_frame - start_time) / (avg_samples + 1)
		end

		if fps_enabled then
			term.setBackgroundColour(fps_bc)
			term.setTextColour(fps_fc)
			term.setCursorPos(1, 1)
			term.write(string.format('%.01ffps %.01fms <%.01ffps', fps_avg, frame_time_avg * 1000, 1 / frame_time_avg))
		end

		if not ok then
			present_capture {
				{ content = 'Capture', children = last_capture_trees, default_expanded = false, },
				{ content = 'Error', children = {
					{ content = tostring(err) }
				}, default_expanded = true, }
			}
			return
		elseif coroutine.status(program_co) == 'dead' then
			if capture_first_frame then
				present_capture {
					{ content = 'Capture', children = last_capture_trees, default_expanded = true, },
				}
			end
			break
		else
			filter = err
		end
	end

	event = table.remove(event_queue, 1) or { coroutine.yield() }

	if (event[1] == 'key' and event[2] == capture_key) or capture_first_frame then
		local cont, timers = present_capture {
			{ content = 'Capture', children = last_capture_trees, default_expanded = true, },
		}
		if not cont then
			break
		end
		for i = 1, #timers do
			table.insert(event_queue, { 'timer', timers[i] })
		end
		capture_first_frame = false
	elseif event[1] == 'terminate' then
		break
	end
end
