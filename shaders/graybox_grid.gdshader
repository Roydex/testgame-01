shader_type spatial;
// World-space grid for grey-box geometry: 1 m minor / 5 m major lines,
// so speed and height are readable while testing movement.

uniform vec4 base_color : source_color = vec4(0.55, 0.56, 0.58, 1.0);
uniform vec4 line_color : source_color = vec4(0.25, 0.26, 0.28, 1.0);
uniform float minor_width = 0.03;
uniform float major_width = 0.06;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float grid(vec2 p, float spacing, float width) {
	vec2 g = abs(fract(p / spacing - 0.5) - 0.5) * spacing;
	float d = min(g.x, g.y);
	return 1.0 - smoothstep(width * 0.5, width, d);
}

void fragment() {
	vec3 n = abs(world_normal);
	vec2 p = n.y > 0.5 ? world_pos.xz : (n.x > 0.5 ? world_pos.zy : world_pos.xy);
	float l = max(grid(p, 1.0, minor_width) * 0.45, grid(p, 5.0, major_width));
	ALBEDO = mix(base_color.rgb, line_color.rgb, l);
	ROUGHNESS = 0.85;
}
