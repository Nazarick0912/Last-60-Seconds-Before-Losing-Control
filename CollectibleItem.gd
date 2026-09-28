extends Area3D

# ──────────────────────────────────────────────────────────
#  CollectibleItem – A floating, glowing pick-up item.
# ──────────────────────────────────────────────────────────

@export var item_id: String = "milk"
@export var item_display_name: String = "Milk"

@onready var _label: Label3D = $Label3D

var _collected: bool = false
var _bob_time: float = 0.0
var _base_y: float = 0.0
var pickup_cooldown: float = 0.0

const ASSET_PATHS = {
	"milk": "res://Christmas Asset/KayKit_Holiday_Bits_1.0_FREE/Assets/gltf/milk.gltf",
	"cookie": "res://Christmas Asset/KayKit_Holiday_Bits_1.0_FREE/Assets/gltf/cookie.gltf",
	"mustard": "res://Kitchen Asset/KayKit_Restaurant_Bits_1.0_FREE/Assets/gltf/mustard.gltf",
	"ketchup": "res://Kitchen Asset/KayKit_Restaurant_Bits_1.0_FREE/Assets/gltf/ketchup.gltf",
	"jar": "res://Kitchen Asset/KayKit_Restaurant_Bits_1.0_FREE/Assets/gltf/jar_A_medium.gltf",
	"pot": "res://Kitchen Asset/KayKit_Restaurant_Bits_1.0_FREE/Assets/gltf/pot_A.gltf",
	"bowl": "res://Kitchen Asset/KayKit_Restaurant_Bits_1.0_FREE/Assets/gltf/bowl.gltf",
	"knife": "res://Kitchen Asset/KayKit_Restaurant_Bits_1.0_FREE/Assets/gltf/knife.gltf",
	"box": "res://Mart Asset/Models/FBX format/shelf-boxes.fbx",
	"bread": "res://Mart Asset/Models/FBX format/display-bread.fbx",
	"pan": "res://Kitchen Asset/KayKit_Restaurant_Bits_1.0_FREE/Assets/gltf/pan_A.gltf",
	"papertowel": "res://Kitchen Asset/KayKit_Restaurant_Bits_1.0_FREE/Assets/gltf/papertowel.gltf",
	"plate": "res://Kitchen Asset/KayKit_Restaurant_Bits_1.0_FREE/Assets/gltf/plate.gltf",
	"fruit": "res://Mart Asset/Models/FBX format/display-fruit.fbx",
	"stew": "res://Kitchen Asset/KayKit_Restaurant_Bits_1.0_FREE/Assets/gltf/stew_bowl.gltf",
	"basketball": "res://Christmas Asset/KayKit_Holiday_Bits_1.0_FREE/Assets/gltf/basketball.gltf"
}

var _model: Node3D = null
var skip_asset_load: bool = false
var external_mesh_to_steal: Node3D = null
var use_spawn_pos: bool = false
var spawn_global_pos: Vector3 = Vector3.ZERO

func _ready() -> void:
	top_level = true
	
	if use_spawn_pos:
		global_position = spawn_global_pos

	body_entered.connect(_on_body_entered)
	add_to_group("collectible_item")
	_base_y = global_position.y

	# 1. SETUP THE TALL CYLINDER COLLISION (Fixes Y-axis detection)
	var col_shape = get_node_or_null("CollisionShape3D")
	if col_shape:
		var tall_cylinder = CylinderShape3D.new()
		tall_cylinder.radius = 1.5   # Wider area
		tall_cylinder.height = 5.0   # Very tall column
		col_shape.shape = tall_cylinder
		col_shape.position.y = 0.0   # Center it so it covers above and below

	# Clean out placeholder
	var old_mesh = get_node_or_null("MeshInstance3D")
	if old_mesh:
		old_mesh.queue_free()

	if external_mesh_to_steal:
		external_mesh_to_steal.reparent(self, true)
		_model = external_mesh_to_steal
	elif item_id in ASSET_PATHS:
		var packed_scene = load(ASSET_PATHS[item_id])
		if packed_scene:
			_model = packed_scene.instantiate()
			_model.scale = Vector3(1.5, 1.5, 1.5)
			_model.position.y = 0.3 # Base hover height
			add_child(_model)

	# Fallback visual model if not mapped
	if _model == null and external_mesh_to_steal == null:
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3(0.55, 0.55, 0.55)
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.65, 0.15)
		mat.emission_enabled = true
		mat.emission = Color(0.9, 0.45, 0.1)
		mat.emission_energy_multiplier = 0.8
		var mi = MeshInstance3D.new()
		mi.mesh = box_mesh
		mi.material_override = mat
		mi.position.y = 0.35
		add_child(mi)
		_model = mi
	
	_label.text = item_display_name

func _physics_process(delta: float) -> void:
	if pickup_cooldown > 0.0:
		pickup_cooldown -= delta

func _process(delta: float) -> void:
	if _collected:
		return
		
	_bob_time += delta
	
	# 2. BOB ONLY THE VISUALS
	if _model:
		_model.position.y = 0.3 + sin(_bob_time * 2.2) * 0.12
	if _label:
		_label.position.y = 1.1 + sin(_bob_time * 2.2) * 0.12
	
	if _model and external_mesh_to_steal == null:
		_model.rotation_degrees.y += delta * 60.0

func animate_scatter_toss(start_pos: Vector3, target_pos: Vector3) -> void:
	global_position = start_pos
	pickup_cooldown = 1.8 # Prevent instant vacuuming back up
	_base_y = target_pos.y

	var tween = create_tween()
	var mid_y = start_pos.y + 2.0
	
	# Parabolic toss arc
	tween.tween_property(self, "global_position:y", mid_y, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "global_position:x", (start_pos.x + target_pos.x) * 0.5, 0.35)
	tween.parallel().tween_property(self, "global_position:z", (start_pos.z + target_pos.z) * 0.5, 0.35)
	
	tween.chain().tween_property(self, "global_position:y", target_pos.y, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "global_position:x", target_pos.x, 0.35)
	tween.parallel().tween_property(self, "global_position:z", target_pos.z, 0.35)

func _on_body_entered(body: Node3D) -> void:
	if _collected or pickup_cooldown > 0.0: return
	if body is CharacterBody3D:
		if body.attached_cart == null:
			var gm := get_node_or_null("/root/GameModeManager")
			if gm and gm.has_signal("warning_triggered"):
				gm.emit_signal("warning_triggered", "🛒 Cart required to collect groceries!")
			var hud := get_tree().root.find_child("ShoppingHUD", true, false)
			if hud and hud.has_method("show_warning"):
				hud.show_warning("🛒 Cart required to collect groceries!")
			return
		var gm := get_node_or_null("/root/GameModeManager")
		if gm:
			if not (item_id in gm.shopping_list): return
			var entry = gm.shopping_list[item_id]
			if entry["collected"] >= entry["required"]: return
		_do_collect()

func _do_collect() -> void:
	_collected = true
	set_deferred("monitoring", false)
	var gm := get_node_or_null("/root/GameModeManager")
	if gm: gm.collect_item(item_id)
	set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)
	queue_free()
