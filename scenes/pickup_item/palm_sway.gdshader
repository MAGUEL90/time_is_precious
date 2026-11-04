shader_type canvas_item;

uniform float sway_pixels = 0.0;

void vertex() {
	// The base stays rooted while the existing canopy moves in whole pixels.
	VERTEX.x += sway_pixels * (1.0 - UV.y);
}
