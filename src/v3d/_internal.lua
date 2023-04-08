
local v3d_internal = {}

--- @return any
function v3d_internal.contextual_error(message, context)
	local traceback
	pcall(function()
		traceback = debug and debug.traceback and debug.traceback()
	end)
	local error_message = tostring(message == nil and '' or message)
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

--- @return any
function v3d_internal.internal_error(message, context)
	return v3d_internal.contextual_error('V3D INTERNAL ERROR: ' .. tostring(message == nil and '' or message), context)
end

return v3d_internal
