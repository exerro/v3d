
-- Import the library
local v3d = require '/v3d'

-- Create objects using default settings
local framebuffer = v3d.create_framebuffer_subpixel(term.getSize())
local geometry = v3d.create_geometry(v3d.GEOMETRY_COLOUR)
local camera = v3d.create_camera()
local pipeline = v3d.create_pipeline()

-- Add a red triangle
geometry:add_colour_triangle(0, 0.8, -2, -0.9, -0.8, -2, 0.9, -0.8, -2, colours.red)

-- Clear the framebuffer to light blue
framebuffer:clear(colours.lightBlue)

-- Draw the geometry to the framebuffer
pipeline:render_geometry({ geometry }, framebuffer, camera)

-- Draw the framebuffer to the screen
framebuffer:blit_subpixel(term)
