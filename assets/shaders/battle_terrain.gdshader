shader_type canvas_item;

uniform sampler2D terrain_data : filter_nearest;
uniform vec2 grid_size; // terrain_grid_w, terrain_grid_h
uniform vec2 field_size; // FIELD_WIDTH, FIELD_HEIGHT
uniform float time;

// Terrain type colors (must match TERRAIN_COLORS in battle_renderer_v3.gd)
vec3 get_terrain_color(float type_val) {
	int t = int(type_val * 255.0 + 0.5);
	if (t == 1) return vec3(0.1, 0.2, 0.1);       // FOREST
	if (t == 2) return vec3(0.22, 0.2, 0.2);       // ROCK
	if (t == 3) return vec3(0.08, 0.12, 0.25);     // WATER
	if (t == 4) return vec3(0.22, 0.2, 0.13);      // SAND
	if (t == 5) return vec3(0.14, 0.12, 0.08);     // MUD
	if (t == 6) return vec3(0.18, 0.22, 0.28);     // ICE
	if (t == 7) return vec3(0.2, 0.1, 0.25);       // CRYSTAL
	if (t == 8) return vec3(0.13, 0.15, 0.11);     // BRUSH
	return vec3(0.12, 0.11, 0.16);                  // OPEN (default)
}

// Simple hash-based noise
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

void fragment() {
	vec2 uv = UV;

	// Map UV to grid coordinates
	vec2 grid_coord = uv * grid_size;
	vec2 cell = floor(grid_coord);
	vec2 cell_fract = fract(grid_coord);

	// Sample center terrain type
	vec2 center_uv = (cell + 0.5) / grid_size;
	float center_type = texture(terrain_data, center_uv).r;
	vec3 center_color = get_terrain_color(center_type);

	// Edge blending: sample neighbors and blend at edges
	vec3 final_color = center_color;
	float blend_zone = 0.3; // How far from edge blending starts

	// Right neighbor
	if (cell_fract.x > 1.0 - blend_zone && cell.x < grid_size.x - 1.0) {
		vec2 n_uv = (cell + vec2(1.5, 0.5)) / grid_size;
		vec3 n_color = get_terrain_color(texture(terrain_data, n_uv).r);
		float t = (cell_fract.x - (1.0 - blend_zone)) / blend_zone;
		final_color = mix(final_color, n_color, t * 0.5);
	}
	// Left neighbor
	if (cell_fract.x < blend_zone && cell.x > 0.0) {
		vec2 n_uv = (cell + vec2(-0.5, 0.5)) / grid_size;
		vec3 n_color = get_terrain_color(texture(terrain_data, n_uv).r);
		float t = (blend_zone - cell_fract.x) / blend_zone;
		final_color = mix(final_color, n_color, t * 0.5);
	}
	// Bottom neighbor
	if (cell_fract.y > 1.0 - blend_zone && cell.y < grid_size.y - 1.0) {
		vec2 n_uv = (cell + vec2(0.5, 1.5)) / grid_size;
		vec3 n_color = get_terrain_color(texture(terrain_data, n_uv).r);
		float t = (cell_fract.y - (1.0 - blend_zone)) / blend_zone;
		final_color = mix(final_color, n_color, t * 0.5);
	}
	// Top neighbor
	if (cell_fract.y < blend_zone && cell.y > 0.0) {
		vec2 n_uv = (cell + vec2(0.5, -0.5)) / grid_size;
		vec3 n_color = get_terrain_color(texture(terrain_data, n_uv).r);
		float t = (blend_zone - cell_fract.y) / blend_zone;
		final_color = mix(final_color, n_color, t * 0.5);
	}

	// Add noise variation per cell
	float noise = value_noise(grid_coord * 4.0) * 0.08 - 0.04;
	final_color += vec3(noise);

	// Water shimmer
	int center_t = int(center_type * 255.0 + 0.5);
	if (center_t == 3) { // WATER
		float shimmer = sin(grid_coord.x * 3.0 + time * 1.5) * cos(grid_coord.y * 2.5 + time * 1.2) * 0.04;
		final_color += vec3(0.0, shimmer * 0.5, shimmer);
	}
	// Crystal shimmer
	if (center_t == 7) { // CRYSTAL
		float sparkle = sin(grid_coord.x * 5.0 + time * 2.0) * sin(grid_coord.y * 4.0 - time * 1.8) * 0.05;
		final_color += vec3(sparkle, 0.0, sparkle);
	}

	COLOR = vec4(final_color, 1.0);
}
