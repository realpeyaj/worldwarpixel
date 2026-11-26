extends SceneTree
## Headless helper to rasterize downloaded game-icons.net SVGs to transparent 512x512 RGBA PNGs.

const CUSTOM_DIR := "res://tools/cache/custom_icons"
const SVG_FILES := ["radar-dish.svg", "missile-launcher.svg", "missile-swarm.svg"]
const BG_PATH := '<path d="M0 0h512v512H0z" fill="#000" fill-opacity="1"></path>'


func _init() -> void:
	var ok_all := true
	for fname: String in SVG_FILES:
		var svg_path := "%s/%s" % [CUSTOM_DIR, fname]
		var out_path := "%s/%s" % [CUSTOM_DIR, fname.replace(".svg", ".png")]
		var raw: String = FileAccess.get_file_as_string(svg_path)
		if raw.is_empty():
			push_error("Failed to read SVG: %s" % svg_path)
			ok_all = false
			continue
		var clean: String = raw.replace(BG_PATH, "")
		var img := Image.new()
		var err: int = img.load_svg_from_string(clean, 1.0)
		if err != OK or img.is_empty():
			push_error("Failed to rasterize SVG %s (err=%d)" % [svg_path, err])
			ok_all = false
			continue
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		var abs_out := ProjectSettings.globalize_path(out_path)
		var serr: int = img.save_png(abs_out)
		if serr != OK:
			push_error("Failed to save PNG %s (err=%d)" % [abs_out, serr])
			ok_all = false
			continue
		var corner: Color = img.get_pixel(0, 0)
		print("[svg-raster] %s -> %s (%dx%d corner_a=%.3f)" % [fname, out_path, img.get_width(), img.get_height(), corner.a])
	quit(0 if ok_all else 1)
