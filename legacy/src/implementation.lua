
return {
	create_texture_sampler = function(texture_uniform, width_uniform, height_uniform)
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
}
