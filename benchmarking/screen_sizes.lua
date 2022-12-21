
--- @class ScreenSize
--- @field name string
--- @field width integer
--- @field height integer

local w, h = term.getSize()

--- @type { [integer]: ScreenSize }
local screen_sizes = {
	{ name = 'Native',  width =   w, height =   h },
	{ name = '540p',    width = 260, height = 120 }, -- divide by (2, 3) to account for subpixels
	{ name = 'Monitor', width = 162, height =  80 },
	{ name = 'Large',   width = 100, height =  50 },
	{ name = 'Normal',  width =  51, height =  19 },
	{ name = 'Pocket',  width =  26, height =  20 },
	{ name = 'Turtle',  width =  39, height =  13 },
	{ name = 'Small',   width =  10, height =   5 },
}

return screen_sizes
