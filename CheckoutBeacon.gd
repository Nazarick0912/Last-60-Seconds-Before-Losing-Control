extends Area3D

# ──────────────────────────────────────────────────────────
#  CheckoutBeacon – Semi-transparent glowing red light bar
#  Activates when all grocery items are collected.
#  Triggers win when player with attached cart enters.
# ──────────────────────────────────────────────────────────

@onready var col_shape: CollisionShape3D = $CollisionShape3D
@onready var beam_mesh: MeshInstance3D = $BeamMesh
@onready var beacon_label: Label3D = $Label3D

var _mat: StandardMaterial3D
var _pulse_time: float = 0.0

func _ready() -> void:
	# Initially inactive and invisible until list is complete
	visible = false
	monitoring = false
	monitorable = false
	
	body_entered.connect(_on_body_entered)
	
	# Setup material for the vertical red light bar
	if beam_mesh:
		_mat = StandardMaterial3D.new()
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.albedo_color = Color(1.0, 0.15, 0.15, 0.42)
		_mat.emission_enabled = true
		_mat.emission = Color(1.0, 0.2, 0.2)
		_mat.emission_energy_multiplier = 3.5
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		beam_mesh.material_override = _mat
		
	var gm := get_node_or_null("/root/GameModeManager")
	if gm:
		if gm.has_signal("checkout_ready"):
			gm.checkout_ready.connect(activate_beacon)
		if gm.list_complete:
			activate_beacon()

func activate_beacon() -> void:
	visible = true
	monitoring = true
	monitorable = true

func _process(delta: float) -> void:
	if not visible:
		return
		
	_pulse_time += delta
	# Continuous rotation of the vertical light cylinder
	if beam_mesh:
		beam_mesh.rotate_y(delta * 0.8)
		
	# Pulsing glow animation
	if _mat:
		var pulse: float = 0.85 + 0.15 * sin(_pulse_time * 4.0)
		_mat.emission_energy_multiplier = 3.0 * pulse
		_mat.albedo_color.a = 0.38 + 0.12 * pulse
		
	if beacon_label:
		beacon_label.position.y = 4.0 + sin(_pulse_time * 2.5) * 0.15

func _on_body_entered(body: Node3D) -> void:
	if not visible:
		return
	if body is CharacterBody3D:
		var gm := get_node_or_null("/root/GameModeManager")
		if not gm or not gm.list_complete or gm._game_ended:
			return
			
		if body.attached_cart != null:
			# Player entered with attached cart: WIN!
			gm.trigger_win()
		else:
			# Warn player they need their cart
			var hud := get_tree().root.find_child("ShoppingHUD", true, false)
			if hud and hud.has_method("show_warning"):
				hud.show_warning("🛒 Bring your cart to checkout to win!")
			elif gm and gm.has_signal("warning_triggered"):
				gm.emit_signal("warning_triggered", "🛒 Bring your cart to checkout to win!")
