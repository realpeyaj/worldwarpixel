class_name GifDecoder
extends RefCounted
## Pure-GDScript GIF87a/GIF89a decoder producing square-cropped 64x64 frames + horizontal strip PNG.

const MAX_DEFAULT_FRAMES := 16


static func load_avatar_from_file(path: String, target_size: int = 64) -> Dictionary:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return {"ok": false, "error": "Unable to read image file."}

	if bytes.size() >= 6:
		var sig: String = bytes.slice(0, 6).get_string_from_ascii()
		if sig == "GIF87a" or sig == "GIF89a":
			return decode_gif_bytes(bytes, target_size, MAX_DEFAULT_FRAMES)

	var img: Image = Image.load_from_file(path)
	if img == null or img.is_empty():
		return {"ok": false, "error": "Unsupported image format."}
	var sq: Image = _crop_and_resize_square(img, target_size)
	var tex: ImageTexture = ImageTexture.create_from_image(sq)
	return {
		"ok": true,
		"frames": [tex],
		"frame_count": 1,
		"delay_ms": 100,
		"strip_image": sq,
		"raw_upload_bytes": sq.save_png_to_buffer(),
		"error": "",
	}


static func decode_gif_bytes(data: PackedByteArray, target_size: int = 64, max_frames: int = MAX_DEFAULT_FRAMES) -> Dictionary:
	if data.size() < 14:
		return {"ok": false, "error": "GIF too small."}
	var sig: String = data.slice(0, 6).get_string_from_ascii()
	if sig != "GIF87a" and sig != "GIF89a":
		return {"ok": false, "error": "Not a valid GIF header."}

	var width: int = int(data[6]) | (int(data[7]) << 8)
	var height: int = int(data[8]) | (int(data[9]) << 8)
	if width <= 0 or height <= 0 or width > 2048 or height > 2048:
		return {"ok": false, "error": "Invalid GIF dimensions."}

	var packed: int = int(data[10])
	var has_gct: bool = (packed & 0x80) != 0
	var gct_size: int = 1 << ((packed & 0x07) + 1)
	var bg_index: int = int(data[11])
	var pos: int = 13

	var gct := PackedByteArray()
	if has_gct:
		if pos + gct_size * 3 > data.size():
			return {"ok": false, "error": "Truncated GIF global palette."}
		gct = data.slice(pos, pos + gct_size * 3)
		pos += gct_size * 3

	var canvas := Image.create(width, height, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0, 0, 0, 0))
	var prev_canvas := canvas.duplicate() as Image

	var disposal: int = 0
	var has_trans: bool = false
	var trans_idx: int = -1
	var delay_cs: int = 10

	var composed_frames: Array[Image] = []
	var frame_delays_ms: Array[int] = []

	while pos < data.size():
		var marker: int = int(data[pos])
		pos += 1
		if marker == 0x3B:
			break
		elif marker == 0x21:
			if pos >= data.size():
				break
			var ext_label: int = int(data[pos])
			pos += 1
			if ext_label == 0xF9 and pos + 5 <= data.size():
				var block_sz: int = int(data[pos])
				pos += 1
				if block_sz == 4 and pos + 4 < data.size():
					var gce_packed: int = int(data[pos])
					disposal = (gce_packed >> 2) & 0x07
					has_trans = (gce_packed & 0x01) != 0
					delay_cs = int(data[pos + 1]) | (int(data[pos + 2]) << 8)
					trans_idx = int(data[pos + 3])
				pos += block_sz
				if pos < data.size() and int(data[pos]) == 0:
					pos += 1
			else:
				while pos < data.size():
					var sub_len: int = int(data[pos])
					pos += 1
					if sub_len == 0:
						break
					pos += sub_len
		elif marker == 0x2C:
			if pos + 9 > data.size():
				break
			var ix: int = int(data[pos]) | (int(data[pos + 1]) << 8)
			var iy: int = int(data[pos + 2]) | (int(data[pos + 3]) << 8)
			var iw: int = int(data[pos + 4]) | (int(data[pos + 5]) << 8)
			var ih: int = int(data[pos + 6]) | (int(data[pos + 7]) << 8)
			var ipacked: int = int(data[pos + 8])
			pos += 9

			var has_lct: bool = (ipacked & 0x80) != 0
			var interlaced: bool = (ipacked & 0x40) != 0
			var lct_size: int = 1 << ((ipacked & 0x07) + 1)
			var palette := gct
			if has_lct:
				if pos + lct_size * 3 > data.size():
					break
				palette = data.slice(pos, pos + lct_size * 3)
				pos += lct_size * 3

			if pos >= data.size():
				break
			var min_code_size: int = int(data[pos])
			pos += 1
			if min_code_size < 2 or min_code_size > 11:
				return {"ok": false, "error": "Unsupported GIF LZW code size."}

			var lzw_bytes := PackedByteArray()
			while pos < data.size():
				var sub_sz: int = int(data[pos])
				pos += 1
				if sub_sz == 0:
					break
				var end_pos: int = mini(pos + sub_sz, data.size())
				lzw_bytes.append_array(data.slice(pos, end_pos))
				pos = end_pos

			if iw <= 0 or ih <= 0:
				continue
			if disposal == 3:
				prev_canvas = canvas.duplicate() as Image

			var indices: PackedInt32Array = _lzw_decode(lzw_bytes, min_code_size, iw * ih)
			_blit_frame(canvas, palette, indices, ix, iy, iw, ih, has_trans, trans_idx, interlaced)
			composed_frames.append(_crop_and_resize_square(canvas, target_size))
			var d_ms: int = delay_cs * 10 if delay_cs > 0 else 100
			frame_delays_ms.append(clampi(d_ms, 40, 1000))

			if disposal == 2:
				var clear_col := Color(0, 0, 0, 0)
				if not has_trans and bg_index >= 0 and bg_index * 3 + 2 < gct.size():
					clear_col = Color8(int(gct[bg_index * 3]), int(gct[bg_index * 3 + 1]), int(gct[bg_index * 3 + 2]), 255)
				canvas.fill_rect(Rect2i(ix, iy, iw, ih), clear_col)
			elif disposal == 3:
				canvas = prev_canvas.duplicate() as Image

			disposal = 0
			has_trans = false
			trans_idx = -1
			delay_cs = 10
		else:
			break

	if composed_frames.is_empty():
		return {"ok": false, "error": "No valid image frames found in GIF."}

	var sampled: Array[Image] = []
	var sampled_delays: Array[int] = []
	var total: int = composed_frames.size()
	if total <= max_frames:
		sampled = composed_frames
		sampled_delays = frame_delays_ms
	else:
		for i in range(max_frames):
			var idx: int = int(floor(float(i) * float(total - 1) / float(max_frames - 1)))
			sampled.append(composed_frames[idx])
			sampled_delays.append(frame_delays_ms[idx])

	var delay_sum := 0
	for d in sampled_delays:
		delay_sum += d
	var avg_delay: int = clampi(int(round(float(delay_sum) / float(maxi(sampled_delays.size(), 1)))), 40, 1000)

	var textures: Array[ImageTexture] = []
	var strip := Image.create(target_size * sampled.size(), target_size, false, Image.FORMAT_RGBA8)
	for fi in range(sampled.size()):
		var fimg: Image = sampled[fi]
		textures.append(ImageTexture.create_from_image(fimg))
		strip.blit_rect(fimg, Rect2i(0, 0, target_size, target_size), Vector2i(fi * target_size, 0))

	return {
		"ok": true,
		"frames": textures,
		"frame_count": textures.size(),
		"delay_ms": avg_delay,
		"strip_image": strip,
		"raw_upload_bytes": data if data.size() <= 1572864 else strip.save_png_to_buffer(),
		"error": "",
	}


static func textures_from_strip_image(strip_img: Image, frame_count: int) -> Array[ImageTexture]:
	var out: Array[ImageTexture] = []
	if strip_img == null or strip_img.is_empty():
		return out
	var n: int = maxi(frame_count, 1)
	var fw: int = maxi(1, int(strip_img.get_width() / n))
	var fh: int = strip_img.get_height()
	if n == 1:
		out.append(ImageTexture.create_from_image(strip_img))
		return out
	for i in range(n):
		var sub := Image.create(fw, fh, false, Image.FORMAT_RGBA8)
		sub.blit_rect(strip_img, Rect2i(i * fw, 0, fw, fh), Vector2i.ZERO)
		out.append(ImageTexture.create_from_image(sub))
	return out


static func textures_from_strip_b64(b64: String, frame_count: int) -> Array[ImageTexture]:
	if b64.is_empty():
		return []
	var raw: PackedByteArray = Marshalls.base64_to_raw(b64)
	if raw.is_empty():
		return []
	var img := Image.new()
	if img.load_png_from_buffer(raw) != OK:
		return []
	return textures_from_strip_image(img, frame_count)


static func _crop_and_resize_square(src: Image, target_size: int) -> Image:
	var img: Image = src.duplicate() as Image
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w: int = img.get_width()
	var h: int = img.get_height()
	var side: int = mini(w, h)
	if w != h and side > 0:
		var rx: int = (w - side) / 2
		var ry: int = (h - side) / 2
		var cropped := Image.create(side, side, false, Image.FORMAT_RGBA8)
		cropped.blit_rect(img, Rect2i(rx, ry, side, side), Vector2i.ZERO)
		img = cropped
	if img.get_width() != target_size or img.get_height() != target_size:
		img.resize(target_size, target_size, Image.INTERPOLATE_LANCZOS)
	return img


static func _lzw_decode(stream: PackedByteArray, min_code_size: int, expected_pixels: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(expected_pixels)
	out.fill(0)

	var clear_code: int = 1 << min_code_size
	var eoi_code: int = clear_code + 1
	var code_size: int = min_code_size + 1
	var next_code: int = eoi_code + 1

	var dict_prefix := PackedInt32Array()
	var dict_suffix := PackedInt32Array()
	dict_prefix.resize(4096)
	dict_suffix.resize(4096)
	for i in range(clear_code):
		dict_prefix[i] = -1
		dict_suffix[i] = i

	var bit_pos := 0
	var total_bits := stream.size() * 8
	var out_idx := 0
	var prev_code := -1
	var stack := PackedInt32Array()
	stack.resize(4096)

	while bit_pos + code_size <= total_bits and out_idx < expected_pixels:
		var code := 0
		for b in range(code_size):
			var bp: int = bit_pos + b
			var byte_v: int = int(stream[bp >> 3])
			if ((byte_v >> (bp & 7)) & 1) != 0:
				code |= (1 << b)
		bit_pos += code_size

		if code == clear_code:
			code_size = min_code_size + 1
			next_code = eoi_code + 1
			prev_code = -1
			continue
		if code == eoi_code:
			break

		var in_code: int = code
		var sp := 0
		if code == next_code and prev_code >= 0:
			var cur := prev_code
			while cur >= clear_code and sp < 4095:
				stack[sp] = dict_suffix[cur]
				sp += 1
				cur = dict_prefix[cur]
			var first_char: int = dict_suffix[cur] if cur >= 0 else 0
			# Emit stack reversed + first_char
			if sp < 4096:
				stack[sp] = first_char
				sp += 1
			# Reorder so stack emits [prev_seq..., first_char]
			for si in range(sp - 1, -1, -1):
				if out_idx < expected_pixels:
					out[out_idx] = stack[si]
					out_idx += 1
			if out_idx < expected_pixels:
				out[out_idx] = first_char
				out_idx += 1
			if next_code < 4096:
				dict_prefix[next_code] = prev_code
				dict_suffix[next_code] = first_char
				next_code += 1
		elif code < next_code:
			var cur: int = code
			while cur >= clear_code and sp < 4095:
				stack[sp] = dict_suffix[cur]
				sp += 1
				cur = dict_prefix[cur]
			var first_char: int = dict_suffix[cur] if cur >= 0 else 0
			stack[sp] = first_char
			sp += 1
			for si in range(sp - 1, -1, -1):
				if out_idx < expected_pixels:
					out[out_idx] = stack[si]
					out_idx += 1
			if prev_code >= 0 and next_code < 4096:
				dict_prefix[next_code] = prev_code
				dict_suffix[next_code] = first_char
				next_code += 1
		else:
			break

		if next_code == (1 << code_size) and code_size < 12:
			code_size += 1
		prev_code = in_code

	return out


static func _blit_frame(canvas: Image, palette: PackedByteArray, indices: PackedInt32Array, ix: int, iy: int, iw: int, ih: int, has_trans: bool, trans_idx: int, interlaced: bool) -> void:
	var cw: int = canvas.get_width()
	var ch: int = canvas.get_height()
	var pal_len: int = palette.size()
	var y_order := PackedInt32Array()
	y_order.resize(ih)
	if not interlaced:
		for y in range(ih):
			y_order[y] = y
	else:
		var k := 0
		for pass_spec: Array in [[0, 8], [4, 8], [2, 4], [1, 2]]:
			var y: int = int(pass_spec[0])
			var step: int = int(pass_spec[1])
			while y < ih:
				y_order[k] = y
				k += 1
				y += step

	var idx := 0
	for row_i in range(ih):
		var dy: int = iy + y_order[row_i]
		for col_i in range(iw):
			var cidx: int = int(indices[idx]) if idx < indices.size() else 0
			idx += 1
			if has_trans and cidx == trans_idx:
				continue
			var dx: int = ix + col_i
			if dx < 0 or dx >= cw or dy < 0 or dy >= ch:
				continue
			var p_off: int = cidx * 3
			if p_off + 2 < pal_len:
				canvas.set_pixel(dx, dy, Color8(int(palette[p_off]), int(palette[p_off + 1]), int(palette[p_off + 2]), 255))
