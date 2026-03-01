shader_type canvas_item;

uniform sampler2D terrain_data : filter_nearest;
uniform vec2 grid_size; // terrain_grid_w, terrain_grid_h
uniform vec2 field_size; // FIELD_WIDTH, FIELD_HEIGHT
uniform float time;

// --- Terrain Colors (brighter, more saturated) ---
vec3 get_terrain_color(int t) {
	if (t == 1) return vec3(0.12, 0.28, 0.10);     // FOREST — rich deep green
	if (t == 2) return vec3(0.30, 0.26, 0.22);      // ROCK — warm gray-brown
	if (t == 3) return vec3(0.08, 0.15, 0.32);      // WATER — deep blue
	if (t == 4) return vec3(0.32, 0.28, 0.16);      // SAND — warm tan
	if (t == 5) return vec3(0.18, 0.14, 0.08);      // MUD — dark brown
	if (t == 6) return vec3(0.24, 0.30, 0.38);      // ICE — cold blue-gray
	if (t == 7) return vec3(0.26, 0.12, 0.32);      // CRYSTAL — vibrant purple
	if (t == 8) return vec3(0.16, 0.22, 0.12);      // BRUSH — muted olive green
	return vec3(0.15, 0.14, 0.12);                   // OPEN — neutral warm gray
}

// Secondary color for terrain detail patterns
vec3 get_terrain_detail_color(int t) {
	if (t == 1) return vec3(0.08, 0.20, 0.06);      // FOREST — darker leaf patches
	if (t == 2) return vec3(0.38, 0.34, 0.28);      // ROCK — lighter stone veins
	if (t == 3) return vec3(0.10, 0.20, 0.42);      // WATER — lighter highlights
	if (t == 4) return vec3(0.38, 0.34, 0.22);      // SAND — lighter dune highlights
	if (t == 5) return vec3(0.12, 0.10, 0.06);      // MUD — darker puddles
	if (t == 6) return vec3(0.32, 0.38, 0.48);      // ICE — frost highlights
	if (t == 7) return vec3(0.34, 0.18, 0.42);      // CRYSTAL — brighter veins
	if (t == 8) return vec3(0.20, 0.28, 0.14);      // BRUSH — lighter leaf bits
	return vec3(0.18, 0.17, 0.14);                   // OPEN — slightly lighter
}

// --- Noise Functions ---
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(269.5, 183.3))) * 43758.5453);
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

// FBM for rich terrain variation
float fbm(vec2 p, int octaves) {
	float sum = 0.0;
	float amp = 0.5;
	float freq = 1.0;
	for (int i = 0; i < octaves; i++) {
		sum += value_noise(p * freq) * amp;
		freq *= 2.0;
		amp *= 0.5;
	}
	return sum;
}

// Voronoi distance for rock/crystal patterns
float voronoi(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float min_dist = 1.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 point = vec2(hash(i + neighbor), hash2(i + neighbor));
			float d = length(neighbor + point - f);
			min_dist = min(min_dist, d);
		}
	}
	return min_dist;
}

int get_terrain_type(vec2 cell) {
	vec2 sample_uv = (cell + 0.5) / grid_size;
	float raw = texture(terrain_data, sample_uv).r;
	return int(raw * 255.0 + 0.5);
}

void fragment() {
	vec2 uv = UV;
	vec2 grid_coord = uv * grid_size;
	vec2 cell = floor(grid_coord);
	vec2 cell_fract = fract(grid_coord);

	// Center terrain type
	int center_t = get_terrain_type(cell);
	vec3 base_color = get_terrain_color(center_t);
	vec3 detail_color = get_terrain_detail_color(center_t);

	// --- Multi-scale terrain noise ---
	// Large-scale variation (landscape undulation)
	float large_noise = fbm(grid_coord * 0.8, 3) * 0.12 - 0.06;
	// Medium detail noise
	float med_noise = value_noise(grid_coord * 3.0) * 0.08 - 0.04;
	// Fine grain noise (texture)
	float fine_noise = value_noise(grid_coord * 8.0) * 0.05 - 0.025;

	vec3 final_color = base_color + vec3(large_noise + med_noise + fine_noise);

	// --- Terrain-specific detail patterns ---
	if (center_t == 0) {
		// OPEN — subtle grass direction lines
		float grass = sin(grid_coord.x * 12.0 + grid_coord.y * 6.0 + value_noise(grid_coord * 2.0) * 4.0) * 0.5 + 0.5;
		grass = smoothstep(0.4, 0.6, grass);
		final_color = mix(final_color, detail_color, grass * 0.15);
	}
	else if (center_t == 1) {
		// FOREST — leaf canopy clusters via FBM
		float canopy = fbm(grid_coord * 5.0, 3);
		float leaf_mask = smoothstep(0.35, 0.55, canopy);
		final_color = mix(final_color, detail_color, leaf_mask * 0.3);
		// Occasional bright highlight (light through canopy)
		float light_gap = smoothstep(0.7, 0.8, canopy);
		final_color += vec3(0.04, 0.06, 0.02) * light_gap;
	}
	else if (center_t == 2) {
		// ROCK — voronoi cracks and layered stone
		float cracks = voronoi(grid_coord * 4.0);
		float crack_line = smoothstep(0.05, 0.12, cracks);
		final_color = mix(detail_color * 0.7, final_color, crack_line);
		// Stone layering
		float layers = sin(grid_coord.y * 8.0 + value_noise(grid_coord * 1.5) * 3.0) * 0.5 + 0.5;
		final_color = mix(final_color, final_color * 1.08, smoothstep(0.45, 0.55, layers) * 0.2);
	}
	else if (center_t == 3) {
		// WATER — animated waves and caustics
		float wave = sin(grid_coord.x * 6.0 + time * 1.8 + sin(grid_coord.y * 3.0) * 2.0);
		wave *= cos(grid_coord.y * 5.0 + time * 1.3);
		float caustic = smoothstep(0.6, 0.95, wave * 0.5 + 0.5);
		final_color += vec3(0.02, 0.05, 0.10) * caustic;
		// Depth darkening toward center
		float depth = smoothstep(0.0, 0.4, min(cell_fract.x, min(cell_fract.y, min(1.0 - cell_fract.x, 1.0 - cell_fract.y))));
		final_color *= 0.88 + depth * 0.12;
	}
	else if (center_t == 4) {
		// SAND — wind ripples
		float ripple = sin(grid_coord.x * 10.0 + grid_coord.y * 3.0 + value_noise(grid_coord * 0.5) * 8.0);
		float ripple_line = smoothstep(0.7, 0.9, abs(ripple));
		final_color = mix(final_color, detail_color, ripple_line * 0.25);
	}
	else if (center_t == 5) {
		// MUD — dark wet patches
		float wet = fbm(grid_coord * 4.0, 3);
		float wet_mask = smoothstep(0.4, 0.6, wet);
		final_color = mix(final_color, detail_color, wet_mask * 0.35);
		// Slight sheen on wet areas
		float sheen = smoothstep(0.55, 0.65, wet) * 0.06;
		final_color += vec3(sheen * 0.3, sheen * 0.2, sheen * 0.1);
	}
	else if (center_t == 6) {
		// ICE — frost patterns and cracks
		float frost = voronoi(grid_coord * 3.5);
		float frost_edge = 1.0 - smoothstep(0.0, 0.08, frost);
		final_color = mix(final_color, vec3(0.45, 0.52, 0.62), frost_edge * 0.3);
		// Specular highlights
		float spec = pow(max(sin(grid_coord.x * 8.0 + time * 0.5) * cos(grid_coord.y * 7.0 - time * 0.3), 0.0), 8.0);
		final_color += vec3(spec * 0.08);
	}
	else if (center_t == 7) {
		// CRYSTAL — pulsing veins and sparkles
		float veins = voronoi(grid_coord * 5.0);
		float vein_glow = 1.0 - smoothstep(0.0, 0.1, veins);
		float pulse = 0.7 + 0.3 * sin(time * 2.5 + veins * 10.0);
		final_color = mix(final_color, vec3(0.5, 0.2, 0.6) * pulse, vein_glow * 0.5);
		// Sparkle points
		float sparkle = pow(hash(floor(grid_coord * 12.0)), 20.0);
		float sparkle_time = sin(time * 3.0 + hash(floor(grid_coord * 12.0)) * 6.28) * 0.5 + 0.5;
		final_color += vec3(0.3, 0.15, 0.4) * sparkle * sparkle_time;
	}
	else if (center_t == 8) {
		// BRUSH — scattered leaf clumps
		float scatter = fbm(grid_coord * 6.0, 2);
		float clump = smoothstep(0.45, 0.6, scatter);
		final_color = mix(final_color, detail_color, clump * 0.25);
	}

	// --- Domain warp for organic noise lookups ---
	float warp_strength = 0.8;
	vec2 warp_offset = vec2(
		value_noise(grid_coord * 1.5 + vec2(5.2, 1.3)) * warp_strength,
		value_noise(grid_coord * 1.5 + vec2(8.7, 3.9)) * warp_strength
	);
	vec2 warped_coord = grid_coord + warp_offset;

	// --- Edge blending (8 directions, wider blend zone, domain-warped noise) ---
	float blend_zone = 0.4;
	vec2 dirs[8] = vec2[8](
		vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0),
		vec2(1.0, 1.0), vec2(-1.0, 1.0), vec2(1.0, -1.0), vec2(-1.0, -1.0)
	);
	// Distances to each edge/corner: cardinal edges then diagonal corners
	float edge_dists[8] = float[8](
		cell_fract.x, 1.0 - cell_fract.x, cell_fract.y, 1.0 - cell_fract.y,
		min(cell_fract.x, cell_fract.y),
		min(1.0 - cell_fract.x, cell_fract.y),
		min(cell_fract.x, 1.0 - cell_fract.y),
		min(1.0 - cell_fract.x, 1.0 - cell_fract.y)
	);

	for (int i = 0; i < 8; i++) {
		float dist_from_edge = 1.0 - edge_dists[i]; // distance toward the neighbor
		// Diagonal neighbors contribute less strongly
		float weight = (i < 4) ? 0.5 : 0.3;
		if (dist_from_edge < blend_zone) {
			vec2 neighbor_cell = cell + dirs[i];
			if (neighbor_cell.x >= 0.0 && neighbor_cell.x < grid_size.x &&
				neighbor_cell.y >= 0.0 && neighbor_cell.y < grid_size.y) {
				int n_t = get_terrain_type(neighbor_cell);
				if (n_t != center_t) {
					vec3 n_color = get_terrain_color(n_t);
					// Domain-warped noise for more organic boundary shapes
					float noise_offset = value_noise(warped_coord * 5.0 + dirs[i] * 2.5) * 0.2 - 0.1;
					float t = smoothstep(0.0, blend_zone, blend_zone - dist_from_edge + noise_offset);
					final_color = mix(final_color, n_color, t * weight);
				}
			}
		}
	}

	// --- Subtle cell boundary lines (thin, dark) ---
	float edge_x = min(cell_fract.x, 1.0 - cell_fract.x);
	float edge_y = min(cell_fract.y, 1.0 - cell_fract.y);
	float edge_dist = min(edge_x, edge_y);
	float grid_line = 1.0 - smoothstep(0.01, 0.04, edge_dist);
	final_color *= 1.0 - grid_line * 0.12; // Very subtle darkening at edges

	// --- Directional lighting (top-left light source) ---
	float light_dir = value_noise(grid_coord * 2.0 + vec2(0.3, -0.2));
	float light = 0.95 + light_dir * 0.10;
	final_color *= light;

	// --- Ambient occlusion at terrain transitions (8 directions) ---
	// Slight darkening where different terrains meet
	float ao = 0.0;
	for (int i = 0; i < 8; i++) {
		vec2 neighbor_cell = cell + dirs[i];
		if (neighbor_cell.x >= 0.0 && neighbor_cell.x < grid_size.x &&
			neighbor_cell.y >= 0.0 && neighbor_cell.y < grid_size.y) {
			int n_t = get_terrain_type(neighbor_cell);
			if (n_t != center_t) {
				float d = 1.0 - edge_dists[i];
				float ao_weight = (i < 4) ? 0.03 : 0.02;
				ao += smoothstep(0.3, 0.0, d) * ao_weight;
			}
		}
	}
	final_color *= 1.0 - ao;

	COLOR = vec4(final_color, 1.0);
}
