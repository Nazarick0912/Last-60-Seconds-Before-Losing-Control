extends CharacterBody3D

# --- Physical Constants ---
@export var SPEED = 5.0
@export var SPRINT_SPEED = 8.5
@export var JUMP_VELOCITY = 6.5
@export var TURN_SPEED = 12.0
@export var MOUSE_SENSITIVITY = 0.001

# Double-tap to sprint variables
var last_press_times = {
	"ui_up": 0.0,
	"ui_down": 0.0,
	"ui_left": 0.0,
	"ui_right": 0.0
}
var is_sprinting = false
const DOUBLE_TAP_TIME = 0.3 # seconds
var is_sliding = false
var slide_timer = 0.0
var target_zoom = 4.0 # Initial camera distance

# Fatigue mechanic variables
var push_time = 0.0
var fatigue_timer = 0.0
var is_fatigued = false
var _npc_collision_cooldown = 0.0

var game_started = false
var start_carpet = null

# --- Zoom Constants ---
@export var ZOOM_SPEED = 0.5
@export var MIN_ZOOM = 1.5
@export var MAX_ZOOM = 6.0

# --- Timer & Sway Settings ---
@export var TOTAL_TIME = 60.0
var play_time_passed: float = 0.0
var sway_phase: float = 0.0
var _hey_played: bool = false

# --- Camera Sway & Escalation Settings ---
@export_group("Camera Sway & Escalation")
@export var BASE_SWAY_SPEED: float = 1.5       # Starting oscillation speed (rad/s)
@export var MAX_SWAY_SPEED: float = 3.5        # Final frantic oscillation speed (rad/s)
@export var MAX_CAMERA_SWAY: float = 25.0      # Maximum horizontal yaw sway in degrees
@export var MAX_CAMERA_ROLL: float = 12.0      # Maximum lateral roll tilt in degrees

# --- Camera-Aligned Sliding Drift & Load Inertia Settings ---
@export_group("Tilt & Load Inertia")
@export var BASE_TILT_MAGNITUDE: float = 14.0  # Base acceleration constant for tilt pull (m/s^2)
@export var KNIGHT_BASE_MASS: float = 1.0      # Mass multiplier on foot (without cart)
@export var CART_EMPTY_MASS: float = 1.5       # Base mass multiplier when pushing empty cart
@export var MASS_PER_ITEM: float = 0.25        # Additional mass multiplier per grocery item collected
@export var BASE_FRICTION: float = 6.0         # Unified low-friction deceleration (m/s^2)
@export var MAX_OPPOSING_DRIFT_RATIO: float = 0.75 # Maximum fraction of player speed that opposing slope drift can counteract

var drift_velocity: Vector3 = Vector3.ZERO     # Accumulated lateral slope drift velocity

var move_sfx_player: AudioStreamPlayer
var attached_cart: RigidBody3D = null
var _orig_parent: Node = null

# --- Node References ---
@onready var visual_model = $Knight
@onready var anim_player = $Knight/AnimationPlayer
@onready var pivot = $CameraPivot 
@onready var camera = $CameraPivot/Camera3D 
@onready var timer_text_edit = get_node_or_null("%TimerText")

var checkout_zones = []

func _ready():
	add_to_group("player")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Find checkout carpets automatically
	_find_checkout_zones(get_tree().root)
	
	move_sfx_player = AudioStreamPlayer.new()
	move_sfx_player.stream = load("res://Assets 1/KayKit_Prototype_Bits_1.1_FREE/Music/Hey watch it.ogg")
	add_child(move_sfx_player)

func _find_checkout_zones(node: Node):
	if "carpet_round_large" in node.name.to_lower():
		start_carpet = node
	elif "carpet" in node.name.to_lower() or "checkout" in node.name.to_lower():
		checkout_zones.append(node)
	for child in node.get_children():
		_find_checkout_zones(child)

func _input(event):
	# 1. Look
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		pivot.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		pivot.rotation.x = clamp(pivot.rotation.x, deg_to_rad(-80), deg_to_rad(80))

	# 2. Zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_zoom -= ZOOM_SPEED
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_zoom += ZOOM_SPEED
		target_zoom = clamp(target_zoom, MIN_ZOOM, MAX_ZOOM)

	# 3. Toggle Grab (E key)
	if event is InputEventKey and event.pressed and event.keycode == KEY_E:
		if attached_cart:
			_detach_cart()
		else:
			_try_grab_nearest_cart()

	# 4. Escape to unlock
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# 5. Handle Double-Tap Sprint Detection
	if event is InputEventKey and event.pressed and not event.is_echo():
		for action in ["ui_up", "ui_down", "ui_left", "ui_right"]:
			if event.is_action_pressed(action):
				var current_time = Time.get_ticks_msec() / 1000.0
				if (current_time - last_press_times[action]) < DOUBLE_TAP_TIME:
					is_sprinting = true
				last_press_times[action] = current_time

func _try_grab_nearest_cart():
	# Find the closest cart within 3 meters
	var carts = get_tree().get_nodes_in_group("shopping_cart")
	var closest_cart = null
	var min_dist = 3.5
	
	for cart in carts:
		if cart is RigidBody3D and "shopping-cart" in cart.name.to_lower():
			var dist = global_position.distance_to(cart.global_position)
			if dist < min_dist:
				min_dist = dist
				closest_cart = cart
	
	if closest_cart:
		_attach_cart(closest_cart)

func _attach_cart(cart: RigidBody3D):
	attached_cart = cart
	_orig_parent = attached_cart.get_parent()
	
	if attached_cart.has_method("set_sleeping"):
		attached_cart.sleeping = false
	attached_cart.freeze = true
	
	# Prevent the cart from pushing the player away (physics feedback loop)
	add_collision_exception_with(attached_cart)
	
	# Reparent to the Knight (so it rotates when the Knight turns)
	attached_cart.reparent(visual_model, true)
	
	# Position in front of the Knight
	# Note: Knight model forward might be different, adjusting Z and rotation
	attached_cart.position = Vector3(0, -0.3, 1.1) 
	attached_cart.rotation_degrees = Vector3(0, 0, 0)

func _detach_cart():
	if is_instance_valid(attached_cart):
		# Restore collisions
		remove_collision_exception_with(attached_cart)
		if is_instance_valid(_orig_parent):
			attached_cart.reparent(_orig_parent, true)
		else:
			attached_cart.reparent(get_parent(), true)
		attached_cart.freeze = false
	attached_cart = null

func _get_cart_item_count() -> int:
	var gm = get_node_or_null("/root/GameModeManager")
	if gm == null or not ("shopping_list" in gm):
		return 0
	var count: int = 0
	for key in gm.shopping_list:
		count += gm.shopping_list[key].get("collected", 0)
	return count

func _physics_process(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Movement & Load calculation
	var load_mult: float = KNIGHT_BASE_MASS
	if attached_cart != null:
		var items_count = _get_cart_item_count()
		load_mult = CART_EMPTY_MASS + (float(items_count) * MASS_PER_ITEM)

	var input_dir := Vector2.ZERO
	if not is_sliding and not is_fatigued:
		input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var current_speed = SPRINT_SPEED if is_sprinting else SPEED
	
	if direction and not is_sliding and not is_fatigued:
		var target_vel = direction * current_speed
		
		# Unified smooth acceleration (no rigid ground snapping)
		var accel = 18.0
		velocity.x = move_toward(velocity.x, target_vel.x, accel * delta)
		velocity.z = move_toward(velocity.z, target_vel.z, accel * delta)
		
		# --- Fatigue Exertion ---
		if attached_cart != null and is_sprinting:
			push_time += delta
			if push_time >= 3.5:
				is_fatigued = true
				push_time = 0.0
				fatigue_timer = 0.5
		if is_instance_valid(visual_model):
			var target_angle = atan2(input_dir.x, input_dir.y)
			visual_model.rotation.y = lerp_angle(visual_model.rotation.y, target_angle, TURN_SPEED * delta)
		if is_instance_valid(anim_player) and anim_player.current_animation != "Rig_Medium_MovementBasic/Running_A":
			anim_player.play("Rig_Medium_MovementBasic/Running_A")
	else:
		# Reset push time if we stop moving voluntarily
		if not is_fatigued:
			push_time = 0.0
			
		# Handle fatigue recovery (input locked to 0, but downhill drift continues to pull)
		if is_fatigued:
			fatigue_timer -= delta
			if fatigue_timer <= 0.0:
				is_fatigued = false
				
		# --- Unified Low-Friction Deceleration (Walking & Sprinting) ---
		var friction = BASE_FRICTION # 6.0 m/s^2 matching the loose sprint threshold
		if attached_cart != null:
			friction = max(3.2, BASE_FRICTION / sqrt(load_mult))
		
		# If we were sprinting with a cart, engage sliding state
		if is_sprinting and attached_cart != null:
			is_sliding = true
			
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, friction * delta)
		
		# Reset sprint and slide only when nearly stopped + 0.5s delay
		if velocity.length() < 0.2:
			if is_sliding:
				if slide_timer <= 0.0:
					slide_timer = 0.5 # Begin the 0.5s lock
				else:
					slide_timer -= delta
					if slide_timer <= 0.0:
						is_sprinting = false
						is_sliding = false
						slide_timer = 0.0
			else:
				is_sprinting = false
		
		if is_instance_valid(anim_player) and anim_player.current_animation != "Rig_Medium_MovementBasic/Jump_Idle":
			anim_player.play("Rig_Medium_MovementBasic/Jump_Idle")

	# --- Wavy Floor Effect Update ---
	var floor_container = get_parent().get_node_or_null("FLOOR")
	if is_instance_valid(floor_container) and game_started:
		var raw_prog = clamp(play_time_passed / TOTAL_TIME, 0.0, 1.0)
		var floor_intensity = lerp(0.35, 1.5, raw_prog)
		for f in floor_container.get_children():
			if f is CSGBox3D and f.material_override is ShaderMaterial:
				f.material_override.set_shader_parameter("wave_intensity", floor_intensity)
				f.material_override.set_shader_parameter("time", play_time_passed)

	# --- Drunken Camera Sway & Dynamic Roll (Phase Accumulated & 28% Baseline) ---
	var active_roll_angle: float = 0.0
	if is_instance_valid(camera):
		# 1. Normalized Direct Scalar with 28% Active Baseline
		var raw_progress: float = clamp(play_time_passed / TOTAL_TIME, 0.0, 1.0) if game_started else 0.0
		var escalation_factor: float = lerp(0.28, 1.0, raw_progress) if game_started else 0.0
		
		# 2. Continuous Frequency Acceleration via Phase Accumulation
		var current_sway_speed: float = lerp(BASE_SWAY_SPEED, MAX_SWAY_SPEED, escalation_factor)
		sway_phase += current_sway_speed * delta
		if sway_phase > TAU:
			sway_phase = fmod(sway_phase, TAU)
			
		# 3. Continuous Amplitude & Re-centering Application
		var base_yaw: float = lerp(-25.0, 0.0, raw_progress)
		var current_sway_max: float = MAX_CAMERA_SWAY * escalation_factor
		var current_roll_max: float = MAX_CAMERA_ROLL * escalation_factor
		
		camera.rotation_degrees.y = base_yaw + sin(sway_phase) * current_sway_max
		active_roll_angle = cos(sway_phase) * current_roll_max
		camera.rotation_degrees.z = active_roll_angle

	# --- Camera-Aligned Sliding Drift & Load Inertia ---
	if is_instance_valid(camera) and game_started and active_roll_angle != 0.0:
		# 1. Downhill Vector Derivation (using load_mult calculated above)

		# Extract camera horizontal right vector (flattened on Y = 0 and normalized)
		var cam_basis = camera.global_transform.basis
		var cam_right = Vector3(cam_basis.x.x, 0.0, cam_basis.x.z)
		if cam_right.length_squared() > 0.0001:
			cam_right = cam_right.normalized()
		else:
			cam_right = Vector3.RIGHT
		
		# When roll > 0 (camera rolls clockwise), the right side of the screen dips down.
		# When roll < 0 (camera rolls counter-clockwise), the left side dips down.
		# sin(deg_to_rad(active_roll_angle)) gives the downhill slope ratio toward the lower side
		var slope_ratio: float = sin(deg_to_rad(active_roll_angle))
		var downhill_vector: Vector3 = cam_right * slope_ratio
		
		# 3. Force Injection (Continuous Accumulation)
		# Scale resulting vector by base tilt magnitude, cart load multiplier, and delta
		var tilt_accel: Vector3 = downhill_vector * BASE_TILT_MAGNITUDE * load_mult
		drift_velocity += tilt_accel * delta
		
		# Ground friction damping for drift so it settles predictably
		var drift_friction: float = 4.5
		drift_velocity = drift_velocity.move_toward(Vector3.ZERO, drift_friction * delta)
		
		# 4. Asymmetric Directional Vector Projection & Opposition Clamping
		var effective_drift: Vector3 = drift_velocity
		
		# Check if the player has active directional input
		if direction.length_squared() > 0.0001 and not is_fatigued:
			var d_input: Vector3 = direction.normalized()
			var d_downhill: Vector3 = downhill_vector.normalized() if downhill_vector.length_squared() > 0.0001 else Vector3.ZERO
			var oppose_factor: float = d_input.dot(d_downhill)
			
			# When oppose_factor < 0.0, the player is pushing uphill / against the slope
			if oppose_factor < 0.0 and d_downhill != Vector3.ZERO:
				# Decompose drift_velocity into parallel (along d_input) and perpendicular components
				var parallel_dot: float = drift_velocity.dot(d_input) # Negative value when opposing
				var v_parallel: Vector3 = d_input * parallel_dot
				var v_perp: Vector3 = drift_velocity - v_parallel
				
				# Maximum allowed opposing speed (e.g. 75% of active locomotive speed)
				var max_opposing_speed: float = current_speed * MAX_OPPOSING_DRIFT_RATIO
				
				# Clamp opposing parallel component so player always maintains positive forward headway
				if abs(parallel_dot) > max_opposing_speed:
					v_parallel = -d_input * max_opposing_speed
					
				# Recombine clamped parallel component with untouched lateral/perpendicular drift
				effective_drift = v_parallel + v_perp
			# When oppose_factor >= 0.0 (downhill or parallel): no clamp, full boost retained!
			
		# Add directly to horizontal velocity prior to move_and_slide()
		velocity.x += effective_drift.x
		velocity.z += effective_drift.z
	else:
		# Decay drift when stopped or before game starts
		drift_velocity = drift_velocity.move_toward(Vector3.ZERO, 5.0 * delta)

	# --- Start Game Proximity Trigger ---
	var gm = get_node_or_null("/root/GameModeManager")
	if not game_started:
		if is_instance_valid(start_carpet):
			if global_position.distance_to(start_carpet.global_position) < 3.0:
				game_started = true
				if gm:
					gm.start_game()

	# --- Checkout Zone Proximity Trigger ---
	if gm and gm.list_complete and game_started:
		for zone in checkout_zones:
			if is_instance_valid(zone):
				if global_position.distance_to(zone.global_position) < 3.0:
					gm.do_checkout()

	move_and_slide()
	
	# --- NPC Collision Sound Trigger ---
	_npc_collision_cooldown -= delta
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		if collider and collider.is_in_group("npc") and _npc_collision_cooldown <= 0.0:
			if move_sfx_player:
				move_sfx_player.play()
				_npc_collision_cooldown = 2.0 # 2 second cooldown 

	if game_started:
		play_time_passed += delta
	var time_left = max(TOTAL_TIME - play_time_passed, 0.0)
	# --- Nervous Camera Effect (Last 10 Seconds) ---
	var pulse = 0.0
	if time_left > 0 and time_left <= 30.0 and game_started:
		var nerv_speed = 20.0 # High frequency
		var nerv_amount = 0.6 * (1.0 - (time_left / 30.0)) # Gets stronger as time runs out
		pulse = sin(play_time_passed * nerv_speed) * nerv_amount
	
	if is_instance_valid(camera):
		camera.position.z = target_zoom + pulse

	if timer_text_edit:
		if not game_started:
			timer_text_edit.text = "Step on the large carpet to start!"
		else:
			timer_text_edit.text = "Time Left: " + str(int(ceil(time_left))) + "s"
	if time_left <= 0.0 and game_started:
		handle_game_over()

func handle_game_over():
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var gm := get_node_or_null("/root/GameModeManager")
	if gm:
		gm.notify_time_up()
