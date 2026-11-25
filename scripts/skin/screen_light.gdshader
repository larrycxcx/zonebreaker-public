// The skin pack's "lighting layer": blends a blurry coloured light map in overlay mode onto **the picture already drawn**.
// Drawn after the terrain and before the enemies, so the backdrop, facades, scenery and terrain are tinted and characters and bullets keep their colours (see screen_light.gd).
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform sampler2D glow : filter_linear;
// How big the light map is laid out in the world (pixels). Bigger than the view, so one screen only shows part of it.
uniform vec2 glow_size = vec2(960.0, 640.0);
// Position of the view's top-left corner in the world, and "how fast the light follows" (0 = pinned to the screen, 1 = pinned to the world), both horizontally and vertically.
uniform vec2 view_origin = vec2(0.0);
uniform float drift = 0.4;
uniform float strength = 1.0;

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// Tiled with mirroring back and forth: the light map is not seamless, and plain repetition would show the seams
vec2 mirrored(vec2 uv) {
	return 1.0 - abs(mod(uv, 2.0) - 1.0);
}

void fragment() {
	vec3 base = texture(screen_texture, SCREEN_UV).rgb;
	vec2 on_screen = world - view_origin;
	// Follows both ways: the light changes as you climb a vertical stage too. In horizontal stages the view never moves vertically (view_origin.y stays 0), so the effect is as before
	vec2 at = on_screen + view_origin * drift;
	vec3 light = texture(glow, mirrored(at / glow_size)).rgb;
	vec3 low = 2.0 * base * light;
	vec3 high = 1.0 - 2.0 * (1.0 - base) * (1.0 - light);
	vec3 lit = mix(low, high, step(0.5, base));
	COLOR = vec4(mix(base, lit, strength), 1.0);
}
