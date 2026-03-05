shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.08, 0.18, 0.42, 1.0);

void fragment() {
    vec2 uv = UV;
    // Animated wave distortion
    float wave1 = sin(uv.x * 8.0 + TIME * 1.5) * 0.02;
    float wave2 = cos(uv.y * 6.0 + TIME * 1.2) * 0.015;
    vec2 distorted_uv = uv + vec2(wave1, wave2);

    // Color shifting
    float shift = sin(TIME * 0.8 + distorted_uv.x * 4.0) * 0.03;
    vec3 water_color = base_color.rgb + vec3(0.0, shift * 0.5, shift);

    // Subtle specular highlight
    float spec = pow(max(sin(distorted_uv.x * 12.0 + TIME * 2.0) * sin(distorted_uv.y * 10.0 - TIME * 1.5), 0.0), 4.0) * 0.12;
    water_color += vec3(spec);

    // Use the texture if present, blend with water effect
    vec4 tex_color = texture(TEXTURE, distorted_uv);
    if (tex_color.a > 0.01) {
        water_color = mix(water_color, tex_color.rgb, 0.6);
    }

    COLOR = vec4(water_color, 1.0);
}
