shader_type canvas_item;
render_mode unshaded;

// Printed-ink look for a 2D game, after Ape Out: a cool blue-gray grade, fine
// film grain, blotchy ink density and slightly ragged shape edges. The grain
// lives on the screen; the ink blotches and edge wobble are anchored to the
// world (grain_overlay.gd feeds in the camera) so they don't swim when the
// camera moves.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;

// Set every frame by grain_overlay.gd.
uniform vec2 view_size = vec2(1280.0, 720.0);
uniform vec2 world_offset = vec2(0.0);
uniform float world_per_px = 1.0;

group_uniforms color;
// Dark -> light tint the image is graded toward.
uniform sampler2D palette : filter_linear, repeat_disable;
uniform float grade_amount : hint_range(0.0, 1.0) = 0.55;
// Pixels more saturated than this keep their own color (lasers, objectives).
uniform float accent_threshold : hint_range(0.0, 1.0) = 0.45;
uniform float accent_softness : hint_range(0.01, 0.5) = 0.1;

group_uniforms ink;
// Uneven ink density, like a screen print: strength and blotch size (world px).
uniform float mottle_strength : hint_range(0.0, 0.5) = 0.05;
uniform float mottle_scale : hint_range(8.0, 512.0) = 35.0;
// How far shape edges wobble (world px) and how tight the wobble is.
uniform float edge_roughness : hint_range(0.0, 8.0) = 2.0;
uniform float edge_detail : hint_range(1.0, 32.0) = 5.0;

group_uniforms grain;
uniform float grain_amount : hint_range(0.0, 0.3) = 0.06;
// Grain size in pixels of a 720p screen (scales with resolution).
uniform float grain_size : hint_range(0.5, 4.0) = 1.2;
// 0 = gray grain, 1 = colored specks.
uniform float grain_chroma : hint_range(0.0, 1.0) = 0.3;
// How many times per second the grain re-rolls. 0 freezes it.
uniform float grain_fps : hint_range(0.0, 60.0) = 12.0;

group_uniforms vignette;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.25;
uniform float vignette_radius : hint_range(0.2, 2.0) = 1.3;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += value_noise(p) * amp;
		p = p * 2.03 + 17.1;
		amp *= 0.5;
	}
	return sum / 0.9375;
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec2 world = world_offset + SCREEN_UV * view_size * world_per_px;
	vec2 world_to_uv = 1.0 / (view_size * world_per_px);

	// Ragged edges: read the screen from a slightly wobbled, world-anchored spot.
	vec2 e = world / edge_detail;
	vec2 wobble = vec2(value_noise(e), value_noise(e + 41.3))
		+ 0.5 * vec2(value_noise(e * 2.7 + 7.1), value_noise(e * 2.7 + 23.9));
	wobble = wobble / 1.5 * 2.0 - 1.0;
	vec3 src = texture(screen_texture, SCREEN_UV + wobble * edge_roughness * world_to_uv).rgb;

	// Grade toward the palette, but let strongly saturated accents through.
	vec3 tinted = texture(palette, vec2(clamp(luma(src), 0.0, 1.0), 0.5)).rgb;
	vec3 col = mix(src, tinted, grade_amount);
	float sat = max(src.r, max(src.g, src.b)) - min(src.r, min(src.g, src.b));
	col = mix(col, src, smoothstep(accent_threshold, accent_threshold + accent_softness, sat));

	// Ink mottle.
	float m = smoothstep(0.25, 0.75, fbm(world / mottle_scale));
	col *= 1.0 + (m - 0.5) * 2.0 * mottle_strength;

	// Film grain, strongest in the midtones.
	vec2 px = SCREEN_UV * vec2(720.0 * view_size.x / view_size.y, 720.0);
	float seed = grain_fps > 0.0 ? mod(floor(TIME * grain_fps), 256.0) : 0.0;
	vec2 offset = vec2(seed * 37.0, seed * 91.0);
	float mono = mix(value_noise(px / grain_size + offset), hash(floor(FRAGCOORD.xy) + offset), 0.5) - 0.5;
	vec3 chroma = vec3(
		hash(FRAGCOORD.xy + offset),
		hash(FRAGCOORD.xy + offset + 19.19),
		hash(FRAGCOORD.xy + offset + 47.47)) - 0.5;
	vec3 g = mix(vec3(mono), chroma, grain_chroma);
	float l = luma(col);
	col += g * grain_amount * 2.0 * (0.35 + 2.6 * l * (1.0 - l));

	vec2 c = (SCREEN_UV - 0.5) * vec2(view_size.x / view_size.y, 1.0) * 2.0;
	col *= mix(1.0, 1.0 - smoothstep(vignette_radius * 0.4, vignette_radius, length(c)), vignette_strength);

	COLOR = vec4(col, 1.0);
}
