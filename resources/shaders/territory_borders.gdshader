shader_type canvas_item;

uniform sampler2D owner_tex : filter_nearest, repeat_disable;
uniform sampler2D nation_lut : filter_nearest, repeat_disable;
uniform vec2 sim_size = vec2(1024.0, 512.0);
uniform float lut_width = 256.0;
uniform float border_visibility : hint_range(0.0, 1.0) = 1.0;

int fetch_owner(vec2 cell) {
	if (cell.x < 0.0 || cell.y < 0.0 || cell.x >= sim_size.x || cell.y >= sim_size.y) {
		return 0;
	}
	vec2 uv_s = (floor(cell) + 0.5) / sim_size;
	int v = int(round(texture(owner_tex, uv_s).r * 255.0));
	return (v == 255) ? 0 : v;
}

void fragment() {
	vec2 sim_pos = UV * sim_size;
	vec2 cell = floor(sim_pos);
	int oid = fetch_owner(cell);
	if (oid <= 0) {
		COLOR = vec4(0.0);
	} else {
		vec2 f = fract(sim_pos);
		int o_l = fetch_owner(cell + vec2(-1.0, 0.0));
		int o_r = fetch_owner(cell + vec2(1.0, 0.0));
		int o_u = fetch_owner(cell + vec2(0.0, -1.0));
		int o_d = fetch_owner(cell + vec2(0.0, 1.0));

		float edge = 0.0;
		if (o_l != oid && f.x < 0.72) edge = 1.0;
		if (o_r != oid && f.x > 0.28) edge = 1.0;
		if (o_u != oid && f.y < 0.72) edge = 1.0;
		if (o_d != oid && f.y > 0.28) edge = 1.0;

		if (edge > 0.5) {
			vec4 ncol = texture(nation_lut, vec2((float(oid) + 0.5) / lut_width, 0.5));
			vec3 border_col = mix(ncol.rgb, vec3(0.04, 0.06, 0.09), 0.52);
			COLOR = vec4(border_col, 0.92 * border_visibility);
		} else {
			COLOR = vec4(0.0);
		}
	}
}
