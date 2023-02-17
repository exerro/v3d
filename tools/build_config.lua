
--- @class build_config
--- String snippets to run a type check on a type. Overrides anything that v3dd
--- would insert on its own. Strings should use `%s` where the value would be
--- placed.
--- The key to this table should be the type documented in v3d.lua, but should
--- omit `| nil` since this is handled automatically.
--- @field v3dd_type_checkers { [string]: string }
--- Lookup table for V3D types which are considered structural. Structural types
--- don't have an "identity" - there is no attempt to wrap them into something
--- v3d interfaces with.
--- Keys to this table should be V3D classes.
--- Note: types that don't have any fields or methods are implicitly considered
--- structural, e.g. `V3DFragmentShader`.
--- @field v3dd_structural_types { [string]: boolean }
--- Blacklist for functions which should not participate in logging to the
--- capture call tree. These functions will still be wrapped with validation,
--- but that validation will simply error on each failure rather than adding a
--- message to the call tree.
--- Keys to this table should be a class name, `.`, then the function name, e.g.
--- `MyClass.my_function`.
--- @field v3dd_fn_logging_blacklist { [string]: boolean }
--- Snippets of code that are inserted before a call to the original function.
--- Note the following variables in scope:
--- * `self` - the instance, if applicable
--- * `call_tree` - a Tree for the call
--- * all relevant variables and functions available in scope from `v3dd.lua`.
--- Also note that, if the function uses overloads, parameters are named `_pN`
--- rather than their original names.
--- Keys to this table should be a class name, `.`, then the function name, e.g.
--- `MyClass.my_function`.
--- @field v3dd_fn_pre_body { [string]: string }
--- Similar to `v3dd_fn_pre_body` but inserted after the call to the function.
--- Additional fields include:
--- * `return_value` - return value of the original function, after conversion,
---                    and call tree modification have taken place.
--- * `return_tree` - tree for the return value.
--- @field v3dd_fn_post_body { [string]: string }
--- Lookup table for fields which should not have details appended when
--- generating the details for the tree of a V3D object.
--- Keys to this table should be a class name, `.`, then the field name, e.g.
--- `MyClass.my_field`.
--- @field v3dd_field_detail_blacklist { [string]: boolean }
--- Snippets of code to add extra details to the tree of an object. Variables in
--- scope:
--- * `instance` - the instance
--- * `trees` - list of trees to have detail added to
--- Note that `trees` is also a map of field name to detail tree, so you can
--- apply modifications to the auto-generated trees of attributes.
--- Keys to this table should be a class name, e.g. `V3DTransform`.
--- @field v3dd_extra_field_details { [string]: string }
local build_config = {
	v3dd_type_checkers = {},
	v3dd_structural_types = {},
	v3dd_fn_logging_blacklist = {},
	v3dd_fn_pre_body = {},
	v3dd_fn_post_body = {},
	v3dd_field_detail_blacklist = {},
	v3dd_extra_field_details = {},
}

do -- type checkers
	build_config.v3dd_type_checkers['V3DFragmentShader'] = 'type(%s) == \'function\''
	build_config.v3dd_type_checkers['V3DCullFace'] = '%s == v3d_lib.CULL_FRONT_FACE or %s == v3d_lib.CULL_BACK_FACE'
	build_config.v3dd_type_checkers['V3DUniforms'] = 'type(%s) == \'table\''
	build_config.v3dd_type_checkers['boolean'] = 'type(%s) == \'boolean\''
	build_config.v3dd_type_checkers['number'] = 'type(%s) == \'number\''
	build_config.v3dd_type_checkers['integer'] = 'type(%s) == \'number\' and %s % 1 < 0.001'
	build_config.v3dd_type_checkers['string'] = 'type(%s) == \'string\''
	build_config.v3dd_type_checkers['table'] = 'type(%s) == \'table\''
	build_config.v3dd_type_checkers['true | false'] = 'type(%s) == \'boolean\''
	build_config.v3dd_type_checkers['any'] = 'true'
end

do -- structural types
	build_config.v3dd_structural_types['V3DPipelineOptions'] = true
	build_config.v3dd_structural_types['V3DLayoutAttribute'] = true
end

do -- fn logging blacklist
	build_config.v3dd_fn_logging_blacklist['v3d.create_layout'] = true
	build_config.v3dd_fn_logging_blacklist['v3d.create_geometry_builder'] = true
	build_config.v3dd_fn_logging_blacklist['v3d.create_debug_cube'] = true
	build_config.v3dd_fn_logging_blacklist['v3d.identity'] = true
	build_config.v3dd_fn_logging_blacklist['v3d.translate'] = true
	build_config.v3dd_fn_logging_blacklist['v3d.scale'] = true
	build_config.v3dd_fn_logging_blacklist['v3d.rotate'] = true
	build_config.v3dd_fn_logging_blacklist['v3d.camera'] = true
	build_config.v3dd_fn_logging_blacklist['v3d.create_texture_sampler'] = true
	build_config.v3dd_fn_logging_blacklist['V3DLayout.add_vertex_attribute'] = true
	build_config.v3dd_fn_logging_blacklist['V3DLayout.add_face_attribute'] = true
	build_config.v3dd_fn_logging_blacklist['V3DLayout.drop_attribute'] = true
	build_config.v3dd_fn_logging_blacklist['V3DLayout.has_attribute'] = true
	build_config.v3dd_fn_logging_blacklist['V3DLayout.get_attribute'] = true
	build_config.v3dd_fn_logging_blacklist['V3DGeometry.to_builder'] = true
	build_config.v3dd_fn_logging_blacklist['V3DGeometryBuilder.set_data'] = true
	build_config.v3dd_fn_logging_blacklist['V3DGeometryBuilder.append_data'] = true
	build_config.v3dd_fn_logging_blacklist['V3DGeometryBuilder.map'] = true
	build_config.v3dd_fn_logging_blacklist['V3DGeometryBuilder.transform'] = true
	build_config.v3dd_fn_logging_blacklist['V3DGeometryBuilder.insert'] = true
	build_config.v3dd_fn_logging_blacklist['V3DGeometryBuilder.cast'] = true
	build_config.v3dd_fn_logging_blacklist['V3DTransform.combine'] = true
	build_config.v3dd_fn_logging_blacklist['V3DTransform.transform'] = true
	build_config.v3dd_fn_logging_blacklist['V3DPipeline.get_uniform'] = true
	build_config.v3dd_fn_logging_blacklist['V3DPipeline.list_uniforms'] = true
end

do -- fn pre body
	-- show current uniform values in tree when calling render_geometry
	build_config.v3dd_fn_pre_body['V3DPipeline.render_geometry'] = [[
local uniforms_tree = { content = 'Uniforms', children = {} }
table.insert(call_tree.children, uniforms_tree)

for _, uniform in ipairs(self:list_uniforms()) do
table.insert(uniforms_tree.children, {
	content = '&lightBlue;' .. uniform .. '&reset; = ' .. fmtobject(self:get_uniform(uniform))
})
end
]]
end

-- TODO: add more checks
--       * width > 0, height > 0 for creating framebuffer
--       * create_debug_cube size > 0
--       * wrap fragment shader for type checking
--       * clear_depth >= 0
--       * framebuffer contents valid before blit
--       * layout new attribute doesn't exist
--       * layout drop_attribute attribute does exist
--       * geometry builder transform applied to a 3/4+ component attribute
--       * geometry builder build checks data lengths and data existing
--       * camera fov > 0
--       * pipeline option has colour attribute xor fragment shader
--       * pipeline option layout has all specified attributes
--       * pipeline option layout position attribute is 3 component vertex
--       * pipeline option layout colour_attribute attribute is 1 component face
--       * pipeline option pixel aspect ratio > 0
--       * pipeline render_geometry layouts match

do -- fn post body
	-- notify blit called after relevant functions
	build_config.v3dd_fn_post_body['V3DFramebuffer.blit_term_subpixel'] = 'v3d_state.blit_called = true'
	build_config.v3dd_fn_post_body['V3DFramebuffer.blit_term_subpixel_depth'] = 'v3d_state.blit_called = true'
	build_config.v3dd_fn_post_body['V3DFramebuffer.blit_graphics'] = 'v3d_state.blit_called = true'
	build_config.v3dd_fn_post_body['V3DFramebuffer.blit_graphics_depth'] = 'v3d_state.blit_called = true'
end

do -- field blacklist
	build_config.v3dd_field_detail_blacklist['V3DLayout.attributes'] = true
	build_config.v3dd_field_detail_blacklist['V3DFramebuffer.colour'] = true
	build_config.v3dd_field_detail_blacklist['V3DFramebuffer.depth'] = true
end

do -- extra field details
	-- show vertex and face attribute lists for V3DLayout
	build_config.v3dd_extra_field_details.V3DLayout = [[
local attr_trees = {}
attr_trees.vertex = {
content = 'Vertex attributes',
children = {},
}
attr_trees.face = {
content = 'Face attributes',
children = {},
}
table.insert(trees, attr_trees.vertex)
table.insert(trees, attr_trees.face)
for i = 1, #instance.attributes do
local attr = instance.attributes[i]
table.insert(attr_trees[attr.type].children, {
	content = attr.name .. ' (' .. fmtobject(attr.size) .. '&lightGrey; components&reset;)',
	children = {
		{ content = '&lightBlue;offset&reset; = ' .. fmtobject(attr.offset) },
		{ content = '&lightBlue;is_numeric&reset; = ' .. fmtobject(attr.is_numeric) },
	},
})
end]]

	-- show transform data for V3DTransform
	build_config.v3dd_extra_field_details.V3DTransform = [[
local s = {}
local r = {}

for y = 1, 3 do
s[y] = {}
for x = 1, 4 do
	local index = (y - 1) * 4 + x
	s[y][x] = fmtobject(instance[index])
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
table.insert(trees, {
	content = table.concat(ss, '  '),
})
end]]

	-- add Data section showing raw data for V3DGeometry
	-- TODO: group by vertex?
	build_config.v3dd_extra_field_details.V3DGeometry = [[
local face_data = { content = 'Raw face data', children = {} }
local vertex_data = { content = 'Raw vertex data', children = {} }
local face_fmt = '&lightGrey;[f%0' .. #tostring(instance.faces) .. 'd %'
              .. #tostring(instance.vertex_offset - 1) .. 'd]: &reset;%s&reset;'
local vertex_fmt = '&lightGrey;[v%0' .. #tostring(instance.vertices) .. 'd %'
              .. #tostring(#instance) .. 'd]: &reset;%s&reset;'

table.insert(trees, face_data)
table.insert(trees, vertex_data)

for i = 1, instance.vertex_offset do
	local face_n = math.floor((i - 1) / instance.layout.face_stride) + 1
	face_data.children[i] = { content = face_fmt:format(face_n, i, fmtobject(instance[i])) }
end

for i = instance.vertex_offset + 1, #instance do
	local vertex_n = math.floor((i - instance.vertex_offset - 1) / instance.layout.vertex_stride) + 1
	table.insert(vertex_data.children, { content = vertex_fmt:format(vertex_n, i, fmtobject(instance[i])) })
end]]

	-- pretty print attributes as list and cull_face as ref for V3DPipelineOptions
	build_config.v3dd_extra_field_details.V3DPipelineOptions = [[
local attributes = {}
local cull_face_s = fmtobject(instance.cull_face)

if instance.attributes then
for i = 1, #instance.attributes do
	attributes[i] = fmtobject(instance.attributes[i])
end
end

if instance.cull_face == v3d_wrapper.CULL_FRONT_FACE then
cull_face_s = '&cyan;v3d.CULL_FRONT_FACE&reset;'
elseif instance.cull_face == v3d_wrapper.CULL_BACK_FACE then
cull_face_s = '&cyan;v3d.CULL_BACK_FACE&reset;'
end

trees.attributes.content = '&lightBlue;attributes&reset; = [' .. table.concat(attributes, ',') .. ']'
trees.cull_face.content = '&lightBlue;cull_face&reset; = ' .. cull_face_s]]
end

return build_config