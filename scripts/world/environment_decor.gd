class_name EnvironmentDecor
extends Node2D
## Layer 7 cartographic framing: outer table matte, hard rectangular border,
## degree tick bars, subtle graticule lines, and a minimalist compass rose.

@export var map_size: Vector2 = Vector2(2048.0, 1024.0)
@export var frame_margin: float = 18.0


func _draw() -> void:
	var w: float = map_size.x
	var h: float = map_size.y

	# Outer cartographic table surface beyond hard rectangular borders
	var pad := 1600.0
	var table_col := Color(0.043, 0.059, 0.086, 1.0)
	draw_rect(Rect2(-pad, -pad, w + pad * 2.0, pad), table_col)
	draw_rect(Rect2(-pad, h, w + pad * 2.0, pad), table_col)
	draw_rect(Rect2(-pad, 0.0, pad, h), table_col)
	draw_rect(Rect2(w, 0.0, pad, h), table_col)

	# Subtle latitude / longitude graticule across the map surface
	var grid_col := Color(0.65, 0.80, 0.94, 0.08)
	var major_col := Color(0.82, 0.88, 0.96, 0.14)
	for lon_deg in range(-150, 180, 30):
		var gx: float = (float(lon_deg) + 180.0) / 360.0 * w
		draw_line(Vector2(gx, 0.0), Vector2(gx, h), major_col if lon_deg == 0 else grid_col, 1.0)
	for lat_deg in range(-60, 90, 30):
		var gy: float = (90.0 - float(lat_deg)) / 180.0 * h
		draw_line(Vector2(0.0, gy), Vector2(w, gy), major_col if lat_deg == 0 else grid_col, 1.0)

	# Crisp alternating nautical border around [0, 0, w, h]
	var step_x: float = w / 24.0  # 15 deg longitude ticks
	var step_y: float = h / 12.0  # 15 deg latitude ticks
	var dark_bar := Color(0.10, 0.14, 0.20, 1.0)
	var light_bar := Color(0.76, 0.72, 0.60, 0.90)
	var bar_w := 5.0

	for i in range(24):
		var col := dark_bar if (i % 2 == 0) else light_bar
		var x0: float = float(i) * step_x
		draw_rect(Rect2(x0, -bar_w, step_x, bar_w), col)
		draw_rect(Rect2(x0, h, step_x, bar_w), col)
	for j in range(12):
		var col := dark_bar if (j % 2 == 0) else light_bar
		var y0: float = float(j) * step_y
		draw_rect(Rect2(-bar_w, y0, bar_w, step_y), col)
		draw_rect(Rect2(w, y0, bar_w, step_y), col)

	# Outer brass-trimmed double border frame
	var outer_rect := Rect2(-frame_margin, -frame_margin, w + frame_margin * 2.0, h + frame_margin * 2.0)
	var inner_rect := Rect2(-bar_w, -bar_w, w + bar_w * 2.0, h + bar_w * 2.0)
	draw_rect(outer_rect, Color(0.55, 0.52, 0.44, 0.65), false, 2.0)
	draw_rect(inner_rect, Color(0.84, 0.79, 0.64, 0.80), false, 1.5)
	draw_rect(Rect2(0.0, 0.0, w, h), Color(0.08, 0.11, 0.15, 0.90), false, 1.5)
