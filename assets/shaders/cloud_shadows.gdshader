shader_type canvas_item;

uniform float time_val = 0.0;
uniform vec2 map_size = vec2(12000.0, 10000.0);
uniform float shadow_strength : hint_range(0.0, 0.6) = 0.22;
uniform float cloud_scale : hint_range(0.0001, 0.002) = 0.0006;
uniform vec2 wind_dir = vec2(1.0, 0.35);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
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

// 3-octave FBM (reduced from 5 for performance)
float fbm3(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	float freq = 1.0;
	for (int i = 0; i < 3; i++) {
		sum += value_noise(p * freq) * amp;
		freq *= 2.1;
		amp *= 0.48;
	}
	return sum;
}

void fragment() {
	vec2 world_pos = UV * map_size;
	vec2 cloud_uv = world_pos * cloud_scale;
	vec2 drift = wind_dir * time_val * 0.012;

	float layer1 = fbm3(cloud_uv + drift);
	float layer2 = fbm3(cloud_uv * 1.7 + drift * 0.6 + vec2(43.7, 91.2));

	float cloud_val = layer1 * 0.65 + layer2 * 0.35;
	float shadow = smoothstep(0.32, 0.58, cloud_val);
	shadow *= shadow;

	float alpha = shadow * shadow_strength;
	alpha = clamp(alpha, 0.0, shadow_strength);

	COLOR = vec4(0.0, 0.0, 0.02, alpha);
}
