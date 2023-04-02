
local a = require 'v3dtest'

print(a.vsl.rewrite(
	{
		v3d_my_function = function(context, local_context, append_line, params)
			if not local_context.flag then
				append_line('first_invocation!')
				local_context.flag = true
			end
			append_line(params[1] .. ' ' .. context.variable)
		end,
	},
	{
		variable = 'context_variable'
	},
	[[
		v3d_my_function('abc')
		v3d_my_function('def')
		v3d_my_function('hij')
	]]
))
