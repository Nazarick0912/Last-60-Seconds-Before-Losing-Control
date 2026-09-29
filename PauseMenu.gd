class_name PauseMenu
extends CanvasLayer

## Global static camera tilt multiplier accessible across the project
static var camera_tilt_scale: float = 1.0

const SETTINGS_PATH: String = "user://settings.cfg"

var _is_paused: bool = false

# Node references
var master_slider: HSlider
var master_val_label: Label
var music_slider: HSlider
var music_val_label: Label
var sfx_slider: HSlider
var sfx_val_label: Label
var voice_slider: HSlider
var voice_val_label: Label
var tilt_slider: HSlider
var tilt_val_label: Label

var resume_btn: Button
var restart_btn: Button
var main_menu_btn: Button
var card_panel: PanelContainer

func _setup_node_references() -> void:
	if not master_slider:
		master_slider = find_child("MasterSlider", true, false) as HSlider
	if not master_val_label:
		master_val_label = find_child("MasterValLabel", true, false) as Label
	if not music_slider:
		music_slider = find_child("MusicSlider", true, false) as HSlider
	if not music_val_label:
		music_val_label = find_child("MusicValLabel", true, false) as Label
	if not sfx_slider:
		sfx_slider = find_child("SFXSlider", true, false) as HSlider
	if not sfx_val_label:
		sfx_val_label = find_child("SFXValLabel", true, false) as Label
	if not voice_slider:
		voice_slider = find_child("VoiceSlider", true, false) as HSlider
	if not voice_val_label:
		voice_val_label = find_child("VoiceValLabel", true, false) as Label
	if not tilt_slider:
		tilt_slider = find_child("TiltSlider", true, false) as HSlider
	if not tilt_val_label:
		tilt_val_label = find_child("TiltValLabel", true, false) as Label

	if not resume_btn:
		resume_btn = find_child("ResumeButton", true, false) as Button
	if not restart_btn:
		restart_btn = find_child("RestartButton", true, false) as Button
	if not main_menu_btn:
		main_menu_btn = find_child("MainMenuButton", true, false) as Button
	if not card_panel:
		card_panel = find_child("CardPanel", true, false) as PanelContainer

const BUS_BASE_DB: Dictionary = {
	"Master": 0.0,
	"Music": 6.0,
	"SFX": -7.5,
	"Voice": -5.0
}

static func _static_init() -> void:
	# Load settings statically on startup so camera_tilt_scale and buses are immediately synced
	apply_saved_audio_and_tilt()

static func apply_saved_audio_and_tilt() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		var master_vol = float(cfg.get_value("audio", "master_volume", 0.5))
		var music_vol = float(cfg.get_value("audio", "music_volume", 0.5))
		var sfx_vol = float(cfg.get_value("audio", "sfx_volume", 0.5))
		var voice_vol = float(cfg.get_value("audio", "voice_volume", 0.5))
		camera_tilt_scale = float(cfg.get_value("gameplay", "camera_tilt_scale", 1.0))
		set_bus_linear("Master", master_vol)
		set_bus_linear("Music", music_vol)
		set_bus_linear("SFX", sfx_vol)
		set_bus_linear("Voice", voice_vol)
	else:
		camera_tilt_scale = 1.0
		set_bus_linear("Master", 0.5)
		set_bus_linear("Music", 0.5)
		set_bus_linear("SFX", 0.5)
		set_bus_linear("Voice", 0.5)

static func set_bus_linear(bus_name: String, linear_val: float) -> void:
	var idx = AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		if linear_val <= 0.001:
			AudioServer.set_bus_mute(idx, true)
		else:
			AudioServer.set_bus_mute(idx, false)
			var base_db: float = BUS_BASE_DB.get(bus_name, 0.0)
			AudioServer.set_bus_volume_db(idx, base_db + linear_to_db(linear_val))

func _enter_tree() -> void:
	_setup_node_references()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_setup_node_references()
	_apply_visual_styling()

	# Connect sliders
	if master_slider and not master_slider.value_changed.is_connected(_on_master_slider_changed):
		master_slider.value_changed.connect(_on_master_slider_changed)
	if music_slider and not music_slider.value_changed.is_connected(_on_music_slider_changed):
		music_slider.value_changed.connect(_on_music_slider_changed)
	if sfx_slider and not sfx_slider.value_changed.is_connected(_on_sfx_slider_changed):
		sfx_slider.value_changed.connect(_on_sfx_slider_changed)
	if voice_slider and not voice_slider.value_changed.is_connected(_on_voice_slider_changed):
		voice_slider.value_changed.connect(_on_voice_slider_changed)
	if tilt_slider and not tilt_slider.value_changed.is_connected(_on_tilt_slider_changed):
		tilt_slider.value_changed.connect(_on_tilt_slider_changed)

	# Connect buttons
	if resume_btn and not resume_btn.pressed.is_connected(_on_resume_pressed):
		resume_btn.pressed.connect(_on_resume_pressed)
	if restart_btn and not restart_btn.pressed.is_connected(_on_restart_pressed):
		restart_btn.pressed.connect(_on_restart_pressed)
	if main_menu_btn and not main_menu_btn.pressed.is_connected(_on_main_menu_pressed):
		main_menu_btn.pressed.connect(_on_main_menu_pressed)

	load_settings()

func _apply_visual_styling() -> void:
	# 1. Card Container: Deep Night Indigo, 4px saturated lavender border, 24px corner radius, bold drop shadow
	if card_panel:
		var panel_style = StyleBoxFlat.new()
		panel_style.bg_color = Color(0.12, 0.09, 0.22, 0.95)
		panel_style.border_width_left = 4
		panel_style.border_width_top = 4
		panel_style.border_width_right = 4
		panel_style.border_width_bottom = 4
		panel_style.border_color = Color(0.48, 0.38, 0.72, 1.0)
		panel_style.corner_radius_top_left = 24
		panel_style.corner_radius_top_right = 24
		panel_style.corner_radius_bottom_left = 24
		panel_style.corner_radius_bottom_right = 24
		panel_style.shadow_color = Color(0, 0, 0, 0.6)
		panel_style.shadow_size = 20
		panel_style.shadow_offset = Vector2(0, 10)
		card_panel.add_theme_stylebox_override("panel", panel_style)

	# 2. Typography & Header ("PAUSED")
	var header_label = find_child("HeaderLabel", true, false) as Label
	if header_label:
		header_label.add_theme_font_size_override("font_size", 40)
		header_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		header_label.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.25, 1.0))
		header_label.add_theme_constant_override("outline_size", 6)
		header_label.add_theme_color_override("font_shadow_color", Color(0.08, 0.04, 0.15, 0.9))
		header_label.add_theme_constant_override("shadow_offset_x", 0)
		header_label.add_theme_constant_override("shadow_offset_y", 4)
		header_label.add_theme_constant_override("shadow_outline_size", 4)

	# Section & Value Labels
	for val_label in [master_val_label, music_val_label, sfx_val_label, voice_val_label, tilt_val_label]:
		if val_label and is_instance_valid(val_label):
			val_label.add_theme_font_size_override("font_size", 16)
			val_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
			val_label.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.25, 0.9))
			val_label.add_theme_constant_override("outline_size", 2)

	for group_name in ["MasterGroup", "MusicGroup", "SFXGroup", "VoiceGroup", "TiltGroup"]:
		var group = find_child(group_name, true, false)
		if group:
			var lbl = group.find_child("Label", true, false) as Label
			if lbl:
				lbl.add_theme_font_size_override("font_size", 16)
				lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
				lbl.add_theme_color_override("font_outline_color", Color(0.10, 0.08, 0.18, 0.8))
				lbl.add_theme_constant_override("outline_size", 2)

	# Separators
	var sep_style = StyleBoxLine.new()
	sep_style.color = Color(0.38, 0.30, 0.55, 0.5)
	sep_style.thickness = 2
	for sep in find_children("*", "HSeparator", true, false):
		sep.add_theme_stylebox_override("separator", sep_style)

	# 3. Chunky Sliders Theme
	_style_sliders()

	# 4. Juicy 3D Arcade Buttons
	# Primary ("Resume"): Bright Golden Yellow, 5px bottom shadow bevel, dark bold text, downward click feel
	if resume_btn:
		_style_beveled_button(
			resume_btn,
			Color(1.0, 0.82, 0.2),         # Top face: Bright Golden Yellow
			Color(0.75, 0.55, 0.1),         # Bottom bevel shadow
			Color(0.18, 0.10, 0.25),        # Dark bold chocolate text
			12,                             # Corner radius
			5,                              # Bevel height
			false,                          # Text outline
			19                              # Font size
		)

	# Secondary ("Restart Run"): Soft Indigo/Purple pill button, 4px darker bottom bevel, white text with outline
	if restart_btn:
		_style_beveled_button(
			restart_btn,
			Color(0.32, 0.25, 0.48, 0.95),  # Soft Indigo/Purple
			Color(0.20, 0.15, 0.32, 1.0),   # Darker bottom bevel
			Color(1.0, 1.0, 1.0),           # White text
			12,                             # Corner radius
			4,                              # Bevel height
			true,                           # Text outline
			17                              # Font size
		)

	# Tertiary ("Main Menu"): Muted Crimson/Rose pill button, 4px darker bottom bevel, white text
	if main_menu_btn:
		_style_beveled_button(
			main_menu_btn,
			Color(0.42, 0.20, 0.26, 0.9),   # Muted Crimson/Rose
			Color(0.26, 0.12, 0.16, 1.0),   # Darker bottom bevel
			Color(1.0, 1.0, 1.0),           # White text
			12,                             # Corner radius
			4,                              # Bevel height
			false,                          # Text outline
			17                              # Font size
		)

func _style_sliders() -> void:
	# Background track (inset, height ~12px, corner radius 7px)
	var groove = StyleBoxFlat.new()
	groove.bg_color = Color(0.08, 0.06, 0.14, 0.9)
	groove.border_width_left = 1
	groove.border_width_top = 1
	groove.border_width_right = 1
	groove.border_width_bottom = 1
	groove.border_color = Color(0.28, 0.22, 0.42, 0.7)
	groove.corner_radius_top_left = 7
	groove.corner_radius_top_right = 7
	groove.corner_radius_bottom_left = 7
	groove.corner_radius_bottom_right = 7
	groove.content_margin_top = 6
	groove.content_margin_bottom = 6
	groove.expand_margin_top = 3
	groove.expand_margin_bottom = 3

	# Fill color: Vibrant Amber Yellow, corner radius 7px
	var grabber_area = StyleBoxFlat.new()
	grabber_area.bg_color = Color(1.0, 0.78, 0.15)
	grabber_area.corner_radius_top_left = 7
	grabber_area.corner_radius_top_right = 7
	grabber_area.corner_radius_bottom_left = 7
	grabber_area.corner_radius_bottom_right = 7
	grabber_area.content_margin_top = 6
	grabber_area.content_margin_bottom = 6
	grabber_area.expand_margin_top = 3
	grabber_area.expand_margin_bottom = 3

	var grabber_area_hl = grabber_area.duplicate()
	grabber_area_hl.bg_color = Color(1.0, 0.85, 0.25)

	# Chunky oversized 22x22 circular grabber with spherical highlight & drop shadow
	var img = Image.create(22, 22, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var center = Vector2(10.5, 10.5)
	var radius = 9.5
	for x in range(22):
		for y in range(22):
			var pos = Vector2(x, y)
			var dist = (pos - center).length()
			if dist <= radius:
				var norm = (pos - center) / radius
				var shade = clamp(-norm.x * 0.4 - norm.y * 0.6, -1.0, 1.0)
				var col = Color(0.96, 0.95, 0.92)
				if shade > 0.25:
					col = col.lerp(Color(1.0, 1.0, 1.0), 0.9)
				elif shade < -0.2:
					col = col.lerp(Color(0.74, 0.72, 0.80), 0.75)
				if dist > radius - 1.5:
					col = col.lerp(Color(0.50, 0.45, 0.60), 0.85)
				img.set_pixel(x, y, col)
			elif dist <= radius + 1.2:
				img.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.4))
	var grabber_tex = ImageTexture.create_from_image(img)

	for slider in [master_slider, music_slider, sfx_slider, voice_slider, tilt_slider]:
		if slider and is_instance_valid(slider):
			slider.custom_minimum_size.y = 30
			slider.add_theme_stylebox_override("slider", groove)
			slider.add_theme_stylebox_override("grabber_area", grabber_area)
			slider.add_theme_stylebox_override("grabber_area_highlight", grabber_area_hl)
			slider.add_theme_icon_override("grabber", grabber_tex)
			slider.add_theme_icon_override("grabber_highlight", grabber_tex)

func _style_beveled_button(
	btn: Button,
	face_color: Color,
	bevel_color: Color,
	text_color: Color,
	corner_rad: int = 12,
	bevel_height: int = 5,
	has_text_outline: bool = false,
	font_size: int = 18
) -> void:
	# Normal state with physical bottom bevel
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = face_color
	style_normal.corner_radius_top_left = corner_rad
	style_normal.corner_radius_top_right = corner_rad
	style_normal.corner_radius_bottom_left = corner_rad
	style_normal.corner_radius_bottom_right = corner_rad
	style_normal.border_width_bottom = bevel_height
	style_normal.border_color = bevel_color
	style_normal.content_margin_top = 10
	style_normal.content_margin_bottom = 10
	style_normal.content_margin_left = 16
	style_normal.content_margin_right = 16

	# Hover state with subtle lift
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = face_color.lightened(0.12)
	style_hover.border_color = bevel_color.lightened(0.08)

	# Pressed state: bevel collapses to 1px and content shifts down for tactile click
	var style_pressed = StyleBoxFlat.new()
	style_pressed.bg_color = face_color.darkened(0.06)
	style_pressed.corner_radius_top_left = corner_rad
	style_pressed.corner_radius_top_right = corner_rad
	style_pressed.corner_radius_bottom_left = corner_rad
	style_pressed.corner_radius_bottom_right = corner_rad
	style_pressed.border_width_bottom = 1
	style_pressed.border_color = bevel_color
	style_pressed.content_margin_top = 10 + (bevel_height - 1)
	style_pressed.content_margin_bottom = 10 - (bevel_height - 1)
	style_pressed.content_margin_left = 16
	style_pressed.content_margin_right = 16

	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	btn.add_theme_stylebox_override("focus", style_hover)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", text_color)
	btn.add_theme_color_override("font_hover_color", text_color)
	btn.add_theme_color_override("font_pressed_color", text_color)
	btn.add_theme_color_override("font_focus_color", text_color)

	if has_text_outline:
		btn.add_theme_color_override("font_outline_color", Color(0.12, 0.08, 0.20, 0.9))
		btn.add_theme_constant_override("outline_size", 4)
	else:
		btn.remove_theme_color_override("font_outline_color")
		btn.remove_theme_constant_override("outline_size")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# If game has already ended in victory or loss screen, do not override
		var hud = get_tree().root.find_child("ShoppingHUD", true, false)
		if hud and hud.get("_game_ended") == true:
			return
		toggle_pause()
		get_viewport().set_input_as_handled()

func toggle_pause() -> void:
	set_paused(!_is_paused)

func set_paused(p: bool) -> void:
	_is_paused = p
	get_tree().paused = p
	visible = p

	if p:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		if resume_btn and is_instance_valid(resume_btn):
			resume_btn.grab_focus()
	else:
		save_settings()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_master_slider_changed(val: float) -> void:
	set_bus_linear("Master", val)
	if master_val_label:
		master_val_label.text = "%d%%" % int(round(val * 100.0))

func _on_music_slider_changed(val: float) -> void:
	set_bus_linear("Music", val)
	if music_val_label:
		music_val_label.text = "%d%%" % int(round(val * 100.0))

func _on_sfx_slider_changed(val: float) -> void:
	set_bus_linear("SFX", val)
	if sfx_val_label:
		sfx_val_label.text = "%d%%" % int(round(val * 100.0))

func _on_voice_slider_changed(val: float) -> void:
	set_bus_linear("Voice", val)
	if voice_val_label:
		voice_val_label.text = "%d%%" % int(round(val * 100.0))

func _on_tilt_slider_changed(val: float) -> void:
	camera_tilt_scale = val
	if tilt_val_label:
		tilt_val_label.text = "%d%%" % int(round(val * 100.0))

func load_settings() -> void:
	var cfg = ConfigFile.new()
	var err = cfg.load(SETTINGS_PATH)
	var master_vol: float = 0.5
	var music_vol: float = 0.5
	var sfx_vol: float = 0.5
	var voice_vol: float = 0.5
	var tilt_val: float = 1.0

	if err == OK:
		master_vol = float(cfg.get_value("audio", "master_volume", 0.5))
		music_vol = float(cfg.get_value("audio", "music_volume", 0.5))
		sfx_vol = float(cfg.get_value("audio", "sfx_volume", 0.5))
		voice_vol = float(cfg.get_value("audio", "voice_volume", 0.5))
		tilt_val = float(cfg.get_value("gameplay", "camera_tilt_scale", 1.0))

	if master_slider:
		master_slider.value = master_vol
	_on_master_slider_changed(master_vol)

	if music_slider:
		music_slider.value = music_vol
	_on_music_slider_changed(music_vol)

	if sfx_slider:
		sfx_slider.value = sfx_vol
	_on_sfx_slider_changed(sfx_vol)

	if voice_slider:
		voice_slider.value = voice_vol
	_on_voice_slider_changed(voice_vol)

	if tilt_slider:
		tilt_slider.value = tilt_val
	_on_tilt_slider_changed(tilt_val)

func save_settings() -> void:
	var cfg = ConfigFile.new()
	cfg.load(SETTINGS_PATH) # Load existing settings to avoid overwriting unrelated sections
	if master_slider:
		cfg.set_value("audio", "master_volume", master_slider.value)
	if music_slider:
		cfg.set_value("audio", "music_volume", music_slider.value)
	if sfx_slider:
		cfg.set_value("audio", "sfx_volume", sfx_slider.value)
	if voice_slider:
		cfg.set_value("audio", "voice_volume", voice_slider.value)
	if tilt_slider:
		cfg.set_value("gameplay", "camera_tilt_scale", tilt_slider.value)
	cfg.save(SETTINGS_PATH)

func _on_resume_pressed() -> void:
	set_paused(false)

func _on_restart_pressed() -> void:
	save_settings()
	get_tree().paused = false
	var gm = get_node_or_null("/root/GameModeManager")
	if gm and gm.has_method("_reset_list"):
		gm._reset_list()
	get_tree().reload_current_scene()

func _on_main_menu_pressed() -> void:
	save_settings()
	get_tree().paused = false
	var gm = get_node_or_null("/root/GameModeManager")
	if gm and gm.has_method("_reset_list"):
		gm._reset_list()
	if ResourceLoader.exists("res://intro.tscn"):
		get_tree().change_scene_to_file("res://intro.tscn")
	else:
		var main_scene = ProjectSettings.get_setting("application/run/main_scene")
		if ResourceLoader.exists(main_scene):
			get_tree().change_scene_to_file(main_scene)
