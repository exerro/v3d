
import * as v3d from '../gen/v3d';

const framebuffer = v3d.create_framebuffer_subpixel(v3d.COLOUR_DEPTH_FORMAT, 51, 19)
var transform = v3d.camera(0, 0, 2)
const pipeline = v3d.create_pipeline({
	layout: v3d.DEBUG_CUBE_LAYOUT,
	colour_attribute: 'colour',
})

const geometry = v3d.create_debug_cube().build()

while (true) {
	transform = transform.combine(v3d.rotate(0, 0.05, 0))

	framebuffer.clear('colour', 1)
	framebuffer.clear('depth')
	pipeline.render_geometry(geometry, framebuffer, transform)
	framebuffer.blit_term_subpixel({})
}
