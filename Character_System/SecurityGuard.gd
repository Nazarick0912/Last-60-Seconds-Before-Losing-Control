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

const PATROL_SPEED: float = 2.8
const CHASE_SPEED: float = 7.6
const TURN_SPEED: float = 9.0

const BOUNDS_MIN: Vector3 = Vector3(-35.0, 0.0, -43.0)
const BOUNDS_MAX: Vector3 = Vector3(1.0, 0.0, -6.0)

var current_state: State = State.PATROL
var target_player: CharacterBody3D = null
var patrol_target: Vector3 = Vector3.ZERO
var patrol_timer: float = 0.0
var chase_timeout: float = 20.0
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
	# Gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

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

	# Flashing red/blue siren effect
	_siren_phase += delta * 14.0
	if siren_light:
		siren_light.light_energy = 1.8 + sin(_siren_phase) * 1.2
		siren_light.light_color = Color(1.0, 0.1, 0.1, 1.0) if sin(_siren_phase) > 0.0 else Color(0.1, 0.3, 1.0, 1.0)

	var to_player = (target_player.global_position - global_position)
	to_player.y = 0.0
	var dist = to_player.length()

	# Catch player or player's cart check (scaled for larger body)
	var caught: bool = (dist < 3.2)
	if not caught and target_player.attached_cart != null and is_instance_valid(target_player.attached_cart):
		var cart_dist = global_position.distance_to(target_player.attached_cart.global_position)
		if cart_dist < 3.0:
			caught = true

	if caught:
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

		# 3. Play angry grunt / catch SFX
		var sfx = AudioStreamPlayer.new()
		sfx.stream = load("res://Assets 1/KayKit_Prototype_Bits_1.1_FREE/Music/Hey watch it.ogg")
		sfx.bus = &"Voice"
		sfx.pitch_scale = 0.85 # Deeper, furious voice
		get_tree().root.add_child(sfx)
		sfx.play()
		sfx.finished.connect(sfx.queue_free)

	# Transition to cooldown
	current_state = State.COOLDOWN
	cooldown_timer = 8.0
	_update_visual_state()
	_pick_new_patrol_point()

func trigger_aggro(_source_pos: Vector3 = Vector3.ZERO) -> void:
	if current_state == State.COOLDOWN:
		return # Still in cooldown grace period

	current_state = State.CHASE
	chase_timeout = 20.0
	_update_visual_state()

	# If the manager is far across the market (> 18m), position him in an adjacent aisle spot
	# ~10-12m from the player so the player immediately SEES the angry manager charging!
	if target_player == null or not is_instance_valid(target_player):
		target_player = get_tree().get_first_node_in_group("player") as CharacterBody3D

	if target_player and is_instance_valid(target_player):
		var d = global_position.distance_to(target_player.global_position)
		if d > 16.0:
			var angle = randf_range(0.0, TAU)
			var offset = Vector3(cos(angle) * 11.0, 0.1, sin(angle) * 11.0)
			var spawn_pos = target_player.global_position + offset
			spawn_pos.x = clamp(spawn_pos.x, BOUNDS_MIN.x + 2.0, BOUNDS_MAX.x - 2.0)
			spawn_pos.z = clamp(spawn_pos.z, BOUNDS_MIN.z + 2.0, BOUNDS_MAX.z - 2.0)
			spawn_pos.y = 0.1
			global_position = spawn_pos
			velocity = Vector3.ZERO

	# Play alert whistle / notice SFX
	var sfx = AudioStreamPlayer.new()
	sfx.stream = load("res://Assets 1/KayKit_Prototype_Bits_1.1_FREE/Music/DingDong.ogg")
	sfx.bus = &"SFX"
	sfx.pitch_scale = 1.3
	get_tree().root.add_child(sfx)
	sfx.play()
	sfx.finished.connect(sfx.queue_free)

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
				overhead_label.modulate = Color(0.3, 0.8, 1.0, 1.0)
			State.CHASE:
				overhead_label.text = "🚨 ANGRY MANAGER! ‼️"
				overhead_label.modulate = Color(1.0, 0.1, 0.1, 1.0)
			State.COOLDOWN:
				overhead_label.text = "👮 Cooling Down..."
				overhead_label.modulate = Color(0.8, 0.8, 0.8, 1.0)

	if siren_light:
		match current_state:
			State.PATROL:
				siren_light.light_color = Color(0.2, 0.6, 1.0, 1.0)
				siren_light.light_energy = 0.6
			State.CHASE:
				siren_light.light_energy = 2.2
			State.COOLDOWN:
				siren_light.light_energy = 0.2

func _pick_new_patrol_point() -> void:
	patrol_timer = randf_range(3.5, 7.0)
	patrol_target = Vector3(
		randf_range(BOUNDS_MIN.x, BOUNDS_MAX.x),
		0.0,
		randf_range(BOUNDS_MIN.z, BOUNDS_MAX.z)
	)
