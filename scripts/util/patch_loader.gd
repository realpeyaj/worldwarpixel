extends Node
## Autoload mounted first so drop-in runtime patches (*.pck) in <exe_dir>/patches/
## override base pack resources cleanly without replacing the engine executable.

var loaded_patches: PackedStringArray = PackedStringArray()


func _init() -> void:
	load_runtime_patches()


static func list_patch_files(patches_dir: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if patches_dir.is_empty() or not DirAccess.dir_exists_absolute(patches_dir):
		return out
	var dir := DirAccess.open(patches_dir)
	if dir == null:
		return out
	var names: Array[String] = []
	dir.list_dir_begin()
	while true:
		var fn: String = dir.get_next()
		if fn.is_empty():
			break
		if dir.current_is_dir():
			continue
		if fn.to_lower().ends_with(".pck"):
			names.append(fn)
	dir.list_dir_end()
	names.sort()
	for fn: String in names:
		out.append(patches_dir.path_join(fn))
	return out


func load_runtime_patches() -> int:
	loaded_patches.clear()
	if OS.has_feature("editor"):
		return 0
	var exe_dir: String = OS.get_executable_path().get_base_dir()
	var patches_dir: String = exe_dir.path_join("patches")
	var files: PackedStringArray = list_patch_files(patches_dir)
	for pck_path: String in files:
		if ProjectSettings.load_resource_pack(pck_path, true):
			loaded_patches.append(pck_path)
	return loaded_patches.size()
