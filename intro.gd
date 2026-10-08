extends Control

const MAIN_SCENE := "res://main.tscn"

@onready var start_button: Button = $StartButton
@onready var background: TextureRect = $Background

var _transitioning: bool = false

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Transition animation on entry
	start_button.modulate.a = 0
	var tw = create_tween()
	tw.tween_property(start_button, "modulate:a", 1.0, 1.0)
	
	start_button.pressed.connect(_on_start_pressed)

func _process(_delta: float) -> void:
	if not _transitioning:
		# Subtle pulse for the button
		var pulse = 0.95 + sin(Time.get_ticks_msec() * 0.005) * 0.05
		start_button.scale = Vector2(pulse, pulse)
		start_button.pivot_offset = start_button.size / 2

func _on_start_pressed() -> void:
	if _transitioning: return
	_transitioning = true
	
	GameModeManager.play_start_sound()
	GameModeManager.restart_music()
	
	var tw = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.5)
	await tw.finished
	
	get_tree().change_scene_to_file(MAIN_SCENE)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and not _transitioning:
		_on_start_pressed()
