extends Area3D

# ──────────────────────────────────────────────────────────
#  PowerUpItem – Arcade Ground-Contact Pickup
#  Collected immediately upon walking over it (no cart needed).
#  Types:
#   • "coffee": 100% Stamina Refill + 5s Unlimited Sprint Boost
#   • "clock": +10s Time Extension on Countdown Timer
# ──────────────────────────────────────────────────────────

@export_enum("coffee", "clock") var powerup_type: String = "coffee"

var _bob_time: float = 0.0
var _base_y: float = 0.0
var _collected: bool = false

@onready var visual_root: Node3D = $Visuals
@onready var aura_light: OmniLight3D = $AuraLight
@onready var label: Label3D = $Label3D
@onready var sparkle_particles: CPUParticles3D = $SparkleParticles

func _ready() -> void:
	add_to_group("powerup_item")
	_base_y = global_position.y
	body_entered.connect(_on_body_entered)
	_setup_visuals()

func _setup_visuals() -> void:
	if powerup_type == "coffee":
		if label:
			label.text = "☕ SPEED COFFEE"
			label.modulate = Color(1.0, 0.75, 0.2)
		if aura_light:
			aura_light.light_color = Color(1.0, 0.65, 0.15)
			aura_light.light_energy = 1.2
	else:
		if label:
			label.text = "⏱️ +10s TIME EXTENSION"
			label.modulate = Color(0.2, 0.85, 1.0)
		if aura_light:
			aura_light.light_color = Color(0.2, 0.8, 1.0)
			aura_light.light_energy = 1.2

func _process(delta: float) -> void:
	if _collected:
		return

	_bob_time += delta
	if visual_root:
		visual_root.position.y = sin(_bob_time * 2.8) * 0.12
		visual_root.rotation.y += delta * 2.5
	if label:
		label.position.y = 1.2 + sin(_bob_time * 2.8) * 0.12

func _on_body_entered(body: Node3D) -> void:
	if _collected:
		return

	var player = null
	if body.is_in_group("player"):
		player = body
	elif body.get("player_owner") != null:
		player = body.player_owner

	if player and is_instance_valid(player):
		_do_collect(player)

func _do_collect(player: CharacterBody3D) -> void:
	_collected = true
	set_deferred("monitoring", false)

	# Play chime sound
	var sfx = AudioStreamPlayer.new()
	sfx.bus = &"SFX"
	sfx.stream = load("res://Assets 1/KayKit_Prototype_Bits_1.1_FREE/Music/Chaching.ogg")
	sfx.pitch_scale = 1.2 if powerup_type == "coffee" else 1.4
	get_tree().root.add_child(sfx)
	sfx.play()
	sfx.finished.connect(sfx.queue_free)

	# Apply effect to player
	if powerup_type == "coffee":
		if player.has_method("apply_coffee_boost"):
			player.apply_coffee_boost()
		var hud = get_tree().root.find_child("ShoppingHUD", true, false)
		if hud and hud.has_method("show_warning"):
			hud.show_warning("☕ CAFFEINE RUSH! Unlimited Sprint & Speed Boost for 5s!")
	elif powerup_type == "clock":
		if player.has_method("apply_clock_boost"):
			player.apply_clock_boost(10.0)
		var hud = get_tree().root.find_child("ShoppingHUD", true, false)
		if hud:
			if "_time_left" in hud:
				hud._time_left += 10.0
			if hud.has_method("show_warning"):
				hud.show_warning("⏱️ TIME EXTENSION! +10 Seconds Added to Clock!")

	if sparkle_particles:
		sparkle_particles.emitting = true
		visual_root.hide()
		label.hide()
		await get_tree().create_timer(0.6).timeout

	queue_free()
