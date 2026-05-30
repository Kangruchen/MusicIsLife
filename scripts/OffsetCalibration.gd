extends Control

const BPM: float = 120.0
const BEAT_INTERVAL: float = 60.0 / BPM
const NOTE_SPEED: float = 300.0
const DEFAULT_JUDGMENT_LINE_X: float = 576.0
const NOTE_SPAWN_X: float = 1200.0
const OFFSET_STEP: float = 10.0
const RETURN_SCENE_META: StringName = &"offset_return_scene_path"

var block_sound: AudioStream
var current_offset: float = 0.0
var current_judgment_x: float = DEFAULT_JUDGMENT_LINE_X
var beat_timer: float = 0.0
var _return_scene_path: String = "res://scenes/main_menu.tscn"
var _gamepad_manager: Node = null

@onready var judgment_line: ColorRect = $JudgmentLine
@onready var notes_container: Control = $NotesContainer
@onready var offset_label: Label = $OffsetLabel
@onready var hint_label: Label = $HintLabel
@onready var decrease_button: Button = $DecreaseButton
@onready var increase_button: Button = $IncreaseButton
@onready var audio_player: AudioStreamPlayer = $AudioStreamPlayer
@onready var metronome_label: Label = $MetronomeLabel


func _ready() -> void:
	_gamepad_manager = get_node_or_null("/root/GamepadManager")
	if get_tree().has_meta(RETURN_SCENE_META):
		var return_path: String = String(get_tree().get_meta(RETURN_SCENE_META))
		if not return_path.is_empty():
			_return_scene_path = return_path

	block_sound = load("res://assets/SFX/block.wav")
	audio_player.stream = block_sound

	load_offset_config()
	update_offset_display()
	update_judgment_line_position()
	_setup_buttons()
	_update_hint_text()

	if _gamepad_manager != null and _gamepad_manager.has_signal("input_scheme_changed"):
		_gamepad_manager.connect("input_scheme_changed", func(_is_gamepad: bool) -> void:
			_update_hint_text()
		)

	beat_timer = 0.0


func _process(delta: float) -> void:
	beat_timer += delta
	if beat_timer >= BEAT_INTERVAL:
		beat_timer -= BEAT_INTERVAL
		_spawn_note()
		_play_metronome()

	_update_notes(delta)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("offset") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("menu"):
		_return_to_main()
	elif event.is_action_pressed("ui_left"):
		_on_decrease_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_on_increase_pressed()
		get_viewport().set_input_as_handled()


func _setup_buttons() -> void:
	decrease_button.pressed.connect(_on_decrease_pressed)
	increase_button.pressed.connect(_on_increase_pressed)

	var focus_style: StyleBoxFlat = _make_focus_style()
	for button in [decrease_button, increase_button]:
		button.focus_mode = Control.FOCUS_ALL
		button.add_theme_stylebox_override("focus", focus_style)

	decrease_button.focus_neighbor_right = decrease_button.get_path_to(increase_button)
	increase_button.focus_neighbor_left = increase_button.get_path_to(decrease_button)
	call_deferred("_focus_decrease_button")


func _focus_decrease_button() -> void:
	if decrease_button != null and is_instance_valid(decrease_button):
		decrease_button.grab_focus()


func _make_focus_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.draw_center = false
	style.set_border_width_all(3)
	style.border_color = Color(1.0, 0.85, 0.25, 1.0)
	style.set_expand_margin_all(5)
	return style


func _spawn_note() -> void:
	var note_visual := ColorRect.new()
	note_visual.size = Vector2(20, 80)
	note_visual.color = Color(1.0, 1.0, 0.0, 0.8)
	note_visual.position = Vector2(NOTE_SPAWN_X, 284)
	notes_container.add_child(note_visual)


func _play_metronome() -> void:
	audio_player.play()
	_flash_metronome()


func _flash_metronome() -> void:
	metronome_label.modulate = Color(1.0, 1.0, 0.0, 1.0)
	await get_tree().create_timer(0.1).timeout
	metronome_label.modulate = Color(1.0, 1.0, 1.0, 1.0)


func _update_notes(delta: float) -> void:
	for note in notes_container.get_children():
		if note is ColorRect:
			note.position.x -= NOTE_SPEED * delta
			if note.position.x + note.size.x >= current_judgment_x and note.position.x <= current_judgment_x:
				_flash_judgment_line()
			if note.position.x < -100:
				note.queue_free()


func _flash_judgment_line() -> void:
	judgment_line.color = Color(0.0, 1.0, 0.0, 1.0)
	await get_tree().create_timer(0.05).timeout
	judgment_line.color = Color(1.0, 1.0, 1.0, 0.8)


func _on_decrease_pressed() -> void:
	_rumble_ui(&"ui_confirm")
	current_offset -= OFFSET_STEP
	update_offset_display()
	update_judgment_line_position()


func _on_increase_pressed() -> void:
	_rumble_ui(&"ui_confirm")
	current_offset += OFFSET_STEP
	update_offset_display()
	update_judgment_line_position()


func update_offset_display() -> void:
	offset_label.text = "Current offset: %.0f ms" % current_offset


func _update_hint_text() -> void:
	if hint_label == null:
		return
	var left_prompt: String = GameConstants.get_action_key_label("ui_left", "Left")
	var right_prompt: String = GameConstants.get_action_key_label("ui_right", "Right")
	var back_prompt: String = GameConstants.get_action_key_label("ui_cancel", "Esc")
	hint_label.text = "Adjust until the note crosses the line with the beat. %s/%s changes offset, %s returns." % [
		left_prompt,
		right_prompt,
		back_prompt,
	]


func update_judgment_line_position() -> void:
	var offset_pixels: float = (current_offset / 1000.0) * NOTE_SPEED
	current_judgment_x = DEFAULT_JUDGMENT_LINE_X + offset_pixels
	judgment_line.position.x = current_judgment_x - judgment_line.size.x / 2.0


func load_offset_config() -> void:
	var config := ConfigFile.new()
	var err := config.load("user://settings.cfg")
	if err == OK:
		current_offset = config.get_value("audio", "offset", 0.0)
		print("Loaded audio offset: ", current_offset, " ms")


func save_offset_config() -> void:
	var config := ConfigFile.new()
	config.load("user://settings.cfg")
	config.set_value("audio", "offset", current_offset)
	config.set_value("audio", "offset_ms", current_offset)
	var err := config.save("user://settings.cfg")
	if err == OK:
		print("Saved audio offset: ", current_offset, " ms")
	else:
		push_error("Failed to save audio offset: %d" % err)


func _return_to_main() -> void:
	_rumble_ui(&"ui_back")
	save_offset_config()
	if get_tree().has_meta(RETURN_SCENE_META):
		get_tree().remove_meta(RETURN_SCENE_META)
	get_tree().change_scene_to_file(_return_scene_path)


func _rumble_ui(preset: StringName) -> void:
	if _gamepad_manager != null and _gamepad_manager.has_method("rumble"):
		_gamepad_manager.call("rumble", preset)
