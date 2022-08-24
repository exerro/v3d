
return function(name)
	local unique = {}
	return setmetatable(unique, {
		__tostring = function() return name end,
		__concat = function(a, b)
			if a == unique then return name .. b else return a .. name end
		end
	})
end
