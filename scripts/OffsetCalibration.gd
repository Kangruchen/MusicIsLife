extends Control

const BPM: float = 120.0
const BEAT_INTERVAL: float = 60.0 / BPM
const NOTE_SPEED: float = 300.0
const DEFAULT_JUDGMENT_LINE_X: float = 576.0
const NOTE_SPAWN_X: float = 1200.0
const OFFSET_STEP: float = 10.0

var block_sound: AudioStream
var current_offset: float = 0.0
var current_judgment_x: float = DEFAULT_JUDGMENT_LINE_X
var beat_timer: float = 0.0
var _gamepad_manager: Node = null
var _rumble_strength_label: Label = null
var _rumble_slider: HSlider = null

@onready var judgment_line: ColorRect = $JudgmentLine
@onready var notes_container: Control = $NotesContainer
@onready var offset_label: Label = $OffsetLabel
@onready var hint_label: Label = $HintLabel
@onready var decrease_button: Button = $DecreaseButton
@onready var increase_button: Button = $IncreaseButton
@onready var audio_player: AudioStreamPlayer = $AudioStreamPlayer
@onready var metronome_label: Label = $MetronomeLabel


func _ready() -> void:
	block_sound = load("res://assets/SFX/block.wav")
	audio_player.stream = block_sound

	load_offset_config()
	update_offset_display()
	update_judgment_line_position()
	_setup_buttons()
	_setup_gamepad_settings()
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
		if get_viewport().gui_get_focus_owner() == _rumble_slider:
			return
		_on_decrease_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		if get_viewport().gui_get_focus_owner() == _rumble_slider:
			return
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


func _setup_gamepad_settings() -> void:
	_gamepad_manager = get_node_or_null("/root/GamepadManager")
	if _gamepad_manager == null:
		return

	var panel: PanelContainer = PanelContainer.new()
	panel.name = "GamepadSettingsPanel"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -230.0
	panel.offset_top = 18.0
	panel.offset_right = -18.0
	panel.offset_bottom = 130.0
	add_child(panel)

	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.0, 0.0, 0.0, 0.35)
	panel_style.set_border_width_all(1)
	panel_style.border_color = Color(1.0, 1.0, 1.0, 0.20)
	panel_style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", panel_style)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var title: Label = Label.new()
	title.text = "Gamepad"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25, 1.0))
	vbox.add_child(title)

	var rumble_check: CheckBox = CheckBox.new()
	rumble_check.text = "Rumble"
	rumble_check.focus_mode = Control.FOCUS_ALL
	rumble_check.button_pressed = bool(_gamepad_manager.get("rumble_enabled"))
	rumble_check.toggled.connect(func(pressed: bool) -> void:
		if _gamepad_manager != null and _gamepad_manager.has_method("set_rumble_enabled"):
			_gamepad_manager.call("set_rumble_enabled", pressed)
	)
	vbox.add_child(rumble_check)

	_rumble_strength_label = Label.new()
	_rumble_strength_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_rumble_strength_label)

	_rumble_slider = HSlider.new()
	_rumble_slider.min_value = 0.0
	_rumble_slider.max_value = 1.0
	_rumble_slider.step = 0.05
	_rumble_slider.focus_mode = Control.FOCUS_ALL
	_rumble_slider.value = float(_gamepad_manager.get("rumble_strength"))
	_rumble_slider.value_changed.connect(func(value: float) -> void:
		_update_rumble_strength_label(value)
		if _gamepad_manager != null and _gamepad_manager.has_method("set_rumble_strength"):
			_gamepad_manager.call("set_rumble_strength", value)
	)
	vbox.add_child(_rumble_slider)
	_update_rumble_strength_label(_rumble_slider.value)

	rumble_check.focus_neighbor_bottom = rumble_check.get_path_to(_rumble_slider)
	_rumble_slider.focus_neighbor_top = _rumble_slider.get_path_to(rumble_check)
	_rumble_slider.focus_neighbor_bottom = _rumble_slider.get_path_to(decrease_button)
	decrease_button.focus_neighbor_top = decrease_button.get_path_to(_rumble_slider)
	increase_button.focus_neighbor_top = increase_button.get_path_to(_rumble_slider)


func _update_rumble_strength_label(value: float) -> void:
	if _rumble_strength_label == null:
		return
	_rumble_strength_label.text = "Strength: %d%%" % int(round(value * 100.0))


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
	current_offset -= OFFSET_STEP
	update_offset_display()
	update_judgment_line_position()


func _on_increase_pressed() -> void:
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
	save_offset_config()
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
