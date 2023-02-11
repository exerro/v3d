
-- Import the library
local v3d = require '/v3d'

-- Create objects using default settings
local framebuffer = v3d.create_framebuffer_subpixel(term.getSize())
local geometry = v3d.create_geometry_builder(v3d.DEFAULT_LAYOUT)
	:set_data('position', { 0, 0.8, -2, -0.9, -0.8, -2, 0.9, -0.8, -2 })
	:set_data('colour', { colours.red })
	:build()
local camera = v3d.create_camera()
local pipeline = v3d.create_pipeline {
	layout = v3d.DEFAULT_LAYOUT,
	colour_attribute = 'colour',
}

-- Clear the framebuffer to light blue
framebuffer:clear(colours.lightBlue)

-- Draw the geometry to the framebuffer
pipeline:render_geometry(geometry, framebuffer, camera)

-- Draw the framebuffer to the screen
framebuffer:blit_subpixel(term)
