extends CanvasLayer

# Dialogue UI Controller for Godot 4.x
# Mount this script on the DialogueUI (CanvasLayer) node.

@onready var avatar: TextureRect = $Panel/Avatar
@onready var role_name_label: Label = $Panel/RoleName
@onready var content_label: Label = $Panel/Content
@onready var next_btn: Button = $Panel/NextBtn
@onready var dialogue_audio: AudioStreamPlayer = $DialogueAudio

@export var type_speed: float = 0.05

var is_running: bool = false
var is_typing: bool = false

# Dialog data loaded from res://data/dialogue_data.json
var _dialogs: Array = []
var _dialog_map: Dictionary = {}
var _current_id: int = -1

func _ready() -> void:
	# Start hidden and disconnected
	visible = false

	# Connect next button
	if next_btn:
		next_btn.pressed.connect(_on_next_btn_pressed)

	# Clean initial UI
	role_name_label.text = ""
	content_label.text = ""
	avatar.visible = false

	# Preload dialogs if available
	_load_dialogs()

func _load_dialogs() -> void:
	var path: String = "res://data/dialogue_data.json"
	var file: FileAccess = FileAccess.open(path, FileAccess.ModeFlags.READ)
	if not file:
		push_warning("Dialogue JSON not found at %s" % path)
		return

	var text: String = file.get_as_text()
	var parse = JSON.parse_string(text)
	if parse.error != OK:
		push_error("Failed to parse dialogue JSON: %s" % parse.error)
		return

	_dialogs = parse.result
	_dialog_map.clear()
	for d in _dialogs:
		if typeof(d) == TYPE_DICTIONARY and d.has("id"):
			_dialog_map[int(d["id"])] = d

func start_dialogue(scene_name: String) -> void:
	# Prevent re-entry
	if is_running:
		return

	if _dialogs.size() == 0:
		_load_dialogs()
		if _dialogs.size() == 0:
			push_warning("No dialogues loaded; aborting start_dialogue")
			return

	# Find the first dialog whose trigger_scene matches scene_name (preserve order)
	var start_entry: Dictionary = {}
	for d in _dialogs:
		if ("trigger_scene" in d) and str(d["trigger_scene"]) == scene_name:
			start_entry = d
			break

	if start_entry == null:
		push_warning("No dialogue found for scene: %s" % scene_name)
		return

	is_running = true
	get_tree().paused = true
	visible = true

	_current_id = int(start_entry["id"])
	_show_dialogue(_current_id)

func _show_dialogue(dialogue_id: int) -> void:
	var entry: Dictionary = {}
	if dialogue_id in _dialog_map:
		entry = _dialog_map[dialogue_id]
	else:
		# Not found
		push_warning("Dialogue id %d not found" % dialogue_id)
		end_dialogue()
		return

	# Set role name
	role_name_label.text = str(entry.get("role_name", ""))

	# Handle avatar
	var art_path := str(entry.get("artwork", "null"))
	if art_path == "null" or art_path.strip_edges() == "":
		avatar.visible = false
	else:
		var tex = ResourceLoader.load(art_path)
		if tex and tex is Texture2D:
			avatar.texture = tex
			avatar.visible = true
		else:
			avatar.visible = false

	# Prepare text
	var full_text: String = str(entry.get("text", ""))
	content_label.text = ""
	next_btn.visible = false
	is_typing = true

	# Optionally play dialogue audio (one-shot for the line)
	var audio_id := str(entry.get("voice_id", "")).strip_edges()
	if audio_id != "":
		var audio_path := "res://audio/dialogue/%s.wav" % audio_id
		var stream = ResourceLoader.load(audio_path)
		if stream and stream is AudioStream:
			dialogue_audio.stream = stream
			dialogue_audio.play()

	# Typing effect (per character)
	var total_chars := full_text.length()
	for i in range(1, total_chars + 1):
		if not is_typing:
			break
		content_label.text = full_text.substr(0, i)

		# skip sound for spaces/newlines
		var ch := full_text.substr(i-1, 1)
		if ch != " " and ch != "\n":
			# optional small click sound could be played here if desired
			pass

		var wait_time := type_speed
		if ch in ["，", "。", "！", "？", "…", ",", ".", "!", "?"]:
			wait_time = type_speed * 5

		await get_tree().create_timer(wait_time).timeout

	is_typing = false
	# Show continue button after typing finished
	next_btn.visible = true

func _on_next_btn_pressed() -> void:
	if is_typing:
		# ignore while typing (button should be hidden) but be safe
		return

	# Get current entry and its next_id
	if not (_current_id in _dialog_map):
		end_dialogue()
		return

	var entry: Dictionary = _dialog_map[_current_id]
	var next_id = entry.get("next_id", null)

	# Handle both None/null and -1 as end signal
	if next_id == null or int(next_id) == -1:
		end_dialogue()
		return

	_current_id = int(next_id)
	_show_dialogue(_current_id)

func end_dialogue() -> void:
	# Stop audio and hide UI
	if dialogue_audio.playing:
		dialogue_audio.stop()

	visible = false
	get_tree().paused = false
	is_running = false
	is_typing = false

	# Clear UI
	role_name_label.text = ""
	content_label.text = ""
	avatar.visible = false

