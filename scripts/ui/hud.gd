class_name GameHUD
extends CanvasLayer
## Modern, minimal strategy interface for Free-World expansion, Gold economy, and maritime infrastructure.

signal map_mode_toggled(political_enabled: bool)
signal reset_view_requested
signal camera_focus_requested(world_pos: Vector2, min_zoom: float)
signal camera_bookmark_save_requested(slot: int)
signal camera_bookmark_jump_requested(slot: int)
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
signal mp_quickplay_requested
signal mp_rooms_refresh_requested
signal mp_team_selected(team_id: int)
signal mp_room_options_changed(is_public: bool, team_mode: bool)
signal mp_room_modifiers_changed(options: Dictionary)
signal mp_spectate_requested(room_code: String)
signal chat_send_requested(channel: String, text: String)
signal leaderboard_open_requested(sort_by: String)
signal watch_replay_requested(match_id: String)
signal replay_speed_changed(mult: float)
signal exit_replay_requested
signal friend_invite_requested(friend_name: String, room_code: String)
signal account_login_requested(username: String, password: String)
signal account_register_requested(username: String, password: String)
signal account_change_password_requested(current_password: String, new_password: String)
signal account_logout_requested
signal pfp_file_selected(file_path: String)
signal friend_search_requested(query: String)
signal friend_request_send_requested(username: String)
signal friend_request_respond_requested(username: String, accept: bool)
signal friend_remove_requested(username: String)
signal friends_refresh_requested
signal menu_visibility_changed(is_open: bool)
signal quit_requested

const MAX_LEADERBOARD_ROWS := 7
const FRIENDS_SAVE_PATH := "user://friends.cfg"
const PROFILE_SAVE_PATH := "user://player_profile.cfg"
const SERVER_REGIONS := [
	{"name": "Manila, PH", "url": "ws://151.242.136.18:30041/ws"},
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
var _tex_hud_town := preload("res://assets/sprites/hud_town.png")
var _tex_hud_factory := preload("res://assets/sprites/hud_factory.png")
var _tex_hud_port := preload("res://assets/sprites/hud_port.png")
var _tex_hud_defense := preload("res://assets/sprites/hud_defense.png")
var _tex_hud_silo := preload("res://assets/sprites/hud_silo.png")
var _tex_hud_sam := preload("res://assets/sprites/hud_sam.png")
var _tex_hud_warship := preload("res://assets/sprites/hud_warship.png")
var _tex_hud_atom := preload("res://assets/sprites/hud_atom.png")
var _tex_hud_hbomb := preload("res://assets/sprites/hud_hbomb.png")
var _tex_hud_mirv := preload("res://assets/sprites/hud_mirv.png")

var _world_state: WorldState
var _selected_structure_id: int = 0
var _selected_dip_nation_id: int = 0
var _pending_alliance_from_id: int = 0
var _radial_cell: Vector2i = Vector2i(-1, -1)
var _radial_world_pos: Vector2 = Vector2.ZERO
var _political_mode: bool = true
var _leaderboard_minimized: bool = false
var _hotkeys_enabled: bool = true
var _commit_ratio: float = 0.25
var _toast_timer: float = 0.0
var _build_mode: String = ""
var _missile_mode: String = ""
var _lb_pool: Array[Dictionary] = []
var _lb_dirty: bool = false
var _exp_dirty: bool = false
var _lb_timer: float = 0.0
var _exp_timer: float = 0.0
var _last_dock_cost_key: int = -1
var _last_dock_afford_mask: int = -1
var _current_room_code: String = ""
var _pending_invite_friend: String = ""
var _pending_join_invite_code: String = ""
var _friends: Array[String] = []
var _is_spectating: bool = false
var _friends_return_to: String = "menu"
var _icon_close_16: ImageTexture
var _icon_play_16: ImageTexture
var _account_logged_in: bool = false
var _account_username: String = ""
var _local_avatar_frames: Array = []
var _local_avatar_delay_ms: int = 100
var _avatar_anim_ms: float = 0.0
var _avatar_last_step: int = -1
var _animated_pfp_nodes: Array[Dictionary] = []
var _dock_avatar_rect: TextureRect
var _victory_avatar_frames: Array = []
var _victory_avatar_delay_ms: int = 100
var _server_friends: Array = []
var _server_incoming: Array = []
var _server_outgoing: Array = []
var _avatar_cache_lookup: Callable = Callable()
var _account_stats: Dictionary = {}
var _last_toast_world_pos: Vector2 = Vector2(-1.0, -1.0)
var _threat_overlay: Control
var _threat_markers: Array[Dictionary] = []
var _mp_public_check: CheckBox
var _mp_team_mode_check: CheckBox
var _mp_team_option: OptionButton
var _mp_rooms_list: VBoxContainer
var _display_mode_option: OptionButton
var _ui_scale_option: OptionButton
var _victory_chart: Control
var _victory_history: Array[Dictionary] = []
var _mp_syncing_opts: bool = false
var _mp_speed_opt: OptionButton
var _mp_nonukes_check: CheckBox
var _mp_diff_opt: OptionButton
var _mp_preset_opt: OptionButton
var _sp_speed_opt: OptionButton
var _sp_nonukes_check: CheckBox
var _sp_diff_opt: OptionButton
var _sp_preset_opt: OptionButton
var _chat_panel: PanelContainer
var _chat_log: RichTextLabel
var _chat_input: LineEdit
var _chat_chan_btn: Button
var _chat_channel: String = "all"
var _chat_active: bool = false
var _rankings_card: PanelContainer
var _rankings_rows: VBoxContainer
var _rankings_tab_lb: Button
var _rankings_tab_hist: Button
var _rankings_mode: String = "leaderboard"
var _cached_leaderboard: Array = []
var _cached_my_matches: Array = []
var _sec_box: VBoxContainer
var _sec_cur_edit: LineEdit
var _sec_new_edit: LineEdit
var _sec_conf_edit: LineEdit
var _sec_status_lbl: Label
var _sec_eye_btn: Button
var _replay_controls_row: HBoxContainer
var _settings_card: PanelContainer
var _sp_diff_opt_init := false
var _rankings_sort: String = "elo"
var _rankings_tab_wins: Button
var _rankings_tab_land: Button
var _rankings_me_lbl: Label
var _gold_aid_amounts: Array[float] = [50000.0, 100000.0, 250000.0]
var _gold_aid_idx: int = 1
var _troop_aid_ratios: Array[float] = [0.15, 0.25, 0.50]
var _troop_aid_idx: int = 1
var _set_mute_check: CheckButton
var _set_master_sl: HSlider
var _set_music_sl: HSlider
var _set_sfx_sl: HSlider
var _set_amb_sl: HSlider
var _set_disp_opt: OptionButton
var _set_scale_opt: OptionButton
var _set_hotkeys_check: CheckButton
var _syncing_settings := false

@onready var root_control: Control = $Root
@onready var top_bar: PanelContainer = $Root/TopBar
@onready var clock_label: Label = $Root/TopBar/HBox/ClockLabel
@onready var map_mode_btn: Button = $Root/TopBar/HBox/MapModeBtn
@onready var reset_view_btn: Button = $Root/TopBar/HBox/ResetViewBtn
@onready var hotkeys_btn: Button = $Root/TopBar/HBox/HotkeysBtn
@onready var audio_btn: Button = $Root/TopBar/HBox/AudioBtn
@onready var menu_btn: Button = $Root/TopBar/HBox/MenuBtn

@onready var spawn_banner: PanelContainer = $Root/SpawnBanner
@onready var nation_name_edit: LineEdit = $Root/SpawnBanner/VBox/Row/NameEdit
@onready var ai_count_option: OptionButton = $Root/SpawnBanner/VBox/Row/AiOption

@onready var action_dock: PanelContainer = $Root/ActionDock
@onready var nation_color_swatch: ColorRect = $Root/ActionDock/HBox/IdentityBlock/NationColorSwatch
@onready var nation_name_label: Label = $Root/ActionDock/HBox/IdentityBlock/IdentityVBox/NationNameLabel
@onready var world_pct_label: Label = $Root/ActionDock/HBox/IdentityBlock/IdentityVBox/WorldPctLabel
@onready var troops_icon: TextureRect = $Root/ActionDock/HBox/TroopsBlock/TopRow/TroopsIcon
@onready var troops_rate_label: Label = $Root/ActionDock/HBox/TroopsBlock/TopRow/TroopsRateLabel
@onready var troops_label: Label = $Root/ActionDock/HBox/TroopsBlock/ValRow/TroopsLabel
@onready var troops_max_label: Label = $Root/ActionDock/HBox/TroopsBlock/ValRow/TroopsMaxLabel
@onready var troop_bar: Control = $Root/ActionDock/HBox/TroopsBlock/TroopBar
@onready var expand_btn: Button = $Root/ActionDock/HBox/AttackBlock/TopRow/ExpandBtn
@onready var attack_pct_label: Label = $Root/ActionDock/HBox/AttackBlock/TopRow/AttackPctLabel
@onready var commit_box: HBoxContainer = $Root/ActionDock/HBox/AttackBlock/CommitBox
@onready var commit_10_btn: Button = $Root/ActionDock/HBox/AttackBlock/CommitBox/Commit10Btn
@onready var commit_25_btn: Button = $Root/ActionDock/HBox/AttackBlock/CommitBox/Commit25Btn
@onready var commit_35_btn: Button = $Root/ActionDock/HBox/AttackBlock/CommitBox/Commit35Btn
@onready var commit_50_btn: Button = $Root/ActionDock/HBox/AttackBlock/CommitBox/Commit50Btn
@onready var commit_75_btn: Button = $Root/ActionDock/HBox/AttackBlock/CommitBox/Commit75Btn
@onready var attack_preview_label: Label = $Root/ActionDock/HBox/AttackBlock/AttackPreviewLabel
@onready var gold_icon: TextureRect = $Root/ActionDock/HBox/PesosBlock/TopRow/GoldIcon
@onready var gold_header_lbl: Label = $Root/ActionDock/HBox/PesosBlock/TopRow/GoldHeaderLbl
@onready var gold_rate_label: Label = $Root/ActionDock/HBox/PesosBlock/TopRow/GoldRateLabel
@onready var gold_label: Label = $Root/ActionDock/HBox/PesosBlock/GoldLabel
@onready var town_btn: Button = $Root/ActionDock/HBox/SlotsRow/TownBtn
@onready var factory_btn: Button = $Root/ActionDock/HBox/SlotsRow/FactoryBtn
@onready var port_btn: Button = $Root/ActionDock/HBox/SlotsRow/PortBtn
@onready var defense_btn: Button = $Root/ActionDock/HBox/SlotsRow/DefenseBtn
@onready var silo_btn: Button = $Root/ActionDock/HBox/SlotsRow/SiloBtn
@onready var sam_btn: Button = $Root/ActionDock/HBox/SlotsRow/SamBtn
@onready var warship_btn: Button = $Root/ActionDock/HBox/SlotsRow/WarshipBtn
@onready var atom_dock_btn: Button = $Root/ActionDock/HBox/SlotsRow/AtomDockBtn
@onready var hbomb_dock_btn: Button = $Root/ActionDock/HBox/SlotsRow/HbombDockBtn
@onready var mirv_dock_btn: Button = $Root/ActionDock/HBox/SlotsRow/MirvDockBtn

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
@onready var home_corners: Control = $Root/MenuOverlay/HomeCorners
@onready var avatar_preview: TextureRect = $Root/MenuOverlay/HomeCorners/ProfileRow/AvatarPreview
@onready var account_status_label: Label = $Root/MenuOverlay/HomeCorners/ProfileRow/AccountStatusLabel
@onready var account_btn: Button = $Root/MenuOverlay/HomeCorners/ProfileRow/AccountBtn
@onready var friends_btn: Button = $Root/MenuOverlay/HomeCorners/ProfileRow/FriendsBtn
@onready var menu_rankings_btn: Button = $Root/MenuOverlay/HomeCorners/TopRightRow/MenuRankingsBtn
@onready var menu_audio_btn: Button = $Root/MenuOverlay/HomeCorners/TopRightRow/MenuAudioBtn
@onready var quit_btn: Button = $Root/MenuOverlay/HomeCorners/QuitBtn

@onready var menu_card: PanelContainer = $Root/MenuOverlay/Center/MenuCard
@onready var logo_rect: TextureRect = $Root/MenuOverlay/Center/MenuCard/VBox/LogoRect
@onready var play_btn: Button = $Root/MenuOverlay/Center/MenuCard/VBox/PlayBtn
@onready var multiplayer_btn: Button = $Root/MenuOverlay/Center/MenuCard/VBox/MultiplayerBtn
@onready var new_match_btn: Button = $Root/MenuOverlay/Center/MenuCard/VBox/NewMatchBtn

@onready var sp_card: PanelContainer = $Root/MenuOverlay/Center/SingleplayerCard
@onready var sp_back_btn: Button = $Root/MenuOverlay/Center/SingleplayerCard/VBox/HeaderRow/SpBackBtn
@onready var sp_icon: TextureRect = $Root/MenuOverlay/Center/SingleplayerCard/VBox/HeaderRow/SpIcon
@onready var menu_name_edit: LineEdit = $Root/MenuOverlay/Center/SingleplayerCard/VBox/NameRow/MenuNameEdit
@onready var menu_ai_option: OptionButton = $Root/MenuOverlay/Center/SingleplayerCard/VBox/AiRow/MenuAiOption
@onready var sp_start_btn: Button = $Root/MenuOverlay/Center/SingleplayerCard/VBox/SpStartBtn

@onready var account_card: PanelContainer = $Root/MenuOverlay/Center/AccountCard
@onready var account_back_btn: Button = $Root/MenuOverlay/Center/AccountCard/VBox/HeaderRow/AccountBackBtn
@onready var profile_avatar: TextureRect = $Root/MenuOverlay/Center/AccountCard/VBox/ProfileHero/ProfileAvatar
@onready var profile_name_label: Label = $Root/MenuOverlay/Center/AccountCard/VBox/ProfileHero/MetaVBox/ProfileNameLabel
@onready var profile_rank_label: Label = $Root/MenuOverlay/Center/AccountCard/VBox/ProfileHero/MetaVBox/ProfileRankLabel
@onready var change_pfp_btn: Button = $Root/MenuOverlay/Center/AccountCard/VBox/ProfileHero/ChangePfpBtn
@onready var account_user_edit: LineEdit = $Root/MenuOverlay/Center/AccountCard/VBox/AccountUserEdit
@onready var pass_row: HBoxContainer = $Root/MenuOverlay/Center/AccountCard/VBox/PassRow
@onready var account_pass_edit: LineEdit = $Root/MenuOverlay/Center/AccountCard/VBox/PassRow/AccountPassEdit
@onready var pass_eye_btn: Button = $Root/MenuOverlay/Center/AccountCard/VBox/PassRow/PassEyeBtn
@onready var confirm_pass_row: HBoxContainer = $Root/MenuOverlay/Center/AccountCard/VBox/ConfirmPassRow
@onready var account_confirm_pass_edit: LineEdit = $Root/MenuOverlay/Center/AccountCard/VBox/ConfirmPassRow/AccountConfirmPassEdit
@onready var confirm_pass_eye_btn: Button = $Root/MenuOverlay/Center/AccountCard/VBox/ConfirmPassRow/ConfirmPassEyeBtn
@onready var login_btn: Button = $Root/MenuOverlay/Center/AccountCard/VBox/AuthBtnRow/LoginBtn
@onready var register_btn: Button = $Root/MenuOverlay/Center/AccountCard/VBox/AuthBtnRow/RegisterBtn
@onready var account_card_status: Label = $Root/MenuOverlay/Center/AccountCard/VBox/AccountCardStatus
@onready var logout_btn: Button = $Root/MenuOverlay/Center/AccountCard/VBox/LogoutBtn
@onready var pfp_file_dialog: FileDialog = $Root/PfpFileDialog

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
@onready var search_status_label: Label = $Root/MenuOverlay/Center/FriendsCard/VBox/SearchStatusLabel
@onready var search_results_box: VBoxContainer = $Root/MenuOverlay/Center/FriendsCard/VBox/SearchResultsBox
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
	ThemeFactory.apply_panel_variant(top_bar, "util_strip")
	ThemeFactory.apply_panel_variant(action_dock, "bottom_bar")
	ThemeFactory.apply_panel_variant(ping_badge, "flat")
	ThemeFactory.apply_panel_variant(menu_card, "flat")
	_icon_close_16 = _make_pixel_icon(_tex_close, Color.WHITE, 14)
	_icon_play_16 = _make_pixel_icon(_tex_play, Color.WHITE, 14)
	var icon_back_16: ImageTexture = _make_pixel_icon(_tex_back, Color.WHITE, 14)
	var icon_friends_16: ImageTexture = _make_pixel_icon(_tex_friends, Color.WHITE, 16)
	var icon_mp_16: ImageTexture = _make_pixel_icon(_tex_multiplayer, Color.WHITE, 16)
	var icon_audio_16: ImageTexture = _make_pixel_icon(_tex_audio, Color.WHITE, 15)

	logo_rect.texture = _tex_logo
	logo_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sp_icon.texture = _icon_play_16
	sp_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
	sp_card.visible = false
	mp_lobby_card.visible = false
	friends_card.visible = false
	account_card.visible = false
	home_corners.visible = true
	menu_card.visible = true
	menu_overlay.visible = true
	menu_overlay.color = Color(0, 0, 0, 0)

	_dock_avatar_rect = TextureRect.new()
	_dock_avatar_rect.name = "DockAvatarRect"
	_dock_avatar_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dock_avatar_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_dock_avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_dock_avatar_rect.visible = false
	nation_color_swatch.add_child(_dock_avatar_rect)
	var def_av := _build_tinted_icon(_tex_banner, _tex_banner_mask, Color(0.32, 0.56, 0.90), 32, 32)
	avatar_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	avatar_preview.texture = def_av
	profile_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	profile_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	profile_avatar.texture = def_av
	victory_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	victory_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	_apply_ui_variants_and_icons(icon_back_16, icon_friends_16, icon_mp_16, icon_audio_16)
	account_back_btn.icon = icon_back_16
	sp_back_btn.icon = icon_back_16
	_populate_spawn_controls()
	_setup_extra_hud_panels()
	_load_profile()
	_apply_saved_display_settings()
	_populate_server_regions()
	_load_friends()
	_init_leaderboard_pool()
	radial_wheel.draw.connect(_on_radial_wheel_draw)
	troop_bar.draw.connect(_on_troop_bar_draw)
	_apply_action_dock_icons(Color(0.32, 0.56, 0.90))
	for icon_ctrl: CanvasItem in [
		victory_icon, conn_bar_icon,
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
		gold_icon, troops_icon, expand_btn,
		town_btn, factory_btn, port_btn, defense_btn, silo_btn, sam_btn,
		warship_btn, atom_dock_btn, hbomb_dock_btn, mirv_dock_btn,
	]:
		pixel_ctrl.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for dock_ctrl: Control in [
		clock_label, map_mode_btn, reset_view_btn, hotkeys_btn, audio_btn, menu_btn,
		expand_btn, commit_10_btn, commit_25_btn, commit_35_btn, commit_50_btn, commit_75_btn,
		troops_rate_label, troops_max_label, gold_rate_label, attack_pct_label,
	]:
		dock_ctrl.add_theme_font_size_override("font_size", 10)
	nation_name_label.add_theme_font_size_override("font_size", 13)
	($Root/ActionDock/HBox/TroopsBlock/TopRow/HeaderLbl as Label).add_theme_font_size_override("font_size", 9)
	world_pct_label.add_theme_font_size_override("font_size", 9)
	attack_preview_label.add_theme_font_size_override("font_size", 9)
	gold_header_lbl.add_theme_font_size_override("font_size", 9)
	troops_label.add_theme_font_size_override("font_size", 15)
	gold_label.add_theme_font_size_override("font_size", 15)
	expand_btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	expand_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	expand_btn.text = "Explore"
	for slot_btn: Button in [
		town_btn, factory_btn, port_btn, defense_btn, silo_btn, sam_btn,
		warship_btn, atom_dock_btn, hbomb_dock_btn, mirv_dock_btn,
	]:
		slot_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		slot_btn.add_theme_font_size_override("font_size", 9)
		slot_btn.add_theme_constant_override("v_separation", 0)
		slot_btn.custom_minimum_size = Vector2(42, 52)
		var key_lbl := slot_btn.get_node_or_null("TopMeta/KeyLbl") as Label
		if key_lbl != null:
			key_lbl.add_theme_font_size_override("font_size", 8)
		var cnt_lbl := slot_btn.get_node_or_null("TopMeta/CountLbl") as Label
		if cnt_lbl != null:
			cnt_lbl.add_theme_font_size_override("font_size", 8)

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
	menu_audio_btn.pressed.connect(func() -> void:
		AudioManager.play_ui_tap()
		_sync_settings_controls()
		_show_menu_page("settings")
	)
	menu_rankings_btn.pressed.connect(func() -> void:
		AudioManager.play_ui_tap()
		_show_menu_page("rankings")
		leaderboard_open_requested.emit(_rankings_sort)
		_render_rankings_rows()
	)
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
			var amt: float = _gold_aid_amounts[clampi(_gold_aid_idx, 0, _gold_aid_amounts.size() - 1)]
			donate_gold_requested.emit(_selected_dip_nation_id, amt)
	)
	donate_troops_btn.pressed.connect(func() -> void:
		if _selected_dip_nation_id > 0:
			AudioManager.play_ui_tap()
			var rat: float = _troop_aid_ratios[clampi(_troop_aid_idx, 0, _troop_aid_ratios.size() - 1)]
			donate_troops_requested.emit(_selected_dip_nation_id, rat)
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

	commit_10_btn.pressed.connect(func() -> void: set_commit_ratio(0.10))
	commit_25_btn.pressed.connect(func() -> void: set_commit_ratio(0.25))
	commit_35_btn.pressed.connect(func() -> void: set_commit_ratio(0.35))
	commit_50_btn.pressed.connect(func() -> void: set_commit_ratio(0.50))
	commit_75_btn.pressed.connect(func() -> void: set_commit_ratio(0.75))

	play_btn.pressed.connect(func() -> void:
		var in_match: bool = _world_state != null and _world_state.match_phase != WorldState.PHASE_SPAWN_SELECT
		if in_match:
			_on_play_pressed()
		else:
			AudioManager.play_ui_tap()
			_show_menu_page("singleplayer")
	)
	sp_start_btn.pressed.connect(_on_play_pressed)
	sp_back_btn.pressed.connect(func() -> void:
		AudioManager.play_ui_tap()
		save_player_name(menu_name_edit.text)
		_show_menu_page("home")
	)
	multiplayer_btn.pressed.connect(func() -> void:
		AudioManager.play_ui_tap()
		save_player_name(menu_name_edit.text)
		_show_menu_page("mp_lobby")
		mp_rooms_refresh_requested.emit()
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
		_submit_friend_search(friend_name_edit.text)
	)
	friend_name_edit.text_submitted.connect(func(txt: String) -> void:
		AudioManager.play_ui_tap()
		_submit_friend_search(txt)
	)
	change_pfp_btn.pressed.connect(func() -> void:
		AudioManager.play_ui_tap()
		pfp_file_dialog.popup_centered_ratio(0.65)
	)
	pfp_file_dialog.file_selected.connect(func(path: String) -> void:
		pfp_file_selected.emit(path)
	)
	account_btn.pressed.connect(func() -> void:
		AudioManager.play_ui_tap()
		_show_menu_page("account")
	)
	account_back_btn.pressed.connect(func() -> void:
		AudioManager.play_ui_tap()
		_show_menu_page("home")
	)
	login_btn.pressed.connect(func() -> void:
		AudioManager.play_ui_tap()
		account_card_status.text = "Signing in..."
		account_login_requested.emit(account_user_edit.text.strip_edges(), account_pass_edit.text)
	)
	register_btn.pressed.connect(func() -> void:
		AudioManager.play_ui_tap()
		var p_txt: String = account_pass_edit.text
		var c_txt: String = account_confirm_pass_edit.text
		if p_txt.length() < 4:
			account_card_status.text = "Password must be at least 4 characters."
			return
		if c_txt.is_empty():
			account_card_status.text = "Please confirm your password to create an account."
			return
		if p_txt != c_txt:
			account_card_status.text = "Passwords do not match."
			return
		account_card_status.text = "Creating permanent account..."
		account_register_requested.emit(account_user_edit.text.strip_edges(), p_txt)
	)
	pass_eye_btn.toggled.connect(func(pressed: bool) -> void:
		AudioManager.play_ui_tap()
		_set_password_visible(pressed)
	)
	confirm_pass_eye_btn.toggled.connect(func(pressed: bool) -> void:
		AudioManager.play_ui_tap()
		_set_password_visible(pressed)
	)
	logout_btn.pressed.connect(func() -> void:
		AudioManager.play_ui_tap()
		account_logout_requested.emit()
	)
	accept_invite_btn.pressed.connect(func() -> void:
		AudioManager.play_ui_tap()
		invite_row.visible = false
		_refresh_friends_badge()
		if not _pending_join_invite_code.is_empty():
			_show_menu_page("mp_lobby")
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
		_show_menu_page("home")
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
		if not _syncing_settings and _set_mute_check != null:
			_syncing_settings = true
			_set_mute_check.button_pressed = t
			_syncing_settings = false
	)
	master_slider.value_changed.connect(func(v: float) -> void:
		AudioManager.set_bus_volume("Master", v)
		if not _syncing_settings and _set_master_sl != null:
			_syncing_settings = true
			_set_master_sl.value = v
			_syncing_settings = false
	)
	music_slider.value_changed.connect(func(v: float) -> void:
		AudioManager.set_bus_volume("Music", v)
		if not _syncing_settings and _set_music_sl != null:
			_syncing_settings = true
			_set_music_sl.value = v
			_syncing_settings = false
	)
	sfx_slider.value_changed.connect(func(v: float) -> void:
		AudioManager.set_bus_volume("SFX", v)
		if not _syncing_settings and _set_sfx_sl != null:
			_syncing_settings = true
			_set_sfx_sl.value = v
			_syncing_settings = false
	)
	ambience_slider.value_changed.connect(func(v: float) -> void:
		AudioManager.set_bus_volume("Ambience", v)
		if not _syncing_settings and _set_amb_sl != null:
			_syncing_settings = true
			_set_amb_sl.value = v
			_syncing_settings = false
	)
	_update_action_dock_buttons()
	_update_commit_buttons()
	_update_hotkeys_button()


func _show_menu_page(page: String) -> void:
	var is_home: bool = (page == "home")
	menu_overlay.color = Color(0, 0, 0, 0) if is_home else Color(0.03, 0.05, 0.09, 0.56)
	home_corners.visible = is_home
	menu_card.visible = is_home
	sp_card.visible = (page == "singleplayer")
	mp_lobby_card.visible = (page == "mp_lobby")
	friends_card.visible = (page == "friends")
	account_card.visible = (page == "account")
	if _rankings_card != null:
		_rankings_card.visible = (page == "rankings")
	if _settings_card != null:
		_settings_card.visible = (page == "settings")


func _make_trophy_icon() -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var gold := Color(0.98, 0.84, 0.34, 1.0)
	for y in range(2, 14):
		for x in range(2, 14):
			var cup: bool = (y >= 2 and y <= 7 and x >= 4 and x <= 11)
			var handles: bool = (y >= 3 and y <= 5 and (x == 3 or x == 12))
			var stem: bool = (y >= 8 and y <= 11 and x >= 7 and x <= 8)
			var base: bool = (y >= 12 and y <= 13 and x >= 5 and x <= 10)
			if cup or handles or stem or base:
				img.set_pixel(x, y, gold)
	return ImageTexture.create_from_image(img)


func _make_gear_icon() -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var col := Color(0.86, 0.92, 0.98, 1.0)
	for y in range(16):
		var dy := float(y) - 7.5
		for x in range(16):
			var dx := float(x) - 7.5
			var d := sqrt(dx * dx + dy * dy)
			var ang := atan2(dy, dx)
			var tooth := cos(ang * 6.0) > 0.45 and d >= 5.0 and d <= 7.2
			var ring := d >= 3.2 and d <= 5.4
			if tooth or ring:
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


func _apply_ui_variants_and_icons(icon_back_16: ImageTexture, icon_friends_16: ImageTexture, icon_mp_16: ImageTexture, icon_audio_16: ImageTexture) -> void:
	for btn: Button in [play_btn, sp_start_btn, create_room_btn, mp_start_btn, add_friend_btn, accept_invite_btn, st_upgrade_btn, victory_new_match_btn, spec_new_match_btn, alliance_accept_btn, login_btn, register_btn]:
		ThemeFactory.apply_button_variant(btn, "primary")
	for btn: Button in [multiplayer_btn, mp_connect_btn, victory_inspect_btn, spec_continue_btn, donate_gold_btn, donate_troops_btn, change_pfp_btn]:
		ThemeFactory.apply_button_variant(btn, "secondary")
	for btn: Button in [sp_back_btn, mp_disconnect_btn, friends_back_btn, new_match_btn, account_back_btn, friends_btn, account_btn, menu_rankings_btn, menu_audio_btn]:
		ThemeFactory.apply_button_variant(btn, "back")
	for btn: Button in [quit_btn, alliance_decline_btn, logout_btn]:
		ThemeFactory.apply_button_variant(btn, "danger")
	for btn: Button in [map_mode_btn, reset_view_btn, hotkeys_btn, audio_btn, menu_btn, lb_toggle_btn, copy_code_btn, mp_friends_btn, pass_eye_btn, confirm_pass_eye_btn]:
		ThemeFactory.apply_button_variant(btn, "ghost")
	pass_eye_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm_pass_eye_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_set_password_visible(false)
	for btn: Button in [commit_10_btn, commit_25_btn, commit_35_btn, commit_50_btn, commit_75_btn]:
		ThemeFactory.set_commit_pill_active(btn, false)
	for btn: Button in [st_close_btn, dip_close_btn, audio_close_btn, dismiss_invite_btn, radial_close_btn]:
		_style_close_button(btn)
	for btn: Button in [expand_btn, town_btn, factory_btn, port_btn, defense_btn, silo_btn, sam_btn, warship_btn, atom_dock_btn, hbomb_dock_btn, mirv_dock_btn]:
		ThemeFactory.apply_button_variant(btn, "dock_slot")

	play_btn.icon = _icon_play_16
	sp_start_btn.icon = _icon_play_16
	mp_start_btn.icon = _icon_play_16
	accept_invite_btn.icon = _icon_play_16
	sp_back_btn.icon = icon_back_16
	mp_disconnect_btn.icon = icon_back_16
	friends_back_btn.icon = icon_back_16
	quit_btn.icon = _icon_close_16
	multiplayer_btn.icon = icon_mp_16
	friends_btn.icon = icon_friends_16
	mp_friends_btn.icon = icon_friends_16
	menu_rankings_btn.icon = _make_trophy_icon()
	menu_audio_btn.icon = _make_gear_icon()
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
	for cnt in [0, 4, 6, 8, 12, 16, 20, 23]:
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


func set_avatar_cache_lookup(cb: Callable) -> void:
	_avatar_cache_lookup = cb


func set_account_error(msg: String) -> void:
	account_card_status.text = msg
	account_card_status.modulate = Color(1.0, 0.56, 0.52, 1.0)


func set_account_state(logged_in: bool, acct_username: String, status_msg: String = "", stats: Dictionary = {}) -> void:
	_account_logged_in = logged_in
	_account_username = acct_username.strip_edges()
	if not stats.is_empty():
		_account_stats = stats.duplicate()
	elif not _account_logged_in:
		_account_stats.clear()
	account_card_status.modulate = Color(0.75, 0.86, 0.96, 0.92)
	if _account_logged_in and not _account_username.is_empty():
		menu_name_edit.text = _account_username
		nation_name_edit.text = _account_username
		menu_name_edit.editable = false
		nation_name_edit.editable = false
		var gp: int = int(_account_stats.get("games_played", 0))
		var wins_cnt: int = int(_account_stats.get("wins", 0))
		var elo_val: int = int(_account_stats.get("elo", 1000))
		var r_title: String = str(_account_stats.get("rank_title", "Silver III"))
		if r_title.is_empty():
			r_title = "Silver III"
		var wr: float = (float(wins_cnt) * 100.0 / float(gp)) if gp > 0 else 0.0
		account_status_label.text = "%s · %s (%d ELO)" % [_account_username, r_title, elo_val]
		profile_name_label.text = "@%s" % _account_username
		profile_rank_label.text = "%s · %d ELO · %dW-%dL (%.0f%%)" % [r_title, elo_val, wins_cnt, maxi(0, gp - wins_cnt), wr]
		if _rankings_me_lbl != null:
			_rankings_me_lbl.text = "Your Rank: @%s · %s · %d ELO · %dW-%dL (%.0f%%)" % [_account_username, r_title, elo_val, wins_cnt, maxi(0, gp - wins_cnt), wr]
		account_btn.text = "Profile"
		account_user_edit.text = _account_username
		account_user_edit.editable = false
		account_pass_edit.text = ""
		account_confirm_pass_edit.text = ""
		_set_password_visible(false)
		pass_row.visible = false
		confirm_pass_row.visible = false
		login_btn.visible = false
		register_btn.visible = false
		logout_btn.visible = true
		if _sec_box != null:
			_sec_box.visible = true
			if _sec_status_lbl != null:
				_sec_status_lbl.text = ""
		account_card_status.text = status_msg if not status_msg.is_empty() else "Signed in as %s (permanent name locked)." % _account_username
	else:
		menu_name_edit.editable = true
		nation_name_edit.editable = true
		account_status_label.text = "Guest"
		profile_name_label.text = "Guest Commander"
		profile_rank_label.text = "Sign in to track ELO, Rank & Match History"
		if _rankings_me_lbl != null:
			_rankings_me_lbl.text = "Your Rank: Guest · Sign in to climb Silver → Sovereign"
		account_btn.text = "Sign In"
		account_user_edit.editable = true
		pass_row.visible = true
		confirm_pass_row.visible = true
		login_btn.visible = true
		register_btn.visible = true
		logout_btn.visible = false
		if _sec_box != null:
			_sec_box.visible = false
			if _sec_cur_edit != null:
				_sec_cur_edit.text = ""
				_sec_new_edit.text = ""
				_sec_conf_edit.text = ""
		account_card_status.text = status_msg if not status_msg.is_empty() else "Sign in or create a permanent account."
	_refresh_friends_ui()


func _make_eye_icon(visible_eye: bool) -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var col := Color(0.86, 0.90, 0.95, 0.95)
	for y in range(16):
		var dy := float(y) - 7.5
		for x in range(16):
			var dx := float(x) - 7.5
			var ell: float = (dx * dx) / 42.25 + (dy * dy) / 14.44
			var in_outline: bool = ell >= 0.56 and ell <= 1.02
			var in_pupil: bool = (dx * dx + dy * dy) <= 4.6
			var in_slash: bool = (not visible_eye) and absf(dx + dy) <= 0.85 and absf(dx) <= 5.5
			if in_outline or in_pupil or in_slash:
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


func _set_password_visible(shown: bool) -> void:
	account_pass_edit.secret = not shown
	account_confirm_pass_edit.secret = not shown
	pass_eye_btn.set_pressed_no_signal(shown)
	confirm_pass_eye_btn.set_pressed_no_signal(shown)
	var tex := _make_eye_icon(shown)
	pass_eye_btn.icon = tex
	confirm_pass_eye_btn.icon = tex


func set_local_avatar(frames: Array, delay_ms: int = 100) -> void:
	_local_avatar_frames = frames.duplicate()
	_local_avatar_delay_ms = clampi(delay_ms, 40, 1000)
	_avatar_last_step = -1
	if not _local_avatar_frames.is_empty():
		var tex: Texture2D = _local_avatar_frames[0] as Texture2D
		avatar_preview.texture = tex
		profile_avatar.texture = tex
		if _dock_avatar_rect != null:
			_dock_avatar_rect.texture = tex
			_dock_avatar_rect.visible = true
	else:
		var col := Color(0.32, 0.56, 0.90)
		var def_tex := _build_tinted_icon(_tex_banner, _tex_banner_mask, col, 32, 32)
		avatar_preview.texture = def_tex
		profile_avatar.texture = def_tex
		if _dock_avatar_rect != null:
			_dock_avatar_rect.texture = null
			_dock_avatar_rect.visible = false


func _submit_friend_search(raw_q: String) -> void:
	var q: String = raw_q.strip_edges()
	if q.is_empty():
		search_status_label.visible = false
		search_results_box.visible = false
		return
	if not _account_logged_in:
		search_status_label.text = "Sign in (Account) to search players in the database."
		search_status_label.visible = true
		search_results_box.visible = false
		return
	search_status_label.text = "Searching database for '%s'..." % q
	search_status_label.visible = true
	friend_search_requested.emit(q)


func _frames_for_user_dict(u: Dictionary) -> Dictionary:
	var b64: String = str(u.get("avatar_b64", ""))
	if not b64.is_empty():
		var f_cnt: int = maxi(1, int(u.get("avatar_frames", 1)))
		var frames: Array[ImageTexture] = GifDecoder.textures_from_strip_b64(b64, f_cnt)
		if not frames.is_empty():
			return {"frames": frames, "delay_ms": clampi(int(u.get("avatar_delay_ms", 100)), 40, 1000)}
	if _avatar_cache_lookup.is_valid():
		var cached: Variant = _avatar_cache_lookup.call(str(u.get("username", "")))
		if cached is Dictionary and not (cached as Dictionary).is_empty():
			return cached as Dictionary
	return {}


func _make_avatar_thumb(frames: Array, delay_ms: int, fallback_col: Color) -> TextureRect:
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(22, 22)
	tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if not frames.is_empty():
		tr.texture = frames[0] as Texture2D
		if frames.size() > 1:
			_animated_pfp_nodes.append({"node": tr, "frames": frames, "delay_ms": clampi(delay_ms, 40, 1000), "step": -1})
	else:
		tr.texture = _build_tinted_icon(_tex_banner, _tex_banner_mask, fallback_col, 20, 20)
	return tr


func update_search_results(query: String, users: Array) -> void:
	for child in search_results_box.get_children():
		child.queue_free()
	if query.strip_edges().is_empty():
		search_status_label.visible = false
		search_results_box.visible = false
		return
	if users.is_empty():
		search_status_label.text = "No player '%s' found in database." % query
		search_status_label.visible = true
		search_results_box.visible = false
		return
	search_status_label.text = "Database results (%d):" % users.size()
	search_status_label.visible = true
	search_results_box.visible = true
	for uv: Variant in users:
		if not (uv is Dictionary):
			continue
		var u := uv as Dictionary
		var uname: String = str(u.get("username", ""))
		var rel: String = str(u.get("relation", "none"))
		var is_online: bool = bool(u.get("online", false))
		var status_txt: String = str(u.get("last_seen_text", "Offline"))
		var av := _frames_for_user_dict(u)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(_make_avatar_thumb(av.get("frames", []), int(av.get("delay_ms", 100)), Color(0.45, 0.72, 0.96)))

		var nm := Label.new()
		nm.text = "%s · %s" % [uname, status_txt]
		nm.modulate = Color(0.68, 0.98, 0.76) if is_online else Color(0.84, 0.88, 0.94)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.clip_text = true
		row.add_child(nm)

		var act_btn := Button.new()
		ThemeFactory.apply_button_variant(act_btn, "primary" if rel == "none" or rel == "incoming" else "secondary")
		match rel:
			"friend":
				act_btn.text = "Friends"
				act_btn.disabled = true
			"outgoing":
				act_btn.text = "Pending"
				act_btn.disabled = true
			"incoming":
				act_btn.text = "Accept"
				var uc_acc := uname
				act_btn.pressed.connect(func() -> void:
					AudioManager.play_ui_tap()
					act_btn.disabled = true
					friend_request_respond_requested.emit(uc_acc, true)
				)
			_:
				act_btn.text = "Add Friend"
				var uc_add := uname
				act_btn.pressed.connect(func() -> void:
					AudioManager.play_ui_tap()
					act_btn.disabled = true
					act_btn.text = "Sent"
					friend_request_send_requested.emit(uc_add)
				)
		row.add_child(act_btn)
		search_results_box.add_child(row)


func update_friends_overview(friends: Array, incoming: Array, outgoing: Array, invites: Array) -> void:
	_server_friends = friends.duplicate()
	_server_incoming = incoming.duplicate()
	_server_outgoing = outgoing.duplicate()
	for iv: Variant in invites:
		if iv is Dictionary:
			var idict := iv as Dictionary
			var from_u: String = str(idict.get("from_username", ""))
			var code: String = str(idict.get("room_code", ""))
			if not code.is_empty():
				show_incoming_invite(from_u, code)
	_refresh_friends_ui()
	_refresh_friends_badge()


func open_friends_page(return_to: String = "menu") -> void:
	AudioManager.play_ui_tap()
	_friends_return_to = return_to
	_show_menu_page("friends")
	menu_overlay.visible = true
	search_status_label.visible = false
	search_results_box.visible = false
	_refresh_friends_ui()
	if _account_logged_in:
		friends_refresh_requested.emit()


func _on_friends_back_pressed() -> void:
	AudioManager.play_ui_tap()
	_show_menu_page("mp_lobby" if _friends_return_to == "mp_lobby" else "home")


func _refresh_friends_badge() -> void:
	var badge_cnt: int = _server_incoming.size() + (1 if invite_row.visible else 0)
	var label_txt := "Friends (%d)" % badge_cnt if badge_cnt > 0 else "Friends"
	friends_btn.text = label_txt
	mp_friends_btn.text = label_txt
	if not _current_room_code.is_empty():
		friends_hint_label.text = "Room Code: %s — click Invite to send to friends." % _current_room_code
	elif _account_logged_in:
		friends_hint_label.text = "Online friends appear first, down to longest offline."
	else:
		friends_hint_label.text = "Sign in to search DB players & see live online status."


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
	_animated_pfp_nodes.clear()
	for child in friends_rows.get_children():
		child.queue_free()

	if _account_logged_in:
		if not _server_incoming.is_empty():
			var inc_hdr := Label.new()
			inc_hdr.text = "INCOMING REQUESTS (%d)" % _server_incoming.size()
			inc_hdr.modulate = Color(0.98, 0.84, 0.42, 0.95)
			friends_rows.add_child(inc_hdr)
			for iv: Variant in _server_incoming:
				if not (iv is Dictionary):
					continue
				var inc := iv as Dictionary
				var from_u: String = str(inc.get("username", ""))
				var av := _frames_for_user_dict(inc)
				var r := HBoxContainer.new()
				r.add_theme_constant_override("separation", 6)
				r.add_child(_make_avatar_thumb(av.get("frames", []), int(av.get("delay_ms", 100)), Color(0.95, 0.78, 0.35)))
				var nm := Label.new()
				nm.text = from_u
				nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				nm.clip_text = true
				r.add_child(nm)
				var acc_b := Button.new()
				acc_b.text = "Accept"
				ThemeFactory.apply_button_variant(acc_b, "primary")
				var fu_cap := from_u
				acc_b.pressed.connect(func() -> void:
					AudioManager.play_ui_tap()
					friend_request_respond_requested.emit(fu_cap, true)
				)
				r.add_child(acc_b)
				var dec_b := Button.new()
				_style_close_button(dec_b)
				dec_b.tooltip_text = "Decline"
				dec_b.pressed.connect(func() -> void:
					AudioManager.play_ui_tap()
					friend_request_respond_requested.emit(fu_cap, false)
				)
				r.add_child(dec_b)
				friends_rows.add_child(r)

		if _server_friends.is_empty():
			var empty_srv := Label.new()
			empty_srv.text = "No friends yet — search for players above to add!"
			empty_srv.modulate = Color(0.64, 0.72, 0.82, 0.85)
			friends_rows.add_child(empty_srv)
		else:
			for fv: Variant in _server_friends:
				if not (fv is Dictionary):
					continue
				var f := fv as Dictionary
				var f_name: String = str(f.get("username", ""))
				var online: bool = bool(f.get("online", false))
				var seen_txt: String = str(f.get("last_seen_text", "Offline"))
				var av := _frames_for_user_dict(f)

				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", 6)

				var dot := ColorRect.new()
				dot.custom_minimum_size = Vector2(8, 8)
				dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				dot.color = Color(0.28, 0.94, 0.54) if online else Color(0.45, 0.50, 0.58)
				row.add_child(dot)

				row.add_child(_make_avatar_thumb(av.get("frames", []), int(av.get("delay_ms", 100)), Color(0.32, 0.62, 0.96) if online else Color(0.45, 0.50, 0.58)))

				var nm := Label.new()
				var rank_s: String = str(f.get("rank_title", ""))
				var elo_v: int = int(f.get("elo", 0))
				nm.text = ("%s (%s · %d)" % [f_name, rank_s, elo_v]) if elo_v > 0 and not rank_s.is_empty() else f_name
				nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				nm.clip_text = true
				row.add_child(nm)

				var st_lbl := Label.new()
				st_lbl.text = seen_txt
				st_lbl.modulate = Color(0.46, 0.96, 0.62) if online else Color(0.60, 0.68, 0.78, 0.86)
				row.add_child(st_lbl)

				var inv_btn := Button.new()
				inv_btn.text = "Invite"
				ThemeFactory.apply_button_variant(inv_btn, "secondary")
				var f_cap := f_name
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
					friend_remove_requested.emit(f_cap)
				)
				row.add_child(rm_btn)
				friends_rows.add_child(row)

		if not _server_outgoing.is_empty():
			var out_names := PackedStringArray()
			for ov: Variant in _server_outgoing:
				if ov is Dictionary:
					out_names.append(str((ov as Dictionary).get("username", "")))
			if not out_names.is_empty():
				var out_lbl := Label.new()
				out_lbl.text = "Pending Sent: " + ", ".join(out_names)
				out_lbl.modulate = Color(0.62, 0.70, 0.80, 0.80)
				out_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				friends_rows.add_child(out_lbl)
		return

	if _friends.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "Sign in to view online friends or search players."
		empty_lbl.modulate = Color(0.64, 0.72, 0.82, 0.85)
		friends_rows.add_child(empty_lbl)
		return
	for f_name: String in _friends:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(8, 8)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.color = Color(0.45, 0.50, 0.58)
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
		_show_menu_page("mp_lobby")
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
	if event is InputEventKey:
		var k_any := event as InputEventKey
		if k_any.pressed and not k_any.echo and k_any.alt_pressed and (k_any.keycode == KEY_ENTER or k_any.keycode == KEY_KP_ENTER):
			_toggle_fullscreen_hotkey()
			get_viewport().set_input_as_handled()
			return
		if k_any.pressed and not k_any.echo and _chat_active and _chat_input != null and _chat_panel != null and _chat_panel.visible and not menu_overlay.visible:
			if k_any.keycode == KEY_ENTER or k_any.keycode == KEY_KP_ENTER:
				if not _chat_input.has_focus():
					_chat_input.grab_focus()
					get_viewport().set_input_as_handled()
					return
			elif k_any.keycode == KEY_TAB and _chat_input.has_focus():
				_toggle_chat_channel()
				get_viewport().set_input_as_handled()
				return
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
	if nation_name_edit.has_focus() or menu_name_edit.has_focus() or mp_server_edit.has_focus() or mp_room_edit.has_focus() or friend_name_edit.has_focus() or account_user_edit.has_focus() or account_pass_edit.has_focus():
		return
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			if ke.ctrl_pressed and ke.keycode in [KEY_1, KEY_2, KEY_3, KEY_4]:
				var b_slot: int = (ke.keycode - KEY_1) + 1
				camera_bookmark_save_requested.emit(b_slot)
				show_toast("Saved camera bookmark [%d] (Alt+%d to jump)" % [b_slot, b_slot], false)
				AudioManager.play_ui_tap()
				get_viewport().set_input_as_handled()
				return
			if ke.alt_pressed and ke.keycode in [KEY_1, KEY_2, KEY_3, KEY_4]:
				var j_slot: int = (ke.keycode - KEY_1) + 1
				camera_bookmark_jump_requested.emit(j_slot)
				get_viewport().set_input_as_handled()
				return
			if ke.keycode == KEY_SPACE or ke.keycode == KEY_HOME:
				_snap_camera_to_capital()
				get_viewport().set_input_as_handled()
				return
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
	_avatar_anim_ms += delta * 1000.0
	if _local_avatar_frames.size() > 1:
		var step: int = int(_avatar_anim_ms / maxf(float(_local_avatar_delay_ms), 40.0)) % _local_avatar_frames.size()
		if step != _avatar_last_step:
			_avatar_last_step = step
			var tex: Texture2D = _local_avatar_frames[step] as Texture2D
			avatar_preview.texture = tex
			profile_avatar.texture = tex
			if _dock_avatar_rect != null and _dock_avatar_rect.visible:
				_dock_avatar_rect.texture = tex
	for entry: Dictionary in _animated_pfp_nodes:
		var node: TextureRect = entry.get("node") as TextureRect
		var frs: Array = entry.get("frames", [])
		if is_instance_valid(node) and frs.size() > 1:
			var st: int = int(_avatar_anim_ms / maxf(float(entry.get("delay_ms", 100)), 40.0)) % frs.size()
			if st != int(entry.get("step", -1)):
				entry["step"] = st
				node.texture = frs[st] as Texture2D
	if victory_overlay.visible and _victory_avatar_frames.size() > 1:
		var vst: int = int(_avatar_anim_ms / maxf(float(_victory_avatar_delay_ms), 40.0)) % _victory_avatar_frames.size()
		victory_icon.texture = _victory_avatar_frames[vst] as Texture2D
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
	_refresh_offscreen_threats()


func get_spawn_config() -> Dictionary:
	var n_name: String = nation_name_edit.text.strip_edges()
	if n_name.is_empty():
		n_name = "Terran Vanguard"
	var ai_id: int = ai_count_option.get_selected_id()
	if ai_id < 0:
		ai_id = 6
	var spd := 1.0
	if _sp_speed_opt != null:
		var spds := [1.0, 1.5, 2.0]
		spd = spds[clampi(_sp_speed_opt.selected, 0, spds.size() - 1)]
	var diff := "normal"
	if _sp_diff_opt != null:
		var diffs := ["normal", "hard", "brutal"]
		diff = diffs[clampi(_sp_diff_opt.selected, 0, diffs.size() - 1)]
	var preset := "standard"
	if _sp_preset_opt != null:
		var presets := ["standard", "fast", "sandbox"]
		preset = presets[clampi(_sp_preset_opt.selected, 0, presets.size() - 1)]
	return {
		"name": n_name,
		"ai_count": ai_id,
		"options": {
			"game_speed": spd,
			"no_nukes": _sp_nonukes_check != null and _sp_nonukes_check.button_pressed,
			"ai_difficulty": diff,
			"start_preset": preset,
		},
	}


func set_commit_ratio(ratio: float) -> void:
	AudioManager.play_ui_tap()
	_commit_ratio = clampf(ratio, 0.10, 0.80)
	_update_commit_buttons()
	if _world_state != null:
		var p: NationData = _world_state.get_player_nation()
		if p != null:
			_update_attack_preview(p)
	troop_bar.queue_redraw()


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
	if _chat_panel != null:
		_chat_panel.visible = (not in_menu) and _chat_active
	menu_visibility_changed.emit(in_menu)


func open_menu() -> void:
	AudioManager.play_panel_open()
	audio_popover.visible = false
	var in_match: bool = _world_state != null and _world_state.match_phase != WorldState.PHASE_SPAWN_SELECT
	play_btn.text = "Resume Match" if in_match else "Singleplayer"
	new_match_btn.visible = in_match
	_show_menu_page("home")
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
			var t_id: int = int(pd.get("team_id", 0))
			var team_tag: String = " [T%d]" % t_id if t_id > 0 else ""
			names.append(str(pd.get("name", "Player")) + team_tag + host_tag + tag)
	mp_players_label.text = "Players (%d): %s" % [players.size(), ", ".join(names)] if not names.is_empty() else "Players: --"
	mp_start_btn.disabled = (not is_host) or (phase != "LOBBY")
	if _mp_public_check != null:
		_mp_public_check.disabled = (not is_host) or (phase != "LOBBY")
	if _mp_team_option != null:
		_mp_team_option.disabled = (phase != "LOBBY") or (_mp_public_check != null and not _mp_team_option.visible)
	for ctrl: Control in [_mp_speed_opt, _mp_nonukes_check, _mp_diff_opt, _mp_preset_opt]:
		if ctrl != null:
			if ctrl is OptionButton:
				(ctrl as OptionButton).disabled = (not is_host) or (phase != "LOBBY")
			elif ctrl is CheckBox:
				(ctrl as CheckBox).disabled = (not is_host) or (phase != "LOBBY")
	if not _pending_invite_friend.is_empty() and not _current_room_code.is_empty():
		var inv_target: String = _pending_invite_friend
		_pending_invite_friend = ""
		_on_invite_friend_pressed(inv_target)


func open_mp_lobby_with_code(code: String) -> void:
	_show_menu_page("mp_lobby")
	menu_overlay.visible = true
	mp_room_edit.text = code.strip_edges().to_upper()
	_sync_hud_chrome_visibility()


func update_mp_room_options(is_public: bool, team_mode: bool) -> void:
	_mp_syncing_opts = true
	if _mp_public_check != null:
		_mp_public_check.button_pressed = is_public
	if _mp_team_mode_check != null:
		_mp_team_mode_check.button_pressed = team_mode
	if _mp_team_option != null:
		_mp_team_option.visible = team_mode
		if not team_mode:
			_mp_team_option.select(0)
	_mp_syncing_opts = false


func update_mp_room_modifiers(opts: Dictionary) -> void:
	_mp_syncing_opts = true
	if _mp_speed_opt != null:
		var spd: float = float(opts.get("game_speed", 1.0))
		_mp_speed_opt.select(2 if spd >= 1.9 else (1 if spd >= 1.4 else 0))
	if _mp_nonukes_check != null:
		_mp_nonukes_check.button_pressed = bool(opts.get("no_nukes", false))
	if _mp_diff_opt != null:
		var diff: String = str(opts.get("ai_difficulty", "normal"))
		_mp_diff_opt.select(2 if diff == "brutal" else (1 if diff == "hard" else 0))
	if _mp_preset_opt != null:
		var preset: String = str(opts.get("start_preset", "standard"))
		_mp_preset_opt.select(2 if preset == "sandbox" else (1 if preset == "fast" else 0))
	_mp_syncing_opts = false


func update_public_rooms(rooms: Array) -> void:
	if _mp_rooms_list == null:
		return
	for ch in _mp_rooms_list.get_children():
		ch.queue_free()
	var shown_rooms: Array = []
	for rv: Variant in rooms:
		if rv is Dictionary and (bool((rv as Dictionary).get("joinable", false)) or bool((rv as Dictionary).get("spectatable", false))):
			shown_rooms.append(rv)
	if shown_rooms.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No open or live public rooms — click Quick Play or Create Room."
		empty_lbl.modulate = Color(0.62, 0.70, 0.80, 0.85)
		empty_lbl.add_theme_font_size_override("font_size", 11)
		_mp_rooms_list.add_child(empty_lbl)
		return
	for r_item: Variant in shown_rooms:
		var rm := r_item as Dictionary
		var r_code: String = str(rm.get("code", ""))
		var h_name: String = str(rm.get("host_name", "Host"))
		var p_cnt: int = int(rm.get("players", 0))
		var m_cnt: int = int(rm.get("max_players", 16))
		var can_join: bool = bool(rm.get("joinable", false))
		var tm_tag := " · Teams" if bool(rm.get("team_mode", false)) else ""
		var live_tag := "" if can_join else " · LIVE"
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var lbl := Label.new()
		lbl.text = "%s · %s (%d/%d%s%s)" % [r_code, h_name, p_cnt, m_cnt, tm_tag, live_tag]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.clip_text = true
		lbl.add_theme_font_size_override("font_size", 11)
		row.add_child(lbl)
		var j_btn := Button.new()
		j_btn.text = "Join" if can_join else "Spectate"
		ThemeFactory.apply_button_variant(j_btn, "primary" if can_join else "secondary")
		var code_cap := r_code
		var join_cap := can_join
		j_btn.pressed.connect(func() -> void:
			AudioManager.play_ui_tap()
			mp_room_edit.text = code_cap
			var cfg: Dictionary = get_spawn_config()
			save_player_name(str(cfg.get("name", "")))
			if join_cap:
				mp_connect_requested.emit(get_mp_server_url(), code_cap, str(cfg.get("name", "Commander")))
			else:
				mp_spectate_requested.emit(code_cap)
		)
		row.add_child(j_btn)
		_mp_rooms_list.add_child(row)


func on_mp_spawn_phase(seconds_left: float) -> void:
	_show_menu_page("home")
	menu_overlay.visible = false
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
	var env_u: String = OS.get_environment("WWP_SERVER_URL").strip_edges()
	if not env_u.is_empty():
		return env_u
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
	if _replay_controls_row != null:
		_replay_controls_row.visible = false
	var by_str: String = (" by %s" % conqueror_name) if not conqueror_name.is_empty() else ""
	spec_label.text = "Your Nation Was Conquered%s — Spectating Live Match" % by_str
	spec_continue_btn.visible = true
	spec_new_match_btn.text = "New Match"
	spectator_banner.visible = true
	_sync_hud_chrome_visibility()
	refresh_player_bar()


func enter_live_spectate_mode(room_code: String) -> void:
	_is_spectating = true
	menu_overlay.visible = false
	clear_build_mode()
	clear_missile_mode()
	if _replay_controls_row != null:
		_replay_controls_row.visible = false
	spec_label.text = "Spectating Live Room %s" % room_code
	spec_continue_btn.visible = false
	spec_new_match_btn.text = "Leave"
	spectator_banner.visible = true
	set_chat_active(true)
	_sync_hud_chrome_visibility()
	refresh_all()


func enter_replay_mode(title_txt: String) -> void:
	_is_spectating = true
	menu_overlay.visible = false
	clear_build_mode()
	clear_missile_mode()
	spec_label.text = "REPLAY · %s" % title_txt
	spec_continue_btn.visible = false
	spec_new_match_btn.text = "Exit Replay"
	spectator_banner.visible = true
	if _replay_controls_row != null:
		_replay_controls_row.visible = true
	set_chat_active(false)
	_sync_hud_chrome_visibility()
	refresh_all()


func set_chat_active(active: bool) -> void:
	_chat_active = active
	if not active and _chat_log != null:
		_chat_log.text = ""
	if _chat_panel != null:
		_chat_panel.visible = active and (not menu_overlay.visible)


func append_chat_message(from_name: String, channel: String, text: String) -> void:
	if _chat_log == null:
		return
	var prefix := "[TEAM] " if channel == "team" else ""
	var col_hex := "#5ce1e6" if channel == "team" else "#e8edf5"
	_chat_log.append_text("[color=%s]%s[b]%s:[/b] %s[/color]\n" % [col_hex, prefix, from_name, text])


func set_password_change_result(ok: bool, msg: String) -> void:
	if _sec_status_lbl != null:
		_sec_status_lbl.text = msg
		_sec_status_lbl.modulate = Color(0.45, 0.96, 0.62) if ok else Color(1.0, 0.45, 0.45)
	if ok and _sec_cur_edit != null:
		_sec_cur_edit.text = ""
		_sec_new_edit.text = ""
		_sec_conf_edit.text = ""


func update_rankings_data(leaderboard: Array, my_matches: Array) -> void:
	_cached_leaderboard = leaderboard.duplicate(true)
	_cached_my_matches = my_matches.duplicate(true)
	if _rankings_card != null and _rankings_card.visible:
		_render_rankings_rows()


func _tier_color(tier: String) -> Color:
	match tier:
		"Sovereign":
			return Color(1.0, 0.38, 0.44)
		"Grandmaster":
			return Color(0.96, 0.46, 0.92)
		"Diamond":
			return Color(0.42, 0.88, 1.0)
		"Platinum":
			return Color(0.32, 0.94, 0.78)
		"Gold":
			return Color(0.98, 0.84, 0.34)
		"Silver":
			return Color(0.78, 0.85, 0.94)
		"Bronze":
			return Color(0.84, 0.56, 0.34)
		_:
			return Color(0.58, 0.62, 0.68)


func _render_rankings_rows() -> void:
	if _rankings_rows == null:
		return
	for ch in _rankings_rows.get_children():
		ch.queue_free()
	if _rankings_mode == "history":
		if _cached_my_matches.is_empty():
			var empty_h := Label.new()
			empty_h.text = "No recorded multiplayer matches yet (sign in to track history & replays)."
			empty_h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			empty_h.modulate = Color(0.68, 0.76, 0.86, 0.88)
			_rankings_rows.add_child(empty_h)
			return
		for mv: Variant in _cached_my_matches:
			if not (mv is Dictionary):
				continue
			var m := mv as Dictionary
			var won: bool = bool(m.get("won", false))
			var pct: float = float(m.get("territory_pct", 0.0))
			var rcode: String = str(m.get("room_code", "ROOM"))
			var mid: String = str(m.get("match_id", ""))
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			var lbl := Label.new()
			lbl.text = "%s · Room %s · %.1f%%" % ["WIN" if won else "LOSS", rcode, pct]
			lbl.modulate = Color(0.42, 0.96, 0.62) if won else Color(0.95, 0.54, 0.50)
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.clip_text = true
			row.add_child(lbl)
			if not mid.is_empty():
				var r_btn := Button.new()
				r_btn.text = "Watch Replay"
				ThemeFactory.apply_button_variant(r_btn, "secondary")
				var mid_cap := mid
				r_btn.pressed.connect(func() -> void:
					AudioManager.play_ui_tap()
					watch_replay_requested.emit(mid_cap)
				)
				row.add_child(r_btn)
			_rankings_rows.add_child(row)
		return

	if _cached_leaderboard.is_empty():
		var empty_l := Label.new()
		empty_l.text = "No ranked commanders found yet."
		empty_l.modulate = Color(0.68, 0.76, 0.86, 0.88)
		_rankings_rows.add_child(empty_l)
		return
	var rank_i := 0
	for uv: Variant in _cached_leaderboard:
		if not (uv is Dictionary):
			continue
		rank_i += 1
		var u := uv as Dictionary
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var pos_l := Label.new()
		pos_l.text = "#%d" % rank_i
		pos_l.custom_minimum_size = Vector2(30, 0)
		pos_l.modulate = Color(0.96, 0.82, 0.34) if rank_i <= 3 else Color(0.76, 0.82, 0.90)
		row.add_child(pos_l)
		var tier_s: String = str(u.get("rank_tier", "Silver"))
		var r_title: String = str(u.get("rank_title", "Silver III"))
		if r_title.is_empty():
			r_title = "Silver III"
		var tier_l := Label.new()
		tier_l.text = "[%s]" % r_title
		tier_l.custom_minimum_size = Vector2(98, 0)
		tier_l.modulate = _tier_color(tier_s)
		row.add_child(tier_l)
		var nm_l := Label.new()
		nm_l.text = str(u.get("username", "Commander"))
		nm_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm_l.clip_text = true
		row.add_child(nm_l)
		var gp: int = int(u.get("games_played", 0))
		var wins_i: int = int(u.get("wins", 0))
		var wr: float = (float(wins_i) * 100.0 / float(gp)) if gp > 0 else 0.0
		var best_pct: float = float(u.get("best_territory_pct", 0.0))
		var elo_l := Label.new()
		elo_l.text = "%d ELO · %dW/%dG (%.0f%%) · %.1f%%" % [int(u.get("elo", 1000)), wins_i, gp, wr, best_pct]
		elo_l.modulate = Color(0.66, 0.92, 0.78)
		row.add_child(elo_l)
		_rankings_rows.add_child(row)


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
	_last_dock_cost_key = -1
	_last_dock_afford_mask = -1
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
	var slots: Array = [
		[town_btn, _build_mode == StructureData.TYPE_TOWN, Color(0.46, 0.94, 0.62, 0.95)],
		[factory_btn, _build_mode == StructureData.TYPE_FACTORY, Color(0.98, 0.80, 0.36, 0.95)],
		[port_btn, _build_mode == StructureData.TYPE_PORT, Color(0.44, 0.86, 1.0, 0.95)],
		[defense_btn, _build_mode == StructureData.TYPE_DEFENSE_POST, Color(0.52, 0.76, 1.0, 0.95)],
		[silo_btn, _build_mode == StructureData.TYPE_MISSILE_SILO, Color(1.0, 0.56, 0.46, 0.95)],
		[sam_btn, _build_mode == StructureData.TYPE_SAM_LAUNCHER, Color(0.42, 0.96, 0.92, 0.95)],
		[warship_btn, _build_mode == "warship", Color(0.48, 0.86, 1.0, 0.95)],
		[atom_dock_btn, _missile_mode == MissileUnit.KIND_ATOM, Color(1.0, 0.82, 0.36, 0.95)],
		[hbomb_dock_btn, _missile_mode == MissileUnit.KIND_HYDROGEN, Color(1.0, 0.52, 0.32, 0.95)],
		[mirv_dock_btn, _missile_mode == MissileUnit.KIND_MIRV, Color(1.0, 0.38, 0.66, 0.95)],
	]
	for entry: Array in slots:
		var btn: Button = entry[0] as Button
		ThemeFactory.set_photo_slot_active(btn, bool(entry[1]), entry[2] as Color)
		btn.modulate = Color.WHITE
	expand_btn.modulate = Color(0.82, 0.96, 1.0) if free_hand else Color.WHITE
	_last_dock_afford_mask = -1
	if _world_state != null and _world_state.match_phase == WorldState.PHASE_PLAYING:
		var p: NationData = _world_state.get_player_nation()
		if p != null:
			_refresh_dock_slot_cost_colors(p)
	troop_bar.queue_redraw()


func _update_commit_buttons() -> void:
	var commits: Array = [
		[commit_10_btn, 0.10],
		[commit_25_btn, 0.25],
		[commit_35_btn, 0.35],
		[commit_50_btn, 0.50],
		[commit_75_btn, 0.75],
	]
	for entry: Array in commits:
		var btn: Button = entry[0] as Button
		ThemeFactory.set_commit_pill_active(btn, is_equal_approx(_commit_ratio, float(entry[1])))
		btn.modulate = Color.WHITE
	attack_pct_label.text = "%d%%" % int(round(_commit_ratio * 100.0))


func _update_hotkeys_button() -> void:
	hotkeys_btn.text = "Keys" if _hotkeys_enabled else "Keys Off"
	hotkeys_btn.tooltip_text = "Keyboard Hotkeys: ON" if _hotkeys_enabled else "Keyboard Hotkeys: OFF"
	hotkeys_btn.modulate = Color(0.78, 0.96, 0.84) if _hotkeys_enabled else Color(0.72, 0.76, 0.82)


func _on_play_pressed() -> void:
	AudioManager.play_ui_tap()
	save_player_name(menu_name_edit.text)
	_show_menu_page("home")
	menu_overlay.visible = false
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
			audio_popover.anchor_left = 0.0
			audio_popover.anchor_right = 0.0
			audio_popover.anchor_top = 0.0
			audio_popover.anchor_bottom = 0.0
			audio_popover.offset_left = 10.0
			audio_popover.offset_top = 44.0
			audio_popover.offset_right = 270.0
			audio_popover.offset_bottom = 324.0
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
	gold_icon.texture = _make_pixel_icon(_tex_coin, Color(0.92, 0.82, 0.44), 12)
	troops_icon.texture = _make_pixel_icon(_tex_troops, Color(0.78, 0.82, 0.88), 12)
	expand_btn.icon = _make_pixel_icon(_tex_attack, Color.WHITE, 13)
	town_btn.icon = _make_pixel_icon(_tex_hud_town, Color.WHITE, 20)
	factory_btn.icon = _make_pixel_icon(_tex_hud_factory, Color.WHITE, 20)
	port_btn.icon = _make_pixel_icon(_tex_hud_port, Color.WHITE, 20)
	defense_btn.icon = _make_pixel_icon(_tex_hud_defense, Color.WHITE, 20)
	silo_btn.icon = _make_pixel_icon(_tex_hud_silo, Color.WHITE, 20)
	sam_btn.icon = _make_pixel_icon(_tex_hud_sam, Color.WHITE, 20)
	warship_btn.icon = _make_pixel_icon(_tex_hud_warship, Color.WHITE, 20)
	atom_dock_btn.icon = _make_pixel_icon(_tex_hud_atom, Color.WHITE, 20)
	hbomb_dock_btn.icon = _make_pixel_icon(_tex_hud_hbomb, Color.WHITE, 20)
	mirv_dock_btn.icon = _make_pixel_icon(_tex_hud_mirv, Color.WHITE, 20)
	var ship_ic: ImageTexture = _make_pixel_icon(_tex_hud_warship, Color.WHITE, 18)
	var upg_ic: ImageTexture = _build_tinted_icon(_tex_upgrade, null, Color.WHITE, 16, 16)
	var boat_ic: ImageTexture = _build_tinted_icon(_tex_boat, null, Color.WHITE, 16, 16)
	st_upgrade_btn.icon = upg_ic
	st_warship_btn.icon = ship_ic
	st_atom_btn.icon = _make_pixel_icon(_tex_hud_atom, Color.WHITE, 16)
	st_hbomb_btn.icon = _make_pixel_icon(_tex_hud_hbomb, Color.WHITE, 16)
	st_mirv_btn.icon = _make_pixel_icon(_tex_hud_mirv, Color.WHITE, 16)
	var dip_ic: ImageTexture = _build_tinted_icon(_tex_diplomacy, null, Color.WHITE, 16, 16)
	ally_btn.icon = dip_ic
	embargo_btn.icon = _build_tinted_icon(_tex_port, _tex_port_mask, Color(1.0, 0.55, 0.45), 16, 16)
	donate_gold_btn.icon = _build_tinted_icon(_tex_coin, null, Color.WHITE, 16, 16)
	donate_troops_btn.icon = _build_tinted_icon(_tex_troops, null, Color.WHITE, 16, 16)
	# Simplified 4-way right-click bar: Top=Attack(crossed swords), Left=Upgrade(arrow up), Right=Boat(boat), Bottom=Ally(handshake)
	radial_attack_btn.icon = _build_tinted_icon(_tex_attack, null, Color.WHITE, 16, 16)
	radial_build_btn.icon = upg_ic
	radial_warship_btn.icon = boat_ic
	radial_missile_btn.icon = st_atom_btn.icon
	radial_dip_btn.icon = dip_ic
	radial_info_btn.icon = dip_ic


func _on_troop_bar_draw() -> void:
	var sz: Vector2 = troop_bar.size
	if sz.x <= 4.0 or sz.y <= 4.0:
		return
	var fill_ratio: float = 0.0
	if _world_state != null:
		var p: NationData = _world_state.get_player_nation()
		if p != null and p.max_troops > 0.0:
			fill_ratio = clampf(p.troops / p.max_troops, 0.0, 1.0)
	var commit_r: float = clampf(_commit_ratio, 0.0, 1.0)
	var bar_y: float = floorf((sz.y - 7.0) * 0.5)
	var bar_h: float = 7.0
	var seg_cnt := 5
	var gap := 2.0
	var seg_w: float = floorf((sz.x - gap * float(seg_cnt - 1)) / float(seg_cnt))
	var fill_x: float = fill_ratio * sz.x
	var commit_x: float = roundf(commit_r * sz.x)
	var col_green := Color(0.24, 0.85, 0.47, 1.0)
	var col_green_hi := Color(0.45, 0.94, 0.63, 1.0)
	var col_dark := Color(0.13, 0.15, 0.19, 1.0)
	var col_gold_bg := Color(0.28, 0.24, 0.11, 1.0)
	var col_border := Color(0.06, 0.07, 0.09, 1.0)
	for i in range(seg_cnt):
		var sx: float = float(i) * (seg_w + gap)
		var sw: float = seg_w if i < seg_cnt - 1 else maxf(seg_w, sz.x - sx)
		var r := Rect2(sx, bar_y, sw, bar_h)
		troop_bar.draw_rect(r, col_dark)
		if sx + sw > commit_x:
			var gx0: float = maxf(sx, commit_x)
			troop_bar.draw_rect(Rect2(gx0, bar_y, (sx + sw) - gx0, bar_h), col_gold_bg)
		if fill_x > sx:
			var fw: float = minf(sw, fill_x - sx)
			troop_bar.draw_rect(Rect2(sx, bar_y, fw, bar_h), col_green)
			troop_bar.draw_rect(Rect2(sx, bar_y, fw, 1.0), col_green_hi)
		troop_bar.draw_rect(r, col_border, false, 1.0)
	var dx: float = clampf(commit_x, 3.0, sz.x - 3.0)
	var cy: float = bar_y + bar_h * 0.5
	var gold_marker := Color(0.96, 0.82, 0.28, 1.0)
	troop_bar.draw_rect(Rect2(dx - 0.5, bar_y - 1.0, 1.0, bar_h + 4.0), gold_marker)
	troop_bar.draw_polygon(
		PackedVector2Array([
			Vector2(dx, cy - 4.0),
			Vector2(dx + 4.0, cy),
			Vector2(dx, cy + 4.0),
			Vector2(dx - 4.0, cy),
		]),
		PackedColorArray([gold_marker, gold_marker, gold_marker, gold_marker])
	)


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


func _update_attack_preview(p: NationData) -> void:
	var sends: float = floorf(p.troops * _commit_ratio)
	var best_def: float = 1.0
	for sid: int in p.structure_ids:
		var st_def: StructureData = _world_state.structures.get(sid)
		if st_def != null and st_def.type == StructureData.TYPE_DEFENSE_POST and not st_def.is_constructing and st_def.level > 0:
			best_def = maxf(best_def, st_def.get_defense_multiplier())
	attack_preview_label.text = "Sends %s troops · Defense %.1fx" % [StructureData.format_compact(sends), best_def]


func _get_dock_slot_costs(p: NationData) -> Array[float]:
	return [
		_world_state.get_structure_build_cost(p.id, StructureData.TYPE_TOWN),
		_world_state.get_structure_build_cost(p.id, StructureData.TYPE_FACTORY),
		_world_state.get_structure_build_cost(p.id, StructureData.TYPE_PORT),
		_world_state.get_structure_build_cost(p.id, StructureData.TYPE_DEFENSE_POST),
		_world_state.get_structure_build_cost(p.id, StructureData.TYPE_MISSILE_SILO),
		_world_state.get_structure_build_cost(p.id, StructureData.TYPE_SAM_LAUNCHER),
		_world_state.get_warship_build_cost(p.id),
		MissileUnit.get_cost(MissileUnit.KIND_ATOM),
		MissileUnit.get_cost(MissileUnit.KIND_HYDROGEN),
		MissileUnit.get_cost(MissileUnit.KIND_MIRV),
	]


func _refresh_dock_slot_cost_colors(p: NationData) -> void:
	var costs: Array[float] = _get_dock_slot_costs(p)
	var afford_mask := 0
	for i in range(costs.size()):
		if p.gold >= costs[i]:
			afford_mask |= (1 << i)
	if afford_mask == _last_dock_afford_mask:
		return
	_last_dock_afford_mask = afford_mask
	var btns: Array[Button] = [
		town_btn, factory_btn, port_btn, defense_btn, silo_btn,
		sam_btn, warship_btn, atom_dock_btn, hbomb_dock_btn, mirv_dock_btn,
	]
	var col_afford := Color(0.95, 0.87, 0.48, 1.0)
	var col_unafford := Color(0.95, 0.37, 0.37, 1.0)
	for i in range(btns.size()):
		var col: Color = col_afford if ((afford_mask & (1 << i)) != 0) else col_unafford
		btns[i].add_theme_color_override("font_color", col)
		btns[i].add_theme_color_override("font_hover_color", col.lightened(0.12))
		btns[i].add_theme_color_override("font_pressed_color", col)


func refresh_player_bar() -> void:
	if _world_state == null:
		return
	if _world_state.match_phase == WorldState.PHASE_SPAWN_SELECT:
		gold_label.text = "--"
		gold_rate_label.text = ""
		troops_label.text = "--"
		troops_max_label.text = ""
		troops_rate_label.text = ""
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
		gold_label.text = "SPEC"
		gold_rate_label.text = ""
		troops_label.text = "0"
		troops_max_label.text = ""
		troops_rate_label.text = ""
		world_pct_label.text = "Spectating · %d Nations" % alive_cnt
		return
	nation_color_swatch.color = p.color
	nation_name_label.text = p.name
	var betray_tag := " [BETRAYAL]" if p.is_betrayer(_world_state.current_tick) else ""
	world_pct_label.text = "%.2f%% of the world%s" % [p.territory_percent, betray_tag]
	troops_label.text = StructureData.format_compact(floor(p.troops))
	troops_max_label.text = "/ %s" % StructureData.format_compact(round(p.max_troops))
	troops_rate_label.text = ("+%.1f/s" % p.effective_troops_per_sec) if p.effective_troops_per_sec < 10.0 else ("+%s/s" % StructureData.format_compact(p.effective_troops_per_sec))
	gold_label.text = StructureData.format_compact(p.gold)
	gold_rate_label.text = ("+%.1f/s" % p.gold_per_sec) if p.gold_per_sec < 10.0 else ("+%s/s" % StructureData.format_compact(p.gold_per_sec))
	_update_attack_preview(p)
	troop_bar.queue_redraw()
	var dock_key: int = p.id * 100003 + p.structure_ids.size() * 131 + _world_state.structures.size() + _world_state.count_warships(p.id) * 17
	if dock_key != _last_dock_cost_key:
		_last_dock_cost_key = dock_key
		_last_dock_afford_mask = -1
		expand_btn.text = "Explore"
		var slot_entries: Array = [
			[town_btn, _world_state.get_structure_build_cost(p.id, StructureData.TYPE_TOWN), _world_state.count_structures_of_type(p.id, StructureData.TYPE_TOWN), "[1] Town (%d owned)"],
			[factory_btn, _world_state.get_structure_build_cost(p.id, StructureData.TYPE_FACTORY), _world_state.count_structures_of_type(p.id, StructureData.TYPE_FACTORY), "[2] Factory (%d owned)"],
			[port_btn, _world_state.get_structure_build_cost(p.id, StructureData.TYPE_PORT), _world_state.count_structures_of_type(p.id, StructureData.TYPE_PORT), "[3] Port (%d owned)"],
			[defense_btn, _world_state.get_structure_build_cost(p.id, StructureData.TYPE_DEFENSE_POST), _world_state.count_structures_of_type(p.id, StructureData.TYPE_DEFENSE_POST), "[4] Defense Post (%d owned)"],
			[silo_btn, _world_state.get_structure_build_cost(p.id, StructureData.TYPE_MISSILE_SILO), _world_state.count_structures_of_type(p.id, StructureData.TYPE_MISSILE_SILO), "[5] Missile Silo (%d owned)"],
			[sam_btn, _world_state.get_structure_build_cost(p.id, StructureData.TYPE_SAM_LAUNCHER), _world_state.count_structures_of_type(p.id, StructureData.TYPE_SAM_LAUNCHER), "[6] SAM Launcher (%d owned)"],
			[warship_btn, _world_state.get_warship_build_cost(p.id), _world_state.count_warships(p.id), "[7] Warship (%d active)"],
			[atom_dock_btn, MissileUnit.get_cost(MissileUnit.KIND_ATOM), -1, "[8] Atom Bomb"],
			[hbomb_dock_btn, MissileUnit.get_cost(MissileUnit.KIND_HYDROGEN), -1, "[9] Hydrogen Bomb"],
			[mirv_dock_btn, MissileUnit.get_cost(MissileUnit.KIND_MIRV), -1, "[F] MIRV Warhead"],
		]
		for entry: Array in slot_entries:
			var btn: Button = entry[0] as Button
			var cost: float = float(entry[1])
			var cnt: int = int(entry[2])
			btn.text = StructureData.format_compact(cost)
			btn.tooltip_text = (str(entry[3]) % cnt) if cnt >= 0 else str(entry[3])
			var cnt_lbl := btn.get_node_or_null("TopMeta/CountLbl") as Label
			if cnt_lbl != null and cnt >= 0:
				cnt_lbl.text = "×%d" % cnt
	_refresh_dock_slot_cost_colors(p)


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
	var local_id: int = _world_state.player_nation_id
	for n: NationData in ranked:
		if not n.alive and n.owned_cell_count == 0:
			continue
		if shown >= _lb_pool.size():
			break
		var slot: Dictionary = _lb_pool[shown]
		slot["nid"] = n.id
		(slot["row"] as HBoxContainer).visible = true
		(slot["dot"] as ColorRect).color = n.color
		var is_local: bool = (n.id == local_id)
		var team_tag: String = (" [T%d]" % n.team_id) if n.team_id > 0 else ""
		var ally_tag: String = " [ALLY]" if ((not is_local) and _world_state.are_allied(local_id, n.id)) else ""
		(slot["name"] as Label).text = n.name + team_tag + (" (You)" if is_local else ally_tag)
		(slot["pct"] as Label).text = "%.2f%%" % n.territory_percent
		(slot["dip_btn"] as Button).visible = ((not is_local) and n.alive)
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


func show_toast(msg: String, is_alert: bool = true, focus_world_pos: Vector2 = Vector2(-1.0, -1.0)) -> void:
	toast_label.text = msg
	toast_label.modulate = Color(1.0, 0.74, 0.70) if is_alert else Color(0.70, 0.96, 0.80)
	_last_toast_world_pos = focus_world_pos
	toast_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if focus_world_pos.x >= 0.0 else Control.CURSOR_ARROW
	toast_panel.visible = true
	_toast_timer = 3.6


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
	var p_n: NationData = _world_state.get_nation(p_id)
	var same_team: bool = (p_n != null and p_n.team_id > 0 and p_n.team_id == other.team_id)
	var allied: bool = _world_state.are_allied(p_id, target_nid)
	var embargoed: bool = _world_state.is_embargoed(p_id, target_nid)
	var rel_str := ("Allied (Team %d)" % other.team_id) if same_team else ("Allied (FFA)" if allied else ("Embargoed" if embargoed else "Neutral"))
	if other.is_betrayer(_world_state.current_tick):
		rel_str += " · BETRAYER"
	dip_status_lbl.text = "Relation: %s\nLand: %.2f%% · Troops: %d · Pesos: %s" % [
		rel_str, other.territory_percent, int(round(other.troops)), StructureData.format_pesos(other.gold)
	]
	ally_btn.text = ("Team %d Pact" % other.team_id) if same_team else ("Break Alliance" if allied else "Propose Alliance")
	ally_btn.disabled = same_team
	ThemeFactory.apply_button_variant(ally_btn, "secondary" if same_team else ("danger" if allied else "primary"))
	embargo_btn.text = "Lift Embargo" if embargoed else "Trade Embargo"
	var g_amt: float = _gold_aid_amounts[clampi(_gold_aid_idx, 0, _gold_aid_amounts.size() - 1)]
	var t_rat: float = _troop_aid_ratios[clampi(_troop_aid_idx, 0, _troop_aid_ratios.size() - 1)]
	donate_gold_btn.text = "Send %s ₱" % StructureData.format_pesos(g_amt)
	donate_troops_btn.text = "Send %d%% Troops" % int(round(t_rat * 100.0))
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
	var is_player_win: bool = (winner_id == _world_state.player_nation_id) or (
		_world_state.winner_team_id > 0 and _world_state.get_player_nation() != null and _world_state.get_player_nation().team_id == _world_state.winner_team_id
	)
	_victory_avatar_frames.clear()
	if is_player_win and not _local_avatar_frames.is_empty():
		_victory_avatar_frames = _local_avatar_frames.duplicate()
		_victory_avatar_delay_ms = _local_avatar_delay_ms
		victory_icon.texture = _victory_avatar_frames[0] as Texture2D
	elif _avatar_cache_lookup.is_valid():
		var cached: Variant = _avatar_cache_lookup.call(w_name)
		if cached is Dictionary and not (cached as Dictionary).get("frames", []).is_empty():
			_victory_avatar_frames = ((cached as Dictionary)["frames"] as Array).duplicate()
			_victory_avatar_delay_ms = clampi(int((cached as Dictionary).get("delay_ms", 100)), 40, 1000)
			victory_icon.texture = _victory_avatar_frames[0] as Texture2D
	if _victory_avatar_frames.is_empty():
		victory_icon.texture = _build_tinted_icon(_tex_banner, _tex_banner_mask, w_col, 24, 24)
	if _world_state.winner_team_id > 0:
		victory_title.text = "TEAM VICTORY" if is_player_win else "TEAM MATCH CONCLUDED"
		victory_sub.text = "Team %d unified %.1f%% of Earth!" % [_world_state.winner_team_id, pct]
	else:
		victory_title.text = "WORLD VICTORY" if is_player_win else "MATCH CONCLUDED"
		victory_sub.text = "%s unified %.1f%% of Earth!" % [w_name, pct]
	victory_title.modulate = Color(1.0, 0.88, 0.42) if is_player_win else Color(0.84, 0.90, 0.98)
	var p_n: NationData = _world_state.get_player_nation()
	if p_n != null:
		victory_stats.text = "Your Peak: %.1f%%  ·  Earned: %s  ·  Nukes: %d Fired / %d Intercepted" % [
			maxf(p_n.peak_territory_percent, p_n.territory_percent),
			StructureData.format_pesos(p_n.total_gold_earned),
			p_n.nukes_launched,
			p_n.nukes_intercepted,
		]
	elif winner != null:
		victory_stats.text = "Treasury: %s Pesos  ·  Standing Army: %d  ·  Structures: %d" % [
			StructureData.format_pesos(winner.gold),
			int(round(winner.troops)),
			winner.structure_ids.size(),
		]
	else:
		victory_stats.text = "World Control: %.1f%%" % pct
	_victory_history = _world_state.match_history.duplicate(true)
	if _victory_chart != null:
		_victory_chart.visible = _victory_history.size() >= 2
		_victory_chart.queue_redraw()
	victory_overlay.visible = true


func _setup_extra_hud_panels() -> void:
	# 1. Click-to-jump on ToastPanel + Fullscreen Off-Screen Threat Arrow Overlay
	toast_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	toast_panel.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			if _last_toast_world_pos.x >= 0.0:
				AudioManager.play_ui_tap()
				camera_focus_requested.emit(_last_toast_world_pos, 2.2)
	)
	_threat_overlay = Control.new()
	_threat_overlay.name = "ThreatEdgeOverlay"
	_threat_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_threat_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_threat_overlay.draw.connect(_on_threat_overlay_draw)
	_threat_overlay.gui_input.connect(_on_threat_overlay_input)
	root_control.add_child(_threat_overlay)
	root_control.move_child(_threat_overlay, 0)

	# 2. Extend AudioPopover with persistent Window Mode & UI Scale controls
	var avbox := audio_popover.get_node_or_null("VBox") as VBoxContainer
	if avbox != null:
		var sep := HSeparator.new()
		avbox.add_child(sep)
		var disp_row := HBoxContainer.new()
		var disp_lbl := Label.new()
		disp_lbl.text = "Display"
		disp_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		disp_row.add_child(disp_lbl)
		_display_mode_option = OptionButton.new()
		_display_mode_option.add_item("Windowed", 0)
		_display_mode_option.add_item("Borderless", 1)
		_display_mode_option.add_item("Fullscreen", 2)
		_display_mode_option.item_selected.connect(func(idx: int) -> void:
			AudioManager.play_ui_tap()
			_apply_display_mode(idx, true)
		)
		disp_row.add_child(_display_mode_option)
		avbox.add_child(disp_row)

		var sc_row := HBoxContainer.new()
		var sc_lbl := Label.new()
		sc_lbl.text = "UI Scale"
		sc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc_row.add_child(sc_lbl)
		_ui_scale_option = OptionButton.new()
		_ui_scale_option.add_item("90%", 0)
		_ui_scale_option.add_item("100%", 1)
		_ui_scale_option.add_item("115%", 2)
		_ui_scale_option.select(1)
		_ui_scale_option.item_selected.connect(func(idx: int) -> void:
			AudioManager.play_ui_tap()
			_apply_ui_scale(idx, true)
		)
		sc_row.add_child(_ui_scale_option)
		avbox.add_child(sc_row)

	# 3. Extend MpLobbyCard with Quick Play, Public Lobbies browser, and Team Mode controls
	var mp_vbox := mp_lobby_card.get_node_or_null("VBox") as VBoxContainer
	if mp_vbox != null:
		var qp_row := HBoxContainer.new()
		qp_row.add_theme_constant_override("separation", 6)
		var qp_btn := Button.new()
		qp_btn.text = "Quick Play"
		qp_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ThemeFactory.apply_button_variant(qp_btn, "primary")
		qp_btn.pressed.connect(func() -> void:
			AudioManager.play_ui_tap()
			mp_status_label.text = "Finding public match..."
			mp_quickplay_requested.emit()
		)
		qp_row.add_child(qp_btn)
		var ref_btn := Button.new()
		ref_btn.text = "Refresh Rooms"
		ThemeFactory.apply_button_variant(ref_btn, "secondary")
		ref_btn.pressed.connect(func() -> void:
			AudioManager.play_ui_tap()
			mp_rooms_refresh_requested.emit()
		)
		qp_row.add_child(ref_btn)
		mp_vbox.add_child(qp_row)
		mp_vbox.move_child(qp_row, mini(2, mp_vbox.get_child_count() - 1))

		var opt_row := HBoxContainer.new()
		opt_row.add_theme_constant_override("separation", 8)
		_mp_public_check = CheckBox.new()
		_mp_public_check.text = "Public Room"
		_mp_public_check.button_pressed = true
		_mp_team_mode_check = CheckBox.new()
		_mp_team_mode_check.text = "Team Mode"
		_mp_team_option = OptionButton.new()
		_mp_team_option.add_item("Free-For-All", 0)
		for ti in range(1, 5):
			_mp_team_option.add_item("Team %d" % ti, ti)
		_mp_team_option.visible = false
		var emit_opts := func() -> void:
			if _mp_syncing_opts:
				return
			_mp_team_option.visible = _mp_team_mode_check.button_pressed
			mp_room_options_changed.emit(_mp_public_check.button_pressed, _mp_team_mode_check.button_pressed)
		_mp_public_check.toggled.connect(func(_v: bool) -> void: emit_opts.call())
		_mp_team_mode_check.toggled.connect(func(_v: bool) -> void: emit_opts.call())
		_mp_team_option.item_selected.connect(func(idx: int) -> void:
			if not _mp_syncing_opts:
				mp_team_selected.emit(idx)
		)
		opt_row.add_child(_mp_public_check)
		opt_row.add_child(_mp_team_mode_check)
		opt_row.add_child(_mp_team_option)
		mp_vbox.add_child(opt_row)

		var scroller := ScrollContainer.new()
		scroller.custom_minimum_size = Vector2(0, 76)
		_mp_rooms_list = VBoxContainer.new()
		_mp_rooms_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroller.add_child(_mp_rooms_list)
		mp_vbox.add_child(scroller)

	# 4. Extend VictoryCard with Territory Timelapse Chart
	var v_vbox := victory_overlay.get_node_or_null("Center/VictoryCard/VBox") as VBoxContainer
	if v_vbox != null:
		_victory_chart = Control.new()
		_victory_chart.name = "VictoryTerritoryChart"
		_victory_chart.custom_minimum_size = Vector2(440, 120)
		_victory_chart.visible = false
		_victory_chart.draw.connect(_on_victory_chart_draw)
		v_vbox.add_child(_victory_chart)
		v_vbox.move_child(_victory_chart, maxi(0, v_vbox.get_child_count() - 2))

	# 5. Singleplayer Page Modifiers (inside Dedicated SingleplayerCard)
	var sp_vbox := sp_card.get_node_or_null("VBox") as VBoxContainer
	if sp_vbox != null:
		var sp_mod := HBoxContainer.new()
		sp_mod.add_theme_constant_override("separation", 6)
		_sp_speed_opt = OptionButton.new()
		_sp_speed_opt.add_item("1× Speed", 0)
		_sp_speed_opt.add_item("1.5× Speed", 1)
		_sp_speed_opt.add_item("2× Speed", 2)
		_sp_diff_opt = OptionButton.new()
		_sp_diff_opt.add_item("AI: Normal", 0)
		_sp_diff_opt.add_item("AI: Hard", 1)
		_sp_diff_opt.add_item("AI: Brutal", 2)
		_sp_preset_opt = OptionButton.new()
		_sp_preset_opt.add_item("Standard", 0)
		_sp_preset_opt.add_item("Fast Start", 1)
		_sp_preset_opt.add_item("Sandbox", 2)
		_sp_nonukes_check = CheckBox.new()
		_sp_nonukes_check.text = "No Nukes"
		sp_mod.add_child(_sp_speed_opt)
		sp_mod.add_child(_sp_diff_opt)
		sp_mod.add_child(_sp_preset_opt)
		sp_mod.add_child(_sp_nonukes_check)
		sp_vbox.add_child(sp_mod)
		sp_vbox.move_child(sp_mod, sp_start_btn.get_index())

	# 6. Host Modifiers row inside MpLobbyCard + Dedicated MP Header Icon
	if mp_vbox != null:
		var mp_hdr := mp_vbox.get_node_or_null("HeaderRow") as HBoxContainer
		if mp_hdr != null:
			var mp_ic := TextureRect.new()
			mp_ic.texture = _make_pixel_icon(_tex_multiplayer, Color.WHITE, 16)
			mp_ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			mp_ic.custom_minimum_size = Vector2(18, 18)
			mp_ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			mp_ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			mp_hdr.add_child(mp_ic)
			mp_hdr.move_child(mp_ic, 1)
		var mod_row := HBoxContainer.new()
		mod_row.add_theme_constant_override("separation", 6)
		_mp_speed_opt = OptionButton.new()
		_mp_speed_opt.add_item("1×", 0)
		_mp_speed_opt.add_item("1.5×", 1)
		_mp_speed_opt.add_item("2×", 2)
		_mp_diff_opt = OptionButton.new()
		_mp_diff_opt.add_item("AI Normal", 0)
		_mp_diff_opt.add_item("AI Hard", 1)
		_mp_diff_opt.add_item("AI Brutal", 2)
		_mp_preset_opt = OptionButton.new()
		_mp_preset_opt.add_item("Standard", 0)
		_mp_preset_opt.add_item("Fast Start", 1)
		_mp_preset_opt.add_item("Sandbox", 2)
		_mp_nonukes_check = CheckBox.new()
		_mp_nonukes_check.text = "No Nukes"
		var emit_mods := func() -> void:
			if _mp_syncing_opts:
				return
			var spds := [1.0, 1.5, 2.0]
			var diffs := ["normal", "hard", "brutal"]
			var presets := ["standard", "fast", "sandbox"]
			mp_room_modifiers_changed.emit({
				"game_speed": spds[clampi(_mp_speed_opt.selected, 0, 2)],
				"ai_difficulty": diffs[clampi(_mp_diff_opt.selected, 0, 2)],
				"start_preset": presets[clampi(_mp_preset_opt.selected, 0, 2)],
				"no_nukes": _mp_nonukes_check.button_pressed,
			})
		_mp_speed_opt.item_selected.connect(func(_i: int) -> void: emit_mods.call())
		_mp_diff_opt.item_selected.connect(func(_i: int) -> void: emit_mods.call())
		_mp_preset_opt.item_selected.connect(func(_i: int) -> void: emit_mods.call())
		_mp_nonukes_check.toggled.connect(func(_v: bool) -> void: emit_mods.call())
		mod_row.add_child(_mp_speed_opt)
		mod_row.add_child(_mp_diff_opt)
		mod_row.add_child(_mp_preset_opt)
		mod_row.add_child(_mp_nonukes_check)
		mp_vbox.add_child(mod_row)

	# 7. Dedicated Global Leaderboard & Match History/Replays Page + Dedicated Settings Page
	var center_node := menu_overlay.get_node_or_null("Center") as CenterContainer
	if center_node != null:
		_rankings_card = PanelContainer.new()
		_rankings_card.visible = false
		_rankings_card.custom_minimum_size = Vector2(580, 420)
		ThemeFactory.apply_panel_variant(_rankings_card, "card")
		var rvbox := VBoxContainer.new()
		rvbox.add_theme_constant_override("separation", 8)
		_rankings_card.add_child(rvbox)

		var rhdr := HBoxContainer.new()
		rhdr.add_theme_constant_override("separation", 8)
		var rback := Button.new()
		rback.text = "Back"
		rback.icon = _make_pixel_icon(_tex_back, Color.WHITE, 14)
		ThemeFactory.apply_button_variant(rback, "back")
		rback.pressed.connect(func() -> void:
			AudioManager.play_ui_tap()
			_show_menu_page("home")
		)
		rhdr.add_child(rback)
		var trophy_ic := TextureRect.new()
		trophy_ic.texture = _make_trophy_icon()
		trophy_ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		trophy_ic.custom_minimum_size = Vector2(18, 18)
		trophy_ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rhdr.add_child(trophy_ic)
		var rtitle := Label.new()
		rtitle.text = "GLOBAL LEADERBOARD"
		rtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rhdr.add_child(rtitle)
		var rref := Button.new()
		rref.text = "Refresh"
		ThemeFactory.apply_button_variant(rref, "secondary")
		rref.pressed.connect(func() -> void:
			AudioManager.play_ui_tap()
			leaderboard_open_requested.emit(_rankings_sort)
		)
		rhdr.add_child(rref)
		rvbox.add_child(rhdr)

		_rankings_me_lbl = Label.new()
		_rankings_me_lbl.text = "Your Rank: Guest · Sign in to climb Silver → Sovereign"
		_rankings_me_lbl.modulate = Color(0.96, 0.84, 0.42, 0.96)
		rvbox.add_child(_rankings_me_lbl)

		var rtabs := HBoxContainer.new()
		rtabs.add_theme_constant_override("separation", 6)
		_rankings_tab_lb = Button.new()
		_rankings_tab_lb.text = "Top ELO"
		_rankings_tab_lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_rankings_tab_wins = Button.new()
		_rankings_tab_wins.text = "Most Wins"
		_rankings_tab_wins.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_rankings_tab_land = Button.new()
		_rankings_tab_land.text = "Peak Land"
		_rankings_tab_land.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_rankings_tab_hist = Button.new()
		_rankings_tab_hist.text = "Match History"
		_rankings_tab_hist.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var select_lb_tab := func(mode_s: String, sort_s: String) -> void:
			AudioManager.play_ui_tap()
			_rankings_mode = mode_s
			_rankings_sort = sort_s
			ThemeFactory.apply_button_variant(_rankings_tab_lb, "primary" if (mode_s == "leaderboard" and sort_s == "elo") else "secondary")
			ThemeFactory.apply_button_variant(_rankings_tab_wins, "primary" if (mode_s == "leaderboard" and sort_s == "wins") else "secondary")
			ThemeFactory.apply_button_variant(_rankings_tab_land, "primary" if (mode_s == "leaderboard" and sort_s == "territory") else "secondary")
			ThemeFactory.apply_button_variant(_rankings_tab_hist, "primary" if mode_s == "history" else "secondary")
			if mode_s == "leaderboard":
				leaderboard_open_requested.emit(_rankings_sort)
			_render_rankings_rows()
		ThemeFactory.apply_button_variant(_rankings_tab_lb, "primary")
		ThemeFactory.apply_button_variant(_rankings_tab_wins, "secondary")
		ThemeFactory.apply_button_variant(_rankings_tab_land, "secondary")
		ThemeFactory.apply_button_variant(_rankings_tab_hist, "secondary")
		_rankings_tab_lb.pressed.connect(func() -> void: select_lb_tab.call("leaderboard", "elo"))
		_rankings_tab_wins.pressed.connect(func() -> void: select_lb_tab.call("leaderboard", "wins"))
		_rankings_tab_land.pressed.connect(func() -> void: select_lb_tab.call("leaderboard", "territory"))
		_rankings_tab_hist.pressed.connect(func() -> void: select_lb_tab.call("history", _rankings_sort))
		rtabs.add_child(_rankings_tab_lb)
		rtabs.add_child(_rankings_tab_wins)
		rtabs.add_child(_rankings_tab_land)
		rtabs.add_child(_rankings_tab_hist)
		rvbox.add_child(rtabs)

		var rscroll := ScrollContainer.new()
		rscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_rankings_rows = VBoxContainer.new()
		_rankings_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_rankings_rows.add_theme_constant_override("separation", 6)
		rscroll.add_child(_rankings_rows)
		rvbox.add_child(rscroll)
		center_node.add_child(_rankings_card)

		# Dedicated Settings Page Card
		_settings_card = PanelContainer.new()
		_settings_card.visible = false
		_settings_card.custom_minimum_size = Vector2(460, 0)
		ThemeFactory.apply_panel_variant(_settings_card, "card")
		var svbox := VBoxContainer.new()
		svbox.add_theme_constant_override("separation", 8)
		_settings_card.add_child(svbox)

		var shdr := HBoxContainer.new()
		shdr.add_theme_constant_override("separation", 8)
		var sback := Button.new()
		sback.text = "Back"
		sback.icon = _make_pixel_icon(_tex_back, Color.WHITE, 14)
		ThemeFactory.apply_button_variant(sback, "back")
		sback.pressed.connect(func() -> void:
			AudioManager.play_ui_tap()
			_show_menu_page("home")
		)
		shdr.add_child(sback)
		var gear_ic := TextureRect.new()
		gear_ic.texture = _make_gear_icon()
		gear_ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		gear_ic.custom_minimum_size = Vector2(18, 18)
		gear_ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		shdr.add_child(gear_ic)
		var stitle_l := Label.new()
		stitle_l.text = "SETTINGS & CONTROLS"
		stitle_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stitle_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		shdr.add_child(stitle_l)
		svbox.add_child(shdr)
		svbox.add_child(HSeparator.new())

		_set_mute_check = CheckButton.new()
		_set_mute_check.text = "Mute All Audio"
		_set_mute_check.toggled.connect(func(v: bool) -> void:
			if not _syncing_settings:
				mute_check.button_pressed = v
		)
		svbox.add_child(_set_mute_check)

		for sl_pair: Array in [
			["Master Volume", master_slider, "_set_master_sl"],
			["Music Volume", music_slider, "_set_music_sl"],
			["SFX / UI Volume", sfx_slider, "_set_sfx_sl"],
			["Ocean Ambience", ambience_slider, "_set_amb_sl"],
		]:
			var srow := HBoxContainer.new()
			srow.add_theme_constant_override("separation", 8)
			var slbl := Label.new()
			slbl.text = str(sl_pair[0])
			slbl.custom_minimum_size = Vector2(140, 0)
			var sldr := HSlider.new()
			sldr.max_value = 1.0
			sldr.step = 0.05
			sldr.value = (sl_pair[1] as HSlider).value
			sldr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var target_sl := sl_pair[1] as HSlider
			sldr.value_changed.connect(func(v: float) -> void:
				if not _syncing_settings:
					target_sl.value = v
			)
			set(str(sl_pair[2]), sldr)
			srow.add_child(slbl)
			srow.add_child(sldr)
			svbox.add_child(srow)

		svbox.add_child(HSeparator.new())
		var sd_row := HBoxContainer.new()
		sd_row.add_theme_constant_override("separation", 8)
		var sdlbl := Label.new()
		sdlbl.text = "Display Mode"
		sdlbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_set_disp_opt = OptionButton.new()
		_set_disp_opt.add_item("Windowed", 0)
		_set_disp_opt.add_item("Borderless", 1)
		_set_disp_opt.add_item("Fullscreen", 2)
		_set_disp_opt.item_selected.connect(func(idx: int) -> void:
			AudioManager.play_ui_tap()
			if _display_mode_option != null:
				_display_mode_option.select(idx)
			_apply_display_mode(idx, true)
		)
		sd_row.add_child(sdlbl)
		sd_row.add_child(_set_disp_opt)
		svbox.add_child(sd_row)

		var ss_row := HBoxContainer.new()
		ss_row.add_theme_constant_override("separation", 8)
		var sslbl := Label.new()
		sslbl.text = "UI Scale"
		sslbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_set_scale_opt = OptionButton.new()
		_set_scale_opt.add_item("90%", 0)
		_set_scale_opt.add_item("100%", 1)
		_set_scale_opt.add_item("115%", 2)
		_set_scale_opt.select(1)
		_set_scale_opt.item_selected.connect(func(idx: int) -> void:
			AudioManager.play_ui_tap()
			if _ui_scale_option != null:
				_ui_scale_option.select(idx)
			_apply_ui_scale(idx, true)
		)
		ss_row.add_child(sslbl)
		ss_row.add_child(_set_scale_opt)
		svbox.add_child(ss_row)

		_set_hotkeys_check = CheckButton.new()
		_set_hotkeys_check.text = "Enable Combat Hotkeys (1-9, F, Space, Alt+Click)"
		_set_hotkeys_check.button_pressed = _hotkeys_enabled
		_set_hotkeys_check.toggled.connect(func(v: bool) -> void:
			if _hotkeys_enabled != v:
				toggle_hotkeys()
		)
		svbox.add_child(_set_hotkeys_check)

		var ctrl_lbl := Label.new()
		ctrl_lbl.text = "Controls: Left-Click Explore/Build · Right-Click Wheel · Shift Multi-Build\nSpace Capital · Ctrl+1..4 / Alt+1..4 Bookmarks · Alt+Click Ping · Enter Chat"
		ctrl_lbl.modulate = Color(0.68, 0.78, 0.90, 0.90)
		ctrl_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ctrl_lbl.add_theme_font_size_override("font_size", 11)
		svbox.add_child(ctrl_lbl)
		center_node.add_child(_settings_card)

	# 8. In-Game Change Password Security + Profile Quick Links inside AccountCard
	var acct_vbox := account_card.get_node_or_null("VBox") as VBoxContainer
	if acct_vbox != null:
		var qnav_row := HBoxContainer.new()
		qnav_row.add_theme_constant_override("separation", 8)
		var p_fr_btn := Button.new()
		p_fr_btn.text = "Friends Roster"
		p_fr_btn.icon = _make_pixel_icon(_tex_friends, Color.WHITE, 14)
		p_fr_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ThemeFactory.apply_button_variant(p_fr_btn, "secondary")
		p_fr_btn.pressed.connect(func() -> void: open_friends_page("account"))
		var p_hist_btn := Button.new()
		p_hist_btn.text = "Match History & Replays"
		p_hist_btn.icon = _make_trophy_icon()
		p_hist_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ThemeFactory.apply_button_variant(p_hist_btn, "secondary")
		p_hist_btn.pressed.connect(func() -> void:
			AudioManager.play_ui_tap()
			_rankings_mode = "history"
			_show_menu_page("rankings")
			if _rankings_tab_lb != null:
				ThemeFactory.apply_button_variant(_rankings_tab_lb, "secondary")
				ThemeFactory.apply_button_variant(_rankings_tab_wins, "secondary")
				ThemeFactory.apply_button_variant(_rankings_tab_land, "secondary")
				ThemeFactory.apply_button_variant(_rankings_tab_hist, "primary")
			leaderboard_open_requested.emit(_rankings_sort)
			_render_rankings_rows()
		)
		qnav_row.add_child(p_fr_btn)
		qnav_row.add_child(p_hist_btn)
		acct_vbox.add_child(qnav_row)
		acct_vbox.move_child(qnav_row, mini(3, acct_vbox.get_child_count() - 1))

		_sec_box = VBoxContainer.new()
		_sec_box.visible = false
		_sec_box.add_theme_constant_override("separation", 6)
		_sec_box.add_child(HSeparator.new())
		var sec_lbl := Label.new()
		sec_lbl.text = "ACCOUNT SECURITY · CHANGE PASSWORD"
		sec_lbl.modulate = Color(0.84, 0.88, 0.96, 0.92)
		_sec_box.add_child(sec_lbl)
		_sec_cur_edit = LineEdit.new()
		_sec_cur_edit.secret = true
		_sec_cur_edit.placeholder_text = "Current Password"
		var new_row := HBoxContainer.new()
		new_row.add_theme_constant_override("separation", 6)
		_sec_new_edit = LineEdit.new()
		_sec_new_edit.secret = true
		_sec_new_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_sec_new_edit.placeholder_text = "New Password (4+ chars)"
		_sec_eye_btn = Button.new()
		_sec_eye_btn.custom_minimum_size = Vector2(36, 0)
		_sec_eye_btn.toggle_mode = true
		_sec_eye_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_sec_eye_btn.icon = _make_eye_icon(false)
		ThemeFactory.apply_button_variant(_sec_eye_btn, "ghost")
		_sec_conf_edit = LineEdit.new()
		_sec_conf_edit.secret = true
		_sec_conf_edit.placeholder_text = "Confirm New Password"
		_sec_eye_btn.toggled.connect(func(shown: bool) -> void:
			AudioManager.play_ui_tap()
			_sec_cur_edit.secret = not shown
			_sec_new_edit.secret = not shown
			_sec_conf_edit.secret = not shown
			_sec_eye_btn.icon = _make_eye_icon(shown)
		)
		new_row.add_child(_sec_new_edit)
		new_row.add_child(_sec_eye_btn)
		var sec_btn := Button.new()
		sec_btn.text = "Update Password"
		ThemeFactory.apply_button_variant(sec_btn, "secondary")
		_sec_status_lbl = Label.new()
		_sec_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sec_btn.pressed.connect(func() -> void:
			AudioManager.play_ui_tap()
			if _sec_new_edit.text.length() < 4:
				set_password_change_result(false, "New password must be at least 4 characters.")
				return
			if _sec_new_edit.text != _sec_conf_edit.text:
				set_password_change_result(false, "New passwords do not match.")
				return
			_sec_status_lbl.text = "Updating password..."
			account_change_password_requested.emit(_sec_cur_edit.text, _sec_new_edit.text)
		)
		_sec_box.add_child(_sec_cur_edit)
		_sec_box.add_child(new_row)
		_sec_box.add_child(_sec_conf_edit)
		_sec_box.add_child(sec_btn)
		_sec_box.add_child(_sec_status_lbl)
		acct_vbox.add_child(_sec_box)

	# 8b. Diplomacy Aid Amount Preset Row inside DiplomacyPanel
	var dip_vbox := diplomacy_panel.get_node_or_null("VBox") as VBoxContainer
	if dip_vbox != null:
		var aid_row := HBoxContainer.new()
		aid_row.add_theme_constant_override("separation", 6)
		var g_cycle := Button.new()
		g_cycle.text = "₱ Tier: 100K"
		g_cycle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ThemeFactory.apply_button_variant(g_cycle, "ghost")
		g_cycle.pressed.connect(func() -> void:
			AudioManager.play_ui_tap()
			_gold_aid_idx = (_gold_aid_idx + 1) % _gold_aid_amounts.size()
			var gv: float = _gold_aid_amounts[_gold_aid_idx]
			g_cycle.text = "₱ Tier: %s" % StructureData.format_pesos(gv)
			if _selected_dip_nation_id > 0:
				show_diplomacy_panel(_selected_dip_nation_id)
		)
		var t_cycle := Button.new()
		t_cycle.text = "Army Tier: 25%"
		t_cycle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ThemeFactory.apply_button_variant(t_cycle, "ghost")
		t_cycle.pressed.connect(func() -> void:
			AudioManager.play_ui_tap()
			_troop_aid_idx = (_troop_aid_idx + 1) % _troop_aid_ratios.size()
			t_cycle.text = "Army Tier: %d%%" % int(round(_troop_aid_ratios[_troop_aid_idx] * 100.0))
			if _selected_dip_nation_id > 0:
				show_diplomacy_panel(_selected_dip_nation_id)
		)
		aid_row.add_child(g_cycle)
		aid_row.add_child(t_cycle)
		dip_vbox.add_child(aid_row)

	# 9. In-Game Multiplayer Chat & Quick Comms Panel
	_chat_panel = PanelContainer.new()
	_chat_panel.visible = false
	_chat_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_chat_panel.offset_left = 14.0
	_chat_panel.offset_top = -270.0
	_chat_panel.offset_right = 356.0
	_chat_panel.offset_bottom = -114.0
	ThemeFactory.apply_panel_variant(_chat_panel, "flat")
	var cvbox := VBoxContainer.new()
	cvbox.add_theme_constant_override("separation", 4)
	_chat_panel.add_child(cvbox)

	_chat_log = RichTextLabel.new()
	_chat_log.bbcode_enabled = true
	_chat_log.scroll_following = true
	_chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_log.add_theme_font_size_override("normal_font_size", 11)
	cvbox.add_child(_chat_log)

	var quick_row := HBoxContainer.new()
	quick_row.add_theme_constant_override("separation", 4)
	for q_item: Array in [["Need ₱", "Need Pesos support!"], ["Attack!", "Coordinate attack now!"], ["Nuking", "Launching strategic strike!"], ["Defend", "Defend border / coast!"]]:
		var qb := Button.new()
		qb.text = str(q_item[0])
		ThemeFactory.apply_button_variant(qb, "ghost")
		qb.add_theme_font_size_override("font_size", 10)
		var q_msg := str(q_item[1])
		qb.pressed.connect(func() -> void:
			AudioManager.play_ui_tap()
			chat_send_requested.emit(_chat_channel, q_msg)
		)
		quick_row.add_child(qb)
	cvbox.add_child(quick_row)

	var cin_row := HBoxContainer.new()
	cin_row.add_theme_constant_override("separation", 4)
	_chat_chan_btn = Button.new()
	_chat_chan_btn.text = "[ALL]"
	ThemeFactory.apply_button_variant(_chat_chan_btn, "secondary")
	_chat_chan_btn.pressed.connect(func() -> void:
		AudioManager.play_ui_tap()
		_toggle_chat_channel()
	)
	_chat_input = LineEdit.new()
	_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_input.placeholder_text = "Enter to chat (Tab: All/Team)..."
	_chat_input.text_submitted.connect(func(txt: String) -> void:
		var clean: String = txt.strip_edges()
		if not clean.is_empty():
			chat_send_requested.emit(_chat_channel, clean)
		_chat_input.text = ""
		_chat_input.release_focus()
	)
	cin_row.add_child(_chat_chan_btn)
	cin_row.add_child(_chat_input)
	cvbox.add_child(cin_row)
	root_control.add_child(_chat_panel)

	# 10. Replay Speed Controls inside SpectatorBanner
	var sp_hbox := spectator_banner.get_node_or_null("HBox") as HBoxContainer
	if sp_hbox != null:
		_replay_controls_row = HBoxContainer.new()
		_replay_controls_row.visible = false
		_replay_controls_row.add_theme_constant_override("separation", 4)
		for spd_v: float in [1.0, 2.0, 4.0]:
			var sb := Button.new()
			sb.text = "%d×" % int(spd_v)
			ThemeFactory.apply_button_variant(sb, "secondary")
			var sv_cap := spd_v
			sb.pressed.connect(func() -> void:
				AudioManager.play_ui_tap()
				replay_speed_changed.emit(sv_cap)
			)
			_replay_controls_row.add_child(sb)
		sp_hbox.add_child(_replay_controls_row)
		sp_hbox.move_child(_replay_controls_row, maxi(1, sp_hbox.get_child_count() - 2))


func _sync_settings_controls() -> void:
	_syncing_settings = true
	if _set_mute_check != null:
		_set_mute_check.button_pressed = mute_check.button_pressed
	if _set_master_sl != null:
		_set_master_sl.value = master_slider.value
	if _set_music_sl != null:
		_set_music_sl.value = music_slider.value
	if _set_sfx_sl != null:
		_set_sfx_sl.value = sfx_slider.value
	if _set_amb_sl != null:
		_set_amb_sl.value = ambience_slider.value
	if _set_disp_opt != null and _display_mode_option != null:
		_set_disp_opt.select(_display_mode_option.selected)
	if _set_scale_opt != null and _ui_scale_option != null:
		_set_scale_opt.select(_ui_scale_option.selected)
	if _set_hotkeys_check != null:
		_set_hotkeys_check.button_pressed = _hotkeys_enabled
	_syncing_settings = false


func _toggle_chat_channel() -> void:
	_chat_channel = "team" if _chat_channel == "all" else "all"
	if _chat_chan_btn != null:
		_chat_chan_btn.text = "[TEAM]" if _chat_channel == "team" else "[ALL]"


func _snap_camera_to_capital() -> void:
	if _world_state == null:
		return
	var p_n: NationData = _world_state.get_player_nation()
	if p_n == null or not p_n.alive:
		return
	var cap: Vector2i = p_n.capital_cell
	if cap.x < 0:
		cap = _world_state.get_nation_label_cell(p_n.id)
	if cap.x >= 0:
		camera_focus_requested.emit(_world_state.sim_to_world(cap), 2.2)
		AudioManager.play_ui_tap()


func _toggle_fullscreen_hotkey() -> void:
	var cur := DisplayServer.window_get_mode()
	var next_idx: int = 0 if cur == DisplayServer.WINDOW_MODE_FULLSCREEN else 2
	if _display_mode_option != null:
		_display_mode_option.select(next_idx)
	_apply_display_mode(next_idx, true)


func _apply_display_mode(idx: int, save_cfg: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	match idx:
		1:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		2:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	if save_cfg:
		var cfg := ConfigFile.new()
		cfg.load(PROFILE_SAVE_PATH)
		cfg.set_value("display", "mode", idx)
		cfg.save(PROFILE_SAVE_PATH)


func _apply_ui_scale(idx: int, save_cfg: bool) -> void:
	var scales := [0.90, 1.0, 1.15]
	var factor: float = scales[clampi(idx, 0, scales.size() - 1)]
	if DisplayServer.get_name() != "headless":
		get_tree().root.content_scale_factor = factor
	if save_cfg:
		var cfg := ConfigFile.new()
		cfg.load(PROFILE_SAVE_PATH)
		cfg.set_value("display", "ui_scale_idx", idx)
		cfg.save(PROFILE_SAVE_PATH)


func _apply_saved_display_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PROFILE_SAVE_PATH) != OK:
		return
	var d_idx: int = clampi(int(cfg.get_value("display", "mode", 0)), 0, 2)
	var s_idx: int = clampi(int(cfg.get_value("display", "ui_scale_idx", 1)), 0, 2)
	if _display_mode_option != null:
		_display_mode_option.select(d_idx)
	if _ui_scale_option != null:
		_ui_scale_option.select(s_idx)
	if d_idx != 0:
		_apply_display_mode(d_idx, false)
	if s_idx != 1:
		_apply_ui_scale(s_idx, false)


func _refresh_offscreen_threats() -> void:
	if _threat_overlay == null:
		return
	_threat_markers.clear()
	if _world_state == null or _world_state.match_phase != WorldState.PHASE_PLAYING or menu_overlay.visible:
		_threat_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_threat_overlay.queue_redraw()
		return
	var vp_rect: Rect2 = get_viewport().get_visible_rect()
	var xform: Transform2D = get_viewport().get_canvas_transform()
	var p_id: int = _world_state.player_nation_id
	var candidates: Array[Dictionary] = []

	for mid: int in _world_state.missiles.keys():
		var m: MissileUnit = _world_state.missiles[mid]
		if m.active and m.kind != MissileUnit.KIND_SAM and m.nation_id != p_id and m.target_nation_id == p_id:
			candidates.append({"world": m.pos, "label": "NUKE"})
	for sid: int in _world_state.ships.keys():
		var sh: ShipUnit = _world_state.ships[sid]
		if sh.active and sh.kind == ShipUnit.KIND_LANDING and sh.nation_id != p_id and sh.target_owner_id == p_id:
			candidates.append({"world": sh.position, "label": "LANDING"})
	if _world_state.last_player_threat_world_pos.x >= 0.0 and candidates.is_empty():
		candidates.append({"world": _world_state.last_player_threat_world_pos, "label": "ATTACK"})

	for item: Dictionary in candidates:
		var wp: Vector2 = item["world"] as Vector2
		var sp: Vector2 = xform * wp
		if vp_rect.grow(-24.0).has_point(sp):
			continue
		var center: Vector2 = vp_rect.size * 0.5
		var dir: Vector2 = (sp - center).normalized()
		var edge_pos := Vector2(
			clampf(center.x + dir.x * (vp_rect.size.x * 0.44), 28.0, vp_rect.size.x - 28.0),
			clampf(center.y + dir.y * (vp_rect.size.y * 0.40), 58.0, vp_rect.size.y - 110.0)
		)
		_threat_markers.append({"screen": edge_pos, "dir": dir, "world": wp, "label": item["label"]})
		if _threat_markers.size() >= 4:
			break
	_threat_overlay.mouse_filter = Control.MOUSE_FILTER_PASS if not _threat_markers.is_empty() else Control.MOUSE_FILTER_IGNORE
	_threat_overlay.queue_redraw()


func _on_threat_overlay_draw() -> void:
	if _threat_markers.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	for mk: Dictionary in _threat_markers:
		var sp: Vector2 = mk["screen"] as Vector2
		var dir: Vector2 = mk["dir"] as Vector2
		var perp := Vector2(-dir.y, dir.x)
		var tri := PackedVector2Array([sp + dir * 13.0, sp - dir * 8.0 + perp * 9.0, sp - dir * 8.0 - perp * 9.0])
		_threat_overlay.draw_colored_polygon(tri, Color(1.0, 0.28, 0.34, 0.94))
		if font != null:
			_threat_overlay.draw_string(font, sp + Vector2(-18.0, 22.0), str(mk["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.78, 0.72, 0.96))


func _on_threat_overlay_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var click_pos: Vector2 = (ev as InputEventMouseButton).position
		for mk: Dictionary in _threat_markers:
			if click_pos.distance_to(mk["screen"] as Vector2) <= 22.0:
				AudioManager.play_ui_tap()
				camera_focus_requested.emit(mk["world"] as Vector2, 2.2)
				get_viewport().set_input_as_handled()
				return


func _on_victory_chart_draw() -> void:
	if _victory_chart == null or _victory_history.size() < 2 or _world_state == null:
		return
	var sz: Vector2 = _victory_chart.size
	var plot := Rect2(Vector2(34.0, 12.0), Vector2(maxf(40.0, sz.x - 46.0), maxf(30.0, sz.y - 30.0)))
	_victory_chart.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.06, 0.08, 0.11, 0.85), true)
	_victory_chart.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.24, 0.30, 0.38, 0.9), false, 1.0)
	for g in [0.25, 0.5, 0.75, 1.0]:
		var gy: float = plot.position.y + plot.size.y * (1.0 - g)
		_victory_chart.draw_line(Vector2(plot.position.x, gy), Vector2(plot.end.x, gy), Color(0.22, 0.26, 0.34, 0.5), 1.0)
	var font: Font = ThemeDB.fallback_font
	if font != null:
		_victory_chart.draw_string(font, Vector2(6.0, plot.position.y + 10.0), "80%", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.68, 0.74, 0.82))
		_victory_chart.draw_string(font, Vector2(6.0, plot.end.y), "0%", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.68, 0.74, 0.82))

	var n_count: int = _victory_history.size()
	for nid: int in _world_state.nations.keys():
		var nd: NationData = _world_state.nations[nid]
		var pts := PackedVector2Array()
		for i in range(n_count):
			var snap: Dictionary = _victory_history[i].get("nations", {}) as Dictionary
			var pct_v: float = float(snap.get(nid, 0.0))
			var px: float = plot.position.x + (float(i) / float(maxi(1, n_count - 1))) * plot.size.x
			var py: float = plot.end.y - clampf(pct_v / 85.0, 0.0, 1.0) * plot.size.y
			pts.append(Vector2(px, py))
		if pts.size() >= 2:
			_victory_chart.draw_polyline(pts, nd.color, 2.4 if nid == _world_state.player_nation_id else 1.4, true)


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
