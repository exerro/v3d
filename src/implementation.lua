
-- TODO
-- hello future Ben
-- here's what's gonna happen:
-- fuck passing functions in as shaders
-- everything's gonna be a string
-- it can autogenerate the string if not provided
-- you also need to handle depth buffer separately
-- and s/_v3d_va_attributes/attributes/
-- basically just finish off the pipeline generation stuff

-- #remove
-- note: this code will be stripped out during the build process, thus removing
--       the error
error 'Cannot use v3d source code, must build the library'
-- #end
--- @type v3d
local v3d = {}


--- @return any
local function v3d_internal_error(message, context)
	local traceback
	pcall(function()
		traceback = debug and debug.traceback and debug.traceback()
	end)
	local error_message = 'V3D INTERNAL ERROR: '
	                   .. tostring(message == nil and '' or message)
	                   .. (traceback and '\n' .. traceback or '')
	pcall(function()
		local h = io.open('.v3d_crash_dump.txt', 'w')
		if h then
			h:write(context and context .. '\n' .. error_message or error_message)
			h:close()
		end
	end)
	error(error_message, 0)
end


--------------------------------------------------------------------------------
--[ String templating functions ]-----------------------------------------------
--------------------------------------------------------------------------------


local function _string_quote(s)
	return '\'' .. (s:gsub('[\\\'\n\t]', { ['\\'] = '\\\\', ['\''] = '\\\'', ['\n'] = '\\n', ['\t'] = '\\t' })) .. '\''
end

local function _xpcall_handler(...)
	return debug.traceback(...)
end

local function v3d_generate_template(template, context)
	local env = {}

	env._G = env
	env._VERSION = _VERSION
	env.assert = assert
	env.error = error
	env.getmetatable = getmetatable
	env.ipairs = ipairs
	env.load = load
	env.next = next
	env.pairs = pairs
	env.pcall = pcall
	env.print = print
	env.rawequal = rawequal
	env.rawget = rawget
	env.rawlen = rawlen
	env.rawset = rawset
	env.select = select
	env.setmetatable = setmetatable
	env.tonumber = tonumber
	env.tostring = tostring
	env.type = type
	env.xpcall = xpcall
	env.math = math
	env.string = string
	env.table = table

	env.quote = _string_quote

	for k, v in pairs(context) do
		env[k] = v
	end

	local write_content = {}

	write_content[1] = 'local _text_segments = {}'
	write_content[2] = 'local _table_insert = table.insert'

	while true do
		local s, f, indent, text, operator = ('\n' .. template):find('\n([\t ]*)([^\n{]*){([%%=#!])')
		if s then
			local close = template:find( (operator == '%' and '%' or '') .. operator .. '}', f)
			           or error('Missing end to \'{' .. operator .. '\': expected a matching \'' .. operator .. '}\'', 2)

			local pre_text = template:sub(1, s - 1 + #indent + #text)
			local content = template:sub(f + 1, close - 1):gsub('^%s+', ''):gsub('%s+$', '')

			if #pre_text > 0 then
				table.insert(write_content, '_table_insert(_text_segments, ' .. _string_quote(pre_text) .. ')')
			end
			template = template:sub(close + 2)

			if operator == '=' then
				table.insert(write_content, '_table_insert(_text_segments, tostring(' .. content .. '))')
			elseif operator == '%' then
				table.insert(write_content, content)
			elseif operator == '!' then
				local f, err = load('return ' .. content, content, nil, env)
				if not f then f, err = load(content, content, nil, env) end
				if not f then error('Invalid {!!} section (syntax): ' .. err .. '\n    ' .. content, 2) end
				local ok, result = xpcall(f, _xpcall_handler)
				if not ok then error('Invalid {!!} section (runtime):\n' .. result, 2) end
				if type(result) ~= 'string' then
					error('Invalid {!!} section (return): not a string (got ' .. type(result) .. ')\n' .. content, 2)
				end
				template = result:gsub('\n', '\n' .. indent) .. template
			elseif operator == '#' then
				-- do nothing, it's a comment
			end
		else
			table.insert(write_content, '_table_insert(_text_segments, ' .. _string_quote(template) .. ')')
			break
		end
	end

	table.insert(write_content, 'return table.concat(_text_segments)')

	local code = table.concat(write_content, '\n')
	local f, err = load(code, 'template string', nil, env)
	if not f then error('Invalid template builder (syntax): ' .. err, 2) end
	local ok, result = xpcall(f, _xpcall_handler)
	if not ok then error('Invalid template builder section (runtime):\n' .. result, 2) end

	return result
end


--------------------------------------------------------------------------------
--[ Subpixel lookup tables ]----------------------------------------------------
--------------------------------------------------------------------------------


local CH_SPACE = string.byte ' '
local CH_0 = string.byte '0'
local CH_A = string.byte 'a'
local CH_SUBPIXEL_NOISEY = 149
local colour_byte_lookup = {}
local subpixel_code_ch_lookup = {}
local subpixel_code_fg_lookup = {}
local subpixel_code_bg_lookup = {}

-- Code for pre-generating the lookup tables above
do
	for i = 0, 15 do
		colour_byte_lookup[2 ^ i] = i < 10 and CH_0 + i or CH_A + (i - 10)
	end

	local function subpixel_byte_value(v0, v1, v2, v3, v4, v5)
		local b0 = v0 == v5 and 0 or 1
		local b1 = v1 == v5 and 0 or 1
		local b2 = v2 == v5 and 0 or 1
		local b3 = v3 == v5 and 0 or 1
		local b4 = v4 == v5 and 0 or 1

		return 128 + b0 + b1 * 2 + b2 * 4 + b3 * 8 + b4 * 16
	end

	local function eval_subpixel_lookups(ci0, ci1, ci2, ci3, ci4, ci5, subpixel_code)
		local colour_count = { [ci0] = 1 }
		local unique_colour_values = { ci0 }
		local unique_colours = 1

		for _, c in ipairs { ci1, ci2, ci3, ci4, ci5 } do
			if colour_count[c] then
				colour_count[c] = colour_count[c] + 1
			else
				colour_count[c] = 1
				unique_colours = unique_colours + 1
				unique_colour_values[unique_colours] = c
			end
		end

		table.sort(unique_colour_values, function(a, b)
			return colour_count[a] > colour_count[b]
		end)

		if unique_colours == 1 then -- these should never be used!
			subpixel_code_ch_lookup[subpixel_code] = false
			subpixel_code_fg_lookup[subpixel_code] = false
			subpixel_code_bg_lookup[subpixel_code] = false
			return
		end

		local colour_indices = { ci0, ci1, ci2, ci3, ci4, ci5 }
		local modal1_colour_index = unique_colour_values[1]
		local modal2_colour_index = unique_colour_values[2]
		local modal1_index = 0
		local modal2_index = 0

		for i = 1, 6 do
			if colour_indices[i] == modal1_colour_index then
				modal1_index = i
			end
			if colour_indices[i] == modal2_colour_index then
				modal2_index = i
			end
		end

		-- spatially map pixels!
		ci0 = (ci0 == modal1_colour_index or ci0 == modal2_colour_index) and ci0 or (ci1 == modal1_colour_index or ci1 == modal2_colour_index) and ci1 or ci2
		ci1 = (ci1 == modal1_colour_index or ci1 == modal2_colour_index) and ci1 or (ci0 == modal1_colour_index or ci0 == modal2_colour_index) and ci0 or ci3
		ci2 = (ci2 == modal1_colour_index or ci2 == modal2_colour_index) and ci2 or (ci3 == modal1_colour_index or ci3 == modal2_colour_index) and ci3 or ci4
		ci3 = (ci3 == modal1_colour_index or ci3 == modal2_colour_index) and ci3 or (ci2 == modal1_colour_index or ci2 == modal2_colour_index) and ci2 or ci5
		ci4 = (ci4 == modal1_colour_index or ci4 == modal2_colour_index) and ci4 or (ci5 == modal1_colour_index or ci5 == modal2_colour_index) and ci5 or ci2
		ci5 = (ci5 == modal1_colour_index or ci5 == modal2_colour_index) and ci5 or (ci4 == modal1_colour_index or ci4 == modal2_colour_index) and ci4 or ci3
		subpixel_code_ch_lookup[subpixel_code] = subpixel_byte_value(ci0, ci1, ci2, ci3, ci4, ci5)
		subpixel_code_fg_lookup[subpixel_code] = ci5 == modal1_colour_index and modal2_index or modal1_index
		subpixel_code_bg_lookup[subpixel_code] = ci5 == modal1_colour_index and modal1_index or modal2_index
	end

	local subpixel_code = 0
	for c5 = 0, 3 do
		for c4 = 0, 3 do
			for c3 = 0, 3 do
				for c2 = 0, 3 do
					for c1 = 0, 3 do
						for c0 = 0, 3 do
							eval_subpixel_lookups(c0, c1, c2, c3, c4, c5, subpixel_code)
							subpixel_code = subpixel_code + 1
						end
					end
				end
			end
		end
	end
end


--------------------------------------------------------------------------------
--[ Layout functions ]----------------------------------------------------------
--------------------------------------------------------------------------------


local function layout_add_layer(layout, name, type, components)
	local new_layer = {}

	new_layer.name = name
	new_layer.type = type
	new_layer.components = components

	--- @type table
	local new_layout = v3d.create_layout()

	for i = 1, #layout.layers do
		new_layout.layers[i] = layout.layers[i]
		new_layout.layer_lookup[layout.layers[i].name] = i
	end

	table.insert(new_layout.layers, new_layer)
	new_layout.layer_lookup[name] = #new_layout.layers

	return new_layout
end

local function layout_drop_layer(layout, layer)
	if not layout:has_layer(layer) then return layout end
	local layer_name = layer.name or layer

	local new_layout = v3d.create_layout()

	for i = 1, #layout.layers do
		local layer = layout.layers[i]
		if layer.name ~= layer_name then
			new_layout = layout_add_layer(new_layout, layer.name, layer.type, layer.components)
		end
	end

	return new_layout
end

local function layout_has_layer(layout, layer)
	if type(layer) == 'table' then
		local index = layout.layer_lookup[layer.name]
		if not index then return false end
		return layout.layers[index].type == layer.type
		   and layout.layers[index].components == layer.components
	end

	return layout.layer_lookup[layer] ~= nil
end

local function layout_get_layer(layout, name)
	local index = layout.layer_lookup[name]
	return index and layout.layers[index]
end


--------------------------------------------------------------------------------
--[ Framebuffer functions ]-----------------------------------------------------
--------------------------------------------------------------------------------


local layer_defaults = {
	['palette-index'] = 0,
	['exp-palette-index'] = 1,
	['depth-reciprocal'] = 0,
	['any-numeric'] = 0,
	['any'] = 0,
}

local function framebuffer_get_buffer(fb, layer)
	return fb.layer_data[layer]
end

local function framebuffer_clear(fb, layer, value)
	local data = fb.layer_data[layer]
	local l = fb.layout:get_layer(layer)

	if value == nil then
		value = layer_defaults[l.type] or v3d_internal_error('no default for layer type ' .. l.type)
	end

	for i = 1, fb.width * fb.height * l.components do
		data[i] = value
	end
end

local function framebuffer_blit_term_subpixel(fb, term, layer, dx, dy)
	dx = dx or 0
	dy = dy or 0

	local SUBPIXEL_WIDTH = 2
	local SUBPIXEL_HEIGHT = 3

	local fb_colour, fb_width = fb.layer_data[layer], fb.width

	local xBlit = 1 + dx

	--- @diagnostic disable-next-line: deprecated
	local table_unpack = table.unpack
	local string_char = string.char
	local term_blit = term.blit
	local term_setCursorPos = term.setCursorPos

	local i0 = 1
	local ch_t = {}
	local fg_t = {}
	local bg_t = {}

	local ixMax = fb_width / SUBPIXEL_WIDTH

	for yBlit = 1 + dy, fb.height / SUBPIXEL_HEIGHT + dy do
		for ix = 1, ixMax do
			local i1 = i0 + fb_width
			local i2 = i1 + fb_width
			local c00, c10 = fb_colour[i0], fb_colour[i0 + 1]
			local c01, c11 = fb_colour[i1], fb_colour[i1 + 1]
			local c02, c12 = fb_colour[i2], fb_colour[i2 + 1]

			-- TODO: make this a massive decision tree?
			-- no!
			-- if two middle pixels are equal, that's a guaranteed colour

			local unique_colour_lookup = { [c00] = 0 }
			local unique_colours = 1

			if c01 ~= c00 then
				unique_colour_lookup[c01] = unique_colours
				unique_colours = unique_colours + 1
			end
			if not unique_colour_lookup[c02] then
				unique_colour_lookup[c02] = unique_colours
				unique_colours = unique_colours + 1
			end
			if not unique_colour_lookup[c10] then
				unique_colour_lookup[c10] = unique_colours
				unique_colours = unique_colours + 1
			end
			if not unique_colour_lookup[c11] then
				unique_colour_lookup[c11] = unique_colours
				unique_colours = unique_colours + 1
			end
			if not unique_colour_lookup[c12] then
				unique_colour_lookup[c12] = unique_colours
				unique_colours = unique_colours + 1
			end

			if unique_colours == 2 then
				local other_colour = c02

				    if c00 ~= c12 then other_colour = c00
				elseif c10 ~= c12 then other_colour = c10
				elseif c01 ~= c12 then other_colour = c01
				elseif c11 ~= c12 then other_colour = c11
				end

				local subpixel_ch = 128

				if c00 ~= c12 then subpixel_ch = subpixel_ch + 1 end
				if c10 ~= c12 then subpixel_ch = subpixel_ch + 2 end
				if c01 ~= c12 then subpixel_ch = subpixel_ch + 4 end
				if c11 ~= c12 then subpixel_ch = subpixel_ch + 8 end
				if c02 ~= c12 then subpixel_ch = subpixel_ch + 16 end

				ch_t[ix] = subpixel_ch
				fg_t[ix] = colour_byte_lookup[other_colour]
				bg_t[ix] = colour_byte_lookup[c12]
			elseif unique_colours == 1 then
				ch_t[ix] = CH_SPACE
				fg_t[ix] = CH_0
				bg_t[ix] = colour_byte_lookup[c00]
			elseif unique_colours > 4 then -- so random that we're gonna just give up lol
				ch_t[ix] = CH_SUBPIXEL_NOISEY
				fg_t[ix] = colour_byte_lookup[c01]
				bg_t[ix] = colour_byte_lookup[c00]
			else
				local colours = { c00, c10, c01, c11, c02, c12 }
				local subpixel_code = unique_colour_lookup[c12] * 1024
				                    + unique_colour_lookup[c02] * 256
				                    + unique_colour_lookup[c11] * 64
				                    + unique_colour_lookup[c01] * 16
				                    + unique_colour_lookup[c10] * 4
				                    + unique_colour_lookup[c00]

				ch_t[ix] = subpixel_code_ch_lookup[subpixel_code]
				fg_t[ix] = colour_byte_lookup[colours[subpixel_code_fg_lookup[subpixel_code]]]
				bg_t[ix] = colour_byte_lookup[colours[subpixel_code_bg_lookup[subpixel_code]]]
			end

			i0 = i0 + SUBPIXEL_WIDTH
		end

		term_setCursorPos(xBlit, yBlit)
		term_blit(string_char(table_unpack(ch_t)), string_char(table_unpack(fg_t)), string_char(table_unpack(bg_t)))
		i0 = i0 + fb_width * 2
	end
end

local function framebuffer_blit_graphics(fb, term, layer, dx, dy)
	local lines = {}
	local index = 1
	local fb_colour = fb.layer_data[layer]
	local fb_width = fb.width
	local string_char = string.char
	local table_concat = table.concat
	local math_floor = math.floor
	local math_log = math.log
	local function convert_pixel(n) return math_floor(math_log(n + 0.5, 2)) end

	if term.getGraphicsMode() == 2 then
		convert_pixel = function(n) return n end
	end

	dx = dx or 0
	dy = dy or 0

	for y = 1, fb.height do
		local line = {}

		for x = 1, fb_width do
			if not pcall(string_char, convert_pixel(fb_colour[index])) then error(fb_colour[index]) end
			line[x] = string_char(convert_pixel(fb_colour[index]))
			index = index + 1
		end

		lines[y] = table_concat(line)
	end

	term.drawPixels(dx, dy, lines)
end


--------------------------------------------------------------------------------
--[ Format functions ]----------------------------------------------------------
--------------------------------------------------------------------------------


local function format_add_attribute(format, name, size, type, is_numeric)
	local attr = {}

	attr.name = name
	attr.size = size
	attr.type = type
	attr.is_numeric = is_numeric
	attr.offset = type == 'vertex' and format.vertex_stride or format.face_stride

	--- @type table
	local new_format = v3d.create_format()

	for i = 1, #format.attributes do
		new_format.attributes[i] = format.attributes[i]
		new_format.attribute_lookup[format.attributes[i].name] = i
	end

	table.insert(new_format.attributes, attr)
	new_format.attribute_lookup[name] = #new_format.attributes

	if type == 'vertex' then
		new_format.vertex_stride = format.vertex_stride + size
		new_format.face_stride = format.face_stride
	else
		new_format.vertex_stride = format.vertex_stride
		new_format.face_stride = format.face_stride + size
	end

	return new_format
end

local function format_add_vertex_attribute(format, name, size, is_numeric)
	return format_add_attribute(format, name, size, 'vertex', is_numeric)
end

local function format_add_face_attribute(format, name, size)
	return format_add_attribute(format, name, size, 'face', false)
end

local function format_drop_attribute(format, attribute)
	if not format:has_attribute(attribute) then return format end
	local attribute_name = attribute.name or attribute

	local new_format = v3d.create_format()

	for i = 1, #format.attributes do
		local attr = format.attributes[i]
		if attr.name ~= attribute_name then
			new_format = format_add_attribute(new_format, attr.name, attr.size, attr.type, attr.is_numeric)
		end
	end

	return new_format
end

local function format_has_attribute(format, attribute)
	if type(attribute) == 'table' then
		local index = format.attribute_lookup[attribute.name]
		if not index then return false end
		return format.attributes[index].size == attribute.size
		   and format.attributes[index].type == attribute.type
		   and format.attributes[index].is_numeric == attribute.is_numeric
	end

	return format.attribute_lookup[attribute] ~= nil
end

local function format_get_attribute(format, name)
	local index = format.attribute_lookup[name]
	return index and format.attributes[index]
end


--------------------------------------------------------------------------------
--[ Geometry functions ]--------------------------------------------------------
--------------------------------------------------------------------------------


local function geometry_to_builder(geometry)
	local gb = v3d.create_geometry_builder(geometry.format)

	-- TODO
	error 'NYI'

	return gb
end

local function geometry_builder_set_data(gb, attribute_name, data)
	gb.attribute_data[attribute_name] = data

	return gb
end

local function geometry_builder_append_data(gb, attribute_name, data)
	local existing_data = gb.attribute_data[attribute_name] or {}

	gb.attribute_data[attribute_name] = existing_data

	for i = 1, #data do
		table.insert(existing_data, data[i])
	end

	return gb
end

local function geometry_builder_map(gb, attribute_name, fn)
	local size = gb.format:get_attribute(attribute_name).size
	local data = gb.attribute_data[attribute_name]

	for i = 0, #data - 1, size do
		local unmapped = {}
		for j = 1, size do
			unmapped[j] = data[i + j]
		end
		local mapped = fn(unmapped)
		for j = 1, size do
			data[i + j] = mapped[j]
		end
	end

	return gb
end

local function geometry_builder_transform(gb, attribute_name, transform, translate)
	local attr_size = gb.format:get_attribute(attribute_name).size
	local tr_fn = transform.transform

	if translate == nil and attr_size ~= 4 then
		translate = true
	end

	local data = gb.attribute_data[attribute_name]
	local vertex_data = {}

	for i = 1, #data, attr_size do
		local translate_this = translate == nil and data[i + 3] == 1 or translate or false
		vertex_data[1] = data[i]
		vertex_data[2] = data[i + 1]
		vertex_data[3] = data[i + 2]
		local result = tr_fn(transform, vertex_data, translate_this)
		data[i] = result[1]
		data[i + 1] = result[2]
		data[i + 2] = result[3]
	end

	return gb
end

local function geometry_builder_insert(gb, other)
	for i = 1, #gb.format.attributes do
		local attr = gb.format.attributes[i]
		local self_data = gb.attributes_data[attr.name]
		local other_data = other.attributes_data[attr.name]
		local offset = #self_data

		for j = 1, #other_data do
			self_data[j + offset] = other_data[j]
		end
	end

	gb.vertices = gb.vertices + other.vertices
	gb.faces = gb.faces + other.faces

	return gb
end

local function geometry_builder_cast(gb, format)
	gb.format = format
	return gb
end

local function geometry_builder_build(gb, label)
	local geometry = {}
	local format = gb.format

	geometry.format = format
	geometry.vertices = 0
	geometry.faces = 0

	geometry.to_builder = geometry_to_builder

	for i = 1, #format.attributes do
		local attr = format.attributes[i]
		local data = gb.attribute_data[attr.name]

		if attr.type == 'vertex' then
			geometry.vertices = #data / attr.size
		else
			geometry.faces = #data / attr.size
		end
	end

	geometry.vertex_offset = format.face_stride * geometry.faces

	for i = 1, #format.attributes do
		local attr = format.attributes[i]
		local data = gb.attribute_data[attr.name]
		local base_offset = attr.offset
		local stride = 0
		local count = 0

		if attr.type == 'vertex' then
			base_offset = base_offset + geometry.vertex_offset
			stride = format.vertex_stride
			count = geometry.vertices
		else
			stride = format.face_stride
			count = geometry.faces
		end

		for j = 0, count - 1 do
			local this_offset = base_offset + stride * j
			local data_offset = attr.size * j

			for k = 1, attr.size do
				geometry[this_offset + k] = data[data_offset + k]
			end
		end
	end

	return geometry
end


--------------------------------------------------------------------------------
--[ Transform functions ]-------------------------------------------------------
--------------------------------------------------------------------------------


local create_identity_transform

local function transform_combine(transform, other)
	local t = create_identity_transform()

	t[ 1] = transform[ 1] * other[1] + transform[ 2] * other[5] + transform[ 3] * other[ 9]
	t[ 2] = transform[ 1] * other[2] + transform[ 2] * other[6] + transform[ 3] * other[10]
	t[ 3] = transform[ 1] * other[3] + transform[ 2] * other[7] + transform[ 3] * other[11]
	t[ 4] = transform[ 1] * other[4] + transform[ 2] * other[8] + transform[ 3] * other[12] + transform[ 4]

	t[ 5] = transform[ 5] * other[1] + transform[ 6] * other[5] + transform[ 7] * other[ 9]
	t[ 6] = transform[ 5] * other[2] + transform[ 6] * other[6] + transform[ 7] * other[10]
	t[ 7] = transform[ 5] * other[3] + transform[ 6] * other[7] + transform[ 7] * other[11]
	t[ 8] = transform[ 5] * other[4] + transform[ 6] * other[8] + transform[ 7] * other[12] + transform[ 8]

	t[ 9] = transform[ 9] * other[1] + transform[10] * other[5] + transform[11] * other[ 9]
	t[10] = transform[ 9] * other[2] + transform[10] * other[6] + transform[11] * other[10]
	t[11] = transform[ 9] * other[3] + transform[10] * other[7] + transform[11] * other[11]
	t[12] = transform[ 9] * other[4] + transform[10] * other[8] + transform[11] * other[12] + transform[12]

	return t
end

local function transform_transform(transform, data, translate)
	local d1 = data[1]
	local d2 = data[2]
	local d3 = data[3]

	local r1 = transform[1] * d1 + transform[ 2] * d2 + transform[ 3] * d3
	local r2 = transform[5] * d1 + transform[ 6] * d2 + transform[ 7] * d3
	local r3 = transform[9] * d1 + transform[10] * d2 + transform[11] * d3

	if translate then
		r1 = r1 + transform[ 4]
		r2 = r2 + transform[ 8]
		r3 = r3 + transform[12]
	end

	return { r1, r2, r3 }
end

local function transform_inverse(transform)
	-- TODO: untested!
	local tr_xx = transform[1]
	local tr_xy = transform[2]
	local tr_xz = transform[3]
	local tr_yx = transform[5]
	local tr_yy = transform[6]
	local tr_yz = transform[7]
	local tr_zx = transform[9]
	local tr_zy = transform[10]
	local tr_zz = transform[11]

	local inverse_det = 1/(tr_xx*(tr_yy*tr_zz-tr_zy*tr_yz)
	                      -tr_xy*(tr_yx*tr_zz-tr_yz*tr_zx)
	                      +tr_xz*(tr_yx*tr_zy-tr_yy*tr_zx))
	local inverse_xx =  (tr_yy*tr_zz-tr_zy*tr_yz) * inverse_det
	local inverse_xy = -(tr_xy*tr_zz-tr_xz*tr_zy) * inverse_det
	local inverse_xz =  (tr_xy*tr_yz-tr_xz*tr_yy) * inverse_det
	local inverse_yx = -(tr_yx*tr_zz-tr_yz*tr_zx) * inverse_det
	local inverse_yy =  (tr_xx*tr_zz-tr_xz*tr_zx) * inverse_det
	local inverse_yz = -(tr_xx*tr_yz-tr_yx*tr_xz) * inverse_det
	local inverse_zx =  (tr_yx*tr_zy-tr_zx*tr_yy) * inverse_det
	local inverse_zy = -(tr_xx*tr_zy-tr_zx*tr_xy) * inverse_det
	local inverse_zz =  (tr_xx*tr_yy-tr_yx*tr_xy) * inverse_det

	return v3d.translate(-transform[4], -transform[8], -transform[12]):combine {
		inverse_xx, inverse_xy, inverse_xz, 0,
		inverse_yx, inverse_yy, inverse_yz, 0,
		inverse_zx, inverse_zy, inverse_zz, 0,
	}
end

local transform_mt = { __mul = transform_combine }


--------------------------------------------------------------------------------
--[ Rasterization functions ]---------------------------------------------------
--------------------------------------------------------------------------------


local RENDER_GEOMETRY_SOURCE = [[
local _v3d_upvalue_uniforms = ...
return function(_, _v3d_geometry, _v3d_fb, _v3d_transform, _v3d_model_transform)
	local _v3d_math_ceil = math.ceil
	local _v3d_math_floor = math.floor
	local _v3d_fb_width = _v3d_fb.width
	local _v3d_fb_width_m1 = _v3d_fb_width - 1
	local _v3d_fb_height_m1 = _v3d_fb.height - 1
	local _v3d_screen_dx = (_v3d_fb.width - 1) / 2
	local _v3d_screen_dy = (_v3d_fb.height - 1) / 2
	local _v3d_screen_sy = -(_v3d_screen_dy - 0.5)
	local _v3d_screen_sx = {= opt_pixel_aspect_ratio =} * (_v3d_screen_dy - 0.5)

	v3d_import_uniforms()
	v3d_assign_layers()
	v3d_init_event_counters()

	local _v3d_stat_total_time = 0
	local _v3d_stat_rasterize_time = 0
	local _v3d_stat_candidate_faces = 0
	local _v3d_stat_drawn_faces = 0
	local _v3d_stat_culled_faces = 0
	local _v3d_stat_clipped_faces = 0
	local _v3d_stat_discarded_faces = 0
	local _v3d_stat_candidate_fragments = 0

	{% if needs_fragment_world_position then %}
	local _v3d_model_transform_xx = _v3d_model_transform[ 1]
	local _v3d_model_transform_xy = _v3d_model_transform[ 2]
	local _v3d_model_transform_xz = _v3d_model_transform[ 3]
	local _v3d_model_transform_dx = _v3d_model_transform[ 4]
	local _v3d_model_transform_yx = _v3d_model_transform[ 5]
	local _v3d_model_transform_yy = _v3d_model_transform[ 6]
	local _v3d_model_transform_yz = _v3d_model_transform[ 7]
	local _v3d_model_transform_dy = _v3d_model_transform[ 8]
	local _v3d_model_transform_zx = _v3d_model_transform[ 9]
	local _v3d_model_transform_zy = _v3d_model_transform[10]
	local _v3d_model_transform_zz = _v3d_model_transform[11]
	local _v3d_model_transform_dz = _v3d_model_transform[12]
	{% else %}
	-- TODO: implement this properly
	if _v3d_model_transform then
		_v3d_transform = _v3d_transform:combine(_v3d_model_transform)
	end
	{% end %}
	
	local _v3d_transform_xx = _v3d_transform[ 1]
	local _v3d_transform_xy = _v3d_transform[ 2]
	local _v3d_transform_xz = _v3d_transform[ 3]
	local _v3d_transform_dx = _v3d_transform[ 4]
	local _v3d_transform_yx = _v3d_transform[ 5]
	local _v3d_transform_yy = _v3d_transform[ 6]
	local _v3d_transform_yz = _v3d_transform[ 7]
	local _v3d_transform_dy = _v3d_transform[ 8]
	local _v3d_transform_zx = _v3d_transform[ 9]
	local _v3d_transform_zy = _v3d_transform[10]
	local _v3d_transform_zz = _v3d_transform[11]
	local _v3d_transform_dz = _v3d_transform[12]

	{% if needs_world_face_normal then %}
	local _v3d_math_sqrt = math.sqrt
	{% end %}

	local _v3d_vertex_offset = _v3d_geometry.vertex_offset
	local _v3d_face_offset = 0

	for _ = 1, _v3d_geometry.vertices, 3 do
		local _v3d_transformed_p0x, _v3d_transformed_p0y, _v3d_transformed_p0z,
		      _v3d_transformed_p1x, _v3d_transformed_p1y, _v3d_transformed_p1z,
		      _v3d_transformed_p2x, _v3d_transformed_p2y, _v3d_transformed_p2z

		{% if needs_fragment_world_position then %}
		local _v3d_world_transformed_p0x, _v3d_world_transformed_p0y, _v3d_world_transformed_p0z,
		      _v3d_world_transformed_p1x, _v3d_world_transformed_p1y, _v3d_world_transformed_p1z,
		      _v3d_world_transformed_p2x, _v3d_world_transformed_p2y, _v3d_world_transformed_p2z
		{% end %}
		{% if needs_world_face_normal then %}
		local _v3d_face_world_normal0, _v3d_face_world_normal1, _v3d_face_world_normal2
		{% end %}
		do
			{% local position_base_offset = opt_format:get_attribute(opt_position_attribute).offset %}
			local _v3d_p0x=_v3d_geometry[_v3d_vertex_offset + {= position_base_offset + 1 =}]
			local _v3d_p0y=_v3d_geometry[_v3d_vertex_offset + {= position_base_offset + 2 =}]
			local _v3d_p0z=_v3d_geometry[_v3d_vertex_offset + {= position_base_offset + 3 =}]
			local _v3d_p1x=_v3d_geometry[_v3d_vertex_offset + {= position_base_offset + opt_format.vertex_stride + 1 =}]
			local _v3d_p1y=_v3d_geometry[_v3d_vertex_offset + {= position_base_offset + opt_format.vertex_stride + 2 =}]
			local _v3d_p1z=_v3d_geometry[_v3d_vertex_offset + {= position_base_offset + opt_format.vertex_stride + 3 =}]
			local _v3d_p2x=_v3d_geometry[_v3d_vertex_offset + {= position_base_offset + opt_format.vertex_stride * 2 + 1 =}]
			local _v3d_p2y=_v3d_geometry[_v3d_vertex_offset + {= position_base_offset + opt_format.vertex_stride * 2 + 2 =}]
			local _v3d_p2z=_v3d_geometry[_v3d_vertex_offset + {= position_base_offset + opt_format.vertex_stride * 2 + 3 =}]

			{% if needs_fragment_world_position then %}
			_v3d_world_transformed_p0x = _v3d_model_transform_xx * _v3d_p0x + _v3d_model_transform_xy * _v3d_p0y + _v3d_model_transform_xz * _v3d_p0z + _v3d_model_transform_dx
			_v3d_world_transformed_p0y = _v3d_model_transform_yx * _v3d_p0x + _v3d_model_transform_yy * _v3d_p0y + _v3d_model_transform_yz * _v3d_p0z + _v3d_model_transform_dy
			_v3d_world_transformed_p0z = _v3d_model_transform_zx * _v3d_p0x + _v3d_model_transform_zy * _v3d_p0y + _v3d_model_transform_zz * _v3d_p0z + _v3d_model_transform_dz
			
			_v3d_world_transformed_p1x = _v3d_model_transform_xx * _v3d_p1x + _v3d_model_transform_xy * _v3d_p1y + _v3d_model_transform_xz * _v3d_p1z + _v3d_model_transform_dx
			_v3d_world_transformed_p1y = _v3d_model_transform_yx * _v3d_p1x + _v3d_model_transform_yy * _v3d_p1y + _v3d_model_transform_yz * _v3d_p1z + _v3d_model_transform_dy
			_v3d_world_transformed_p1z = _v3d_model_transform_zx * _v3d_p1x + _v3d_model_transform_zy * _v3d_p1y + _v3d_model_transform_zz * _v3d_p1z + _v3d_model_transform_dz
			
			_v3d_world_transformed_p2x = _v3d_model_transform_xx * _v3d_p2x + _v3d_model_transform_xy * _v3d_p2y + _v3d_model_transform_xz * _v3d_p2z + _v3d_model_transform_dx
			_v3d_world_transformed_p2y = _v3d_model_transform_yx * _v3d_p2x + _v3d_model_transform_yy * _v3d_p2y + _v3d_model_transform_yz * _v3d_p2z + _v3d_model_transform_dy
			_v3d_world_transformed_p2z = _v3d_model_transform_zx * _v3d_p2x + _v3d_model_transform_zy * _v3d_p2y + _v3d_model_transform_zz * _v3d_p2z + _v3d_model_transform_dz
			
			_v3d_transformed_p0x = _v3d_transform_xx * _v3d_world_transformed_p0x + _v3d_transform_xy * _v3d_world_transformed_p0y + _v3d_transform_xz * _v3d_world_transformed_p0z + _v3d_transform_dx
			_v3d_transformed_p0y = _v3d_transform_yx * _v3d_world_transformed_p0x + _v3d_transform_yy * _v3d_world_transformed_p0y + _v3d_transform_yz * _v3d_world_transformed_p0z + _v3d_transform_dy
			_v3d_transformed_p0z = _v3d_transform_zx * _v3d_world_transformed_p0x + _v3d_transform_zy * _v3d_world_transformed_p0y + _v3d_transform_zz * _v3d_world_transformed_p0z + _v3d_transform_dz
			
			_v3d_transformed_p1x = _v3d_transform_xx * _v3d_world_transformed_p1x + _v3d_transform_xy * _v3d_world_transformed_p1y + _v3d_transform_xz * _v3d_world_transformed_p1z + _v3d_transform_dx
			_v3d_transformed_p1y = _v3d_transform_yx * _v3d_world_transformed_p1x + _v3d_transform_yy * _v3d_world_transformed_p1y + _v3d_transform_yz * _v3d_world_transformed_p1z + _v3d_transform_dy
			_v3d_transformed_p1z = _v3d_transform_zx * _v3d_world_transformed_p1x + _v3d_transform_zy * _v3d_world_transformed_p1y + _v3d_transform_zz * _v3d_world_transformed_p1z + _v3d_transform_dz
			
			_v3d_transformed_p2x = _v3d_transform_xx * _v3d_world_transformed_p2x + _v3d_transform_xy * _v3d_world_transformed_p2y + _v3d_transform_xz * _v3d_world_transformed_p2z + _v3d_transform_dx
			_v3d_transformed_p2y = _v3d_transform_yx * _v3d_world_transformed_p2x + _v3d_transform_yy * _v3d_world_transformed_p2y + _v3d_transform_yz * _v3d_world_transformed_p2z + _v3d_transform_dy
			_v3d_transformed_p2z = _v3d_transform_zx * _v3d_world_transformed_p2x + _v3d_transform_zy * _v3d_world_transformed_p2y + _v3d_transform_zz * _v3d_world_transformed_p2z + _v3d_transform_dz
			{% else %}
			_v3d_transformed_p0x = _v3d_transform_xx * _v3d_p0x + _v3d_transform_xy * _v3d_p0y + _v3d_transform_xz * _v3d_p0z + _v3d_transform_dx
			_v3d_transformed_p0y = _v3d_transform_yx * _v3d_p0x + _v3d_transform_yy * _v3d_p0y + _v3d_transform_yz * _v3d_p0z + _v3d_transform_dy
			_v3d_transformed_p0z = _v3d_transform_zx * _v3d_p0x + _v3d_transform_zy * _v3d_p0y + _v3d_transform_zz * _v3d_p0z + _v3d_transform_dz

			_v3d_transformed_p1x = _v3d_transform_xx * _v3d_p1x + _v3d_transform_xy * _v3d_p1y + _v3d_transform_xz * _v3d_p1z + _v3d_transform_dx
			_v3d_transformed_p1y = _v3d_transform_yx * _v3d_p1x + _v3d_transform_yy * _v3d_p1y + _v3d_transform_yz * _v3d_p1z + _v3d_transform_dy
			_v3d_transformed_p1z = _v3d_transform_zx * _v3d_p1x + _v3d_transform_zy * _v3d_p1y + _v3d_transform_zz * _v3d_p1z + _v3d_transform_dz

			_v3d_transformed_p2x = _v3d_transform_xx * _v3d_p2x + _v3d_transform_xy * _v3d_p2y + _v3d_transform_xz * _v3d_p2z + _v3d_transform_dx
			_v3d_transformed_p2y = _v3d_transform_yx * _v3d_p2x + _v3d_transform_yy * _v3d_p2y + _v3d_transform_yz * _v3d_p2z + _v3d_transform_dy
			_v3d_transformed_p2z = _v3d_transform_zx * _v3d_p2x + _v3d_transform_zy * _v3d_p2y + _v3d_transform_zz * _v3d_p2z + _v3d_transform_dz
			{% end %}
			
			{% if needs_world_face_normal then %}
			local _v3d_face_normal_d1x = _v3d_world_transformed_p1x - _v3d_world_transformed_p0x
			local _v3d_face_normal_d1y = _v3d_world_transformed_p1y - _v3d_world_transformed_p0y
			local _v3d_face_normal_d1z = _v3d_world_transformed_p1z - _v3d_world_transformed_p0z
			local _v3d_face_normal_d2x = _v3d_world_transformed_p2x - _v3d_world_transformed_p0x
			local _v3d_face_normal_d2y = _v3d_world_transformed_p2y - _v3d_world_transformed_p0y
			local _v3d_face_normal_d2z = _v3d_world_transformed_p2z - _v3d_world_transformed_p0z
			_v3d_face_world_normal0 = _v3d_face_normal_d1y*_v3d_face_normal_d2z - _v3d_face_normal_d1z*_v3d_face_normal_d2y
			_v3d_face_world_normal1 = _v3d_face_normal_d1z*_v3d_face_normal_d2x - _v3d_face_normal_d1x*_v3d_face_normal_d2z
			_v3d_face_world_normal2 = _v3d_face_normal_d1x*_v3d_face_normal_d2y - _v3d_face_normal_d1y*_v3d_face_normal_d2x
			local _v3d_face_normal_divisor = 1 / _v3d_math_sqrt(_v3d_face_world_normal0 * _v3d_face_world_normal0 + _v3d_face_world_normal1 * _v3d_face_world_normal1 + _v3d_face_world_normal2 * _v3d_face_world_normal2)
			_v3d_face_world_normal0 = _v3d_face_world_normal0 * _v3d_face_normal_divisor
			_v3d_face_world_normal1 = _v3d_face_world_normal1 * _v3d_face_normal_divisor
			_v3d_face_world_normal2 = _v3d_face_world_normal2 * _v3d_face_normal_divisor
			{% end %}
		end

		-- #embed VERTEX_ATTRIBUTE_ASSIGNMENT
		-- #embed FACE_ATTRIBUTE_ASSIGNMENT

		-- #increment_statistic candidate_faces

		{% if opt_cull_face then %}
		local _v3d_cull_face

		do
			local _v3d_d1x = _v3d_transformed_p1x - _v3d_transformed_p0x
			local _v3d_d1y = _v3d_transformed_p1y - _v3d_transformed_p0y
			local _v3d_d1z = _v3d_transformed_p1z - _v3d_transformed_p0z
			local _v3d_d2x = _v3d_transformed_p2x - _v3d_transformed_p0x
			local _v3d_d2y = _v3d_transformed_p2y - _v3d_transformed_p0y
			local _v3d_d2z = _v3d_transformed_p2z - _v3d_transformed_p0z
			local _v3d_cx = _v3d_d1y*_v3d_d2z - _v3d_d1z*_v3d_d2y
			local _v3d_cy = _v3d_d1z*_v3d_d2x - _v3d_d1x*_v3d_d2z
			local _v3d_cz = _v3d_d1x*_v3d_d2y - _v3d_d1y*_v3d_d2x
			{% local cull_face_comparison_operator = opt_cull_face == v3d.CULL_FRONT_FACE and '<' or '>' %}
			_v3d_cull_face = _v3d_cx * _v3d_transformed_p0x + _v3d_cy * _v3d_transformed_p0y + _v3d_cz * _v3d_transformed_p0z {= cull_face_comparison_operator =} 0
		end

		if not _v3d_cull_face then
		{% end %}

			-- TODO: make this split polygons
			{% local clipping_plane = 0.0001 %}
			if _v3d_transformed_p0z <= {= clipping_plane =} and _v3d_transformed_p1z <= {= clipping_plane =} and _v3d_transformed_p2z <= {= clipping_plane =} then
				local _v3d_rasterize_p0_w = -1 / _v3d_transformed_p0z
				local _v3d_rasterize_p0_x = _v3d_screen_dx + _v3d_transformed_p0x * _v3d_rasterize_p0_w * _v3d_screen_sx
				local _v3d_rasterize_p0_y = _v3d_screen_dy + _v3d_transformed_p0y * _v3d_rasterize_p0_w * _v3d_screen_sy
				local _v3d_rasterize_p1_w = -1 / _v3d_transformed_p1z
				local _v3d_rasterize_p1_x = _v3d_screen_dx + _v3d_transformed_p1x * _v3d_rasterize_p1_w * _v3d_screen_sx
				local _v3d_rasterize_p1_y = _v3d_screen_dy + _v3d_transformed_p1y * _v3d_rasterize_p1_w * _v3d_screen_sy
				local _v3d_rasterize_p2_w = -1 / _v3d_transformed_p2z
				local _v3d_rasterize_p2_x = _v3d_screen_dx + _v3d_transformed_p2x * _v3d_rasterize_p2_w * _v3d_screen_sx
				local _v3d_rasterize_p2_y = _v3d_screen_dy + _v3d_transformed_p2y * _v3d_rasterize_p2_w * _v3d_screen_sy

				-- #embed TRIANGLE_RASTERIZATION_NOCLIP_VERTEX_ATTRIBUTE_PARAMETERS
				{! TRIANGLE_RASTERIZATION_EMBED !}
				-- #increment_statistic drawn_faces
			else
				-- #increment_statistic discarded_faces
			end

		{% if opt_cull_face then %}
		else
			-- #increment_statistic culled_faces
		end
		{% end %}
	
		_v3d_vertex_offset = _v3d_vertex_offset + {= opt_format.vertex_stride * 3 =}
		_v3d_face_offset = _v3d_face_offset + {= opt_format.face_stride =}
	end

	v3d_export_uniforms()

	return {
		total_time = _v3d_stat_total_time,
		rasterize_time = _v3d_stat_rasterize_time,
		candidate_faces = _v3d_stat_candidate_faces,
		drawn_faces = _v3d_stat_drawn_faces,
		culled_faces = _v3d_stat_culled_faces,
		clipped_faces = _v3d_stat_clipped_faces,
		discarded_faces = _v3d_stat_discarded_faces,
		candidate_fragments = _v3d_stat_candidate_fragments,
		events = {
			v3d_store_event_counters()
		},
	}
end
]]

local TRIANGLE_RASTERIZATION_EMBED = [[
-- #embed VERTEX_ORDERING

local _v3d_midpoint_scalar = (_v3d_rasterize_p1_y - _v3d_rasterize_p0_y) / (_v3d_rasterize_p2_y - _v3d_rasterize_p0_y)
local _v3d_rasterize_pM_x = _v3d_rasterize_p0_x * (1 - _v3d_midpoint_scalar) + _v3d_rasterize_p2_x * _v3d_midpoint_scalar

-- #embed MIDPOINT_CALCULATION

if _v3d_rasterize_pM_x > _v3d_rasterize_p1_x then
	_v3d_rasterize_pM_x, _v3d_rasterize_p1_x = _v3d_rasterize_p1_x, _v3d_rasterize_pM_x
	-- #embed MIDPOINT_SWAP
end

local _v3d_row_top_min = _v3d_math_floor(_v3d_rasterize_p0_y + 0.5)
local _v3d_row_top_max = _v3d_math_floor(_v3d_rasterize_p1_y - 0.5)
local _v3d_row_bottom_min = _v3d_row_top_max + 1
local _v3d_row_bottom_max = _v3d_math_ceil(_v3d_rasterize_p2_y - 0.5)

if _v3d_row_top_min < 0 then _v3d_row_top_min = 0 end
if _v3d_row_bottom_min < 0 then _v3d_row_bottom_min = 0 end
if _v3d_row_top_max > _v3d_fb_height_m1 then _v3d_row_top_max = _v3d_fb_height_m1 end
if _v3d_row_bottom_max > _v3d_fb_height_m1 then _v3d_row_bottom_max = _v3d_fb_height_m1 end

if _v3d_row_top_min <= _v3d_row_top_max then
	local _v3d_tri_dy = _v3d_rasterize_p1_y - _v3d_rasterize_p0_y
	if _v3d_tri_dy > 0 then
		-- #embed FLAT_TRIANGLE_CALCULATIONS(top, p0, p0, pM, p1)

		local _v3d_row_min_index = _v3d_row_top_min * _v3d_fb_width
		local _v3d_row_max_index = _v3d_row_top_max * _v3d_fb_width

		{! FLAT_TRIANGLE_RASTERIZATION_EMBED !}
	end
end

if _v3d_row_bottom_min <= _v3d_row_bottom_max then
	local _v3d_tri_dy = _v3d_rasterize_p2_y - _v3d_rasterize_p1_y

	if _v3d_tri_dy > 0 then
		-- #embed FLAT_TRIANGLE_CALCULATIONS(bottom, pM, p1, p2, p2)

		local _v3d_row_min_index = _v3d_row_bottom_min * _v3d_fb_width
		local _v3d_row_max_index = _v3d_row_bottom_max * _v3d_fb_width

		{! FLAT_TRIANGLE_RASTERIZATION_EMBED !}
	end
end
]]

local FLAT_TRIANGLE_RASTERIZATION_EMBED = [[
for _v3d_base_index = _v3d_row_min_index, _v3d_row_max_index, _v3d_fb_width do
	local _v3d_row_min_column = _v3d_math_ceil(_v3d_tri_left_x)
	local _v3d_row_max_column = _v3d_math_ceil(_v3d_tri_right_x)

	if _v3d_row_min_column < 0 then _v3d_row_min_column = 0 end
	if _v3d_row_max_column > _v3d_fb_width_m1 then _v3d_row_max_column = _v3d_fb_width_m1 end

	-- #embed ROW_CALCULATIONS

	{% if #layer_sizes_written ~= 1 then %}
	for _v3d_x = _v3d_row_min_column, _v3d_row_max_column do
	{% else %}
		{%
		local min_bound = '_v3d_base_index + _v3d_row_min_column'
		local max_bound = '_v3d_base_index + _v3d_row_max_column'
	
		if layer_sizes_written[1] ~= 1 then
			min_bound = '(' .. min_bound .. ') * ' .. layer_sizes_written[1]
			max_bound = '(' .. max_bound .. ') * ' .. layer_sizes_written[1]
		end
		%}
	for _v3d_fragment_layer_index{= layer_sizes_written[1] =} = {= min_bound =} + 1, {= max_bound =} + 1, {= layer_sizes_written[1] =} do
	{% end %}
		v3d_register_layer_written()

		{% if #layer_sizes_written > 1 then %}
			{% for _, i in ipairs(layer_sizes_written) do %}
		local _v3d_fragment_layer_index{= i =} = (_v3d_base_index + _v3d_x) * {= i =} + 1
			{% end %}
		{% end %}
		-- #increment_statistic candidate_fragments
		-- #embed COLUMN_CALCULATE_ATTRIBUTES
		{! FRAGMENT_SHADER_EMBED !}
		-- #embed COLUMN_ADVANCE
	end

	_v3d_tri_left_x = _v3d_tri_left_x + _v3d_tri_left_dx_dy
	_v3d_tri_right_x = _v3d_tri_right_x + _v3d_tri_right_dx_dy
	-- #embed ROW_ADVANCE
end
]]

local function _parse_parameters(s)
	local params = {}
	local i = 1
	local start = 1
	local in_string = nil

	while i <= #s do
		local char = s:sub(i, i)

		if (char == '\'' or char == '"') and not in_string then
			in_string = char
			i = i + 1
		elseif char == in_string then
			in_string = nil
			i = i + 1
		elseif char == '\\' then
			i = i + (in_string and 2 or 1)
		elseif in_string then
			i = select(2, assert(s:find('[^\\\'"]+', i))) + 1
		elseif char == '(' or char == '{' or char == '[' then
			local close = char == '(' and ')' or char == '{' and '}' or ']'
			i = select(2, assert(s:find('%b' .. char .. close, i))) + 1
		elseif char == ',' then
			table.insert(params, s:sub(start, i - 1))
			start = i + 1
			i = i + 1
		else
			i = select(2, assert(s:find('[^\\\'"(){}%[%],]+', i))) + 1
		end
	end

	if i > start then
		table.insert(params, s:sub(start))
	end

	for i = 1, #params do
		params[i] = params[i]:gsub('^%s+', '', 1):gsub('%s+$', '', 1)
	end

	return params
end

local function _rewrite_vfsl(s, replacements)
	local changed
	repeat
		changed = false
		s = ('\n' .. s):gsub('(\n[ \t]*)([^\n]-[^_])(v3d_[%w_]+)(%b())', function(w, c, f, p)
			local params = _parse_parameters(p:sub(2, -2))
			local result = {}

			if c:find '%-%-' then
				return w .. c .. f .. p
			end

			local replace = replacements[f]

			if not replace then
				return w .. c .. f .. p
			end

			if not c:find "[^ \t]" then
				w = w .. c
				c = ''
			end

			if type(replace) == 'function' then
				replace(params, result)
			elseif #params == 0 then
				result[1] = replace
			else
				v3d_internal_error('Tried to pass parameters to a string replacement')
			end

			changed = true

			return w .. c .. table.concat(result, w)
		end):sub(2)
	until not changed

	return s
end

local function v3d_create_pipeline(options)
	--- @type V3DLayout
	local opt_layout = options.layout
	--- @type V3DFormat
	local opt_format = options.format
	local opt_position_attribute = options.position_attribute
	local opt_cull_face = options.cull_face == nil and v3d.CULL_BACK_FACE or options.cull_face
	local opt_fragment_shader = options.fragment_shader
	local opt_pixel_aspect_ratio = options.pixel_aspect_ratio or 1
	local opt_statistics = options.statistics or false

	local pipeline = {}
	local uniforms = {}

	-- format incoming shader code to unindent it
	do
		opt_fragment_shader = opt_fragment_shader:gsub('%s+$', '')

		local lines = {}
		local min_line_length = math.huge
		local matching_indentation_length = 0

		for line in opt_fragment_shader:gmatch '[^\n]+' do
			if line:find '%S' then
				line = line:match '^%s*'
				table.insert(lines, line)
				min_line_length = math.min(min_line_length, #line)
			end
		end

		if lines[1] then
			for i = 1, min_line_length do
				local c = lines[1]:sub(i, i)
				local ok = true
				for j = 2, #lines do
					if lines[j]:sub(i, i) ~= c then
						ok = false
						break
					end
				end
				if not ok then
					break
				end
				matching_indentation_length = i
			end

			opt_fragment_shader = opt_fragment_shader
				:gsub('^' .. lines[1]:sub(1, matching_indentation_length), '')
				:gsub('\n' .. lines[1]:sub(1, matching_indentation_length), '\n')
		end
	end

	--- @type V3DPipelineOptions
	pipeline.options = {
		layout = opt_layout,
		format = opt_format,
		position_attribute = opt_position_attribute,
		cull_face = opt_cull_face,
		fragment_shader = opt_fragment_shader,
		pixel_aspect_ratio = opt_pixel_aspect_ratio,
		statistics = opt_statistics,
	}

	-- names of all layers which are accessed
	local layers_written = {}
	-- sizes of all layers which are accessed
	-- TODOA
	-- true if v3d_layer_was_written() is ever used
	local layers_any_written_checked = false
	-- map of layer names to whether anything checks if it's written to
	local layers_written_checked = {}

	-- names of all uniforms which are accessed
	local uniforms_accessed = {}
	-- names of all uniforms which are written
	local uniforms_written = {}

	-- list of face attributes which should be initialised
	local geometry_read_face_attributes = {}
	-- list of vertex attributes which should be initialised
	local geometry_read_vertex_attributes = {}
	-- list of attributes (name + size) which should be interpolated over fragments
	local interpolate_attributes = {}

	-- names of events that are counted
	local event_counters = {}

	-- whether the pipeline should interpolate depth across fragments
	local needs_interpolated_depth = false

	-- whether the pipeline should interpolate world position across fragments
	local needs_fragment_world_position = false

	local template_context = {
		v3d = v3d,

		opt_layout = opt_layout,
		opt_format = opt_format,
		opt_position_attribute = opt_position_attribute,
		opt_cull_face = opt_cull_face,
		opt_pixel_aspect_ratio = opt_pixel_aspect_ratio,
		opt_statistics = opt_statistics,

		FLAT_TRIANGLE_RASTERIZATION_EMBED = FLAT_TRIANGLE_RASTERIZATION_EMBED,
		TRIANGLE_RASTERIZATION_EMBED = TRIANGLE_RASTERIZATION_EMBED,
		FRAGMENT_SHADER_EMBED = opt_fragment_shader,

		needs_fragment_world_position = needs_fragment_world_position,
		needs_interpolated_depth = needs_interpolated_depth,

		layer_sizes_written = {},

		-- whether to generate face normals in world-space
		needs_world_face_normal = false,
	}

	do -- fragment shader macro rewrite
		local layer_names_lookup = {}
		local layer_sizes_lookup = {}
		local attribute_names_lookup = {}
		local uniform_read_names_lookup = {}
		local uniform_write_names_lookup = {}
		local event_counter_names_lookup = {}
		local added_fragment_world_position_attr = false
		local functions = {}

		local is_discarded_checked = false

		local function destring(s)
			return s:gsub('^[\'"]', '', 1):gsub('[\'"]$', '', 1)
		end

		local function register_attribute(name)
			local attr = opt_format:get_attribute(name) or error('Unknown attribute \'' .. name .. '\'')

			if attribute_names_lookup[name] then
				return attr
			end

			attribute_names_lookup[name] = true

			if attr.type == 'vertex' then
				table.insert(geometry_read_vertex_attributes, attr)
				table.insert(interpolate_attributes, { name = attr.name, size = attr.size })
			else
				table.insert(geometry_read_face_attributes, attr)
			end

			return attr
		end

		local function register_layer(name)
			local layer = opt_layout:get_layer(name) or error('Unknown layer \'' .. name .. '\'')

			if not layer_names_lookup[name] then
				table.insert(layers_written, layer)
				layer_names_lookup[name] = true
			end

			if not layer_sizes_lookup[layer.components] then
				table.insert(template_context.layer_sizes_written, layer.components)
				layer_sizes_lookup[layer.components] = true
			end

			return name, layer
		end

		local function register_generic(list, lookup, name)
			if not lookup[name] then
				table.insert(list, name)
				lookup[name] = true
			end
		end

		local function layer_index(layer, i)
			if i == 1 then
				return '_v3d_fragment_layer_index' .. layer.components
			else
				return '_v3d_fragment_layer_index' .. layer.components .. ' + ' .. i - 1
			end
		end

		function functions.v3d_read_attribute_values(params, result)
			local attr = register_attribute(destring(params[1]))
			local parts = {}

			for i = 1, attr.size do
				table.insert(parts, '_v3d_attr_' .. attr.name .. i)
			end

			table.insert(result, table.concat(parts, ', '))
		end
		function functions.v3d_read_attribute(params, result)
			local i = tonumber(params[2] or '1')
			local attr = register_attribute(destring(params[1]))

			table.insert(result, '_v3d_attr_' .. attr.name .. i)
		end

		--- v3d_read_attribute_gradient(string-literal)
		--- v3d_read_attribute_gradient(string-literal, integer-literal)

		function functions.v3d_write_layer_values(params, result)
			local name, layer = register_layer(destring(params[1]))

			for i = 1, layer.components do
				table.insert(result, '_v3d_layer_' .. name .. '[' .. layer_index(layer, i) .. '] = ' .. tostring(params[i + 1]))
			end

			table.insert(result, 'v3d_notify_any_layer_written()')
			table.insert(result, 'v3d_notify_specific_layer_written(' .. name .. ')')
		end
		function functions.v3d_write_layer(params, result)
			local i = tonumber(params[3] and params[2] or '1')
			local name, layer = register_layer(destring(params[1]))

			table.insert(result, '_v3d_layer_' .. name .. '[' .. layer_index(layer, i) .. '] = ' .. params[i + 1])
			table.insert(result, 'v3d_notify_any_layer_written()')
			table.insert(result, 'v3d_notify_specific_layer_written(' .. name .. ')')
		end
		function functions.v3d_read_layer_values(params, result)
			local name, layer = register_layer(destring(params[1]))
			local parts = {}

			for i = 1, layer.components do
				table.insert(parts, '_v3d_layer_' .. name .. '[' .. layer_index(layer, i) .. ']')
			end

			table.insert(result, table.concat(parts, ', '))
		end
		function functions.v3d_read_layer(params, result)
			local i = tonumber(params[2] or '1')
			local name, layer = register_layer(destring(params[1]))

			table.insert(result, '_v3d_layer_' .. name .. '[' .. layer_index(layer, i) .. ']')
		end
		function functions.v3d_was_layer_written(params, result)
			if params[1] then
				local name = destring(params[1])
				layers_written_checked[name] = true
				table.insert(result, '_v3d_specific_layer_written_' .. name)
			else
				layers_any_written_checked = true
				table.insert(result, '_v3d_any_layer_written')
			end
		end

		function functions.v3d_read_uniform(params, result)
			local name = destring(params[1])
			register_generic(uniforms_accessed, uniform_read_names_lookup, name)
			table.insert(result, '_v3d_uniform_' .. name)
		end
		function functions.v3d_write_uniform(params, result)
			local name = destring(params[1])
			register_generic(uniforms_accessed, uniform_read_names_lookup, name)
			register_generic(uniforms_written, uniform_write_names_lookup, name)
			table.insert(result, '_v3d_uniform_' .. name .. ' = ' .. params[2])
		end

		--- v3d_face_row_bounds()
		--- v3d_face_row_bounds('min' | 'max')
		--- v3d_row_column_bounds()
		--- v3d_row_column_bounds('min' | 'max')

		function functions.v3d_face_world_normal(params, result)
			local component = params[1] and destring(params[1])

			template_context.needs_world_face_normal = true
			template_context.needs_fragment_world_position = true

			local parts = {}

			for i = 1, 3 do
				if not component or (i == 1 and component == 'x' or i == 2 and component == 'y' or i == 3 and component == 'z') then
					table.insert(parts, '_v3d_face_world_normal' .. i - 1)
				end
			end

			table.insert(result, table.concat(parts, ', '))
		end

		--- v3d_face_was_clipped()

		--- v3d_fragment_polygon_section()

		--- v3d_fragment_is_face_front_facing()

		function functions.v3d_fragment_depth(_, result)
			needs_interpolated_depth = true
			table.insert(result, '_v3d_row_w')
		end

		--- v3d_fragment_screen_position()
		--- v3d_fragment_screen_position('x' | 'y')

		--- v3d_fragment_view_position()
		--- v3d_fragment_view_position('x' | 'y' | 'z')

		function functions.v3d_fragment_world_position(params, result)
			local component = params[1] and destring(params[1])

			if not added_fragment_world_position_attr then
				table.insert(interpolate_attributes, { name = '_v3d_fragment_world_position', size = 3 })
				added_fragment_world_position_attr = true
				template_context.needs_world_face_normal = true
			end

			local parts = {}

			for i = 1, 3 do
				if not component or (i == 1 and component == 'x' or i == 2 and component == 'y' or i == 3 and component == 'z') then
					table.insert(parts, '_v3d_attr__v3d_fragment_world_position' .. i)
				end
			end

			table.insert(result, table.concat(parts, ', '))
		end

		function functions.v3d_discard_fragment(_, result)
			table.insert(result, '_v3d_builtin_fragment_discarded = true') -- TODO!
		end
		function functions.v3d_was_fragment_discarded(_, result)
			is_discarded_checked = true
			table.insert(result, '_v3d_builtin_fragment_discarded')
		end

		function functions.v3d_compare_depth(params, result)
			table.insert(result, params[1] .. ' > ' .. params[2])
		end

		function functions.v3d_count_event(params, result)
			local name = destring(params[1])
			register_generic(event_counters, event_counter_names_lookup, name)
			if opt_statistics then
				table.insert(result, '_v3d_event_counter_' .. name .. ' = _v3d_event_counter_' .. name .. ' + ' .. (params[2] or '1'))
			end
		end

		-- replace simple variables
		template_context.FRAGMENT_SHADER_EMBED = template_context.FRAGMENT_SHADER_EMBED
			:gsub('v3d_framebuffer_width%(%s*%)%s*%-%s*1', '_v3d_fb_width_m1')
			:gsub('v3d_framebuffer_height%(%s*%)%s*%-%s*1', '_v3d_fb_height_m1')
			:gsub('v3d_framebuffer_width%(%s*%)', '_v3d_fb_width')
			:gsub('v3d_framebuffer_height%(%s*%)', '_v3d_fb_height')

		template_context.FRAGMENT_SHADER_EMBED = _rewrite_vfsl(template_context.FRAGMENT_SHADER_EMBED, functions)

		if is_discarded_checked then
			template_context.FRAGMENT_SHADER_EMBED = 'local _v3d_builtin_fragment_discarded = false\n' .. template_context.FRAGMENT_SHADER_EMBED
		end

		needs_interpolated_depth = needs_interpolated_depth or #interpolate_attributes > 0

		table.sort(template_context.layer_sizes_written)
	end

	local pipeline_source = RENDER_GEOMETRY_SOURCE

	do -- STAT_TOTAL_TIME
		-- TODO
	end

	do -- STAT_RASTERIZE_TIME
		-- TODO
	end

	pipeline_source = v3d_generate_template(pipeline_source, template_context)

	do -- embeds
		local embeds = {}
		embeds.VERTEX_ATTRIBUTE_ASSIGNMENT = function()
			local result = ''

			for _, attr in ipairs(geometry_read_vertex_attributes) do
				for i = 1, attr.size do
					result = result .. 'local _v3d_p0_va_' .. attr.name .. i .. ' = _v3d_geometry[_v3d_vertex_offset + ' .. (attr.offset + i) .. ']\n'
									.. 'local _v3d_p1_va_' .. attr.name .. i .. ' = _v3d_geometry[_v3d_vertex_offset + ' .. (attr.offset + opt_format.vertex_stride + i) .. ']\n'
									.. 'local _v3d_p2_va_' .. attr.name .. i .. ' = _v3d_geometry[_v3d_vertex_offset + ' .. (attr.offset + opt_format.vertex_stride * 2 + i) .. ']\n'
				end
			end

			return result
		end
		embeds.FACE_ATTRIBUTE_ASSIGNMENT = function()
			local result = ''

			for _, attr in ipairs(geometry_read_face_attributes) do
				for i = 1, attr.size do
					result = result .. 'local _v3d_attr_' .. attr.name .. i
							.. ' = _v3d_geometry[_v3d_face_offset+' .. (attr.offset + i) .. ']\n'
				end
			end

			return result
		end
		embeds.TRIANGLE_RASTERIZATION_NOCLIP_VERTEX_ATTRIBUTE_PARAMETERS = function()
			local result = ''

			for _, attr in ipairs(interpolate_attributes) do
				for i = 1, attr.size do
					if attr.name == '_v3d_fragment_world_position' then
						local name = i == 1 and 'x' or i == 2 and 'y' or 'z'
						result = result .. 'local _v3d_rasterize_p0_va_' .. attr.name .. i .. ' = _v3d_world_transformed_p0' .. name .. '\n'
						                .. 'local _v3d_rasterize_p1_va_' .. attr.name .. i .. ' = _v3d_world_transformed_p1' .. name .. '\n'
						                .. 'local _v3d_rasterize_p2_va_' .. attr.name .. i .. ' = _v3d_world_transformed_p2' .. name .. '\n'
					else
						result = result .. 'local _v3d_rasterize_p0_va_' .. attr.name .. i .. ' = _v3d_p0_va_' .. attr.name .. i .. '\n'
						                .. 'local _v3d_rasterize_p1_va_' .. attr.name .. i .. ' = _v3d_p1_va_' .. attr.name .. i .. '\n'
						                .. 'local _v3d_rasterize_p2_va_' .. attr.name .. i .. ' = _v3d_p2_va_' .. attr.name .. i .. '\n'
					end
				end
			end

			return result
		end
		embeds.VERTEX_ORDERING = function()
			local to_swap = { '_v3d_rasterize_pN_x', '_v3d_rasterize_pN_y' }

			if needs_interpolated_depth then
				table.insert(to_swap, '_v3d_rasterize_pN_w')
			end

			for _, attr in ipairs(interpolate_attributes) do
				for i = 1, attr.size do
					table.insert(to_swap, '_v3d_rasterize_pN_va_' .. attr.name .. i)
				end
			end

			local function swap_test(a, b)
				local result = 'if _v3d_rasterize_pA_y > _v3d_rasterize_pB_y then\n'

				for i = 1, #to_swap do
					local sA = to_swap[i]:gsub('N', 'A')
					local sB = to_swap[i]:gsub('N', 'B')
					result = result .. '\t' .. sA .. ', ' .. sB .. ' = ' .. sB .. ', ' .. sA .. '\n'
				end

				return (result .. 'end'):gsub('A', a):gsub('B', b)
			end

			return swap_test(0, 1) .. '\n' .. swap_test(1, 2) .. '\n' .. swap_test(0, 1)
		end
		embeds.MIDPOINT_CALCULATION = function()
			local calculation = ''

			if needs_interpolated_depth then
				calculation = calculation .. 'local _v3d_rasterize_pM_w = _v3d_rasterize_p0_w * (1 - _v3d_midpoint_scalar) + _v3d_rasterize_p2_w * _v3d_midpoint_scalar\n'
			end

			for _, attr in ipairs(interpolate_attributes) do
				for i = 1, attr.size do
					local s = attr.name .. i
					calculation = calculation .. 'local _v3d_rasterize_pM_va_' .. s .. ' = (_v3d_rasterize_p0_va_' ..s .. ' * _v3d_rasterize_p0_w * (1 - _v3d_midpoint_scalar) + _v3d_rasterize_p2_va_' .. s .. ' * _v3d_rasterize_p2_w * _v3d_midpoint_scalar) / _v3d_rasterize_pM_w\n'
				end
			end

			return calculation
		end
		embeds.MIDPOINT_SWAP = function()
			local swap = ''

			if needs_interpolated_depth then
				swap = swap .. '_v3d_rasterize_pM_w, _v3d_rasterize_p1_w = _v3d_rasterize_p1_w, _v3d_rasterize_pM_w\n'
			end

			for _, attr in ipairs(interpolate_attributes) do
				for i = 1, attr.size do
					local s = attr.name .. i
					swap = swap .. '_v3d_rasterize_pM_va_' .. s .. ', _v3d_rasterize_p1_va_' .. s .. ' = _v3d_rasterize_p1_va_' .. s .. ', _v3d_rasterize_pM_va_' .. s .. '\n'
				end
			end

			return swap
		end
		embeds.FLAT_TRIANGLE_CALCULATIONS = function(name, top_left, top_right, bottom_left, bottom_right)
			local result = 'local _v3d_tri_y_correction = _v3d_row_' .. name .. '_min + 0.5 - _v3d_rasterize_' .. top_right .. '_y\n'
						.. 'local _v3d_tri_left_dx_dy = (_v3d_rasterize_' .. bottom_left .. '_x - _v3d_rasterize_' .. top_left .. '_x) / _v3d_tri_dy\n'
						.. 'local _v3d_tri_right_dx_dy = (_v3d_rasterize_' .. bottom_right .. '_x - _v3d_rasterize_' .. top_right .. '_x) / _v3d_tri_dy\n'
						.. 'local _v3d_tri_left_x = _v3d_rasterize_' .. top_left .. '_x + _v3d_tri_left_dx_dy * _v3d_tri_y_correction - 0.5\n'
						.. 'local _v3d_tri_right_x = _v3d_rasterize_' .. top_right .. '_x + _v3d_tri_right_dx_dy * _v3d_tri_y_correction - 1.5\n'

			if needs_interpolated_depth then
				result = result .. 'local _v3d_tri_left_dw_dy = (_v3d_rasterize_' .. bottom_left .. '_w - _v3d_rasterize_' .. top_left .. '_w) / _v3d_tri_dy\n'
								.. 'local _v3d_tri_right_dw_dy = (_v3d_rasterize_' .. bottom_right .. '_w - _v3d_rasterize_' .. top_right .. '_w) / _v3d_tri_dy\n'
								.. 'local _v3d_tri_left_w = _v3d_rasterize_' .. top_left .. '_w + _v3d_tri_left_dw_dy * _v3d_tri_y_correction\n'
								.. 'local _v3d_tri_right_w = _v3d_rasterize_' .. top_right .. '_w + _v3d_tri_right_dw_dy * _v3d_tri_y_correction\n'
			end

			for _, attr in ipairs(interpolate_attributes) do
				for i = 1, attr.size do
					local s = attr.name .. i
					result = result .. 'local _v3d_tri_left_va_d' .. s .. 'w_dy = (_v3d_rasterize_' .. bottom_left .. '_va_' .. s .. ' * _v3d_rasterize_' .. bottom_left .. '_w - _v3d_rasterize_' .. top_left .. '_va_' .. s .. ' * _v3d_rasterize_' .. top_left .. '_w) / _v3d_tri_dy\n'
									.. 'local _v3d_tri_right_va_d' .. s .. 'w_dy = (_v3d_rasterize_' .. bottom_right .. '_va_' .. s .. ' * _v3d_rasterize_' .. bottom_right .. '_w - _v3d_rasterize_' .. top_right .. '_va_' .. s .. ' * _v3d_rasterize_' .. top_right .. '_w) / _v3d_tri_dy\n'
									.. 'local _v3d_tri_left_va_' .. s .. '_w = _v3d_rasterize_' .. top_left .. '_va_' .. s .. ' * _v3d_rasterize_' .. top_left .. '_w + _v3d_tri_left_va_d' .. s .. 'w_dy * _v3d_tri_y_correction\n'
									.. 'local _v3d_tri_right_va_' .. s .. '_w = _v3d_rasterize_' .. top_right .. '_va_' .. s .. ' * _v3d_rasterize_' .. top_right .. '_w + _v3d_tri_right_va_d' .. s .. 'w_dy * _v3d_tri_y_correction\n'
				end
			end

			return result
		end
		embeds.ROW_CALCULATIONS = function()
			local result = ''

			if needs_interpolated_depth then
				result = result .. 'local _v3d_row_x_correction = _v3d_row_min_column - _v3d_tri_left_x\n'
								.. 'local _v3d_row_dx = _v3d_tri_right_x - _v3d_tri_left_x + 1\n' -- TODO: + 1 ???
								.. 'local _v3d_row_dw_dx = (_v3d_tri_right_w - _v3d_tri_left_w) / _v3d_row_dx\n'
								.. 'local _v3d_row_w = _v3d_tri_left_w + _v3d_row_dw_dx * _v3d_row_x_correction\n'
			end

			for _, attr in ipairs(interpolate_attributes) do
				for i = 1, attr.size do
					local s = attr.name .. i
					result = result .. 'local _v3d_row_va_d' .. s .. 'w_dx = (_v3d_tri_right_va_' .. s .. '_w - _v3d_tri_left_va_' .. s .. '_w) / _v3d_row_dx\n'
									.. 'local _v3d_row_va_' .. s .. '_w = _v3d_tri_left_va_' .. s .. '_w + _v3d_row_va_d' .. s .. 'w_dx * _v3d_row_x_correction\n'
				end
			end

			return result
		end
		embeds.COLUMN_CALCULATE_ATTRIBUTES = function()
			local result = ''

			for _, attr in ipairs(interpolate_attributes) do
				for i = 1, attr.size do
					local s = attr.name .. i
					result = result .. 'local _v3d_attr_' .. s .. ' = _v3d_row_va_' .. s .. '_w / _v3d_row_w\n'
				end
			end

			return result
		end
		embeds.COLUMN_ADVANCE = function()
			local result = ''

			if needs_interpolated_depth then
				result = result .. '_v3d_row_w = _v3d_row_w + _v3d_row_dw_dx\n'
			end

			for _, attr in ipairs(interpolate_attributes) do
				for i = 1, attr.size do
					local s = attr.name .. i
					result = result .. '_v3d_row_va_' .. s .. '_w = _v3d_row_va_' .. s .. '_w + _v3d_row_va_d' .. s .. 'w_dx\n'
				end
			end

			return result
		end
		embeds.ROW_ADVANCE = function()
			local result = ''

			if needs_interpolated_depth then
				result = result .. '_v3d_tri_left_w = _v3d_tri_left_w + _v3d_tri_left_dw_dy\n'
								.. '_v3d_tri_right_w = _v3d_tri_right_w + _v3d_tri_right_dw_dy\n'
			end

			for _, attr in ipairs(interpolate_attributes) do
				for i = 1, attr.size do
					local s = attr.name .. i
					result = result .. '_v3d_tri_left_va_' .. s .. '_w = _v3d_tri_left_va_' .. s .. '_w + _v3d_tri_left_va_d' .. s .. 'w_dy\n'
									.. '_v3d_tri_right_va_' .. s .. '_w = _v3d_tri_right_va_' .. s .. '_w + _v3d_tri_right_va_d' .. s .. 'w_dy\n'
				end
			end

			return result
		end
		local count

		repeat
			pipeline_source, count = pipeline_source:gsub('(\t+)%-%-%s*#embed%s+([%w_]+)([^\n]*)\n', function(indent, name, params)
				local embed = embeds[name]

				if not embed then
					v3d_internal_error('Missing embed ' .. name)
				end

				if type(embed) == 'function' then
					local ps = {}
					for p in params:sub(2, -2):gmatch '[^,]+' do
						table.insert(ps, (p:gsub('^%s+', '', 1):gsub('%s+$', '', 1)))
					end
					embed = embed(table.unpack(ps))
				end

				--- @cast embed string

				return indent .. embed:gsub('\n', '\n' .. indent) .. '\n'
			end)
		until count == 0
	end

	local function do_nothing(_, _)
		-- don't add anything to result
	end

	local function enable_if(flag, fn)
		return flag and fn or do_nothing
	end

	for _, name in ipairs { 'candidate_faces', 'drawn_faces', 'culled_faces', 'clipped_faces', 'discarded_faces', 'candidate_fragments' } do -- statistics
		local replace = '--%s*#increment_statistic%s+' .. name
		local replace_with = opt_statistics and '_v3d_stat_' .. name .. ' = _v3d_stat_' .. name .. ' + 1' or ''
		pipeline_source = pipeline_source:gsub(replace, replace_with)
	end

	pipeline_source = _rewrite_vfsl(pipeline_source, {
		v3d_pixel_aspect_ratio = '{= opt_pixel_aspect_ratio =}',
		v3d_transform = '_v3d_transform',
		v3d_model_transform = '_v3d_model_transform',
		v3d_import_uniforms = function(_, result)
			if #uniforms_accessed > 0 then
				table.insert(result, 'local _v3d_uniforms = _v3d_upvalue_uniforms')
			end
			for _, uniform_name in ipairs(uniforms_accessed) do
				table.insert(result, 'local _v3d_uniform_' .. uniform_name .. ' = _v3d_uniforms["' .. uniform_name .. '"]')
			end
		end,
		v3d_export_uniforms = function(_, result)
			for _, uniform_name in ipairs(uniforms_accessed) do
				table.insert(result, '_v3d_uniforms["' .. uniform_name .. '"] =  _v3d_uniform_' .. uniform_name)
			end
		end,
		v3d_assign_layers = function(_, result)
			for _, layer in ipairs(layers_written) do
				table.insert(result, 'local _v3d_layer_' .. layer.name .. ' = _v3d_fb.layer_data["' .. layer.name .. '"]')
			end
		end,
		v3d_init_event_counters = enable_if(opt_statistics, function(_, result)
			for _, counter_name in ipairs(event_counters) do
				table.insert(result, 'local _v3d_event_counter_' .. counter_name .. ' = 0')
			end
		end),
		v3d_store_event_counters = function(_, result)
			for _, counter_name in ipairs(event_counters) do
				if opt_statistics then
					table.insert(result, counter_name .. ' = _v3d_event_counter_' .. counter_name .. ',')
				else
					table.insert(result, counter_name .. ' = 0,')
				end
			end
		end,
		v3d_register_layer_written = enable_if(layers_any_written_checked, function(_, result)
			if layers_any_written_checked then
				table.insert(result, 'local _v3d_any_layer_written = false')
			end
			for layer in pairs(layers_written_checked) do
				table.insert(result, 'local _v3d_specific_layer_written_' .. layer .. ' = false')
			end
		end),
		v3d_notify_any_layer_written = enable_if(layers_any_written_checked, function(_, result)
			table.insert(result, '_v3d_any_layer_written = true')
		end),
		v3d_notify_specific_layer_written = function(params, result)
			return layers_written_checked[params[1]] and '_v3d_specific_layer_written_' .. params[1] .. ' = true' or ''
		end,
	})

	_rewrite_vfsl(pipeline_source, setmetatable({}, { __index = function(_, fn)
		error('Unexpanded macro \'' .. fn .. '\'')
	end }))

	local f, err = load(pipeline_source, 'pipeline source')

	if not f then
		f = v3d_internal_error('Failed to compile pipeline render_geometry function: ' .. err, pipeline_source)
	end

	pipeline.source = pipeline_source
	pipeline.render_geometry = f(uniforms)

	pipeline.set_uniform = function(_, name, value)
		uniforms[name] = value
	end

	pipeline.get_uniform = function(_, name)
		return uniforms[name]
	end

	pipeline.list_uniforms = function(_)
		local t = {}
		for k in pairs(uniforms) do
			t[#t + 1] = k
		end
		return t
	end

	return pipeline
end

local function create_texture_sampler(texture_uniform, width_uniform, height_uniform)
	local math_floor = math.floor

	texture_uniform = texture_uniform or 'u_texture'
	width_uniform = width_uniform or 'u_texture_width'
	height_uniform = height_uniform or 'u_texture_height'

	return function(uniforms, u, v)
		local image = uniforms[texture_uniform]
		local image_width = uniforms[width_uniform]
		local image_height = uniforms[height_uniform]

		local x = math_floor(u * image_width)
		if x < 0 then x = 0 end
		if x >= image_width then x = image_width - 1 end
		local y = math_floor(v * image_height)
		if y < 0 then y = 0 end
		if y >= image_height then y = image_height - 1 end

		local colour = image[y + 1][x + 1]

		if colour == 0 then
			return nil
		end

		return colour
	end
end


--------------------------------------------------------------------------------
--[ Constructors ]--------------------------------------------------------------
--------------------------------------------------------------------------------


local function create_layout()
	local layout = {}

	layout.layers = {}
	layout.layer_lookup = {}

	layout.add_layer = layout_add_layer
	layout.drop_layer = layout_drop_layer
	layout.has_layer = layout_has_layer
	layout.get_layer = layout_get_layer

	return layout
end

local function create_framebuffer(layout, width, height)
	local fb = {}

	fb.layout = layout
	fb.width = width
	fb.height = height
	fb.layer_data = {}
	fb.get_buffer = framebuffer_get_buffer
	fb.clear = framebuffer_clear
	fb.blit_term_subpixel = framebuffer_blit_term_subpixel
	fb.blit_graphics = framebuffer_blit_graphics

	for i = 1, #layout.layers do
		local layer = layout.layers[i]
		fb.layer_data[layer.name] = {}
		framebuffer_clear(fb, layer.name)
	end

	return fb
end

local function create_framebuffer_subpixel(layout, width, height)
	return create_framebuffer(layout, width * 2, height * 3) -- multiply by subpixel dimensions
end

local function create_format()
	local format = {}

	format.attributes = {}
	format.attribute_lookup = {}
	format.vertex_stride = 0
	format.face_stride = 0

	format.add_vertex_attribute = format_add_vertex_attribute
	format.add_face_attribute = format_add_face_attribute
	format.drop_attribute = format_drop_attribute
	format.has_attribute = format_has_attribute
	format.get_attribute = format_get_attribute

	return format
end

local function create_geometry_builder(format)
	local gb = {}

	gb.format = format
	gb.attribute_data = {}

	gb.set_data = geometry_builder_set_data
	gb.append_data = geometry_builder_append_data
	gb.map = geometry_builder_map
	gb.transform = geometry_builder_transform
	gb.insert = geometry_builder_insert
	gb.cast = geometry_builder_cast
	gb.build = geometry_builder_build

	return gb
end

function create_identity_transform()
	local t = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0 }

	t.combine = transform_combine
	t.transform = transform_transform
	t.inverse = transform_inverse

	return setmetatable(t, transform_mt)
end

local function create_translate_transform(dx, dy, dz)
	local t = { 1, 0, 0, dx, 0, 1, 0, dy, 0, 0, 1, dz }

	t.combine = transform_combine
	t.transform = transform_transform

	return setmetatable(t, transform_mt)
end

local function create_scale_transform(sx, sy, sz)
	local t = { sx, 0, 0, 0, 0, sy or sx, 0, 0, 0, 0, sz or sx, 0 }

	t.combine = transform_combine
	t.transform = transform_transform

	return setmetatable(t, transform_mt)
end

local function create_rotate_transform(tx, ty, tz)
	local math_sin = math.sin
	local math_cos = math.cos
	local sin_x = math_sin(tx)
	local sin_y = math_sin(ty)
	local sin_z = math_sin(tz)
	local cos_x = math_cos(tx)
	local cos_y = math_cos(ty)
	local cos_z = math_cos(tz)
	local fxx = cos_y*cos_z - sin_x*sin_y*sin_z
	local fxy = cos_x*sin_z
	local fxz = sin_y*cos_z + sin_x*cos_y*sin_z
	local fyx = -cos_y*sin_z - sin_x*sin_y*cos_z
	local fyy = cos_x*cos_z
	local fyz = -sin_y*sin_z + sin_x*cos_y*cos_z
	local fzx = -cos_x*sin_y
	local fzy = -sin_x
	local fzz = cos_x*cos_y
	local t = { fxx, fxy, fxz, 0, fyx, fyy, fyz, 0, fzx, fzy, fzz, 0 }

	t.combine = transform_combine
	t.transform = transform_transform

	return setmetatable(t, transform_mt)
end

local function create_camera_transform(x, y, z, rx, ry, rz, fov)
	if not y then
		fov = x
		x = 0
	end

	if not rz then
		fov = ry
		ry = rx
		rx = 0
	end

	fov = fov or math.pi / 3
	rx = rx or 0
	ry = ry or 0
	rz = rz or 0
	x = x or 0
	y = y or 0
	z = z or 0

	local tan_inverse = 1 / math.tan(fov / 2)

	return transform_combine(transform_combine(
		{ tan_inverse, 0, 0, 0, 0, tan_inverse, 0, 0, 0, 0, 1, 0 },
		create_rotate_transform(-rx, -ry, -rz)),
		{ 1, 0, 0, -x, 0, 1, 0, -y, 0, 0, 1, -z })
end

local function create_debug_cube(cx, cy, cz, size)
	local s2 = (size or 1) / 2

	cx = cx or 0
	cy = cy or 0
	cz = cz or 0

	return create_geometry_builder(v3d.DEBUG_CUBE_FORMAT)
		:set_data('position', {
			-s2,  s2,  s2, -s2, -s2,  s2,  s2,  s2,  s2, -- front 1
			-s2, -s2,  s2,  s2, -s2,  s2,  s2,  s2,  s2, -- front 2
			 s2,  s2, -s2,  s2, -s2, -s2, -s2,  s2, -s2, -- back 1
			 s2, -s2, -s2, -s2, -s2, -s2, -s2,  s2, -s2, -- back 2
			-s2,  s2, -s2, -s2, -s2, -s2, -s2,  s2,  s2, -- left 1
			-s2, -s2, -s2, -s2, -s2,  s2, -s2,  s2,  s2, -- left 2
			 s2,  s2,  s2,  s2, -s2,  s2,  s2,  s2, -s2, -- right 1
			 s2, -s2,  s2,  s2, -s2, -s2,  s2,  s2, -s2, -- right 2
			-s2,  s2, -s2, -s2,  s2,  s2,  s2,  s2, -s2, -- top 1
			-s2,  s2,  s2,  s2,  s2,  s2,  s2,  s2, -s2, -- top 2
			 s2, -s2, -s2,  s2, -s2,  s2, -s2, -s2, -s2, -- bottom 1
			 s2, -s2,  s2, -s2, -s2,  s2, -s2, -s2, -s2, -- bottom 2
		})
		:set_data('uv', {
			0, 0, 0, 1, 1, 0, -- front 1
			0, 1, 1, 1, 1, 0, -- front 2
			0, 0, 0, 1, 1, 0, -- back 1
			0, 1, 1, 1, 1, 0, -- back 2
			0, 0, 0, 1, 1, 0, -- left 1
			0, 1, 1, 1, 1, 0, -- left 2
			0, 0, 0, 1, 1, 0, -- right 1
			0, 1, 1, 1, 1, 0, -- right 2
			0, 0, 0, 1, 1, 0, -- top 1
			0, 1, 1, 1, 1, 0, -- top 2
			0, 0, 0, 1, 1, 0, -- bottom 1
			0, 1, 1, 1, 1, 0, -- bottom 2
		})
		:set_data('colour', {
			colours.blue, colours.cyan, -- front,
			colours.brown, colours.yellow, -- back
			colours.lightBlue, colours.pink, -- left
			colours.red, colours.orange, -- right
			colours.green, colours.lime, -- top
			colours.purple, colours.magenta, -- bottom
		})
		:set_data('face_normal', {
			 0,  0,  1,  0,  0,  1, -- front
			 0,  0,  1,  0,  0, -1, -- back
			-1,  0,  0, -1,  0,  0, -- left
			 1,  0,  0,  1,  0,  0, -- right
			 0,  1,  0,  0,  1,  0, -- top
			 0, -1,  0,  0, -1,  0, -- bottom
		})
		:set_data('face_index', { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 })
		:set_data('side_index', { 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5 })
		:set_data('side_name', {
			'front', 'front',
			'back', 'back',
			'left', 'left',
			'right', 'right',
			'top', 'top',
			'bottom', 'bottom',
		})
		:map('position', function(d)
			return { d[1] + cx, d[2] + cy, d[3] + cz }
		end)
end


--------------------------------------------------------------------------------
--[ Library export ]------------------------------------------------------------
--------------------------------------------------------------------------------


do
	-- This purely exists to bypass the language server being too clever for itself.
	-- It's here so the LS can't work out what's going on so we keep the types and
	-- docstrings from the top of the file rather than adding weird shit from here.
	local function set_library(name, fn)
		local c = v3d
		c[name] = fn
	end

	set_library('generate_template', v3d_generate_template)
	set_library('create_format', create_format)
	set_library('create_layout', create_layout)
	set_library('create_framebuffer', create_framebuffer)
	set_library('create_framebuffer_subpixel', create_framebuffer_subpixel)
	set_library('create_geometry_builder', create_geometry_builder)
	set_library('create_debug_cube', create_debug_cube)
	set_library('identity', create_identity_transform)
	set_library('translate', create_translate_transform)
	set_library('scale', create_scale_transform)
	set_library('rotate', create_rotate_transform)
	set_library('camera', create_camera_transform)
	set_library('create_pipeline', v3d_create_pipeline)
	set_library('create_texture_sampler', create_texture_sampler)

	set_library('CULL_FRONT_FACE', -1)
	set_library('CULL_BACK_FACE', 1)
	set_library('GEOMETRY_COLOUR', 1)
	set_library('GEOMETRY_UV', 2)
	set_library('GEOMETRY_COLOUR_UV', 3)
	set_library('COLOUR_LAYOUT', v3d.create_layout()
		:add_layer('colour', 'exp-palette-index', 1))
	set_library('COLOUR_DEPTH_LAYOUT', v3d.create_layout()
		:add_layer('colour', 'exp-palette-index', 1)
		:add_layer('depth', 'depth-reciprocal', 1))
	set_library('DEFAULT_FORMAT', v3d.create_format()
		:add_vertex_attribute('position', 3, true)
		:add_face_attribute('colour', 1))
	set_library('UV_FORMAT', v3d.create_format()
		:add_vertex_attribute('position', 3, true)
		:add_vertex_attribute('uv', 2, true))
	set_library('DEBUG_CUBE_FORMAT', v3d.create_format()
		:add_vertex_attribute('position', 3, true)
		:add_vertex_attribute('uv', 2, true)
		:add_face_attribute('colour', 1)
		:add_face_attribute('face_normal', 3)
		:add_face_attribute('face_index', 1)
		:add_face_attribute('side_index', 1)
		:add_face_attribute('side_name', 1))
end

return v3d
