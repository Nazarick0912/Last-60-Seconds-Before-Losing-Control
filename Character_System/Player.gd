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
var target_zoom = 4.0 # Initial camera distance

# --- Stamina System & Tiered Recovery Matrix ---
@export_group("Stamina System")
@export var MAX_STAMINA: float = 100.0
const RATE_REST: float = 100.0 / 3.5      # ~28.57 units/sec (1.0x)
const RATE_WALK: float = RATE_REST * 0.5   # ~14.28 units/sec (0.5x)
const SPRINT_DRAIN_RATE: float = 100.0 / 3.5 # ~28.57 units/sec (exhausts in 3.5s)
const DANGER_ZONE_THRESHOLD: float = 33.33   # 1/3 of the gauge
const SPRINT_RECHARGE_GATE: float = 25.0     # 25% minimum gate to sprint again after exhaustion

var stamina: float = 100.0
var can_sprint: bool = true
var is_fatigued: bool = false
var fatigue_timer: float = 0.0
var _npc_collision_cooldown: float = 0.0

var panting_sfx_player: AudioStreamPlayer
var sweat_particles: CPUParticles3D
var overhead_stamina_sprite: Sprite3D
var overhead_stamina_bar: ProgressBar
var overhead_stamina_viewport: SubViewport

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
@export var MAX_DRIFT_SPEED_CAP: float = 3.25   # Hard ceiling on drift velocity (strictly <= 65% of 5.0 m/s walk speed)
@export var KNIGHT_BASE_MASS: float = 1.0      # Mass multiplier on foot (without cart)
@export var CART_EMPTY_MASS: float = 1.4       # Base mass multiplier when pushing empty cart
@export var MASS_PER_ITEM: float = 0.20        # Additional mass multiplier per grocery item collected
@export var BASE_FRICTION: float = 6.0         # Unified low-friction deceleration (m/s^2)
@export var MAX_OPPOSING_DRIFT_RATIO: float = 0.65 # Opposing drift can NEVER counteract more than 65% of player speed
@export var FORWARD_ANCHOR_CROSS_DRIFT_RATIO: float = 0.50 # Max cross-drift as fraction of forward speed while anchored
@export var COUNTER_STEER_SLOPE_CLAMP_RATIO: float = 0.65  # Max slope drift fraction when counter-steering
@export var DRIFT_DAMPING: float = 1.5         # Viscous drag damping for smooth, manageable acceleration

var drift_velocity: Vector3 = Vector3.ZERO     # Accumulated lateral slope drift velocity
var input_velocity: Vector3 = Vector3.ZERO     # Active player locomotion velocity

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

	panting_sfx_player = AudioStreamPlayer.new()
	panting_sfx_player.stream = load("res://Assets 1/KayKit_Prototype_Bits_1.1_FREE/Music/Ouch.ogg")
	add_child(panting_sfx_player)

	# --- Sweat Particle FX Setup ---
	sweat_particles = CPUParticles3D.new()
	sweat_particles.emitting = false
	sweat_particles.amount = 14
	sweat_particles.lifetime = 0.6
	sweat_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sweat_particles.emission_sphere_radius = 0.25
	sweat_particles.direction = Vector3(0, 1, 0)
	sweat_particles.spread = 45.0
	sweat_particles.initial_velocity_min = 0.4
	sweat_particles.initial_velocity_max = 0.8
	sweat_particles.gravity = Vector3(0, -6.0, 0)

	var drop_mesh = SphereMesh.new()
	drop_mesh.radius = 0.035
	drop_mesh.height = 0.07
	var drop_mat = StandardMaterial3D.new()
	drop_mat.albedo_color = Color(0.5, 0.85, 1.0, 0.85)
	drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop_mat.emission_enabled = true
	drop_mat.emission = Color(0.4, 0.8, 1.0)
	drop_mat.emission_energy_multiplier = 1.5
	drop_mesh.material = drop_mat
	sweat_particles.mesh = drop_mesh
	sweat_particles.position = Vector3(0, 1.9, 0)
	if visual_model:
		visual_model.add_child(sweat_particles)
	else:
		add_child(sweat_particles)

	# --- Overhead Billboard Stamina Bar Setup ---
	overhead_stamina_viewport = SubViewport.new()
	overhead_stamina_viewport.size = Vector2i(140, 18)
	overhead_stamina_viewport.transparent_bg = true
	overhead_stamina_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(overhead_stamina_viewport)

	overhead_stamina_bar = ProgressBar.new()
	overhead_stamina_bar.size = Vector2(140, 18)
	overhead_stamina_bar.show_percentage = false
	overhead_stamina_bar.min_value = 0.0
	overhead_stamina_bar.max_value = 100.0
	overhead_stamina_bar.value     = 100.0

	var bar_bg = StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.08, 0.08, 0.12, 0.85)
	bar_bg.corner_radius_top_left     = 6
	bar_bg.corner_radius_top_right    = 6
	bar_bg.corner_radius_bottom_left  = 6
	bar_bg.corner_radius_bottom_right = 6
	bar_bg.set_border_width_all(2)
	bar_bg.border_color = Color(0.3, 0.6, 0.9, 0.9)
	overhead_stamina_bar.add_theme_stylebox_override("background", bar_bg)

	var bar_fill = StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.2, 0.85, 0.95, 1.0)
	bar_fill.corner_radius_top_left     = 5
	bar_fill.corner_radius_top_right    = 5
	bar_fill.corner_radius_bottom_left  = 5
	bar_fill.corner_radius_bottom_right = 5
	overhead_stamina_bar.add_theme_stylebox_override("fill", bar_fill)
	overhead_stamina_viewport.add_child(overhead_stamina_bar)

	# 25% gate notch marker on overhead bar
	var gate_marker = ColorRect.new()
	gate_marker.color = Color(1.0, 0.85, 0.2, 0.9)
	gate_marker.position = Vector2(35, 0) # 25% of 140 width
	gate_marker.size = Vector2(2, 18)
	overhead_stamina_bar.add_child(gate_marker)

	# 33.33% danger zone notch marker on overhead bar
	var danger_marker = ColorRect.new()
	danger_marker.color = Color(1.0, 0.45, 0.15, 0.9)
	danger_marker.position = Vector2(46.66, 0) # 33.33% of 140 width
	danger_marker.size = Vector2(2, 18)
	overhead_stamina_bar.add_child(danger_marker)

	overhead_stamina_sprite = Sprite3D.new()
	overhead_stamina_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	overhead_stamina_sprite.texture = overhead_stamina_viewport.get_texture()
	overhead_stamina_sprite.position = Vector3(0, 2.35, 0)
	overhead_stamina_sprite.pixel_size = 0.009
	overhead_stamina_sprite.no_depth_test = true
	overhead_stamina_sprite.modulate.a = 0.0 # Initially faded out
	add_child(overhead_stamina_sprite)

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

	# 5. Handle Double-Tap Sprint Detection (Obeying 25% sprint gate)
	if event is InputEventKey and event.pressed and not event.is_echo():
		for action in ["ui_up", "ui_down", "ui_left", "ui_right"]:
			if event.is_action_pressed(action):
				var current_time = Time.get_ticks_msec() / 1000.0
				if (current_time - last_press_times[action]) < DOUBLE_TAP_TIME:
					if can_sprint and stamina > 0.0:
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

func trigger_fatigue_penalty() -> void:
	stamina = 0.0
	is_fatigued = true
	fatigue_timer = 0.5
	can_sprint = false
	is_sprinting = false
	if panting_sfx_player:
		panting_sfx_player.pitch_scale = randf_range(0.82, 0.90)
		panting_sfx_player.play()

func update_stamina(delta: float, is_moving: bool) -> void:
	if is_sprinting and can_sprint and is_moving and not is_fatigued:
		# Drain stamina during active sprint
		stamina = max(0.0, stamina - SPRINT_DRAIN_RATE * delta)
		if stamina <= 0.0:
			trigger_fatigue_penalty()
		return

	# If player stopped moving or is fatigued, cancel sprint state without any penalty
	if not is_moving and not is_fatigued:
		is_sprinting = false

	# Recovery Loop (handles walking, standing, and fatigue freeze)
	if stamina < 100.0:
		var recovery_rate: float = 0.0
		var collected_items: int = 0
		if attached_cart != null:
			if "collected_items" in attached_cart:
				collected_items = attached_cart.collected_items.size()
			else:
				collected_items = _get_cart_item_count()

		var in_danger_zone: bool = (stamina < DANGER_ZONE_THRESHOLD) and (attached_cart != null)

		if is_moving:
			if in_danger_zone:
				# Scaled trickle while pushing loaded cart through danger zone
				var trickle_mult: float = clamp(0.25 - (float(collected_items) * 0.02), 0.15, 0.25)
				recovery_rate = RATE_REST * trickle_mult
			else:
				# Normal walk recovery
				recovery_rate = RATE_WALK
		else:
			if in_danger_zone:
				# Slightly dampened rest while holding loaded cart on incline
				var rest_mult: float = clamp(0.80 - (float(collected_items) * 0.015), 0.65, 0.80)
				recovery_rate = RATE_REST * rest_mult
			else:
				# Unrestricted full rest recovery
				recovery_rate = RATE_REST

		# Positive Rate Guarantee: recovery_rate is strictly positive
		stamina = min(100.0, stamina + recovery_rate * delta)

		# Check sprint gate reset
		if not can_sprint and stamina >= SPRINT_RECHARGE_GATE:
			can_sprint = true

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
	if not is_fatigued:
		input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var is_moving: bool = direction.length_squared() > 0.0001 and not is_fatigued
	
	# Update stamina engine with tiered recovery matrix
	update_stamina(delta, is_moving)

	# Handle 0.5s exhaustion freeze timer
	if is_fatigued:
		fatigue_timer -= delta
		if fatigue_timer <= 0.0:
			is_fatigued = false
			fatigue_timer = 0.0

	# --- Sweat Particle Emission ---
	if sweat_particles:
		var should_sweat: bool = (is_sprinting and can_sprint and is_moving) or is_fatigued or (not can_sprint and stamina < SPRINT_RECHARGE_GATE)
		sweat_particles.emitting = should_sweat

	# --- Overhead Billboard UI Update ---
	if overhead_stamina_sprite and overhead_stamina_bar:
		overhead_stamina_bar.value = stamina
		var target_alpha: float = 1.0 if (stamina < 99.5 or is_fatigued) else 0.0
		overhead_stamina_sprite.modulate.a = move_toward(overhead_stamina_sprite.modulate.a, target_alpha, 3.0 * delta)
		
		if not can_sprint:
			overhead_stamina_bar.modulate = Color(1.0, 0.25, 0.25) # Red exhaustion lockout
		elif stamina < DANGER_ZONE_THRESHOLD:
			overhead_stamina_bar.modulate = Color(1.0, 0.55, 0.15) # Danger zone orange/amber
		elif stamina < 70.0:
			overhead_stamina_bar.modulate = Color(1.0, 0.85, 0.2)  # Yellow
		else:
			overhead_stamina_bar.modulate = Color(0.2, 0.85, 0.95) # Cyan/Green
	
	var current_speed = SPRINT_SPEED if (is_sprinting and can_sprint) else SPEED

	if is_moving:
		var target_vel = direction * current_speed
		
		# Unified smooth acceleration (no rigid ground snapping)
		var accel = 24.0
		input_velocity.x = move_toward(input_velocity.x, target_vel.x, accel * delta)
		input_velocity.z = move_toward(input_velocity.z, target_vel.z, accel * delta)
		
		if is_instance_valid(visual_model):
			var target_angle = atan2(input_dir.x, input_dir.y)
			visual_model.rotation.y = lerp_angle(visual_model.rotation.y, target_angle, TURN_SPEED * delta)
		if is_instance_valid(anim_player) and anim_player.current_animation != "Rig_Medium_MovementBasic/Running_A":
			anim_player.play("Rig_Medium_MovementBasic/Running_A")
	else:
		# --- Unified Low-Friction Deceleration (Walking & Sprinting) ---
		var friction = BASE_FRICTION # 6.0 m/s^2 matching the loose sprint threshold
		if attached_cart != null:
			friction = max(3.2, BASE_FRICTION / sqrt(load_mult))
			
		input_velocity.x = move_toward(input_velocity.x, 0.0, friction * delta)
		input_velocity.z = move_toward(input_velocity.z, 0.0, friction * delta)
		
		# Reset sprint when nearly stopped (smooth deceleration, zero freeze)
		if input_velocity.length() < 0.2:
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

	# --- Drunken Camera Sway & Dynamic Roll (Phase Accumulated & 30% Baseline) ---
	var active_roll_angle: float = 0.0
	if is_instance_valid(camera):
		# 1. Normalized Direct Scalar with 30% Active Baseline & Last 20s Escalation Surge
		var raw_progress: float = clamp(play_time_passed / TOTAL_TIME, 0.0, 1.0) if game_started else 0.0
		var late_surge: float = 0.0
		if raw_progress > 0.66: # Ramps up dynamically during the final 20 seconds
			late_surge = pow((raw_progress - 0.66) / 0.34, 1.25) * 0.40
		var escalation_factor: float = clamp(lerp(0.30, 1.0, raw_progress) + late_surge, 0.0, 1.40) if game_started else 0.0
		
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
	if is_instance_valid(camera) and game_started:
		# 1. Downhill Vector Derivation (using load_mult calculated above)

		# Extract camera horizontal right vector (flattened on Y = 0 and normalized)
		var cam_basis = camera.global_transform.basis
		var cam_right = Vector3(cam_basis.x.x, 0.0, cam_basis.x.z)
		if cam_right.length_squared() > 0.0001:
			cam_right = cam_right.normalized()
		else:
			cam_right = Vector3.RIGHT
		
		# sin(deg_to_rad(active_roll_angle)) gives the downhill slope ratio toward the lower side
		var slope_ratio: float = sin(deg_to_rad(active_roll_angle))
		var downhill_vector: Vector3 = cam_right * slope_ratio
		
		# 2. Pulling Force Escalation (Slightly increased pulling force, especially during last 20s)
		var raw_progress_drift: float = clamp(play_time_passed / TOTAL_TIME, 0.0, 1.0)
		var last_20s_pull: float = 1.0
		if raw_progress_drift > 0.66: # Final 20 seconds
			last_20s_pull += pow((raw_progress_drift - 0.66) / 0.34, 1.2) * 0.45
		
		# Manageable acceleration injection
		var tilt_accel: Vector3 = downhill_vector * (BASE_TILT_MAGNITUDE * last_20s_pull) * load_mult
		drift_velocity += tilt_accel * delta
		
		# Viscous drag damping: eliminates static friction deadbands so drift is immediately felt,
		# while smoothly curbing acceleration toward manageable terminal velocities
		drift_velocity = drift_velocity.lerp(Vector3.ZERO, DRIFT_DAMPING * delta)
		
		# Hard ceiling on drift velocity so it remains balanced (max 3.25 m/s)
		if drift_velocity.length() > MAX_DRIFT_SPEED_CAP:
			drift_velocity = drift_velocity.normalized() * MAX_DRIFT_SPEED_CAP
		
		# 3. Binary Forward Anchor & Strict 65% Opposing Drift Clamp
		var effective_drift: Vector3 = drift_velocity
		
		# Camera forward vector on horizontal plane
		var cam_forward = -Vector3(cam_basis.z.x, 0.0, cam_basis.z.z)
		if cam_forward.length_squared() > 0.0001:
			cam_forward = cam_forward.normalized()
		else:
			cam_forward = -Vector3.FORWARD
			
		var d_downhill: Vector3 = downhill_vector.normalized() if downhill_vector.length_squared() > 0.0001 else Vector3.ZERO
		
		# Active intentional player locomotion vector
		var v_input: Vector3 = direction * current_speed if (direction.length_squared() > 0.0001 and not is_fatigued) else Vector3.ZERO
		
		if v_input.length_squared() > 0.0001:
			var v_forward: float = v_input.dot(cam_forward)
			
			# 3a. Forward Keel Anchor:
			# When driving forward along aisle (v_forward > 0.1), anchor lateral cross-drift
			# to prevent violent sideways slamming while steering down corridors
			if v_forward > 0.1 and d_downhill != Vector3.ZERO:
				var slope_drift_dot: float = effective_drift.dot(d_downhill)
				var v_slope_drift: Vector3 = d_downhill * slope_drift_dot
				var v_remaining_drift: Vector3 = effective_drift - v_slope_drift
				
				var max_allowed_cross_drift: float = v_forward * FORWARD_ANCHOR_CROSS_DRIFT_RATIO
				if abs(slope_drift_dot) > max_allowed_cross_drift:
					v_slope_drift = d_downhill * sign(slope_drift_dot) * max_allowed_cross_drift
				effective_drift = v_slope_drift + v_remaining_drift

			# 3b. Strict Opposing Drift Clamp:
			# The opposing drift can NEVER counteract more than 65% of player's active speed!
			# Guarantees at least 35% forward headway in player's intended direction under all conditions.
			var u_input: Vector3 = v_input.normalized()
			var input_speed: float = v_input.length()
			var drift_along_input: float = effective_drift.dot(u_input)
			
			if drift_along_input < 0.0:
				var max_opposing: float = input_speed * MAX_OPPOSING_DRIFT_RATIO
				if abs(drift_along_input) > max_opposing:
					var clamped_opposing_drift: float = -max_opposing
					var perp_drift: Vector3 = effective_drift - (u_input * drift_along_input)
					effective_drift = (u_input * clamped_opposing_drift) + perp_drift
		else:
			# Unanchored Release: when player is not actively pressing keys, coasting, or fatigued,
			# raw accumulated drift asserts full control, smoothly sliding player and cart downhill
			effective_drift = drift_velocity
			
		# Sum active locomotion and slope drift without compounding
		velocity.x = input_velocity.x + effective_drift.x
		velocity.z = input_velocity.z + effective_drift.z
	else:
		# Decay drift when stopped or before game starts
		drift_velocity = drift_velocity.lerp(Vector3.ZERO, 3.0 * delta)
		velocity.x = input_velocity.x
		velocity.z = input_velocity.z

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
					if attached_cart != null:
						gm.trigger_win()
					else:
						var hud := get_tree().root.find_child("ShoppingHUD", true, false)
						if hud and hud.has_method("show_warning"):
							hud.show_warning("🛒 Bring your cart to checkout to win!")

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
