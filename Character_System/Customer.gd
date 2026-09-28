extends RigidBody3D

# ──────────────────────────────────────────────────────────
#  Customer NPC  –  randomly wanders INSIDE the market.
#  Acts as a physics obstacle the player must avoid.
# ──────────────────────────────────────────────────────────

@onready var mesh_container = $Meshes

# ── Movement ─────────────────────────────────────────────
const WALK_SPEED : float = 2.5
const TURN_SPEED : float = 5.0
const CENTRE     : Vector3 = Vector3(-17.0, 0.0, -25.0)

# Tight bounds that keep NPCs inside the market floor
# (based on the wall CSG structure + asset layout)
const BOUNDS_MIN : Vector3 = Vector3(-38.0, -2.0, -46.0)
const BOUNDS_MAX : Vector3 = Vector3( 4.0,  -2.0,  -4.0)

var _move_dir  : Vector3 = Vector3.ZERO
var _dir_timer : float   = 0.0

@export var is_vip: bool = false
var _vip_label: Label3D = null

func _ready() -> void:
	randomize()

	# 20% chance to be a VIP customer if not explicitly configured
	if not is_vip and randf() < 0.20:
		is_vip = true

	if is_vip:
		add_to_group("vip_customer")
		_create_vip_visuals()

	# Pick and show a random character model
	var all_chars: Array = mesh_container.get_children()
	for c in all_chars:
		c.hide()

	var chosen: Node = all_chars[randi() % all_chars.size()]
	chosen.show()

	var anim: AnimationPlayer = chosen.get_node_or_null("AnimationPlayer")
	if anim:
		var anim_val = anim.get_animation("Rig_Medium_MovementBasic/Walking_A")
		if anim_val:
			anim_val.loop_mode = Animation.LOOP_LINEAR
		anim.play("Rig_Medium_MovementBasic/Walking_A")

	# Physically drop the visual skeletal meshes to perfectly match the floor tile
	mesh_container.position.y -= 0.25

	# Stay upright
	axis_lock_angular_x = true
	axis_lock_angular_z = true

	add_to_group("npc")
	_pick_new_direction()

func _create_vip_visuals() -> void:
	_vip_label = Label3D.new()
	_vip_label.text = "👑 VIP Shopper"
	_vip_label.font_size = 28
	_vip_label.modulate = Color(1.0, 0.85, 0.1)
	_vip_label.outline_modulate = Color(0.1, 0.05, 0.0, 1.0)
	_vip_label.outline_size = 6
	_vip_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_vip_label.position = Vector3(0, 2.5, 0)
	add_child(_vip_label)

	var vip_light = OmniLight3D.new()
	vip_light.light_color = Color(1.0, 0.85, 0.2)
	vip_light.light_energy = 0.8
	vip_light.omni_range = 2.5
	vip_light.position = Vector3(0, 2.2, 0)
	add_child(vip_light)

func _physics_process(delta: float) -> void:
	if not is_inside_tree(): return
	_dir_timer -= delta
	if _dir_timer <= 0.0:
		_pick_new_direction()

	# Steer back toward centre when approaching a wall
	var pos: Vector3 = global_position
	var near_wall: bool = (
		pos.x < BOUNDS_MIN.x + 2.0 or pos.x > BOUNDS_MAX.x - 2.0 or
		pos.z < BOUNDS_MIN.z + 2.0 or pos.z > BOUNDS_MAX.z - 2.0
	)
	if near_wall:
		_move_dir  = (CENTRE - pos).normalized()
		_dir_timer = randf_range(1.5, 3.0)

	# Apply horizontal walk velocity; preserve gravity (vertical)
	linear_velocity = Vector3(
		_move_dir.x * WALK_SPEED,
		linear_velocity.y,
		_move_dir.z * WALK_SPEED
	)

	# Rotate to face movement direction smoothly
	if _move_dir.length_squared() > 0.01:
		var target_y: float = atan2(_move_dir.x, _move_dir.z)
		rotation.y = lerp_angle(rotation.y, target_y, TURN_SPEED * delta)

func _pick_new_direction() -> void:
	_dir_timer = randf_range(2.5, 6.0)
	var angle: float = randf_range(0.0, TAU)
	_move_dir = Vector3(cos(angle), 0.0, sin(angle))
