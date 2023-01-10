package me.exerro.raster_visuals

import me.exerro.colour.ColourPalette
import me.exerro.colour.RGBA

const val PIXELS_PER_TILE = 32
const val TILES_X = 50
const val TILES_Y = 30
const val SCREEN_TILE_X0 = 4
const val SCREEN_TILE_X1 = 45
const val SCREEN_TILE_Y0 = 3
const val SCREEN_TILE_Y1 = 26
const val SCREEN_WIDTH = SCREEN_TILE_X1 - SCREEN_TILE_X0 + 1
const val SCREEN_HEIGHT = SCREEN_TILE_Y1 - SCREEN_TILE_Y0 + 1
const val WINDOW_WIDTH = PIXELS_PER_TILE * TILES_X
const val WINDOW_HEIGHT = PIXELS_PER_TILE * TILES_Y

val WINDOW_BACKGROUND_COLOUR = RGBA(0.05f, 0.07f, 0.09f)
val SCREEN_BACKGROUND_COLOUR_INACTIVE = RGBA(0.12f, 0.14f, 0.16f)
val SCREEN_BACKGROUND_COLOUR_ACTIVE = ColourPalette.purple
