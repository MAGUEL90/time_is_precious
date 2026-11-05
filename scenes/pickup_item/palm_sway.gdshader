shader_type canvas_item;

uniform float sway_pixels = 0.0;
varying vec4 sprite_tint;

void vertex() {
	sprite_tint = COLOR;
	// Make one transparent pixel of room on either side, so a moving leaf at
	// the texture edge is not cut off by the original sprite quad.
	if (UV.x < 0.5) {
		VERTEX.x -= 1.0;
		UV.x -= TEXTURE_PIXEL_SIZE.x;
	} else {
		VERTEX.x += 1.0;
		UV.x += TEXTURE_PIXEL_SIZE.x;
	}
}

void fragment() {
	// A quad has only four vertices: move the sampled canopy pixels instead
	// so the lower half of the trunk remains absolutely fixed.
	float canopy = 1.0 - smoothstep(0.36, 0.50, UV.y);
	vec2 source_uv = UV - vec2(sway_pixels * TEXTURE_PIXEL_SIZE.x * canopy, 0.0);
	if (source_uv.x < 0.0 || source_uv.x > 1.0) {
		COLOR = vec4(0.0);
	} else {
		COLOR = sprite_tint * texture(TEXTURE, source_uv);
	}
}
