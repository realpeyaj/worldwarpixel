class_name GameHUD
extends CanvasLayer
## Modern, minimal strategy interface for Free-World expansion, Gold economy, and maritime infrastructure.

signal map_mode_toggled(political_enabled: bool)
signal reset_view_requested
signal build_mode_selected(mode: String)
signal upgrade_structure_requested(structure_id: int)
signal cancel_expansion_requested(expansion_id: int)
signal cancel_ship_requested(ship_id: int)
signal build_warship_requested(port_id: int)
signal missile_mode_selected(kind: String)
signal radial_attack_requested(cell: Vector2i)
signal radial_build_requested(s_type: String, cell: Vector2i)
signal radial_missile_requested(kind: String, cell: Vector2i)
signal radial_warship_requested(cell: Vector2i)
signal request_alliance_requested(target_nation_id: int)
signal respond_alliance_requested(from_nation_id: int, accept: bool)
signal break_alliance_requested(target_nation_id: int)
signal toggle_embargo_requested(target_nation_id: int)
signal donate_gold_requested(target_nation_id: int, amount: float)
signal donate_troops_requested(target_nation_id: int, ratio: float)
signal close_structure_requested
signal play_match_requested
signal new_match_requested
signal mp_connect_requested(ws_url: String, room_code: String, player_name: String)
signal mp_disconnect_requested
signal mp_start_match_requested(ai_count: int)
signal friend_invite_requested(friend_name: String, room_code: String)
signal menu_visibility_changed(is_open: bool)
signal quit_requested

const MAX_LEADERBOARD_ROWS := 7
const FRIENDS_SAVE_PATH := "user://friends.cfg"
const PROFILE_SAVE_PATH := "user://player_profile.cfg"
const SERVER_REGIONS := [
	{"name": "Manila, PH", "url": "ws://151.242.136.36:30041/ws"},
]

var _tex_logo := preload("res://assets/sprites/logo_world_war_pixel.png")
var _tex_play := preload("res://assets/sprites/icon_play.png")
var _tex_back := preload("res://assets/sprites/icon_back.png")
var _tex_close := preload("res://assets/sprites/icon_close.png")
var _tex_friends := preload("res://assets/sprites/icon_friends.png")
var _tex_multiplayer := preload("res://assets/sprites/icon_multiplayer.png")
var _tex_audio := preload("res://assets/sprites/icon_audio.png")
var _tex_attack := preload("res://assets/sprites/icon_attack.png")
var _tex_town := preload("res://assets/sprites/icon_town.png")
var _tex_town_mask := preload("res://assets/sprites/icon_town_mask.png")
var _tex_port := preload("res://assets/sprites/icon_port.png")
var _tex_port_mask := preload("res://assets/sprites/icon_port_mask.png")
var _tex_factory := preload("res://assets/sprites/icon_factory.png")
var _tex_factory_mask := preload("res://assets/sprites/icon_factory_mask.png")
var _tex_defense := preload("res://assets/sprites/icon_defense_post.png")
var _tex_defense_mask := preload("res://assets/sprites/icon_defense_post_mask.png")
var _tex_silo := preload("res://assets/sprites/icon_silo.png")
var _tex_silo_mask := preload("res://assets/sprites/icon_silo_mask.png")
var _tex_sam := preload("res://assets/sprites/icon_sam.png")
var _tex_sam_mask := preload("res://assets/sprites/icon_sam_mask.png")
var _tex_warship := preload("res://assets/sprites/icon_warship.png")
var _tex_warship_mask := preload("res://assets/sprites/icon_warship_mask.png")
var _tex_missile := preload("res://assets/sprites/icon_missile.png")
var _tex_diplomacy := preload("res://assets/sprites/icon_diplomacy.png")
var _tex_wifi := preload("res://assets/sprites/icon_wifi.png")
var _tex_banner := preload("res://assets/sprites/icon_banner.png")
var _tex_banner_mask := preload("res://assets/sprites/icon_banner_mask.png")
var _tex_upgrade := preload("res://assets/sprites/icon_upgrade.png")
var _tex_boat := preload("res://assets/sprites/icon_boat.png")
var _tex_coin := preload("res://assets/sprites/icon_coin.png")
var _tex_troops := preload("res://assets/sprites/icon_troops.png")

var _world_state: WorldState
var _selected_structure_id: int = 0
var _selected_dip_nation_id: int = 0
var _pending_alliance_from_id: int = 0
var _radial_cell: Vector2i = Vector2i(-1, -1)
var _radial_world_pos: Vector2 = Vector2.ZERO
var _political_mode: bool = true
var _leaderboard_minimized: bool = false
var _hotkeys_enabled: bool = true
var _commit_ratio: float = 0.35
var _toast_timer: float = 0.0
var _build_mode: String = ""
var _missile_mode: String = ""
var _lb_pool: Array[Dictionary] = []
var _lb_dirty: bool = false
var _exp_dirty: bool = false
var _lb_timer: float = 0.0
var _exp_timer: float = 0.0
var _last_dock_cost_key: int = -1
var _current_room_code: String = ""
var _pending_invite_friend: String = ""
var _pending_join_invite_code: String = ""
var _friends: Array[String] = []
var _is_spectating: bool = false
var _friends_return_to: String = "menu"
var _icon_close_16: ImageTexture
var _icon_play_16: ImageTexture

@onready var root_control: Control = $Root
@onready var top_bar: PanelContainer = $Root/TopBar
@onready var clock_label: Label = $Root/TopBar/HBox/ClockLabel
@onready var gold_icon: TextureRect = $Root/TopBar/HBox/GoldIcon
@onready var gold_label: Label = $Root/TopBar/HBox/GoldLabel
@onready var troops_icon: TextureRect = $Root/TopBar/HBox/TroopsIcon
@onready var troops_label: Label = $Root/TopBar/HBox/TroopsLabel
@onready var world_pct_label: Label = $Root/TopBar/HBox/WorldPctLabel
@onready var map_mode_btn: Button = $Root/TopBar/HBox/MapModeBtn
@onready var reset_view_btn: Button = $Root/TopBar/HBox/ResetViewBtn
@onready var hotkeys_btn: Button = $Root/TopBar/HBox/HotkeysBtn
@onready var audio_btn: Button = $Root/TopBar/HBox/AudioBtn
@onready var menu_btn: Button = $Root/TopBar/HBox/MenuBtn

@onready var spawn_banner: PanelContainer = $Root/SpawnBanner
@onready var nation_name_edit: LineEdit = $Root/SpawnBanner/VBox/Row/NameEdit
@onready var ai_count_option: OptionButton = $Root/SpawnBanner/VBox/Row/AiOption

@onready var action_dock: PanelContainer = $Root/ActionDock
@onready var expand_btn: Button = $Root/ActionDock/HBox/ExpandBtn
@onready var town_btn: Button = $Root/ActionDock/HBox/TownBtn
@onready var port_btn: Button = $Root/ActionDock/HBox/PortBtn
@onready var factory_btn: Button = $Root/ActionDock/HBox/FactoryBtn
@onready var defense_btn: Button = $Root/ActionDock/HBox/DefenseBtn
@onready var silo_btn: Button = $Root/ActionDock/HBox/SiloBtn
@onready var sam_btn: Button = $Root/ActionDock/HBox/SamBtn
@onready var warship_btn: Button = $Root/ActionDock/HBox/WarshipBtn
@onready var atom_dock_btn: Button = $Root/ActionDock/HBox/AtomDockBtn
@onready var hbomb_dock_btn: Button = $Root/ActionDock/HBox/HbombDockBtn
@onready var mirv_dock_btn: Button = $Root/ActionDock/HBox/MirvDockBtn
@onready var commit_sep: VSeparator = $Root/ActionDock/HBox/CommitSep
@onready var commit_box: HBoxContainer = $Root/ActionDock/HBox/CommitBox
@onready var commit_20_btn: Button = $Root/ActionDock/HBox/CommitBox/Commit20Btn
@onready var commit_35_btn: Button = $Root/ActionDock/HBox/CommitBox/Commit35Btn
@onready var commit_50_btn: Button = $Root/ActionDock/HBox/CommitBox/Commit50Btn
@onready var commit_75_btn: Button = $Root/ActionDock/HBox/CommitBox/Commit75Btn

@onready var hover_card: PanelContainer = $Root/HoverCard
@onready var hover_title: Label = $Root/HoverCard/VBox/Title
@onready var hover_sub: Label = $Root/HoverCard/VBox/Sub
@onready var hover_owner_dot: ColorRect = $Root/HoverCard/VBox/OwnerRow/Dot
@onready var hover_owner_lbl: Label = $Root/HoverCard/VBox/OwnerRow/OwnerLbl

@onready var structure_panel: PanelContainer = $Root/RightStack/StructurePanel
@onready var st_icon: TextureRect = $Root/RightStack/StructurePanel/VBox/Header/StIcon
@onready var st_title: Label = $Root/RightStack/StructurePanel/VBox/Header/Title
@onready var st_close_btn: Button = $Root/RightStack/StructurePanel/VBox/Header/CloseBtn
@onready var st_sub: Label = $Root/RightStack/StructurePanel/VBox/SubLabel
@onready var st_stats: Label = $Root/RightStack/StructurePanel/VBox/StatsLabel
@onready var st_next_lbl: Label = $Root/RightStack/StructurePanel/VBox/NextLabel
@onready var st_prog_bar: ProgressBar = $Root/RightStack/StructurePanel/VBox/ProgressBar
@onready var st_upgrade_btn: Button = $Root/RightStack/StructurePanel/VBox/UpgradeBtn
@onready var st_action_row: HBoxContainer = $Root/RightStack/StructurePanel/VBox/ActionRow
@onready var st_warship_btn: Button = $Root/RightStack/StructurePanel/VBox/ActionRow/BuildWarshipBtn
@onready var st_atom_btn: Button = $Root/RightStack/StructurePanel/VBox/ActionRow/AtomBtn
@onready var st_hbomb_btn: Button = $Root/RightStack/StructurePanel/VBox/ActionRow/HbombBtn
@onready var st_mirv_btn: Button = $Root/RightStack/StructurePanel/VBox/ActionRow/MirvBtn

@onready var expansions_panel: PanelContainer = $Root/RightStack/ExpansionsPanel
@onready var exp_rows: VBoxContainer = $Root/RightStack/ExpansionsPanel/VBox/Rows

@onready var diplomacy_panel: PanelContainer = $Root/RightStack/DiplomacyPanel
@onready var dip_dot: ColorRect = $Root/RightStack/DiplomacyPanel/VBox/Header/DipDot
@onready var dip_title: Label = $Root/RightStack/DiplomacyPanel/VBox/Header/DipTitle
@onready var dip_close_btn: Button = $Root/RightStack/DiplomacyPanel/VBox/Header/DipCloseBtn
@onready var dip_status_lbl: Label = $Root/RightStack/DiplomacyPanel/VBox/DipStatusLabel
@onready var ally_btn: Button = $Root/RightStack/DiplomacyPanel/VBox/BtnGrid/AllyBtn
@onready var embargo_btn: Button = $Root/RightStack/DiplomacyPanel/VBox/BtnGrid/EmbargoBtn
@onready var donate_gold_btn: Button = $Root/RightStack/DiplomacyPanel/VBox/BtnGrid/DonateGoldBtn
@onready var donate_troops_btn: Button = $Root/RightStack/DiplomacyPanel/VBox/BtnGrid/DonateTroopsBtn

@onready var alliance_banner: PanelContainer = $Root/AllianceBanner
@onready var alliance_prompt: Label = $Root/AllianceBanner/HBox/AlliancePrompt
@onready var alliance_accept_btn: Button = $Root/AllianceBanner/HBox/AcceptBtn
@onready var alliance_decline_btn: Button = $Root/AllianceBanner/HBox/DeclineBtn

@onready var radial_menu: Control = $Root/RadialMenu
@onready var radial_wheel: Control = $Root/RadialMenu/Wheel
@onready var radial_attack_btn: Button = $Root/RadialMenu/Wheel/RadialAttackBtn
@onready var radial_build_btn: Button = $Root/RadialMenu/Wheel/RadialBuildBtn
@onready var radial_warship_btn: Button = $Root/RadialMenu/Wheel/RadialWarshipBtn
@onready var radial_missile_btn: Button = $Root/RadialMenu/Wheel/RadialMissileBtn
@onready var radial_dip_btn: Button = $Root/RadialMenu/Wheel/RadialDipBtn
@onready var radial_info_btn: Button = $Root/RadialMenu/Wheel/RadialInfoBtn
@onready var radial_close_btn: Button = $Root/RadialMenu/Wheel/RadialCloseBtn
@onready var radial_sub_picker: PanelContainer = $Root/RadialMenu/SubPicker
@onready var radial_sub_hbox: HBoxContainer = $Root/RadialMenu/SubPicker/SubHBox

@onready var leaderboard_panel: PanelContainer = $Root/LeaderboardPanel
@onready var lb_toggle_btn: Button = $Root/LeaderboardPanel/VBox/Header/ToggleBtn
@onready var lb_body: VBoxContainer = $Root/LeaderboardPanel/VBox/Body
@onready var lb_claimed_lbl: Label = $Root/LeaderboardPanel/VBox/Body/ClaimedLabel
@onready var lb_rows: VBoxContainer = $Root/LeaderboardPanel/VBox/Body/Rows
@onready var lb_victory_lbl: Label = $Root/LeaderboardPanel/VBox/Body/VictoryBanner
@onready var world_min_btn: Button = $Root/WorldControlMinBtn

@onready var menu_overlay: ColorRect = $Root/MenuOverlay
@onready var menu_card: PanelContainer = $Root/MenuOverlay/Center/MenuCard
@onready var logo_rect: TextureRect = $Root/MenuOverlay/Center/MenuCard/VBox/LogoRect
@onready var menu_name_edit: LineEdit = $Root/MenuOverlay/Center/MenuCard/VBox/NameRow/MenuNameEdit
@onready var menu_ai_option: OptionButton = $Root/MenuOverlay/Center/MenuCard/VBox/AiRow/MenuAiOption
@onready var play_btn: Button = $Root/MenuOverlay/Center/MenuCard/VBox/PlayBtn
@onready var multiplayer_btn: Button = $Root/MenuOverlay/Center/MenuCard/VBox/SocialRow/MultiplayerBtn
@onready var friends_btn: Button = $Root/MenuOverlay/Center/MenuCard/VBox/SocialRow/FriendsBtn
@onready var new_match_btn: Button = $Root/MenuOverlay/Center/MenuCard/VBox/NewMatchBtn
@onready var menu_audio_btn: Button = $Root/MenuOverlay/Center/MenuCard/VBox/FooterRow/MenuAudioBtn
@onready var quit_btn: Button = $Root/MenuOverlay/Center/MenuCard/VBox/FooterRow/QuitBtn

@onready var mp_lobby_card: PanelContainer = $Root/MenuOverlay/Center/MpLobbyCard
@onready var server_value_label: Label = $Root/MenuOverlay/Center/MpLobbyCard/VBox/ServerRow/ServerValueLabel
@onready var server_option: OptionButton = $Root/MenuOverlay/Center/MpLobbyCard/VBox/ServerRow/ServerOption
@onready var conn_bar_icon: TextureRect = $Root/MenuOverlay/Center/MpLobbyCard/VBox/ServerRow/ConnBarIcon
@onready var conn_strength_label: Label = $Root/MenuOverlay/Center/MpLobbyCard/VBox/ServerRow/ConnStrengthLabel
@onready var mp_server_edit: LineEdit = $Root/MenuOverlay/Center/MpLobbyCard/VBox/ServerRow/MpServerEdit
@onready var assigned_code_label: Label = $Root/MenuOverlay/Center/MpLobbyCard/VBox/AssignedCodeRow/AssignedCodeLabel
@onready var copy_code_btn: Button = $Root/MenuOverlay/Center/MpLobbyCard/VBox/AssignedCodeRow/CopyCodeBtn
@onready var mp_room_edit: LineEdit = $Root/MenuOverlay/Center/MpLobbyCard/VBox/RoomRow/MpRoomEdit
@onready var create_room_btn: Button = $Root/MenuOverlay/Center/MpLobbyCard/VBox/BtnRow/CreateRoomBtn
@onready var mp_connect_btn: Button = $Root/MenuOverlay/Center/MpLobbyCard/VBox/BtnRow/MpConnectBtn
@onready var mp_disconnect_btn: Button = $Root/MenuOverlay/Center/MpLobbyCard/VBox/HeaderRow/MpDisconnectBtn
@onready var mp_friends_btn: Button = $Root/MenuOverlay/Center/MpLobbyCard/VBox/HeaderRow/MpFriendsBtn
@onready var mp_status_label: Label = $Root/MenuOverlay/Center/MpLobbyCard/VBox/MpStatusLabel
@onready var mp_players_label: Label = $Root/MenuOverlay/Center/MpLobbyCard/VBox/MpPlayersLabel
@onready var mp_start_btn: Button = $Root/MenuOverlay/Center/MpLobbyCard/VBox/MpStartBtn

@onready var friends_card: PanelContainer = $Root/MenuOverlay/Center/FriendsCard
@onready var friends_back_btn: Button = $Root/MenuOverlay/Center/FriendsCard/VBox/HeaderRow/FriendsBackBtn
@onready var friends_header_icon: TextureRect = $Root/MenuOverlay/Center/FriendsCard/VBox/HeaderRow/FriendsIcon
@onready var friend_name_edit: LineEdit = $Root/MenuOverlay/Center/FriendsCard/VBox/FriendAddRow/FriendNameEdit
@onready var add_friend_btn: Button = $Root/MenuOverlay/Center/FriendsCard/VBox/FriendAddRow/AddFriendBtn
@onready var friends_rows: VBoxContainer = $Root/MenuOverlay/Center/FriendsCard/VBox/FriendsScroll/FriendsRows
@onready var invite_row: HBoxContainer = $Root/MenuOverlay/Center/FriendsCard/VBox/InviteRow
@onready var invite_label: Label = $Root/MenuOverlay/Center/FriendsCard/VBox/InviteRow/InviteLabel
@onready var accept_invite_btn: Button = $Root/MenuOverlay/Center/FriendsCard/VBox/InviteRow/AcceptInviteBtn
@onready var dismiss_invite_btn: Button = $Root/MenuOverlay/Center/FriendsCard/VBox/InviteRow/DismissInviteBtn
@onready var friends_hint_label: Label = $Root/MenuOverlay/Center/FriendsCard/VBox/FriendsHintLabel

@onready var audio_popover: PanelContainer = $Root/AudioPopover
@onready var audio_close_btn: Button = $Root/AudioPopover/VBox/Header/AudioCloseBtn
@onready var mute_check: CheckButton = $Root/AudioPopover/VBox/MuteCheck
@onready var master_slider: HSlider = $Root/AudioPopover/VBox/MasterSlider
@onready var music_slider: HSlider = $Root/AudioPopover/VBox/MusicSlider
@onready var sfx_slider: HSlider = $Root/AudioPopover/VBox/SfxSlider
@onready var ambience_slider: HSlider = $Root/AudioPopover/VBox/AmbienceSlider

@onready var toast_panel: PanelContainer = $Root/ToastPanel
@onready var toast_label: Label = $Root/ToastPanel/ToastLabel
@onready var ping_badge: PanelContainer = $Root/PingBadge
@onready var ping_icon: TextureRect = $Root/PingBadge/HBox/PingIcon
@onready var ping_label: Label = $Root/PingBadge/HBox/PingLabel

@onready var victory_overlay: ColorRect = $Root/VictoryOverlay
@onready var victory_icon: TextureRect = $Root/VictoryOverlay/Center/VictoryCard/VBox/HeaderRow/VictoryIcon
@onready var victory_title: Label = $Root/VictoryOverlay/Center/VictoryCard/VBox/HeaderRow/VictoryTitle
@onready var victory_sub: Label = $Root/VictoryOverlay/Center/VictoryCard/VBox/VictorySub
@onready var victory_stats: Label = $Root/VictoryOverlay/Center/VictoryCard/VBox/VictoryStats
@onready var victory_new_match_btn: Button = $Root/VictoryOverlay/Center/VictoryCard/VBox/BtnRow/VictoryNewMatchBtn
@onready var victory_inspect_btn: Button = $Root/VictoryOverlay/Center/VictoryCard/VBox/BtnRow/VictoryInspectBtn

@onready var spectator_banner: PanelContainer = $Root/SpectatorBanner
@onready var spec_label: Label = $Root/SpectatorBanner/HBox/SpecLabel
@onready var spec_continue_btn: Button = $Root/SpectatorBanner/HBox/SpecContinueBtn
@onready var spec_new_match_btn: Button = $Root/SpectatorBanner/HBox/SpecNewMatchBtn


func _ready() -> void:
	root_control.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root_control.theme = ThemeFactory.build_strategy_theme()
	ThemeFactory.apply_panel_variant(top_bar, "dock_top")
	ThemeFactory.apply_panel_variant(action_dock, "dock_bottom")
	ThemeFactory.apply_panel_variant(ping_badge, "flat")
	_icon_close_16 = _make_pixel_icon(_tex_close, Color.WHITE, 14)
	_icon_play_16 = _make_pixel_icon(_tex_play, Color.WHITE, 14)
	var icon_back_16: ImageTexture = _make_pixel_icon(_tex_back, Color.WHITE, 14)
	var icon_friends_16: ImageTexture = _make_pixel_icon(_tex_friends, Color.WHITE, 16)
	var icon_mp_16: ImageTexture = _make_pixel_icon(_tex_multiplayer, Color.WHITE, 16)
	var icon_audio_16: ImageTexture = _make_pixel_icon(_tex_audio, Color.WHITE, 15)

	logo_rect.texture = _tex_logo
	logo_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	friends_header_icon.texture = icon_friends_16
	friends_header_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	hover_card.visible = false
	structure_panel.visible = false
	expansions_panel.visible = false
	diplomacy_panel.visible = false
	alliance_banner.visible = false
	radial_menu.visible = false
	radial_sub_picker.visible = false
	audio_popover.visible = false
	toast_panel.visible = false
	victory_overlay.visible = false
	spectator_banner.visible = false
	lb_victory_lbl.visible = false
	action_dock.visible = false
	spawn_banner.visible = false
	world_min_btn.visible = false
	new_match_btn.visible = false
	mp_lobby_card.visible = false
	friends_card.visible = false
	menu_card.visible = true
	menu_overlay.visible = true

	_apply_ui_variants_and_icons(icon_back_16, icon_friends_16, icon_mp_16, icon_audio_16)
	_populate_spawn_controls()
	_load_profile()
	_populate_server_regions()
	_load_friends()
	_init_leaderboard_pool()
	radial_wheel.draw.connect(_on_radial_wheel_draw)
	_apply_action_dock_icons(Color(0.32, 0.56, 0.90))
	for icon_ctrl: CanvasItem in [
		gold_icon, troops_icon, victory_icon, conn_bar_icon,
		expand_btn, town_btn, port_btn, factory_btn, defense_btn, silo_btn, sam_btn,
		warship_btn, atom_dock_btn, hbomb_dock_btn, mirv_dock_btn,
		st_icon, st_upgrade_btn, st_warship_btn, st_atom_btn, st_hbomb_btn, st_mirv_btn,
		ally_btn, embargo_btn, donate_gold_btn, donate_troops_btn,
		ping_icon, radial_attack_btn, radial_build_btn, radial_warship_btn, radial_missile_btn, radial_dip_btn, radial_info_btn,
	]:
		icon_ctrl.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	for pixel_ctrl: CanvasItem in [
		play_btn, multiplayer_btn, friends_btn, menu_audio_btn, quit_btn,
		mp_disconnect_btn, mp_friends_btn, mp_start_btn, friends_back_btn,
		accept_invite_btn, dismiss_invite_btn, st_close_btn, dip_close_btn,
		audio_close_btn, radial_close_btn, audio_btn,
	]:
		pixel_ctrl.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for dock_ctrl: Control in [
		gold_label, troops_label, world_pct_label, clock_label,
		map_mode_btn, reset_view_btn, hotkeys_btn, audio_btn, menu_btn,
		commit_20_btn, commit_35_btn, commit_50_btn, commit_75_btn,
	]:
		dock_ctrl.add_theme_font_size_override("font_size", 11)
	for slot_btn: Button in [
		expand_btn, town_btn, factory_btn, port_btn, defense_btn, silo_btn, sam_btn,
		warship_btn, atom_dock_btn, hbomb_dock_btn, mirv_dock_btn,
	]:
		slot_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		slot_btn.add_theme_font_size_override("font_size", 10)
		slot_btn.add_theme_constant_override("v_separation", 1)
		slot_btn.custom_minimum_size = Vector2(52, 38) if slot_btn == expand_btn else Vector2(46, 38)

	ping_icon.texture = _build_tinted_icon(_tex_wifi, null, Color.WHITE, 16, 16)
	conn_bar_icon.texture = ping_icon.texture
	update_ping(-1)
	_sync_hud_chrome_visibility()

	victory_new_match_btn.pressed.connect(func() -> void:
		AudioManager.play_ui_tap()
		victory_overlay.visible = false
		new_match_requested.emit()
	)
	victory_inspect_btn.pressed.connect(func() -> void:
		AudioManager.play_ui_tap()
		victory_overlay.visible = false
	)
	spec_continue_btn.pressed.connect(func() -> void:
		AudioManager.play_ui_tap()
		spectator_banner.visible = false
	)
	spec_new_match_btn.pressed.connect(func() -> void:
		AudioManager.play_ui_tap()
		spectator_banner.visible = false
		new_match_requested.emit()
	)

	map_mode_btn.pressed.connect(_on_map_mode_pressed)
	reset_view_btn.pressed.connect(func() -> void:
		AudioManager.play_ui_tap()
		reset_view_requested.emit()
	)
	hotkeys_btn.pressed.connect(toggle_hotkeys)
	menu_btn.pressed.connect(open_menu)
	audio_btn.pressed.connect(_toggle_audio_popover)
	menu_audio_btn.pressed.connect(_toggle_audio_popover)
	lb_toggle_btn.pressed.connect(_on_lb_toggle_pressed)
	world_min_btn.pressed.connect(_on_lb_toggle_pressed)

	st_close_btn.pressed.connect(func() -> void:
		AudioManager.play_panel_close()
		close_structure_requested.emit()
	)
	st_upgrade_btn.pressed.connect(func() -> void:
		if _selected_structure_id > 0:
			upgrade_structure_requested.emit(_selected_structure_id)
	)
	st_warship_btn.pressed.connect(func() -> void:
		if _selected_structure_id > 0:
			AudioManager.play_ui_tap()
			build_warship_requested.emit(_selected_structure_id)
	)
	st_atom_btn.pressed.connect(func() -> void: _select_missile_mode(MissileUnit.KIND_ATOM))
	st_hbomb_btn.pressed.connect(func() -> void: _select_missile_mode(MissileUnit.KIND_HYDROGEN))
	st_mirv_btn.pressed.connect(func() -> void: _select_missile_mode(MissileUnit.KIND_MIRV))

	dip_close_btn.pressed.connect(func() -> void:
		AudioManager.play_panel_close()
		_selected_dip_nation_id = 0
		diplomacy_panel.visible = false
	)
	ally_btn.pressed.connect(_on_ally_btn_pressed)
	embargo_btn.pressed.connect(func() -> void:
		if _selected_dip_nation_id > 0:
			AudioManager.play_ui_tap()
			toggle_embargo_requested.emit(_selected_dip_nation_id)
	)
	donate_gold_btn.pressed.connect(func() -> void:
		if _selected_dip_nation_id > 0:
			AudioManager.play_ui_tap()
			donate_gold_requested.emit(_selected_dip_nation_id, 100000.0)
	)
	donate_troops_btn.pressed.connect(func() -> void:
		if _selected_dip_nation_id > 0:
			AudioManager.play_ui_tap()
			donate_troops_requested.emit(_selected_dip_nation_id, 0.25)
	)

	alliance_accept_btn.pressed.connect(func() -> void: _respond_to_pending_alliance(true))
	alliance_decline_btn.pressed.connect(func() -> void: _respond_to_pending_alliance(false))

	radial_menu.gui_input.connect(_on_radial_bg_input)
	radial_close_btn.pressed.connect(close_radial_menu)
	radial_attack_btn.pressed.connect(_on_radial_attack_pressed)
	radial_build_btn.pressed.connect(_on_radial_build_pressed)
	radial_warship_btn.pressed.connect(_on_radial_warship_pressed)
	radial_missile_btn.pressed.connect(_on_radial_missile_pressed)
	radial_dip_btn.pressed.connect(_on_radial_dip_pressed)
	radial_info_btn.pressed.connect(_on_radial_info_pressed)

	expand_btn.pressed.connect(func() -> void: _select_build_mode(""))
	town_btn.pressed.connect(func() -> void: _select_build_mode(StructureData.TYPE_TOWN))
	factory_btn.pressed.connect(func() -> void: _select_build_mode(StructureData.TYPE_FACTORY))
	port_btn.pressed.connect(func() -> void: _select_build_mode(StructureData.TYPE_PORT))
	defense_btn.pressed.connect(func() -> void: _select_build_mode(StructureData.TYPE_DEFENSE_POST))
	silo_btn.pressed.connect(func() -> void: _select_build_mode(StructureData.TYPE_MISSILE_SILO))
	sam_btn.pressed.connect(func() -> void: _select_build_mode(StructureData.TYPE_SAM_LAUNCHER))
	warship_btn.pressed.connect(func() -> void: _select_build_mode("warship"))
	atom_dock_btn.pressed.connect(func() -> void: _select_missile_mode(MissileUnit.KIND_ATOM))
	hbomb_dock_btn.pressed.connect(func() -> void: _select_missile_mode(MissileUnit.KIND_HYDROGEN))
	mirv_dock_btn.pressed.connect(func() -> void: _select_missile_mode(MissileUnit.KIND_MIRV))

	commit_20_btn.pressed.connect(func() -> void: set_commit_ratio(0.20))
	commit_35_btn.pressed.connect(func() -> void: set_commit_ratio(0.35))
	commit_50_btn.pressed.connect(func() -> void: set_commit_ratio(0.50))
	commit_75_btn.pressed.connect(func() -> void: set_commit_ratio(0.75))

	play_btn.pressed.connect(_on_play_pressed)
	multiplayer_btn.pressed.connect(func() -> void:
		AudioManager.play_ui_tap()
		save_player_name(menu_name_edit.text)
		menu_card.visible = false
		friends_card.visible = false
		mp_lobby_card.visible = true
	)
	friends_btn.pressed.connect(func() -> void:
		save_player_name(menu_name_edit.text)
		open_friends_page("menu")
	)
	mp_friends_btn.pressed.connect(func() -> void:
		save_player_name(menu_name_edit.text)
		open_friends_page("mp_lobby")
	)
	friends_back_btn.pressed.connect(_on_friends_back_pressed)
	create_room_btn.pressed.connect(func() -> void:
		AudioManager.play_ui_tap()
		mp_room_edit.text = ""
		mp_status_label.text = "Creating Room on %s..." % get_selected_server_name()
		var cfg: Dictionary = get_spawn_config()
		save_player_name(str(cfg.get("name", "")))
		mp_connect_requested.emit(get_mp_server_url(), "", str(cfg.get("name", "Commander")))
	)
	mp_connect_btn.pressed.connect(func() -> void:
		AudioManager.play_ui_tap()
		var code_in: String = mp_room_edit.text.strip_edges().to_upper()
		mp_status_label.text = ("Joining Room %s on %s..." % [code_in, get_selected_server_name()]) if not code_in.is_empty() else ("Creating Room on %s..." % get_selected_server_name())
		var cfg: Dictionary = get_spawn_config()
		save_player_name(str(cfg.get("name", "")))
		mp_connect_requested.emit(get_mp_server_url(), code_in, str(cfg.get("name", "Commander")))
	)
	copy_code_btn.pressed.connect(func() -> void:
		AudioManager.play_ui_tap()
		if not _current_room_code.is_empty():
			DisplayServer.clipboard_set(_current_room_code)
			show_toast("Copied Room Code: %s" % _current_room_code, false)
	)
	add_friend_btn.pressed.connect(func() -> void:
		AudioManager.play_ui_tap()
		add_friend(friend_name_edit.text)
		friend_name_edit.text = ""
	)
	friend_name_edit.text_submitted.connect(func(txt: String) -> void:
		AudioManager.play_ui_tap()
		add_friend(txt)
		friend_name_edit.text = ""
	)
	accept_invite_btn.pressed.connect(func() -> void:
		AudioManager.play_ui_tap()
		invite_row.visible = false
		_refresh_friends_badge()
		if not _pending_join_invite_code.is_empty():
			friends_card.visible = false
			mp_lobby_card.visible = true
			mp_room_edit.text = _pending_join_invite_code
			var cfg: Dictionary = get_spawn_config()
			save_player_name(str(cfg.get("name", "")))
			mp_connect_requested.emit(get_mp_server_url(), _pending_join_invite_code, str(cfg.get("name", "Commander")))
			_pending_join_invite_code = ""
	)
	dismiss_invite_btn.pressed.connect(func() -> void:
		AudioManager.play_ui_tap()
		_pending_join_invite_code = ""
		invite_row.visible = false
		_refresh_friends_badge()
	)
	audio_close_btn.pressed.connect(func() -> void:
		AudioManager.play_panel_close()
		audio_popover.visible = false
	)
	mp_disconnect_btn.pressed.connect(func() -> void:
		AudioManager.play_ui_tap()
		mp_disconnect_requested.emit()
		on_mp_disconnected("Returned to main menu.")
		mp_lobby_card.visible = false
		friends_card.visible = false
		menu_card.visible = true
	)
	mp_start_btn.pressed.connect(func() -> void:
		AudioManager.play_ui_tap()
		var cfg: Dictionary = get_spawn_config()
		mp_start_match_requested.emit(int(cfg.get("ai_count", 4)))
	)
	new_match_btn.pressed.connect(func() -> void:
		AudioManager.play_ui_tap()
		menu_overlay.visible = false
		_sync_hud_chrome_visibility()
		new_match_requested.emit()
	)
	quit_btn.pressed.connect(func() -> void:
		AudioManager.play_ui_tap()
		save_player_name(menu_name_edit.text)
		quit_requested.emit()
	)

	mute_check.toggled.connect(func(t: bool) -> void:
		AudioManager.set_muted(t)
		audio_btn.modulate = Color(1.0, 0.48, 0.48) if t else Color.WHITE
		audio_btn.tooltip_text = "Audio: Muted" if t else "Audio Settings"
	)
	master_slider.value_changed.connect(func(v: float) -> void: AudioManager.set_bus_volume("Master", v))
	music_slider.value_changed.connect(func(v: float) -> void: AudioManager.set_bus_volume("Music", v))
	sfx_slider.value_changed.connect(func(v: float) -> void: AudioManager.set_bus_volume("SFX", v))
	ambience_slider.value_changed.connect(func(v: float) -> void: AudioManager.set_bus_volume("Ambience", v))
	_update_action_dock_buttons()
	_update_commit_buttons()
	_update_hotkeys_button()


func _apply_ui_variants_and_icons(icon_back_16: ImageTexture, icon_friends_16: ImageTexture, icon_mp_16: ImageTexture, icon_audio_16: ImageTexture) -> void:
	for btn: Button in [play_btn, create_room_btn, mp_start_btn, add_friend_btn, accept_invite_btn, st_upgrade_btn, victory_new_match_btn, spec_new_match_btn, alliance_accept_btn]:
		ThemeFactory.apply_button_variant(btn, "primary")
	for btn: Button in [multiplayer_btn, friends_btn, mp_connect_btn, victory_inspect_btn, spec_continue_btn, donate_gold_btn, donate_troops_btn]:
		ThemeFactory.apply_button_variant(btn, "secondary")
	for btn: Button in [mp_disconnect_btn, friends_back_btn, menu_audio_btn, new_match_btn]:
		ThemeFactory.apply_button_variant(btn, "back")
	for btn: Button in [quit_btn, alliance_decline_btn]:
		ThemeFactory.apply_button_variant(btn, "danger")
	for btn: Button in [map_mode_btn, reset_view_btn, hotkeys_btn, audio_btn, menu_btn, lb_toggle_btn, copy_code_btn, mp_friends_btn, commit_20_btn, commit_35_btn, commit_50_btn, commit_75_btn]:
		ThemeFactory.apply_button_variant(btn, "ghost")
	for btn: Button in [st_close_btn, dip_close_btn, audio_close_btn, dismiss_invite_btn, radial_close_btn]:
		_style_close_button(btn)
	for btn: Button in [expand_btn, town_btn, factory_btn, port_btn, defense_btn, silo_btn, sam_btn, warship_btn, atom_dock_btn, hbomb_dock_btn, mirv_dock_btn]:
		ThemeFactory.apply_button_variant(btn, "dock_slot")

	play_btn.icon = _icon_play_16
	mp_start_btn.icon = _icon_play_16
	accept_invite_btn.icon = _icon_play_16
	mp_disconnect_btn.icon = icon_back_16
	friends_back_btn.icon = icon_back_16
	quit_btn.icon = _icon_close_16
	multiplayer_btn.icon = icon_mp_16
	friends_btn.icon = icon_friends_16
	mp_friends_btn.icon = icon_friends_16
	menu_audio_btn.icon = icon_audio_16
	audio_btn.icon = icon_audio_16


func _style_close_button(btn: Button) -> void:
	if btn == null:
		return
	ThemeFactory.apply_button_variant(btn, "ghost_danger")
	btn.text = ""
	btn.icon = _icon_close_16
	btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	btn.add_theme_color_override("icon_normal_color", Color(1.0, 0.45, 0.45))
	btn.add_theme_color_override("icon_hover_color", Color.WHITE)
	btn.add_theme_color_override("icon_pressed_color", Color.WHITE)


func _populate_spawn_controls() -> void:
	ai_count_option.clear()
	menu_ai_option.clear()
	for cnt in [0, 4, 6, 8, 10]:
		var label := "%d AI Nations" % cnt
		ai_count_option.add_item(label, cnt)
		menu_ai_option.add_item(label, cnt)
	ai_count_option.select(2)
	menu_ai_option.select(2)
	nation_name_edit.text_changed.connect(func(txt: String) -> void:
		if menu_name_edit.text != txt:
			menu_name_edit.text = txt
		save_player_name(txt)
	)
	menu_name_edit.text_changed.connect(func(txt: String) -> void:
		if nation_name_edit.text != txt:
			nation_name_edit.text = txt
		save_player_name(txt)
	)
	nation_name_edit.focus_exited.connect(func() -> void: save_player_name(nation_name_edit.text))
	menu_name_edit.focus_exited.connect(func() -> void: save_player_name(menu_name_edit.text))
	nation_name_edit.text_submitted.connect(func(txt: String) -> void: save_player_name(txt))
	menu_name_edit.text_submitted.connect(func(txt: String) -> void: save_player_name(txt))
	ai_count_option.item_selected.connect(func(idx: int) -> void:
		if menu_ai_option.selected != idx:
			menu_ai_option.select(idx)
	)
	menu_ai_option.item_selected.connect(func(idx: int) -> void:
		if ai_count_option.selected != idx:
			ai_count_option.select(idx)
	)


func _load_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PROFILE_SAVE_PATH) == OK:
		var saved: String = str(cfg.get_value("profile", "player_name", "")).strip_edges()
		if not saved.is_empty():
			menu_name_edit.text = saved
			nation_name_edit.text = saved


func save_player_name(raw_name: String) -> void:
	var clean: String = raw_name.strip_edges()
	if clean.is_empty():
		return
	var cfg := ConfigFile.new()
	cfg.load(PROFILE_SAVE_PATH)
	cfg.set_value("profile", "player_name", clean)
	cfg.save(PROFILE_SAVE_PATH)


func _populate_server_regions() -> void:
	server_option.clear()
	for i in range(SERVER_REGIONS.size()):
		server_option.add_item(str(SERVER_REGIONS[i]["name"]), i)
	server_option.select(0)
	server_option.visible = false
	server_value_label.text = str(SERVER_REGIONS[0]["name"])
	mp_server_edit.visible = false
	mp_server_edit.text = str(SERVER_REGIONS[0]["url"])


func get_selected_server_name() -> String:
	var idx: int = clampi(server_option.selected, 0, SERVER_REGIONS.size() - 1)
	return str(SERVER_REGIONS[idx]["name"])


func open_friends_page(return_to: String = "menu") -> void:
	AudioManager.play_ui_tap()
	_friends_return_to = return_to
	menu_card.visible = false
	mp_lobby_card.visible = false
	friends_card.visible = true
	menu_overlay.visible = true
	_refresh_friends_ui()


func _on_friends_back_pressed() -> void:
	AudioManager.play_ui_tap()
	friends_card.visible = false
	if _friends_return_to == "mp_lobby":
		mp_lobby_card.visible = true
	else:
		menu_card.visible = true


func _refresh_friends_badge() -> void:
	var label_txt := "Friends (1)" if invite_row.visible else "Friends"
	friends_btn.text = label_txt
	mp_friends_btn.text = label_txt
	if not _current_room_code.is_empty():
		friends_hint_label.text = "Room Code: %s — click Invite to send to friends." % _current_room_code
	else:
		friends_hint_label.text = "Invite a friend to auto-create a %s room." % get_selected_server_name()


func _load_friends() -> void:
	_friends.clear()
	var cfg := ConfigFile.new()
	if cfg.load(FRIENDS_SAVE_PATH) == OK:
		var list: Variant = cfg.get_value("social", "friends", [])
		if list is Array:
			for item: Variant in list:
				var s: String = str(item).strip_edges()
				if not s.is_empty() and not _friends.has(s):
					_friends.append(s)
	_refresh_friends_ui()


func _save_friends() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("social", "friends", _friends)
	cfg.save(FRIENDS_SAVE_PATH)


func add_friend(raw_name: String) -> void:
	var clean: String = raw_name.strip_edges()
	if clean.is_empty():
		return
	if not _friends.has(clean):
		_friends.append(clean)
		_save_friends()
		_refresh_friends_ui()
		show_toast("Added %s to Friends." % clean, false)


func remove_friend(clean: String) -> void:
	if _friends.has(clean):
		_friends.erase(clean)
		_save_friends()
		_refresh_friends_ui()


func _refresh_friends_ui() -> void:
	for child in friends_rows.get_children():
		child.queue_free()
	if _friends.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No friends added yet — add a friend above to invite."
		empty_lbl.modulate = Color(0.64, 0.72, 0.82, 0.85)
		friends_rows.add_child(empty_lbl)
		return
	for f_name: String in _friends:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(8, 8)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.color = Color(0.32, 0.90, 0.56)
		row.add_child(dot)

		var nm := Label.new()
		nm.text = f_name
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.clip_text = true
		row.add_child(nm)

		var inv_btn := Button.new()
		inv_btn.text = "Invite"
		ThemeFactory.apply_button_variant(inv_btn, "secondary")
		var f_cap: String = f_name
		inv_btn.pressed.connect(func() -> void:
			AudioManager.play_ui_tap()
			_on_invite_friend_pressed(f_cap)
		)
		row.add_child(inv_btn)

		var rm_btn := Button.new()
		_style_close_button(rm_btn)
		rm_btn.tooltip_text = "Remove Friend"
		rm_btn.pressed.connect(func() -> void:
			AudioManager.play_ui_tap()
			remove_friend(f_cap)
		)
		row.add_child(rm_btn)

		friends_rows.add_child(row)


func _on_invite_friend_pressed(friend_name: String) -> void:
	if _current_room_code.is_empty():
		_pending_invite_friend = friend_name
		friends_card.visible = false
		mp_lobby_card.visible = true
		mp_room_edit.text = ""
		mp_status_label.text = "Creating Room on %s to invite %s..." % [get_selected_server_name(), friend_name]
		var cfg: Dictionary = get_spawn_config()
		save_player_name(str(cfg.get("name", "")))
		mp_connect_requested.emit(get_mp_server_url(), "", str(cfg.get("name", "Commander")))
		return
	DisplayServer.clipboard_set(_current_room_code)
	friend_invite_requested.emit(friend_name, _current_room_code)
	show_toast("Invited %s to Room %s (Code copied)!" % [friend_name, _current_room_code], false)


func show_incoming_invite(from_name: String, room_code: String) -> void:
	if room_code.is_empty():
		return
	_pending_join_invite_code = room_code.strip_edges().to_upper()
	invite_label.text = "%s invited you · Code: %s" % [from_name, _pending_join_invite_code]
	invite_row.visible = true
	_refresh_friends_badge()
	show_toast("Room Invite from %s (Code: %s)!" % [from_name, _pending_join_invite_code], false)


func bind_world_state(world_state: WorldState) -> void:
	_world_state = world_state
	refresh_all()


func _unhandled_input(event: InputEvent) -> void:
	if _world_state == null or _world_state.match_phase != WorldState.PHASE_PLAYING:
		return
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo and ke.keycode == KEY_ESCAPE:
			if radial_menu.visible:
				close_radial_menu()
				get_viewport().set_input_as_handled()
				return
			if diplomacy_panel.visible:
				_selected_dip_nation_id = 0
				diplomacy_panel.visible = false
				get_viewport().set_input_as_handled()
				return
			if _missile_mode != "":
				clear_missile_mode()
				missile_mode_selected.emit("")
				get_viewport().set_input_as_handled()
				return
	if menu_overlay.visible or not _hotkeys_enabled:
		return
	if nation_name_edit.has_focus() or menu_name_edit.has_focus() or mp_server_edit.has_focus() or mp_room_edit.has_focus() or friend_name_edit.has_focus():
		return
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			match ke.keycode:
				KEY_1:
					_select_build_mode(StructureData.TYPE_TOWN)
					get_viewport().set_input_as_handled()
				KEY_2:
					_select_build_mode(StructureData.TYPE_FACTORY)
					get_viewport().set_input_as_handled()
				KEY_3:
					_select_build_mode(StructureData.TYPE_PORT)
					get_viewport().set_input_as_handled()
				KEY_4:
					_select_build_mode(StructureData.TYPE_DEFENSE_POST)
					get_viewport().set_input_as_handled()
				KEY_5:
					_select_build_mode(StructureData.TYPE_MISSILE_SILO)
					get_viewport().set_input_as_handled()
				KEY_6:
					_select_build_mode(StructureData.TYPE_SAM_LAUNCHER)
					get_viewport().set_input_as_handled()
				KEY_7:
					_select_build_mode("warship")
					get_viewport().set_input_as_handled()
				KEY_8, KEY_N:
					_select_missile_mode(MissileUnit.KIND_ATOM)
					get_viewport().set_input_as_handled()
				KEY_9, KEY_H:
					_select_missile_mode(MissileUnit.KIND_HYDROGEN)
					get_viewport().set_input_as_handled()
				KEY_F, KEY_0, KEY_M:
					_select_missile_mode(MissileUnit.KIND_MIRV)
					get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			toast_panel.visible = false
	if _lb_dirty:
		_lb_timer += delta
		if _lb_timer >= 0.25:
			_lb_timer = 0.0
			refresh_leaderboard()
	if _exp_dirty:
		_exp_timer += delta
		if _exp_timer >= 0.16:
			_exp_timer = 0.0
			refresh_expansions()


func get_spawn_config() -> Dictionary:
	var n_name: String = nation_name_edit.text.strip_edges()
	if n_name.is_empty():
		n_name = "Terran Vanguard"
	var ai_id: int = ai_count_option.get_selected_id()
	if ai_id < 0:
		ai_id = 6
	return {"name": n_name, "ai_count": ai_id}


func set_commit_ratio(ratio: float) -> void:
	AudioManager.play_ui_tap()
	_commit_ratio = clampf(ratio, 0.15, 0.80)
	_update_commit_buttons()


func get_commit_ratio() -> float:
	return _commit_ratio


func toggle_hotkeys() -> void:
	AudioManager.play_ui_tap()
	_hotkeys_enabled = not _hotkeys_enabled
	_update_hotkeys_button()


func _sync_hud_chrome_visibility() -> void:
	var in_menu: bool = menu_overlay.visible
	if in_menu:
		top_bar.visible = false
		action_dock.visible = false
		spawn_banner.visible = false
		leaderboard_panel.visible = false
		world_min_btn.visible = false
		hover_card.visible = false
		ping_badge.visible = false
		structure_panel.visible = false
		expansions_panel.visible = false
		diplomacy_panel.visible = false
		alliance_banner.visible = false
		radial_menu.visible = false
	else:
		var is_playing: bool = _world_state != null and _world_state.match_phase == WorldState.PHASE_PLAYING
		top_bar.visible = true
		ping_badge.visible = true
		leaderboard_panel.visible = not _leaderboard_minimized
		world_min_btn.visible = _leaderboard_minimized
		action_dock.visible = is_playing and not _is_spectating
		spawn_banner.visible = (_world_state != null and _world_state.match_phase == WorldState.PHASE_SPAWN_SELECT)
	menu_visibility_changed.emit(in_menu)


func open_menu() -> void:
	AudioManager.play_panel_open()
	audio_popover.visible = false
	var in_match: bool = _world_state != null and _world_state.match_phase != WorldState.PHASE_SPAWN_SELECT
	play_btn.text = "Resume Match" if in_match else "Play Match"
	new_match_btn.visible = in_match
	mp_lobby_card.visible = false
	friends_card.visible = false
	menu_card.visible = true
	menu_overlay.visible = true
	_sync_hud_chrome_visibility()


func update_mp_lobby(room_code: String, phase: String, players: Array, ai_count: int, is_host: bool) -> void:
	_current_room_code = room_code
	mp_room_edit.text = room_code
	assigned_code_label.text = "Room Code: %s" % (room_code if not room_code.is_empty() else "(Not in Room)")
	copy_code_btn.disabled = room_code.is_empty()
	_refresh_friends_badge()
	mp_status_label.text = "%s · Room %s · %s · AI: %d (%s)" % [get_selected_server_name(), room_code, phase, ai_count, "Host" if is_host else "Guest"]
	var names := PackedStringArray()
	for pv: Variant in players:
		if pv is Dictionary:
			var pd := pv as Dictionary
			var tag: String = " [Spawned]" if bool(pd.get("has_spawn", false)) else ""
			var host_tag: String = " ★" if bool(pd.get("is_host", false)) else ""
			names.append(str(pd.get("name", "Player")) + host_tag + tag)
	mp_players_label.text = "Players (%d): %s" % [players.size(), ", ".join(names)] if not names.is_empty() else "Players: --"
	mp_start_btn.disabled = (not is_host) or (phase != "LOBBY")
	if not _pending_invite_friend.is_empty() and not _current_room_code.is_empty():
		var inv_target: String = _pending_invite_friend
		_pending_invite_friend = ""
		_on_invite_friend_pressed(inv_target)


func on_mp_spawn_phase(seconds_left: float) -> void:
	menu_overlay.visible = false
	mp_lobby_card.visible = false
	friends_card.visible = false
	menu_card.visible = true
	audio_popover.visible = false
	_sync_hud_chrome_visibility()
	world_pct_label.text = "MP Spawn Selection (%.0fs)" % maxf(seconds_left, 0.0)


func on_mp_disconnected(reason: String) -> void:
	_current_room_code = ""
	assigned_code_label.text = "Room Code: (Not in Room)"
	copy_code_btn.disabled = true
	_refresh_friends_badge()
	mp_status_label.text = reason
	mp_players_label.text = "Players: --"
	mp_start_btn.disabled = true


func get_mp_server_url() -> String:
	var idx: int = clampi(server_option.selected, 0, SERVER_REGIONS.size() - 1)
	var u: String = str(SERVER_REGIONS[idx]["url"]).strip_edges()
	return u if not u.is_empty() else MPClient.DEFAULT_SERVER_URL


func update_ping(ping_ms: int) -> void:
	var col := Color(0.62, 0.70, 0.80, 0.85)
	var bars := "▯▯▯▯"
	if ping_ms < 0:
		ping_label.text = "--ms"
		conn_strength_label.text = "▯▯▯▯ --ms"
	else:
		ping_label.text = "%dms" % ping_ms
		if ping_ms < 80:
			col = Color(0.32, 0.92, 0.52, 1.0)
			bars = "▮▮▮▮"
		elif ping_ms < 150:
			col = Color(0.66, 0.92, 0.42, 1.0)
			bars = "▮▮▮▯"
		elif ping_ms < 230:
			col = Color(0.96, 0.80, 0.30, 1.0)
			bars = "▮▮▯▯"
		else:
			col = Color(0.96, 0.38, 0.34, 1.0)
			bars = "▮▯▯▯"
		conn_strength_label.text = "%s %dms" % [bars, ping_ms]
	ping_icon.self_modulate = col
	ping_label.modulate = col
	conn_bar_icon.self_modulate = col
	conn_strength_label.modulate = col


func enter_spectator_mode(conqueror_name: String = "") -> void:
	_is_spectating = true
	clear_build_mode()
	clear_missile_mode()
	structure_panel.visible = false
	diplomacy_panel.visible = false
	radial_menu.visible = false
	radial_sub_picker.visible = false
	var by_str: String = (" by %s" % conqueror_name) if not conqueror_name.is_empty() else ""
	spec_label.text = "Your Nation Was Conquered%s — Spectating Live Match" % by_str
	spectator_banner.visible = true
	_sync_hud_chrome_visibility()
	refresh_player_bar()


func on_match_started() -> void:
	_is_spectating = false
	spectator_banner.visible = false
	menu_overlay.visible = false
	audio_popover.visible = false
	_sync_hud_chrome_visibility()
	var p: NationData = _world_state.get_player_nation() if _world_state != null else null
	if p != null:
		_apply_action_dock_icons(p.color)
	refresh_all()


func on_match_reset() -> void:
	_is_spectating = false
	spectator_banner.visible = false
	menu_overlay.visible = false
	victory_overlay.visible = false
	audio_popover.visible = false
	structure_panel.visible = false
	expansions_panel.visible = false
	diplomacy_panel.visible = false
	alliance_banner.visible = false
	radial_menu.visible = false
	radial_sub_picker.visible = false
	_selected_structure_id = 0
	_selected_dip_nation_id = 0
	_pending_alliance_from_id = 0
	clear_build_mode()
	clear_missile_mode()
	_sync_hud_chrome_visibility()
	refresh_all()


func clear_build_mode() -> void:
	_build_mode = ""
	_update_action_dock_buttons()


func clear_missile_mode() -> void:
	_missile_mode = ""
	_update_action_dock_buttons()


func _select_build_mode(mode: String) -> void:
	AudioManager.play_ui_tap()
	_build_mode = mode if _build_mode != mode else ""
	_missile_mode = ""
	_update_action_dock_buttons()
	build_mode_selected.emit(_build_mode)


func _select_missile_mode(kind: String) -> void:
	AudioManager.play_ui_tap()
	_missile_mode = kind if _missile_mode != kind else ""
	if _missile_mode != "":
		_build_mode = ""
		build_mode_selected.emit("")
		show_toast("Click once to lock target, click again to launch %s!" % _missile_mode.to_upper(), false)
	_update_action_dock_buttons()
	missile_mode_selected.emit(_missile_mode)


func _update_action_dock_buttons() -> void:
	var free_hand: bool = (_build_mode == "" and _missile_mode == "")
	ThemeFactory.set_slot_active(expand_btn, free_hand, Color(0.56, 0.88, 1.0, 0.95))
	ThemeFactory.set_slot_active(town_btn, _build_mode == StructureData.TYPE_TOWN, Color(0.46, 0.94, 0.62, 0.95))
	ThemeFactory.set_slot_active(factory_btn, _build_mode == StructureData.TYPE_FACTORY, Color(0.98, 0.80, 0.36, 0.95))
	ThemeFactory.set_slot_active(port_btn, _build_mode == StructureData.TYPE_PORT, Color(0.44, 0.86, 1.0, 0.95))
	ThemeFactory.set_slot_active(defense_btn, _build_mode == StructureData.TYPE_DEFENSE_POST, Color(0.52, 0.76, 1.0, 0.95))
	ThemeFactory.set_slot_active(silo_btn, _build_mode == StructureData.TYPE_MISSILE_SILO, Color(1.0, 0.56, 0.46, 0.95))
	ThemeFactory.set_slot_active(sam_btn, _build_mode == StructureData.TYPE_SAM_LAUNCHER, Color(0.42, 0.96, 0.92, 0.95))
	ThemeFactory.set_slot_active(warship_btn, _build_mode == "warship", Color(0.48, 0.86, 1.0, 0.95))
	ThemeFactory.set_slot_active(atom_dock_btn, _missile_mode == MissileUnit.KIND_ATOM, Color(1.0, 0.82, 0.36, 0.95))
	ThemeFactory.set_slot_active(hbomb_dock_btn, _missile_mode == MissileUnit.KIND_HYDROGEN, Color(1.0, 0.52, 0.32, 0.95))
	ThemeFactory.set_slot_active(mirv_dock_btn, _missile_mode == MissileUnit.KIND_MIRV, Color(1.0, 0.38, 0.66, 0.95))
	expand_btn.modulate = Color(0.76, 0.94, 1.0) if free_hand else Color.WHITE
	town_btn.modulate = Color(0.76, 0.98, 0.82) if _build_mode == StructureData.TYPE_TOWN else Color.WHITE
	factory_btn.modulate = Color(1.0, 0.88, 0.62) if _build_mode == StructureData.TYPE_FACTORY else Color.WHITE
	port_btn.modulate = Color(0.72, 0.94, 1.0) if _build_mode == StructureData.TYPE_PORT else Color.WHITE
	defense_btn.modulate = Color(0.74, 0.86, 1.0) if _build_mode == StructureData.TYPE_DEFENSE_POST else Color.WHITE
	silo_btn.modulate = Color(1.0, 0.72, 0.66) if _build_mode == StructureData.TYPE_MISSILE_SILO else Color.WHITE
	sam_btn.modulate = Color(0.68, 0.98, 1.0) if _build_mode == StructureData.TYPE_SAM_LAUNCHER else Color.WHITE
	warship_btn.modulate = Color(0.66, 0.92, 1.0) if _build_mode == "warship" else Color.WHITE
	atom_dock_btn.modulate = Color(1.0, 0.78, 0.44) if _missile_mode == MissileUnit.KIND_ATOM else Color.WHITE
	hbomb_dock_btn.modulate = Color(1.0, 0.56, 0.36) if _missile_mode == MissileUnit.KIND_HYDROGEN else Color.WHITE
	mirv_dock_btn.modulate = Color(1.0, 0.44, 0.66) if _missile_mode == MissileUnit.KIND_MIRV else Color.WHITE
	commit_sep.visible = free_hand
	commit_box.visible = free_hand


func _update_commit_buttons() -> void:
	var active_col := Color(0.68, 0.94, 1.0)
	ThemeFactory.set_slot_active(commit_20_btn, is_equal_approx(_commit_ratio, 0.20), active_col)
	ThemeFactory.set_slot_active(commit_35_btn, is_equal_approx(_commit_ratio, 0.35), active_col)
	ThemeFactory.set_slot_active(commit_50_btn, is_equal_approx(_commit_ratio, 0.50), active_col)
	ThemeFactory.set_slot_active(commit_75_btn, is_equal_approx(_commit_ratio, 0.75), active_col)
	commit_20_btn.modulate = active_col if is_equal_approx(_commit_ratio, 0.20) else Color.WHITE
	commit_35_btn.modulate = active_col if is_equal_approx(_commit_ratio, 0.35) else Color.WHITE
	commit_50_btn.modulate = active_col if is_equal_approx(_commit_ratio, 0.50) else Color.WHITE
	commit_75_btn.modulate = active_col if is_equal_approx(_commit_ratio, 0.75) else Color.WHITE


func _update_hotkeys_button() -> void:
	hotkeys_btn.text = "Keys" if _hotkeys_enabled else "Keys Off"
	hotkeys_btn.tooltip_text = "Keyboard Hotkeys: ON" if _hotkeys_enabled else "Keyboard Hotkeys: OFF"
	hotkeys_btn.modulate = Color(0.78, 0.96, 0.84) if _hotkeys_enabled else Color(0.72, 0.76, 0.82)


func _on_play_pressed() -> void:
	AudioManager.play_ui_tap()
	save_player_name(menu_name_edit.text)
	menu_overlay.visible = false
	friends_card.visible = false
	audio_popover.visible = false
	_sync_hud_chrome_visibility()
	play_match_requested.emit()


func _toggle_audio_popover() -> void:
	audio_popover.visible = not audio_popover.visible
	if audio_popover.visible:
		if menu_overlay.visible:
			audio_popover.anchor_left = 0.5
			audio_popover.anchor_right = 0.5
			audio_popover.anchor_top = 0.5
			audio_popover.anchor_bottom = 0.5
			audio_popover.offset_left = -130.0
			audio_popover.offset_top = -140.0
			audio_popover.offset_right = 130.0
			audio_popover.offset_bottom = 140.0
		else:
			audio_popover.anchor_left = 0.5
			audio_popover.anchor_right = 0.5
			audio_popover.anchor_top = 1.0
			audio_popover.anchor_bottom = 1.0
			audio_popover.offset_left = 114.0
			audio_popover.offset_top = -360.0
			audio_popover.offset_right = 374.0
			audio_popover.offset_bottom = -96.0
		audio_popover.move_to_front()
		AudioManager.play_panel_open()
	else:
		AudioManager.play_panel_close()


static func _make_pixel_icon(base: Texture2D, tint: Color = Color.WHITE, size_px: int = 16) -> ImageTexture:
	if base == null:
		return null
	var img: Image = base.get_image().duplicate()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	if size_px > 0 and (img.get_width() != size_px or img.get_height() != size_px):
		img.resize(size_px, size_px, Image.INTERPOLATE_NEAREST)
	if tint != Color.WHITE:
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				var c: Color = img.get_pixel(x, y)
				if c.a > 0.01:
					img.set_pixel(x, y, Color(c.r * tint.r, c.g * tint.g, c.b * tint.b, c.a * tint.a))
	return ImageTexture.create_from_image(img)


func _apply_action_dock_icons(player_col: Color) -> void:
	gold_icon.texture = _build_tinted_icon(_tex_coin, null, Color.WHITE, 15, 15)
	troops_icon.texture = _build_tinted_icon(_tex_troops, null, Color.WHITE, 15, 15)
	expand_btn.icon = _build_tinted_icon(_tex_attack, null, Color.WHITE, 16, 16)
	town_btn.icon = _build_tinted_icon(_tex_town, _tex_town_mask, player_col, 16, 16)
	factory_btn.icon = _build_tinted_icon(_tex_factory, _tex_factory_mask, player_col, 16, 16)
	port_btn.icon = _build_tinted_icon(_tex_port, _tex_port_mask, player_col, 16, 16)
	defense_btn.icon = _build_tinted_icon(_tex_defense, _tex_defense_mask, player_col, 16, 16)
	silo_btn.icon = _build_tinted_icon(_tex_silo, _tex_silo_mask, player_col, 16, 16)
	sam_btn.icon = _build_tinted_icon(_tex_sam, _tex_sam_mask, player_col, 16, 16)
	var ship_ic: ImageTexture = _build_tinted_icon(_tex_warship, _tex_warship_mask, player_col, 20, 11)
	warship_btn.icon = ship_ic
	atom_dock_btn.icon = _build_tinted_icon(_tex_missile, null, Color(1.0, 0.88, 0.45), 16, 16)
	hbomb_dock_btn.icon = _build_tinted_icon(_tex_missile, null, Color(1.0, 0.52, 0.32), 16, 16)
	mirv_dock_btn.icon = _build_tinted_icon(_tex_missile, null, Color(1.0, 0.36, 0.68), 16, 16)
	var upg_ic: ImageTexture = _build_tinted_icon(_tex_upgrade, null, Color.WHITE, 16, 16)
	var boat_ic: ImageTexture = _build_tinted_icon(_tex_boat, null, Color.WHITE, 16, 16)
	st_upgrade_btn.icon = upg_ic
	st_warship_btn.icon = ship_ic
	st_atom_btn.icon = atom_dock_btn.icon
	st_hbomb_btn.icon = hbomb_dock_btn.icon
	st_mirv_btn.icon = mirv_dock_btn.icon
	var dip_ic: ImageTexture = _build_tinted_icon(_tex_diplomacy, null, Color.WHITE, 16, 16)
	ally_btn.icon = dip_ic
	embargo_btn.icon = _build_tinted_icon(_tex_port, _tex_port_mask, Color(1.0, 0.55, 0.45), 16, 16)
	donate_gold_btn.icon = _build_tinted_icon(_tex_coin, null, Color.WHITE, 16, 16)
	donate_troops_btn.icon = _build_tinted_icon(_tex_troops, null, Color.WHITE, 16, 16)
	# Simplified 4-way right-click bar: Top=Attack(crossed swords), Left=Upgrade(arrow up), Right=Boat(boat), Bottom=Ally(handshake)
	radial_attack_btn.icon = expand_btn.icon
	radial_build_btn.icon = upg_ic
	radial_warship_btn.icon = boat_ic
	radial_missile_btn.icon = atom_dock_btn.icon
	radial_dip_btn.icon = dip_ic
	radial_info_btn.icon = dip_ic


static func _build_tinted_icon(base: Texture2D, mask: Texture2D, col: Color, out_w: int = 20, out_h: int = 20) -> ImageTexture:
	if base == null:
		return null
	var img: Image = base.get_image().duplicate()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	if mask != null:
		var m_img: Image = mask.get_image()
		var tint: Color = col.lightened(0.18)
		for y in range(mini(img.get_height(), m_img.get_height())):
			for x in range(mini(img.get_width(), m_img.get_width())):
				var mp: Color = m_img.get_pixel(x, y)
				if mp.a > 0.01:
					var dst_c: Color = img.get_pixel(x, y)
					img.set_pixel(x, y, dst_c.blend(Color(mp.r * tint.r, mp.g * tint.g, mp.b * tint.b, mp.a)))
	if out_w > 0 and out_h > 0 and (img.get_width() != out_w or img.get_height() != out_h):
		img.resize(out_w, out_h, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)


func update_clock_text(text: String) -> void:
	clock_label.text = text


func mark_leaderboard_dirty() -> void:
	_lb_dirty = true


func mark_expansions_dirty() -> void:
	_exp_dirty = true


func refresh_all() -> void:
	if _world_state == null:
		return
	refresh_player_bar()
	refresh_leaderboard()
	refresh_expansions()
	if _selected_structure_id > 0:
		show_selected_structure(_selected_structure_id)
	if _selected_dip_nation_id > 0:
		show_diplomacy_panel(_selected_dip_nation_id)


func refresh_player_bar() -> void:
	if _world_state == null:
		return
	if _world_state.match_phase == WorldState.PHASE_SPAWN_SELECT:
		gold_label.text = "Pesos: --"
		troops_label.text = "--"
		world_pct_label.text = "Select Spawn Point"
		return
	var p: NationData = _world_state.get_player_nation()
	if p == null:
		return
	if _is_spectating or (not p.alive and p.owned_cell_count == 0):
		var alive_cnt := 0
		for nid_k: int in _world_state.nations.keys():
			if (_world_state.nations[nid_k] as NationData).alive:
				alive_cnt += 1
		gold_label.text = "Pesos: SPECTATING"
		troops_label.text = "Defeated"
		world_pct_label.text = "Spectating · %d Nations Alive" % alive_cnt
		return
	gold_label.text = "Pesos: %s (+%s/s)" % [StructureData.format_pesos(p.gold), StructureData.format_pesos(p.gold_per_sec)]
	troops_label.text = "%d/%d (+%.1f/s)" % [int(floor(p.troops)), int(round(p.max_troops)), p.effective_troops_per_sec]
	var betray_tag := " [BETRAYAL]" if p.is_betrayer(_world_state.current_tick) else ""
	world_pct_label.text = "%.2f%% / 80%%%s" % [p.territory_percent, betray_tag]
	var dock_key: int = p.id * 100003 + p.structure_ids.size() * 131 + _world_state.structures.size() + _world_state.count_warships(p.id) * 17
	if dock_key == _last_dock_cost_key:
		return
	_last_dock_cost_key = dock_key
	expand_btn.text = "Explore"
	town_btn.text = "1·%s" % StructureData.format_pesos(_world_state.get_structure_build_cost(p.id, StructureData.TYPE_TOWN))
	town_btn.tooltip_text = "[1] Town (%d owned)" % _world_state.count_structures_of_type(p.id, StructureData.TYPE_TOWN)
	factory_btn.text = "2·%s" % StructureData.format_pesos(_world_state.get_structure_build_cost(p.id, StructureData.TYPE_FACTORY))
	factory_btn.tooltip_text = "[2] Factory (%d owned)" % _world_state.count_structures_of_type(p.id, StructureData.TYPE_FACTORY)
	port_btn.text = "3·%s" % StructureData.format_pesos(_world_state.get_structure_build_cost(p.id, StructureData.TYPE_PORT))
	port_btn.tooltip_text = "[3] Port (%d owned)" % _world_state.count_structures_of_type(p.id, StructureData.TYPE_PORT)
	defense_btn.text = "4·%s" % StructureData.format_pesos(_world_state.get_structure_build_cost(p.id, StructureData.TYPE_DEFENSE_POST))
	defense_btn.tooltip_text = "[4] Defense Post (%d owned)" % _world_state.count_structures_of_type(p.id, StructureData.TYPE_DEFENSE_POST)
	silo_btn.text = "5·%s" % StructureData.format_pesos(_world_state.get_structure_build_cost(p.id, StructureData.TYPE_MISSILE_SILO))
	silo_btn.tooltip_text = "[5] Missile Silo (%d owned)" % _world_state.count_structures_of_type(p.id, StructureData.TYPE_MISSILE_SILO)
	sam_btn.text = "6·%s" % StructureData.format_pesos(_world_state.get_structure_build_cost(p.id, StructureData.TYPE_SAM_LAUNCHER))
	sam_btn.tooltip_text = "[6] SAM Launcher (%d owned)" % _world_state.count_structures_of_type(p.id, StructureData.TYPE_SAM_LAUNCHER)
	warship_btn.text = "7·%s" % StructureData.format_pesos(_world_state.get_warship_build_cost(p.id))
	warship_btn.tooltip_text = "[7] Warship (%d active)" % _world_state.count_warships(p.id)
	atom_dock_btn.text = "8·%s" % StructureData.format_pesos(MissileUnit.get_cost(MissileUnit.KIND_ATOM))
	atom_dock_btn.tooltip_text = "[8] Atom Bomb"
	hbomb_dock_btn.text = "9·%s" % StructureData.format_pesos(MissileUnit.get_cost(MissileUnit.KIND_HYDROGEN))
	hbomb_dock_btn.tooltip_text = "[9] Hydrogen Bomb"
	mirv_dock_btn.text = "F·%s" % StructureData.format_pesos(MissileUnit.get_cost(MissileUnit.KIND_MIRV))
	mirv_dock_btn.tooltip_text = "[F] MIRV Warhead"


func show_hovered_cell(cell: Vector2i) -> void:
	if _world_state == null or cell.x < 0 or cell.y < 0:
		hover_card.visible = false
		return
	var info: Dictionary = _world_state.get_cell_info(cell.x, cell.y)
	var t: int = int(info.get("terrain", 0))
	if t == WorldState.T_OCEAN:
		hover_card.visible = false
		return

	hover_card.visible = true
	var world_pos: Vector2 = _world_state.sim_to_world(cell)
	var st: StructureData = _world_state.find_structure_near(world_pos, 10.0)
	if st != null:
		hover_title.text = "%s (Lv.%d/%d) — %s" % [st.get_display_name(), st.level, st.get_max_level(), str(info.get("region_hint", "Earth"))]
	else:
		hover_title.text = str(info.get("region_hint", "Earth"))

	var coast_txt: String = " · Coastal" if bool(info.get("coastal", false)) else ""
	hover_sub.text = "%s%s" % [str(info.get("terrain_name", "Land")), coast_txt]

	var oid: int = int(info.get("owner_id", 0))
	if oid == 0:
		if bool(info.get("fallout", false)):
			hover_owner_dot.color = Color(0.56, 0.68, 0.18)
			hover_owner_lbl.text = "Nuclear Waste (2.4x Troop Cost to Reclaim)"
		else:
			hover_owner_dot.color = Color(0.42, 0.48, 0.56)
			hover_owner_lbl.text = "Unclaimed Land (Conquerable)"
	else:
		var owner: NationData = _world_state.get_nation(oid)
		hover_owner_dot.color = owner.color if owner != null else Color.GRAY
		hover_owner_lbl.text = owner.name if owner != null else "Nation #%d" % oid


func show_selected_structure(sid: int) -> void:
	var was_closed := (not structure_panel.visible) and sid > 0
	_selected_structure_id = sid
	if _world_state == null or sid <= 0:
		structure_panel.visible = false
		return
	var st: StructureData = _world_state.get_structure(sid)
	if st == null:
		structure_panel.visible = false
		return

	structure_panel.visible = true
	if was_closed:
		AudioManager.play_panel_open()
	var owner: NationData = _world_state.get_nation(st.nation_id)
	var owner_name: String = owner.name if owner != null else "Unknown"
	var st_col: Color = owner.color if owner != null else Color.WHITE
	var base_t: Texture2D = _tex_town
	var mask_t: Texture2D = _tex_town_mask
	match st.type:
		StructureData.TYPE_PORT:
			base_t = _tex_port
			mask_t = _tex_port_mask
		StructureData.TYPE_FACTORY:
			base_t = _tex_factory
			mask_t = _tex_factory_mask
		StructureData.TYPE_DEFENSE_POST:
			base_t = _tex_defense
			mask_t = _tex_defense_mask
		StructureData.TYPE_MISSILE_SILO:
			base_t = _tex_silo
			mask_t = _tex_silo_mask
		StructureData.TYPE_SAM_LAUNCHER:
			base_t = _tex_sam
			mask_t = _tex_sam_mask
	st_icon.texture = _build_tinted_icon(base_t, mask_t, st_col)
	var max_lvl: int = st.get_max_level()
	st_title.text = "%s (Lv.%d / %d)" % [st.get_display_name(), st.level, max_lvl]
	st_sub.text = "Owner: %s" % owner_name

	var detail_lines := ""
	match st.type:
		StructureData.TYPE_TOWN:
			detail_lines = "Income: +%s / sec\nPop Cap: +%d · Regen: +%.1f/s\nSupply Radius: %.0f · Factory Boost: %.2fx" % [
				StructureData.format_pesos(st.get_gold_per_sec()), int(round(st.get_max_troops_bonus())), st.get_troops_per_sec_bonus(), st.get_supply_radius(), st.factory_boost
			]
		StructureData.TYPE_PORT:
			var max_s: int = StructureData.get_max_trade_ships(maxi(1, st.level))
			detail_lines = "Income: +%s / sec\nTrade Ships: %d/%d (Spd %.0f)\nFactory Boost: %.2fx" % [
				StructureData.format_pesos(st.get_gold_per_sec()), st.active_ship_ids.size(), max_s, st.get_ship_speed(), st.factory_boost
			]
		StructureData.TYPE_FACTORY:
			detail_lines = "Income: +%s / sec\nTerrain: %.2fx · Connected: %d (%d Bridges)\nOrganic Range: %.0f · Link Bonus: %.2fx" % [
				StructureData.format_pesos(st.get_gold_per_sec()), st.terrain_bonus, st.connected_count, st.bridge_count, st.get_factory_base_radius(), st.connection_bonus
			]
		StructureData.TYPE_DEFENSE_POST:
			detail_lines = "Border Defense Multiplier: %.2fx\nFortified Radius: %.0f sim cells" % [
				st.get_defense_multiplier(), st.get_defense_radius()
			]
		StructureData.TYPE_MISSILE_SILO:
			var cd_s: String = "READY" if st.action_cooldown_ticks == 0 else "Reloading (%.1fs)" % (float(st.action_cooldown_ticks) / float(WorldState.TICK_RATE_HZ))
			detail_lines = "Strategic Warhead Silo · %s\nSelect Atom, H-Bomb, or MIRV below" % cd_s
		StructureData.TYPE_SAM_LAUNCHER:
			var scd_s: String = "READY" if st.sam_ammo > 0 and st.action_cooldown_ticks == 0 else ("Cycling (%.1fs)" % (float(st.action_cooldown_ticks) / float(WorldState.TICK_RATE_HZ)) if st.sam_ammo > 0 else "Reloading (%.1fs)" % (float(st.sam_reload_ticks) / float(WorldState.TICK_RATE_HZ)))
			detail_lines = "SAM Charges: %d/%d · Umbrella: %.0f cells\nStatus: %s" % [st.sam_ammo, StructureData.SAM_MAX_AMMO, st.get_sam_radius(), scd_s]
	st_stats.text = detail_lines
	st_next_lbl.text = st.get_next_level_summary()

	st_action_row.visible = false
	st_warship_btn.visible = false
	st_atom_btn.visible = false
	st_hbomb_btn.visible = false
	st_mirv_btn.visible = false

	if st.is_constructing:
		st_prog_bar.visible = true
		st_prog_bar.value = st.get_progress_ratio() * 100.0
		st_upgrade_btn.disabled = true
		st_upgrade_btn.text = "Constructing (%d%%)..." % int(round(st.get_progress_ratio() * 100.0))
	else:
		st_prog_bar.visible = false
		if st.nation_id != _world_state.player_nation_id:
			st_upgrade_btn.disabled = true
			st_upgrade_btn.text = "Foreign Structure"
		else:
			if st.type == StructureData.TYPE_PORT:
				st_action_row.visible = true
				st_warship_btn.visible = true
				var w_cost: float = _world_state.get_warship_build_cost(st.nation_id)
				st_warship_btn.text = "Warship (%s)" % StructureData.format_pesos(w_cost)
				st_warship_btn.disabled = (st.action_cooldown_ticks > 0)
			elif st.type == StructureData.TYPE_MISSILE_SILO:
				st_action_row.visible = true
				st_atom_btn.visible = true
				st_hbomb_btn.visible = true
				st_mirv_btn.visible = true
				var busy: bool = (st.action_cooldown_ticks > 0)
				st_atom_btn.disabled = busy
				st_hbomb_btn.disabled = busy
				st_mirv_btn.disabled = busy

			if st.level >= max_lvl:
				st_upgrade_btn.disabled = true
				st_upgrade_btn.text = "MAX LEVEL (%d/%d)" % [max_lvl, max_lvl]
			else:
				var cost: float = st.get_next_upgrade_cost()
				st_upgrade_btn.disabled = false
				st_upgrade_btn.text = "Upgrade Instantly -> Lv.%d/%d (%s)" % [st.level + 1, max_lvl, StructureData.format_pesos(cost)]


func _init_leaderboard_pool() -> void:
	_lb_pool.clear()
	for child in lb_rows.get_children():
		child.queue_free()
	for i in range(MAX_LEADERBOARD_ROWS):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		row.visible = false

		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(10, 10)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dot)

		var nm := Label.new()
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.clip_text = true
		row.add_child(nm)

		var pct := Label.new()
		row.add_child(pct)

		var dip_btn := Button.new()
		dip_btn.text = "Dip"
		ThemeFactory.apply_button_variant(dip_btn, "ghost")
		dip_btn.icon = _build_tinted_icon(_tex_diplomacy, null, Color.WHITE, 14, 14)
		var slot_idx: int = i
		dip_btn.pressed.connect(func() -> void:
			var nid_val: int = int(_lb_pool[slot_idx].get("nid", 0))
			if nid_val > 0:
				AudioManager.play_ui_tap()
				show_diplomacy_panel(nid_val)
		)
		row.add_child(dip_btn)

		lb_rows.add_child(row)
		_lb_pool.append({"row": row, "dot": dot, "name": nm, "pct": pct, "dip_btn": dip_btn, "nid": 0})


func refresh_expansions() -> void:
	if _world_state == null:
		return
	_exp_dirty = false
	var player_orders: Array[ExpansionOrder] = []
	for eid: int in _world_state.expansions.keys():
		var o: ExpansionOrder = _world_state.expansions[eid]
		if o.nation_id == _world_state.player_nation_id:
			player_orders.append(o)

	var landing_ships: Array[ShipUnit] = []
	for sid: int in _world_state.ships.keys():
		var sh: ShipUnit = _world_state.ships[sid]
		if sh.active and sh.nation_id == _world_state.player_nation_id and sh.kind == ShipUnit.KIND_LANDING:
			landing_ships.append(sh)

	if player_orders.is_empty() and landing_ships.is_empty():
		if expansions_panel.visible:
			expansions_panel.visible = false
			for child in exp_rows.get_children():
				child.queue_free()
		return

	for child in exp_rows.get_children():
		child.queue_free()
	expansions_panel.visible = true
	var max_boat_rows: int = mini(landing_ships.size(), 6)
	for bi in range(max_boat_rows):
		var sh: ShipUnit = landing_ships[bi]
		var s_row := HBoxContainer.new()
		s_row.add_theme_constant_override("separation", 6)
		var nav_lbl := Label.new()
		nav_lbl.text = "Landing Boat · %d troops en route" % int(round(sh.troops_carried))
		nav_lbl.modulate = Color(0.58, 0.88, 1.0)
		nav_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nav_lbl.clip_text = true
		s_row.add_child(nav_lbl)

		var rs_btn := Button.new()
		_style_close_button(rs_btn)
		rs_btn.tooltip_text = "Retreat Landing Boat"
		var sid_cap: int = sh.id
		rs_btn.pressed.connect(func() -> void:
			AudioManager.play_ui_tap()
			cancel_ship_requested.emit(sid_cap)
		)
		s_row.add_child(rs_btn)
		exp_rows.add_child(s_row)
	if landing_ships.size() > max_boat_rows:
		var more_lbl := Label.new()
		more_lbl.text = "+%d more landing boats en route" % (landing_ships.size() - max_boat_rows)
		more_lbl.modulate = Color(0.58, 0.84, 0.96, 0.85)
		exp_rows.add_child(more_lbl)

	for o: ExpansionOrder in player_orders:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var lbl := Label.new()
		var t_name: String = str(WorldState.TERRAIN_NAMES.get(o.target_terrain, "Land"))
		var kind_txt: String = "Contested" if o.is_contested else "Wild"
		lbl.text = "%s (%s) · %d%% · %s · %d troops" % [
			t_name, kind_txt, int(round(o.get_progress_percent())), o.supply_quality, int(round(o.remaining_troops))
		]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.clip_text = true
		row.add_child(lbl)

		var c_btn := Button.new()
		_style_close_button(c_btn)
		c_btn.tooltip_text = "Cancel Operation"
		var eid_cap: int = o.id
		c_btn.pressed.connect(func() -> void:
			AudioManager.play_ui_tap()
			cancel_expansion_requested.emit(eid_cap)
		)
		row.add_child(c_btn)
		exp_rows.add_child(row)


func refresh_leaderboard() -> void:
	if _world_state == null:
		return
	_lb_dirty = false
	lb_claimed_lbl.text = "World Claimed: %.1f%% · Victory: 80.0%%" % _world_state.get_claimed_percent()
	var ranked: Array[NationData] = _world_state.get_leaderboard()
	var shown := 0
	for n: NationData in ranked:
		if not n.alive and n.owned_cell_count == 0:
			continue
		if shown >= _lb_pool.size():
			break
		var slot: Dictionary = _lb_pool[shown]
		slot["nid"] = n.id
		(slot["row"] as HBoxContainer).visible = true
		(slot["dot"] as ColorRect).color = n.color
		var ally_tag := " [ALLY]" if (not n.is_player and _world_state.are_allied(_world_state.player_nation_id, n.id)) else ""
		(slot["name"] as Label).text = n.name + (" (You)" if n.is_player else ally_tag)
		(slot["pct"] as Label).text = "%.2f%%" % n.territory_percent
		(slot["dip_btn"] as Button).visible = (not n.is_player and n.alive)
		shown += 1

	for i in range(shown, _lb_pool.size()):
		_lb_pool[i]["nid"] = 0
		(_lb_pool[i]["row"] as HBoxContainer).visible = false

	if _world_state.winner_nation_id != 0:
		var winner: NationData = _world_state.get_nation(_world_state.winner_nation_id)
		if winner != null:
			lb_victory_lbl.visible = true
			lb_victory_lbl.text = "VICTORY: %s (%.1f%%)" % [winner.name, winner.territory_percent]
	else:
		lb_victory_lbl.visible = false


func show_toast(msg: String, is_alert: bool = true) -> void:
	toast_label.text = msg
	toast_label.modulate = Color(1.0, 0.74, 0.70) if is_alert else Color(0.70, 0.96, 0.80)
	toast_panel.visible = true
	_toast_timer = 3.2


func _on_map_mode_pressed() -> void:
	AudioManager.play_ui_tap()
	_political_mode = not _political_mode
	map_mode_btn.text = "Map" if _political_mode else "Terrain"
	map_mode_btn.tooltip_text = "Political Borders" if _political_mode else "Natural Terrain"
	map_mode_toggled.emit(_political_mode)


func _on_lb_toggle_pressed() -> void:
	AudioManager.play_ui_tap()
	_leaderboard_minimized = not _leaderboard_minimized
	leaderboard_panel.visible = not _leaderboard_minimized
	world_min_btn.visible = _leaderboard_minimized


func show_diplomacy_panel(target_nid: int) -> void:
	if _world_state == null or target_nid <= 0 or target_nid == _world_state.player_nation_id:
		return
	var other: NationData = _world_state.get_nation(target_nid)
	if other == null or not other.alive:
		diplomacy_panel.visible = false
		return
	var was_closed := not diplomacy_panel.visible
	_selected_dip_nation_id = target_nid
	diplomacy_panel.visible = true
	if was_closed:
		AudioManager.play_panel_open()
	dip_dot.color = other.color
	dip_title.text = other.name
	var p_id: int = _world_state.player_nation_id
	var allied: bool = _world_state.are_allied(p_id, target_nid)
	var embargoed: bool = _world_state.is_embargoed(p_id, target_nid)
	var rel_str := "Allied" if allied else ("Embargoed" if embargoed else "Neutral")
	if other.is_betrayer(_world_state.current_tick):
		rel_str += " · BETRAYER"
	dip_status_lbl.text = "Relation: %s\nLand: %.2f%% · Troops: %d · Pesos: %s" % [
		rel_str, other.territory_percent, int(round(other.troops)), StructureData.format_pesos(other.gold)
	]
	ally_btn.text = "Break Alliance" if allied else "Propose Alliance"
	ThemeFactory.apply_button_variant(ally_btn, "danger" if allied else "primary")
	embargo_btn.text = "Lift Embargo" if embargoed else "Trade Embargo"
	donate_gold_btn.text = "Send %s Pesos" % StructureData.format_pesos(100000.0)
	donate_gold_btn.disabled = not allied
	donate_troops_btn.disabled = not allied


func _on_ally_btn_pressed() -> void:
	if _world_state == null or _selected_dip_nation_id <= 0:
		return
	AudioManager.play_ui_tap()
	if _world_state.are_allied(_world_state.player_nation_id, _selected_dip_nation_id):
		break_alliance_requested.emit(_selected_dip_nation_id)
	else:
		request_alliance_requested.emit(_selected_dip_nation_id)


func show_alliance_offer(from_nid: int) -> void:
	if _world_state == null:
		return
	var from_n: NationData = _world_state.get_nation(from_nid)
	if from_n == null or not from_n.alive:
		return
	_pending_alliance_from_id = from_nid
	alliance_prompt.text = "%s proposes a 5-minute Alliance!" % from_n.name
	alliance_banner.visible = true


func _respond_to_pending_alliance(accept: bool) -> void:
	AudioManager.play_ui_tap()
	alliance_banner.visible = false
	if _pending_alliance_from_id > 0:
		respond_alliance_requested.emit(_pending_alliance_from_id, accept)
	_pending_alliance_from_id = 0


func show_victory_screen(winner_id: int, pct: float) -> void:
	if _world_state == null:
		return
	var winner: NationData = _world_state.get_nation(winner_id)
	var w_name: String = winner.name if winner != null else "Nation #%d" % winner_id
	var w_col: Color = winner.color if winner != null else Color.GOLD
	var is_player_win: bool = (winner_id == _world_state.player_nation_id)
	victory_icon.texture = _build_tinted_icon(_tex_banner, _tex_banner_mask, w_col, 24, 24)
	victory_title.text = "WORLD VICTORY" if is_player_win else "MATCH CONCLUDED"
	victory_title.modulate = Color(1.0, 0.88, 0.42) if is_player_win else Color(0.84, 0.90, 0.98)
	victory_sub.text = "%s unified %.1f%% of Earth!" % [w_name, pct]
	if winner != null:
		victory_stats.text = "Treasury: %s Pesos  ·  Standing Army: %d  ·  Structures: %d" % [
			StructureData.format_pesos(winner.gold),
			int(round(winner.troops)),
			winner.structure_ids.size(),
		]
	else:
		victory_stats.text = "World Control: %.1f%%" % pct
	victory_overlay.visible = true


func _on_radial_wheel_draw() -> void:
	var c := radial_wheel.size * 0.5
	var r_outer := minf(c.x, c.y) - 6.0
	var r_inner := 22.0
	radial_wheel.draw_circle(c, r_outer, Color(0.07, 0.11, 0.17, 0.88))
	radial_wheel.draw_arc(c, r_outer, 0.0, TAU, 56, Color(0.84, 0.70, 0.34, 0.65), 2.0)
	for i in range(4):
		var a := float(i) * (TAU / 4.0) + PI * 0.25
		var dir := Vector2(cos(a), sin(a))
		radial_wheel.draw_line(c + dir * r_inner, c + dir * r_outer, Color(0.28, 0.42, 0.58, 0.55), 1.0)
	radial_wheel.draw_circle(c, r_inner, Color(0.11, 0.17, 0.26, 0.94))
	radial_wheel.draw_arc(c, r_inner, 0.0, TAU, 32, Color(0.45, 0.66, 0.86, 0.72), 1.5)


func open_radial_menu(screen_pos: Vector2, world_pos: Vector2, cell: Vector2i) -> void:
	if _world_state == null or _world_state.match_phase != WorldState.PHASE_PLAYING:
		return
	_radial_cell = cell
	_radial_world_pos = world_pos
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var wx: float = clampf(screen_pos.x - 110.0, 12.0, maxf(12.0, vp.x - 232.0))
	var wy: float = clampf(screen_pos.y - 110.0, 48.0, maxf(48.0, vp.y - 300.0))
	radial_wheel.position = Vector2(wx, wy)
	radial_sub_picker.visible = false

	var is_land: bool = _world_state.is_land_cell(cell.x, cell.y)
	var owner_id: int = _world_state.get_owner_at(cell.x, cell.y)
	var p_id: int = _world_state.player_nation_id
	var is_ally: bool = (owner_id > 0 and owner_id != p_id and _world_state.are_allied(p_id, owner_id))
	var has_port := false
	var p_n: NationData = _world_state.get_player_nation()
	if p_n != null:
		for sid: int in p_n.structure_ids:
			var st: StructureData = _world_state.get_structure(sid)
			if st != null and not st.is_constructing and st.level >= 1 and st.type == StructureData.TYPE_PORT:
				has_port = true
				break

	var near_st: StructureData = _world_state.find_structure_near(world_pos, 22.0)
	var has_own_st: bool = (near_st != null and near_st.nation_id == p_id)

	# Top = Attack (crossed swords), Left = Upgrade (arrow up), Right = Boat (boat), Bottom = Ally (handshake)
	radial_attack_btn.text = "Attack"
	radial_attack_btn.disabled = not is_land or is_ally

	if has_own_st:
		radial_build_btn.text = "Upgrade" if near_st.can_upgrade() else "Max Lv"
		radial_build_btn.disabled = not near_st.can_upgrade()
	else:
		radial_build_btn.text = "Upgrade"
		radial_build_btn.disabled = (owner_id != p_id)

	radial_warship_btn.text = "Boat"
	radial_warship_btn.disabled = not (has_port or (is_land and not is_ally))

	radial_dip_btn.text = "Ally"
	radial_dip_btn.disabled = (owner_id <= 0 or owner_id == p_id)

	radial_missile_btn.visible = false
	radial_info_btn.visible = false
	radial_menu.visible = true
	radial_wheel.queue_redraw()
	AudioManager.play_panel_open()


func close_radial_menu() -> void:
	if radial_menu.visible:
		radial_menu.visible = false
		radial_sub_picker.visible = false
		AudioManager.play_panel_close()


func _on_radial_bg_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			close_radial_menu()


func _on_radial_attack_pressed() -> void:
	AudioManager.play_ui_tap()
	var c := _radial_cell
	close_radial_menu()
	radial_attack_requested.emit(c)


func _on_radial_warship_pressed() -> void:
	AudioManager.play_ui_tap()
	var c := _radial_cell
	var p_id: int = _world_state.player_nation_id if _world_state != null else 0
	var is_land: bool = _world_state != null and _world_state.is_land_cell(c.x, c.y)
	close_radial_menu()
	if is_land and _world_state != null and _world_state.should_use_sea_crossing(p_id, c):
		radial_attack_requested.emit(c)
	else:
		radial_warship_requested.emit(c)


func _on_radial_dip_pressed() -> void:
	AudioManager.play_ui_tap()
	var oid: int = _world_state.get_owner_at(_radial_cell.x, _radial_cell.y) if _world_state != null else 0
	close_radial_menu()
	if oid > 0 and oid != _world_state.player_nation_id:
		if not _world_state.are_allied(_world_state.player_nation_id, oid):
			request_alliance_requested.emit(oid)
		show_diplomacy_panel(oid)


func _on_radial_info_pressed() -> void:
	close_radial_menu()


func _on_radial_build_pressed() -> void:
	AudioManager.play_ui_tap()
	if _world_state != null:
		var near_st: StructureData = _world_state.find_structure_near(_radial_world_pos, 22.0)
		if near_st != null and near_st.nation_id == _world_state.player_nation_id:
			var sid: int = near_st.id
			close_radial_menu()
			show_selected_structure(sid)
			if near_st.can_upgrade():
				upgrade_structure_requested.emit(sid)
			return
	_populate_radial_subpicker([
		["Town", StructureData.TYPE_TOWN, town_btn.icon],
		["Factory", StructureData.TYPE_FACTORY, factory_btn.icon],
		["Port", StructureData.TYPE_PORT, port_btn.icon],
		["Defense", StructureData.TYPE_DEFENSE_POST, defense_btn.icon],
		["Silo", StructureData.TYPE_MISSILE_SILO, silo_btn.icon],
		["SAM", StructureData.TYPE_SAM_LAUNCHER, sam_btn.icon],
	], true)


func _on_radial_missile_pressed() -> void:
	AudioManager.play_ui_tap()
	_populate_radial_subpicker([
		["Atom (%s)" % StructureData.format_pesos(MissileUnit.get_cost(MissileUnit.KIND_ATOM)), MissileUnit.KIND_ATOM, atom_dock_btn.icon],
		["H-Bomb (%s)" % StructureData.format_pesos(MissileUnit.get_cost(MissileUnit.KIND_HYDROGEN)), MissileUnit.KIND_HYDROGEN, hbomb_dock_btn.icon],
		["MIRV (%s)" % StructureData.format_pesos(MissileUnit.get_cost(MissileUnit.KIND_MIRV)), MissileUnit.KIND_MIRV, mirv_dock_btn.icon],
	], false)


func _populate_radial_subpicker(entries: Array, is_build: bool) -> void:
	for child in radial_sub_hbox.get_children():
		child.queue_free()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	radial_sub_picker.position = Vector2(
		clampf(radial_wheel.position.x - 85.0, 12.0, maxf(12.0, vp.x - 460.0)),
		minf(radial_wheel.position.y + 236.0, vp.y - 104.0)
	)
	for entry: Array in entries:
		var b := Button.new()
		b.text = str(entry[0])
		var key: String = str(entry[1])
		if entry.size() >= 3 and entry[2] is Texture2D:
			b.icon = entry[2]
		if is_build and _world_state != null:
			var chk: Dictionary = _world_state.can_place_structure(_world_state.player_nation_id, key, _radial_cell.x, _radial_cell.y)
			b.disabled = not bool(chk.get("ok", false))
		b.pressed.connect(func() -> void:
			AudioManager.play_ui_tap()
			var c := _radial_cell
			close_radial_menu()
			if is_build:
				radial_build_requested.emit(key, c)
			else:
				radial_missile_requested.emit(key, c)
		)
		radial_sub_hbox.add_child(b)
	radial_sub_picker.visible = true
