shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.08, 0.18, 0.42, 1.0);

void fragment() {
    vec2 uv = UV;

    // Animated wave distortion
    float wave1 = sin(uv.x * 8.0 + TIME * 1.5) * 0.03;
    float wave2 = cos(uv.y * 6.0 + TIME * 1.2) * 0.025;

    // Color shifting
    float shift = sin(TIME * 0.8 + uv.x * 4.0 + wave1) * 0.06;

    // Specular highlight (sparkle on waves)
    float spec = pow(max(sin(uv.x * 12.0 + TIME * 2.0 + wave1) * sin(uv.y * 10.0 - TIME * 1.5 + wave2), 0.0), 3.0) * 0.25;

    // Build water overlay color
    vec3 tint = vec3(wave1 * 2.0, shift * 0.5 + wave2, shift + spec * 0.5);
    tint += vec3(spec * 0.3, spec * 0.5, spec);

    // Semi-transparent animated overlay on top of the baked water texture
    float alpha = 0.3 + spec * 0.4 + abs(wave1) * 2.0;
    COLOR = vec4(tint * 0.5 + vec3(0.05, 0.1, 0.15), alpha);
}
