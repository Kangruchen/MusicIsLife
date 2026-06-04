extends Node

signal input_scheme_changed(is_gamepad: bool)
signal controller_icon_family_changed(family: String)

const SETTINGS_FILE_PATH: String = "user://settings.cfg"
const SETTINGS_SECTION: String = "gamepad"
const SETTINGS_RUMBLE_ENABLED: String = "rumble_enabled"
const SETTINGS_RUMBLE_STRENGTH: String = "rumble_strength"
const SETTINGS_CONTROLLER_ICON_FAMILY: String = "controller_icon_family"

const SCHEME_KEYBOARD_MOUSE: StringName = &"keyboard_mouse"
const SCHEME_GAMEPAD: StringName = &"gamepad"
const CONTROLLER_ICON_AUTO: String = "auto"
const CONTROLLER_ICON_PLAYSTATION: String = "playstation"
const CONTROLLER_ICON_XBOX: String = "xbox"
const CONTROLLER_ICON_NINTENDO: String = "nintendo"
const NOTE_TYPE_GUARD: int = 0
const NOTE_TYPE_HIT: int = 1
const NOTE_TYPE_DODGE: int = 2

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
	JOY_BUTTON_A: "×",
	JOY_BUTTON_B: "○",
	JOY_BUTTON_X: "□",
	JOY_BUTTON_Y: "△",
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
@export_range(0.0, 1.0, 0.05) var rumble_strength: float = 1.0

var current_scheme: StringName = SCHEME_KEYBOARD_MOUSE
var controller_icon_family: String = CONTROLLER_ICON_AUTO
var last_gamepad_device: int = -1
var _last_rumble_msec: int = 0
var _last_heat_level: int = 0


func _ready() -> void:
	_ensure_controller_ui_actions()
	_load_settings()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

	var event_bus: Node = get_node_or_null("/root/EventBus")
	if event_bus == null:
		return

	if not event_bus.judgment_made.is_connected(_on_judgment_made):
		event_bus.judgment_made.connect(_on_judgment_made)
	if not event_bus.attack_result_display.is_connected(_on_attack_result_display):
		event_bus.attack_result_display.connect(_on_attack_result_display)
	if not event_bus.heat_changed.is_connected(_on_heat_changed):
		event_bus.heat_changed.connect(_on_heat_changed)
	if not event_bus.boss_energy_depleted.is_connected(_on_boss_energy_depleted):
		event_bus.boss_energy_depleted.connect(_on_boss_energy_depleted)
	if not event_bus.player_died.is_connected(_on_player_died):
		event_bus.player_died.connect(_on_player_died)
	if not event_bus.boss_defeated.is_connected(_on_boss_defeated):
		event_bus.boss_defeated.connect(_on_boss_defeated)


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
		NOTE_TYPE_GUARD:
			return get_action_prompt(&"note_guard", "J" if fallback.is_empty() else fallback)
		NOTE_TYPE_HIT:
			return get_action_prompt(&"note_hit", "I" if fallback.is_empty() else fallback)
		NOTE_TYPE_DODGE:
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
			weak = 0.35
			strong = 0.58
			duration = 0.075
		&"defense_ok":
			weak = 0.22
			strong = 0.36
			duration = 0.06
		&"miss":
			weak = 0.75
			strong = 1.00
			duration = 0.15
		&"heavy":
			weak = 0.55
			strong = 0.88
			duration = 0.12
		&"heat_up":
			weak = 0.45
			strong = 0.72
			duration = 0.08
			_start_vibration(device, weak, strong, duration)
			get_tree().create_timer(0.11).timeout.connect(func() -> void:
				_start_vibration(_get_active_gamepad_device(), 0.35, 0.55, 0.065)
			)
			return
		&"shield_break":
			weak = 0.65
			strong = 1.00
			duration = 0.18
		&"victory":
			weak = 0.45
			strong = 0.70
			duration = 0.20
		&"death":
			weak = 0.80
			strong = 0.95
			duration = 0.28
		&"ui_confirm":
			weak = 0.18
			strong = 0.34
			duration = 0.05
		&"ui_back":
			weak = 0.24
			strong = 0.44
			duration = 0.065
		_:
			weak = 0.30
			strong = 0.48
			duration = 0.07

	_start_vibration(device, weak, strong, duration)


func set_rumble_enabled(value: bool) -> void:
	rumble_enabled = value
	_save_settings()


func set_rumble_strength(value: float) -> void:
	rumble_strength = clampf(value, 0.0, 1.0)
	_save_settings()


func get_controller_icon_mode() -> String:
	return controller_icon_family


func get_controller_icon_family() -> String:
	return _get_controller_family()


func set_controller_icon_mode(mode: String) -> void:
	var normalized: String = _normalize_controller_icon_mode(mode)
	if controller_icon_family == normalized:
		return
	controller_icon_family = normalized
	_save_settings()
	controller_icon_family_changed.emit(_get_controller_family())
	input_scheme_changed.emit(is_gamepad_active())


func _ensure_controller_ui_actions() -> void:
	_ensure_key_action(&"ui_accept", KEY_ENTER)
	_ensure_key_action(&"ui_accept", KEY_SPACE)
	_ensure_button_action(&"ui_accept", JOY_BUTTON_A)

	_ensure_key_action(&"ui_cancel", KEY_ESCAPE)
	_ensure_button_action(&"ui_cancel", JOY_BUTTON_B)

	_ensure_key_action(&"ui_up", KEY_UP)
	_ensure_key_action(&"ui_up", KEY_W)
	_ensure_button_action(&"ui_up", JOY_BUTTON_DPAD_UP)
	_ensure_motion_action(&"ui_up", JOY_AXIS_LEFT_Y, -1.0)

	_ensure_key_action(&"ui_down", KEY_DOWN)
	_ensure_key_action(&"ui_down", KEY_S)
	_ensure_button_action(&"ui_down", JOY_BUTTON_DPAD_DOWN)
	_ensure_motion_action(&"ui_down", JOY_AXIS_LEFT_Y, 1.0)

	_ensure_key_action(&"ui_left", KEY_LEFT)
	_ensure_key_action(&"ui_left", KEY_A)
	_ensure_button_action(&"ui_left", JOY_BUTTON_DPAD_LEFT)
	_ensure_motion_action(&"ui_left", JOY_AXIS_LEFT_X, -1.0)

	_ensure_key_action(&"ui_right", KEY_RIGHT)
	_ensure_key_action(&"ui_right", KEY_D)
	_ensure_button_action(&"ui_right", JOY_BUTTON_DPAD_RIGHT)
	_ensure_motion_action(&"ui_right", JOY_AXIS_LEFT_X, 1.0)


func _ensure_key_action(action: StringName, physical_keycode: Key) -> void:
	_ensure_action(action)
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = physical_keycode
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)


func _ensure_button_action(action: StringName, button_index: JoyButton) -> void:
	_ensure_action(action)
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = button_index
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)


func _ensure_motion_action(action: StringName, axis: JoyAxis, axis_value: float) -> void:
	_ensure_action(action)
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = axis_value
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)


func _ensure_action(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)


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
		CONTROLLER_ICON_PLAYSTATION:
			return BUTTON_LABELS_PLAYSTATION
		CONTROLLER_ICON_NINTENDO:
			return BUTTON_LABELS_NINTENDO
		_:
			return BUTTON_LABELS_XBOX


func _get_controller_family() -> String:
	if controller_icon_family != CONTROLLER_ICON_AUTO:
		return controller_icon_family

	var device: int = _get_active_gamepad_device()
	if device < 0:
		return CONTROLLER_ICON_PLAYSTATION
	var joy_name: String = Input.get_joy_name(device).to_lower()
	if joy_name.contains("switch") or joy_name.contains("nintendo") or joy_name.contains("joy-con") or joy_name.contains("joycon") or joy_name.contains("pro controller"):
		return CONTROLLER_ICON_NINTENDO
	if joy_name.contains("xbox") or joy_name.contains("xinput") or joy_name.contains("microsoft") or joy_name.contains("x-box"):
		return CONTROLLER_ICON_XBOX
	if joy_name.contains("playstation") or joy_name.contains("dualshock") or joy_name.contains("dualsense") or joy_name.contains("sony") or joy_name.contains("ps4") or joy_name.contains("ps5") or joy_name.contains("wireless controller"):
		return CONTROLLER_ICON_PLAYSTATION
	return CONTROLLER_ICON_PLAYSTATION


func _normalize_controller_icon_mode(mode: String) -> String:
	var normalized: String = mode.strip_edges().to_lower()
	match normalized:
		CONTROLLER_ICON_AUTO, CONTROLLER_ICON_PLAYSTATION, CONTROLLER_ICON_XBOX, CONTROLLER_ICON_NINTENDO:
			return normalized
		_:
			return CONTROLLER_ICON_AUTO


func _get_active_gamepad_device() -> int:
	var joypads: Array[int] = Input.get_connected_joypads()
	if joypads.is_empty():
		return -1
	if last_gamepad_device >= 0 and joypads.has(last_gamepad_device):
		return last_gamepad_device
	last_gamepad_device = int(joypads[0])
	return last_gamepad_device


func _set_gamepad_active(device: int) -> void:
	var previous_family: String = _get_controller_family()
	var was_gamepad_active: bool = is_gamepad_active()
	if device >= 0:
		last_gamepad_device = device
	_set_scheme(SCHEME_GAMEPAD)
	var next_family: String = _get_controller_family()
	if was_gamepad_active and previous_family != next_family:
		controller_icon_family_changed.emit(next_family)
		input_scheme_changed.emit(true)


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
	var previous_family: String = _get_controller_family()
	if connected:
		last_gamepad_device = device
	elif device == last_gamepad_device:
		last_gamepad_device = _get_active_gamepad_device()
		if last_gamepad_device < 0:
			_set_keyboard_mouse_active()
	var next_family: String = _get_controller_family()
	if previous_family != next_family:
		controller_icon_family_changed.emit(next_family)
		input_scheme_changed.emit(is_gamepad_active())


func _load_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	var err: int = config.load(SETTINGS_FILE_PATH)
	if err != OK:
		return
	rumble_enabled = bool(config.get_value(SETTINGS_SECTION, SETTINGS_RUMBLE_ENABLED, rumble_enabled))
	rumble_strength = clampf(float(config.get_value(SETTINGS_SECTION, SETTINGS_RUMBLE_STRENGTH, rumble_strength)), 0.0, 1.0)
	controller_icon_family = _normalize_controller_icon_mode(String(config.get_value(SETTINGS_SECTION, SETTINGS_CONTROLLER_ICON_FAMILY, controller_icon_family)))


func _save_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	var err: int = config.load(SETTINGS_FILE_PATH)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		return
	config.set_value(SETTINGS_SECTION, SETTINGS_RUMBLE_ENABLED, rumble_enabled)
	config.set_value(SETTINGS_SECTION, SETTINGS_RUMBLE_STRENGTH, rumble_strength)
	config.set_value(SETTINGS_SECTION, SETTINGS_CONTROLLER_ICON_FAMILY, controller_icon_family)
	config.save(SETTINGS_FILE_PATH)
