class_name ThemeFactory
extends RefCounted
## Cohesive rounded grand-strategy UI theme with beveled surfaces, pill bars,
## geometric sans typography (Exo 2 OFL), and semantic button states.

const UI_FONT_PATH := "res://assets/fonts/Exo2-Medium.ttf"

static var _cached_font: Font = null
static var _font_checked: bool = false


static func get_ui_font() -> Font:
	if not _font_checked:
		_font_checked = true
		if ResourceLoader.exists(UI_FONT_PATH):
			var loaded := load(UI_FONT_PATH)
			if loaded is Font:
				_cached_font = loaded as Font
		if _cached_font == null and FileAccess.file_exists(UI_FONT_PATH):
			var ff := FontFile.new()
			if ff.load_dynamic_font(UI_FONT_PATH) == OK:
				_cached_font = ff
	if _cached_font != null:
		return _cached_font
	return ThemeDB.fallback_font


static func _make_rounded_box(
	bg: Color,
	border: Color,
	border_w: int,
	radius: int,
	pad_x: float,
	pad_y: float,
	shadow_sz: int = 0,
	bottom_bevel: int = 0
) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.anti_aliasing = true
	sb.anti_aliasing_size = 1.0
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	if bottom_bevel > border_w:
		sb.border_width_bottom = bottom_bevel
	sb.set_corner_radius_all(radius)
	if shadow_sz > 0:
		sb.shadow_color = Color(0.01, 0.02, 0.04, 0.36)
		sb.shadow_size = shadow_sz
		sb.shadow_offset = Vector2(0, 2)
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	return sb


static func _make_empty_box(pad_x: float, pad_y: float) -> StyleBoxEmpty:
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	return sb


static func _apply_button_rounded(
	target: Button,
	normal_bg: Color,
	hover_bg: Color,
	pressed_bg: Color,
	disabled_bg: Color,
	border_col: Color,
	pad_x: float = 12.0,
	pad_y: float = 6.0,
	radius: int = 8
) -> void:
	var n_sb := _make_rounded_box(normal_bg, border_col, 1, radius, pad_x, pad_y, 2, 2)
	var h_sb := _make_rounded_box(hover_bg, border_col.lightened(0.28), 1, radius, pad_x, pad_y, 3, 2)
	var p_sb := _make_rounded_box(pressed_bg, border_col.lightened(0.18), 1, radius, pad_x, pad_y, 0, 1)
	var d_sb := _make_rounded_box(disabled_bg, Color(border_col.r, border_col.g, border_col.b, 0.32), 1, radius, pad_x, pad_y, 0, 1)
	target.add_theme_stylebox_override("normal", n_sb)
	target.add_theme_stylebox_override("hover", h_sb)
	target.add_theme_stylebox_override("focus", h_sb)
	target.add_theme_stylebox_override("pressed", p_sb)
	target.add_theme_stylebox_override("disabled", d_sb)


static func apply_panel_variant(panel: PanelContainer, variant: String) -> void:
	if panel == null:
		return
	match variant:
		"dock_top":
			panel.add_theme_stylebox_override(
				"panel",
				_make_rounded_box(Color(0.06, 0.10, 0.16, 0.90), Color(0.32, 0.48, 0.68, 0.42), 1, 10, 10.0, 5.0, 4, 2)
			)
		"dock_bottom", "bottom_bar":
			panel.add_theme_stylebox_override(
				"panel",
				_make_rounded_box(Color(0.05, 0.08, 0.13, 0.92), Color(0.30, 0.44, 0.62, 0.40), 1, 12, 10.0, 4.0, 6, 2)
			)
		"util_strip":
			panel.add_theme_stylebox_override(
				"panel",
				_make_rounded_box(Color(0.06, 0.09, 0.15, 0.88), Color(0.32, 0.46, 0.64, 0.38), 1, 10, 10.0, 4.0, 4, 2)
			)
		"flat":
			panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		_:
			panel.add_theme_stylebox_override(
				"panel",
				_make_rounded_box(Color(0.06, 0.10, 0.16, 0.93), Color(0.34, 0.52, 0.74, 0.44), 1, 12, 14.0, 11.0, 8, 2)
			)


static func apply_button_variant(btn: Button, variant: String) -> void:
	if btn == null:
		return
	match variant:
		"primary":
			_apply_button_rounded(btn, Color(0.16, 0.56, 0.37, 0.96), Color(0.22, 0.68, 0.46, 0.98), Color(0.13, 0.45, 0.30, 0.98), Color(0.16, 0.28, 0.22, 0.62), Color(0.42, 0.86, 0.62, 0.58), 12.0, 7.0, 9)
		"secondary":
			_apply_button_rounded(btn, Color(0.18, 0.38, 0.62, 0.95), Color(0.24, 0.48, 0.76, 0.98), Color(0.14, 0.31, 0.52, 0.98), Color(0.16, 0.23, 0.32, 0.62), Color(0.45, 0.74, 0.98, 0.52), 12.0, 7.0, 9)
		"back":
			_apply_button_rounded(btn, Color(0.20, 0.27, 0.37, 0.92), Color(0.28, 0.37, 0.50, 0.96), Color(0.16, 0.22, 0.30, 0.96), Color(0.16, 0.20, 0.26, 0.60), Color(0.46, 0.58, 0.74, 0.44), 11.0, 6.0, 8)
		"danger":
			_apply_button_rounded(btn, Color(0.68, 0.20, 0.23, 0.96), Color(0.82, 0.27, 0.30, 0.98), Color(0.54, 0.15, 0.18, 0.98), Color(0.32, 0.16, 0.18, 0.62), Color(1.0, 0.48, 0.48, 0.52), 12.0, 7.0, 9)
		"ghost":
			var idle := _make_empty_box(6.0, 3.0)
			var hov := _make_rounded_box(Color(0.28, 0.42, 0.60, 0.40), Color(0.56, 0.76, 0.96, 0.48), 1, 7, 6.0, 3.0)
			var prs := _make_rounded_box(Color(0.36, 0.54, 0.76, 0.56), Color(0.82, 0.92, 1.0, 0.72), 1, 7, 6.0, 3.0)
			btn.add_theme_stylebox_override("normal", idle)
			btn.add_theme_stylebox_override("disabled", idle)
			btn.add_theme_stylebox_override("focus", hov)
			btn.add_theme_stylebox_override("hover", hov)
			btn.add_theme_stylebox_override("pressed", prs)
		"ghost_danger":
			var idle_d := _make_empty_box(5.0, 3.0)
			var hov_d := _make_rounded_box(Color(0.76, 0.20, 0.23, 0.74), Color(1.0, 0.52, 0.52, 0.85), 1, 7, 5.0, 3.0)
			var prs_d := _make_rounded_box(Color(0.60, 0.15, 0.18, 0.88), Color(1.0, 0.62, 0.62, 0.95), 1, 7, 5.0, 3.0)
			btn.add_theme_stylebox_override("normal", idle_d)
			btn.add_theme_stylebox_override("disabled", idle_d)
			btn.add_theme_stylebox_override("focus", hov_d)
			btn.add_theme_stylebox_override("hover", hov_d)
			btn.add_theme_stylebox_override("pressed", prs_d)
		"dock_slot":
			set_slot_active(btn, false, Color(0.92, 0.82, 0.46, 0.90))


static func set_slot_active(btn: Button, active: bool, accent_border: Color = Color(0.92, 0.82, 0.46, 0.90)) -> void:
	if btn == null:
		return
	if active:
		var act := _make_rounded_box(Color(0.22, 0.36, 0.54, 0.80), accent_border, 1, 7, 5.0, 3.0)
		btn.add_theme_stylebox_override("normal", act)
		btn.add_theme_stylebox_override("hover", act)
		btn.add_theme_stylebox_override("focus", act)
		btn.add_theme_stylebox_override("pressed", act)
	else:
		var idle := _make_empty_box(5.0, 3.0)
		var hov := _make_rounded_box(Color(0.24, 0.38, 0.56, 0.44), Color(0.58, 0.78, 0.96, 0.52), 1, 7, 5.0, 3.0)
		var prs := _make_rounded_box(Color(0.32, 0.50, 0.72, 0.62), accent_border, 1, 7, 5.0, 3.0)
		btn.add_theme_stylebox_override("normal", idle)
		btn.add_theme_stylebox_override("disabled", idle)
		btn.add_theme_stylebox_override("hover", hov)
		btn.add_theme_stylebox_override("focus", hov)
		btn.add_theme_stylebox_override("pressed", prs)


static func set_commit_pill_active(btn: Button, active: bool) -> void:
	if btn == null:
		return
	if active:
		var act := _make_rounded_box(Color(0.26, 0.21, 0.08, 0.96), Color(0.90, 0.74, 0.28, 1.0), 1, 6, 5.0, 2.0)
		btn.add_theme_stylebox_override("normal", act)
		btn.add_theme_stylebox_override("hover", act)
		btn.add_theme_stylebox_override("focus", act)
		btn.add_theme_stylebox_override("pressed", act)
		btn.add_theme_color_override("font_color", Color(1.0, 0.89, 0.45))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 0.93, 0.56))
	else:
		var idle := _make_rounded_box(Color(0.11, 0.14, 0.20, 0.92), Color(0.26, 0.34, 0.46, 0.68), 1, 6, 5.0, 2.0)
		var hov := _make_rounded_box(Color(0.17, 0.22, 0.30, 0.96), Color(0.42, 0.54, 0.70, 0.88), 1, 6, 5.0, 2.0)
		btn.add_theme_stylebox_override("normal", idle)
		btn.add_theme_stylebox_override("disabled", idle)
		btn.add_theme_stylebox_override("hover", hov)
		btn.add_theme_stylebox_override("focus", hov)
		btn.add_theme_stylebox_override("pressed", hov)
		btn.add_theme_color_override("font_color", Color(0.84, 0.88, 0.94))
		btn.add_theme_color_override("font_hover_color", Color.WHITE)


static func set_photo_slot_active(btn: Button, active: bool, accent: Color = Color(0.92, 0.82, 0.46, 0.95)) -> void:
	if btn == null:
		return
	if active:
		var act := _make_rounded_box(Color(accent.r * 0.26, accent.g * 0.26, accent.b * 0.26, 0.82), accent, 1, 7, 4.0, 2.0)
		act.content_margin_top = 12.0
		btn.add_theme_stylebox_override("normal", act)
		btn.add_theme_stylebox_override("hover", act)
		btn.add_theme_stylebox_override("focus", act)
		btn.add_theme_stylebox_override("pressed", act)
	else:
		var idle := _make_empty_box(4.0, 2.0)
		idle.content_margin_top = 12.0
		var hov := _make_rounded_box(Color(0.16, 0.24, 0.36, 0.52), Color(0.48, 0.68, 0.90, 0.52), 1, 7, 4.0, 2.0)
		hov.content_margin_top = 12.0
		var prs := _make_rounded_box(Color(accent.r * 0.26, accent.g * 0.26, accent.b * 0.26, 0.82), accent, 1, 7, 4.0, 2.0)
		prs.content_margin_top = 12.0
		btn.add_theme_stylebox_override("normal", idle)
		btn.add_theme_stylebox_override("disabled", idle)
		btn.add_theme_stylebox_override("hover", hov)
		btn.add_theme_stylebox_override("focus", hov)
		btn.add_theme_stylebox_override("pressed", prs)


static func build_strategy_theme() -> Theme:
	var theme := Theme.new()
	var ui_font: Font = get_ui_font()
	if ui_font != null:
		theme.default_font = ui_font
	theme.default_font_size = 13

	var panel_sb := _make_rounded_box(
		Color(0.06, 0.10, 0.16, 0.93),
		Color(0.34, 0.52, 0.74, 0.44),
		1,
		12,
		14.0,
		11.0,
		8,
		2
	)
	theme.set_stylebox("panel", "PanelContainer", panel_sb)

	var bar_sb := _make_rounded_box(
		Color(0.06, 0.10, 0.16, 0.92),
		Color(0.32, 0.48, 0.68, 0.42),
		1,
		10,
		10.0,
		5.0,
		4,
		2
	)
	theme.set_stylebox("panel", "TopBarPanel", bar_sb)

	var btn_normal := _make_rounded_box(Color(0.17, 0.25, 0.36, 0.94), Color(0.38, 0.54, 0.74, 0.45), 1, 8, 10.0, 5.0, 2, 2)
	var btn_hover := _make_rounded_box(Color(0.24, 0.35, 0.50, 0.98), Color(0.56, 0.76, 0.98, 0.68), 1, 8, 10.0, 5.0, 3, 2)
	var btn_pressed := _make_rounded_box(Color(0.14, 0.20, 0.30, 0.98), Color(0.46, 0.68, 0.92, 0.72), 1, 8, 10.0, 5.0, 0, 1)
	var btn_disabled := _make_rounded_box(Color(0.14, 0.18, 0.24, 0.64), Color(0.24, 0.30, 0.38, 0.34), 1, 8, 10.0, 5.0, 0, 1)

	for ctrl_type: String in ["Button", "OptionButton", "CheckButton"]:
		theme.set_stylebox("normal", ctrl_type, btn_normal)
		theme.set_stylebox("hover", ctrl_type, btn_hover)
		theme.set_stylebox("pressed", ctrl_type, btn_pressed)
		theme.set_stylebox("focus", ctrl_type, btn_hover)
		theme.set_stylebox("disabled", ctrl_type, btn_disabled)
		theme.set_color("font_color", ctrl_type, Color(0.94, 0.97, 1.0))
		theme.set_color("font_hover_color", ctrl_type, Color.WHITE)
		theme.set_color("font_pressed_color", ctrl_type, Color(0.98, 0.99, 1.0))
		theme.set_color("font_disabled_color", ctrl_type, Color(0.58, 0.64, 0.72, 0.78))
		theme.set_color("font_outline_color", ctrl_type, Color(0.04, 0.07, 0.12, 0.80))
		theme.set_constant("outline_size", ctrl_type, 1)

	theme.set_color("font_color", "Label", Color(0.94, 0.97, 1.0))
	theme.set_color("font_shadow_color", "Label", Color(0.02, 0.04, 0.08, 0.78))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)

	var le_normal := _make_rounded_box(Color(0.05, 0.09, 0.15, 0.95), Color(0.30, 0.44, 0.62, 0.78), 1, 7, 10.0, 6.0)
	var le_focus := _make_rounded_box(Color(0.07, 0.12, 0.20, 0.98), Color(0.86, 0.72, 0.36, 0.95), 2, 7, 10.0, 6.0)
	theme.set_stylebox("normal", "LineEdit", le_normal)
	theme.set_stylebox("focus", "LineEdit", le_focus)
	theme.set_color("font_color", "LineEdit", Color(0.96, 0.98, 1.0))

	var pb_bg := _make_rounded_box(Color(0.06, 0.09, 0.15, 0.95), Color(0.28, 0.40, 0.56, 0.75), 1, 99, 0.0, 0.0)
	var pb_fill := _make_rounded_box(Color(0.28, 0.72, 0.94, 0.96), Color(0.64, 0.88, 1.0, 0.75), 1, 99, 0.0, 0.0)
	theme.set_stylebox("background", "ProgressBar", pb_bg)
	theme.set_stylebox("fill", "ProgressBar", pb_fill)

	var sl_track := _make_rounded_box(Color(0.09, 0.14, 0.22, 0.96), Color(0.28, 0.42, 0.58, 0.80), 1, 99, 0.0, 3.0)
	var sl_fill := _make_rounded_box(Color(0.32, 0.74, 0.96, 0.94), Color(0.64, 0.88, 1.0, 0.72), 1, 99, 0.0, 3.0)
	theme.set_stylebox("slider", "HSlider", sl_track)
	theme.set_stylebox("grabber_area", "HSlider", sl_fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", sl_fill)

	var pm_panel := _make_rounded_box(Color(0.07, 0.11, 0.18, 0.98), Color(0.34, 0.50, 0.68, 0.85), 1, 8, 8.0, 6.0, 6)
	var pm_hover := _make_rounded_box(Color(0.22, 0.38, 0.58, 0.94), Color(0.58, 0.78, 0.96, 0.82), 1, 6, 8.0, 4.0)
	theme.set_stylebox("panel", "PopupMenu", pm_panel)
	theme.set_stylebox("hover", "PopupMenu", pm_hover)
	theme.set_color("font_color", "PopupMenu", Color(0.93, 0.96, 1.0))
	theme.set_color("font_hover_color", "PopupMenu", Color.WHITE)

	var hsep := StyleBoxLine.new()
	hsep.color = Color(0.34, 0.48, 0.66, 0.42)
	hsep.thickness = 1
	theme.set_stylebox("separator", "HSeparator", hsep)

	var vsep := StyleBoxLine.new()
	vsep.color = Color(0.34, 0.48, 0.66, 0.38)
	vsep.thickness = 1
	vsep.vertical = true
	theme.set_stylebox("separator", "VSeparator", vsep)

	return theme
