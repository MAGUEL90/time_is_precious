shader_type canvas_item;

uniform float radius_pixels : hint_range(32.0, 240.0, 1.0) = 96.0;
uniform float softness_pixels : hint_range(0.0, 96.0, 1.0) = 24.0;
uniform float darkness : hint_range(0.0, 1.0, 0.01) = 1.0;

void fragment() {
	// Called for every pixel the material is visible on.
	vec2 pixel_offset = (UV - vec2(0.5)) / SCREEN_PIXEL_SIZE;
	float distance_from_center = length(pixel_offset);
	float mask = smoothstep(
		radius_pixels - softness_pixels,
		radius_pixels,
		distance_from_center
	);

	COLOR = vec4(0.0, 0.0, 0.0, mask * darkness);
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
