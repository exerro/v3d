
local IR = {}

----------------------------------------------------------------------------------------------------

do -- registers, values, and variables
	--- Numeric ID of a register.
	--- @class IRRegisterId: integer

	--- A reference to a register or a constant value.
	--- @alias IRValue IRConstant | IRRegisterRef

	--- A constant value. `constant_value` is Lua-formatted and must be copy-able (i.e. not a
	--- table literal).
	--- @class IRConstant
	--- @field value_kind "constant"
	--- @field constant_value string

	--- A reference to a register.
	--- @class IRRegisterRef
	--- @field value_kind "register"
	--- @field register_id IRRegisterId

	--- A variable with a tag to disambiguate shadowed names.
	--- @class IRVariable
	--- @field variable_name string
	--- @field variable_tag IRVariableTag

	--- A tag to disambiguate shadowed names.
	--- @class IRVariableTag: integer

	----------------------------------------------------------------------------

	--- Create a register reference value from the given register ID.
	--- @param register_id IRRegisterId
	--- @return IRRegisterRef
	function IR.register(register_id)
		return { value_kind = "register", register_id = register_id }
	end

	--- Create a constant value. Value is converted to a string. Strings are not quoted.
	--- @param constant_value any
	--- @return IRConstant
	function IR.constant(constant_value)
		return { value_kind = "constant", constant_value = tostring(constant_value) }
	end

	--- Create a constant value. Value is converted to a string. Strings are quoted.
	--- @param constant_value any
	--- @return IRConstant
	function IR.constant_quoting(constant_value)
		if type(constant_value) == "string" then
			constant_value = string.format("%q", constant_value)
		end
		return IR.constant(constant_value)
	end

	--- Return a string representation of a value suitable for serialization or table keys.
	--- @param value IRValue
	--- @return string
	function IR.value_to_lookup(value)
		if value.value_kind == "register" then
			return "R" .. tostring(value.register_id)
		else
			return "K" .. value.constant_value
		end
	end

	--- Convert a value lookup string back into an IRValue.
	--- @param lookup string
	--- @return IRValue
	function IR.value_from_lookup(lookup)
		if lookup:sub(1, 1) == "R" then
			return IR.register(tonumber(lookup:sub(2)) or error("invalid register id: " .. lookup:sub(2)))
		else
			return IR.constant(lookup:sub(2))
		end
	end

	--- Return a user-readable string representation of a value.
	--- @param value IRValue
	function IR.value_to_string(value)
		if value.value_kind == "register" then
			return "R(" .. tostring(value.register_id) .. ")"
		else
			return "K(" .. value.constant_value .. ")"
		end
	end

	--- Create a variable using its name and tag.
	--- @param name string
	--- @param tag IRVariableTag
	--- @return IRVariable
	function IR.variable(name, tag)
		return { variable_name = name, variable_tag = tag }
	end

	--- Return a user-readable string representation of a variable.
	--- @param var IRVariable
	--- @return string
	function IR.variable_to_string(var)
		return string.format("%s#%d", var.variable_name, var.variable_tag)
	end

	--- Return a user-readable string representation of a variable.
	--- @param var_name string
	--- @param var_tag IRVariableTag
	--- @return string
	function IR.variable2_to_string(var_name, var_tag)
		return string.format("%s#%d", var_name, var_tag)
	end

	--- Create a variable from its string representation.
	--- @param str string
	--- @return IRVariable
	function IR.variable_from_string(str)
		local name, tag = str:match("^(.-)#(%d+)$")
		return IR.variable(name, tonumber(tag) or error("invalid variable tag: " .. tag))
	end
end

----------------------------------------------------------------------------------------------------

do -- blocks and instructions
	--- A sequence of instructions.
	--- @class IRBlock
	--- @field instructions IRInstruction[]

	--- An atomic operation.
	--- @alias IRInstruction
	--- | IRLoadInstruction
	--- | IRStoreInstruction
	--- | IRParamInstruction
	--- | IRCopyInstruction
	--- | IRTableInstruction
	--- | IRGetInstruction
	--- | IRSetInstruction
	--- | IRCallInstruction
	--- | IRAddInstruction
	--- | IRSubInstruction
	--- | IRMulInstruction
	--- | IRDivInstruction
	--- | IRModInstruction
	--- | IRExpInstruction
	--- | IREqInstruction
	--- | IRLtInstruction
	--- | IRLteInstruction
	--- | IRUnmInstruction
	--- | IRNotInstruction
	--- | IRLenInstruction
	--- | IRIfInstruction
	--- | IRLoopInstruction
	--- | IRBreakInstruction

	--- Load the latest value of a variable into a register.
	---
	--- We store variables separately to registers since SSA and instruction reordering logic differs.
	---
	--- `R(<register_id>) := V(<load_variable>)`
	--- @class IRLoadInstruction
	--- @field instruction_kind "load"
	--- @field register_id IRRegisterId
	--- @field load_variable IRVariable

	--- Store the value of a register into a variable.
	---
	--- `V(<store_variable>) := RK(<store_value>)`
	--- @class IRStoreInstruction
	--- @field instruction_kind "store"
	--- @field store_variable IRVariable
	--- @field store_value IRValue

	--- Load a parameter value into a register.
	---
	--- Practically this is a no-op. However, this helps optimisation and codegen understand how the
	--- value is used and tracked.
	---
	--- `R(<register_id>) := P(<param_index>)`
	--- @class IRParamInstruction
	--- @field instruction_kind "param"
	--- @field register_id IRRegisterId
	--- @field param_index number

	--- Copy a value into a register.
	---
	--- `R(<register_id>) := RK(<copy_value>)`
	--- @class IRCopyInstruction
	--- @field instruction_kind "copy"
	--- @field register_id IRRegisterId
	--- @field copy_value IRValue

	--- Assign an empty table to a register.
	---
	--- `R(<register_id>) := {}`
	--- @class IRTableInstruction
	--- @field instruction_kind "table"
	--- @field register_id IRRegisterId

	--- Get an index of a table and store it in a register.
	---
	--- `R(<register_id>) := R(<get_subject>)[RK(<get_index>)]`
	--- @class IRGetInstruction
	--- @field instruction_kind "get"
	--- @field register_id IRRegisterId
	--- @field get_subject IRRegisterId
	--- @field get_index IRValue

	--- Set an index of a table to a value.
	---
	--- `R(<set_subject>)[RK(<set_index>)] := RK(<set_value>)`
	--- @class IRSetInstruction
	--- @field instruction_kind "set"
	--- @field set_subject IRRegisterId
	--- @field set_index IRValue
	--- @field set_value IRValue

	--- Call a function with the given parameters and store the result in a register.
	---
	--- The function is pure if it has no side effects, i.e. the call may be omitted without
	--- consequence.
	---
	--- `R(<register_id>) := <call_fn_name>(RK(<call_parameters>)...)`
	--- @class IRCallInstruction
	--- @field instruction_kind "call"
	--- @field register_id IRRegisterId
	--- @field call_fn_name string
	--- @field call_parameters IRValue[]
	--- @field call_is_pure boolean

	--- Add two values and store the result in a register.
	---
	--- `is_dynamic` captures whether the instruction may invoke any metamethod.
	---
	--- `R(<register_id>) := RK(<add_lvalue>) + RK(<add_rvalue>)`
	--- @class IRAddInstruction
	--- @field instruction_kind "add"
	--- @field register_id IRRegisterId
	--- @field is_dynamic boolean
	--- @field add_lvalue IRValue
	--- @field add_rvalue IRValue

	--- Subtract two values and store the result in a register.
	---
	--- `is_dynamic` captures whether the instruction may invoke any metamethod.
	---
	--- `R(<register_id>) := RK(<sub_lvalue>) - RK(<sub_rvalue>)`
	--- @class IRSubInstruction
	--- @field instruction_kind "sub"
	--- @field register_id IRRegisterId
	--- @field is_dynamic boolean
	--- @field sub_lvalue IRValue
	--- @field sub_rvalue IRValue

	--- Multiply two values and store the result in a register.
	---
	--- `is_dynamic` captures whether the instruction may invoke any metamethod.
	---
	--- `R(<register_id>) := RK(<mul_lvalue>) * RK(<mul_rvalue>)`
	--- @class IRMulInstruction
	--- @field instruction_kind "mul"
	--- @field register_id IRRegisterId
	--- @field is_dynamic boolean
	--- @field mul_lvalue IRValue
	--- @field mul_rvalue IRValue

	--- Divide two values and store the result in a register.
	---
	--- `is_dynamic` captures whether the instruction may invoke any metamethod.
	---
	--- `R(<register_id>) := RK(<div_lvalue>) / RK(<div_rvalue>)`
	--- @class IRDivInstruction
	--- @field instruction_kind "div"
	--- @field register_id IRRegisterId
	--- @field is_dynamic boolean
	--- @field div_lvalue IRValue
	--- @field div_rvalue IRValue

	--- Modulo two values and store the result in a register.
	---
	--- `is_dynamic` captures whether the instruction may invoke any metamethod.
	---
	--- `R(<register_id>) := RK(<mod_lvalue>) % RK(<mod_rvalue>)`
	--- @class IRModInstruction
	--- @field instruction_kind "mod"
	--- @field register_id IRRegisterId
	--- @field is_dynamic boolean
	--- @field mod_lvalue IRValue
	--- @field mod_rvalue IRValue

	--- Exponentiate two values and store the result in a register.
	---
	--- `is_dynamic` captures whether the instruction may invoke any metamethod.
	---
	--- `R(<register_id>) := RK(<exp_lvalue>) ^ RK(<exp_rvalue>)`
	--- @class IRExpInstruction
	--- @field instruction_kind "exp"
	--- @field register_id IRRegisterId
	--- @field is_dynamic boolean
	--- @field exp_lvalue IRValue
	--- @field exp_rvalue IRValue

	--- Concatenate two strings and store the result in a register.
	---
	--- `is_dynamic` captures whether the instruction may invoke any metamethod.
	---
	--- `R(<register_id>) := RK(<cat_lvalue>) .. RK(<cat_rvalue>)`
	--- @class IRCatInstruction
	--- @field instruction_kind "cat"
	--- @field register_id IRRegisterId
	--- @field is_dynamic boolean
	--- @field cat_lvalue IRValue
	--- @field cat_rvalue IRValue

	--- Check if two values are equal and store the result in a register.
	---
	--- `is_dynamic` captures whether the instruction may invoke any metamethod.
	---
	--- `R(<register_id>) := RK(<eq_lvalue>) == RK(<eq_rvalue>)`
	--- @class IREqInstruction
	--- @field instruction_kind "eq"
	--- @field register_id IRRegisterId
	--- @field is_dynamic boolean
	--- @field eq_lvalue IRValue
	--- @field eq_rvalue IRValue

	--- Check if the left value is less than the right value.
	---
	--- `is_dynamic` captures whether the instruction may invoke any metamethod.
	---
	--- `R(<register_id>) := RK(<lt_lvalue>) < RK(<lt_rvalue>)`
	--- @class IRLtInstruction
	--- @field instruction_kind "lt"
	--- @field register_id IRRegisterId
	--- @field is_dynamic boolean
	--- @field lt_lvalue IRValue
	--- @field lt_rvalue IRValue

	--- Check if the left value is less than or equal to the right value.
	---
	--- `is_dynamic` captures whether the instruction may invoke any metamethod.
	---
	--- `R(<register_id>) := RK(<lte_lvalue>) <= RK(<lte_rvalue>)`
	--- @class IRLteInstruction
	--- @field instruction_kind "lte"
	--- @field register_id IRRegisterId
	--- @field is_dynamic boolean
	--- @field lte_lvalue IRValue
	--- @field lte_rvalue IRValue

	--- Negate a value and store the result in a register.
	---
	--- `is_dynamic` captures whether the instruction may invoke any metamethod.
	---
	--- `R(<register_id>) := -RK(<unm_rvalue>)`
	--- @class IRUnmInstruction
	--- @field instruction_kind "unm"
	--- @field register_id IRRegisterId
	--- @field is_dynamic boolean
	--- @field unm_rvalue IRValue

	--- Invert a boolean value and store the result in a register.
	---
	--- `R(<register_id>) := not RK(<not_rvalue>)`
	--- @class IRNotInstruction
	--- @field instruction_kind "not"
	--- @field register_id IRRegisterId
	--- @field not_rvalue IRValue

	--- Get the length of a string or table and store the result in a register.
	---
	--- `R(<register_id>) := #RK(<len_subject>)`
	--- @class IRLenInstruction
	--- @field instruction_kind "len"
	--- @field register_id IRRegisterId
	--- @field len_subject IRRegisterId

	--- Perform the instructions of one of two branches based on a condition.
	---
	--- `IF <if_condition> THEN <if_true_block> ELSE <if_false_block>`
	--- @class IRIfInstruction
	--- @field instruction_kind "if"
	--- @field if_condition IRValue
	--- @field if_true_block IRBlock
	--- @field if_false_block IRBlock

	--- Perform the instructions of the loop block until broken.
	---
	--- `LOOP <loop_block>`
	--- @class IRLoopInstruction
	--- @field instruction_kind "loop"
	--- @field loop_block IRBlock

	--- Break out of a containing LOOP instruction.
	---
	--- `BREAK`
	--- @class IRBreakInstruction
	--- @field instruction_kind "break"

	----------------------------------------------------------------------------

	--- @param register_id IRRegisterId
	--- @param variable IRVariable
	--- @return IRLoadInstruction
	function IR.LOAD(register_id, variable)
		return { instruction_kind = "load", register_id = register_id, load_variable = variable }
	end

	--- @param variable IRVariable
	--- @param value IRValue
	--- @return IRStoreInstruction
	function IR.STORE(variable, value)
		return { instruction_kind = "store", store_variable = variable, store_value = value }
	end

	--- @param register_id IRRegisterId
	--- @param param_index integer
	--- @return IRParamInstruction
	function IR.PARAM(register_id, param_index)
		return { instruction_kind = "param", register_id = register_id, param_index = param_index }
	end

	--- @param register_id IRRegisterId
	--- @param value IRValue
	--- @return IRCopyInstruction
	function IR.COPY(register_id, value)
		return { instruction_kind = "copy", register_id = register_id, copy_value = value }
	end

	--- @param register_id IRRegisterId
	--- @param subject IRRegisterId
	--- @param index IRValue
	--- @return IRGetInstruction
	function IR.GET(register_id, subject, index)
		return { instruction_kind = "get", register_id = register_id, get_subject = subject, get_index = index }
	end

	--- @param subject IRRegisterId
	--- @param index IRValue
	--- @param value IRValue
	--- @return IRSetInstruction
	function IR.SET(subject, index, value)
		return { instruction_kind = "set", set_subject = subject, set_index = index, set_value = value }
	end

	--- @param register_id IRRegisterId
	--- @param fn_name string
	--- @param parameters IRValue[]
	--- @param is_pure boolean
	--- @return IRCallInstruction
	function IR.CALL(register_id, fn_name, parameters, is_pure)
		return { instruction_kind = "call", register_id = register_id, call_fn_name = fn_name, call_parameters = parameters, call_is_pure = is_pure }
	end

	--- @param register_id IRRegisterId
	--- @param lvalue IRValue
	--- @param rvalue IRValue
	--- @param is_dynamic boolean
	--- @return IRAddInstruction
	function IR.ADD(register_id, lvalue, rvalue, is_dynamic)
		return { instruction_kind = "add", register_id = register_id, add_lvalue = lvalue, add_rvalue = rvalue, is_dynamic = is_dynamic }
	end

	--- @param register_id IRRegisterId
	--- @param lvalue IRValue
	--- @param rvalue IRValue
	--- @param is_dynamic boolean
	--- @return IRSubInstruction
	function IR.SUB(register_id, lvalue, rvalue, is_dynamic)
		return { instruction_kind = "sub", register_id = register_id, sub_lvalue = lvalue, sub_rvalue = rvalue, is_dynamic = is_dynamic }
	end

	--- @param register_id IRRegisterId
	--- @param lvalue IRValue
	--- @param rvalue IRValue
	--- @param is_dynamic boolean
	--- @return IRMulInstruction
	function IR.MUL(register_id, lvalue, rvalue, is_dynamic)
		return { instruction_kind = "mul", register_id = register_id, mul_lvalue = lvalue, mul_rvalue = rvalue, is_dynamic = is_dynamic }
	end

	--- @param register_id IRRegisterId
	--- @param lvalue IRValue
	--- @param rvalue IRValue
	--- @param is_dynamic boolean
	--- @return IRDivInstruction
	function IR.DIV(register_id, lvalue, rvalue, is_dynamic)
		return { instruction_kind = "div", register_id = register_id, div_lvalue = lvalue, div_rvalue = rvalue, is_dynamic = is_dynamic }
	end

	--- @param register_id IRRegisterId
	--- @param lvalue IRValue
	--- @param rvalue IRValue
	--- @param is_dynamic boolean
	--- @return IRModInstruction
	function IR.MOD(register_id, lvalue, rvalue, is_dynamic)
		return { instruction_kind = "mod", register_id = register_id, mod_lvalue = lvalue, mod_rvalue = rvalue, is_dynamic = is_dynamic }
	end

	--- @param register_id IRRegisterId
	--- @param lvalue IRValue
	--- @param rvalue IRValue
	--- @param is_dynamic boolean
	--- @return IRExpInstruction
	function IR.EXP(register_id, lvalue, rvalue, is_dynamic)
		return { instruction_kind = "exp", register_id = register_id, exp_lvalue = lvalue, exp_rvalue = rvalue, is_dynamic = is_dynamic }
	end

	--- @param register_id IRRegisterId
	--- @param lvalue IRValue
	--- @param rvalue IRValue
	--- @param is_dynamic boolean
	--- @return IRCatInstruction
	function IR.CAT(register_id, lvalue, rvalue, is_dynamic)
		return { instruction_kind = "cat", register_id = register_id, cat_lvalue = lvalue, cat_rvalue = rvalue, is_dynamic = is_dynamic }
	end

	--- @param register_id IRRegisterId
	--- @param lvalue IRValue
	--- @param rvalue IRValue
	--- @param is_dynamic boolean
	--- @return IREqInstruction
	function IR.EQ(register_id, lvalue, rvalue, is_dynamic)
		return { instruction_kind = "eq", register_id = register_id, eq_lvalue = lvalue, eq_rvalue = rvalue, is_dynamic = is_dynamic }
	end

	--- @param register_id IRRegisterId
	--- @param lvalue IRValue
	--- @param rvalue IRValue
	--- @param is_dynamic boolean
	--- @return IRLtInstruction
	function IR.LT(register_id, lvalue, rvalue, is_dynamic)
		return { instruction_kind = "lt", register_id = register_id, lt_lvalue = lvalue, lt_rvalue = rvalue, is_dynamic = is_dynamic }
	end

	--- @param register_id IRRegisterId
	--- @param lvalue IRValue
	--- @param rvalue IRValue
	--- @param is_dynamic boolean
	--- @return IRLteInstruction
	function IR.LTE(register_id, lvalue, rvalue, is_dynamic)
		return { instruction_kind = "lte", register_id = register_id, lte_lvalue = lvalue, lte_rvalue = rvalue, is_dynamic = is_dynamic }
	end

	--- @param register_id IRRegisterId
	--- @param value IRValue
	--- @param is_dynamic boolean
	--- @return IRUnmInstruction
	function IR.UNM(register_id, value, is_dynamic)
		return { instruction_kind = "unm", register_id = register_id, unm_value = value, is_dynamic = is_dynamic }
	end

	--- @param register_id IRRegisterId
	--- @param value IRValue
	--- @return IRNotInstruction
	function IR.NOT(register_id, value)
		return { instruction_kind = "not", register_id = register_id, not_value = value }
	end

	--- @param register_id IRRegisterId
	--- @param subject IRRegisterId
	--- @return IRLenInstruction
	function IR.LEN(register_id, subject)
		return { instruction_kind = "len", register_id = register_id, len_suject = subject }
	end

	--- @param condition IRValue
	--- @param true_block IRBlock
	--- @param false_block IRBlock
	--- @return IRIfInstruction
	function IR.IF(condition, true_block, false_block)
		return { instruction_kind = "if", if_condition = condition, if_true_block = true_block, if_false_block = false_block }
	end

	--- @param block IRBlock
	--- @return IRLoopInstruction
	function IR.LOOP(block)
		return { instruction_kind = "loop", loop_block = block }
	end

	--- @return IRBreakInstruction
	function IR.BREAK()
		return { instruction_kind = "break" }
	end

	----------------------------------------------------------------------------

	--- @param original IRInstruction
	--- @param ctor fun(IRRegisterId, IRValue, IRValue, boolean): IRInstruction
	--- @param register_id IRRegisterId
	--- @param lvalue IRValue
	--- @param rvalue IRValue
	--- @param is_dynamic boolean
	--- @param map fun(IRValue): IRValue
	--- @return IRInstruction
	local function map_binop_values(original, ctor, register_id, lvalue, rvalue, is_dynamic, map)
		local new_lvalue = map(lvalue)
		local new_rvalue = map(rvalue)
		if new_lvalue == lvalue and new_rvalue == rvalue then
			return original
		else
			return ctor(register_id, new_lvalue, new_rvalue, is_dynamic)
		end
	end

	--- @param block IRBlock
	--- @param map fun(IRInstruction): IRInstruction
	--- @return IRBlock
	function IR.map_instructions(block, map)
		local new_instructions = {}
		local changed = false
		for i, instruction in ipairs(block.instructions) do
			local new_instruction = map(instruction)

			if new_instruction.instruction_kind == "if" then
				local if_true_block = new_instruction.if_true_block
				local if_false_block = new_instruction.if_false_block
				local new_if_true_block = IR.map_instructions(if_true_block, map)
				local new_if_false_block = IR.map_instructions(if_false_block, map)

				if new_if_true_block ~= if_true_block or new_if_false_block ~= if_false_block then
					new_instruction = IR.IF(new_instruction.if_condition, new_if_true_block, new_if_false_block)
				end
			elseif new_instruction.instruction_kind == "loop" then
				local loop_block = new_instruction.loop_block
				local new_loop_block = IR.map_instructions(loop_block, map)

				if new_loop_block ~= loop_block then
					new_instruction = IR.LOOP(new_loop_block)
				end
			end

			changed = changed or new_instruction ~= instruction
			new_instructions[i] = new_instruction
		end
		return changed and new_instructions or block
	end

	--- @param instruction IRInstruction
	--- @param map fun(IRValue): IRValue
	--- @return IRInstruction
	function IR.map_values(instruction, map)
		if instruction.instruction_kind == "load" then
			return instruction
		elseif instruction.instruction_kind == "store" then
			local new_store_value = map(instruction.store_value)
			if new_store_value == instruction.store_value then
				return instruction
			else
				return IR.STORE(instruction.store_variable_name, new_store_value)
			end
		elseif instruction.instruction_kind == "param" then
			return instruction
		elseif instruction.instruction_kind == "copy" then
			local new_copy_value = map(instruction.copy_value)
			if new_copy_value == instruction.copy_value then
				return instruction
			else
				return IR.COPY(instruction.register_id, new_copy_value)
			end
		elseif instruction.instruction_kind == "get" then
			local new_index = map(instruction.get_index)
			if new_index == instruction.get_index then
				return instruction
			else
				return IR.GET(instruction.register_id, instruction.get_subject, new_index)
			end
		elseif instruction.instruction_kind == "set" then
			local new_index = map(instruction.set_index)
			local new_value = map(instruction.set_value)
			if new_index == instruction.set_index and new_value == instruction.set_value then
				return instruction
			else
				return IR.SET(instruction.set_subject, new_index, new_value)
			end
		elseif instruction.instruction_kind == "call" then
			local changed = false
			local new_parameters = {}
			for i, parameter in ipairs(instruction.call_parameters) do
				local new_parameter = map(parameter)
				changed = changed or new_parameter ~= parameter
				new_parameters[i] = new_parameter
			end
			if changed then
				return IR.CALL(instruction.register_id, instruction.call_fn_name, new_parameters, instruction.call_is_pure)
			else
				return instruction
			end
		elseif instruction.instruction_kind == "add" then
			return map_binop_values(instruction, IR.ADD, instruction.register_id, instruction.add_left, instruction.add_rvalue, instruction.is_dynamic, map)
		elseif instruction.instruction_kind == "sub" then
			return map_binop_values(instruction, IR.SUB, instruction.register_id, instruction.sub_left, instruction.sub_rvalue, instruction.is_dynamic, map)
		elseif instruction.instruction_kind == "mul" then
			return map_binop_values(instruction, IR.MUL, instruction.register_id, instruction.mul_left, instruction.mul_rvalue, instruction.is_dynamic, map)
		elseif instruction.instruction_kind == "div" then
			return map_binop_values(instruction, IR.DIV, instruction.register_id, instruction.div_left, instruction.div_rvalue, instruction.is_dynamic, map)
		elseif instruction.instruction_kind == "mod" then
			return map_binop_values(instruction, IR.MOD, instruction.register_id, instruction.mod_left, instruction.mod_rvalue, instruction.is_dynamic, map)
		elseif instruction.instruction_kind == "exp" then
			return map_binop_values(instruction, IR.EXP, instruction.register_id, instruction.exp_left, instruction.exp_rvalue, instruction.is_dynamic, map)
		elseif instruction.instruction_kind == "cat" then
			return map_binop_values(instruction, IR.CAT, instruction.register_id, instruction.cat_left, instruction.cat_rvalue, instruction.is_dynamic, map)
		elseif instruction.instruction_kind == "eq" then
			return map_binop_values(instruction, IR.EQ, instruction.register_id, instruction.eq_left, instruction.eq_rvalue, instruction.is_dynamic, map)
		elseif instruction.instruction_kind == "lt" then
			return map_binop_values(instruction, IR.LT, instruction.register_id, instruction.lt_left, instruction.lt_rvalue, instruction.is_dynamic, map)
		elseif instruction.instruction_kind == "lte" then
			return map_binop_values(instruction, IR.LTE, instruction.register_id, instruction.lte_left, instruction.lte_rvalue, instruction.is_dynamic, map)
		elseif instruction.instruction_kind == "unm" then
			local new_rvalue = map(instruction.unm_rvalue)
			if new_rvalue == instruction.unm_rvalue then
				return instruction
			else
				return IR.UNM(instruction.register_id, new_rvalue, instruction.is_dynamic)
			end
		elseif instruction.instruction_kind == "not" then
			local new_rvalue = map(instruction.not_rvalue)
			if new_rvalue == instruction.not_rvalue then
				return instruction
			else
				return IR.NOT(instruction.register_id, new_rvalue)
			end
		elseif instruction.instruction_kind == "len" then
			return instruction
		elseif instruction.instruction_kind == "if" then
			local new_condition = map(instruction.if_condition)
			if new_condition == instruction.if_condition then
				return instruction
			else
				return IR.IF(new_condition, instruction.if_true, instruction.if_false)
			end
		elseif instruction.instruction_kind == "loop" then
			return instruction
		elseif instruction.instruction_kind == "break" then
			return instruction
		else
			error("unhandled instruction kind: " .. tostring(instruction.instruction_kind))
		end
	end

	----------------------------------------------------------------------------

	--- @param name string
	--- @param register_id IRRegisterId
	--- @param lvalue IRValue
	--- @param op string
	--- @param rvalue IRValue
	--- @param is_dynamic boolean
	local function fmt_binop(name, register_id, lvalue, op, rvalue, is_dynamic)
		local dynamicness = is_dynamic and " (dynamic)" or ""
		return string.format("%s R(%d) := %s %s %s%s", name, register_id, IR.value_to_string(lvalue), op, IR.value_to_string(rvalue), dynamicness)
	end

	--- @param name string
	--- @param register_id IRRegisterId
	--- @param op string
	--- @param rvalue IRValue
	--- @param is_dynamic boolean
	local function fmt_unop(name, register_id, op, rvalue, is_dynamic)
		local dynamicness = is_dynamic and " (dynamic)" or ""
		return string.format("%s R(%d) := %s%s%s", name, register_id, op, IR.value_to_string(rvalue), dynamicness)
	end

	--- @param block IRBlock
	--- @param indent? string
	--- @return string
	function IR.block_to_string(block, indent)
		indent = indent or ""
		local s = {}
		for i, instruction in ipairs(block.instructions) do
			s[i] = "\n" .. indent .. IR.instruction_to_string(instruction, indent)
		end
		return table.concat(s)
	end

	--- @param instruction IRInstruction
	--- @param indent? string
	--- @return string
	function IR.instruction_to_string(instruction, indent)
		indent = indent or ""
		if instruction.instruction_kind == "load" then
			return string.format("LOAD  R(%d) := %s", instruction.register_id, IR.variable_to_string(instruction.load_variable_name))
		elseif instruction.instruction_kind == "store" then
			return string.format("STORE %s := %s", IR.variable_to_string(instruction.store_variable_name), IR.value_to_string(instruction.store_value))
		elseif instruction.instruction_kind == "param" then
			return string.format("PARAM R(%d) := param %s", instruction.register_id, instruction.param_index)
		elseif instruction.instruction_kind == "copy" then
			return string.format("COPY  R(%d) := %s", instruction.register_id, IR.value_to_string(instruction.copy_value))
		elseif instruction.instruction_kind == "get" then
			return string.format("GET   R(%d) := R(%d)[%s]", instruction.register_id, instruction.get_subject, IR.value_to_string(instruction.get_index))
		elseif instruction.instruction_kind == "set" then
			return string.format("SET   R(%d)[%s] := %s", instruction.set_subject, IR.value_to_string(instruction.set_index), IR.value_to_string(instruction.set_value))
		elseif instruction.instruction_kind == "call" then
			local parameters = {}
			for i, parameter in ipairs(instruction.call_parameters) do
				parameters[i] = IR.value_to_string(parameter)
			end
			local purity = instruction.call_is_pure and " (pure)" or ""
			return string.format("CALL  R(%d) := %s(%s)%s", instruction.register_id, instruction.call_fn_name, table.concat(parameters, ", "), purity)
		elseif instruction.instruction_kind == "add" then
			return fmt_binop("ADD  ", instruction.register_id, instruction.add_lvalue, "+", instruction.add_rvalue, instruction.is_dynamic)
		elseif instruction.instruction_kind == "sub" then
			return fmt_binop("SUB  ", instruction.register_id, instruction.sub_lvalue, "-", instruction.sub_rvalue, instruction.is_dynamic)
		elseif instruction.instruction_kind == "mul" then
			return fmt_binop("MUL  ", instruction.register_id, instruction.mul_lvalue, "*", instruction.mul_rvalue, instruction.is_dynamic)
		elseif instruction.instruction_kind == "div" then
			return fmt_binop("DIV  ", instruction.register_id, instruction.div_lvalue, "/", instruction.div_rvalue, instruction.is_dynamic)
		elseif instruction.instruction_kind == "mod" then
			return fmt_binop("MOD  ", instruction.register_id, instruction.mod_lvalue, "%", instruction.mod_rvalue, instruction.is_dynamic)
		elseif instruction.instruction_kind == "exp" then
			return fmt_binop("EXP  ", instruction.register_id, instruction.exp_lvalue, "^", instruction.exp_rvalue, instruction.is_dynamic)
		elseif instruction.instruction_kind == "cat" then
			return fmt_binop("CAT  ", instruction.register_id, instruction.cat_lvalue, "..", instruction.cat_rvalue, instruction.is_dynamic)
		elseif instruction.instruction_kind == "eq" then
			return fmt_binop("EQ   ", instruction.register_id, instruction.eq_lvalue, "==", instruction.eq_rvalue, instruction.is_dynamic)
		elseif instruction.instruction_kind == "lt" then
			return fmt_binop("LT   ", instruction.register_id, instruction.lt_lvalue, "<", instruction.lt_rvalue, instruction.is_dynamic)
		elseif instruction.instruction_kind == "lte" then
			return fmt_binop("LTE  ", instruction.register_id, instruction.lte_lvalue, "<=", instruction.lte_rvalue, instruction.is_dynamic)
		elseif instruction.instruction_kind == "unm" then
			return fmt_unop("UNM  ", instruction.register_id, "-", instruction.unm_value, instruction.is_dynamic)
		elseif instruction.instruction_kind == "not" then
			return fmt_unop("NOT  ", instruction.register_id, "not ", instruction.not_value, instruction.is_dynamic)
		elseif instruction.instruction_kind == "len" then
			return fmt_unop("LEN  ", instruction.register_id, "#", instruction.len_value, instruction.is_dynamic)
		elseif instruction.instruction_kind == "if" then
			local if_true = IR.block_to_string(instruction.if_true_block, indent .. "  ")
			local if_false = IR.block_to_string(instruction.if_false_block, indent .. "  ")
			return "IF " .. IR.value_to_string(instruction.if_condition) .. " THEN" .. if_true .. "\nELSE" .. if_false .. "\nEND"
		elseif instruction.instruction_kind == "loop" then
			return "LOOP" .. IR.block_to_string(instruction.loop_block, indent .. "  ") .. "\nEND"
		elseif instruction.instruction_kind == "break" then
			return "BREAK"
		else
			error("unknown instruction kind: " .. tostring(instruction.instruction_kind))
		end
	end
end

----------------------------------------------------------------------------------------------------

do -- functions
	--- @class IRFunctionDef
	--- @field body IRBlock
	--- @field return_value IRValue
end

----------------------------------------------------------------------------------------------------

do -- builder/inlining contexts
	--- @class IRBuilderContext
	--- @field private used_name_lookup { [string]: true }
	--- @field private used_register_id_lookup { [integer]: true }
	--- @field private next_variable_tag_lookup { [string]: integer }
	--- @field private next_register_id integer
	IR.BuilderContext = {}

	--- @return IRBuilderContext
	function IR.BuilderContext.new()
		local ctx = {
			used_name_lookup = {},
			used_register_id_lookup = {},
			next_register_id = 0,
		}

		setmetatable(ctx, IR.BuilderContext)

		return ctx
	end

	--- @param variable IRVariable
	function IR.BuilderContext:reserve_variable(variable)
		self.used_name_lookup[IR.variable_to_string(variable)] = true
	end

	--- @param register_id IRRegisterId
	function IR.BuilderContext:reserve_register(register_id)
		self.used_register_id_lookup[register_id] = true
	end

	--- @param variable_name string
	--- @return IRVariableTag
	function IR.BuilderContext:tag_new_variable(variable_name)
		local tag = self.next_variable_tag_lookup[variable_name] or 0
		while self.used_name_lookup[IR.variable2_to_string(variable_name, tag)] do
			tag = tag + 1
		end
		self.next_variable_tag_lookup[variable_name] = tag + 1
		return tag
	end

	--- @return IRRegisterId
	function IR.BuilderContext:new_register_id()
		local register_id = self.next_register_id
		while self.used_register_id_lookup[register_id] do
			register_id = register_id + 1
		end
		self.next_register_id = register_id + 1
		return register_id
	end

	----------------------------------------------------------------------------

	--- @param ctx IRInliningContext
	--- @param ctor fun(IRRegisterId, IRValue, IRValue, boolean): IRInstruction
	--- @param register_id IRRegisterId
	--- @param lvalue IRValue
	--- @param rvalue IRValue
	--- @param is_dynamic boolean
	--- @return IRInstruction
	local function transform_binop(ctx, ctor, register_id, lvalue, rvalue, is_dynamic)
		local new_register_id = ctx:transform_register(register_id)
		local new_lvalue = ctx:transform_value(lvalue)
		local new_rvalue = ctx:transform_value(rvalue)
		return ctor(new_register_id, new_lvalue, new_rvalue, is_dynamic)
	end

	--- @class IRInliningContext
	--- @field private builder IRBuilderContext
	--- @field private parameters IRValue[]
	--- @field private register_map { [IRRegisterId]: IRRegisterId }
	--- @field private variable_map { [string]: IRVariable }
	IR.InliningContext = {}

	--- @param builder IRBuilderContext
	--- @return IRInliningContext
	function IR.InliningContext.new(builder, parameters)
		local ctx = {
			builder = builder,
			parameters = parameters,
		}

		setmetatable(ctx, IR.InliningContext)

		return ctx
	end

	--- @param variable IRVariable
	--- @return IRVariable
	function IR.InliningContext:transform_variable(variable)
		local lookup = IR.variable_to_string(variable)
		local mapped = self.variable_map[lookup]
		if not mapped then
			local mapped_tag = self.builder:tag_new_variable(variable.variable_name)
			mapped = IR.variable(variable.variable_name, mapped_tag)
			self.variable_map[lookup] = mapped
		end
		return mapped
	end

	--- @param register_id IRRegisterId
	--- @return IRRegisterId
	function IR.InliningContext:transform_register(register_id)
		local mapped = self.register_map[register_id]
		if not mapped then
			mapped = self.builder:new_register_id()
			self.register_map[register_id] = mapped
		end
		return mapped
	end

	--- @param value IRValue
	--- @return IRValue
	function IR.InliningContext:transform_value(value)
		if value.value_kind == "constant" then
			return value
		else
			return IR.register(self:transform_register(value.register_id))
		end
	end

	--- @param instruction IRInstruction
	--- @return IRInstruction
	function IR.InliningContext:transform_instruction(instruction)
		if instruction.instruction_kind == "load" then
			local register_id = self:transform_register(instruction.register_id)
			local variable = self:transform_variable(instruction.load_variable)
			return IR.LOAD(register_id, variable)
		elseif instruction.instruction_kind == "store" then
			local variable = self:transform_variable(instruction.store_variable)
			local new_store_value = self:transform_value(instruction.store_value)
			return IR.STORE(variable, new_store_value)
		elseif instruction.instruction_kind == "param" then
			local register_id = self:transform_register(instruction.register_id)
			return IR.COPY(register_id, self.parameters[instruction.param_index])
		elseif instruction.instruction_kind == "copy" then
			local register_id = self:transform_register(instruction.register_id)
			local new_copy_value = self:transform_value(instruction.copy_value)
			return IR.COPY(register_id, new_copy_value)
		elseif instruction.instruction_kind == "get" then
			local register_id = self:transform_register(instruction.register_id)
			local get_subject = self:transform_register(instruction.get_subject)
			local new_index = self:transform_value(instruction.get_index)
			return IR.GET(register_id, get_subject, new_index)
		elseif instruction.instruction_kind == "set" then
			local set_subject = self:transform_register(instruction.set_subject)
			local new_index = self:transform_value(instruction.set_index)
			local new_value = self:transform_value(instruction.set_value)
			return IR.SET(set_subject, new_index, new_value)
		elseif instruction.instruction_kind == "call" then
			local register_id = self:transform_register(instruction.register_id)
			local new_parameters = {}
			for i, parameter in ipairs(instruction.call_parameters) do
				new_parameters[i] = self:transform_value(parameter)
			end
			return IR.CALL(register_id, instruction.call_fn_name, new_parameters, instruction.call_is_pure)
		elseif instruction.instruction_kind == "add" then
			return transform_binop(self, IR.ADD, instruction.register_id, instruction.add_lvalue, instruction.add_right, instruction.is_dynamic)
		elseif instruction.instruction_kind == "sub" then
			return transform_binop(self, IR.SUB, instruction.register_id, instruction.sub_lvalue, instruction.sub_right, instruction.is_dynamic)
		elseif instruction.instruction_kind == "mul" then
			return transform_binop(self, IR.MUL, instruction.register_id, instruction.mul_lvalue, instruction.mul_right, instruction.is_dynamic)
		elseif instruction.instruction_kind == "div" then
			return transform_binop(self, IR.DIV, instruction.register_id, instruction.div_lvalue, instruction.div_right, instruction.is_dynamic)
		elseif instruction.instruction_kind == "mod" then
			return transform_binop(self, IR.MOD, instruction.register_id, instruction.mod_lvalue, instruction.mod_right, instruction.is_dynamic)
		elseif instruction.instruction_kind == "exp" then
			return transform_binop(self, IR.EXP, instruction.register_id, instruction.exp_lvalue, instruction.exp_right, instruction.is_dynamic)
		elseif instruction.instruction_kind == "cat" then
			return transform_binop(self, IR.CAT, instruction.register_id, instruction.cat_lvalue, instruction.cat_right, instruction.is_dynamic)
		elseif instruction.instruction_kind == "eq" then
			return transform_binop(self, IR.EQ, instruction.register_id, instruction.eq_lvalue, instruction.eq_right, instruction.is_dynamic)
		elseif instruction.instruction_kind == "lt" then
			return transform_binop(self, IR.LT, instruction.register_id, instruction.lt_lvalue, instruction.lt_right, instruction.is_dynamic)
		elseif instruction.instruction_kind == "lte" then
			return transform_binop(self, IR.LTE, instruction.register_id, instruction.lte_lvalue, instruction.lte_right, instruction.is_dynamic)
		elseif instruction.instruction_kind == "unm" then
			local register_id = self:transform_register(instruction.register_id)
			local new_rvalue = self:transform_value(instruction.unm_rvalue)
			return IR.UNM(register_id, new_rvalue, instruction.is_dynamic)
		elseif instruction.instruction_kind == "not" then
			local register_id = self:transform_register(instruction.register_id)
			local new_rvalue = self:transform_value(instruction.not_rvalue)
			return IR.NOT(register_id, new_rvalue)
		elseif instruction.instruction_kind == "len" then
			local register_id = self:transform_register(instruction.register_id)
			local subject = self:transform_register(instruction.len_subject)
			return IR.LEN(register_id, subject)
		elseif instruction.instruction_kind == "if" then
			local new_condition = self:transform_value(instruction.if_condition)
			local if_true = self:transform_block(instruction.if_true)
			local if_false = self:transform_block(instruction.if_false)
			return IR.IF(new_condition, if_true, if_false)
		elseif instruction.instruction_kind == "loop" then
			local new_body = self:transform_block(instruction.loop_body)
			return IR.LOOP(new_body)
		elseif instruction.instruction_kind == "break" then
			return instruction
		else
			error("unhandled instruction kind: " .. tostring(instruction.instruction_kind))
		end
	end

	--- @param block IRBlock
	--- @return IRBlock
	function IR.InliningContext:transform_block(block)
		local instructions = {}
		for i, instruction in ipairs(block) do
			instructions[i] = self:transform_instruction(instruction)
		end
		return instructions
	end
end

----------------------------------------------------------------------------------------------------

-- Description of IR properties
--[[
Staleness: (inverse fresh) property indicating that evaluating the same instruction would no longer produce the same result
	LOAD becomes stale when there is a STORE to the same variable
	PARAM is never stale
	COPY is never stale
	GET_INDEX becomes stale when the underlying register is modified (accounting for aliases, aware of constant indices, aware of impure function calls)
	CALL is stale based on the purity of the function
	ADD .. UNM is stale based on whether its operands are dynamic
	NOT is never stale
	LEN becomes stale when the underlying register is modified (accounting for aliases, aware of constant indices, aware of impure function calls)
	STORE is never stale
	SET_INDEX is never stale
	IF has the staleness of the union of the instructions of its branches
	LOOP has the staleness of the instructions of its body, and its instructions' staleness are looped

Reordering:
	All instructions can be deferred until they become stale or their first use, with the following additional constraints:
	* STORE can be deferred until there is a STORE/LOAD to/from the same variable
	* SET_INDEX can be deferred until the underlying register is modified (accounting for aliases, aware of constant indices, aware of impure function calls) or until there is a matching GET_INDEX
	* IF/LOOP as before

CSE:
	An instruction writing to regA can be replaced with a move from regB if regB is fresh and all other instruction arguments are equal

LICM:
	Harder, TODO

Alias removal:
	A val referring to a COPY register can be replaced with the COPY's source val
	A LOAD instruction can be replaced with a COPY if the last STORE is singular and known - different to CSE, this replaces the first LOAD too!

Dead code elimination:
	A register assignment which is never used can be removed if not an impure function call
	An IF with two empty branches can be removed
	A LOOP with transitively only IFs and BREAKs can be removed

Dead store elimination:
	A STORE without a matching LOAD can be removed
	A SET_INDEX without a matching GET_INDEX can be removed if the subject has not escaped (e.g. relevant for parameters)

Table flattening:
	If all uses of a register are GET_INDEX and SET_INDEX subjects with constant keys, a new variable can be generated (next to register assignment) for each constant key and all GET_INDEX/SET_INDEX instructions can be replaced with LOAD/STORE to/from the new variables

Constant folding:
	An instruction can be replaced with a constant value (COPY) if all its operands are constants

Reduction:
	Various equalities may be used to simplify instructions if operands are not dynamic, e.g. x + 0 = x, x * 1 = x, x ^ 0 = 1, x .. "" = x, not not x = x, etc.

Branch factoring:
	Common instructions from two branches of an IF can be moved before the IF
	Method:
		* Compute hashes of instructions
		* Find shared hashes between branches
		* Defer non-common instructions from each branch as much as possible
		* Order instructions consistently based on hash
		* While first instruction hashes of each branch match, hoist the instruction into a new register and replace branches with COPYs

Loop unrolling:
	If a LOOP has a known small number of iterations, replace it with that many copies of the loop body.
]]

----------------------------------------------------------------------------------------------------

return IR
