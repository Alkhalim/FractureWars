shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.25, 0.12, 0.35, 1.0);

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
    vec2 uv = UV;

    // Pulsing crystal sparkle using noise + threshold
    vec2 grid = floor(uv * 20.0);
    float noise = hash(grid);
    float sparkle_threshold = 0.85 + sin(TIME * 2.0 + noise * 6.28) * 0.1;
    float sparkle = step(sparkle_threshold, noise) * (0.5 + 0.5 * sin(TIME * 3.0 + noise * 10.0));

    vec3 shard_color = base_color.rgb;
    // Slow pulse
    shard_color += vec3(0.04 * sin(TIME * 1.2), 0.0, 0.06 * sin(TIME * 0.7));
    // Crystal sparkles
    shard_color += vec3(sparkle * 0.15, sparkle * 0.05, sparkle * 0.2);

    // Use the texture if present
    vec4 tex_color = texture(TEXTURE, uv);
    if (tex_color.a > 0.01) {
        shard_color = mix(shard_color, tex_color.rgb, 0.6) + vec3(sparkle * 0.1, 0.0, sparkle * 0.15);
    }

    COLOR = vec4(shard_color, 1.0);
}
