local vsl_ir = require "vsl_ir"
local vsl_types = require "vsl_types"
local vsl_parse = require "vsl_parse"

local NamingCtx
do
	--- @class NamingCtx
	--- @field private next_variable_tag_lookup { [string]: VariableTag } map of variable names to the ID it should be assigned when next declared
	--- @field private next_ssa_version_lookup { [VariableNameAndTagKey]: SsaVersion } map of variable names+tags to the next SSA version it should use when assigned
	--- @field private next_temporary_id_value integer
	--- @field private next_block_id_value BlockId
	NamingCtx = {}

	--- @alias VariableNameAndTagKey string -- "<variable_name>:<variable_tag>"

	function NamingCtx.new()
		--- @type NamingCtx
		local ctx = {
			next_variable_tag_lookup = {},
			next_ssa_version_lookup = {},
			next_temporary_id_value = 0,
			next_block_id_value = 1,
		}

		return setmetatable(ctx, { __index = NamingCtx })
	end

	--- @param variable_name string
	--- @param variable_tag VariableTag
	--- @return VariableNameAndTagKey
	function NamingCtx.name_and_tag_key(variable_name, variable_tag)
		return variable_name .. ":" .. variable_tag
	end

	--- @param variable_name string
	--- @return VariableTag
	function NamingCtx:next_variable_tag(variable_name)
		local tag = self.next_variable_tag_lookup[variable_name] or 0
		self.next_variable_tag_lookup[variable_name] = tag + 1
		return tag
	end

	--- @param name_and_tag VariableNameAndTagKey
	--- @return SsaVersion
	function NamingCtx:next_ssa_version_raw(name_and_tag)
		local version = self.next_ssa_version_lookup[name_and_tag] or 0
		self.next_ssa_version_lookup[name_and_tag] = version + 1
		return version
	end

	--- @param variable_name string
	--- @param variable_tag VariableTag
	--- @return SsaVersion
	function NamingCtx:next_ssa_version(variable_name, variable_tag)
		return self:next_ssa_version_raw(variable_name .. ":" .. variable_tag)
	end

	--- @return integer
	function NamingCtx:next_temporary_id()
		local id = self.next_temporary_id_value
		self.next_temporary_id_value = self.next_temporary_id_value + 1
		return id
	end

	--- @return integer
	function NamingCtx:next_block_id()
		local id = self.next_block_id_value
		self.next_block_id_value = self.next_block_id_value + 1
		return id
	end
end

local IR = {}
do -- IR definitions
	--- @alias Definition StructDef | FnDef

	--- @class StructDef
	--- @field type "struct"
	--- @field docstring string?
	--- @field can_construct boolean false if the struct has private fields or is opaque
	--- @field name string name of the struct
	--- @field type_parameters string[] list of type parameter names
	--- @field fields StructDefField[] list of fields in flattened storage/offset order
	--- @field tuple_constructor StructDefField[]? ordered list of field names when constructing a struct like Foo(1, 2, 3)

	--- @class StructDefField
	--- @field docstring string?
	--- @field name string | integer
	--- @field offset number
	--- @field type ValueType

	--- @class FnDef
	--- @field type "function"
	--- @field docstring string?
	--- @field name string
	--- @field type_parameters string[]
	--- @field params FnDefParameter[]
	--- @field return_type ValueType
	--- @field return_value ValueRef?
	--- @field blocks { [BlockId]: Block }
	--- @field registers { [RegisterIdLookup]: RegisterAssignment }
	--- @field main_block BlockId
	--- @field naming NamingCtx

	--- @class FnDefParameter
	--- @field docstring string?
	--- @field name string
	--- @field type ValueType

	--- @alias BlockId integer
	--- @alias VariableTag integer
	--- @alias SsaVersion integer
	--- @alias RegisterIdLookup string -- "t<temporary_id>" or "v<variable_name>:<variable_tag>:<ssa_version>"

	--- @alias RegisterId TemporaryRegister | VariableRegister

	--- @class TemporaryRegister
	--- @field register_kind "temporary"
	--- @field temporary_id integer

	--- @class VariableRegister
	--- @field register_kind "variable"
	--- @field variable_name string
	--- @field variable_tag VariableTag
	--- @field ssa_version SsaVersion

	--- @class Block
	--- @field statements Statement[]

	--- @alias RegisterAssignment
	--- | RegAssignLoadParam
	--- | RegAssignPhi
	--- | RegAssignMove
	--- | RegAssignTable
	--- | RegAssignGetIndex
	--- | RegAssignCast
	--- | RegAssignCallFn
	--- | RegAssignInfixOp
	--- | RegAssignPrefixOp

	--- @class RegAssignLoadParam
	--- @field assign_kind "load_param"
	--- @field register_type ValueType
	--- @field load_param_index integer

	--- @class RegAssignPhi
	--- @field assign_kind "phi"
	--- @field register_type ValueType
	--- @field phi_primary VariableRegister
	--- @field phi_secondary VariableRegister

	--- @class RegAssignMove
	--- @field assign_kind "move"
	--- @field register_type ValueType
	--- @field move_value ValueRef

	--- @class RegAssignTable
	--- @field assign_kind "create_table"
	--- @field register_type ValueType
	--- @field table_elements { key: ValueRef, value: ValueRef }[]

	--- @class RegAssignGetIndex
	--- @field assign_kind "get_index"
	--- @field register_type ValueType
	--- @field get_index_subject ValueRef
	--- @field get_index ValueRef

	--- @class RegAssignCast
	--- @field assign_kind "cast"
	--- @field register_type ValueType
	--- @field cast_subject ValueRef

	--- @class RegAssignCallFn
	--- @field assign_kind "call_fn"
	--- @field register_type ValueType
	--- @field call_fn_name string | RegisterId
	--- @field call_fn_pure boolean
	--- @field call_fn_parameters ValueRef[]

	--- @class RegAssignInfixOp
	--- @field assign_kind "infix_op"
	--- @field register_type ValueType
	--- @field infix_op_operator InfixOpName
	--- @field infix_op_lvalue ValueRef
	--- @field infix_op_rvalue ValueRef

	--- @class RegAssignPrefixOp
	--- @field assign_kind "prefix_op"
	--- @field register_type ValueType
	--- @field prefix_op_operator UnaryOpName
	--- @field prefix_op_rvalue ValueRef

	--- @alias UnaryOpName "unm" | "not" | "len"
	--- @alias InfixOpName "add" | "sub" | "mul" | "div" | "mod" | "exp" | "concat" | "lt" | "lte" | "eq" | "neq"

	--- @alias ValueRef ConstantValueRef | RegisterValueRef

	--- @class ConstantValueRef
	--- @field value_kind "constant"
	--- @field constant_value string
	--- @field constant_type ValueType

	--- @class RegisterValueRef
	--- @field value_kind "register"
	--- @field register_id RegisterId

	--- @alias Statement
	--- | EvalStatement
	--- | SetIndexStatement
	--- | IfStatement
	--- | LoopStatement
	--- | BreakStatement

	--- @class EvalStatement
	--- @field statement_kind "evaluate"
	--- @field evaluate_register_id RegisterId

	--- @class SetIndexStatement
	--- @field statement_kind "set_index"
	--- @field set_index_subject RegisterId
	--- @field set_index ValueRef
	--- @field set_index_value ValueRef

	--- @class IfStatement
	--- @field statement_kind "if"
	--- @field if_condition ValueRef
	--- @field if_true BlockId
	--- @field if_false BlockId

	--- @class LoopStatement
	--- @field statement_kind "loop"
	--- @field loop_body BlockId

	--- @class BreakStatement
	--- @field statement_kind "break"

	--- @class NameAndType
	--- @field name string
	--- @field type ValueType

	--- @alias ValueType
	--- | TypeNil
	--- | TypeBoolean
	--- | TypeInteger
	--- | TypeNumber
	--- | TypeString
	--- | TypeDynamic
	--- | TypeParameter
	--- | TypeStruct
	--- | TypeArray
	--- | TypeBuffer
	--- | TypeRef

	--- @param register_id RegisterId
	--- @return RegisterIdLookup
	function IR.reg_to_lookup(register_id)
		if register_id.register_kind == "temporary" then
			return "t" .. register_id.temporary_id
		else
			return "v" .. register_id.variable_name .. ":" .. register_id.variable_tag .. ":" .. register_id.ssa_version
		end
	end

	--- @param register_lookup RegisterIdLookup
	--- @return RegisterId
	function IR.lookup_to_reg(register_lookup)
		if register_lookup:sub(1, 1) == "t" then
			local temporary_id = tonumber(register_lookup:sub(2)) or error "internal_bug: invalid temporary register lookup"
			return { register_kind = "temporary", temporary_id = temporary_id }
		else
			local var_name, var_tag_str, ssa_version_str = register_lookup:match("^v([^:]+):([^:]+):([^:]+)$")
			local var_tag = tonumber(var_tag_str) or error "internal_bug: invalid variable tag in register lookup"
			local ssa_version = tonumber(ssa_version_str) or error "internal_bug: invalid SSA version in register lookup"
			return { register_kind = "variable", variable_name = var_name, variable_tag = var_tag, ssa_version = ssa_version }
		end
	end

	--- @param register_id RegisterId
	--- @return RegisterValueRef
	function IR.reg_to_value(register_id)
		return { value_kind = "register", register_id = register_id }
	end

	--- @param constant boolean | number | string
	--- @param known_type ValueType?
	--- @return ConstantValueRef
	function IR.constant_to_value(constant, known_type)
		if not known_type then
			--- @type string
			local type_kind = type(constant)
			local as_number = tonumber(constant)
			if as_number then
				if as_number % 1 == 0 then
					type_kind = "integer"
				else
					type_kind = "number"
				end
			elseif constant == "true" or constant == "false" then
				type_kind = "boolean"
			elseif constant == "nil" then
				type_kind = "nil"
			end
			known_type = vsl_types.from_primitive_type(type_kind)
		end
		return { value_kind = "constant", constant_value = tostring(constant), constant_type = known_type }
	end

	--- @param field_name string | integer
	--- @return ConstantValueRef
	function IR.field_name_to_value(field_name)
		if type(field_name) == "string" then
			return { value_kind = "constant", constant_value = string.format("%q", field_name), constant_type = IR.STRING_TYPE }
		else
			return { value_kind = "constant", constant_value = tostring(field_name), constant_value_type = IR.INTEGER_TYPE }
		end
	end

	--- @param struct_def StructDef
	--- @return TypeStruct
	function IR.struct_def_to_type(struct_def)
		--- @type TypeStructField[]
		local struct_fields = {}
		for _, field in ipairs(struct_def.fields) do
			table.insert(struct_fields, {
				name = field.name,
				offset = field.offset,
				type = field.type,
			})
		end

		--- @type TypeStruct
		return {
			type_kind = "struct",
			struct_name_hint = struct_def.name,
			struct_fields = struct_fields,
		}
	end

	IR.NIL_TYPE = vsl_types.NIL_TYPE
	IR.BOOLEAN_TYPE = vsl_types.BOOLEAN_TYPE
	IR.INTEGER_TYPE = vsl_types.INTEGER_TYPE
	IR.NUMBER_TYPE = vsl_types.NUMBER_TYPE
	IR.STRING_TYPE = vsl_types.STRING_TYPE
	IR.DYNAMIC_TYPE = vsl_types.DYNAMIC_TYPE
	IR.NIL = vsl_types.NIL
	IR.from_primitive_type = vsl_types.from_primitive_type
	IR.type_parameter = vsl_types.type_parameter
	IR.struct_type = vsl_types.struct_type
	IR.array_type = vsl_types.array_type
	IR.buffer_type = vsl_types.buffer_type
	IR.ref_type = vsl_types.ref_type
	IR.type_name = vsl_types.type_to_string
	IR.is_type_assignable = vsl_types.is_type_assignable
	IR.type_flattened_element_count = vsl_types.type_flattened_element_count
end

local GlobalCtx
do
	--- @class GlobalCtx
	--- @field private scope { [string]: GlobalValue }
	GlobalCtx = {}

	--- @alias GlobalValue GlobalFn | GlobalStruct | GlobalOpaqueFn

	--- @class GlobalFn
	--- @field global_kind "function"
	--- @field name string
	--- @field function_definition FnDef

	--- @class GlobalStruct
	--- @field global_kind "struct"
	--- @field name string
	--- @field struct_definition StructDef

	--- @class GlobalOpaqueFn
	--- @field global_kind "opaque function"
	--- @field name string
	--- @field opaque_fn_pure boolean
	--- @field opaque_fn_type_parameters string[]
	--- @field opaque_fn_params NameAndType[]
	--- @field opaque_fn_return_type ValueType

	function GlobalCtx.new()
		--- @type GlobalCtx
		local ctx = {
			scope = {},
		}
		return setmetatable(ctx, { __index = GlobalCtx })
	end

	function GlobalCtx:shallow_copy()
		local ctx = GlobalCtx.new()
		for k, v in pairs(self.scope) do
			ctx.scope[k] = v
		end
		return ctx
	end

	--- @param definitions { [any]: Definition }
	--- @return GlobalCtx
	function GlobalCtx:add_definitions(definitions)
		for _, definition in pairs(definitions) do
			if definition.type == "struct" then
				self.scope[definition.name] = { global_kind = "struct", name = definition.name, struct_definition = definition }
			else
				self.scope[definition.name] = { global_kind = "function", name = definition.name, function_definition = definition }
			end
		end
		return self
	end

	--- @param name string
	--- @param pure boolean
	--- @param type_parameters string[]
	--- @param params NameAndType[]
	--- @param return_type ValueType?
	--- @return GlobalCtx
	function GlobalCtx:define_opaque_fn(name, pure, type_parameters, params, return_type)
		--- @type GlobalOpaqueFn
		self.scope[name] = {
			global_kind = "opaque function",
			name = name,
			opaque_fn_pure = pure,
			opaque_fn_type_parameters = type_parameters,
			opaque_fn_params = params,
			opaque_fn_return_type = return_type or IR.NIL_TYPE,
		}
		return self
	end

	--- @param name string
	--- @param type_parameters string[]
	--- @param can_construct boolean
	--- @param fields StructDefField[]
	--- @param tuple_constructor? StructDefField[]
	--- @return GlobalCtx
	function GlobalCtx:define_type(name, type_parameters, can_construct, fields, tuple_constructor)
		--- @type GlobalStruct
		self.scope[name] = {
			global_kind = "struct",
			name = name,
			struct_definition = {
				name = name,
				can_construct = can_construct,
				fields = fields,
				type = "struct",
				type_parameters = type_parameters,
				tuple_constructor = tuple_constructor,
			}
		}
		return self
	end

	--- @param name_token Token
	--- @return GlobalValue
	function GlobalCtx:lookup(name_token)
		return self.scope[name_token.text] or vsl_parse.error_at(name_token.position, "'" .. name_token.text .. "' is undefined")
	end

	--- @param name_token Token
	--- @return StructDef
	function GlobalCtx:lookup_expect_struct(name_token)
		--- @type GlobalValue
		local def = self.scope[name_token.text]
		if not def then
			return vsl_parse.error_at(name_token.position, "Undefined type '" .. name_token.text .. "'")
		elseif def.global_kind == "struct" then
			return def.struct_definition
		else
			return vsl_parse.error_at(name_token.position, "Expected type but got " .. def.global_kind .. " '" .. name_token.text .. "'")
		end
	end
end

local FnCtx
do
	--- @class FnCtx
	--- @field globals GlobalCtx
	--- @field scope_stack ScopeFrame[]
	--- @field type_parameter_lookup { [string]: true }
	--- @field naming NamingCtx
	--- @field private block_stack Block[]
	--- @field private block_lookup { [BlockId]: Block }
	--- @field private registers { [RegisterIdLookup]: RegisterAssignment }
	--- @field private main_block_id BlockId
	--- @field empty_block_id BlockId
	--- @field break_block_id BlockId
	FnCtx = {}

	--- @class ScopeFrame
	--- @field variables { [string]: LocalScopeEntry }
	--- @field ssa_lookup { [VariableNameAndTagKey]: SsaVersion }

	--- @class LocalScopeEntry
	--- @field variable_name string
	--- @field variable_tag VariableTag
	--- @field variable_type ValueType

	--- @param globals GlobalCtx
	--- @return FnCtx
	function FnCtx.new(globals, type_parameters, params)
		--- @type { string: LocalScopeEntry }
		local current_scope = {}

		--- @type Statement[]
		local main_block = { statements = {} }

		local type_parameter_lookup = {}
		for _, type_parameter in ipairs(type_parameters) do
			type_parameter_lookup[type_parameter] = true
		end

		local naming = NamingCtx.new()
		local main_block_id = naming:next_block_id()
		local empty_block_id = naming:next_block_id()
		local break_block_id = naming:next_block_id()

		--- @type FnCtx
		local ctx = {
			globals = globals,
			scope_stack = { { variables = current_scope, ssa_lookup = {} } },
			type_parameter_lookup = type_parameter_lookup,
			naming = naming,
			ssa_lookup = {},
			name_fixer = {},
			block_lookup = {
				[main_block_id] = main_block,
				[empty_block_id] = { statements = {} },
				[break_block_id] = { statements = { { statement_kind = "break" } } },
			},
			block_stack = { main_block },
			registers = {},
			main_block_id = main_block_id,
			empty_block_id = empty_block_id,
			break_block_id = break_block_id,
		}

		setmetatable(ctx, { __index = FnCtx })

		for i, param in ipairs(params) do
			local register_id = ctx:declare_local(param.name, param.type)
			ctx:assign_and_evaluate_register(register_id, {
				assign_kind = "load_param",
				register_type = param.type,
				load_param_index = i,
			})
		end

		return ctx
	end

	--- @param name string
	--- @return boolean
	function FnCtx:is_type_parameter(name)
		return self.type_parameter_lookup[name] or false
	end

	function FnCtx:get_type_lookup()
		return function(name_token)
			for i = #self.scope_stack, 1, -1 do
				if self.scope_stack[i].variables[name_token.text] then
					return vsl_parse.error_at(name_token.position, "'" .. name_token.text .. "' is not a type")
				end
			end

			if self.type_parameter_lookup[name_token.text] then
				--- @type TypeParameter
				return IR.type_parameter(name_token.text)
			else
				return IR.struct_def_to_type(self.globals:lookup_expect_struct(name_token))
			end
		end
	end

	--- @param name string
	--- @param var_type ValueType
	--- @return VariableRegister
	function FnCtx:declare_local(name, var_type)
		local top_scope_stack = self.scope_stack[#self.scope_stack]
		local tag = self.naming:next_variable_tag(name)
		local name_and_tag = NamingCtx.name_and_tag_key(name, tag)
		local ssa_version = self.naming:next_ssa_version_raw(name_and_tag)

		--- @type LocalScopeEntry
		top_scope_stack.variables[name] = { variable_name = name, variable_tag = tag, variable_type = var_type }
		top_scope_stack.ssa_lookup[name_and_tag] = ssa_version

		--- @type VariableRegister
		return { register_kind = "variable", variable_name = name, variable_tag = tag, ssa_version = ssa_version }
	end

	--- @param name string
	--- @return VariableRegister
	function FnCtx:declare_anonymous_local(name)
		local tag = self.naming:next_variable_tag(name)
		local name_and_tag = NamingCtx.name_and_tag_key(name, tag)
		local ssa_version = self.naming:next_ssa_version_raw(name_and_tag)

		--- @type VariableRegister
		return { register_kind = "variable", variable_name = name, variable_tag = tag, ssa_version = ssa_version }
	end

	--- @return TemporaryRegister
	function FnCtx:declare_temporary()
		--- @type TemporaryRegister
		return { register_kind = "temporary", temporary_id = self.naming:next_temporary_id() }
	end

	--- @param register_id RegisterId
	--- @param assignment RegisterAssignment
	--- @return RegisterId
	function FnCtx:assign_register(register_id, assignment)
		self.registers[IR.reg_to_lookup(register_id)] = assignment
		return register_id
	end

	--- @param register_id RegisterId
	--- @param assignment RegisterAssignment
	--- @return RegisterId
	function FnCtx:assign_and_evaluate_register(register_id, assignment)
		self:push_statement({ statement_kind = "evaluate", evaluate_register_id = register_id })
		return self:assign_register(register_id, assignment)
	end

	--- @param variable_name string
	--- @return boolean
	function FnCtx:is_defined(variable_name)
		for i = #self.scope_stack, 1, -1 do
			local scope = self.scope_stack[i]
			if scope.variables[variable_name] then
				return true
			end
		end
		return false
	end

	--- @param variable_tk Token
	--- @return VariableTag, ValueType
	function FnCtx:lookup_variable(variable_tk)
		for i = #self.scope_stack, 1, -1 do
			local scope = self.scope_stack[i]
			local entry = scope.variables[variable_tk.text]
			if entry then
				return entry.variable_tag, entry.variable_type
			end
		end
		if self:is_type_parameter(variable_tk.text) then
			return vsl_parse.error_at(variable_tk.position, "'" .. variable_tk.text .. "' is a type parameter and cannot be used as a variable"), IR.DYNAMIC_TYPE
		else
			return vsl_parse.error_at(variable_tk.position, "'" .. variable_tk.text .. "' is not a variable"), IR.DYNAMIC_TYPE
		end
	end

	--- @param variable_name string
	--- @param variable_tag VariableTag
	--- @return SsaVersion
	function FnCtx:get_variable_ssa_version(variable_name, variable_tag)
		local ssa_lookup = NamingCtx.name_and_tag_key(variable_name, variable_tag)
		for i = #self.scope_stack, 1, -1 do
			local scope = self.scope_stack[i]
			local entry = scope.ssa_lookup[ssa_lookup]
			if entry then
				return entry
			end
		end
		error("internal bug: SSA version not found for " .. variable_name)
	end

	--- @param register_id RegisterId
	--- @return RegisterAssignment
	function FnCtx:get_register_assignment(register_id)
		return self.registers[IR.reg_to_lookup(register_id)] or error("internal bug: no assignment for register " .. IR.reg_to_lookup(register_id))
	end

	--- @param variable_name string
	--- @param variable_tag VariableTag
	--- @return SsaVersion
	function FnCtx:gen_new_ssa_version(variable_name, variable_tag)
		return self.naming:next_ssa_version(variable_name, variable_tag)
	end

	--- @param variable_name string
	--- @param variable_tag VariableTag
	--- @param ssa_version SsaVersion
	function FnCtx:commit_new_version(variable_name, variable_tag, ssa_version)
		local name_and_tag = NamingCtx.name_and_tag_key(variable_name, variable_tag)
		self.scope_stack[#self.scope_stack].ssa_lookup[name_and_tag] = ssa_version
	end

	--- @param statement Statement
	function FnCtx:push_statement(statement)
		table.insert(self.block_stack[#self.block_stack].statements, statement)
	end

	--- @return BlockId, Statement[]
	function FnCtx:alloc_block()
		local statements = {}
		local block_id = self.naming:next_block_id()
		self.block_lookup[block_id] = { statements = statements }
		return block_id, statements
	end

	--- @return BlockId
	function FnCtx:push_block()
		local block = { statements = {} }
		local block_id = self.naming:next_block_id()
		self.block_lookup[block_id] = block
		table.insert(self.scope_stack, { variables = {}, ssa_lookup = {} })
		table.insert(self.block_stack, block)
		return block_id
	end

	--- @return { [VariableNameAndTagKey]: SsaVersion }
	function FnCtx:finish_block()
		table.remove(self.block_stack)
		return table.remove(self.scope_stack).ssa_lookup
	end

	function FnCtx:push_scope()
		table.insert(self.scope_stack, { variables = {}, ssa_lookup = self.scope_stack[#self.scope_stack].ssa_lookup })
	end

	function FnCtx:finish_scope()
		table.remove(self.scope_stack)
	end

	--- @return BlockId
	function FnCtx:push_loop_ssa_block()
		local ssa_lookup = {}
		table.insert(self.scope_stack, { variables = {}, ssa_lookup = ssa_lookup })

		local block_id = self:push_block()

		for i = 1, #self.scope_stack do
			for name_and_tag in pairs(self.scope_stack[i].ssa_lookup) do
				ssa_lookup[name_and_tag] = true
			end
		end

		for name_and_tag in pairs(ssa_lookup) do
			local next_ssa_version = self.naming:next_ssa_version_raw(name_and_tag)
			ssa_lookup[name_and_tag] = next_ssa_version

			local name, tag_str = name_and_tag:match("^(.-):(%d+)$")
			local tag = tonumber(tag_str) or error "internal error: tag was not a number"
			self:push_statement({
				statement_kind = "evaluate",
				evaluate_register_id = { register_kind = "variable", variable_name = name, variable_tag = tag, ssa_version = next_ssa_version }
			})
		end

		return block_id
	end

	function FnCtx:finish_loop_ssa_block()
		local inner_ssa_lookup = self:finish_block()

		local loop_ssa_lookup = table.remove(self.scope_stack).ssa_lookup
		local current_ssa_lookup = self.scope_stack[#self.scope_stack].ssa_lookup

		for name_and_tag, loop_ssa_version in pairs(loop_ssa_lookup) do
			local new_ssa_version = inner_ssa_lookup[name_and_tag]
			local name, tag_str = name_and_tag:match("^(.-):(%d+)$")
			local tag = tonumber(tag_str) or error "internal error: tag was not a number"

			local pre_loop_ssa_version
			for i = #self.scope_stack, 1, -1 do
				local iter_scope_frame = self.scope_stack[i]
				pre_loop_ssa_version = iter_scope_frame.ssa_lookup[name_and_tag]
				if pre_loop_ssa_version then
					break
				end
			end

			local phi_register_id = { type = "variable", variable_name = name, variable_tag = tag, ssa_version = loop_ssa_version }
			--- @type VariableRegister
			local pre_loop_register_id = { register_kind = "variable", variable_name = name, variable_tag = tag, ssa_version = pre_loop_ssa_version }

			if inner_ssa_lookup[name_and_tag] then
				local register_type = self:get_register_assignment(pre_loop_register_id).register_type
				-- loop modified the variable and therefore we must assign a phi node and update our
				-- current scope to reflect the new variable

				--- @type VariableRegister
				local new_register_id = { register_kind = "variable", variable_name = name, variable_tag = tag, ssa_version = new_ssa_version }
				self:assign_register(phi_register_id, { assign_kind = "phi", register_type = register_type, phi_primary = pre_loop_register_id, phi_secondary = new_register_id })
				current_ssa_lookup[name_and_tag] = loop_ssa_version
			else
				-- loop did not modify the variable, therefore we leave our current scope untouched
				-- so new references to the variable will use the pre-loop SSA version, and produce
				-- a simple move which will be optimised out/discarded later
				-- TODO: FIXME: IR.DYNAMIC_TYPE is a hack!
				--- @type RegisterAssignment
				local assignment = { assign_kind = "move", register_type = IR.DYNAMIC_TYPE, move_value = IR.reg_to_value(pre_loop_register_id) }
				self:assign_register(phi_register_id, assignment)
			end

			-- note, in both cases, we do not produce a statement to evaluate the register
			-- this is because we would need to put it before the already-written loop, and
			-- fortunately the evaluation would be a no-op since it's just an SSA re-versioning
			-- we still need to provide an assignment for all registers so that optimisation passes
			-- can properly reason about the values, for example inlining aliases (like with the
			-- latter case from above)
		end
	end

	--- @param ssa_changes { [VariableNameAndTagKey]: SsaVersion }
	function FnCtx:apply_ssa_changes(ssa_changes)
		local top_scope_ssa = self.scope_stack[#self.scope_stack].ssa_lookup
		for name_and_tag, ssa_version in pairs(ssa_changes) do
			top_scope_ssa[name_and_tag] = ssa_version
		end
	end

	--- @param name string
	--- @param type_parameters string[]
	--- @param params FnDefParameter[]
	--- @param return_type ValueType
	--- @param return_value ValueRef?
	--- @return FnDef
	function FnCtx:build(name, type_parameters, params, return_type, return_value)
		--- @type FnDef
		return {
			type = "function",
			name = name,
			type_parameters = type_parameters,
			params = params,
			return_type = return_type,
			return_value = return_value,
			blocks = self.block_lookup,
			registers = self.registers,
			main_block = self.main_block_id,
			naming = self.naming,
		}
	end
end

local FnInliningCtx
do
	--- @class FnInliningCtx
	--- @field fn_ctx FnCtx
	--- @field private type_parameter_assignments { [string]: ValueType }
	--- @field parameters ValueRef[]
	--- @field fn_registers { [RegisterIdLookup]: RegisterAssignment }
	--- @field block_id_mapping { [BlockId]: BlockId }
	--- @field private block_statements { [BlockId]: Statement[] } maps old block IDs to new statement list
	--- @field register_mapping { [RegisterIdLookup]: RegisterId }
	--- @field variable_mapping { [VariableNameAndTagKey]: VariableTag }
	FnInliningCtx = {}

	--- @param ctx FnInliningCtx
	--- @param register_id RegisterId
	--- @return RegisterId
	local function transform_register_id(ctx, register_id)
		local new_register_id = ctx.register_mapping[IR.reg_to_lookup(register_id)]
		if new_register_id then
			return new_register_id
		end
		if register_id.register_kind == "temporary" then
			new_register_id = ctx.fn_ctx:declare_temporary()
		else
			local src_variable_name = register_id.variable_name
			local src_variable_tag = register_id.variable_tag
			local name_and_tag_key = NamingCtx.name_and_tag_key(src_variable_name, src_variable_tag)
			local new_variable_tag = ctx.variable_mapping[name_and_tag_key]
			if not new_variable_tag then
				new_variable_tag = ctx.fn_ctx.naming:next_variable_tag(src_variable_name)
				ctx.variable_mapping[name_and_tag_key] = new_variable_tag
			end
			new_register_id = { register_kind = "variable", variable_name = src_variable_name, variable_tag = new_variable_tag, ssa_version = register_id.ssa_version }
		end
		ctx.register_mapping[IR.reg_to_lookup(register_id)] = new_register_id
		return new_register_id
	end

	--- @param ctx FnInliningCtx
	--- @param assignment RegisterAssignment
	--- @return RegisterAssignment
	local function transform_assignment(ctx, assignment)
		if assignment.assign_kind == "load_param" then
			--- @type RegAssignMove
			return {
				assign_kind = "move",
				register_type = ctx:transform_type(assignment.register_type),
				move_value = ctx.parameters[assignment.load_param_index],
			}
		elseif assignment.assign_kind == "phi" then
			error "TODO: transform_assignment not implemented for phi"
		elseif assignment.assign_kind == "move" then
			--- @type RegAssignMove
			return {
				assign_kind = "move",
				register_type = ctx:transform_type(assignment.register_type),
				move_value = ctx:transform_value_ref(assignment.move_value),
			}
		elseif assignment.assign_kind == "create_table" then
			local elements = {}
			for _, field in ipairs(assignment.table_elements) do
				table.insert(elements, {
					key = ctx:transform_value_ref(field.key),
					value = ctx:transform_value_ref(field.value),
				})
			end
			--- @type RegAssignTable
			return {
				assign_kind = "create_table",
				register_type = ctx:transform_type(assignment.register_type),
				table_elements = elements,
			}
		elseif assignment.assign_kind == "get_index" then
			--- @type RegAssignGetIndex
			return {
				assign_kind = "get_index",
				register_type = ctx:transform_type(assignment.register_type),
				get_index_subject = ctx:transform_value_ref(assignment.get_index_subject),
				get_index = ctx:transform_value_ref(assignment.get_index),
			}
		elseif assignment.assign_kind == "cast" then
			error "TODO: transform_assignment not implemented for cast"
		elseif assignment.assign_kind == "call_fn" then
			error "TODO: transform_assignment not implemented for call_fn"
		elseif assignment.assign_kind == "infix_op" then
			--- @type RegAssignInfixOp
			return {
				assign_kind = "infix_op",
				register_type = ctx:transform_type(assignment.register_type),
				infix_op_lvalue = ctx:transform_value_ref(assignment.infix_op_lvalue),
				infix_op_operator = assignment.infix_op_operator,
				infix_op_rvalue = ctx:transform_value_ref(assignment.infix_op_rvalue),
			}
		elseif assignment.assign_kind == "prefix_op" then
			error "TODO: transform_assignment not implemented for prefix_op"
		else
			error("internal error: unknown assignment kind " .. tostring(assignment.assign_kind))
		end
	end

	--- @param ctx FnInliningCtx
	--- @param statement Statement
	--- @return Statement
	local function transform_statement(ctx, statement)
		if statement.statement_kind == "evaluate" then
			local new_reg_id = transform_register_id(ctx, statement.evaluate_register_id)
			local old_assignment = ctx.fn_registers[IR.reg_to_lookup(statement.evaluate_register_id)]
			local new_assignment = transform_assignment(ctx, old_assignment)
			ctx.fn_ctx:assign_register(new_reg_id, new_assignment)
			--- @type EvalStatement
			return { statement_kind = "evaluate", evaluate_register_id = new_reg_id }
		elseif statement.statement_kind == "set_index" then
			--- @type SetIndexStatement
			return {
				statement_kind = "set_index",
				set_index_subject = transform_register_id(ctx, statement.set_index_subject),
				set_index = ctx:transform_value_ref(statement.set_index),
				set_index_value = ctx:transform_value_ref(statement.set_index_value),
			}
		elseif statement.statement_kind == "if" then
			--- @type IfStatement
			return {
				statement_kind = "if",
				if_condition = ctx:transform_value_ref(statement.if_condition),
				if_true = ctx.block_id_mapping[statement.if_true],
				if_false = ctx.block_id_mapping[statement.if_false],
			}
		elseif statement.statement_kind == "loop" then
			--- @type LoopStatement
			return {
				statement_kind = "loop",
				loop_body = ctx.block_id_mapping[statement.loop_body],
			}
		elseif statement.statement_kind == "break" then
			return statement
		else
			error("internal error: unknown statement kind " .. tostring(statement.statement_kind))
		end
	end

	--- @param fn_ctx FnCtx
	--- @param type_parameter_assignments { [string]: ValueType }
	--- @param parameters ValueRef[]
	--- @param fn_registers { [RegisterIdLookup]: RegisterAssignment }
	--- @return FnInliningCtx
	function FnInliningCtx.new(fn_ctx, type_parameter_assignments, parameters, fn_registers)
		--- @type FnInliningCtx
		local ctx = {
			fn_ctx = fn_ctx,
			type_parameter_assignments = type_parameter_assignments,
			parameters = parameters,
			fn_registers = fn_registers,
			block_id_mapping = {},
			block_statements = {},
			register_mapping = {},
			variable_mapping = {},
		}
		return setmetatable(ctx, { __index = FnInliningCtx })
	end

	--- @param block_id BlockId
	function FnInliningCtx:declare_block(block_id)
		local new_block_id, block_statements = self.fn_ctx:alloc_block()
		self.block_id_mapping[block_id] = new_block_id
		self.block_statements[block_id] = block_statements
	end

	--- @param block_id BlockId
	--- @param block Block
	function FnInliningCtx:populate_block(block_id, block)
		local statements = self.block_statements[block_id]
		for _, statement in ipairs(block.statements) do
			table.insert(statements, transform_statement(self, statement))
		end
	end

	--- @param statement Statement
	function FnInliningCtx:transform_emit_statement(statement)
		self.fn_ctx:push_statement(transform_statement(self, statement))
	end

	--- @param value_ref ValueRef
	--- @return ValueRef
	function FnInliningCtx:transform_value_ref(value_ref)
		if value_ref.value_kind == "constant" then
			return value_ref
		else
			--- @type ValueRef
			return { value_kind = "register", register_id = transform_register_id(self, value_ref.register_id) }
		end
	end

	--- @param value_type ValueType
	--- @return ValueType
	function FnInliningCtx:transform_type(value_type)
		return value_type -- TODO!
	end
end

local UNARY_OPERATOR_PRECEDENCE = 7
local ADD_SUB_OPERATOR_PRECEDENCE = 5
local MUL_DIV_MOD_OPERATOR_PRECEDENCE = 6
local EXP_OPERATOR_PRECEDENCE = 8
local CONCAT_OPERATOR_PRECEDENCE = 4
local EQUALITY_OPERATOR_PRECEDENCE = 3
local AND_OPERATOR_PRECEDENCE = 2
local OR_OPERATOR_PRECEDENCE = 1


--- @type function(parser: ParseCtx, lookup_name: function(Token): ValueType) -> ValueType
local parse_type
do
	function parse_type(parser, lookup_name)
		if parser:consume("nil") then
			return vsl_types.NIL_TYPE
		elseif parser:consume("bool") or parser:consume("boolean") then
			--- @type ValueType
			return vsl_types.BOOLEAN_TYPE
		elseif parser:consume("integer") then
			--- @type ValueType
			return vsl_types.INTEGER_TYPE
		elseif parser:consume("number") then
			--- @type ValueType
			return vsl_types.NUMBER_TYPE
		elseif parser:consume("string") then
			--- @type ValueType
			return vsl_types.STRING_TYPE
		elseif parser:consume("dynamic") then
			return vsl_types.DYNAMIC_TYPE
		elseif parser:consume("buffer") then
			parser:expect("<")
			local element = parse_type(parser, lookup_name)
			parser:expect(">")
			--- @type TypeBuffer
			return vsl_types.buffer_type(element)
		elseif parser:consume("array") then
			parser:expect("<")
			local element = parse_type(parser, lookup_name)
			parser:expect(",")
			local size_token = parser:expect_type(vsl_parse.TokenType.NUMBER)
			local size = tonumber(size_token.text)
			if size == nil or size < 0 or size % 1 ~= 0 then
				return vsl_parse.error_at(size_token.position, "Expected positive integer for array size")
			end
			parser:expect(">")
			--- @type TypeArray
			return vsl_types.array_type(element, size)
		elseif parser:test_type(vsl_parse.TokenType.IDENTIFIER) then
			return lookup_name(parser:advance())
		else
			return parser:error_next("Expected type reference")
		end
	end
end

--- @type function(parser: ParseCtx, fn_ctx: FnCtx) -> Expr
local parse_expr
do
	--- @alias ExtendedInfixOpName InfixOpName | "gt" | "gte" | "and" | "or"

	--- @class Expr
	--- @field expr_position TokenPosition
	--- @field expr_type ValueType

	--- @class LiteralExpr: Expr
	--- @field expr_kind "literal"
	--- @field expr_position TokenPosition
	--- @field expr_type ValueType
	--- @field literal_value string

	--- @class VariableExpr: Expr
	--- @field expr_kind "variable"
	--- @field expr_position TokenPosition
	--- @field expr_type ValueType
	--- @field variable_name string
	--- @field variable_tag VariableTag

	--- @class TableExpr: Expr
	--- @field expr_kind "create_table"
	--- @field expr_position TokenPosition
	--- @field expr_type ValueType
	--- @field table_elements { key: Expr, value: Expr }[]

	--- @class InlinedCallExpr: Expr
	--- @field expr_kind "inlined_call"
	--- @field expr_position TokenPosition
	--- @field expr_type ValueType
	--- @field inlined_call_fn FnDef
	--- @field inlined_call_parameters Expr[]
	--- @field inlined_call_type_parameter_assignments { [string]: ValueType }

	--- @class OpaqueCallExpr: Expr
	--- @field expr_kind "opaque_call"
	--- @field expr_position TokenPosition
	--- @field expr_type ValueType
	--- @field opaque_call_name string
	--- @field opaque_call_pure boolean
	--- @field opaque_call_parameters Expr[]

	--- @class DynamicMethodCallExpr: Expr
	--- @field expr_kind "dynamic_call"
	--- @field expr_position TokenPosition
	--- @field expr_type ValueType
	--- @field dynamic_subject Expr
	--- @field dynamic_call_name string
	--- @field dynamic_call_parameters Expr[]

	--- @class UnbufferRefExpr: Expr
	--- @field expr_kind "unbuffer_ref"
	--- @field expr_position TokenPosition
	--- @field expr_type ValueType
	--- @field unbuffer_ref_subject Expr

	--- @class IndexExpr: Expr
	--- @field expr_kind "get_index"
	--- @field expr_position TokenPosition
	--- @field expr_type ValueType
	--- @field index_subject Expr
	--- @field index Expr

	--- @class NarrowRefExpr: Expr
	--- @field expr_kind "narrow_ref"
	--- @field expr_position TokenPosition
	--- @field expr_type ValueType
	--- @field narrow_ref_subject Expr
	--- @field narrow_ref_offset_delta integer

	--- @class CreateRefExpr: Expr
	--- @field expr_kind "create_ref"
	--- @field expr_position TokenPosition
	--- @field expr_type ValueType
	--- @field create_ref_buffer Expr
	--- @field create_ref_index Expr
	--- @field create_ref_offset integer

	--- @class CastExpr: Expr
	--- @field expr_kind "cast"
	--- @field expr_position TokenPosition
	--- @field expr_type ValueType
	--- @field cast_expr Expr

	--- @class InfixExpr: Expr
	--- @field expr_kind "infix_op"
	--- @field expr_position TokenPosition
	--- @field expr_type ValueType
	--- @field infix_lvalue Expr
	--- @field infix_operator InfixOpName
	--- @field infix_rvalue Expr

	--- @class PrefixExpr: Expr
	--- @field expr_kind "prefix_op"
	--- @field expr_position TokenPosition
	--- @field expr_type ValueType
	--- @field prefix_operator UnaryOpName
	--- @field prefix_rvalue Expr

	--- @class OperatorFragment
	--- @field arity "unary" | "binary"
	--- @field operator UnaryOpName | ExtendedInfixOpName
	--- @field precedence integer
	--- @field position TokenPosition

	--- @type { [string]: { precedence: integer, name: ExtendedInfixOpName } }
	local INFIX_OPERATORS = {
		["+"] = { precedence = ADD_SUB_OPERATOR_PRECEDENCE, name = "add" },
		["-"] = { precedence = ADD_SUB_OPERATOR_PRECEDENCE, name = "sub" },
		["*"] = { precedence = MUL_DIV_MOD_OPERATOR_PRECEDENCE, name = "mul" },
		["/"] = { precedence = MUL_DIV_MOD_OPERATOR_PRECEDENCE, name = "div" },
		["%"] = { precedence = MUL_DIV_MOD_OPERATOR_PRECEDENCE, name = "mod" },
		["^"] = { precedence = EXP_OPERATOR_PRECEDENCE, name = "exp" },
		[".."] = { precedence = CONCAT_OPERATOR_PRECEDENCE, name = "concat" },
		["=="] = { precedence = EQUALITY_OPERATOR_PRECEDENCE, name = "eq" },
		["~="] = { precedence = EQUALITY_OPERATOR_PRECEDENCE, name = "neq" },
		["<"] = { precedence = EQUALITY_OPERATOR_PRECEDENCE, name = "lt" },
		[">"] = { precedence = EQUALITY_OPERATOR_PRECEDENCE, name = "gt" },
		["<="] = { precedence = EQUALITY_OPERATOR_PRECEDENCE, name = "lte" },
		[">="] = { precedence = EQUALITY_OPERATOR_PRECEDENCE, name = "gte" },
		["and"] = { precedence = AND_OPERATOR_PRECEDENCE, name = "and" },
		["or"] = { precedence = OR_OPERATOR_PRECEDENCE, name = "or" },
	}

	local PREFIX_OPERATORS = {
		["-"] = "unm",
		["not"] = "not",
		["#"] = "len",
	}

	--- @param expr_type ValueType
	--- @param expr_value string
	--- @param expr_position TokenPosition
	--- @return LiteralExpr
	local function typed_literal_expr(expr_type, expr_value, expr_position)
		--- @type LiteralExpr
		return { expr_kind = "literal", expr_position = expr_position, expr_type = expr_type, literal_value = expr_value }
	end

	--- @param type ValueType
	--- @param field_token Token
	--- @return ValueType, integer offset
	local function lookup_field(type, field_token)
		if type.type_kind == "ref" then
			return lookup_field(type.ref_element, field_token)
		elseif type.type_kind == "dynamic" then
			return IR.DYNAMIC_TYPE, 0
		elseif type.type_kind == "array" then
			local index = tonumber(field_token.text)
			if not index then
				return vsl_parse.error_at(field_token.position, "invalid array index : " .. field_token.text), 0
			elseif index < 0 or index >= type.array_size or index % 1 ~= 0 then
				return vsl_parse.error_at(field_token.position, "array index out of bounds: " .. index .. " (array size " .. type.array_size .. ")"), 0
			else
				return type.array_element, index * IR.type_flattened_element_count(type.array_element)
			end
		elseif type.type_kind == "struct" then
			local field_name = tonumber(field_token.text) or field_token.text
			for _, field in ipairs(type.struct_fields) do
				if field.name == field_name then
					return field.type, field.offset
				end
			end
			return vsl_parse.error_at(field_token.position, "struct has no field named '" .. field_token.text .. "'"), 0
		else
			return vsl_parse.error_at(field_token.position, "cannot access field " .. field_token.text .. " of type " .. IR.type_name(type)), 0
		end
	end

	--- @param src_type ValueType
	--- @param dst_type ValueType
	--- @param error_pos TokenPosition
	local function assert_type_assignable(src_type, dst_type, error_pos)
		if not IR.is_type_assignable(src_type, dst_type) then
			return vsl_parse.error_at(error_pos, "Cannot assign value of type " .. IR.type_name(src_type) .. " to type " .. IR.type_name(dst_type))
		end
	end

	--- @param src_type ValueType
	--- @param dst_type ValueType
	--- @param error_pos TokenPosition
	local function assert_type_assignable_or_dynamic(src_type, dst_type, error_pos)
		if src_type.type_kind == "dynamic" then
			return
		elseif not IR.is_type_assignable(src_type, dst_type) then
			return vsl_parse.error_at(error_pos, "Cannot assign value of type " .. IR.type_name(src_type) .. " to type " .. IR.type_name(dst_type))
		end
	end

	--- @param src_type ValueType
	--- @param dst_type ValueType
	--- @param error_pos TokenPosition
	local function assert_type_castable(src_type, dst_type, error_pos)
		if src_type.type_kind == "dynamic" or dst_type.type_kind == "dynamic" then
			return
		end
		return assert_type_assignable(src_type, dst_type, error_pos)
	end

	--- @param parser ParseCtx
	--- @param fn_ctx FnCtx
	--- @return { name: Token, value: Expr }
	local function parse_struct_field_init(parser, fn_ctx)
		local name = parser:expect_type(vsl_parse.TokenType.IDENTIFIER)
		parser:expect("=")
		local value = parse_expr(parser, fn_ctx)
		return { name = name, value = value }
	end

	--- @param type_name string
	--- @return string
	local function type_name_to_function_suffix(type_name)
		if type_name:sub(1, 3) == "V3D" then
			type_name = type_name:sub(4)
		end
		local parts = {}
		local first = 1
		local i = string.find(type_name, "%w[A-Z]")
		while i do
			local l = #string.match(type_name, "[A-Z]+", i + 1)
			table.insert(parts, type_name:sub(first, i):lower())
			if l > 1 then
				table.insert(parts, type_name:sub(i + 1, i + l - 1):lower())
			end
			first = i + l
			i = string.find(type_name, "%w[A-Z]", first)
		end
		table.insert(parts, type_name:sub(first):lower())
		return table.concat(parts, "_")
	end

	--- @param assignments { [string]: ValueType }
	--- @param type ValueType
	--- @return ValueType
	local function assign_type_parameters(assignments, type)
		if type.type_kind == "type_parameter" then
			return assignments[type.type_parameter_name] or type
		elseif type.type_kind == "struct" then
			local new_fields = {}
			for _, field in ipairs(type.struct_fields) do
				table.insert(new_fields, { name = field.name, type = assign_type_parameters(assignments, field.type), offset = field.offset })
			end
			return IR.struct_type(new_fields, type.struct_name_hint)
		elseif type.type_kind == "array" then
			return IR.array_type(assign_type_parameters(assignments, type.array_element), type.array_size)
		elseif type.type_kind == "buffer" then
			return IR.buffer_type(assign_type_parameters(assignments, type.buffer_element))
		elseif type.type_kind == "ref" then
			return IR.ref_type(assign_type_parameters(assignments, type.ref_element))
		else
			return type
		end
	end

	--- @param expected_args { type: ValueType }[]
	--- @param actual_args Expr[]
	--- @param ident Token
	--- @return { [string]: ValueType }
	local function type_check_args(expected_args, actual_args, ident)
		if #actual_args < #expected_args then
			return vsl_parse.error_at(ident.position, "Not enough values to call '" .. ident.text .. "' (expected " .. #expected_args .. ", got " .. #actual_args .. ")")
		elseif #actual_args > #expected_args then
			return vsl_parse.error_at(ident.position, "Too many values to call '" .. ident.text .. "' (expected " .. #expected_args .. ", got " .. #actual_args .. ")")
		end

		local type_parameter_assignments = {}
		local function try_assign_parameter(src_type, dst_type)
			if dst_type.type_kind == "type_parameter" then
				if type_parameter_assignments[dst_type.type_parameter_name] then
					dst_type = type_parameter_assignments[dst_type.type_parameter_name]
				else
					type_parameter_assignments[dst_type.type_parameter_name] = src_type
					return true
				end
			end

			if src_type.type_kind == "integer" and dst_type.type_kind == "number" then
				return true
			elseif src_type.type_kind ~= dst_type.type_kind then
				return false
			end

			if src_type.type_kind == "type_parameter" then
				return src_type.type_parameter_name == dst_type.type_parameter_name
			elseif src_type.type_kind == "struct" then
				return true -- TODO
			elseif src_type.type_kind == "array" then
				return src_type.array_size == dst_type.array_size and try_assign_parameter(src_type.array_element, dst_type.array_element)
			elseif src_type.type_kind == "buffer" then
				return try_assign_parameter(src_type.buffer_element, dst_type.buffer_element)
			elseif src_type.type_kind == "ref" then
				return try_assign_parameter(src_type.ref_element, dst_type.ref_element)
			else
				return true
			end
		end

		for i, expected in ipairs(expected_args) do
			local actual = actual_args[i]
			if not try_assign_parameter(actual.expr_type, expected.type) then
				vsl_parse.error_at(actual.expr_position, "Cannot assign value of type " .. IR.type_name(actual.expr_type) .. " to parameter '" .. expected.name .. "' of type " .. IR.type_name(expected.type))
			end
		end

		return type_parameter_assignments
	end

	--- @param field_name string | integer
	--- @param position TokenPosition
	--- @return Expr
	local function field_name_to_expr(field_name, position)
		if type(field_name) == "number" then
			return typed_literal_expr(IR.INTEGER_TYPE, tostring(field_name), position)
		else
			return typed_literal_expr(IR.STRING_TYPE, string.format("%q", field_name), position)
		end
	end

	--- @param fn_ctx FnCtx
	--- @param fn_name Token
	--- @param args Expr[]
	--- @param allow_struct_init boolean
	--- @return Expr
	local function resolve_fn_call(fn_ctx, fn_name, args, allow_struct_init)
		if fn_ctx:is_defined(fn_name.text) then
			-- TODO: possibly calling a local function (do type checking still, expect dynamic)
			return vsl_parse.error_at(fn_name.position, "Local function calls are not yet supported")
		elseif fn_ctx:is_type_parameter(fn_name.text) then
			return vsl_parse.error_at(fn_name.position, "Cannot call type parameter '" .. fn_name.text .. "' as a function")
		else
			local global_value = fn_ctx.globals:lookup(fn_name)

			if global_value.global_kind == "function" then
				local fn = global_value.function_definition
				local type_parameter_assignments = type_check_args(fn.params, args, fn_name)
				--- @type InlinedCallExpr
				return {
					expr_kind = "inlined_call",
					expr_position = fn_name.position,
					expr_type = assign_type_parameters(type_parameter_assignments, fn.return_type),
					inlined_call_fn = fn,
					inlined_call_parameters = args,
					inlined_call_type_parameter_assignments = type_parameter_assignments
				}
			elseif global_value.global_kind == "opaque function" then
				local type_parameter_assignments = type_check_args(global_value.opaque_fn_params, args, fn_name)
				--- @type OpaqueCallExpr
				return {
					expr_kind = "opaque_call",
					expr_position = fn_name.position,
					expr_type = assign_type_parameters(type_parameter_assignments, global_value.opaque_fn_return_type),
					opaque_call_name = global_value.name,
					opaque_call_pure = global_value.opaque_fn_pure,
					opaque_call_parameters = args
				}
			elseif allow_struct_init then -- struct
				local struct = global_value.struct_definition

				if not struct.can_construct then
					return vsl_parse.error_at(fn_name.position, "Cannot initialise struct type '" .. fn_name.text .. "' (private constructor)")
				elseif not struct.tuple_constructor then
					return vsl_parse.error_at(fn_name.position, "Cannot initialise struct type '" .. fn_name.text .. "' as a tuple")
				end

				local type_parameter_assignments = type_check_args(struct.tuple_constructor, args, fn_name)

				local table_elements = {}
				for i, field in ipairs(struct.tuple_constructor) do
					table.insert(table_elements, { key = field_name_to_expr(field.name, fn_name.position), value = args[i] })
				end

				--- @TableExpr
				return {
					expr_kind = "create_table",
					expr_position = fn_name.position,
					expr_type = assign_type_parameters(type_parameter_assignments, IR.struct_def_to_type(struct)),
					table_elements = table_elements
				}
			else
				return vsl_parse.error_at(fn_name.position, "No function named '" .. fn_name.text .. "'")
			end
		end
	end

	--- @param fn_ctx FnCtx
	--- @param struct_name Token
	--- @param fields Expr[]
	--- @return Expr
	local function resolve_struct_table_literal(fn_ctx, struct_name, fields)
		if fn_ctx:is_type_parameter(struct_name.text) then
			return vsl_parse.error_at(struct_name.position, "Cannot initialise type parameter '" .. struct_name.text .. "' as a struct")
		end

		local struct_type = fn_ctx.globals:lookup_expect_struct(struct_name)

		if not struct_type.can_construct then
			return vsl_parse.error_at(struct_name.position, "Cannot initialise struct type '" .. struct_name.text .. "' (private constructor)")
		end

		local required_fields_lookup = {}
		for _, field in ipairs(struct_type.struct_fields) do
			required_fields_lookup[field.name] = field.type
		end

		local create_table_fields = {}
		local assigned_fields = {}
		for _, field in ipairs(fields) do
			local expected_type = required_fields_lookup[field.name.text]
			if assigned_fields[field.name.text] then
				return vsl_parse.error_at(field.name.position, "duplicate field assigned: '" .. field.name.text .. "'")
			elseif expected_type == nil then
				return vsl_parse.error_at(field.name.position, "struct type has no field named '" .. field.name.text .. "'")
			elseif not IR.is_type_assignable(field.value.type, expected_type) then
				return vsl_parse.error_at(field.value.expr_position, "Cannot assign value of type " .. IR.type_name(field.value.type) .. " to field '" .. field.name.text .. "' with type " .. IR.type_name(expected_type))
			end
			assigned_fields[field.name.text] = true
			required_fields_lookup[field.name.text] = nil
			table.insert(create_table_fields, { key = field_name_to_expr(field.name.text, field.name.position), value = field.value })
		end

		local missing_field_name = next(required_fields_lookup)
		if missing_field_name ~= nil then
			return vsl_parse.error_at(struct_name.position, "missing value for field '" .. missing_field_name .. "'")
		end

		--- @type TableExpr
		return {
			expr_kind = "create_table",
			expr_position = struct_name.position,
			expr_type = IR.struct_def_to_type(struct_type),
			table_elements = create_table_fields
		}
	end

	--- @param parser ParseCtx
	--- @param fn_ctx FnCtx
	--- @param ident Token
	--- @return Expr
	local function parse_expr_after_ident(parser, fn_ctx, ident)
		if parser:test("(") then
			local args = parser:list_of("(", parse_expr, ")", fn_ctx)
			return resolve_fn_call(fn_ctx, ident, args, true)
		elseif parser:test("{") then
			local fields = parser:list_of("{", parse_struct_field_init, "}", fn_ctx)
			return resolve_struct_table_literal(fn_ctx, ident, fields)
		else
			local variable_tag, variable_type = fn_ctx:lookup_variable(ident)
			--- @type VariableExpr
			return {
				expr_kind = "variable",
				expr_position = ident.position,
				expr_type = variable_type,
				variable_name = ident.text,
				variable_tag = variable_tag
			}
		end
	end

	--- @return function(parser: ParseCtx, fn_ctx: FnCtx): { key: TypedExpr, value: TypedExpr }
	local function get_table_element_parser()
		local next_array_index = 1
		--- @param parser ParseCtx
		--- @param fn_ctx FnCtx
		return function(parser, fn_ctx)
			if parser:test_type(vsl_parse.TokenType.IDENTIFIER) then
				local ident = parser:advance()
				if parser:consume("=") then
					local value = parse_expr(parser, fn_ctx)
					return { key = field_name_to_expr(ident.text, ident.position), value = value }
				else
					local key = field_name_to_expr(next_array_index, ident.position)
					local value = parse_expr_after_ident(parser, fn_ctx, ident)
					next_array_index = next_array_index + 1
					return { key = key, value = value }
				end
			elseif parser:test("[") then
				parser:advance()
				local key = parse_expr(parser, fn_ctx)
				parser:expect("]")
				parser:expect("=")
				local value = parse_expr(parser, fn_ctx)
				return { key = key, value = value }
			else
				return parser:error_next("Expected table element")
			end
		end
	end

	--- @param parser ParseCtx
	--- @param fn_ctx FnCtx
	--- @return Expr
	local function parse_expr_primary(parser, fn_ctx)
		if parser:test("nil") then
			local token = parser:expect("nil")
			return typed_literal_expr(IR.NIL_TYPE, "nil", token.position)
		elseif parser:test("true") or parser:test("false") then
			local token = parser:expect(vsl_parse.TokenType.KEYWORD)
			return typed_literal_expr(IR.BOOLEAN_TYPE, token.text, token.position)
		elseif parser:test_type(vsl_parse.TokenType.NUMBER) then
			local token = parser:advance()
			--- @type ValueType
			local expr_type = IR.INTEGER_TYPE
			local expr_value = token.text
			if token.text:find "%." then
				expr_type = IR.NUMBER_TYPE
			elseif token.text:sub(1, 2) == "0b" then
				local n = tonumber(token.text:sub(3), 2)
				expr_value = tostring(n)
			end
			return typed_literal_expr(expr_type, expr_value, token.position)
		elseif parser:test_type(vsl_parse.TokenType.STRING) then
			local token = parser:advance()
			return typed_literal_expr(IR.STRING_TYPE, token.text, token.position)
		elseif parser:consume("(") then
			local expr = parse_expr(parser, fn_ctx)
			parser:expect(")")
			return expr
		elseif parser:test_type(vsl_parse.TokenType.IDENTIFIER) then
			local variable_name_tk = parser:advance()
			return parse_expr_after_ident(parser, fn_ctx, variable_name_tk)
		elseif parser:test("{") then
			local position = parser.tokens[parser.current_token_index].position
			local elements = parser:list_of("{", get_table_element_parser(), "}", fn_ctx)
			--- @type TableExpr
			return {
				expr_kind = "create_table",
				expr_position = position,
				expr_type = IR.DYNAMIC_TYPE,
				table_elements = elements
			}
		else
			return parser:error_next("Expected expression")
		end
	end

	--- @param parser ParseCtx
	--- @param expr Expr
	--- @return Expr
	local function parse_dot_index(parser, expr)
		local field_token = parser:advance()
		if not field_token then
			return parser:error_next("Expected field name or numeric index after '.'")
		elseif field_token.type ~= vsl_parse.TokenType.IDENTIFIER and field_token.type ~= vsl_parse.TokenType.NUMBER then
			return vsl_parse.error_at(field_token.position, "Expected field name or numeric index after '.'")
		end

		local field_type, field_offset = lookup_field(expr.expr_type, field_token)

		if expr.expr_type.type_kind == "ref" then
			if expr.expr_kind == "create_ref" then
				--- @type CreateRefExpr
				return {
					expr_kind = "create_ref",
					expr_position = field_token.position,
					expr_type = IR.ref_type(field_type),
					create_ref_buffer = expr.create_ref_buffer,
					create_ref_index = expr.create_ref_index,
					create_ref_offset = expr.create_ref_offset + field_offset,
				}
			else
				--- @type NarrowRefExpr
				return {
					expr_kind = "narrow_ref",
					expr_position = field_token.position,
					expr_type = IR.ref_type(field_type),
					narrow_ref_subject = expr,
					narrow_ref_offset_delta = field_offset,
				}
			end
		elseif field_token.type == vsl_parse.TokenType.IDENTIFIER then
			local field_index = typed_literal_expr(IR.STRING_TYPE, string.format("%q", field_token.text), field_token.position)
			--- @type IndexExpr
			return {
				expr_kind = "get_index",
				expr_position = field_token.position,
				expr_type = field_type,
				index_subject = expr,
				index = field_index,
			}
		else -- number
			local field_index = typed_literal_expr(IR.INTEGER_TYPE, field_token.text, field_token.position)
			--- @type IndexExpr
			return {
				expr_kind = "get_index",
				expr_position = field_token.position,
				expr_type = field_type,
				index_subject = expr,
				index = field_index,
			}
		end
	end

	--- @param parser ParseCtx
	--- @param fn_ctx FnCtx
	--- @param expr Expr
	--- @return Expr
	local function parse_bracketed_index(parser, fn_ctx, expr)
		--- @type Expr
		local index = parse_expr(parser, fn_ctx)
		parser:expect("]")

		if expr.expr_type.type_kind == "dynamic" then
			--- @type IndexExpr
			return {
				expr_kind = "get_index",
				expr_position = index.expr_position,
				expr_type = IR.DYNAMIC_TYPE,
				index_subject = expr,
				index = index
			}
		elseif expr.expr_type.type_kind == "array" then
			--- @type IndexExpr
			return {
				expr_kind = "get_index",
				expr_position = index.expr_position,
				expr_type = expr.expr_type.array_element,
				index_subject = expr,
				index = index
			}
		elseif expr.expr_type.type_kind == "buffer" then
			--- @type CreateRefExpr
			return {
				expr_kind = "create_ref",
				expr_position = index.expr_position,
				expr_type = expr.expr_type.buffer_element,
				create_ref_buffer = expr,
				create_ref_index = index,
				create_ref_offset = 0
			}
		elseif expr.expr_type.type_kind == "ref" and expr.expr_type.ref_element.type_kind == "array" then
			return vsl_parse.error_at(index.expr_position, "cannot narrow ref to an array: not yet implemented")
		else
			return vsl_parse.error_at(index.expr_position, "cannot index into type '" .. IR.type_name(expr.expr_type) .. "'")
		end
	end

	--- @param parser ParseCtx
	--- @param fn_ctx FnCtx
	--- @param expr Expr
	--- @param method_name Token
	--- @param args Expr[]
	--- @return Expr
	local function resolve_method_call(parser, fn_ctx, expr, method_name, args)
		if expr.expr_type.type_kind == "ref" then
			--- @type UnbufferRefExpr
			local unbuffer_expr = {
				expr_kind = "unbuffer_ref",
				expr_position = method_name.position,
				expr_type = expr.expr_type.ref_element,
				unbuffer_ref_subject = expr,
			}
			if method_name.text == "unbuffer" then
				if #args ~= 0 then
					return vsl_parse.error_at(method_name.position, "Method 'unbuffer' does not take any arguments")
				end
				return unbuffer_expr
			else
				return resolve_method_call(parser, fn_ctx, unbuffer_expr, method_name, args)
			end
		elseif expr.expr_type.type_kind == "struct" then
			local type_name = expr.expr_type.struct_name_hint or vsl_parse.error_at(method_name.position, "struct has unknown type name so cannot call methods on it")
			local fn_name = { text = type_name_to_function_suffix(type_name) .. "_" .. method_name.text, position = method_name.position, type = method_name.type }
			table.insert(args, 1, expr)
			return resolve_fn_call(fn_ctx, fn_name, args, false)
		elseif expr.expr_type.type_kind == "dynamic" then
			--- @type DynamicMethodCallExpr
			return {
				expr_kind = "dynamic_call",
				expr_position = method_name.position,
				expr_type = IR.DYNAMIC_TYPE,
				dynamic_subject = expr,
				dynamic_call_name = method_name.text,
				dynamic_call_parameters = args,
			}
		else
			return vsl_parse.error_at(method_name.position, "Cannot call method '" .. method_name.text .. "' on type '" .. IR.type_name(expr.expr_type) .. "'")
		end
	end

	--- @param parser ParseCtx
	--- @param fn_ctx FnCtx
	--- @return Expr
	local function parse_expr_and_suffixes(parser, fn_ctx)
		local expr = parse_expr_primary(parser, fn_ctx)

		while true do
			if parser:consume(".") then
				expr = parse_dot_index(parser, expr)
			elseif parser:consume("[") then
				expr = parse_bracketed_index(parser, fn_ctx, expr)
			elseif parser:consume(":") then
				local method_name = parser:expect_type(vsl_parse.TokenType.IDENTIFIER)
				local args = parser:list_of("(", parse_expr, ")", fn_ctx)
				expr = resolve_method_call(parser, fn_ctx, expr, method_name, args)
			elseif parser:test("::") then
				local tk = parser:advance()
				local cast_type = parse_type(parser, fn_ctx:get_type_lookup())
				assert_type_castable(expr.expr_type, cast_type, tk.position)
				--- @type Expr
				expr = {
					expr_kind = "cast",
					expr_position = tk.position,
					expr_type = cast_type,
					cast_expr = expr
				}
			else
				break
			end
		end

		return expr
	end

	--- @param fn_ctx FnCtx
	--- @param op OperatorFragment
	--- @param rvalue Expr
	--- @return Expr
	local function apply_prefix_operator(fn_ctx, op, rvalue)
		if rvalue.expr_type.type_kind == "ref" then
			--- @type UnbufferRefExpr
			local unbuffer_expr = {
				expr_kind = "unbuffer_ref",
				expr_position = rvalue.expr_position,
				expr_type = rvalue.expr_type.ref_element,
				unbuffer_ref_subject = rvalue
			}
			return apply_prefix_operator(fn_ctx, op, unbuffer_expr)
		elseif rvalue.expr_type.type_kind == "struct" then
			local struct_name = rvalue.expr_type.struct_name_hint or vsl_parse.error_at(rvalue.position, "unknown struct type name so cannot apply operator '" .. op.operator .. "'")
			local fn_name = { text = type_name_to_function_suffix(struct_name) .. "_" .. op.operator, position = op.position, type = vsl_parse.TokenType.IDENTIFIER }
			return resolve_fn_call(fn_ctx, fn_name, { rvalue }, false)
		elseif op.operator == "unm" then
			assert_type_assignable_or_dynamic(rvalue.expr_type, IR.NUMBER_TYPE, op.position)
			local result_type = rvalue.expr_type.type_kind == "integer" and IR.INTEGER_TYPE or IR.NUMBER_TYPE
			--- @type PrefixExpr
			return {
				expr_kind = "prefix_op",
				expr_position = op.position,
				expr_type = result_type,
				prefix_operator = "unm",
				prefix_rvalue = rvalue,
			}
		elseif op.operator == "not" then
			assert_type_assignable_or_dynamic(rvalue.expr_type, IR.BOOLEAN_TYPE, op.position)
			--- @type PrefixExpr
			return {
				expr_kind = "prefix_op",
				expr_position = op.position,
				expr_type = IR.BOOLEAN_TYPE,
				prefix_operator = "not",
				prefix_rvalue = rvalue,
			}
		elseif op.operator == "len" then
			--- @type PrefixExpr
			local expr = {
				expr_kind = "prefix_op",
				expr_position = op.position,
				expr_type = IR.INTEGER_TYPE,
				prefix_operator = "len",
				prefix_rvalue = rvalue,
			}
			if rvalue.expr_type.type_kind == "buffer" then
				--- @type InfixExpr
				local actual_length = {
					expr_kind = "infix_op",
					expr_position = op.position,
					expr_type = IR.INTEGER_TYPE,
					infix_lvalue = expr,
					infix_operator = "div",
					infix_rvalue = typed_literal_expr(IR.INTEGER_TYPE, tostring(IR.type_flattened_element_count(rvalue.expr_type.buffer_element)), op.position),
				}
				return actual_length
			else
				assert_type_assignable_or_dynamic(rvalue.expr_type, IR.STRING_TYPE, op.position)
				return expr
			end
		else
			error "internal bug: unhandled prefix operator"
		end
	end

	--- @param fn_ctx FnCtx
	--- @param op OperatorFragment
	--- @param lvalue Expr
	--- @param rvalue Expr
	--- @return Expr
	local function apply_infix_operator(fn_ctx, op, lvalue, rvalue)
		if lvalue.expr_type.type_kind == "ref" then
			--- @type UnbufferRefExpr
			lvalue = {
				expr_kind = "unbuffer_ref",
				expr_position = lvalue.expr_position,
				expr_type = lvalue.expr_type.ref_element,
				unbuffer_ref_subject = lvalue,
			}
		end

		if rvalue.expr_type.type_kind == "ref" then
			--- @type UnbufferRefExpr
			rvalue = {
				expr_kind = "unbuffer_ref",
				expr_position = rvalue.expr_position,
				expr_type = rvalue.expr_type.ref_element,
				unbuffer_ref_subject = rvalue,
			}
		end

		if op.operator == "gt" or op.operator == "gte" then
			lvalue, rvalue = rvalue, lvalue
			op.operator = op.operator == "gt" and "lt" or "lte"
		end

		if lvalue.expr_type.type_kind == "struct" or rvalue.expr_type.type_kind == "struct" then
			local lvalue_struct_name, rvalue_struct_name

			if lvalue.expr_type.type_kind == "struct" then
				lvalue_struct_name = lvalue.expr_type.struct_name_hint or vsl_parse.error_at(rvalue.position, "unknown lvalue type name so cannot apply operator '" .. op.operator .. "'")
			else
				lvalue_struct_name = lvalue.expr_type.type_kind
			end

			if rvalue.expr_type.type_kind == "struct" then
				rvalue_struct_name = rvalue.expr_type.struct_name_hint or vsl_parse.error_at(rvalue.position, "unknown rvalue type name so cannot apply operator '" .. op.operator .. "'")
			else
				rvalue_struct_name = rvalue.expr_type.type_kind
			end

			local fn_name = { text = type_name_to_function_suffix(lvalue_struct_name) .. "_" .. op.operator .. "_" .. type_name_to_function_suffix(rvalue_struct_name), position = op.position, type = vsl_parse.TokenType.IDENTIFIER }
			return resolve_fn_call(fn_ctx, fn_name, { lvalue, rvalue }, false)
		elseif op.operator == "add" or op.operator == "sub" or op.operator == "mul" or op.operator == "div" or op.operator == "mod" or op.operator == "exp" then
			assert_type_assignable_or_dynamic(lvalue.expr_type, IR.NUMBER_TYPE, lvalue.expr_position)
			assert_type_assignable_or_dynamic(rvalue.expr_type, IR.NUMBER_TYPE, rvalue.expr_position)
			--- @type any screw you Lua LS
			local operator_name = op.operator
			local result_type = lvalue.expr_type.type_kind == "integer" and rvalue.expr_type.type_kind == "integer" and operator_name ~= "div" and operator_name ~= "exp" and IR.INTEGER_TYPE or IR.NUMBER_TYPE
			--- @type InfixExpr
			return {
				expr_kind = "infix_op",
				expr_position = op.position,
				expr_type = result_type,
				infix_lvalue = lvalue,
				infix_operator = operator_name,
				infix_rvalue = rvalue,
			}
		elseif op.operator == "concat" then
			assert_type_assignable_or_dynamic(lvalue.expr_type, IR.STRING_TYPE, lvalue.expr_position)
			assert_type_assignable_or_dynamic(rvalue.expr_type, IR.STRING_TYPE, rvalue.expr_position)
			--- @type InfixExpr
			return {
				expr_kind = "infix_op",
				expr_position = op.position,
				expr_type = IR.STRING_TYPE,
				infix_lvalue = lvalue,
				infix_operator = "concat",
				infix_rvalue = rvalue,
			}
		elseif op.operator == "lt" or op.operator == "lte" then
			assert_type_assignable_or_dynamic(lvalue.expr_type, IR.NUMBER_TYPE, lvalue.expr_position)
			assert_type_assignable_or_dynamic(rvalue.expr_type, IR.NUMBER_TYPE, rvalue.expr_position)
			--- @type any screw you Lua LS
			local operator_name = op.operator
			--- @type InfixExpr
			return {
				expr_kind = "infix_op",
				expr_position = op.position,
				expr_type = IR.BOOLEAN_TYPE,
				infix_lvalue = lvalue,
				infix_operator = operator_name,
				infix_rvalue = rvalue,
			}
		elseif op.operator == "eq" or op.operator == "neq" then
			--- @type any screw you Lua LS
			local operator_name = op.operator
			--- @type InfixExpr
			return {
				expr_kind = "infix_op",
				expr_position = op.position,
				expr_type = IR.BOOLEAN_TYPE,
				infix_lvalue = lvalue,
				infix_operator = operator_name,
				infix_rvalue = rvalue,
			}
		elseif op.operator == "and" then
			error "TODO: unhandled operator and"
		elseif op.operator == "or" then
			error "TODO: unhandled operator or"
		else
			error "internal bug: unhandled binary operator"
		end
	end

	--- @param parser ParseCtx
	--- @param fn_ctx FnCtx
	--- @return Expr
	function parse_expr(parser, fn_ctx)
		--- @type OperatorFragment[]
		local operator_stack = {}
		--- @type Expr[]
		local expression_stack = {}

		local function apply_operator()
			--- @type OperatorFragment
			local op = table.remove(operator_stack)
			--- @type Expr
			local rvalue = table.remove(expression_stack)

			if op.arity == "unary" then
				table.insert(expression_stack, apply_prefix_operator(fn_ctx, op, rvalue))
			else
				--- @type Expr
				local lvalue = table.remove(expression_stack)

				table.insert(expression_stack, apply_infix_operator(fn_ctx, op, lvalue, rvalue))
			end
		end

		while true do
			while true do
				local tk = parser.tokens[parser.current_token_index]
				local prefix_operator_name = tk and PREFIX_OPERATORS[tk.text] or false
				if not prefix_operator_name then
					break
				end
				parser:advance()
				--- @type OperatorFragment
				local op = { arity = "unary", operator = prefix_operator_name, precedence = UNARY_OPERATOR_PRECEDENCE, position = tk.position }
				table.insert(operator_stack, op)
			end

			table.insert(expression_stack, parse_expr_and_suffixes(parser, fn_ctx))

			local tk = parser.tokens[parser.current_token_index]
			local infix_op = tk and INFIX_OPERATORS[tk.text]
			if not infix_op then
				break
			end
			parser:advance()

			--- @type OperatorFragment
			local op = { arity = "binary", operator = infix_op.name, precedence = infix_op.precedence, position = tk.position }

			while operator_stack[#operator_stack] and operator_stack[#operator_stack].precedence >= op.precedence and tk.text ~= "^" do
				apply_operator()
			end

			table.insert(operator_stack, op)
		end

		while operator_stack[1] do
			apply_operator()
		end

		return expression_stack[1]
	end
end

local parse
do
	--- @param src_type ValueType
	--- @param dst_type ValueType
	--- @param error_pos TokenPosition
	local function assert_type_assignable(src_type, dst_type, error_pos)
		if not IR.is_type_assignable(src_type, dst_type) then
			vsl_parse.error_at(error_pos, "Cannot assign " .. IR.type_name(src_type) .. " to " .. IR.type_name(dst_type))
		end
	end

	local encode_expr_to_value_ref

	--- @param fn_ctx FnCtx
	--- @param to_register_id RegisterId
	--- @param buffer_register RegisterId
	--- @param base_offset_register RegisterId
	--- @param unbuffer_type ValueType
	--- @param static_offset number
	local function encode_unbuffer_to_register(fn_ctx, to_register_id, buffer_register, base_offset_register, unbuffer_type, static_offset)
		if unbuffer_type.type_kind == "struct" then
			local table_elements = {}
			for _, field in ipairs(unbuffer_type.struct_fields) do
				local field_register = fn_ctx:declare_temporary()
				encode_unbuffer_to_register(fn_ctx, field_register, buffer_register, base_offset_register, field.type, static_offset + field.offset)
				table.insert(table_elements, { key = IR.field_name_to_value(field.name), value = IR.reg_to_value(field_register) })
			end
			fn_ctx:assign_and_evaluate_register(to_register_id, {
				assign_kind = "create_table",
				register_type = unbuffer_type,
				table_elements = table_elements,
			})
		elseif unbuffer_type.type_kind == "array" then
			error "TODO: unbuffer array"
		else
			local offset_register = base_offset_register

			if static_offset ~= 0 then
				offset_register = fn_ctx:declare_temporary()
				fn_ctx:assign_and_evaluate_register(offset_register, {
					assign_kind = "infix_op",
					register_type = IR.INTEGER_TYPE,
					infix_op_lvalue = IR.reg_to_value(base_offset_register),
					infix_op_operator = "add",
					infix_op_rvalue = IR.constant_to_value(static_offset, IR.INTEGER_TYPE),
				})
			end

			fn_ctx:assign_and_evaluate_register(to_register_id, {
				assign_kind = "get_index",
				register_type = unbuffer_type,
				get_index_subject = IR.reg_to_value(buffer_register),
				get_index = IR.reg_to_value(offset_register),
			})
		end
	end

	--- @param fn_ctx FnCtx
	--- @param buffer_value ValueRef
	--- @param index_value ValueRef
	--- @param static_offset integer
	--- @param register_id RegisterId
	--- @param buffered_type ValueType
	local function encode_create_ref_to_register(fn_ctx, buffer_value, index_value, static_offset, register_id, buffered_type)
		local buffer_stride = IR.type_flattened_element_count(buffered_type)

		local index_register = fn_ctx:declare_temporary()
		fn_ctx:assign_and_evaluate_register(index_register, {
			assign_kind = "infix_op",
			register_type = IR.INTEGER_TYPE,
			infix_op_lvalue = index_value,
			infix_op_operator = "mul",
			infix_op_rvalue = IR.constant_to_value(buffer_stride, IR.INTEGER_TYPE),
		})

		local adjusted_static_offset = static_offset - buffer_stride + 1

		if adjusted_static_offset ~= 0 then
			local applied_offset_register = fn_ctx:declare_temporary()
			fn_ctx:assign_and_evaluate_register(applied_offset_register, {
				assign_kind = "infix_op",
				register_type = IR.INTEGER_TYPE,
				infix_op_lvalue = IR.reg_to_value(index_register),
				infix_op_operator = "add",
				infix_op_rvalue = IR.constant_to_value(adjusted_static_offset, IR.INTEGER_TYPE),
			})
			index_register = applied_offset_register
		end

		fn_ctx:assign_and_evaluate_register(register_id, {
			assign_kind = "create_table",
			register_type = IR.ref_type(buffered_type),
			table_elements = {
				{ key = IR.field_name_to_value("buffer"), value = buffer_value },
				{ key = IR.field_name_to_value("offset"), value = IR.reg_to_value(index_register) },
			}
		})
	end

	--- @param fn_ctx FnCtx
	--- @param expr Expr
	--- @param register_id RegisterId
	local function encode_expr_to_register(fn_ctx, expr, register_id)
		if expr.expr_kind == "literal" then
			fn_ctx:assign_and_evaluate_register(register_id, {
				assign_kind = "move",
				register_type = expr.expr_type,
				move_value = IR.constant_to_value(expr.literal_value, expr.expr_type),
			})
		elseif expr.expr_kind == "variable" then
			local ssa_version = fn_ctx:get_variable_ssa_version(expr.variable_name, expr.variable_tag)
			local assigned_register_id = { register_kind = "variable", variable_name = expr.variable_name, variable_tag = expr.variable_tag, ssa_version = ssa_version }
			fn_ctx:assign_and_evaluate_register(register_id, {
				assign_kind = "move",
				register_type = expr.expr_type,
				move_value = IR.reg_to_value(assigned_register_id),
			})
		elseif expr.expr_kind == "create_table" then
			--- @type { key: ValueRef, value: ValueRef }[]
			local table_values = {}
			for _, element in ipairs(expr.table_elements) do
				local key = encode_expr_to_value_ref(fn_ctx, element.key)
				local value = encode_expr_to_value_ref(fn_ctx, element.value)
				table.insert(table_values, { key = key, value = value })
			end

			--- @type RegAssignTable
			local assignment = {
				assign_kind = "create_table",
				register_type = expr.expr_type,
				table_elements = table_values,
			}
			fn_ctx:assign_and_evaluate_register(register_id, assignment)
		elseif expr.expr_kind == "inlined_call" then
			local parameters = {}
			for _, param in ipairs(expr.inlined_call_parameters) do
				table.insert(parameters, encode_expr_to_value_ref(fn_ctx, param))
			end
			local inlining_ctx = FnInliningCtx.new(fn_ctx, expr.inlined_call_type_parameter_assignments, parameters, expr.inlined_call_fn.registers)

			for block_id in pairs(expr.inlined_call_fn.blocks) do
				if block_id ~= expr.inlined_call_fn.main_block then
					inlining_ctx:declare_block(block_id)
				end
			end

			for block_id, block in pairs(expr.inlined_call_fn.blocks) do
				if block_id ~= expr.inlined_call_fn.main_block then
					inlining_ctx:populate_block(block_id, block)
				end
			end

			for _, statement in ipairs(expr.inlined_call_fn.blocks[expr.inlined_call_fn.main_block].statements) do
				inlining_ctx:transform_emit_statement(statement)
			end

			local return_value = inlining_ctx:transform_value_ref(expr.inlined_call_fn.return_value)

			fn_ctx:assign_and_evaluate_register(register_id, {
				assign_kind = "move",
				register_type = inlining_ctx:transform_type(expr.inlined_call_fn.return_type),
				move_value = return_value,
			})

		elseif expr.expr_kind == "opaque_call" then
			--- @type ValueRef[]
			local parameters = {}
			for _, param in ipairs(expr.opaque_call_parameters) do
				table.insert(parameters, encode_expr_to_value_ref(fn_ctx, param))
			end
			fn_ctx:assign_and_evaluate_register(register_id, {
				assign_kind = "call_fn",
				register_type = expr.expr_type,
				call_fn_name = expr.opaque_call_name,
				call_fn_pure = expr.opaque_call_pure,
				call_fn_parameters = parameters,
			})
		elseif expr.expr_kind == "unbuffer_ref" then
			local ref_subject = encode_expr_to_value_ref(fn_ctx, expr.unbuffer_ref_subject)
			local get_field_buffer = fn_ctx:declare_temporary()
			fn_ctx:assign_and_evaluate_register(get_field_buffer, {
				assign_kind = "get_index",
				register_type = IR.buffer_type(expr.expr_type),
				get_index_subject = ref_subject,
				get_index = IR.field_name_to_value "buffer",
			})
			local get_field_offset = fn_ctx:declare_temporary()
			fn_ctx:assign_and_evaluate_register(get_field_offset, {
				assign_kind = "get_index",
				register_type = IR.INTEGER_TYPE,
				get_index_subject = ref_subject,
				get_index = IR.field_name_to_value "offset",
			})
			encode_unbuffer_to_register(fn_ctx, register_id, get_field_buffer, get_field_offset, expr.expr_type, 0)
		elseif expr.expr_kind == "get_index" then
			fn_ctx:assign_and_evaluate_register(register_id, {
				assign_kind = "get_index",
				register_type = expr.expr_type,
				get_index_subject = encode_expr_to_value_ref(fn_ctx, expr.index_subject),
				get_index = encode_expr_to_value_ref(fn_ctx, expr.index),
			})
		elseif expr.expr_kind == "create_ref" then
			local inner_type = expr.expr_type.ref_element or error "internal bug: create_ref has a non-ref type"
			local buffer = encode_expr_to_value_ref(fn_ctx, expr.create_ref_buffer)
			local index = encode_expr_to_value_ref(fn_ctx, expr.create_ref_index)
			local static_offset = expr.create_ref_offset
			encode_create_ref_to_register(fn_ctx, buffer, index, static_offset, register_id, inner_type)
		elseif expr.expr_kind == "narrow_ref" then
			if expr.narrow_ref_offset_delta == 0 then
				encode_expr_to_register(fn_ctx, expr.narrow_ref_subject, register_id)
				return
			end

			local ref_subject = encode_expr_to_value_ref(fn_ctx, expr.narrow_ref_subject)

			local get_field_buffer = fn_ctx:declare_temporary()
			fn_ctx:assign_and_evaluate_register(get_field_buffer, {
				assign_kind = "get_index",
				register_type = IR.buffer_type(expr.narrow_ref_subject.type.ref_element),
				get_index_subject = ref_subject,
				get_index = IR.field_name_to_value "buffer",
			})
			local get_field_offset = fn_ctx:declare_temporary()
			fn_ctx:assign_and_evaluate_register(get_field_offset, {
				assign_kind = "get_index",
				register_type = IR.INTEGER_TYPE,
				get_index_subject = ref_subject,
				get_index = IR.field_name_to_value "offset",
			})
			local update_field_offset = fn_ctx:declare_temporary()
			fn_ctx:assign_and_evaluate_register(update_field_offset, {
				assign_kind = "infix_op",
				register_type = IR.INTEGER_TYPE,
				infix_op_lvalue = IR.reg_to_value(get_field_offset),
				infix_op_operator = "add",
				infix_op_rvalue = IR.constant_to_value(expr.narrow_ref_offset_delta, IR.INTEGER_TYPE),
			})
			fn_ctx:assign_and_evaluate_register(register_id, {
				assign_kind = "create_table",
				register_type = expr.expr_type,
				table_elements = {
					{ key = IR.field_name_to_value "buffer", value = IR.reg_to_value(get_field_buffer) },
					{ key = IR.field_name_to_value "offset", value = IR.reg_to_value(update_field_offset) },
				}
			})
		elseif expr.expr_kind == "cast" then
			fn_ctx:assign_and_evaluate_register(register_id, {
				assign_kind = "cast",
				register_type = expr.expr_type,
				cast_subject = encode_expr_to_value_ref(fn_ctx, expr.cast_expr),
			})
		elseif expr.expr_kind == "infix_op" then
			fn_ctx:assign_and_evaluate_register(register_id, {
				assign_kind = "infix_op",
				register_type = expr.expr_type,
				infix_op_lvalue = encode_expr_to_value_ref(fn_ctx, expr.infix_lvalue),
				infix_op_operator = expr.infix_operator,
				infix_op_rvalue = encode_expr_to_value_ref(fn_ctx, expr.infix_rvalue),
			})
		else
			error "TODO"
		end
	end

	--- @param fn_ctx FnCtx
	--- @param expr Expr
	--- @return ValueRef
	function encode_expr_to_value_ref(fn_ctx, expr)
		if expr.expr_kind == "literal" then
			return IR.constant_to_value(expr.literal_value, expr.expr_type)
		elseif expr.expr_kind == "variable" then
			local ssa_version = fn_ctx:get_variable_ssa_version(expr.variable_name, expr.variable_tag)
			local register_id = { register_kind = "variable", variable_name = expr.variable_name, variable_tag = expr.variable_tag, ssa_version = ssa_version }
			return IR.reg_to_value(register_id)
		else
			local temporary = fn_ctx:declare_temporary()
			encode_expr_to_register(fn_ctx, expr, temporary)
			return IR.reg_to_value(temporary)
		end
	end

	--- @param fn_ctx FnCtx
	--- @param buffer_reg RegisterId
	--- @param offset_ref ValueRef
	--- @param value_ref ValueRef
	--- @param value_type ValueType
	--- @param static_offset integer
	local function encode_flattening_assignment(fn_ctx, buffer_reg, offset_ref, value_ref, value_type, static_offset)
		if value_type.type_kind == "struct" then
			for _, field in ipairs(value_type.struct_fields) do
				local field_value_ref = fn_ctx:declare_temporary()
				fn_ctx:assign_and_evaluate_register(field_value_ref, {
					assign_kind = "get_index",
					register_type = field.type,
					get_index_subject = value_ref,
					get_index = IR.field_name_to_value(field.name),
				})
				encode_flattening_assignment(fn_ctx, buffer_reg, offset_ref, IR.reg_to_value(field_value_ref), field.type, static_offset + field.offset)
			end
		elseif value_type.type_kind == "array" then
			local array_flattened_element_count = IR.type_flattened_element_count(value_type.array_element)
			for i = 0, value_type.array_size - 1 do
				local field_value_ref = fn_ctx:declare_temporary()
				fn_ctx:assign_and_evaluate_register(field_value_ref, {
					assign_kind = "get_index",
					register_type = value_type.array_element,
					get_index_subject = value_ref,
					get_index = IR.constant_to_value(i, IR.INTEGER_TYPE),
				})
				encode_flattening_assignment(fn_ctx, buffer_reg, offset_ref, IR.reg_to_value(field_value_ref), value_type.array_element, static_offset + i * array_flattened_element_count)
			end
		elseif IR.type_flattened_element_count(value_type) == 1 then
			local updated_offset_ref = offset_ref

			if static_offset ~= 0 then
				local new_offset_register = fn_ctx:declare_temporary()
				fn_ctx:assign_and_evaluate_register(new_offset_register, {
					assign_kind = "infix_op",
					register_type = IR.INTEGER_TYPE,
					infix_op_lvalue = offset_ref,
					infix_op_operator = "add",
					infix_op_rvalue = IR.constant_to_value(static_offset, IR.INTEGER_TYPE),
				})
				updated_offset_ref = IR.reg_to_value(new_offset_register)
			end

			fn_ctx:push_statement({
				statement_kind = "set_index",
				set_index_subject = buffer_reg,
				set_index = updated_offset_ref,
				set_index_value = value_ref,
			})
		else
			error("internal bug: type with more than 1 element not being flattened into buffer (" .. IR.type_name(value_type) .. ")")
		end
	end

	local parse_statements

	--- @param parser ParseCtx
	--- @param fn_ctx FnCtx
	local function parse_and_encode_local(parser, fn_ctx)
		local name = parser:expect_type(vsl_parse.TokenType.IDENTIFIER)

		local explicit_type = nil
		if parser:consume(":") then
			explicit_type = parse_type(parser, fn_ctx:get_type_lookup())
		end

		if parser:test("=") then
			parser:expect("=")
			local expr = parse_expr(parser, fn_ctx)

			if explicit_type then
				assert_type_assignable(expr.expr_type, explicit_type, expr.expr_position)
			end

			local register_id = fn_ctx:declare_local(name.text, expr.expr_type)
			encode_expr_to_register(fn_ctx, expr, register_id)
		elseif explicit_type then
			local register_id = fn_ctx:declare_local(name.text, explicit_type)
			fn_ctx:assign_and_evaluate_register(register_id, {
				assign_kind = "cast",
				register_type = explicit_type,
				cast_subject = IR.constant_to_value("nil", IR.NIL_TYPE),
			})
		else
			return parser:error_next("Expected type annotation or initial variable assignment")
		end

		parser:consume(";")
	end

	--- @param parser ParseCtx
	--- @param fn_ctx FnCtx
	local function parse_and_encode_if_statement(parser, fn_ctx)
		local cond_expr = parse_expr(parser, fn_ctx)
		local cond_value = encode_expr_to_value_ref(fn_ctx, cond_expr)

		assert_type_assignable(cond_expr.expr_type, IR.BOOLEAN_TYPE, cond_expr.expr_position)

		local block_ssa_changes = {}

		parser:expect("then")
		local if_true_block_id = fn_ctx:push_block()
		parse_statements(parser, fn_ctx)
		table.insert(block_ssa_changes, fn_ctx:finish_block())

		--- @type { cond: ValueRef, block_id: BlockId }
		local elseifs = {}
		while parser:consume("elseif") do
			local elseif_cond_expr = parse_expr(parser, fn_ctx)
			local elseif_cond_value = encode_expr_to_value_ref(fn_ctx, elseif_cond_expr)
			assert_type_assignable(elseif_cond_expr.expr_type, IR.BOOLEAN_TYPE, elseif_cond_expr.expr_position)
			parser:expect("then")
			local elseif_true_block_id = fn_ctx:push_block()
			parse_statements(parser, fn_ctx)
			table.insert(elseifs, { cond = elseif_cond_value, block_id = elseif_true_block_id })
			table.insert(block_ssa_changes, fn_ctx:finish_block())
		end

		local if_false_block_id = fn_ctx.empty_block_id
		if parser:consume("else") then
			if_false_block_id = fn_ctx:push_block()
			parse_statements(parser, fn_ctx)
			table.insert(block_ssa_changes, fn_ctx:finish_block())
		end

		parser:expect("end")

		for i = #elseifs, 1, -1 do
			local elseif_block_id = fn_ctx:push_block()
			fn_ctx:push_statement({
				statement_kind = "if",
				if_condition = elseifs[i].cond,
				if_true = elseifs[i].block_id,
				if_false = if_false_block_id,
			})
			local ssa_changes = fn_ctx:finish_block()
			assert(not next(ssa_changes)) -- should be no SSA changes from this trivial block
			if_false_block_id = elseif_block_id
		end

		fn_ctx:push_statement({
			statement_kind = "if",
			if_condition = cond_value,
			if_true = if_true_block_id,
			if_false = if_false_block_id,
		})

		-- TODO: define SSA versions for modified variables from all block_ssa_changes

		error "TODO: SSA magic!"

		-- TODO: SSA magic
	end

	--- @param parser ParseCtx
	--- @param fn_ctx FnCtx
	local function parse_and_encode_while_loop(parser, fn_ctx)
		local outer_block_id = fn_ctx:push_loop_ssa_block()
		local cond_expr = parse_expr(parser, fn_ctx)
		local cond_value = encode_expr_to_value_ref(fn_ctx, cond_expr)

		assert_type_assignable(cond_expr.expr_type, IR.BOOLEAN_TYPE, cond_expr.expr_position)

		parser:expect("do")
		local inner_block_id = fn_ctx:push_block()
		parse_statements(parser, fn_ctx)
		parser:expect("end")

		local inner_ssa_changes = fn_ctx:finish_block()
		fn_ctx:push_statement({
			statement_kind = "if",
			if_condition = cond_value,
			if_true = inner_block_id,
			if_false = fn_ctx.break_block_id,
		})
		fn_ctx:apply_ssa_changes(inner_ssa_changes)
		fn_ctx:finish_loop_ssa_block()

		fn_ctx:push_statement({
			statement_kind = "loop",
			loop_body = outer_block_id,
		})
	end

	--- @param parser ParseCtx
	--- @param fn_ctx FnCtx
	local function parse_and_encode_repeat_loop(parser, fn_ctx)
		local outer_block_id = fn_ctx:push_loop_ssa_block()
		parse_statements(parser, fn_ctx)
		parser:expect("until")
		local cond_expr = parse_expr(parser, fn_ctx)
		local cond_value = encode_expr_to_value_ref(fn_ctx, cond_expr)

		assert_type_assignable(cond_expr.expr_type, IR.BOOLEAN_TYPE, cond_expr.expr_position)

		fn_ctx:push_statement({
			statement_kind = "if",
			if_condition = cond_value,
			if_true = fn_ctx.break_block_id,
			if_false = fn_ctx.empty_block_id,
		})
		fn_ctx:finish_loop_ssa_block()

		fn_ctx:push_statement({
			statement_kind = "loop",
			loop_body = outer_block_id,
		})
	end

	--- @param parser ParseCtx
	--- @param fn_ctx FnCtx
	--- @param key_var_name Token?
	--- @param value_var_name Token?
	--- @param iter_var VariableRegister
	--- @param limit ValueRef
	--- @param step ValueRef
	--- @param iterable ValueRef?
	--- @param iterable_type ValueType
	local function parse_and_encode_for_loop_body(parser, fn_ctx, key_var_name, value_var_name, iter_var, limit, step, iterable, iterable_type)
		local iter_var_type = fn_ctx:get_register_assignment(iter_var).register_type

		local iter_var_ssa_1 = fn_ctx:gen_new_ssa_version(iter_var.variable_name, iter_var.variable_tag)
		local iter_var_ssa_2 = fn_ctx:gen_new_ssa_version(iter_var.variable_name, iter_var.variable_tag)
		--- @type VariableRegister
		local iter_reg_ssa_1 = { register_kind = "variable", variable_name = iter_var.variable_name, variable_tag = iter_var.variable_tag, ssa_version = iter_var_ssa_1 }
		--- @type VariableRegister
		local iter_reg_ssa_2 = { register_kind = "variable", variable_name = iter_var.variable_name, variable_tag = iter_var.variable_tag, ssa_version = iter_var_ssa_2 }

		local outer_block_id = fn_ctx:push_loop_ssa_block()
		fn_ctx:assign_and_evaluate_register(iter_reg_ssa_1, {
			assign_kind = "phi",
			register_type = iter_var_type,
			phi_primary = iter_var,
			phi_secondary = iter_reg_ssa_2,
		})
		local cond_value

		if step.value_kind == "constant" and tonumber(step.constant_value) > 0 then
			local cond_register = fn_ctx:declare_temporary()
			fn_ctx:assign_and_evaluate_register(cond_register, {
				assign_kind = "infix_op",
				register_type = IR.BOOLEAN_TYPE,
				infix_op_lvalue = IR.reg_to_value(iter_reg_ssa_1),
				infix_op_operator = "lte",
				infix_op_rvalue = limit,
			})
			cond_value = IR.reg_to_value(cond_register)
		else
			local cond_register1 = fn_ctx:declare_temporary()
			fn_ctx:assign_and_evaluate_register(cond_register1, {
				assign_kind = "infix_op",
				register_type = IR.BOOLEAN_TYPE,
				infix_op_lvalue = IR.reg_to_value(iter_reg_ssa_1),
				infix_op_operator = "sub",
				infix_op_rvalue = limit,
			})
			local cond_register2 = fn_ctx:declare_temporary()
			fn_ctx:assign_and_evaluate_register(cond_register2, {
				assign_kind = "infix_op",
				register_type = IR.BOOLEAN_TYPE,
				infix_op_lvalue = IR.reg_to_value(cond_register1),
				infix_op_operator = "mul",
				infix_op_rvalue = step,
			})
			local cond_register3 = fn_ctx:declare_temporary()
			fn_ctx:assign_and_evaluate_register(cond_register3, {
				assign_kind = "infix_op",
				register_type = IR.BOOLEAN_TYPE,
				infix_op_lvalue = IR.reg_to_value(cond_register2),
				infix_op_operator = "lte",
				infix_op_rvalue = IR.constant_to_value(0, IR.NUMBER_TYPE),
			})
			cond_value = IR.reg_to_value(cond_register3)
		end
		local inner_block_id = fn_ctx:push_block()
		parser:expect("do")
		if key_var_name then
			local key_var = fn_ctx:declare_local(key_var_name.text, iter_var_type)
			fn_ctx:assign_and_evaluate_register(key_var, {
				assign_kind = "move",
				register_type = iter_var_type,
				move_value = IR.reg_to_value(iter_reg_ssa_1),
			})
		end
		if value_var_name then
			if not iterable then
				error "internal bug: missing iterable value for foreach loop"
			end

			if iterable_type.type_kind == "buffer" then
				local value_type = IR.ref_type(iterable_type.buffer_element)
				local value_var = fn_ctx:declare_local(value_var_name.text, value_type)
				encode_create_ref_to_register(fn_ctx, iterable, IR.reg_to_value(iter_reg_ssa_1), 0, value_var, iterable_type.buffer_element)
			else
				local iterable_element_type = iterable_type.type_kind == "array" and iterable_type.array_element or IR.DYNAMIC_TYPE
				local value_var = fn_ctx:declare_local(value_var_name.text, iterable_element_type)
				fn_ctx:assign_and_evaluate_register(value_var, {
					assign_kind = "get_index",
					register_type = iterable_element_type,
					get_index_subject = iterable,
					get_index = IR.reg_to_value(iter_reg_ssa_1),
				})
			end
		end
		parse_statements(parser, fn_ctx)
		fn_ctx:assign_and_evaluate_register(iter_reg_ssa_2, {
			assign_kind = "infix_op",
			register_type = iter_var_type,
			infix_op_lvalue = IR.reg_to_value(iter_reg_ssa_1),
			infix_op_operator = "add",
			infix_op_rvalue = step,
		})
		parser:expect("end")
		local inner_ssa_changes = fn_ctx:finish_block()
		fn_ctx:push_statement({
			statement_kind = "if",
			if_condition = cond_value,
			if_true = inner_block_id,
			if_false = fn_ctx.break_block_id,
		})
		fn_ctx:apply_ssa_changes(inner_ssa_changes)
		fn_ctx:finish_loop_ssa_block()
		fn_ctx:push_statement({
			statement_kind = "loop",
			loop_body = outer_block_id,
		})
	end

	--- @param parser ParseCtx
	--- @param fn_ctx FnCtx
	local function parse_and_encode_for_loop(parser, fn_ctx)
		local key_var_name = nil
		local value_var_name = parser:expect_type(vsl_parse.TokenType.IDENTIFIER)
		if parser:consume(",") then
			key_var_name = value_var_name
			value_var_name = parser:expect_type(vsl_parse.TokenType.IDENTIFIER)
		end

		if parser:consume("=") then
			if key_var_name then
				vsl_parse.error_at(value_var_name.position, "Cannot have key and value variable in numeric for loop")
			end

			local init = parse_expr(parser, fn_ctx)
			parser:expect(",")
			local limit = parse_expr(parser, fn_ctx)
			local step
			if parser:consume(",") then
				step = parse_expr(parser, fn_ctx)
			else
				step = { expr_kind = "literal", expr_position = limit.expr_position, expr_type = IR.INTEGER_TYPE, literal_value = "1" }
			end

			if step.expr_type.type_kind == "number" then
				init.expr_type = IR.NUMBER_TYPE
			end

			assert_type_assignable(init.expr_type, IR.NUMBER_TYPE, init.expr_position)
			assert_type_assignable(limit.expr_type, IR.NUMBER_TYPE, limit.expr_position)
			assert_type_assignable(step.expr_type, IR.NUMBER_TYPE, step.expr_position)

			local iter_var_temp = fn_ctx:declare_anonymous_local("temp")
			encode_expr_to_register(fn_ctx, init, iter_var_temp)
			local limit_value = encode_expr_to_value_ref(fn_ctx, limit)
			local step_value = encode_expr_to_value_ref(fn_ctx, step)

			parse_and_encode_for_loop_body(parser, fn_ctx, value_var_name, nil, iter_var_temp, limit_value, step_value, nil, IR.NIL_TYPE)
		elseif parser:consume("in") then
			local iterable_expr = parse_expr(parser, fn_ctx)
			local iterable_value = encode_expr_to_value_ref(fn_ctx, iterable_expr)

			local iter_var_temp = fn_ctx:declare_anonymous_local("temp")
			fn_ctx:assign_and_evaluate_register(iter_var_temp, {
				assign_kind = "move",
				register_type = IR.INTEGER_TYPE,
				move_value = IR.constant_to_value(1, IR.INTEGER_TYPE),
			})

			if iterable_expr.expr_type.type_kind == "ref" then
				local ref_element = iterable_expr.expr_type.ref_element
				if ref_element.type_kind == "dynamic" or ref_element.type_kind == "buffer" then
					iterable_expr = { expr_kind = "unbuffer_ref", expr_position = iterable_expr.expr_position, expr_type = ref_element, unbuffer_ref_subject = iterable_expr }
				elseif ref_element.type_kind == "array" then
					vsl_parse.error_at(iterable_expr.expr_position, "Cannot iterate over a ref to an array value: not yet implemented")
				else
					vsl_parse.error_at(iterable_expr.expr_position, "Cannot iterate over a ref to a " .. IR.type_name(ref_element) .. " value")
				end
			end

			if iterable_expr.expr_type.type_kind == "dynamic" then
				local limit_temporary = fn_ctx:declare_temporary()
				fn_ctx:assign_and_evaluate_register(limit_temporary, {
					assign_kind = "prefix_op",
					register_type = IR.INTEGER_TYPE,
					prefix_op_operator = "len",
					prefix_op_rvalue = iterable_value
				})
				local limit_value = IR.reg_to_value(limit_temporary)
				local step_value = IR.constant_to_value(1, IR.INTEGER_TYPE)
				parse_and_encode_for_loop_body(parser, fn_ctx, key_var_name, value_var_name, iter_var_temp, limit_value, step_value, iterable_value, iterable_expr.expr_type)
			elseif iterable_expr.expr_type.type_kind == "array" then
				local limit_value = IR.constant_to_value(iterable_expr.expr_type.array_size, IR.INTEGER_TYPE)
				local step_value = IR.constant_to_value(1, IR.INTEGER_TYPE)
				parse_and_encode_for_loop_body(parser, fn_ctx, key_var_name, value_var_name, iter_var_temp, limit_value, step_value, iterable_value, iterable_expr.expr_type)
			elseif iterable_expr.expr_type.type_kind == "buffer" then
				local buffer_stride = IR.type_flattened_element_count(iterable_expr.expr_type.buffer_element)
				local limit_temporary1 = fn_ctx:declare_temporary()
				fn_ctx:assign_and_evaluate_register(limit_temporary1, {
					assign_kind = "prefix_op",
					register_type = IR.INTEGER_TYPE,
					prefix_op_operator = "len",
					prefix_op_rvalue = iterable_value
				})
				local limit_temporary2 = fn_ctx:declare_temporary() -- TODO: I think we want `.length` instead
				fn_ctx:assign_and_evaluate_register(limit_temporary2, {
					assign_kind = "infix_op",
					register_type = IR.INTEGER_TYPE,
					infix_op_lvalue = IR.reg_to_value(limit_temporary1),
					infix_op_operator = "div",
					infix_op_rvalue = IR.constant_to_value(buffer_stride, IR.INTEGER_TYPE),
				})
				local limit_value = IR.reg_to_value(limit_temporary2)
				local step_value = IR.constant_to_value(1, IR.INTEGER_TYPE)
				parse_and_encode_for_loop_body(parser, fn_ctx, key_var_name, value_var_name, iter_var_temp, limit_value, step_value, iterable_value, iterable_expr.expr_type)
			else
				vsl_parse.error_at(iterable_expr.expr_position, "Cannot iterate over a " .. iterable_expr.expr_type.type_kind .. " value")
			end
		else
			parser:error_next("Expected 'in' or '=' after for loop variable")
		end
	end

	--- @param parser ParseCtx
	--- @param fn_ctx FnCtx
	--- @return ValueRef?
	local function parse_statement(parser, fn_ctx)
		if parser:consume("local") then
			parse_and_encode_local(parser, fn_ctx)
			return nil
		elseif parser:consume("if") then
			parse_and_encode_if_statement(parser, fn_ctx)
			return nil
		elseif parser:consume("while") then
			parse_and_encode_while_loop(parser, fn_ctx)
			return nil
		elseif parser:consume("repeat") then
			parse_and_encode_repeat_loop(parser, fn_ctx)
			return nil
		elseif parser:consume("for") then
			parse_and_encode_for_loop(parser, fn_ctx)
			return nil
		elseif parser:consume("return") then
			return parser:error_next("'return' is not supported; the last expression of a function is its return value")
		elseif parser:consume("break") then
			-- TODO: check we're in a loop?
			fn_ctx:push_statement({ statement_kind  = "break" })

			return nil
		elseif parser:consume("do") then
			fn_ctx:push_scope()
			parse_statements(parser, fn_ctx)
			parser:expect("end")
			fn_ctx:finish_scope()

			return nil
		else
			local lvalue = parse_expr(parser, fn_ctx)

			if parser:consume("=") then
				local rvalue = parse_expr(parser, fn_ctx)
				parser:consume(";")

				if lvalue.expr_type.type_kind == "ref" then
					assert_type_assignable(rvalue.expr_type, lvalue.expr_type.ref_element, rvalue.expr_position)
					local rvalue_ref = encode_expr_to_value_ref(fn_ctx, rvalue)
					local ref_reg = encode_expr_to_value_ref(fn_ctx, lvalue)
					local buffer_reg = fn_ctx:declare_temporary()
					fn_ctx:assign_and_evaluate_register(buffer_reg, {
						assign_kind = "get_index",
						register_type = IR.buffer_type(lvalue.expr_type.ref_element),
						get_index_subject = ref_reg,
						get_index = IR.field_name_to_value "buffer",
					})
					local offset_reg = fn_ctx:declare_temporary()
					fn_ctx:assign_and_evaluate_register(offset_reg, {
						assign_kind = "get_index",
						register_type = IR.INTEGER_TYPE,
						get_index_subject = ref_reg,
						get_index = IR.field_name_to_value "offset",
					})

					encode_flattening_assignment(fn_ctx, buffer_reg, IR.reg_to_value(offset_reg), rvalue_ref, lvalue.expr_type.ref_element, 0)
				elseif lvalue.expr_kind == "variable" then
					assert_type_assignable(rvalue.expr_type, lvalue.expr_type, rvalue.expr_position)
					local ssa_version = fn_ctx:gen_new_ssa_version(lvalue.variable_name, lvalue.variable_tag)
					local register_id = { type = "variable", variable_name = lvalue.variable_name, variable_tag = lvalue.variable_tag, ssa_version = ssa_version }
					encode_expr_to_register(fn_ctx, rvalue, register_id)
					fn_ctx:commit_new_version(lvalue.variable_name, lvalue.variable_tag, ssa_version)
				elseif lvalue.expr_kind == "get_index" then
					assert_type_assignable(rvalue.expr_type, lvalue.expr_type, rvalue.expr_position)
					local rvalue_ref = encode_expr_to_value_ref(fn_ctx, rvalue)
					local index_subject = fn_ctx:declare_temporary()
					encode_expr_to_register(fn_ctx, lvalue.index_subject, index_subject)
					local index = encode_expr_to_value_ref(fn_ctx, lvalue.index)
					fn_ctx:push_statement({
						statement_kind = "set_index",
						set_index_subject = index_subject,
						set_index = index,
						set_index_value = rvalue_ref,
					})
				else
					vsl_parse.error_at(lvalue.expr_position, "Cannot assign to a " .. lvalue.expr_kind .. " expression")
				end

				return nil
			else
				-- TODO: ops like +=, *=, etc
				parser:consume(";")
				return encode_expr_to_value_ref(fn_ctx, lvalue)
			end
		end
	end

	--- @param parser ParseCtx
	--- @param fn_ctx FnCtx
	--- @return ValueRef?
	function parse_statements(parser, fn_ctx)
		local return_value = nil
		while not parser:test("end") and not parser:test("elseif") and not parser:test("else") and not parser:test("until") do
			return_value = parse_statement(parser, fn_ctx)
		end
		return return_value
	end

	--- @param parser ParseCtx
	--- @return string[]
	local function parse_type_parameters(parser)
		local params = {}
		if parser:consume("<") then
			repeat
				local param = parser:expect_type(vsl_parse.TokenType.IDENTIFIER)
				table.insert(params, param.text)
			until not parser:consume(",") and not parser:test_type(vsl_parse.TokenType.IDENTIFIER)
			parser:expect(">")
		end
		return params
	end

	--- @param lookup_type_name function(Token): ValueType
	--- @return function(ParseCtx): StructDefField
	local function get_parse_struct_def_field(lookup_type_name)
		local offset = 0
		--- @param parser ParseCtx
		--- @return StructDefField
		return function(parser)
			local name = parser:expect_type(vsl_parse.TokenType.IDENTIFIER)
			parser:expect(":")
			local type = parse_type(parser, lookup_type_name)
			local this_offset = offset

			offset = offset + IR.type_flattened_element_count(type)

			--- @type StructDefField
			return {
				name = name.text,
				type = type,
				offset = this_offset,
				docstring = nil,
			}
		end
	end

	--- @param parser ParseCtx
	--- @param lookup_name function(Token): ValueType
	--- @return NameAndType
	local function parse_name_and_type(parser, lookup_name)
		local name = parser:expect_type(vsl_parse.TokenType.IDENTIFIER)
		parser:expect(":")
		local type = parse_type(parser, lookup_name)
		return { name = name.text, type = type }
	end

	--- @param parser ParseCtx
	--- @param globals GlobalCtx
	--- @return Definition
	local function parse_definition(parser, globals)
		local function lookup_type_name(name_token)
			local struct_def = globals:lookup_expect_struct(name_token)
			return IR.struct_def_to_type(struct_def)
		end

		if parser:consume("struct") then
			local name_token = parser:expect_type(vsl_parse.TokenType.IDENTIFIER)
			local type_parameters = parse_type_parameters(parser)
			local fields = parser:list_of("{", get_parse_struct_def_field(lookup_type_name), "}")
			local tuple_constructor = {}

			for i, field in ipairs(fields) do
				tuple_constructor[i] = field
			end

			table.sort(fields, function(a, b) return a.name < b.name end)

			--- @type StructDef
			return {
				type = "struct",
				docstring = nil, -- TODO
				can_construct = true,
				name = name_token.text,
				type_parameters = type_parameters,
				fields = fields,
				tuple_constructor = tuple_constructor,
			}
		elseif parser:test("function") then
			parser:expect("function")
			local name_token = parser:expect_type(vsl_parse.TokenType.IDENTIFIER)
			local type_parameters = parse_type_parameters(parser)
			local params = parser:list_of("(", parse_name_and_type, ")", lookup_type_name)

			--- @type ValueType
			local return_type
			if parser:consume(":") then
				return_type = parse_type(parser, lookup_type_name)
			else
				return_type = IR.NIL_TYPE
			end

			local fn_ctx = FnCtx.new(globals, type_parameters, params)
			local return_value = parse_statements(parser, fn_ctx)
			parser:expect("end")

			-- TODO: check return type

			return fn_ctx:build(name_token.text, type_parameters, params, return_type, return_value)
		else
			return parser:error_next("Expected 'struct' or 'function'")
		end
	end

	--- @param tokens Token[]
	--- @param globals GlobalCtx
	--- @return Definition[]
	function parse(tokens, globals)
		local parser = vsl_parse.ParseCtx.new(tokens)
		local decls = {}
		local inner_globals = globals:shallow_copy()

		while parser.current_token_index <= #parser.tokens do
			local definition = parse_definition(parser, inner_globals)
			table.insert(decls, definition)
			inner_globals:add_definitions { definition }
		end

		return decls
	end
end

local block_tostring, fn_tostring, value_ref_tostring
do
	--- @param type ValueType
	--- @return string
	local function type_tostring(type)
		if type.type_kind == "nil" or type.type_kind == "boolean" or type.type_kind == "integer" or type.type_kind == "number" or type.type_kind == "string" or type.type_kind == "dynamic" then
			return type.type_kind
		elseif type.type_kind == "type_parameter" then
			return "<" .. type.type_parameter_name .. ">"
		elseif type.type_kind == "struct" then
			if type.struct_name_hint then
				return type.struct_name_hint
			end
			local str = "struct { "
			for i, field in ipairs(type.struct_fields) do
				if i == 1 then
					str = str .. field.name .. ": " .. type_tostring(field.type)
				else
					str = str .. ", " .. field.name .. ": " .. type_tostring(field.type)
				end
			end
			return str .. " }"
		elseif type.type_kind == "array" then
			return "[" .. type_tostring(type.array_element) .. "; " .. type.array_size .. "]"
		elseif type.type_kind == "buffer" then
			return "buffer<" .. type_tostring(type.buffer_element) .. ">"
		elseif type.type_kind == "ref" then
			return "ref<" .. type_tostring(type.ref_element) .. ">"
		end
		error "wat"
	end

	--- @param register_id RegisterId
	--- @return string
	local function register_tostring(register_id)
		if register_id.register_kind == "temporary" then
			return "%temp" .. register_id.temporary_id
		else
			return "%" .. register_id.variable_name .. "_" .. register_id.variable_tag .. "v" .. register_id.ssa_version
		end
	end

	--- @param value_ref ValueRef
	--- @return string
	function value_ref_tostring(value_ref)
		if value_ref.value_kind == "constant" then
			return "$" .. value_ref.constant_value
		else
			return register_tostring(value_ref.register_id)
		end
	end

	--- @param blocks { [BlockId]: Block }
	--- @param registers { [RegisterIdLookup]: RegisterAssignment }
	--- @param block_id BlockId
	--- @param indent string
	--- @return string
	function block_tostring(blocks, registers, block_id, indent)
		local str = ""
		local block = blocks[block_id]

		for _, statement in ipairs(block.statements) do
			if statement.statement_kind == "evaluate" then
				local register_id = statement.evaluate_register_id
				local register_name = register_tostring(register_id)
				local register_assignment = registers[IR.reg_to_lookup(register_id)]
				local register_assignment_str = "?"

				if register_assignment.assign_kind == "load_param" then
					register_assignment_str = "param " .. register_assignment.load_param_index
				elseif register_assignment.assign_kind == "phi" then
					register_assignment_str = "phi(" .. register_tostring(register_assignment.phi_primary) .. ", " .. register_tostring(register_assignment.phi_secondary) .. ")"
				elseif register_assignment.assign_kind == "move" then
					register_assignment_str = value_ref_tostring(register_assignment.move_value)
				elseif register_assignment.assign_kind == "create_table" then
					register_assignment_str = "table"
					for _, element in ipairs(register_assignment.table_elements) do
						register_assignment_str = register_assignment_str .. "\n" .. indent .. "  [" .. value_ref_tostring(element.key) .. "] = " .. value_ref_tostring(element.value)
					end
				elseif register_assignment.assign_kind == "get_index" then
					register_assignment_str = value_ref_tostring(register_assignment.get_index_subject) .. "[" .. value_ref_tostring(register_assignment.get_index) .. "]"
				elseif register_assignment.assign_kind == "cast" then
					register_assignment_str = "cast " .. value_ref_tostring(register_assignment.cast_subject)
				elseif register_assignment.assign_kind == "call_fn" then
					local parameters = {}
					for _, param in ipairs(register_assignment.call_fn_parameters) do
						table.insert(parameters, value_ref_tostring(param))
					end
					register_assignment_str = "call " .. register_assignment.call_fn_name .. "(" .. table.concat(parameters, ", ") .. ")"
					if register_assignment.call_fn_pure then
						register_assignment_str = "pure " .. register_assignment_str
					end
				elseif register_assignment.assign_kind == "infix_op" then
					register_assignment_str = value_ref_tostring(register_assignment.infix_op_lvalue) .. " " .. register_assignment.infix_op_operator .. " " .. value_ref_tostring(register_assignment.infix_op_rvalue)
				elseif register_assignment.assign_kind == "prefix_op" then
					register_assignment_str = register_assignment.prefix_op_operator .. " " .. value_ref_tostring(register_assignment.prefix_op_rvalue)
				end

				str = str .. "\n" .. indent .. "eval " .. register_name .. " :: " .. type_tostring(register_assignment.register_type) .. " := " .. register_assignment_str
			elseif statement.statement_kind == "set_index" then
				str = str .. "\n" .. indent .. "set_index "
				.. register_tostring(statement.set_index_subject) .. " ["
				.. value_ref_tostring(statement.set_index) .. "] = "
				.. value_ref_tostring(statement.set_index_value)
			elseif statement.statement_kind == "if" then
				local if_true = block_tostring(blocks, registers, statement.if_true, indent .. "  ")
				local if_false = block_tostring(blocks, registers, statement.if_false, indent .. "  ")

				if if_true == "" and if_false ~= "" then
					str = str .. "\n" .. indent .. "if not (" .. value_ref_tostring(statement.if_condition) .. ") then" .. if_false .. "\n" .. indent .. "end"
				else
					str = str .. "\n" .. indent .. "if " .. value_ref_tostring(statement.if_condition) .. " then" .. if_true .. "\n" .. indent
					if if_false == "" then
						str = str .. "end"
					else
						str = str .. "else" .. if_false .. "\n" .. indent .. "end"
					end
				end
			elseif statement.statement_kind == "loop" then
				str = str .. "\n" .. indent .. "loop" .. block_tostring(blocks, registers, statement.loop_body, indent .. "  ") .. "\n" .. indent .. "end"
			elseif statement.statement_kind == "break" then
				str = str .. "\n" .. indent .. "break"
			else
				error "unhandled statement kind"
			end
		end

		return str
	end

	--- @param fn FnDef
	--- @return string
	function fn_tostring(fn)
		local str = ""

		if fn.docstring ~= nil then
			str = str .. "--- " .. fn.docstring .. "\n"
		end

		str = str .. "function " .. fn.name

		if #fn.type_parameters > 0 then
			str = str .. "<" .. table.concat(fn.type_parameters, ", ") .. ">"
		end

		str = str .. "("

		for i, param in ipairs(fn.params) do
			if i > 1 then
				str = str .. ", "
			end
			str = str .. param.name .. ": " .. type_tostring(param.type)
		end

		str = str .. "): " .. type_tostring(fn.return_type)

		str = str .. block_tostring(fn.blocks, fn.registers, fn.main_block, "  ")

		if fn.return_value ~= nil then
			str = str .. "\n  return " .. value_ref_tostring(fn.return_value)
		end

		str = str .. "\nend"

		return str
	end
end

local Optimisation = {}
do
	--- @param r1 RegisterId
	--- @param r2 RegisterId
	--- @return boolean
	local function registers_are_equal(r1, r2)
		if r1.register_kind == "temporary" then
			if r2.register_kind == "temporary" then
				return r1.temporary_id == r2.temporary_id
			else
				return false
			end
		else
			if r2.register_kind == "variable" then
				return r1.variable_name == r2.variable_name and r1.variable_tag == r2.variable_tag and r1.ssa_version == r2.ssa_version
			else
				return false
			end
		end
	end

	--- @param v1 ValueRef
	--- @param v2 ValueRef
	--- @return boolean
	local function values_are_equal(v1, v2)
		if v1.value_kind == "constant" then
			if v2.value_kind == "constant" then
				return v1.constant_value == v2.constant_value
			else
				return false
			end
		else
			if v2.value_kind == "register" then
				return registers_are_equal(v1.register_id, v2.register_id)
			else
				return false
			end
		end
	end

	--- @param registers { [RegisterIdLookup]: RegisterAssignment }
	--- @param value_ref ValueRef
	--- @return boolean was_aliased, ValueRef
	local function unalias_value_ref(registers, value_ref)
		if value_ref.value_kind == "register" then
			local assignment = registers[IR.reg_to_lookup(value_ref.register_id)]
			if assignment.assign_kind == "move" then
				local new_value_ref = assignment.move_value
				if new_value_ref.value_kind == "register" and new_value_ref.register_id.register_kind == "variable" then
					-- workaround to prevent unaliasing to a variable register which may have had an SSA assignment since then
					return false, value_ref
				end
				local changed = not values_are_equal(value_ref, new_value_ref)
				if changed then
					return true, select(2, unalias_value_ref(registers, new_value_ref))
				else
					return false, new_value_ref
				end
			else
				return false, value_ref
			end
		else
			return false, value_ref
		end
	end

	--- @param fn FnDef
	--- @param value ValueRef
	--- @return boolean
	local function is_integer_or_numeric(fn, value)
		local value_type = value.value_kind == "constant" and value.constant_type or fn.registers[IR.reg_to_lookup(value.register_id)].register_type
		return value_type.type_kind == "integer" or value_type.type_kind == "number"
	end

	--- @param registers { [RegisterIdLookup]: RegisterAssignment }
	--- @param register_id VariableRegister
	--- @return boolean was_aliased, VariableRegister
	local function unalias_phi_register_id(registers, register_id)
		local assignment = registers[IR.reg_to_lookup(register_id)]
		if assignment.assign_kind == "move" then
			if assignment.move_value.value_kind == "register" then
				local new_register_id = assignment.move_value.register_id
				if new_register_id.register_kind == "variable" then
					return true, new_register_id
				else
					return false, register_id
				end
			else
				return false, register_id
			end
		else
			return false, register_id
		end
	end

	--- @param naming_ctx NamingCtx
	--- @param src_register RegisterId
	--- @param index_constant ConstantValueRef
	--- @return RegisterId
	local function constant_index_to_new_register(naming_ctx, src_register, index_constant)
		if src_register.register_kind == "temporary" then
			local temporary_id = naming_ctx:next_temporary_id()
			return { register_kind = "temporary", temporary_id = temporary_id }
		else
			local desired_name = src_register.variable_name .. "_" .. tostring(index_constant.constant_value)
			if index_constant.constant_value:sub(1, 1) == "\"" or index_constant.constant_value:sub(1, 1) == "'" then
				local name = index_constant.constant_value:match("^.([%w_]+)")
				if name then
					desired_name = src_register.variable_name .. "_" .. name
				else
					desired_name = src_register.variable_name .. "_field"
				end
			end

			local variable_tag = naming_ctx:next_variable_tag(desired_name)
			local ssa_version = naming_ctx:next_ssa_version(desired_name, variable_tag)

			return { register_kind = "variable", variable_name = desired_name, variable_tag = variable_tag, ssa_version = ssa_version }
		end
	end

	--- Replace references to a register with a reference to that register's value if its assignment
	--- is a move.
	--- @param fn FnDef
	--- @return boolean changed
	function Optimisation.unalias_trivial_moves(fn)
		local changed = false

		for _, assignment in pairs(fn.registers) do
			if assignment.assign_kind == "phi" then
				local primary_was_aliased, new_primary = unalias_phi_register_id(fn.registers, assignment.phi_primary)
				if primary_was_aliased and new_primary.variable_name == assignment.phi_primary.variable_name and new_primary.variable_tag == assignment.phi_primary.variable_tag then
					assignment.phi_primary = new_primary
					changed = true
				end
				local secondary_was_aliased, new_secondary = unalias_phi_register_id(fn.registers, assignment.phi_secondary)
				if secondary_was_aliased and new_secondary.variable_name == assignment.phi_secondary.variable_name and new_secondary.variable_tag == assignment.phi_secondary.variable_tag then
					assignment.phi_secondary = new_secondary
					changed = true
				end
			elseif assignment.assign_kind == "move" then
				local was_aliased, new_value = unalias_value_ref(fn.registers, assignment.move_value)
				if was_aliased then
					assignment.move_value = new_value
					changed = true
				end
			elseif assignment.assign_kind == "create_table" then
				for _, element in ipairs(assignment.table_elements) do
					local key_was_aliased, new_key = unalias_value_ref(fn.registers, element.key)
					local value_was_aliased, new_value = unalias_value_ref(fn.registers, element.value)
					if key_was_aliased then
						element.key = new_key
						changed = true
					end
					if value_was_aliased then
						element.value = new_value
						changed = true
					end
				end
			elseif assignment.assign_kind == "get_index" then
				local subject_was_aliased, new_subject = unalias_value_ref(fn.registers, assignment.get_index_subject)
				if subject_was_aliased then
					assignment.get_index_subject = new_subject
					changed = true
				end
				local index_was_aliased, new_index = unalias_value_ref(fn.registers, assignment.get_index)
				if index_was_aliased then
					assignment.get_index = new_index
					changed = true
				end
			elseif assignment.assign_kind == "cast" then
				local subject_was_aliased, new_subject = unalias_value_ref(fn.registers, assignment.cast_subject)
				if subject_was_aliased then
					assignment.cast_subject = new_subject
					changed = true
				end
			elseif assignment.assign_kind == "call_fn" then
				for i, param in ipairs(assignment.call_fn_parameters) do
					local param_was_aliased, new_param = unalias_value_ref(fn.registers, param)
					if param_was_aliased then
						assignment.call_fn_parameters[i] = new_param
						changed = true
					end
				end
			elseif assignment.assign_kind == "infix_op" then
				local lvalue_was_aliased, new_lvalue = unalias_value_ref(fn.registers, assignment.infix_op_lvalue)
				if lvalue_was_aliased then
					assignment.infix_op_lvalue = new_lvalue
					changed = true
				end
				local rvalue_was_aliased, new_rvalue = unalias_value_ref(fn.registers, assignment.infix_op_rvalue)
				if rvalue_was_aliased then
					assignment.infix_op_rvalue = new_rvalue
					changed = true
				end
			elseif assignment.assign_kind == "prefix_op" then
				local rvalue_was_aliased, new_rvalue = unalias_value_ref(fn.registers, assignment.prefix_op_rvalue)
				if rvalue_was_aliased then
					assignment.prefix_op_rvalue = new_rvalue
					changed = true
				end
			end
		end

		for _, block in pairs(fn.blocks) do
			for _, statement in ipairs(block.statements) do
				if statement.statement_kind == "evaluate" then
					local register_id = statement.evaluate_register_id
					if register_id.register_kind == "variable" then
						local assignment = fn.registers[IR.reg_to_lookup(register_id)]
						if assignment.assign_kind == "phi" then
							if assignment.phi_secondary.variable_name == register_id.variable_name and assignment.phi_secondary.variable_tag == register_id.variable_tag and assignment.phi_secondary.ssa_version == register_id.ssa_version then
								fn.registers[IR.reg_to_lookup(register_id)] = {
									assign_kind = "move",
									register_type = assignment.register_type,
									move_value = IR.reg_to_value(assignment.phi_primary)
								}
								changed = true
							end
						end
					end
				elseif statement.statement_kind == "set_index" then
					local subject_was_aliased, new_subject = unalias_value_ref(fn.registers, IR.reg_to_value(statement.set_index_subject))
					if subject_was_aliased and new_subject.value_kind == "register" then
						statement.set_index_subject = new_subject.register_id
						changed = true
					end
					local index_was_aliased, new_index = unalias_value_ref(fn.registers, statement.set_index)
					if index_was_aliased then
						statement.set_index = new_index
						changed = true
					end
					local value_was_aliased, new_value = unalias_value_ref(fn.registers, statement.set_index_value)
					if value_was_aliased then
						statement.set_index_value = new_value
						changed = true
					end
				elseif statement.statement_kind == "if" then
					local cond_was_aliased, new_cond = unalias_value_ref(fn.registers, statement.if_condition)
					if cond_was_aliased then
						statement.if_condition = new_cond
						changed = true
					end
				end
			end
		end

		return changed
	end

	--- Removes registers and their assignments which are not used and whose evaluation doesn't
	--- produce side effects.
	--- @param fn FnDef
	--- @return boolean changed
	function Optimisation.remove_dead_code(fn)
		local used_registers = {}
		local value_queue = { fn.return_value }

		for _, block in pairs(fn.blocks) do
			for i = #block.statements, 1, -1 do
				local statement = block.statements[i]
				if statement.statement_kind == "evaluate" then
					local register_lookup = IR.reg_to_lookup(statement.evaluate_register_id)
					local assignment = fn.registers[register_lookup]
					if assignment.assign_kind == "call_fn" and not assignment.call_fn_pure then
						for _, param in ipairs(assignment.call_fn_parameters) do
							table.insert(value_queue, param)
						end
						table.insert(value_queue, IR.reg_to_value(statement.evaluate_register_id))
					end
				elseif statement.statement_kind == "set_index" then
					table.insert(value_queue, IR.reg_to_value(statement.set_index_subject))
					table.insert(value_queue, statement.set_index)
					table.insert(value_queue, statement.set_index_value)
				elseif statement.statement_kind == "if" then
					table.insert(value_queue, statement.if_condition)
				end
			end
		end

		while true do
			--- @type ValueRef?
			local value = table.remove(value_queue)
			if value == nil then break end
			if value.value_kind ~= "constant" then
				local register_id = value.register_id
				local register_lookup = IR.reg_to_lookup(register_id)
				if not used_registers[register_lookup] then
					used_registers[register_lookup] = true

					local assignment = fn.registers[register_lookup]

					if assignment.assign_kind == "phi" then
						table.insert(value_queue, IR.reg_to_value(assignment.phi_primary))
						table.insert(value_queue, IR.reg_to_value(assignment.phi_secondary))
					elseif assignment.assign_kind == "move" then
						table.insert(value_queue, assignment.move_value)
					elseif assignment.assign_kind == "create_table" then
						for _, element in ipairs(assignment.table_elements) do
							table.insert(value_queue, element.key)
							table.insert(value_queue, element.value)
						end
					elseif assignment.assign_kind == "get_index" then
						table.insert(value_queue, assignment.get_index_subject)
						table.insert(value_queue, assignment.get_index)
					elseif assignment.assign_kind == "cast" then
						table.insert(value_queue, assignment.cast_subject)
					elseif assignment.assign_kind == "call_fn" then
						for _, param in ipairs(assignment.call_fn_parameters) do
							table.insert(value_queue, param)
						end
					elseif assignment.assign_kind == "infix_op" then
						table.insert(value_queue, assignment.infix_op_lvalue)
						table.insert(value_queue, assignment.infix_op_rvalue)
					elseif assignment.assign_kind == "prefix_op" then
						table.insert(value_queue, assignment.prefix_op_rvalue)
					end
				end
			end
		end

		local changed = false
		for _, block in pairs(fn.blocks) do
			for i = #block.statements, 1, -1 do
				local statement = block.statements[i]
				if statement.statement_kind == "evaluate" then
					local register_lookup = IR.reg_to_lookup(statement.evaluate_register_id)
					if not used_registers[register_lookup] then
						table.remove(block.statements, i)
						fn.registers[register_lookup] = nil
						changed = true
					end
				end
			end
		end

		return changed
	end

	--- Flattens table constants which are only used in `get_index` ops with constant indices into
	--- local variables for the component fields.
	---
	--- TODO: support mutation and function parameter flattening
	--- @param fn FnDef
	--- @return boolean changed
	function Optimisation.flatten_tables(fn)
		--- @type { [RegisterIdLookup]: ConstantValueRef[] }
		local candidates = {}
		for register_lookup, assignment in pairs(fn.registers) do
			if assignment.assign_kind == "create_table" then
				candidates[register_lookup] = {}
			end
		end

		--- @param value ValueRef
		local function note_used_in_non_index(value)
			if value.value_kind == "register" then
				local lookup = IR.reg_to_lookup(value.register_id)
				candidates[lookup] = nil
			end
		end

		--- @param table_reg_lookup RegisterIdLookup
		--- @param index ValueRef
		local function note_used_as_index(table_reg_lookup, index)
			local candidate = candidates[table_reg_lookup]
			if candidate then
				if index.value_kind == "constant" then
					table.insert(candidate, index)
				else
					candidates[table_reg_lookup] = nil
				end
			end
		end

		for _, block in pairs(fn.blocks) do
			for _, statement in ipairs(block.statements) do
				if statement.statement_kind == "evaluate" then
					local assignment = fn.registers[IR.reg_to_lookup(statement.evaluate_register_id)]
					if assignment.assign_kind == "phi" then
						note_used_in_non_index(IR.reg_to_value(assignment.phi_primary))
						note_used_in_non_index(IR.reg_to_value(assignment.phi_secondary))
					elseif assignment.assign_kind == "move" then
						note_used_in_non_index(assignment.move_value)
					elseif assignment.assign_kind == "create_table" then
						for _, element in ipairs(assignment.table_elements) do
							note_used_in_non_index(element.key)
							note_used_in_non_index(element.value)
						end
					elseif assignment.assign_kind == "get_index" then
						note_used_in_non_index(assignment.get_index)

						local subject = assignment.get_index_subject
						if subject.value_kind == "register" then
							local reg_lookup = IR.reg_to_lookup(subject.register_id)
							note_used_as_index(reg_lookup, assignment.get_index)
						end
					elseif assignment.assign_kind == "cast" then
						note_used_in_non_index(assignment.cast_subject)
					elseif assignment.assign_kind == "call_fn" then
						for _, param in ipairs(assignment.call_fn_parameters) do
							note_used_in_non_index(param)
						end
					elseif assignment.assign_kind == "infix_op" then
						note_used_in_non_index(assignment.infix_op_lvalue)
						note_used_in_non_index(assignment.infix_op_rvalue)
					elseif assignment.assign_kind == "prefix_op" then
						note_used_in_non_index(assignment.prefix_op_rvalue)
					end
				elseif statement.statement_kind == "set_index" then
					note_used_in_non_index(statement.set_index)
					note_used_in_non_index(statement.set_index_value)

					local reg_lookup = IR.reg_to_lookup(statement.set_index_subject)
					candidates[reg_lookup] = nil
					-- TODO: support modifying the table indices too!
					-- note_used_as_index(reg_lookup, statement.set_index)
				elseif statement.statement_kind == "if" then
				end
			end
		end

		-- note, here we're assuming that fields are not modified, only read, based on a TODO above
		-- supporting writes is nontrivial since we need to do SSA versioning and potentially produce phi nodes

		local flatten_register_lookup = {}
		for reg_lookup, indices in pairs(candidates) do
			local index_value_lookup = {}
			for _, index in ipairs(indices) do
				local register_id = constant_index_to_new_register(fn.naming, IR.lookup_to_reg(reg_lookup), index)
				index_value_lookup[index.constant_value] = register_id
			end
			flatten_register_lookup[reg_lookup] = index_value_lookup
		end

		local changed = false
		for _, block in ipairs(fn.blocks) do
			for i = #block.statements, 1, -1 do
				local statement = block.statements[i]
				if statement.statement_kind == "evaluate" then
					local register_lookup = IR.reg_to_lookup(statement.evaluate_register_id)
					local flatten_lookup = flatten_register_lookup[register_lookup]
					if flatten_lookup then
						for _, register in pairs(flatten_lookup) do
							table.insert(block.statements, i, {
								statement_kind = "evaluate",
								evaluate_register_id = register,
							})
						end
						changed = true
					end
				end
			end
		end

		for table_reg, flatten_lookup in pairs(flatten_register_lookup) do
			local table_assignment = fn.registers[table_reg]
			local table_elements = table_assignment.table_elements

			for constant_value, register in pairs(flatten_lookup) do
				--- @type ValueType
				local register_type = IR.NIL_TYPE
				--- @type ValueRef
				local register_value = IR.NIL

				for i = 1, #table_elements do
					local table_element = table_elements[i]
					if table_element.key.value_kind == "constant" and table_element.key.constant_value == constant_value then
						if table_element.value.value_kind == "register" then
							register_type = fn.registers[IR.reg_to_lookup(table_element.value.register_id)].register_type
						else
							register_type = table_element.value.constant_type
						end
						register_value = table_element.value
						break
					end
				end

				fn.registers[IR.reg_to_lookup(register)] = {
					assign_kind = "move",
					register_type = register_type,
					move_value = register_value,
				}
			end
		end

		for k, assignment in pairs(fn.registers) do
			if assignment.assign_kind == "get_index" then
				local subject = assignment.get_index_subject
				if subject.value_kind == "register" then
					local subject_reg_lookup = IR.reg_to_lookup(subject.register_id)
					local flatten_lookup = flatten_register_lookup[subject_reg_lookup]
					if flatten_lookup then
						local new_reg = flatten_lookup[assignment.get_index.constant_value]
						fn.registers[k] = {
							assign_kind = "move",
							register_type = assignment.register_type,
							move_value = IR.reg_to_value(new_reg),
						}
						changed = true
					end
				end
			end
		end

		return changed
	end

	--- @param fn FnDef
	--- @param assignment RegisterAssignment
	--- @return boolean changed, RegisterAssignment
	local function fold_constants(fn, assignment)

		---   - `(A * K) < 0` => `A < 0` or `A > 0` if `K` is -ve
		---   - `(A * K) <= 0` => `A <= 0` or `A >= 0` if `K` is -ve
		---   - `(A / K) < 0` => `A * K < 0`
		---   - `(A / K) <= 0` => `A * K <= 0`
		--- * Additionally, the following transformations are applied on booleans:

		if assignment.assign_kind == "infix_op" then
			local lvalue = assignment.infix_op_lvalue
			local rvalue = assignment.infix_op_rvalue
			if assignment.infix_op_operator == "add" then
				if lvalue.value_kind == "constant" then
					if rvalue.value_kind == "constant" then
						local result = tonumber(lvalue.constant_value) + tonumber(rvalue.constant_value)
						return true, { assign_kind = "move", register_type = assignment.register_type, move_value = IR.constant_to_value(result) }
					elseif is_integer_or_numeric(fn, rvalue) then
						assignment.infix_op_lvalue = rvalue
						assignment.infix_op_rvalue = lvalue
						return true, assignment
					else
						return false, assignment
					end
				elseif is_integer_or_numeric(fn, lvalue) then
					local lvalue_reg_lookup = IR.reg_to_lookup(lvalue.register_id)
					local lvalue_assignment = fn.registers[lvalue_reg_lookup]
					if rvalue.value_kind == "constant" and rvalue.constant_value == "0" then
						return true, { assign_kind = "move", register_type = assignment.register_type, move_value = lvalue }
					elseif rvalue.value_kind == "constant" then
						if lvalue_assignment.assign_kind == "infix_op" and lvalue_assignment.infix_op_operator == "add" then
							-- TODO: `(A + K1) + K2` => `A + (K1 + K2)`
							-- TODO: `(K1 + A) + K2` => `A + (K1 + K2)`
							return false, assignment -- TODO
						elseif lvalue_assignment.assign_kind == "infix_op" and lvalue_assignment.infix_op_operator == "sub" then
							-- TODO: `(K1 - A) + K2` => `(K1 + K2) - A`
							-- TODO: `(A - K1) + K2` => `A + (K2 - K1)`
							return false, assignment -- TODO
						else
							return false, assignment
						end
					elseif lvalue_assignment.assign_kind == "prefix_op" and lvalue_assignment.infix_op_operator == "unm" then
						return true, { assign_kind = "infix_op", register_type = assignment.register_type, infix_op_operator = "sub", infix_op_lvalue = rvalue, infix_op_rvalue = lvalue_assignment.prefix_op_rvalue }
					else
						local rvalue_reg_lookup = IR.reg_to_lookup(rvalue.register_id)
						if fn.registers[rvalue_reg_lookup].assign_kind == "prefix_op" and fn.registers[rvalue_reg_lookup].prefix_op_operator == "unm" then
							local new_rvalue = fn.registers[rvalue_reg_lookup].prefix_op_rvalue
							return true, { assign_kind = "infix_op", register_type = assignment.register_type, infix_op_operator = "sub", infix_op_lvalue = lvalue, infix_op_rvalue = new_rvalue }
						else
							return false, assignment
						end
					end
				else
					return false, assignment
				end
			elseif assignment.infix_op_operator == "sub" then
				if lvalue.value_kind == "constant" then
					if rvalue.value_kind == "constant" then
						local result = tonumber(lvalue.constant_value) - tonumber(rvalue.constant_value)
						return true, { assign_kind = "move", register_type = assignment.register_type, move_value = IR.constant_to_value(result) }
					elseif lvalue.constant_value == "0" and is_integer_or_numeric(fn, rvalue) then
						return true, { assign_kind = "prefix_op", register_type = assignment.register_type, prefix_op_operator = "unm", prefix_op_rvalue = rvalue }
					else
						-- TODO: `A - (-B)` => `A + B`
						return false, assignment
					end
				elseif is_integer_or_numeric(fn, lvalue) then
					if rvalue.value_kind == "constant" and rvalue.constant_value == "0" then
						return true, { assign_kind = "move", register_type = assignment.register_type, move_value = lvalue }
					elseif rvalue.value_kind == "constant" then
						local new_rvalue = IR.constant_to_value(tostring(-tonumber(rvalue.constant_value)), rvalue.constant_type)
						return true, { assign_kind = "infix_op", register_type = assignment.register_type, infix_op_operator = "add", infix_op_lvalue = lvalue, infix_op_rvalue = new_rvalue }
					else
						-- TODO: `A - (-B)` => `A + B`
						return false, assignment
					end
				else
					return false, assignment
				end
			elseif assignment.infix_op_operator == "mul" then
				if lvalue.value_kind == "constant" then
					if rvalue.value_kind == "constant" then
						local result = tonumber(lvalue.constant_value) * tonumber(rvalue.constant_value)
						return true, { assign_kind = "move", register_type = assignment.register_type, move_value = IR.constant_to_value(result) }
					elseif is_integer_or_numeric(fn, rvalue) then
						assignment.infix_op_lvalue = rvalue
						assignment.infix_op_rvalue = lvalue
						return true, assignment
					else
						return false, assignment
					end
				elseif is_integer_or_numeric(fn, lvalue) then
					if rvalue.value_kind == "constant" and rvalue.constant_value == "0" then
						return true, { assign_kind = "move", register_type = assignment.register_type, move_value = IR.constant_to_value("0", assignment.register_type) }
					elseif rvalue.value_kind == "constant" and rvalue.constant_value == "1" then
						return true, { assign_kind = "move", register_type = assignment.register_type, move_value = lvalue }
					elseif rvalue.value_kind == "constant" and rvalue.constant_value == "2" then
						return true, { assign_kind = "infix_op", register_type = assignment.register_type, infix_op_lvalue = lvalue, infix_op_rvalue = lvalue, infix_op_operator = "add" }
					else
						-- TODO: `(A * K1) * K2` => `A * (K1 * K2)`
						-- TODO: `(K1 * A) * K2` => `A * (K1 * K2)`
						return false, assignment
					end
				else
					return false, assignment
				end
			elseif assignment.infix_op_operator == "div" then
				-- TODO: `0 / A` => `0`
				-- TODO: `A / 1` => `A`
				-- TODO: `A / K` => `A * K'`
				-- TODO: `A / (1/B)` => `A * B`
				-- TODO: `(A / K1) / K2` => `A / (K1 * K2)`
				return false, assignment -- TODO
			elseif assignment.infix_op_operator == "mod" then
				return false, assignment -- TODO
			elseif assignment.infix_op_operator == "exp" then
				-- TODO: `A ^ 0` => `1`
				-- TODO: `A ^ 1` => `A`
				-- TODO: `A ^ 2` => `A * A`
				return false, assignment -- TODO
			elseif assignment.infix_op_operator == "concat" then
				return false, assignment -- TODO
			elseif assignment.infix_op_operator == "lt" then
				return false, assignment -- TODO
			elseif assignment.infix_op_operator == "lte" then
				return false, assignment -- TODO
			elseif assignment.infix_op_operator == "eq" then
				return false, assignment -- TODO
			elseif assignment.infix_op_operator == "neq" then
				return false, assignment -- TODO
			else
				error "internal bug: unhandled infix operator"
				return false, assignment -- for LS
			end
		elseif assignment.assign_kind == "prefix_op" then
			if assignment.prefix_op_operator == "not" then
				--- TODO: `not (not A)` => `A`
				return false, assignment -- TODO
			elseif assignment.prefix_op_operator == "unm" then
				--- TODO: `-(-A)` => `A`
				--- TODO: `-K` => `K'`
				return false, assignment -- TODO
			else
				return false, assignment
			end
		else
			return false, assignment
		end
	end

	--- Folds and reassociates constants:
	--- * Operators whose operands are all constants are evaluated statically. The corresponding
	---   register assignment is replaced by a constant value.
	--- * For integer/numeric operands, the following transformations are applied:
	---   - Identities:
	---   - `A + 0` => `A`
	---   - `A - 0` => `A`
	---   - `0 - A` => `-A`
	---   - `A * 0` => `0`
	---   - `A * 1` => `A`
	---   - `A * 2` => `A + A`
	---   - `0 / A` => `0`
	---   - `A / 1` => `A`
	---   - `A ^ 0` => `1`
	---   - `A ^ 1` => `A`
	---   - `A ^ 2` => `A * A`
	---   - Normalisation:
	---     `K + A` => `A + K`
	---     `K * A` => `A * K`
	---   - `A + (-B)` => `A - B`
	---   - `(-A) + B` => `B - A`
	---   - `A - K` => `A + K'`
	---   - `A - (-B)` => `A + B`
	---   - `A / K` => `A * K'`
	---   - `A / (1/B)` => `A * B`
	---   - `-(-A)` => `A`
	---   - Constant propagation:
	---   - `(A + K1) + K2` => `A + (K1 + K2)`
	---   - `(K1 + A) + K2` => `A + (K1 + K2)`
	---   - `(K1 - A) + K2` => `(K1 + K2) - A`
	---   - `(A * K1) * K2` => `A * (K1 * K2)`
	---   - `(K1 * A) * K2` => `A * (K1 * K2)`
	---   - Comparison:
	---   - `A + K1 < K2` => `A < K2 - K1`
	---   - `A + K1 <= K2` => `A <= K2 - K1`
	---   - `A + K1 == K2` => `A == K2 - K1`
	---   - `A * K < 0` => `A < 0` or `A > 0` if `K` is -ve
	---   - `A * K <= 0` => `A <= 0` or `A >= 0` if `K` is -ve
	---   - `A / K < 0` => `A * K < 0`
	---   - `A / K <= 0` => `A * K <= 0`
	---   - `not (A < B)` => `B <= A`
	---   - `not (A <= B)` => `B < A`
	--- * Additionally, the following transformations are applied for booleans:
	---   - `not (not A)` => `A`
	---   - `not (A == B)` => `A ~= B`
	---   - `not (A ~= B)` => `A == B`
	---
	--- TODO: for single-ref registers, making sure not to hot loop things:
	---   - Re-association
	---   - `(A + K1) * K2` => `(A * K2) + (K1 * K2)`
	---   - `(A + K1) / K2` => `(A / K2) + (K1 / K2)`
	---   - `(K1 - A) * K2` => `(K1 * K2) - (A * K2)`
	---   - `(K1 - A) / K2` => `(K1 / K2) - (A / K2)`
	---   - `A - (B - C)` => `(A + C) - B`
	---   - `A / (B / C)` => `(A * C) / B`
	--- @param fn FnDef
	--- @return boolean changed
	function Optimisation.fold_constants(fn)
		local changed = false

		-- TODO: change this to be in eval order for fewer passes

		for reg_lookup, assignment in pairs(fn.registers) do
			local reg_changed, new_assignment = fold_constants(fn, assignment)
			local changed_at_least_once = reg_changed
			while reg_changed do
				reg_changed, new_assignment = fold_constants(fn, new_assignment)
			end
			if changed_at_least_once then
				fn.registers[reg_lookup] = new_assignment
				changed = true
			end
		end

		return changed
	end

	--- @param value ValueRef
	--- @return string
	local function operand_to_lookup(value)
		if value.value_kind == "register" then
			return IR.reg_to_lookup(value.register_id)
		else
			return "(" .. value.constant_value .. ")"
		end
	end

	--- @param infix RegAssignInfixOp
	--- @return string
	local function infix_to_lookup(infix)
		return infix.infix_op_operator .. "|" .. operand_to_lookup(infix.infix_op_lvalue) .. "|" .. operand_to_lookup(infix.infix_op_rvalue)
	end

	--- @param prefix RegAssignPrefixOp
	--- @return string
	local function prefix_to_lookup(prefix)
		return prefix.prefix_op_operator .. "|" .. operand_to_lookup(prefix.prefix_op_rvalue)
	end

	--- @param fn FnDef
	--- @param outer_statements Statement[]
	--- @param i integer
	--- @param inner_block_id BlockId
	--- @param registers_to_hoist { [RegisterIdLookup]: true }
	--- @param allow_inner_block boolean
	--- @return integer
	local function try_hoist_evaluations(fn, outer_statements, i, inner_block_id, registers_to_hoist, allow_inner_block)
		local n_hoisted = 0
		local inner_statements = fn.blocks[inner_block_id].statements
		local j = 1
		while j <= #inner_statements do
			local statement = inner_statements[j]
			if statement.statement_kind == "evaluate" then
				local register_lookup = IR.reg_to_lookup(statement.evaluate_register_id)
				if registers_to_hoist[register_lookup] then
					table.remove(inner_statements, j)
					j = j - 1
					table.insert(outer_statements, i, statement)
					i = i + 1
					n_hoisted = n_hoisted + 1
				end
			elseif statement.statement_kind == "if" and allow_inner_block then
				-- assume one is a `break` block, thus we can just do both as one will be a noop
				local inner_hoisted = try_hoist_evaluations(fn, outer_statements, i, statement.if_true, registers_to_hoist, false)
				inner_hoisted = inner_hoisted + try_hoist_evaluations(fn, outer_statements, i, statement.if_false, registers_to_hoist, false)
				n_hoisted = n_hoisted + inner_hoisted
				i = i + inner_hoisted
			end
			j = j + 1
		end
		return n_hoisted
	end

	--- @param value ValueRef
	--- @param loop_dependent_registers { [RegisterIdLookup]: true }
	--- @return true?
	local function is_var_loop_dependent(value, loop_dependent_registers)
		if value.value_kind == "register" then
			local move_reg_lookup = IR.reg_to_lookup(value.register_id)
			return loop_dependent_registers[move_reg_lookup]
		else
			return nil
		end
	end

	--- @param fn FnDef
	--- @param block_id BlockId
	--- @param loop_dependent_registers { [RegisterIdLookup]: true }
	--- @param already_evaluated_registers { [RegisterIdLookup]: true }
	--- @param cse_lookup { [string]: RegisterId }
	--- @param phis { [RegisterIdLookup]: true }
	--- @return boolean
	local function consume_block_for_licm_and_cse(fn, block_id, loop_dependent_registers, already_evaluated_registers, cse_lookup, phis)
		local changed = false
		local statements = fn.blocks[block_id].statements
		local i = 1
		while i <= #statements do
			local statement = statements[i]
			if statement.statement_kind == "evaluate" then
				local register_lookup = IR.reg_to_lookup(statement.evaluate_register_id)
				local assignment = fn.registers[register_lookup]

				if assignment.assign_kind == "infix_op" or assignment.assign_kind == "prefix_op" then
					-- TODO: unalias args?

					local op_lookup = assignment.assign_kind == "infix_op" and infix_to_lookup(assignment) or assignment.assign_kind == "prefix_op" and prefix_to_lookup(assignment) or nil

					if cse_lookup[op_lookup] then
						local target_register = cse_lookup[op_lookup]
						local target_register_lookup = IR.reg_to_lookup(target_register)
						local target_value = IR.reg_to_value(target_register)
						--- @type RegisterAssignment
						assignment = { assign_kind = "move", register_type = fn.registers[target_register_lookup].register_type, move_value = target_value }
						fn.registers[register_lookup] = assignment
						changed = true
					end

					if op_lookup and assignment.prefix_op_operator ~= "len" then
						cse_lookup[op_lookup] = IR.lookup_to_reg(register_lookup)
					end
				end

				if assignment.assign_kind == "load_param" then
					-- do nothing
				elseif assignment.assign_kind == "phi" then
					local primary = IR.reg_to_lookup(assignment.phi_primary)
					local secondary = IR.reg_to_lookup(assignment.phi_secondary)
					phis[primary] = true
					phis[secondary] = true
					if not already_evaluated_registers[primary] or not already_evaluated_registers[secondary] or loop_dependent_registers[primary] or loop_dependent_registers[secondary] then
						loop_dependent_registers[register_lookup] = true
					end
				elseif assignment.assign_kind == "move" then
					loop_dependent_registers[register_lookup] = is_var_loop_dependent(assignment.move_value, loop_dependent_registers)
				elseif assignment.assign_kind == "create_table" then
					--- @type true?
					local table_is_loop_dependent = true
					for _, element in ipairs(assignment.table_elements) do
						table_is_loop_dependent = table_is_loop_dependent or is_var_loop_dependent(element.key, loop_dependent_registers)
						table_is_loop_dependent = table_is_loop_dependent or is_var_loop_dependent(element.value, loop_dependent_registers)
						if table_is_loop_dependent then break end
					end
					loop_dependent_registers[register_lookup] = table_is_loop_dependent
				elseif assignment.assign_kind == "cast" then
					loop_dependent_registers[register_lookup] = is_var_loop_dependent(assignment.cast_subject, loop_dependent_registers)
				elseif assignment.assign_kind == "call_fn" then
					--- @type true?
					local call_is_loop_dependent = not assignment.call_fn_pure or nil
					for _, parameter in ipairs(assignment.call_fn_parameters) do
						if call_is_loop_dependent then
							break
						else
							call_is_loop_dependent = is_var_loop_dependent(parameter, loop_dependent_registers)
						end
					end
					loop_dependent_registers[register_lookup] = call_is_loop_dependent
				elseif assignment.assign_kind == "get_index" then
					-- TODO: detect dependence here; for now do nothing
					-- NOTE: this is very difficult since the table may be aliased, so any impure fn or set_index in the loop could affect this (LICM + CSE)
					loop_dependent_registers[register_lookup] = true -- sadge :/
				elseif assignment.assign_kind == "infix_op" then
					local is_invariant_l = is_var_loop_dependent(assignment.infix_op_lvalue, loop_dependent_registers)
					local is_invariant_r = is_var_loop_dependent(assignment.infix_op_rvalue, loop_dependent_registers)
					loop_dependent_registers[register_lookup] = is_invariant_l or is_invariant_r
				elseif assignment.assign_kind == "prefix_op" then
					local is_invariant_r = is_var_loop_dependent(assignment.prefix_op_rvalue, loop_dependent_registers)
					loop_dependent_registers[register_lookup] = is_invariant_r
				end

				already_evaluated_registers[register_lookup] = true
			elseif statement.statement_kind == "set_index" then
			elseif statement.statement_kind == "if" then
				local cse_lookup_if_true = {}
				local cse_lookup_if_false = {}
				for k, v in pairs(cse_lookup) do
					cse_lookup_if_true[k] = v
					cse_lookup_if_false[k] = v
				end

				changed = consume_block_for_licm_and_cse(fn, statement.if_true, loop_dependent_registers, already_evaluated_registers, cse_lookup_if_true, phis) or changed
				changed = consume_block_for_licm_and_cse(fn, statement.if_false, loop_dependent_registers, already_evaluated_registers, cse_lookup_if_false, phis) or changed
			elseif statement.statement_kind == "loop" then
				local did_hoist_any = false
				while true do
					local loop_inner_dependent_registers = {}
					local evaluated_registers = {}
					local inner_cse_lookup = {}
					for k, v in pairs(cse_lookup) do
						inner_cse_lookup[k] = v
					end
					local inner_phis = {}
					changed = consume_block_for_licm_and_cse(fn, statement.loop_body, loop_inner_dependent_registers, evaluated_registers, inner_cse_lookup, inner_phis) or changed
					for k, v in pairs(inner_phis) do
						phis[k] = v
					end

					local registers_to_hoist = {}
					for register_lookup in pairs(evaluated_registers) do
						if not loop_inner_dependent_registers[register_lookup] and not phis[register_lookup] then
							registers_to_hoist[register_lookup] = true
						end
					end

					if not next(registers_to_hoist) then break end
					local n_hoisted = try_hoist_evaluations(fn, statements, i, statement.loop_body, registers_to_hoist, true)
					if n_hoisted == 0 then break end
					did_hoist_any = true
				end
				if did_hoist_any then
					changed = true
					i = i - 1 -- repeat for the hoisted statements
				end
			elseif statement.statement_kind == "break" then
				-- do nothing
			end

			i = i + 1
		end
		return changed
	end

	--- Perform "Loop Invariant Code Motion" and "Common Subexpression Elimination":
	--- * LICM: move calculations which don't depend on a variable changing within the loop out of the loop
	--- * CSE: re-use previously calculated values
	--- @param fn FnDef
	--- @return boolean changed
	function Optimisation.licm_and_cse(fn)
		return consume_block_for_licm_and_cse(fn, fn.main_block, {}, {}, {}, {})
	end

	-- variable aliasing: if a variable is only assigned to or written once to another variable, replace the other variable with the first, mapping SSA versions
	-- sign simplification: e.g. where we evaluate `%temp0 < 0` and `%temp0 := %temp1 * %temp2` and we know the sign of either %temp1 or %temp2, simplify
	-- mutable table flattening & parameter flattening: if a variable is assigned to a table literal, then only used with `get_index` and `set_index` operations with constant keys, replace the variable with multiple variables for each key; same for `load_param`, but must write indices at the end; be careful of metatables
	-- loop unrolling: for loops with a known small number of iterations, repeat the loop body multiple times instead
	-- branch factoring: if both branches of an if statement start or end with the same kinds of statements, move those statements outside the if
	-- branch elimination: if the condition of an if statement is a constant, replace the if with just the relevant branch
	-- branch inversion: if the condition of an if statement is a NOT operation, swap the branches and remove the NOT
	-- looped strength reduction; if loop contains `k + i * x`, replace with variable `y = k; y = y + x`
	-- CSE for table indices: if an index is used multiple times, index once and use a register; be aware of writes and aliasing
	-- table preallocation? if `local a = {}; a[1] = x`, replace with `local a = { [1] = x }` or `{ [1] = 1 }` if `x` is dependent on a loop or sth
	-- http://lua-users.org/lists/lua-l/2009-11/msg00089.html
	-- https://github.com/tarantool/tarantool/wiki/LuaJIT-Optimizations
	--    NLF: Natural Loop First
	--    Recursive Unrolling
	--    Data-Flow Analysis
	--    Sparse Snapshotting
	--    1-D Snapshot Compression
	--    Control-Flow Specialization
	--    Hash Key Specialization
	--    Scalar Evolution Analysis
	--    AA: Alias Analysis
	--    ESC: Escape Analysis
	--    Index Reassociation
	--    FWD: Load Forwarding, Store Forwarding
	--    Loop-Invariant Hoisting via Synthetic Unrolling
	--    PHI Elimination
	--    Instable Loop Unrolling
	--    Spill and Restore Scheduling
	--    Loop Inversion
	--    Loop Alignment
end

local compile_to_lua
do
	--- @class LuaAssignment
	--- @field precedence integer
	--- @field pure boolean
	--- @field value string
	--- @field dependents { [RegisterIdLookup]: RegisterId }

	--- @alias LuaStatement
	--- | LuaEvalStatement
	--- | LuaSetIndexStatement
	--- | LuaIfStatement
	--- | LuaLoopStatement
	--- | LuaBreakStatement

	--- @class LuaEvalStatement
	--- @field statement_kind "evaluate"
	--- @field evaluate_register_id RegisterIdLookup

	--- @class LuaSetIndexStatement
	--- @field statement_kind "set_index"
	--- @field set_index_subject ValueRef
	--- @field set_index ValueRef
	--- @field set_index_value ValueRef

	--- @class LuaIfStatement
	--- @field statement_kind "if"
	--- @field if_condition ValueRef
	--- @field if_true BlockId
	--- @field if_false BlockId

	--- @class LuaLoopStatement
	--- @field statement_kind "loop"
	--- @field loop_body BlockId

	--- @class LuaBreakStatement
	--- @field statement_kind "break"

	local PRECEDENCE_MAX = 20

	--- @param register_id RegisterId
	--- @return string
	local function register_to_var_name(register_id)
		if register_id.register_kind == "temporary" then
			return "__temp" .. tostring(register_id.temporary_id)
		else
			return register_id.variable_name .. "_" .. tostring(register_id.variable_tag)
		end
	end

	--- @param value ValueRef
	--- @param inlineable_registers { [RegisterIdLookup]: true }
	--- @param dependents { [RegisterIdLookup]: RegisterId }
	--- @return string
	local function value_to_template_expr(value, inlineable_registers, dependents)
		if value.value_kind == "constant" then
			return value.constant_value
		else
			local reg_lookup = IR.reg_to_lookup(value.register_id)
			if inlineable_registers[reg_lookup] then
				dependents[reg_lookup] = value.register_id
				return "&" .. reg_lookup
			else
				return register_to_var_name(value.register_id)
			end
		end
	end

	local INFIX_OPS = {
		add = { precedence = 5, symbol = "+" },
		sub = { precedence = 5, symbol = "-" },
		mul = { precedence = 6, symbol = "*" },
		div = { precedence = 6, symbol = "/" },
		mod = { precedence = 6, symbol = "%" },
		exp = { precedence = 8, symbol = "^" },
		concat = { precedence = 4, symbol = ".." },
		lt = { precedence = 3, symbol = "<" },
		lte = { precedence = 3, symbol = "<=" },
		eq = { precedence = 3, symbol = "==" },
		neq = { precedence = 3, symbol = "~=" },
	}

	local PREFIX_OPS = {
		["not"] = { precedence = 7, symbol = "not " },
		len = { precedence = 7, symbol = "#" },
		unm = { precedence = 7, symbol = "-" },
	}

	--- @param fn FnDef
	--- @param assignment RegisterAssignment
	--- @param inlineable_registers { [RegisterIdLookup]: true }
	--- @return LuaAssignment
	local function convert_assignment(fn, assignment, inlineable_registers)
		if assignment.assign_kind == "move" then
			local dependents = {}
			return {
				precedence = PRECEDENCE_MAX,
				pure = true,
				value = value_to_template_expr(assignment.move_value, inlineable_registers, dependents),
				dependents = dependents,
			}
		elseif assignment.assign_kind == "load_param" then
			return {
				precedence = PRECEDENCE_MAX,
				pure = true,
				value = fn.params[assignment.load_param_index].name,
				dependents = {},
			}
		elseif assignment.assign_kind == "phi" then
			if assignment.phi_primary.variable_name ~= assignment.phi_secondary.variable_name then
				error "weird phi things happened :("
			end
			if assignment.phi_primary.variable_tag ~= assignment.phi_secondary.variable_tag then
				error "weird phi things happened :("
			end
			return {
				precedence = PRECEDENCE_MAX,
				pure = true,
				value = register_to_var_name(assignment.phi_primary),
				dependents = {},
			}
		elseif assignment.assign_kind == "create_table" then
			local array_values = {}
			local array_index = 1
			--- @type { key: ValueRef, value: ValueRef }[]
			local elements = {}
			for _, element in ipairs(assignment.table_elements) do
				table.insert(elements, element)
			end

			while true do
				local found = false
				local array_index_str = tostring(array_index)
				for i = #elements, 1, -1 do
					local key = elements[i].key
					if key.value_kind == "constant" and key.constant_value == array_index_str then
						table.insert(array_values, elements[i].value)
						table.remove(elements, i)
						array_index = array_index + 1
						found = true
						break
					end
				end
				if not found then
					break
				end
			end

			local s = "{"
			local dependents = {}

			for i, value in ipairs(array_values) do
				s = s .. (i == 1 and " " or ", ") .. value_to_template_expr(value, inlineable_registers, dependents)
			end

			for i, element in ipairs(elements) do
				local k = value_to_template_expr(element.key, inlineable_registers, dependents)
				local v = value_to_template_expr(element.value, inlineable_registers, dependents)
				s = s .. (i == 1 and #array_values == 0 and " " or ", ") .. "[" .. k .. "] = " .. v
			end

			return {
				precedence = PRECEDENCE_MAX,
				pure = true,
				value = s .. (#array_values == 0 and #elements == 0 and "" or " ") .. "}",
				dependents = dependents,
			}
		elseif assignment.assign_kind == "get_index" then
			local dependents = {}
			local subject = value_to_template_expr(assignment.get_index_subject, inlineable_registers, dependents)
			local index = value_to_template_expr(assignment.get_index, inlineable_registers, dependents)
			return {
				precedence = PRECEDENCE_MAX,
				pure = true,
				value = subject .. "[" .. index .. "]",
				dependents = dependents,
			}
		elseif assignment.assign_kind == "cast" then
			local dependents = {}
			return {
				precedence = PRECEDENCE_MAX,
				pure = true,
				value = value_to_template_expr(assignment.cast_subject, inlineable_registers, dependents),
				dependents = dependents,
			}
		elseif assignment.assign_kind == "call_fn" then
			local dependents = {}
			local params = {}
			for _, param in ipairs(assignment.call_fn_parameters) do
				table.insert(params, value_to_template_expr(param, inlineable_registers, dependents))
			end
			return {
				precedence = PRECEDENCE_MAX,
				pure = assignment.call_fn_pure,
				value = fn.name .. "(" .. table.concat(params, ", ") .. ")",
				dependents = dependents,
			}
		elseif assignment.assign_kind == "infix_op" then
			local op = INFIX_OPS[assignment.infix_op_operator]
			local dependents = {}
			return {
				precedence = op.precedence,
				pure = true,
				value = value_to_template_expr(assignment.infix_op_lvalue, inlineable_registers, dependents) .. " " .. op.symbol .. " " .. value_to_template_expr(assignment.infix_op_rvalue, inlineable_registers, dependents),
				dependents = dependents,
			}
		elseif assignment.assign_kind == "prefix_op" then
			local op = PREFIX_OPS[assignment.prefix_op_operator]
			local dependents = {}
			return {
				precedence = op.precedence,
				pure = true,
				value = op.symbol .. value_to_template_expr(assignment.prefix_op_rvalue, inlineable_registers, dependents),
				dependents = dependents,
			}
		else
			error("unhandled register assignment kind: " .. tostring(assignment.assign_kind))
		end
	end

	--- @param fn FnDef
	--- @return { [RegisterIdLookup]: true }
	local function find_single_reference_registers(fn)
		local ref_counts = {}

		local function note_value_ref(value)
			if value.value_kind == "register" then
				local reg_lookup = IR.reg_to_lookup(value.register_id)
				ref_counts[reg_lookup] = (ref_counts[reg_lookup] or 0) + 1
			end
		end

		for _, block in pairs(fn.blocks) do
			for _, statement in ipairs(block.statements) do
				if statement.statement_kind == "set_index" then
					note_value_ref(IR.reg_to_value(statement.set_index_subject))
					note_value_ref(statement.set_index)
					note_value_ref(statement.set_index_value)
				elseif statement.statement_kind == "if" then
					note_value_ref(statement.if_condition)
				end
			end
		end

		for _, assignment in pairs(fn.registers) do
			if assignment.assign_kind == "move" then
				note_value_ref(assignment.move_value)
			elseif assignment.assign_kind == "create_table" then
				for _, element in ipairs(assignment.table_elements) do
					note_value_ref(element.key)
					note_value_ref(element.value)
				end
			elseif assignment.assign_kind == "get_index" then
				note_value_ref(assignment.get_index_subject)
				note_value_ref(assignment.get_index)
			elseif assignment.assign_kind == "cast" then
				note_value_ref(assignment.cast_subject)
			elseif assignment.assign_kind == "call_fn" then
				for _, param in ipairs(assignment.call_fn_parameters) do
					note_value_ref(param)
				end
			elseif assignment.assign_kind == "infix_op" then
				note_value_ref(assignment.infix_op_lvalue)
				note_value_ref(assignment.infix_op_rvalue)
			elseif assignment.assign_kind == "prefix_op" then
				note_value_ref(assignment.prefix_op_rvalue)
			end
		end

		local inlineable = {}

		for reg_lookup, count in pairs(ref_counts) do
			if count == 1 then
				inlineable[reg_lookup] = true
			end
		end

		return inlineable
	end

	--- @class CompileToLuaCtx
	--- @field registers { [RegisterIdLookup]: LuaAssignment? }
	--- @field blocks { [BlockId]: LuaStatement[] }
	--- @field main_block BlockId
	--- @field return_value ValueRef
	--- @field single_reference_registers { [RegisterIdLookup]: true }
	local CompileToLuaCtx = {}

	--- @param fn FnDef
	--- @return CompileToLuaCtx
	function CompileToLuaCtx.new(fn)
		local single_reference_registers = find_single_reference_registers(fn)

		--- @type CompileToLuaCtx
		local ctx = {
			registers = {},
			blocks = {},
			main_block = fn.main_block,
			return_value = fn.return_value,
			single_reference_registers = single_reference_registers,
		}

		for reg_id, assignment in pairs(fn.registers) do
			ctx.registers[reg_id] = convert_assignment(fn, assignment, single_reference_registers)
		end

		for block_id, block in pairs(fn.blocks) do
			--- @type LuaStatement[]
			local new_block = {}
			for _, statement in ipairs(block.statements) do
				--- @cast statement Statement
				if statement.statement_kind == "evaluate" then
					local assign_kind = fn.registers[IR.reg_to_lookup(statement.evaluate_register_id)].assign_kind
					if assign_kind == "load_param" or assign_kind == "phi" then
						-- do nothing
					else
						table.insert(new_block, { statement_kind = "evaluate", evaluate_register_id = IR.reg_to_lookup(statement.evaluate_register_id) })
					end
				elseif statement.statement_kind == "set_index" then
					table.insert(new_block, { statement_kind = "set_index", set_index_subject = IR.reg_to_value(statement.set_index_subject), set_index = statement.set_index, set_index_value = statement.set_index_value })
				elseif statement.statement_kind == "if" then
					table.insert(new_block, { statement_kind = "if", if_condition = statement.if_condition, if_true = statement.if_true, if_false = statement.if_false })
				elseif statement.statement_kind == "loop" then
					table.insert(new_block, { statement_kind = "loop", loop_body = statement.loop_body })
				elseif statement.statement_kind == "break" then
					table.insert(new_block, { statement_kind = "break" })
				end
			end
			ctx.blocks[block_id] = new_block
		end

		return setmetatable(ctx, { __index = CompileToLuaCtx })
	end

	--- @param available_to_inline { [RegisterIdLookup]: true }
	function CompileToLuaCtx:apply_side_effect(available_to_inline)
		local to_remove = {}
		for reg_lookup in pairs(available_to_inline) do
			local assignment = self.registers[reg_lookup]
			if assignment and not assignment.pure then
				table.insert(to_remove, reg_lookup)
			end
		end
		for _, k in ipairs(to_remove) do
			available_to_inline[k] = nil
		end
	end

	--- @param reg_lookup RegisterIdLookup
	--- @param available_to_inline { [RegisterIdLookup]: true }
	--- @return boolean
	function CompileToLuaCtx:try_inline_inside_assignment(reg_lookup, available_to_inline)
		local assignment = self.registers[reg_lookup]

		if not assignment then
			return false
		end

		local inlined = {}
		for dep_reg_lookup, _ in pairs(assignment.dependents) do
			if available_to_inline[dep_reg_lookup] then
				local dep_find_str = "&" .. dep_reg_lookup
				local f = assignment.value:find(dep_find_str)

				if f then
					local dep_assignment = self.registers[dep_reg_lookup] or error "internal bug: dependency on a inlined register"
					if f == 1 or f == #assignment.value - #dep_find_str + 2 then
						assignment.precedence = math.min(assignment.precedence, dep_assignment.precedence)
					end

					assignment.pure = assignment.pure and dep_assignment.pure

					if assignment.value == dep_find_str then
						assignment.value = dep_assignment.value
					elseif dep_assignment.precedence < assignment.precedence then
						assignment.value = assignment.value:gsub(dep_find_str, "(" .. dep_assignment.value .. ")")
					elseif f ~= 1 and dep_assignment.precedence == assignment.precedence then
						assignment.value = assignment.value:gsub(dep_find_str, "(" .. dep_assignment.value .. ")")
					else
						assignment.value = assignment.value:gsub(dep_find_str, dep_assignment.value)
					end

					table.insert(inlined, dep_reg_lookup)
				end
			end
		end

		for _, k in ipairs(inlined) do
			self.registers[k] = nil
			assignment.dependents[k] = nil
		end

		if not assignment.pure then
			self:apply_side_effect(available_to_inline)
		end

		if IR.lookup_to_reg(reg_lookup).register_kind == "temporary" then
			available_to_inline[reg_lookup] = true
		end

		return #inlined > 0
	end

	--- @param statement LuaStatement
	--- @param key string
	--- @param available_to_inline { [RegisterIdLookup]: true }
	--- @return boolean
	function CompileToLuaCtx:try_inline_inside_indirect(statement, key, available_to_inline)
		--- @type ValueRef
		local value = statement[key]
		if value.value_kind == "register" then
			local reg_lookup = IR.reg_to_lookup(value.register_id)
			if available_to_inline[reg_lookup] and self.single_reference_registers[reg_lookup] then
				statement[key] = {
					value_kind = "constant",
					constant_value = self:finalise_assignment(self.registers[reg_lookup]),
					constant_type = IR.DYNAMIC_TYPE,
				}
				self.registers[reg_lookup] = nil
				return true
			end
		end
		return false
	end

	--- @param block_id BlockId
	--- @param available_to_inline { [RegisterIdLookup]: true }
	--- @return boolean
	function CompileToLuaCtx:do_inline_pass(block_id, available_to_inline)
		local block = self.blocks[block_id]
		local changed = false

		for _, statement in ipairs(block) do
			if statement.statement_kind == "evaluate" then
				changed = self:try_inline_inside_assignment(statement.evaluate_register_id, available_to_inline) or changed
			elseif statement.statement_kind == "set_index" then
				changed = self:try_inline_inside_indirect(statement, "set_index_subject", available_to_inline) or changed
				changed = self:try_inline_inside_indirect(statement, "set_index", available_to_inline) or changed
				changed = self:try_inline_inside_indirect(statement, "set_index_value", available_to_inline) or changed
				self:apply_side_effect(available_to_inline)
			elseif statement.statement_kind == "if" then
				changed = self:try_inline_inside_indirect(statement, "if_condition", available_to_inline) or changed
				local available_to_inline_clone = {}
				for k, v in pairs(available_to_inline) do
					available_to_inline_clone[k] = v
				end
				changed = self:do_inline_pass(statement.if_true, available_to_inline) or changed
				changed = self:do_inline_pass(statement.if_false, available_to_inline_clone) or changed
				local removed_keys = {}
				for k, _ in pairs(available_to_inline) do
					if not available_to_inline_clone[k] then
						table.insert(removed_keys, k)
					end
				end
				for _, k in ipairs(removed_keys) do
					available_to_inline[k] = nil
				end
			elseif statement.statement_kind == "loop" then
				changed = self:do_inline_pass(statement.loop_body, {}) or changed
			elseif statement.statement_kind == "break" then
				self:apply_side_effect(available_to_inline)
			end
		end

		return changed
	end

	--- @param return_value ValueRef
	--- @return string
	function CompileToLuaCtx:inline_return_value(return_value)
		local available_to_inline = {}
		self:do_inline_pass(self.main_block, available_to_inline)
		if return_value.value_kind == "constant" then
			return return_value.constant_value
		else
			local reg_lookup = IR.reg_to_lookup(return_value.register_id)
			local assignment = self.registers[reg_lookup] or error "internal bug: return value is an inlined register"

			if available_to_inline[reg_lookup] then
				self.registers[reg_lookup] = nil
				return assignment.value
			else
				return register_to_var_name(return_value.register_id)
			end
		end
	end

	--- @param assignment LuaAssignment
	function CompileToLuaCtx:finalise_assignment(assignment)
		for reg_lookup, reg_id in pairs(assignment.dependents) do
			assignment.value = assignment.value:gsub("&" .. reg_lookup, register_to_var_name(reg_id))
		end
		return assignment.value
	end

	--- @param value ValueRef
	function CompileToLuaCtx:get_finalised_value(value)
		if value.value_kind == "constant" then
			return value.constant_value
		else
			return register_to_var_name(value.register_id)
		end
	end

	local function is_break_block(block)
		return #block == 1 and block[1].statement_kind == "break"
	end

	function CompileToLuaCtx:write_block(block_id, lines, newline)
		for _, statement in ipairs(self.blocks[block_id]) do
			if statement.statement_kind == "evaluate" then
				local assignment = self.registers[statement.evaluate_register_id]
				if assignment then
					local register_id = IR.lookup_to_reg(statement.evaluate_register_id)
					local var_name = register_to_var_name(register_id)
					local is_local = register_id.register_kind ~= "variable" or register_id.ssa_version == 0
					table.insert(lines, newline .. (is_local and "local " or "") .. var_name .. " = " .. self:finalise_assignment(assignment))
				end
			elseif statement.statement_kind == "set_index" then
				local subject = self:get_finalised_value(statement.set_index_subject)
				local index = self:get_finalised_value(statement.set_index)
				local value = self:get_finalised_value(statement.set_index_value)
				table.insert(lines, newline .. subject .. "[" .. index .. "] = " .. value)
			elseif statement.statement_kind == "if" then
				table.insert(lines, newline .. "if " .. self:get_finalised_value(statement.if_condition) .. " then")
				self:write_block(statement.if_true, lines, newline .. "\t")
				table.insert(lines, newline .. "else")
				self:write_block(statement.if_false, lines, newline .. "\t")
				table.insert(lines, newline .. "end")
			elseif statement.statement_kind == "loop" then
				local did_simplify_while = false
				local statements = self.blocks[statement.loop_body]
				for statement_index = 1, #statements do
					local if_candidate = statements[statement_index]
					if if_candidate.statement_kind == "if" then
						local if_true = if_candidate.if_true
						local if_false = if_candidate.if_false
						if is_break_block(self.blocks[if_false]) then
							table.insert(lines, newline .. "while " .. self:get_finalised_value(if_candidate.if_condition) .. " do")
							self:write_block(if_true, lines, newline .. "\t")
							table.insert(lines, newline .. "end")
							did_simplify_while = true
							break
						elseif is_break_block(self.blocks[if_true]) then
							table.insert(lines, newline .. "while not " .. self:get_finalised_value(if_candidate.if_condition) .. " do")
							self:write_block(if_false, lines, newline .. "\t")
							table.insert(lines, newline .. "end")
							did_simplify_while = true
							break
						end
					elseif if_candidate.statement_kind ~= "evaluate" or self.registers[if_candidate.evaluate_register_id] then
						break
					end
				end
				if not did_simplify_while then
					table.insert(lines, newline .. "while true do")
					self:write_block(statement.loop_body, lines, newline .. "\t")
					table.insert(lines, newline .. "end")
				end
			elseif statement.statement_kind == "break" then
				table.insert(lines, newline .. "break")
			end
		end
	end

	--- @param fn FnDef
	function compile_to_lua(fn)
		local ctx = CompileToLuaCtx.new(fn)

		while ctx:do_inline_pass(fn.main_block, {}) do end
		local return_value_str = fn.return_value and ctx:inline_return_value(fn.return_value)
		local lines = {}
		ctx:write_block(fn.main_block, lines, "\n\t")

		local str = "return function("
		for i, param in ipairs(fn.params) do
			str = str .. param.name
			if i < #fn.params then
				str = str .. ", "
			end
		end
		str = str .. ")"
		str = str .. table.concat(lines)
		if fn.return_value then
			str = str .. "\n\t" .. return_value_str
		end
		return str .. "\nend"
	end
end

local tokens = vsl_parse.lex [[
struct vec2 {
	x: number,
	y: number
}

struct vec3 {
	x: number,
	y: number,
	z: number,
}

struct Bbox {
	top_left: vec2,
	bottom_right: vec2
}

struct Poly {
	-- vertices: [vec3; 3]
	vertex1: vec3,
	vertex2: vec3,
	vertex3: vec3,
}

function vec2_add_vec2(a: vec2, b: vec2): vec2
	vec2(a.x + b.x, a.y + b.y)
end

function vec3_add_vec3(a: vec3, b: vec3): vec3
	vec3(a.x + b.x, a.y + b.y, a.z + b.z)
end

-- function transform_mul_vec3(transform: V3DTransform, vec: vec3): vec3
-- 	vec3(
-- 		transform.1 * vec.x + transform.2 * vec.y + transform.3 * vec.z + transform.4,
-- 		transform.5 * vec.x + transform.6 * vec.y + transform.7 * vec.z + transform.8,
-- 		transform.9 * vec.x + transform.10 * vec.y + transform.11 * vec.z + transform.12,
-- 	)
-- end

-- function replace<T>(bboxes: buffer<Bbox>)
-- 	local i = 1
-- 	while i < 10 do
-- 		floor(i)
-- 		bboxes[i].bottom_right = vec2(1, 2) + vec2(3, 4)
-- 		i = i + 1
-- 	end
-- end

-- function transform_polys(polys: buffer<Poly>, transform: V3DTransform)
-- 	for i, poly in polys do
-- 		-- poly.vertex1 = transform * poly.vertex1
-- 		poly.vertex2 = poly.vertex2 + vec3(1, 2, 3)
-- 	end
-- 	-- local temp = 1
-- 	-- while temp <= 10 do
-- 	-- 	polys[temp].vertex1 = transform * polys[temp].vertex1
-- 	-- 	-- polys[temp].vertex2 = transform * polys[temp].vertex2
-- 	-- 	-- polys[temp].vertex3 = transform * polys[temp].vertex3
-- 	-- 	temp = temp + 1
-- 	-- end
-- end

-- function licm_test(vecs: buffer<vec3>, add: vec3)
-- 	local a2 = vec3(add.x, add.y, add.z)
-- 	for vec in vecs do
-- 		for i = 1, 3 do
-- 			vec = a2 + vec3(4, 5, 6)
-- 		end
-- 	end
-- end

function ssa_aliasing_test()
	local t: dynamic = {}
	local i = 0
	while i < 10 do
		local j = i
		i = i + 1
		t.x = i :: dynamic
		t.y = j :: dynamic
		i = j + 1
	end
end
]]

local globals = GlobalCtx.new()
	:define_opaque_fn("floor", true, {}, { { name = "value", type = IR.NUMBER_TYPE } }, IR.NUMBER_TYPE)
	:define_type("V3DTransform", {}, false, {
		{ name = 1, offset = 0, type = IR.NUMBER_TYPE },
		{ name = 2, offset = 1, type = IR.NUMBER_TYPE },
		{ name = 3, offset = 2, type = IR.NUMBER_TYPE },
		{ name = 4, offset = 3, type = IR.NUMBER_TYPE },
		{ name = 5, offset = 4, type = IR.NUMBER_TYPE },
		{ name = 6, offset = 5, type = IR.NUMBER_TYPE },
		{ name = 7, offset = 6, type = IR.NUMBER_TYPE },
		{ name = 8, offset = 7, type = IR.NUMBER_TYPE },
		{ name = 9, offset = 8, type = IR.NUMBER_TYPE },
		{ name = 10, offset = 9, type = IR.NUMBER_TYPE },
		{ name = 11, offset = 10, type = IR.NUMBER_TYPE },
		{ name = 12, offset = 11, type = IR.NUMBER_TYPE },
	}, nil)
local result = parse(tokens, globals)
for _, def in ipairs(result) do
	if def.type == "function" then
		print(fn_tostring(def))
		Optimisation.unalias_trivial_moves(def)
		Optimisation.remove_dead_code(def)
		print(fn_tostring(def))
		Optimisation.flatten_tables(def)
		Optimisation.unalias_trivial_moves(def)
		Optimisation.fold_constants(def)
		Optimisation.unalias_trivial_moves(def)
		Optimisation.remove_dead_code(def)
		print(fn_tostring(def))
		while Optimisation.licm_and_cse(def) do Optimisation.unalias_trivial_moves(def) end
		Optimisation.remove_dead_code(def)
		print(fn_tostring(def))
		print(compile_to_lua(def))
	end
end
