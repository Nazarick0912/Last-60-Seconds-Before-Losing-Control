extends CharacterBody3D

# ──────────────────────────────────────────────────────────
#  SecurityGuard / Angry Manager
#  Patrols supermarket. Aggros when player hits 5 customers
#  or hits a VIP customer.
#  Consequence on catch:
#   1. Stuns player for 1.0 second.
#   2. Randomly scatters 1-2 collected items out of the cart
#      across the aisle floor!
# ──────────────────────────────────────────────────────────

enum State { PATROL, CHASE, COOLDOWN }

const PATROL_SPEED: float = 2.4
const CHASE_SPEED: float = 7.2
const TURN_SPEED: float = 8.0

const BOUNDS_MIN: Vector3 = Vector3(-35.0, 0.0, -43.0)
const BOUNDS_MAX: Vector3 = Vector3(1.0, 0.0, -6.0)

var current_state: State = State.PATROL
var target_player: CharacterBody3D = null
var patrol_target: Vector3 = Vector3.ZERO
var patrol_timer: float = 0.0
var chase_timeout: float = 16.0
var cooldown_timer: float = 0.0

@onready var overhead_label: Label3D = $OverheadLabel
@onready var siren_light: OmniLight3D = $SirenLight
@onready var anim_player: AnimationPlayer = get_node_or_null("Model/AnimationPlayer")

var _siren_phase: float = 0.0

func _ready() -> void:
	add_to_group("security_guard")
	_pick_new_patrol_point()
	_update_visual_state()

func _physics_process(delta: float) -> void:
	# Find player if not cached
	if target_player == null or not is_instance_valid(target_player):
		target_player = get_tree().get_first_node_in_group("player") as CharacterBody3D

	match current_state:
		State.PATROL:
			_process_patrol(delta)
		State.CHASE:
			_process_chase(delta)
		State.COOLDOWN:
			_process_cooldown(delta)

	move_and_slide()

func _process_patrol(delta: float) -> void:
	patrol_timer -= delta
	if patrol_timer <= 0.0 or global_position.distance_to(patrol_target) < 1.0:
		_pick_new_patrol_point()

	var move_dir = (patrol_target - global_position)
	move_dir.y = 0.0
	if move_dir.length_squared() > 0.01:
		move_dir = move_dir.normalized()
		velocity.x = move_dir.x * PATROL_SPEED
		velocity.z = move_dir.z * PATROL_SPEED
		rotation.y = lerp_angle(rotation.y, atan2(move_dir.x, move_dir.z), TURN_SPEED * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 4.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 4.0 * delta)

	if anim_player and anim_player.has_animation("Rig_Medium_MovementBasic/Walking_A"):
		if anim_player.current_animation != "Rig_Medium_MovementBasic/Walking_A":
			anim_player.play("Rig_Medium_MovementBasic/Walking_A")
		anim_player.speed_scale = 1.0

func _process_chase(delta: float) -> void:
	chase_timeout -= delta
	if chase_timeout <= 0.0 or target_player == null:
		_end_chase()
		return

	# Flashing red siren effect
	_siren_phase += delta * 12.0
	if siren_light:
		siren_light.light_energy = 1.5 + sin(_siren_phase) * 1.2
		siren_light.light_color = Color(1.0, 0.1, 0.1) if sin(_siren_phase) > 0.0 else Color(0.1, 0.3, 1.0)

	var to_player = (target_player.global_position - global_position)
	to_player.y = 0.0
	var dist = to_player.length()

	# Catch player check!
	if dist < 1.8:
		_catch_player()
		return

	# Sprint toward player
	var chase_dir = to_player.normalized()
	velocity.x = chase_dir.x * CHASE_SPEED
	velocity.z = chase_dir.z * CHASE_SPEED
	rotation.y = lerp_angle(rotation.y, atan2(chase_dir.x, chase_dir.z), TURN_SPEED * 1.5 * delta)

	if anim_player and anim_player.has_animation("Rig_Medium_MovementBasic/Running_A"):
		if anim_player.current_animation != "Rig_Medium_MovementBasic/Running_A":
			anim_player.play("Rig_Medium_MovementBasic/Running_A")
		anim_player.speed_scale = 1.3

func _process_cooldown(delta: float) -> void:
	cooldown_timer -= delta
	if cooldown_timer <= 0.0:
		current_state = State.PATROL
		_update_visual_state()
		return

	# Walk slowly away during cooldown
	_process_patrol(delta)

func _catch_player() -> void:
	if target_player and is_instance_valid(target_player):
		# 1. Stun player for 1.0 second
		if target_player.has_method("trigger_stun"):
			target_player.trigger_stun(1.0)

		# 2. Scatter groceries out of the cart across aisle floor
		if target_player.has_method("scatter_cart_items"):
			target_player.scatter_cart_items()

		# 3. Audio & HUD feedback
		var gm = get_node_or_null("/root/GameModeManager")
		if gm and gm.has_signal("warning_triggered"):
			gm.emit_signal("warning_triggered", "💥 BUSTED! The Manager stunned you & scattered your groceries!")

	# Transition to cooldown
	current_state = State.COOLDOWN
	cooldown_timer = 8.0
	_update_visual_state()
	_pick_new_patrol_point()

func trigger_aggro(source_pos: Vector3 = Vector3.ZERO) -> void:
	if current_state == State.COOLDOWN:
		return # Still in cooldown grace period

	current_state = State.CHASE
	chase_timeout = 16.0
	_update_visual_state()

	var hud = get_tree().root.find_child("ShoppingHUD", true, false)
	if hud and hud.has_method("show_warning"):
		hud.show_warning("🚨 ANGRY MANAGER IS CHASING YOU! RUN!")

func _end_chase() -> void:
	current_state = State.COOLDOWN
	cooldown_timer = 5.0
	_update_visual_state()
	_pick_new_patrol_point()

func _update_visual_state() -> void:
	if overhead_label:
		match current_state:
			State.PATROL:
				overhead_label.text = "👮 Security Guard"
				overhead_label.modulate = Color(0.3, 0.8, 1.0)
			State.CHASE:
				overhead_label.text = "🚨 ANGRY MANAGER! ‼️"
				overhead_label.modulate = Color(1.0, 0.1, 0.1)
			State.COOLDOWN:
				overhead_label.text = "👮 Cooling Down..."
				overhead_label.modulate = Color(0.8, 0.8, 0.8)

	if siren_light:
		match current_state:
			State.PATROL:
				siren_light.light_color = Color(0.2, 0.6, 1.0)
				siren_light.light_energy = 0.5
			State.CHASE:
				siren_light.light_energy = 2.0
			State.COOLDOWN:
				siren_light.light_energy = 0.2

func _pick_new_patrol_point() -> void:
	patrol_timer = randf_range(3.5, 7.0)
	patrol_target = Vector3(
		randf_range(BOUNDS_MIN.x, BOUNDS_MAX.x),
		0.0,
		randf_range(BOUNDS_MIN.z, BOUNDS_MAX.z)
	)
