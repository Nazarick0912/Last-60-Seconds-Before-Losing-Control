extends Area3D

# ──────────────────────────────────────────────────────────
#  HazardPuddle – Spilled Milk / Wet Floor Hazard
#  Forces a 360° spin-out on the player with temporary loss
#  of steering control. Upon contact, splashes and changes
#  location to another supermarket aisle.
# ──────────────────────────────────────────────────────────

const BOUNDS_MIN: Vector3 = Vector3(-35.0, 0.02, -43.0)
const BOUNDS_MAX: Vector3 = Vector3(1.0, 0.02, -6.0)

@onready var splash_particles: CPUParticles3D = $SplashParticles
@onready var puddle_mesh: MeshInstance3D = $PuddleMesh
@onready var sign_node: Node3D = $CautionSign

var _is_relocating: bool = false

func _ready() -> void:
	add_to_group("hazard_puddle")
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if _is_relocating:
		return

	var player = null
	if body.is_in_group("player"):
		player = body
	elif body.get("player_owner") != null:
		player = body.player_owner
	elif body.name.to_lower().find("cart") != -1 or body.name.to_lower().find("player") != -1:
		player = get_tree().get_first_node_in_group("player")

	if player and is_instance_valid(player) and player.has_method("trigger_spin_out"):
		if player.get("is_spinning") == true:
			return # Already spinning out

		_is_relocating = true
		player.trigger_spin_out()

		# Trigger splash burst
		if splash_particles:
			splash_particles.emitting = true

		# Play puddle splash SFX
		var sfx = AudioStreamPlayer.new()
		sfx.stream = load("res://Assets 1/KayKit_Prototype_Bits_1.1_FREE/Music/Ouch.ogg")
		sfx.bus = &"SFX"
		sfx.pitch_scale = randf_range(1.3, 1.6)
		add_child(sfx)
		sfx.play()

		# Relocate to a new random location inside the supermarket
		var tween = create_tween()
		tween.tween_property(puddle_mesh, "scale", Vector3.ZERO, 0.25)
		if sign_node:
			tween.parallel().tween_property(sign_node, "scale", Vector3.ZERO, 0.25)
		tween.tween_callback(self._relocate_to_new_spot)

func _relocate_to_new_spot() -> void:
	var new_x = randf_range(BOUNDS_MIN.x, BOUNDS_MAX.x)
	var new_z = randf_range(BOUNDS_MIN.z, BOUNDS_MAX.z)
	global_position = Vector3(new_x, 0.02, new_z)

	# Ripple / pop-in animation at the new spot
	puddle_mesh.scale = Vector3.ZERO
	if sign_node:
		sign_node.scale = Vector3.ZERO

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(puddle_mesh, "scale", Vector3(1.0, 1.0, 1.0), 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if sign_node:
		tween.tween_property(sign_node, "scale", Vector3(1.0, 1.0, 1.0), 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(func(): _is_relocating = false)
