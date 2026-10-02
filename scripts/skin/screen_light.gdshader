// 素材包的「光照层」：把一张模糊的彩色光斑按 overlay 方式混到**已经画好的画面**上。
// 画在地形之后、敌人之前，所以背景、楼面、装饰、地形被染色，人和子弹保持原色（见 screen_light.gd）。
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform sampler2D glow : filter_linear;
// 光斑贴图在世界里铺多大（像素）。比画面大，所以一屏只看得到其中一块。
uniform vec2 glow_size = vec2(960.0, 640.0);
// 画面左上角在世界里的位置，和「光斑跟着走多快」（0 = 钉在屏幕上，1 = 钉在世界上）。
uniform vec2 view_origin = vec2(0.0);
uniform float drift = 0.4;
uniform float strength = 1.0;

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// 来回镜像着铺：光斑贴图不是无缝的，直接重复会看到接缝
vec2 mirrored(vec2 uv) {
	return 1.0 - abs(mod(uv, 2.0) - 1.0);
}

void fragment() {
	vec3 base = texture(screen_texture, SCREEN_UV).rgb;
	vec2 on_screen = world - view_origin;
	vec2 at = on_screen + vec2(view_origin.x * drift, 0.0);
	vec3 light = texture(glow, mirrored(at / glow_size)).rgb;
	vec3 low = 2.0 * base * light;
	vec3 high = 1.0 - 2.0 * (1.0 - base) * (1.0 - light);
	vec3 lit = mix(low, high, step(0.5, base));
	COLOR = vec4(mix(base, lit, strength), 1.0);
}
