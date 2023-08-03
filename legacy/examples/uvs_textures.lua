
local v3d = require '/v3d'

local framebuffer = v3d.create_framebuffer_subpixel(v3d.COLOUR_DEPTH_FORMAT, term.getSize())
local pipeline = v3d.create_pipeline {
	layout = v3d.UV_LAYOUT,
	attributes = { 'uv' },
	pack_attributes = false,
	fragment_shader = v3d.create_texture_sampler(),
}
local cube = v3d.create_debug_cube():cast(v3d.UV_LAYOUT):build()

term.setPaletteColour(colours.lightGrey, 0.4, 0.3, 0.2)
term.setPaletteColour(colours.grey, 0.4, 0.33, 0.24)

local image = paintutils.loadImage 'example.nfp'
pipeline:set_uniform('u_texture', image)
pipeline:set_uniform('u_texture_width', #image[1])
pipeline:set_uniform('u_texture_height', #image)

pcall(function()
	local rotation = 0
	while true do
		rotation = rotation + 0.04
		local s = math.sin(rotation)
		local c = math.cos(rotation)
		local distance = 2
		local transform = v3d.camera(s * distance, 0, c * distance, rotation)
		framebuffer:clear('colour', colours.white)
		framebuffer:clear('depth')
		pipeline:render_geometry(cube, framebuffer, transform)
		framebuffer:blit_term_subpixel(term, 'colour')
		sleep(0.05)
	end
end)

term.setPaletteColour(colours.lightGrey, term.nativePaletteColour(colours.lightGrey))
term.setPaletteColour(colours.grey, term.nativePaletteColour(colours.grey))
