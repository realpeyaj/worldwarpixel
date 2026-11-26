extends Node
## Centralized audio manager providing rich, smooth, non-clicky SFX,
## pooled playback, bus volume control, cooldown throttling, and ocean ambience ducking.

const SFX_DIR := "res://assets/audio/sfx/"
const AMBIENCE_PATH := "res://assets/audio/ambience/world_ocean_ambience.wav"
const THEME_PATH := "res://assets/audio/music/world_war_pixel_theme.wav"
const SFX_POOL_SIZE := 16

var _categories: Dictionary = {
	"ui_tap": ["drop_001.wav", "drop_002.wav"],
	"expand_launch": ["glass_001.wav", "glass_002.wav"],
	"build_placed": ["maximize_001.wav", "maximize_002.wav"],
	"upgrade_instant": ["upgrade_001.wav", "upgrade_002.wav"],
	"trade_gold": ["pluck_001.wav", "pluck_002.wav"],
	"victory": ["victory_fanfare.wav"],
	"error": ["error_001.wav"],
	"panel_open": ["open_001.wav"],
	"panel_close": ["close_001.wav"],
	"ship_depart": ["ship_depart.wav"],
	"bridge_connect": ["bridge_connect.wav"],
	"army_deploy": ["army_deploy.wav"],
	"army_order": ["switch_001.wav"],
	"battle_clash": ["battle_clash.wav"],
	"cannon_fire": ["cannon_fire.wav"],
	"missile_launch": ["missile_launch.wav"],
	"silo_nuke_launch": ["silo_nuke_launch.wav"],
	"sam_launch": ["sam_launch.wav"],
	"nuke_blast": ["nuke_blast.wav"],
	"sam_intercept": ["sam_intercept.wav"],
	"diplomacy_chime": ["diplomacy_chime.wav"],
	"betrayal_alert": ["betrayal_alert.wav"],
	"boat_bell": ["boat_bell.wav"],
	"target_lock": ["target_lock.wav"],
	"warship_horn": ["warship_horn.wav"],
	"troop_donate": ["troop_donate.wav"],
	"retreat_horn": ["retreat_horn.wav"],
	"land_conquer_pop": [
		"conquer_pop_001.wav",
		"conquer_pop_002.wav",
		"conquer_pop_003.wav",
		"conquer_pop_004.wav",
		"conquer_pop_005.wav",
		"conquer_pop_006.wav",
	],
	"invasion_warning": ["invasion_warning.wav"],
	"friend_request": ["friend_request.wav"],
	"defeat": ["defeat_drums.wav"],
}

var _category_buses: Dictionary = {
	"ui_tap": "UI",
	"expand_launch": "SFX",
	"build_placed": "SFX",
	"upgrade_instant": "SFX",
	"trade_gold": "SFX",
	"victory": "SFX",
	"error": "UI",
	"panel_open": "UI",
	"panel_close": "UI",
	"ship_depart": "SFX",
	"bridge_connect": "SFX",
	"army_deploy": "SFX",
	"army_order": "UI",
	"battle_clash": "SFX",
	"cannon_fire": "SFX",
	"missile_launch": "SFX",
	"silo_nuke_launch": "SFX",
	"sam_launch": "SFX",
	"nuke_blast": "SFX",
	"sam_intercept": "SFX",
	"diplomacy_chime": "UI",
	"betrayal_alert": "UI",
	"boat_bell": "SFX",
	"target_lock": "UI",
	"warship_horn": "SFX",
	"troop_donate": "SFX",
	"retreat_horn": "UI",
	"land_conquer_pop": "SFX",
	"invasion_warning": "UI",
	"friend_request": "UI",
	"defeat": "SFX",
}

var _category_cooldown_ms: Dictionary = {
	"ui_tap": 45,
	"expand_launch": 90,
	"build_placed": 90,
	"upgrade_instant": 60,
	"trade_gold": 1200,
	"victory": 500,
	"error": 180,
	"panel_open": 80,
	"panel_close": 80,
	"ship_depart": 350,
	"bridge_connect": 300,
	"army_deploy": 140,
	"army_order": 90,
	"battle_clash": 900,
	"cannon_fire": 180,
	"missile_launch": 220,
	"silo_nuke_launch": 260,
	"sam_launch": 160,
	"nuke_blast": 400,
	"sam_intercept": 240,
	"diplomacy_chime": 250,
	"betrayal_alert": 600,
	"boat_bell": 180,
	"target_lock": 80,
	"warship_horn": 220,
	"troop_donate": 150,
	"retreat_horn": 180,
	"land_conquer_pop": 72,
	"invasion_warning": 2800,
	"friend_request": 500,
	"defeat": 800,
}

var _streams: Dictionary = {}
var _last_played_ms: Dictionary = {}
var _sfx_pool: Array[AudioStreamPlayer] = []
var _pool_cursor: int = 0
var _ambience_player: AudioStreamPlayer
var _music_player: AudioStreamPlayer
var _duck_tween: Tween
var _music_tween: Tween
var _music_duck_tween: Tween
var _is_muted: bool = false
var _is_headless: bool = false


func _ready() -> void:
	_is_headless = (DisplayServer.get_name() == "headless")
	_load_streams()
	_setup_players()
	if not _is_headless:
		call_deferred("_begin_ambience_after_startup")


func _begin_ambience_after_startup() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	await tree.create_timer(0.25).timeout
	if is_inside_tree():
		start_world_ambience()


func _exit_tree() -> void:
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	if _music_duck_tween != null and _music_duck_tween.is_valid():
		_music_duck_tween.kill()
	AudioServer.lock()
	if _ambience_player != null:
		_ambience_player.stop()
		_ambience_player.stream = null
	if _music_player != null:
		_music_player.stop()
		_music_player.stream = null
	for p: AudioStreamPlayer in _sfx_pool:
		p.stop()
		p.stream = null
	AudioServer.unlock()
	_streams.clear()


func _load_streams() -> void:
	for cat: String in _categories.keys():
		var loaded: Array[AudioStream] = []
		var files: Array = _categories[cat]
		for fname: String in files:
			var full_path: String = SFX_DIR + fname
			if ResourceLoader.exists(full_path):
				var stream: AudioStream = load(full_path)
				if stream != null:
					loaded.append(stream)
		_streams[cat] = loaded


func _setup_players() -> void:
	for i in range(SFX_POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.name = "SFXPlayer_%d" % i
		player.bus = &"SFX"
		add_child(player)
		_sfx_pool.append(player)

	_ambience_player = AudioStreamPlayer.new()
	_ambience_player.name = "AmbiencePlayer"
	_ambience_player.bus = &"Ambience"
	_ambience_player.volume_db = -24.0
	_ambience_player.finished.connect(_on_ambience_finished)
	add_child(_ambience_player)

	if ResourceLoader.exists(AMBIENCE_PATH):
		var amb: AudioStream = load(AMBIENCE_PATH)
		if amb is AudioStreamWAV:
			var wav := amb as AudioStreamWAV
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = int(wav.get_length() * wav.mix_rate)
		_ambience_player.stream = amb

	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus = &"Music"
	_music_player.volume_db = -30.0
	_music_player.finished.connect(_on_music_finished)
	add_child(_music_player)

	if ResourceLoader.exists(THEME_PATH):
		var mus: AudioStream = load(THEME_PATH)
		if mus is AudioStreamWAV:
			var mwav := mus as AudioStreamWAV
			mwav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			mwav.loop_begin = 0
			mwav.loop_end = int(mwav.get_length() * mwav.mix_rate)
		_music_player.stream = mus


func _on_ambience_finished() -> void:
	if not _is_headless and _ambience_player.stream != null:
		_ambience_player.play()


func _on_music_finished() -> void:
	if not _is_headless and _music_player != null and _music_player.stream != null and _music_player.volume_db > -50.0:
		_music_player.play()


func start_world_ambience(fade_sec: float = 2.0) -> void:
	if _is_headless or _ambience_player.stream == null:
		return
	if not _ambience_player.playing:
		_ambience_player.volume_db = -30.0
		_ambience_player.play()
	var tw := create_tween()
	tw.tween_property(_ambience_player, "volume_db", -9.5, fade_sec)


func start_game_music(fade_sec: float = 2.5) -> void:
	if _is_headless or _music_player == null or _music_player.stream == null:
		return
	if _music_duck_tween != null and _music_duck_tween.is_valid():
		_music_duck_tween.kill()
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	if not _music_player.playing:
		_music_player.volume_db = -32.0
		_music_player.play()
	_music_tween = create_tween()
	_music_tween.tween_property(_music_player, "volume_db", -13.0, fade_sec)


func stop_game_music(fade_sec: float = 0.8) -> void:
	if _is_headless or _music_player == null:
		return
	if _music_duck_tween != null and _music_duck_tween.is_valid():
		_music_duck_tween.kill()
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	if not _music_player.playing:
		return
	_music_tween = create_tween()
	_music_tween.tween_property(_music_player, "volume_db", -56.0, fade_sec)
	_music_tween.tween_callback(_music_player.stop)


func play_sfx(category: String, volume_db: float = -8.0, pitch_center: float = 1.0, pitch_jitter: float = 0.03) -> void:
	if _is_headless or _is_muted:
		return
	if not _streams.has(category):
		return
	var variants: Array = _streams[category]
	if variants.is_empty():
		return

	var now: int = Time.get_ticks_msec()
	var cooldown: int = int(_category_cooldown_ms.get(category, 0))
	var prev: int = int(_last_played_ms.get(category, -10000))
	if now - prev < cooldown:
		return
	_last_played_ms[category] = now

	var player: AudioStreamPlayer = null
	for p_cand: AudioStreamPlayer in _sfx_pool:
		if not p_cand.playing:
			player = p_cand
			break
	if player == null:
		player = _sfx_pool[_pool_cursor]
		_pool_cursor = (_pool_cursor + 1) % _sfx_pool.size()
	player.stream = variants[randi() % variants.size()]
	player.bus = StringName(_category_buses.get(category, "SFX"))
	player.volume_db = volume_db + randf_range(-0.6, 0.4)
	player.pitch_scale = pitch_center + randf_range(-pitch_jitter, pitch_jitter)
	player.play()


func play_ui_tap() -> void:
	play_sfx("ui_tap", -11.0, 0.96, 0.03)


func play_expand_launch() -> void:
	play_sfx("expand_launch", -9.0, 0.94, 0.03)


func play_build_placed() -> void:
	play_sfx("build_placed", -8.0, 0.95, 0.02)


func play_upgrade_instant(level: int) -> void:
	var pitch: float = 0.92 + clampf(float(level) * 0.032, 0.0, 0.36)
	play_sfx("upgrade_instant", -7.0, pitch, 0.015)


func play_trade_gold() -> void:
	play_sfx("trade_gold", -16.0, 1.0, 0.04)


func play_ship_depart() -> void:
	play_sfx("ship_depart", -12.0, 0.98, 0.03)


func play_bridge_connect() -> void:
	play_sfx("bridge_connect", -10.0, 1.0, 0.02)


func play_army_deploy() -> void:
	play_sfx("army_deploy", -9.0, 0.96, 0.03)


func play_army_order() -> void:
	play_sfx("army_order", -12.0, 0.95, 0.03)


func play_battle_clash() -> void:
	play_sfx("battle_clash", -15.0, 0.95, 0.05)


func play_panel_open() -> void:
	play_sfx("panel_open", -13.0, 1.0, 0.02)


func play_panel_close() -> void:
	play_sfx("panel_close", -13.0, 1.0, 0.02)


func play_victory() -> void:
	play_sfx("victory", -5.0, 1.0, 0.01)
	duck_ambience(1.4, -8.0)
	duck_music(1.6, -5.0)


func play_error() -> void:
	play_sfx("error", -11.0, 0.90, 0.02)
	duck_ambience(0.45, -4.0)


func play_cannon_fire() -> void:
	play_sfx("cannon_fire", -11.0, 0.96, 0.05)


func play_missile_launch() -> void:
	play_sfx("missile_launch", -8.0, 0.98, 0.04)


func play_silo_nuke_launch() -> void:
	play_sfx("silo_nuke_launch", -7.0, 0.98, 0.03)


func play_sam_launch() -> void:
	play_sfx("sam_launch", -9.5, 1.0, 0.04)


func play_nuke_blast() -> void:
	play_sfx("nuke_blast", -4.5, 0.95, 0.03)
	duck_ambience(1.3, -7.5)
	duck_music(1.4, -4.5)


func play_sam_intercept() -> void:
	play_sfx("sam_intercept", -9.0, 1.02, 0.03)


func play_diplomacy_chime() -> void:
	play_sfx("diplomacy_chime", -10.0, 1.0, 0.02)


func play_betrayal_alert() -> void:
	play_sfx("betrayal_alert", -7.0, 0.96, 0.02)
	duck_ambience(0.85, -5.0)
	duck_music(0.85, -3.5)


func play_boat_bell() -> void:
	play_sfx("boat_bell", -7.5, 1.0, 0.02)


func play_target_lock() -> void:
	play_sfx("target_lock", -9.0, 1.0, 0.02)


func play_warship_horn() -> void:
	play_sfx("warship_horn", -8.5, 0.98, 0.02)


func play_troop_donate() -> void:
	play_sfx("troop_donate", -9.5, 1.0, 0.02)


func play_retreat_horn() -> void:
	play_sfx("retreat_horn", -10.5, 1.0, 0.02)


func play_land_conquer_pop(cells_claimed: int = 1, is_contested: bool = false) -> void:
	var vol_db: float = (-7.2 if is_contested else -8.5) + (0.5 if cells_claimed >= 5 else 0.0)
	var pitch_c: float = 0.96 if is_contested else 1.03
	play_sfx("land_conquer_pop", vol_db, pitch_c, 0.08)


func play_under_attack_warning() -> void:
	play_sfx("invasion_warning", -8.5, 1.0, 0.015)
	duck_music(0.75, -3.0)


func play_friend_request() -> void:
	play_sfx("friend_request", -8.0, 1.0, 0.015)


func play_defeat() -> void:
	play_sfx("defeat", -5.0, 1.0, 0.01)
	duck_ambience(1.6, -8.0)
	duck_music(1.8, -5.5)


func duck_ambience(duration_sec: float = 0.7, duck_offset_db: float = -6.0) -> void:
	if _is_headless or _ambience_player == null:
		return
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.tween_property(_ambience_player, "volume_db", -9.5 + duck_offset_db, 0.08)
	_duck_tween.tween_interval(duration_sec)
	_duck_tween.tween_property(_ambience_player, "volume_db", -9.5, 0.45)


func duck_music(duration_sec: float = 1.0, duck_offset_db: float = -4.5) -> void:
	if _is_headless or _music_player == null or not _music_player.playing or _music_player.volume_db <= -35.0:
		return
	if _music_duck_tween != null and _music_duck_tween.is_valid():
		_music_duck_tween.kill()
	_music_duck_tween = create_tween()
	_music_duck_tween.tween_property(_music_player, "volume_db", clampf(-13.0 + duck_offset_db, -40.0, 0.0), 0.08)
	_music_duck_tween.tween_interval(duration_sec)
	_music_duck_tween.tween_property(_music_player, "volume_db", -13.0, 0.55)


func set_bus_volume(bus_name: String, linear: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var clamped: float = clampf(linear, 0.0001, 1.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(clamped))
	AudioServer.set_bus_mute(idx, linear <= 0.001)


func get_bus_volume(bus_name: String) -> float:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0 or AudioServer.is_bus_mute(idx):
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(idx))


func set_muted(muted: bool) -> void:
	_is_muted = muted
	var master_idx: int = AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		AudioServer.set_bus_mute(master_idx, muted)


func is_muted() -> bool:
	return _is_muted
