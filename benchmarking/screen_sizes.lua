
--- @class ScreenSize
--- @field name string
--- @field width integer
--- @field height integer

local w, h = term.getSize()

--- @type { [integer]: ScreenSize }
local screen_sizes = {
	{ name = 'Small',   width =  10, height =   5 },
	{ name = 'Turtle',  width =  39, height =  13 },
	{ name = 'Pocket',  width =  26, height =  20 },
	{ name = 'Normal',  width =  51, height =  19 },
	{ name = 'Monitor', width = 162, height =  80 },
	{ name = '540p',    width = 260, height = 120 }, -- divide by (2, 3) to account for subpixels
	{ name = 'Native',  width =   w, height =   h },
}

return screen_sizes
