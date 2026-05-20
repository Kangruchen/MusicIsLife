extends Node
class_name GamepadManager

signal input_scheme_changed(is_gamepad: bool)

const SETTINGS_FILE_PATH: String = "user://settings.cfg"
const SETTINGS_SECTION: String = "gamepad"
const SETTINGS_RUMBLE_ENABLED: String = "rumble_enabled"
const SETTINGS_RUMBLE_STRENGTH: String = "rumble_strength"

const SCHEME_KEYBOARD_MOUSE: StringName = &"keyboard_mouse"
const SCHEME_GAMEPAD: StringName = &"gamepad"

const BUTTON_LABELS_XBOX := {
	JOY_BUTTON_A: "A",
	JOY_BUTTON_B: "B",
	JOY_BUTTON_X: "X",
	JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "View",
	JOY_BUTTON_START: "Menu",
	JOY_BUTTON_LEFT_SHOULDER: "LB",
	JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_LEFT_STICK: "LS",
	JOY_BUTTON_RIGHT_STICK: "RS",
	JOY_BUTTON_DPAD_UP: "D-Up",
	JOY_BUTTON_DPAD_DOWN: "D-Down",
	JOY_BUTTON_DPAD_LEFT: "D-Left",
	JOY_BUTTON_DPAD_RIGHT: "D-Right",
}

const BUTTON_LABELS_PLAYSTATION := {
	JOY_BUTTON_A: "Cross",
	JOY_BUTTON_B: "Circle",
	JOY_BUTTON_X: "Square",
	JOY_BUTTON_Y: "Triangle",
	JOY_BUTTON_BACK: "Share",
	JOY_BUTTON_START: "Options",
	JOY_BUTTON_LEFT_SHOULDER: "L1",
	JOY_BUTTON_RIGHT_SHOULDER: "R1",
	JOY_BUTTON_LEFT_STICK: "L3",
	JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_DPAD_UP: "D-Up",
	JOY_BUTTON_DPAD_DOWN: "D-Down",
	JOY_BUTTON_DPAD_LEFT: "D-Left",
	JOY_BUTTON_DPAD_RIGHT: "D-Right",
}

const BUTTON_LABELS_NINTENDO := {
	JOY_BUTTON_A: "B",
	JOY_BUTTON_B: "A",
	JOY_BUTTON_X: "Y",
	JOY_BUTTON_Y: "X",
	JOY_BUTTON_BACK: "-",
	JOY_BUTTON_START: "+",
	JOY_BUTTON_LEFT_SHOULDER: "L",
	JOY_BUTTON_RIGHT_SHOULDER: "R",
	JOY_BUTTON_LEFT_STICK: "LS",
	JOY_BUTTON_RIGHT_STICK: "RS",
	JOY_BUTTON_DPAD_UP: "D-Up",
	JOY_BUTTON_DPAD_DOWN: "D-Down",
	JOY_BUTTON_DPAD_LEFT: "D-Left",
	JOY_BUTTON_DPAD_RIGHT: "D-Right",
}

@export var rumble_enabled: bool = true
@export_range(0.0, 1.0, 0.05) var rumble_strength: float = 0.7

var current_scheme: StringName = SCHEME_KEYBOARD_MOUSE
var last_gamepad_device: int = -1
var _last_rumble_msec: int = 0
var _last_heat_level: int = 0


func _ready() -> void:
	_load_settings()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

	if not EventBus.judgment_made.is_connected(_on_judgment_made):
		EventBus.judgment_made.connect(_on_judgment_made)
	if not EventBus.attack_result_display.is_connected(_on_attack_result_display):
		EventBus.attack_result_display.connect(_on_attack_result_display)
	if not EventBus.heat_changed.is_connected(_on_heat_changed):
		EventBus.heat_changed.connect(_on_heat_changed)
	if not EventBus.boss_energy_depleted.is_connected(_on_boss_energy_depleted):
		EventBus.boss_energy_depleted.connect(_on_boss_energy_depleted)
	if not EventBus.player_died.is_connected(_on_player_died):
		EventBus.player_died.connect(_on_player_died)
	if not EventBus.boss_defeated.is_connected(_on_boss_defeated):
		EventBus.boss_defeated.connect(_on_boss_defeated)


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		var button_event: InputEventJoypadButton = event as InputEventJoypadButton
		if button_event.pressed:
			_set_gamepad_active(button_event.device)
	elif event is InputEventJoypadMotion:
		var motion_event: InputEventJoypadMotion = event as InputEventJoypadMotion
		if absf(motion_event.axis_value) >= 0.45:
			_set_gamepad_active(motion_event.device)
	elif event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo:
			_set_keyboard_mouse_active()
	elif event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event as InputEventMouseButton
		if mouse_button.pressed:
			_set_keyboard_mouse_active()
	elif event is InputEventMouseMotion:
		var mouse_motion: InputEventMouseMotion = event as InputEventMouseMotion
		if mouse_motion.relative.length_squared() > 16.0:
			_set_keyboard_mouse_active()


func is_gamepad_active() -> bool:
	return current_scheme == SCHEME_GAMEPAD


func get_action_prompt(action: StringName, fallback: String = "") -> String:
	if not InputMap.has_action(action):
		return fallback
	var events: Array = InputMap.action_get_events(action)
	if events.is_empty():
		return fallback

	var preferred: String = _find_event_prompt(events, is_gamepad_active())
	if not preferred.is_empty():
		return preferred

	var secondary: String = _find_event_prompt(events, not is_gamepad_active())
	if not secondary.is_empty():
		return secondary

	return fallback


func get_note_prompt(note_type: int, fallback: String = "") -> String:
	match note_type:
		Note.NoteType.GUARD:
			return get_action_prompt(&"note_guard", "J" if fallback.is_empty() else fallback)
		Note.NoteType.HIT:
			return get_action_prompt(&"note_hit", "I" if fallback.is_empty() else fallback)
		Note.NoteType.DODGE:
			return get_action_prompt(&"note_dodge", "L" if fallback.is_empty() else fallback)
		_:
			return fallback


func format_input_event(event: InputEvent) -> String:
	if event is InputEventKey:
		return _format_key_event(event as InputEventKey)
	if event is InputEventMouseButton:
		return _format_mouse_button(event as InputEventMouseButton)
	if event is InputEventJoypadButton:
		return _format_joypad_button(event as InputEventJoypadButton)
	if event is InputEventJoypadMotion:
		return _format_joypad_motion(event as InputEventJoypadMotion)
	return ""


func rumble(preset: StringName) -> void:
	if not rumble_enabled:
		return

	var device: int = _get_active_gamepad_device()
	if device < 0:
		return

	var now: int = Time.get_ticks_msec()
	if now - _last_rumble_msec < 45:
		return
	_last_rumble_msec = now

	var weak: float = 0.0
	var strong: float = 0.0
	var duration: float = 0.05

	match preset:
		&"defense_perfect":
			weak = 0.18
			strong = 0.28
			duration = 0.04
		&"defense_ok":
			weak = 0.10
			strong = 0.15
			duration = 0.035
		&"miss":
			weak = 0.55
			strong = 0.85
			duration = 0.10
		&"heavy":
			weak = 0.38
			strong = 0.62
			duration = 0.08
		&"heat_up":
			weak = 0.30
			strong = 0.48
			duration = 0.055
			_start_vibration(device, weak, strong, duration)
			get_tree().create_timer(0.09).timeout.connect(func() -> void:
				_start_vibration(_get_active_gamepad_device(), 0.22, 0.36, 0.045)
			)
			return
		&"shield_break":
			weak = 0.45
			strong = 0.70
			duration = 0.12
		&"victory":
			weak = 0.30
			strong = 0.45
			duration = 0.16
		&"death":
			weak = 0.60
			strong = 0.95
			duration = 0.20
		_:
			weak = 0.20
			strong = 0.30
			duration = 0.05

	_start_vibration(device, weak, strong, duration)


func set_rumble_enabled(value: bool) -> void:
	rumble_enabled = value
	_save_settings()


func set_rumble_strength(value: float) -> void:
	rumble_strength = clampf(value, 0.0, 1.0)
	_save_settings()


func _find_event_prompt(events: Array, want_gamepad: bool) -> String:
	for event in events:
		var is_gamepad_event: bool = event is InputEventJoypadButton or event is InputEventJoypadMotion
		if is_gamepad_event != want_gamepad:
			continue
		var label: String = format_input_event(event)
		if not label.is_empty():
			return label
	return ""


func _format_key_event(event: InputEventKey) -> String:
	var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if code == 0:
		return ""
	var label: String = OS.get_keycode_string(code)
	return label


func _format_mouse_button(event: InputEventMouseButton) -> String:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			return "Mouse 1"
		MOUSE_BUTTON_RIGHT:
			return "Mouse 2"
		MOUSE_BUTTON_MIDDLE:
			return "Mouse 3"
		MOUSE_BUTTON_WHEEL_UP:
			return "Wheel Up"
		MOUSE_BUTTON_WHEEL_DOWN:
			return "Wheel Down"
		_:
			return "Mouse %d" % event.button_index


func _format_joypad_button(event: InputEventJoypadButton) -> String:
	var labels: Dictionary = _get_button_labels()
	return String(labels.get(event.button_index, "Button %d" % event.button_index))


func _format_joypad_motion(event: InputEventJoypadMotion) -> String:
	var positive: bool = event.axis_value > 0.0
	match event.axis:
		JOY_AXIS_LEFT_X:
			return "LS Right" if positive else "LS Left"
		JOY_AXIS_LEFT_Y:
			return "LS Down" if positive else "LS Up"
		JOY_AXIS_RIGHT_X:
			return "RS Right" if positive else "RS Left"
		JOY_AXIS_RIGHT_Y:
			return "RS Down" if positive else "RS Up"
		JOY_AXIS_TRIGGER_LEFT:
			return "LT"
		JOY_AXIS_TRIGGER_RIGHT:
			return "RT"
		_:
			return "Axis %d+" % event.axis if positive else "Axis %d-" % event.axis


func _get_button_labels() -> Dictionary:
	match _get_controller_family():
		"playstation":
			return BUTTON_LABELS_PLAYSTATION
		"nintendo":
			return BUTTON_LABELS_NINTENDO
		_:
			return BUTTON_LABELS_XBOX


func _get_controller_family() -> String:
	var device: int = _get_active_gamepad_device()
	if device < 0:
		return "xbox"
	var joy_name: String = Input.get_joy_name(device).to_lower()
	if joy_name.contains("playstation") or joy_name.contains("dualshock") or joy_name.contains("dualsense") or joy_name.contains("sony"):
		return "playstation"
	if joy_name.contains("switch") or joy_name.contains("nintendo") or joy_name.contains("joy-con"):
		return "nintendo"
	return "xbox"


func _get_active_gamepad_device() -> int:
	var joypads: Array[int] = Input.get_connected_joypads()
	if joypads.is_empty():
		return -1
	if last_gamepad_device >= 0 and joypads.has(last_gamepad_device):
		return last_gamepad_device
	last_gamepad_device = int(joypads[0])
	return last_gamepad_device


func _set_gamepad_active(device: int) -> void:
	if device >= 0:
		last_gamepad_device = device
	_set_scheme(SCHEME_GAMEPAD)


func _set_keyboard_mouse_active() -> void:
	_set_scheme(SCHEME_KEYBOARD_MOUSE)


func _set_scheme(next_scheme: StringName) -> void:
	if current_scheme == next_scheme:
		return
	current_scheme = next_scheme
	input_scheme_changed.emit(is_gamepad_active())


func _start_vibration(device: int, weak: float, strong: float, duration: float) -> void:
	if device < 0:
		return
	var strength: float = clampf(rumble_strength, 0.0, 1.0)
	if strength <= 0.0:
		return
	Input.start_joy_vibration(device, clampf(weak * strength, 0.0, 1.0), clampf(strong * strength, 0.0, 1.0), maxf(0.01, duration))


func _on_judgment_made(_track: int, judgment: int, _timing_diff: float) -> void:
	match judgment:
		0:
			rumble(&"defense_perfect")
		1, 2:
			rumble(&"defense_ok")
		3:
			rumble(&"miss")


func _on_attack_result_display(attack_type: int, is_perfect: bool, _heat_level: int) -> void:
	if attack_type == 1:
		rumble(&"heavy")
	elif attack_type == 0 and is_perfect:
		rumble(&"defense_perfect")


func _on_heat_changed(heat_level: int, _heat_counter: int) -> void:
	if heat_level > _last_heat_level:
		rumble(&"heat_up")
	_last_heat_level = heat_level


func _on_boss_energy_depleted() -> void:
	rumble(&"shield_break")


func _on_player_died() -> void:
	rumble(&"death")


func _on_boss_defeated() -> void:
	rumble(&"victory")


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		last_gamepad_device = device
	elif device == last_gamepad_device:
		last_gamepad_device = _get_active_gamepad_device()
		if last_gamepad_device < 0:
			_set_keyboard_mouse_active()


func _load_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	var err: int = config.load(SETTINGS_FILE_PATH)
	if err != OK:
		return
	rumble_enabled = bool(config.get_value(SETTINGS_SECTION, SETTINGS_RUMBLE_ENABLED, rumble_enabled))
	rumble_strength = clampf(float(config.get_value(SETTINGS_SECTION, SETTINGS_RUMBLE_STRENGTH, rumble_strength)), 0.0, 1.0)


func _save_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	var err: int = config.load(SETTINGS_FILE_PATH)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		return
	config.set_value(SETTINGS_SECTION, SETTINGS_RUMBLE_ENABLED, rumble_enabled)
	config.set_value(SETTINGS_SECTION, SETTINGS_RUMBLE_STRENGTH, rumble_strength)
	config.save(SETTINGS_FILE_PATH)
