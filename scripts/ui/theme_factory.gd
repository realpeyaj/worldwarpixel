class_name ThemeFactory
extends RefCounted
## Builds a crisp pixel-modern hybrid strategy UI theme: chamfered pixel 9-patch frames & bevels
## paired with clean typography and generous dark-slate spacing.


static func _make_9patch_box(
	tex_path: String,
	margin_px: int,
	pad_x: float,
	pad_y: float,
	fallback_bg: Color,
	fallback_border: Color
) -> StyleBox:
	if ResourceLoader.exists(tex_path):
		var tex: Texture2D = load(tex_path)
		if tex != null:
			var sb := StyleBoxTexture.new()
			sb.texture = tex
			sb.texture_margin_left = float(margin_px)
			sb.texture_margin_right = float(margin_px)
			sb.texture_margin_top = float(margin_px)
			sb.texture_margin_bottom = float(margin_px)
			sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
			sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
			sb.content_margin_left = pad_x
			sb.content_margin_right = pad_x
			sb.content_margin_top = pad_y
			sb.content_margin_bottom = pad_y
			return sb

	var fb := StyleBoxFlat.new()
	fb.anti_aliasing = false
	fb.bg_color = fallback_bg
	fb.border_color = fallback_border
	fb.set_border_width_all(2)
	fb.set_corner_radius_all(0)
	fb.content_margin_left = pad_x
	fb.content_margin_right = pad_x
	fb.content_margin_top = pad_y
	fb.content_margin_bottom = pad_y
	return fb


static func build_strategy_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 12

	var panel_sb := StyleBoxFlat.new()
	panel_sb.anti_aliasing = true
	panel_sb.bg_color = Color(0.14, 0.18, 0.24, 0.72)
	panel_sb.border_color = Color(0.70, 0.80, 0.90, 0.22)
	panel_sb.set_border_width_all(1)
	panel_sb.set_corner_radius_all(7)
	panel_sb.content_margin_left = 9.0
	panel_sb.content_margin_right = 9.0
	panel_sb.content_margin_top = 6.0
	panel_sb.content_margin_bottom = 6.0
	theme.set_stylebox("panel", "PanelContainer", panel_sb)

	var bar_sb := StyleBoxFlat.new()
	bar_sb.anti_aliasing = true
	bar_sb.bg_color = Color(0.14, 0.18, 0.24, 0.68)
	bar_sb.border_color = Color(0.70, 0.80, 0.90, 0.20)
	bar_sb.set_border_width_all(1)
	bar_sb.set_corner_radius_all(7)
	bar_sb.set_content_margin_all(5)
	theme.set_stylebox("panel", "TopBarPanel", bar_sb)

	var btn_normal := StyleBoxFlat.new()
	btn_normal.anti_aliasing = true
	btn_normal.bg_color = Color(0.22, 0.27, 0.35, 0.56)
	btn_normal.border_color = Color(0.74, 0.82, 0.92, 0.20)
	btn_normal.set_border_width_all(1)
	btn_normal.set_corner_radius_all(5)
	btn_normal.content_margin_left = 6.0
	btn_normal.content_margin_right = 6.0
	btn_normal.content_margin_top = 3.0
	btn_normal.content_margin_bottom = 3.0

	var btn_hover := btn_normal.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color(0.28, 0.35, 0.45, 0.74)
	btn_hover.border_color = Color(0.84, 0.90, 0.98, 0.36)

	var btn_pressed := btn_normal.duplicate() as StyleBoxFlat
	btn_pressed.bg_color = Color(0.33, 0.42, 0.54, 0.82)
	btn_pressed.border_color = Color(0.90, 0.95, 1.0, 0.48)

	var btn_disabled := btn_normal.duplicate() as StyleBoxFlat
	btn_disabled.bg_color = Color(0.16, 0.20, 0.26, 0.34)
	btn_disabled.border_color = Color(0.50, 0.58, 0.66, 0.12)

	for ctrl_type: String in ["Button", "OptionButton", "CheckButton"]:
		theme.set_stylebox("normal", ctrl_type, btn_normal)
		theme.set_stylebox("hover", ctrl_type, btn_hover)
		theme.set_stylebox("pressed", ctrl_type, btn_pressed)
		theme.set_stylebox("focus", ctrl_type, btn_hover)
		theme.set_stylebox("disabled", ctrl_type, btn_disabled)
		theme.set_color("font_color", ctrl_type, Color(0.93, 0.96, 0.99))
		theme.set_color("font_hover_color", ctrl_type, Color(1.0, 1.0, 1.0))
		theme.set_color("font_pressed_color", ctrl_type, Color(0.98, 0.99, 1.0))
		theme.set_color("font_disabled_color", ctrl_type, Color(0.56, 0.62, 0.70, 0.75))
		theme.set_constant("outline_size", ctrl_type, 0)

	theme.set_color("font_color", "Label", Color(0.92, 0.95, 0.98))
	theme.set_color("font_shadow_color", "Label", Color(0.04, 0.06, 0.10, 0.35))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)

	var le_normal := StyleBoxFlat.new()
	le_normal.anti_aliasing = true
	le_normal.bg_color = Color(0.12, 0.16, 0.22, 0.78)
	le_normal.border_color = Color(0.68, 0.78, 0.88, 0.26)
	le_normal.set_border_width_all(1)
	le_normal.set_corner_radius_all(5)
	le_normal.content_margin_left = 8
	le_normal.content_margin_right = 8
	le_normal.content_margin_top = 4
	le_normal.content_margin_bottom = 4
	var le_focus := le_normal.duplicate() as StyleBoxFlat
	le_focus.border_color = Color(0.56, 0.78, 0.98, 0.65)
	theme.set_stylebox("normal", "LineEdit", le_normal)
	theme.set_stylebox("focus", "LineEdit", le_focus)
	theme.set_color("font_color", "LineEdit", Color(0.95, 0.97, 1.0))

	var pb_bg := StyleBoxFlat.new()
	pb_bg.anti_aliasing = true
	pb_bg.bg_color = Color(0.12, 0.16, 0.22, 0.75)
	pb_bg.border_color = Color(0.64, 0.74, 0.86, 0.22)
	pb_bg.set_border_width_all(1)
	pb_bg.set_corner_radius_all(4)
	var pb_fill := StyleBoxFlat.new()
	pb_fill.anti_aliasing = true
	pb_fill.bg_color = Color(0.38, 0.70, 0.96, 0.88)
	pb_fill.set_corner_radius_all(4)
	theme.set_stylebox("background", "ProgressBar", pb_bg)
	theme.set_stylebox("fill", "ProgressBar", pb_fill)

	var sl_track := StyleBoxFlat.new()
	sl_track.anti_aliasing = true
	sl_track.bg_color = Color(0.18, 0.23, 0.30, 0.78)
	sl_track.border_color = Color(0.64, 0.74, 0.86, 0.24)
	sl_track.set_border_width_all(1)
	sl_track.set_corner_radius_all(3)
	sl_track.content_margin_top = 3
	sl_track.content_margin_bottom = 3
	var sl_fill := sl_track.duplicate() as StyleBoxFlat
	sl_fill.bg_color = Color(0.40, 0.70, 0.96, 0.88)
	theme.set_stylebox("slider", "HSlider", sl_track)
	theme.set_stylebox("grabber_area", "HSlider", sl_fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", sl_fill)

	return theme
