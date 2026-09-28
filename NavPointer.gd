extends Node3D

# ──────────────────────────────────────────────────────────
#  NavPointer – 3D Floating Stylized Navigation Pointer
#  Hovers above the player and rotates in real-time to point
#  toward the nearest uncollected grocery item on the list.
#  Once all items are gathered, switches color to neon green
#  and points directly to the Checkout Counter!
# ──────────────────────────────────────────────────────────

const BASE_HEIGHT: float = 2.7
const ROT_SPEED: float = 12.0

@onready var arrow_mesh: MeshInstance3D = $ArrowMesh
@onready var arrow_mat: StandardMaterial3D = null

var target_position: Vector3 = Vector3.ZERO
var has_target: bool = false
var is_pointing_to_checkout: bool = false

func _ready() -> void:
	top_level = false
	position.y = BASE_HEIGHT
	if arrow_mesh and arrow_mesh.material_override:
		arrow_mat = arrow_mesh.material_override
	elif arrow_mesh and arrow_mesh.get_active_material(0):
		arrow_mat = arrow_mesh.get_active_material(0).duplicate()
		arrow_mesh.material_override = arrow_mat

func _process(delta: float) -> void:
	# 1. Subtle vertical hover bobbing
	position.y = BASE_HEIGHT + sin(Time.get_ticks_msec() * 0.005) * 0.12

	# 2. Acquire best objective target
	_update_target()

	# 3. Orient pointer toward target
	if has_target:
		var dir: Vector3 = (target_position - global_position)
		dir.y = 0.0
		if dir.length_squared() > 0.1:
			var target_angle = atan2(dir.x, dir.z)
			rotation.y = lerp_angle(rotation.y, target_angle, ROT_SPEED * delta)
	else:
		# Idle gentle rotation when all done or no target
		rotation.y += delta * 1.5

func _update_target() -> void:
	var gm = get_node_or_null("/root/GameModeManager")
	if not gm or not "shopping_list" in gm:
		has_target = false
		return

	# Case A: Shopping list complete -> Point to Checkout!
	if gm.get("list_complete") == true:
		is_pointing_to_checkout = true
		_set_pointer_color(Color(0.2, 1.0, 0.4), "CHECKOUT")
		var beacons = get_tree().get_nodes_in_group("checkout_beacon")
		if beacons.size() > 0:
			target_position = beacons[0].global_position
			has_target = true
			return
		# Fallback to checkout zone
		var parent_player = get_parent()
		if parent_player and "checkout_zones" in parent_player and parent_player.checkout_zones.size() > 0:
			target_position = parent_player.checkout_zones[0].global_position
			has_target = true
			return

	# Case B: Point to nearest needed grocery item
	is_pointing_to_checkout = false
	_set_pointer_color(Color(1.0, 0.85, 0.15), "GROCERY")

	var collectibles = get_tree().get_nodes_in_group("collectible_item")
	var closest_dist: float = INF
	var best_pos: Vector3 = Vector3.ZERO
	var found: bool = false

	for item in collectibles:
		if not is_instance_valid(item):
			continue
		var i_id = item.get("item_id")
		if i_id and i_id in gm.shopping_list:
			var entry = gm.shopping_list[i_id]
			if entry["collected"] < entry["required"]:
				var d = global_position.distance_squared_to(item.global_position)
				if d < closest_dist:
					closest_dist = d
					best_pos = item.global_position
					found = true

	if found:
		target_position = best_pos
		has_target = true
	else:
		has_target = false

func _set_pointer_color(col: Color, _mode: String) -> void:
	if arrow_mat:
		arrow_mat.albedo_color = col
		arrow_mat.emission = col
