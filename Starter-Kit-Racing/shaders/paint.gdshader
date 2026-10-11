shader_type spatial;

// Swaps a vehicle's body paint color for a new one, keeping its light/dark shading.
// Everything else in the color palette (windows, tires, lights) stays the same.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform vec4 original_paint : source_color;
uniform vec4 new_paint : source_color;
uniform float roughness = 1.0;
uniform float hue_tolerance = 0.06;
uniform float min_saturation = 0.35;

vec3 rgb_to_hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

void fragment() {
	vec3 color = texture(albedo_texture, UV).rgb;
	vec3 hsv = rgb_to_hsv(color);
	vec3 paint_hsv = rgb_to_hsv(original_paint.rgb);

	float hue_distance = abs(hsv.x - paint_hsv.x);
	hue_distance = min(hue_distance, 1.0 - hue_distance);

	if (hsv.y > min_saturation && hue_distance < hue_tolerance) {
		color = clamp(new_paint.rgb * (hsv.z / paint_hsv.z), 0.0, 1.0); // Keep the shading of darker/lighter paint
	}

	ALBEDO = color;
	ROUGHNESS = roughness;
}
