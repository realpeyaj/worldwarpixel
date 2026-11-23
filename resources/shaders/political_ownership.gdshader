shader_type canvas_item;

uniform sampler2D owner_tex : filter_nearest, repeat_disable;
uniform sampler2D nation_lut : filter_nearest, repeat_disable;
uniform vec2 sim_size = vec2(1024.0, 512.0);
uniform float lut_width = 256.0;
uniform float political_opacity : hint_range(0.0, 1.0) = 0.42;

int fetch_owner(vec2 cell) {
	if (cell.x < 0.0 || cell.y < 0.0 || cell.x >= sim_size.x || cell.y >= sim_size.y) {
		return 0;
	}
	return int(round(texture(owner_tex, (floor(cell) + 0.5) / sim_size).r * 255.0));
}

void fragment() {
	vec2 cell = floor(UV * sim_size);
	int oid = fetch_owner(cell);
	if (oid <= 0) {
		COLOR = vec4(0.0);
	} else if (oid == 255) {
		vec2 sub = floor(UV * sim_size * 2.0);
		float n1 = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
		float n2 = fract(sin(dot(sub, vec2(269.5, 183.3))) * 43758.5453);
		float broil = 0.5 + 0.5 * sin(TIME * 2.2 + n1 * 6.28318 + cell.x * 0.18 + cell.y * 0.18);
		float mottle = mix(n1, n2, 0.45);
		int o_l = fetch_owner(cell + vec2(-1.0, 0.0));
		int o_r = fetch_owner(cell + vec2(1.0, 0.0));
		int o_u = fetch_owner(cell + vec2(0.0, -1.0));
		int o_d = fetch_owner(cell + vec2(0.0, 1.0));
		bool rim = (o_l != 255) || (o_r != 255) || (o_u != 255) || (o_d != 255);
		vec3 ash = vec3(0.09, 0.13, 0.08);
		vec3 rad = vec3(0.12, 0.76, 0.10);
		vec3 wcol = mix(ash, rad, smoothstep(0.30, 0.85, mix(mottle, broil, 0.28)));
		if (n2 > 0.86 && broil > 0.55) {
			wcol = mix(wcol, vec3(0.22, 1.0, 0.22), 0.55);
		}
		if (rim) {
			wcol = mix(wcol, vec3(0.28, 0.92, 0.18), 0.42);
		}
		COLOR = vec4(wcol, rim ? 0.88 : 0.78);
	} else {
		vec4 ncol = texture(nation_lut, vec2((float(oid) + 0.5) / lut_width, 0.5));
		int o_l = fetch_owner(cell + vec2(-1.0, 0.0));
		int o_r = fetch_owner(cell + vec2(1.0, 0.0));
		int o_u = fetch_owner(cell + vec2(0.0, -1.0));
		int o_d = fetch_owner(cell + vec2(0.0, 1.0));
		bool inner_rim = (o_l != oid) || (o_r != oid) || (o_u != oid) || (o_d != oid);
		float alpha = political_opacity * (inner_rim ? 1.28 : 0.92);
		COLOR = vec4(ncol.rgb, clamp(alpha, 0.0, 0.85));
	}
}
