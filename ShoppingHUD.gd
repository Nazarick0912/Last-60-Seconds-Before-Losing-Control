extends CanvasLayer

# ──────────────────────────────────────────────────────────
#  ShoppingHUD  –  In-game overlay
#   • Shopping list panel  (top-left, always visible)
#   • Centre-top timer     (prominent countdown)
#   • Win / Lose result overlay (centre, shown on game end)
# ──────────────────────────────────────────────────────────

const TOTAL_TIME: float = 60.0   # must match Player.gd TOTAL_TIME

var _list_panel:   PanelContainer
var _list_label:   Label

var _timer_panel:  PanelContainer
var _timer_label:  Label
var _time_left:    float = TOTAL_TIME
var _game_ended:   bool  = false

var _result_root:  Control
var _result_title: Label
var _result_sub:   Label
var _restart_btn:  Button

var _warning_panel:  PanelContainer
var _warning_label:  Label
var _warning_timer:  float = 0.0

var _checkout_banner: PanelContainer
var _checkout_label:  Label

var _stamina_panel:   PanelContainer
var _stamina_bar:     ProgressBar
var _stamina_label:   Label
var _stamina_gate_line: ColorRect

# ── Lifecycle ─────────────────────────────────────────────
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keep ticking while paused

	_build_list_panel()
	_build_timer()
	_build_warning_toast()
	_build_checkout_banner()
	_build_stamina_bar()
	_build_result_overlay()

	var gm: Node = get_node_or_null("/root/GameModeManager")
	if gm:
		gm.list_updated.connect(_refresh_list)
		gm.game_won.connect(_on_game_won)
		gm.game_lost.connect(_on_game_lost)
		if gm.has_signal("checkout_ready"):
			gm.checkout_ready.connect(_on_checkout_ready)
		if gm.has_signal("warning_triggered"):
			gm.warning_triggered.connect(show_warning)

	_refresh_list()

func _process(delta: float) -> void:
	if _game_ended:
		return
	var gm: Node = get_node_or_null("/root/GameModeManager")
	if gm and gm.is_active():
		_time_left = max(0.0, _time_left - delta)
		_update_timer()

	_process_warning_toast(delta)
	_process_checkout_banner(delta)
	_process_stamina_ui(delta)

# ── Shopping list panel (top-left) ────────────────────────
func _build_list_panel() -> void:
	_list_panel = PanelContainer.new()
	_list_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_list_panel.position = Vector2(20, 20)
	_list_panel.custom_minimum_size = Vector2(270, 0)

	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.05, 0.15, 0.84)
	s.border_color = Color(0.55, 0.35, 0.9, 1.0)
	s.set_border_width_all(2)
	s.corner_radius_top_left    = 12
	s.corner_radius_top_right   = 12
	s.corner_radius_bottom_left = 12
	s.corner_radius_bottom_right= 12
	s.set_content_margin_all(16)
	_list_panel.add_theme_stylebox_override("panel", s)
	add_child(_list_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_list_panel.add_child(vbox)

	var title := Label.new()
	title.text = "🛒  Shopping List"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	vbox.add_child(title)

	var sep := HSeparator.new()
	var ss  := StyleBoxFlat.new()
	ss.bg_color = Color(0.55, 0.35, 0.9, 0.55)
	ss.set_content_margin_all(3)
	sep.add_theme_stylebox_override("separator", ss)
	vbox.add_child(sep)

	_list_label = Label.new()
	_list_label.add_theme_font_size_override("font_size", 24)
	_list_label.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	vbox.add_child(_list_label)

	var tip := Label.new()
	tip.text = "\n💡 Walk into glowing items!"
	tip.add_theme_font_size_override("font_size", 11)
	tip.add_theme_color_override("font_color", Color(0.7, 0.7, 0.9, 0.8))
	vbox.add_child(tip)

# ── Centre-top countdown timer ────────────────────────────
func _build_timer() -> void:
	_timer_panel = PanelContainer.new()
	# Anchor to top-centre, grow both sides
	_timer_panel.anchor_left   = 0.5
	_timer_panel.anchor_right  = 0.5
	_timer_panel.anchor_top    = 0.0
	_timer_panel.anchor_bottom = 0.0
	_timer_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_timer_panel.offset_left   = -90.0
	_timer_panel.offset_right  =  90.0
	_timer_panel.offset_top    =  15.0
	_timer_panel.offset_bottom =  15.0   # auto sized by content
	_timer_panel.custom_minimum_size = Vector2(180, 0)

	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.05, 0.18, 0.88)
	s.border_color = Color(0.85, 0.42, 0.08, 1.0)
	s.set_border_width_all(2)
	s.corner_radius_top_left    = 14
	s.corner_radius_top_right   = 14
	s.corner_radius_bottom_left = 14
	s.corner_radius_bottom_right= 14
	s.set_content_margin_all(10)
	_timer_panel.add_theme_stylebox_override("panel", s)
	add_child(_timer_panel)

	_timer_label = Label.new()
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 30)
	_timer_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_timer_label.text = "⏱  60s"
	_timer_panel.add_child(_timer_label)

func _update_timer() -> void:
	var secs: int = int(ceil(_time_left))
	_timer_label.text = "⏱  %ds" % secs

	if _time_left <= 10.0:
		# Pulse red
		var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.01)
		_timer_label.add_theme_color_override("font_color", Color(1.0, pulse * 0.25, pulse * 0.25))
	elif _time_left <= 30.0:
		_timer_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.1))
	else:
		_timer_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))

# ── Cart Requirement Warning Toast (Top-Center) ───────────
func _build_warning_toast() -> void:
	_warning_panel = PanelContainer.new()
	_warning_panel.anchor_left   = 0.5
	_warning_panel.anchor_right  = 0.5
	_warning_panel.anchor_top    = 0.0
	_warning_panel.anchor_bottom = 0.0
	_warning_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_warning_panel.offset_left   = -230.0
	_warning_panel.offset_right  =  230.0
	_warning_panel.offset_top    =  75.0
	_warning_panel.custom_minimum_size = Vector2(460, 48)

	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.70, 0.08, 0.08, 0.94)
	s.border_color = Color(1.0, 0.35, 0.35, 1.0)
	s.set_border_width_all(3)
	s.corner_radius_top_left    = 14
	s.corner_radius_top_right   = 14
	s.corner_radius_bottom_left = 14
	s.corner_radius_bottom_right= 14
	s.set_content_margin_all(10)
	_warning_panel.add_theme_stylebox_override("panel", s)
	_warning_panel.visible = false
	add_child(_warning_panel)

	_warning_label = Label.new()
	_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warning_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_warning_label.add_theme_font_size_override("font_size", 18)
	_warning_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_warning_label.text = "⚠️ Cart required to collect groceries!"
	_warning_panel.add_child(_warning_label)

func show_warning(msg: String = "🛒 Cart required to collect groceries!") -> void:
	if _game_ended:
		return
	_warning_label.text = msg
	_warning_timer = 1.5
	_warning_panel.visible = true

func _process_warning_toast(delta: float) -> void:
	if _warning_timer > 0.0:
		_warning_timer -= delta
		# Red pulsing effect
		var pulse: float = 0.8 + 0.2 * sin(Time.get_ticks_msec() * 0.015)
		_warning_panel.modulate = Color(1.0, pulse, pulse, clamp(_warning_timer / 0.25, 0.0, 1.0))
		if _warning_timer <= 0.0:
			_warning_panel.visible = false
	else:
		_warning_panel.visible = false

# ── Checkout Goal Alert Banner ────────────────────────────
func _build_checkout_banner() -> void:
	_checkout_banner = PanelContainer.new()
	_checkout_banner.anchor_left   = 0.5
	_checkout_banner.anchor_right  = 0.5
	_checkout_banner.anchor_top    = 0.0
	_checkout_banner.anchor_bottom = 0.0
	_checkout_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_checkout_banner.offset_left   = -270.0
	_checkout_banner.offset_right  =  270.0
	_checkout_banner.offset_top    =  75.0
	_checkout_banner.custom_minimum_size = Vector2(540, 52)

	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.08, 0.45, 0.15, 0.95)
	s.border_color = Color(0.35, 1.0, 0.45, 1.0)
	s.set_border_width_all(3)
	s.corner_radius_top_left    = 14
	s.corner_radius_top_right   = 14
	s.corner_radius_bottom_left = 14
	s.corner_radius_bottom_right= 14
	s.set_content_margin_all(10)
	_checkout_banner.add_theme_stylebox_override("panel", s)
	_checkout_banner.visible = false
	add_child(_checkout_banner)

	_checkout_label = Label.new()
	_checkout_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_checkout_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_checkout_label.add_theme_font_size_override("font_size", 20)
	_checkout_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.2))
	_checkout_label.text = "🎉 ALL ITEMS COLLECTED! HEAD TO CHECKOUT! 🛒"
	_checkout_banner.add_child(_checkout_label)

func _on_checkout_ready() -> void:
	if not _game_ended:
		_checkout_banner.visible = true

func _process_checkout_banner(_delta: float) -> void:
	if _checkout_banner.visible and not _game_ended:
		# Glowing banner pulse
		var pulse: float = 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.008)
		_checkout_banner.modulate = Color(1.0, 1.0, 1.0, pulse)

# ── Stamina UI Meter (Bottom-Center) ──────────────────────
func _build_stamina_bar() -> void:
	_stamina_panel = PanelContainer.new()
	_stamina_panel.anchor_left   = 0.5
	_stamina_panel.anchor_right  = 0.5
	_stamina_panel.anchor_top    = 1.0
	_stamina_panel.anchor_bottom = 1.0
	_stamina_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_stamina_panel.grow_vertical   = Control.GROW_DIRECTION_BEGIN
	_stamina_panel.offset_left   = -160.0
	_stamina_panel.offset_right  =  160.0
	_stamina_panel.offset_top    = -65.0
	_stamina_panel.offset_bottom = -20.0
	_stamina_panel.custom_minimum_size = Vector2(320, 42)

	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.04, 0.05, 0.12, 0.88)
	s.border_color = Color(0.2, 0.65, 0.95, 0.9)
	s.set_border_width_all(2)
	s.corner_radius_top_left    = 10
	s.corner_radius_top_right   = 10
	s.corner_radius_bottom_left = 10
	s.corner_radius_bottom_right= 10
	s.set_content_margin_all(8)
	_stamina_panel.add_theme_stylebox_override("panel", s)
	_stamina_panel.modulate.a = 0.0 # Initially faded out when 100%
	add_child(_stamina_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_stamina_panel.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title := Label.new()
	title.text = "⚡ STAMINA"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	header.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	_stamina_label = Label.new()
	_stamina_label.text = "100%"
	_stamina_label.add_theme_font_size_override("font_size", 12)
	_stamina_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	header.add_child(_stamina_label)

	var bar_container := Control.new()
	bar_container.custom_minimum_size = Vector2(0, 14)
	vbox.add_child(bar_container)

	_stamina_bar = ProgressBar.new()
	_stamina_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stamina_bar.show_percentage = false
	_stamina_bar.min_value = 0.0
	_stamina_bar.max_value = 100.0
	_stamina_bar.value     = 100.0

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.12, 0.14, 0.22, 1.0)
	bg_style.corner_radius_top_left    = 5
	bg_style.corner_radius_top_right   = 5
	bg_style.corner_radius_bottom_left = 5
	bg_style.corner_radius_bottom_right= 5
	_stamina_bar.add_theme_stylebox_override("background", bg_style)

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.18, 0.80, 0.95, 1.0)
	fill_style.corner_radius_top_left    = 5
	fill_style.corner_radius_top_right   = 5
	fill_style.corner_radius_bottom_left = 5
	fill_style.corner_radius_bottom_right= 5
	_stamina_bar.add_theme_stylebox_override("fill", fill_style)
	bar_container.add_child(_stamina_bar)

	# 25% Sprint Recharge Gate Line
	_stamina_gate_line = ColorRect.new()
	_stamina_gate_line.color = Color(1.0, 0.85, 0.2, 0.85) # Gold notch
	_stamina_gate_line.anchor_left   = 0.25
	_stamina_gate_line.anchor_right  = 0.25
	_stamina_gate_line.anchor_top    = 0.0
	_stamina_gate_line.anchor_bottom = 1.0
	_stamina_gate_line.offset_left   = -1.0
	_stamina_gate_line.offset_right  =  1.0
	bar_container.add_child(_stamina_gate_line)

	# 33.33% Danger Zone Threshold Line
	var danger_line := ColorRect.new()
	danger_line.color = Color(1.0, 0.45, 0.15, 0.85) # Orange notch
	danger_line.anchor_left   = 0.3333
	danger_line.anchor_right  = 0.3333
	danger_line.anchor_top    = 0.0
	danger_line.anchor_bottom = 1.0
	danger_line.offset_left   = -1.0
	danger_line.offset_right  =  1.0
	bar_container.add_child(danger_line)

func _process_stamina_ui(delta: float) -> void:
	if _game_ended:
		_stamina_panel.modulate.a = move_toward(_stamina_panel.modulate.a, 0.0, 3.0 * delta)
		return

	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return

	var stamina_val = player.get("stamina")
	var can_sprint_val = player.get("can_sprint")
	if stamina_val == null:
		return

	var current_stamina: float = float(stamina_val)
	var can_spr: bool = bool(can_sprint_val) if can_sprint_val != null else true
	var is_fatigued_val: bool = bool(player.get("is_fatigued")) if player.get("is_fatigued") != null else false

	_stamina_bar.value = current_stamina

	# Dynamic visual fade: smoothly fade to 1.0 when stamina < 100.0, fade to 0.0 when 100.0
	var target_alpha: float = 1.0 if (current_stamina < 99.5 or is_fatigued_val) else 0.0
	_stamina_panel.modulate.a = move_toward(_stamina_panel.modulate.a, target_alpha, 3.0 * delta)

	# Style and text coloring based on 25% recharge gate state and 33.33% Danger Zone
	if not can_spr:
		# Lockout state (recharging up to 25%)
		var pulse: float = 0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.015)
		_stamina_label.text = "EXHAUSTED! (RECHARGING: %d%% / 25%%)" % int(current_stamina)
		_stamina_label.add_theme_color_override("font_color", Color(1.0, 0.3 * pulse, 0.3 * pulse))
		_stamina_bar.modulate = Color(1.0, 0.3, 0.3)
	elif current_stamina < 33.33:
		# Danger zone (< 33.33%)
		_stamina_label.text = "%d%% [DANGER ZONE]" % int(current_stamina)
		_stamina_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.15))
		_stamina_bar.modulate = Color(1.0, 0.55, 0.15)
	elif current_stamina < 70.0:
		_stamina_label.text = "%d%%" % int(current_stamina)
		_stamina_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		_stamina_bar.modulate = Color(1.0, 0.85, 0.2)
	else:
		_stamina_label.text = "%d%%" % int(current_stamina)
		_stamina_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
		_stamina_bar.modulate = Color(0.18, 0.85, 0.95)

# ── Win / Lose result overlay (centre)  ──────────────────
func _build_result_overlay() -> void:
	_result_root = Control.new()
	_result_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_root.visible = false
	add_child(_result_root)

	# Dark backdrop
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0, 0.65)
	_result_root.add_child(bg)

	# Centre card
	var card := PanelContainer.new()
	card.anchor_left   = 0.5
	card.anchor_right  = 0.5
	card.anchor_top    = 0.5
	card.anchor_bottom = 0.5
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical   = Control.GROW_DIRECTION_BOTH
	card.custom_minimum_size = Vector2(500, 300)
	card.offset_left   = -250.0
	card.offset_right  =  250.0
	card.offset_top    = -150.0
	card.offset_bottom =  150.0

	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.07, 0.06, 0.18, 0.97)
	cs.border_color = Color(0.75, 0.38, 0.10, 1.0)
	cs.set_border_width_all(3)
	cs.corner_radius_top_left    = 18
	cs.corner_radius_top_right   = 18
	cs.corner_radius_bottom_left = 18
	cs.corner_radius_bottom_right= 18
	cs.set_content_margin_all(40)
	card.add_theme_stylebox_override("panel", cs)
	_result_root.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	card.add_child(vbox)

	_result_title = Label.new()
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_title.add_theme_font_size_override("font_size", 40)
	vbox.add_child(_result_title)

	_result_sub = Label.new()
	_result_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_sub.add_theme_font_size_override("font_size", 16)
	_result_sub.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
	_result_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_result_sub)

	_restart_btn = Button.new()
	_restart_btn.text = "  Play Again  "
	_restart_btn.custom_minimum_size = Vector2(200, 52)
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.85, 0.38, 0.08)
	bs.corner_radius_top_left    = 26
	bs.corner_radius_top_right   = 26
	bs.corner_radius_bottom_left = 26
	bs.corner_radius_bottom_right= 26
	bs.set_content_margin_all(14)
	_restart_btn.add_theme_stylebox_override("normal", bs)
	_restart_btn.add_theme_stylebox_override("hover",  bs.duplicate())
	_restart_btn.add_theme_font_size_override("font_size", 20)
	_restart_btn.add_theme_color_override("font_color", Color(1, 1, 1))
	_restart_btn.pressed.connect(_on_restart)
	vbox.add_child(_restart_btn)

# ── Signal handlers ───────────────────────────────────────
func _refresh_list() -> void:
	var gm: Node = get_node_or_null("/root/GameModeManager")
	if not gm:
		return
	var lines: Array = gm.get_progress_lines()
	_list_label.text = "\n".join(lines)

func _on_game_won() -> void:
	_game_ended = true
	_update_timer()
	var secs: int = int(ceil(max(0.0, _time_left)))
	_result_title.text = "🎉  MISSION COMPLETE!"
	_result_title.add_theme_color_override("font_color", Color(0.25, 1.0, 0.35))
	_result_sub.text   = "You found everything on your list — great shopper!\n\nTime remaining: %ds" % secs
	_result_root.visible = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_game_lost() -> void:
	_game_ended = true
	_time_left = 0.0
	_update_timer()
	_result_title.text = "⏰  TIME'S UP!"
	_result_title.add_theme_color_override("font_color", Color(1.0, 0.32, 0.22))
	_result_sub.text   = "You didn't finish your shopping in time.\nWatch out for those pesky shoppers blocking you!"
	_result_root.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_restart() -> void:
	get_tree().paused = false
	var gm: Node = get_node_or_null("/root/GameModeManager")
	if gm and gm.has_method("_reset_list"):
		gm._reset_list()
	get_tree().reload_current_scene()
