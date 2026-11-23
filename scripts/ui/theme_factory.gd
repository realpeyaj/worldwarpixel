class_name ThemeFactory
extends RefCounted
## Builds a cohesive pixel-art grand-strategy UI theme with stepped 9-patch frames,
## borderless inner controls (zero box-in-box clutter), and semantic color button variants.


static func _make_9patch_box(
	tex_path: String,
	margin_px: int,
	pad_x: float,
	pad_y: float,
	fallback_bg: Color,
	fallback_border: Color,
	modulate: Color = Color.WHITE
) -> StyleBox:
	if ResourceLoader.exists(tex_path):
		var tex: Texture2D = load(tex_path)
		if tex != null:
			var sb := StyleBoxTexture.new()
			sb.texture = tex
			sb.modulate_color = modulate
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
	fb.bg_color = fallback_bg * modulate
	fb.border_color = fallback_border
	fb.set_border_width_all(2)
	fb.set_corner_radius_all(0)
	fb.content_margin_left = pad_x
	fb.content_margin_right = pad_x
	fb.content_margin_top = pad_y
	fb.content_margin_bottom = pad_y
	return fb


static func _make_pixel_flat(
	bg: Color,
	border: Color,
	border_w: int,
	pad_x: float,
	pad_y: float
) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.anti_aliasing = false
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(0)
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


static func _apply_button_9patch(
	target: Button,
	normal_col: Color,
	hover_col: Color,
	pressed_col: Color,
	disabled_col: Color,
	pad_x: float = 10.0,
	pad_y: float = 6.0
) -> void:
	var n_sb := _make_9patch_box("res://assets/ui/btn_normal_9patch.png", 4, pad_x, pad_y, Color(0.24, 0.34, 0.46), Color(0.06, 0.09, 0.14), normal_col)
	var h_sb := _make_9patch_box("res://assets/ui/btn_hover_9patch.png", 4, pad_x, pad_y, Color(0.32, 0.45, 0.62), Color(0.10, 0.14, 0.22), hover_col)
	var p_sb := _make_9patch_box("res://assets/ui/btn_pressed_9patch.png", 4, pad_x, pad_y, Color(0.20, 0.28, 0.38), Color(0.05, 0.08, 0.12), pressed_col)
	var d_sb := _make_9patch_box("res://assets/ui/btn_disabled_9patch.png", 4, pad_x, pad_y, Color(0.18, 0.22, 0.28, 0.72), Color(0.08, 0.10, 0.14), disabled_col)
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
				_make_9patch_box("res://assets/ui/dock_top_9patch.png", 4, 10.0, 4.0, Color(0.07, 0.11, 0.17, 0.95), Color(0.04, 0.06, 0.09))
			)
		"dock_bottom":
			panel.add_theme_stylebox_override(
				"panel",
				_make_9patch_box("res://assets/ui/dock_bottom_9patch.png", 4, 8.0, 4.0, Color(0.05, 0.09, 0.14, 0.96), Color(0.04, 0.06, 0.09))
			)
		"flat":
			panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		_:
			panel.add_theme_stylebox_override(
				"panel",
				_make_9patch_box("res://assets/ui/panel_9patch.png", 4, 10.0, 8.0, Color(0.07, 0.11, 0.17, 0.94), Color(0.04, 0.06, 0.09))
			)


static func apply_button_variant(btn: Button, variant: String) -> void:
	if btn == null:
		return
	match variant:
		"primary":
			_apply_button_9patch(btn, Color(0.22, 0.62, 0.40), Color(0.28, 0.76, 0.50), Color(0.18, 0.52, 0.34), Color(0.18, 0.32, 0.24, 0.65), 10.0, 6.0)
		"secondary":
			_apply_button_9patch(btn, Color(0.24, 0.48, 0.74), Color(0.32, 0.60, 0.88), Color(0.20, 0.40, 0.64), Color(0.18, 0.26, 0.36, 0.65), 10.0, 6.0)
		"back":
			_apply_button_9patch(btn, Color(0.34, 0.42, 0.54), Color(0.46, 0.56, 0.70), Color(0.26, 0.34, 0.44), Color(0.20, 0.24, 0.30, 0.65), 10.0, 5.0)
		"danger":
			_apply_button_9patch(btn, Color(0.74, 0.24, 0.26), Color(0.88, 0.32, 0.34), Color(0.60, 0.18, 0.20), Color(0.38, 0.18, 0.20, 0.65), 10.0, 6.0)
		"ghost":
			var idle := _make_empty_box(5.0, 2.0)
			var hov := _make_pixel_flat(Color(0.34, 0.48, 0.66, 0.42), Color(0.60, 0.78, 0.96, 0.55), 1, 5.0, 2.0)
			var prs := _make_pixel_flat(Color(0.42, 0.60, 0.82, 0.58), Color(0.84, 0.92, 1.0, 0.78), 1, 5.0, 2.0)
			btn.add_theme_stylebox_override("normal", idle)
			btn.add_theme_stylebox_override("disabled", idle)
			btn.add_theme_stylebox_override("focus", hov)
			btn.add_theme_stylebox_override("hover", hov)
			btn.add_theme_stylebox_override("pressed", prs)
		"ghost_danger":
			var idle_d := _make_empty_box(4.0, 2.0)
			var hov_d := _make_pixel_flat(Color(0.78, 0.22, 0.24, 0.72), Color(1.0, 0.52, 0.52, 0.85), 1, 4.0, 2.0)
			var prs_d := _make_pixel_flat(Color(0.62, 0.16, 0.18, 0.88), Color(1.0, 0.62, 0.62, 0.95), 1, 4.0, 2.0)
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
		var act := _make_pixel_flat(Color(0.24, 0.38, 0.54, 0.78), accent_border, 1, 4.0, 2.0)
		btn.add_theme_stylebox_override("normal", act)
		btn.add_theme_stylebox_override("hover", act)
		btn.add_theme_stylebox_override("focus", act)
		btn.add_theme_stylebox_override("pressed", act)
	else:
		var idle := _make_empty_box(4.0, 2.0)
		var hov := _make_pixel_flat(Color(0.28, 0.42, 0.60, 0.46), Color(0.62, 0.80, 0.98, 0.55), 1, 4.0, 2.0)
		var prs := _make_pixel_flat(Color(0.36, 0.54, 0.76, 0.62), accent_border, 1, 4.0, 2.0)
		btn.add_theme_stylebox_override("normal", idle)
		btn.add_theme_stylebox_override("disabled", idle)
		btn.add_theme_stylebox_override("hover", hov)
		btn.add_theme_stylebox_override("focus", hov)
		btn.add_theme_stylebox_override("pressed", prs)


static func build_strategy_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 12

	var panel_sb := _make_9patch_box(
		"res://assets/ui/panel_9patch.png",
		4,
		10.0,
		8.0,
		Color(0.07, 0.11, 0.17, 0.94),
		Color(0.04, 0.06, 0.09, 1.0)
	)
	theme.set_stylebox("panel", "PanelContainer", panel_sb)

	var bar_sb := _make_9patch_box(
		"res://assets/ui/dock_top_9patch.png",
		4,
		10.0,
		4.0,
		Color(0.07, 0.11, 0.17, 0.95),
		Color(0.04, 0.06, 0.09, 1.0)
	)
	theme.set_stylebox("panel", "TopBarPanel", bar_sb)

	var btn_normal := _make_9patch_box("res://assets/ui/btn_normal_9patch.png", 4, 8.0, 4.0, Color(0.24, 0.34, 0.46), Color(0.05, 0.08, 0.13), Color(0.26, 0.35, 0.48))
	var btn_hover := _make_9patch_box("res://assets/ui/btn_hover_9patch.png", 4, 8.0, 4.0, Color(0.34, 0.46, 0.62), Color(0.08, 0.12, 0.18), Color(0.36, 0.48, 0.65))
	var btn_pressed := _make_9patch_box("res://assets/ui/btn_pressed_9patch.png", 4, 8.0, 4.0, Color(0.20, 0.28, 0.38), Color(0.05, 0.08, 0.13), Color(0.42, 0.56, 0.74))
	var btn_disabled := _make_9patch_box("res://assets/ui/btn_disabled_9patch.png", 4, 8.0, 4.0, Color(0.18, 0.22, 0.28, 0.72), Color(0.08, 0.10, 0.14), Color(0.22, 0.27, 0.34, 0.72))

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
		theme.set_color("font_outline_color", ctrl_type, Color(0.05, 0.08, 0.13, 0.85))
		theme.set_constant("outline_size", ctrl_type, 1)

	theme.set_color("font_color", "Label", Color(0.93, 0.96, 1.0))
	theme.set_color("font_shadow_color", "Label", Color(0.03, 0.05, 0.09, 0.85))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)

	var le_normal := _make_pixel_flat(Color(0.07, 0.11, 0.17, 0.94), Color(0.26, 0.38, 0.52, 1.0), 2, 8.0, 4.0)
	var le_focus := _make_pixel_flat(Color(0.09, 0.14, 0.21, 0.98), Color(0.84, 0.70, 0.34, 1.0), 2, 8.0, 4.0)
	theme.set_stylebox("normal", "LineEdit", le_normal)
	theme.set_stylebox("focus", "LineEdit", le_focus)
	theme.set_color("font_color", "LineEdit", Color(0.95, 0.97, 1.0))

	var pb_bg := _make_pixel_flat(Color(0.07, 0.11, 0.17, 0.94), Color(0.26, 0.38, 0.52, 1.0), 2, 0.0, 0.0)
	var pb_fill := _make_pixel_flat(Color(0.28, 0.70, 0.92, 0.95), Color(0.62, 0.88, 1.0, 0.75), 1, 0.0, 0.0)
	theme.set_stylebox("background", "ProgressBar", pb_bg)
	theme.set_stylebox("fill", "ProgressBar", pb_fill)

	var sl_track := _make_pixel_flat(Color(0.10, 0.16, 0.24, 0.95), Color(0.28, 0.40, 0.54, 1.0), 1, 0.0, 3.0)
	var sl_fill := _make_pixel_flat(Color(0.32, 0.72, 0.96, 0.92), Color(0.62, 0.86, 1.0, 0.70), 1, 0.0, 3.0)
	theme.set_stylebox("slider", "HSlider", sl_track)
	theme.set_stylebox("grabber_area", "HSlider", sl_fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", sl_fill)

	var pm_panel := _make_pixel_flat(Color(0.08, 0.13, 0.20, 0.98), Color(0.28, 0.42, 0.58, 1.0), 2, 6.0, 6.0)
	var pm_hover := _make_pixel_flat(Color(0.24, 0.40, 0.58, 0.92), Color(0.58, 0.78, 0.96, 0.85), 1, 6.0, 4.0)
	theme.set_stylebox("panel", "PopupMenu", pm_panel)
	theme.set_stylebox("hover", "PopupMenu", pm_hover)
	theme.set_color("font_color", "PopupMenu", Color(0.93, 0.96, 1.0))
	theme.set_color("font_hover_color", "PopupMenu", Color.WHITE)

	var hsep := StyleBoxLine.new()
	hsep.color = Color(0.28, 0.40, 0.54, 0.65)
	hsep.thickness = 1
	theme.set_stylebox("separator", "HSeparator", hsep)

	var vsep := StyleBoxLine.new()
	vsep.color = Color(0.28, 0.40, 0.54, 0.55)
	vsep.thickness = 1
	vsep.vertical = true
	theme.set_stylebox("separator", "VSeparator", vsep)

	return theme
