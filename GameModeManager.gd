extends Node

# ──────────────────────────────────────────────────────────
#  GameModeManager  – Autoload singleton
#  Tracks the player's shopping list and broadcasts signals
#  to the ShoppingHUD.
# ──────────────────────────────────────────────────────────

signal list_updated()
signal game_won()
signal game_lost()
signal checkout_ready()
signal warning_triggered(msg: String)

# Shopping list definition: key → { label, required, collected }
var shopping_list: Dictionary = {}

var _game_active: bool = false
var _game_ended:  bool = false
var list_complete: bool = false

# Global Audio Stream Players
var start_sfx_player: AudioStreamPlayer
var bgm_player: AudioStreamPlayer
var pickup_player: AudioStreamPlayer
var lose_player: AudioStreamPlayer
var win_sfx_player: AudioStreamPlayer
# ── Lifecycle ────────────────────────────────────────────
func _ready() -> void:
	# --- AUDIO SETUP ---
	bgm_player = AudioStreamPlayer.new()
	var bgm_stream = load("res://Assets 1/KayKit_Prototype_Bits_1.1_FREE/Music/In the Hall of the Mountain King.ogg") as AudioStreamOggVorbis
	if bgm_stream:
		bgm_stream.loop = true
	bgm_player.stream = bgm_stream
	bgm_player.volume_db = -10.0
	bgm_player.autoplay = true
	add_child(bgm_player)
	
	pickup_player = AudioStreamPlayer.new()
	pickup_player.stream = load("res://Assets 1/KayKit_Prototype_Bits_1.1_FREE/Music/Chaching.ogg")
	add_child(pickup_player)
	
	lose_player = AudioStreamPlayer.new()
	lose_player.stream = load("res://Assets 1/KayKit_Prototype_Bits_1.1_FREE/Music/Lose2.ogg")
	add_child(lose_player)
	
	start_sfx_player = AudioStreamPlayer.new()
	start_sfx_player.stream = load("res://Assets 1/KayKit_Prototype_Bits_1.1_FREE/Music/DingDong.ogg")
	add_child(start_sfx_player)
	_reset_list()
	
	win_sfx_player = AudioStreamPlayer.new()
	win_sfx_player.stream = load("res://Assets 1/KayKit_Prototype_Bits_1.1_FREE/Music/Yeah.ogg")
	win_sfx_player.process_mode = Node.PROCESS_MODE_ALWAYS 
	add_child(win_sfx_player)

func _reset_list() -> void:
	# Resume BGM if it was stopped (e.g. after a loss)
	if bgm_player and not bgm_player.playing:
		bgm_player.play()
	shopping_list.clear()
	
	var ALL_AVAILABLE = [
		{ "id": "milk",       "label": "🥛 Milk" },
		{ "id": "cookie",     "label": "🍪 Cookie" },
		{ "id": "mustard",    "label": "🌭 Mustard" },
		{ "id": "ketchup",    "label": "🍅 Ketchup" },
		{ "id": "jar",        "label": "🫙 Jar" },
		{ "id": "pot",        "label": "🍲 Pot" },
		{ "id": "pan",        "label": "🍳 Pan" },
		{ "id": "papertowel", "label": "🧻 Paper Towel" },
		{ "id": "bowl",       "label": "🥣 Bowl" },
		{ "id": "knife",      "label": "🔪 Knife" },
		{ "id": "box",        "label": "📦 Box" },
		{ "id": "bread",      "label": "🍞 Bread" },
		{ "id": "fruit",      "label": "🍓 Fruit" },
		{ "id": "carrots",    "label": "🥕 Carrots" },
		{ "id": "cheese",     "label": "🧀 Cheese" },
		{ "id": "plate",      "label": "🍽️ Plate" },
		{ "id": "burger",     "label": "🍔 Burger" },
		{ "id": "stew",       "label": "🍲 Stew" },
		{ "id": "basketball", "label": "🏀 Basketball" },
		{ "id": "ham",        "label": "🍖 Ham" },
		{ "id": "tomatoes",   "label": "🍅 Tomatoes" },
		{ "id": "onions",     "label": "🧅 Onions" },
		{ "id": "potatoes",   "label": "🥔 Potatoes" }
	]
	
	# Scramble the list
	ALL_AVAILABLE.shuffle()
	
	# Pick between 3 to 6 unique items to find
	var amount_to_pick = randi_range(5, 6)
	var picked_items = ALL_AVAILABLE.slice(0, amount_to_pick)
	
	for item in picked_items:
		shopping_list[item["id"]] = {
			"label": item["label"],
			# Generate 1 to 3 copies per item
			"required": randi_range(1, 3), 
			"collected": 0
		}
		
	_game_active = false
	_game_ended  = false
	list_complete = false

func start_game() -> void:
	if not _game_active and not _game_ended:
		_game_active = true
		if start_sfx_player:
			start_sfx_player.play()

# ── Called by CollectibleItem when the player picks up an item ──
func collect_item(item_id: String) -> void:
	if not _game_active or _game_ended:
		return
	if item_id in shopping_list:
		var entry: Dictionary = shopping_list[item_id]
		if entry["collected"] < entry["required"]:
			entry["collected"] += 1
			if pickup_player:
				pickup_player.play()
			emit_signal("list_updated")
			_check_win()

# ── Check if all items are collected ────────────────────
func _check_win() -> void:
	for key in shopping_list:
		if shopping_list[key]["collected"] < shopping_list[key]["required"]:
			return
	
	# All items collected, but we haven't checked out yet!
	if not list_complete:
		list_complete = true
		emit_signal("checkout_ready")
		emit_signal("list_updated") 

func trigger_win() -> void:
	do_checkout()

func do_checkout() -> void:
	if list_complete and not _game_ended:
		_game_ended  = true
		_game_active = false
		
		if win_sfx_player:
			win_sfx_player.play()
			
		# NEW (Optional): Stop the background music so you can hear the win sound better
		if bgm_player:
			bgm_player.stop()
		emit_signal("game_won")

# ── Called externally when the player's 60 s timer runs out ─
func notify_time_up() -> void:
	if not _game_ended:
		_game_ended  = true
		_game_active = false
		if bgm_player:
			bgm_player.stop()
		if lose_player:
			lose_player.play()
		emit_signal("game_lost")

# ── Helpers ──────────────────────────────────────────────
func is_active() -> bool:
	return _game_active

## Returns formatted shopping list for UI display
func get_progress_lines() -> Array:
	var lines: Array = []
	for key in shopping_list:
		var e: Dictionary = shopping_list[key]
		var done: int = mini(e["collected"], e["required"])
		var tick: String = "✅" if done >= e["required"] else "🔲"
		lines.append("%s %s  %d / %d" % [tick, e["label"], done, e["required"]])
	return lines

func play_start_sound() -> void:
	if start_sfx_player:
		start_sfx_player.play()
