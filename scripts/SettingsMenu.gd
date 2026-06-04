extends Control
class_name SettingsMenu

const SETTINGS_FILE_PATH: String = "user://settings.cfg"
const RETURN_SCENE_META: StringName = &"offset_return_scene_path"
const GAMEPLAY_SETTINGS_SECTION: String = "gameplay"
const PREJUDGE_HINT_MODE_KEY: String = "prejudge_key_hint_display_mode"
const PREJUDGE_HINT_MODE_ALWAYS: int = 0
const PREJUDGE_HINT_MODE_LIMITED: int = 1
const ICON_MODE_ITEMS: Array[Dictionary] = [
	{"label": "Auto Detect", "mode": "auto"},
	{"label": "PlayStation", "mode": "playstation"},
	{"label": "Xbox", "mode": "xbox"},
	{"label": "Nintendo", "mode": "nintendo"},
]
const KEY_HINT_MODE_ITEMS: Array[Dictionary] = [
	{"label": "Always", "mode": PREJUDGE_HINT_MODE_ALWAYS},
	{"label": "Limited", "mode": PREJUDGE_HINT_MODE_LIMITED},
]

@onready var rumble_check: CheckBox = $Panel/Margin/VBox/RumbleCheck
@onready var strength_label: Label = $Panel/Margin/VBox/StrengthLabel
@onready var strength_slider: HSlider = $Panel/Margin/VBox/StrengthSlider
@onready var icon_button: OptionButton = $Panel/Margin/VBox/IconButton
@onready var key_hint_button: OptionButton = $Panel/Margin/VBox/KeyHintButton
@onready var latency_button: Button = $Panel/Margin/VBox/LatencyButton
@onready var back_button: Button = $Panel/Margin/VBox/BackButton

var _gamepad_manager: Node = null


func _ready() -> void:
	_gamepad_manager = get_node_or_null("/root/GamepadManager")
	_setup_icon_options()
	_setup_key_hint_options()
	_setup_values()
	_setup_focus()

	rumble_check.toggled.connect(_on_rumble_toggled)
	strength_slider.value_changed.connect(_on_strength_changed)
	icon_button.item_selected.connect(_on_icon_mode_selected)
	key_hint_button.item_selected.connect(_on_key_hint_mode_selected)
	latency_button.pressed.connect(_on_latency_pressed)
	back_button.pressed.connect(_on_back_pressed)
	call_deferred("_focus_first_control")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()


func _setup_values() -> void:
	if _gamepad_manager != null:
		rumble_check.button_pressed = bool(_gamepad_manager.get("rumble_enabled"))
		strength_slider.value = float(_gamepad_manager.get("rumble_strength"))
	else:
		var fallback_config: ConfigFile = ConfigFile.new()
		if fallback_config.load(SETTINGS_FILE_PATH) == OK:
			rumble_check.button_pressed = bool(fallback_config.get_value("gamepad", "rumble_enabled", true))
			strength_slider.value = float(fallback_config.get_value("gamepad", "rumble_strength", 1.0))
			_select_icon_mode(String(fallback_config.get_value("gamepad", "controller_icon_family", "auto")))
			_select_key_hint_mode(int(fallback_config.get_value(GAMEPLAY_SETTINGS_SECTION, PREJUDGE_HINT_MODE_KEY, PREJUDGE_HINT_MODE_ALWAYS)))
	_update_strength_label(strength_slider.value)
	if _gamepad_manager != null and _gamepad_manager.has_method("get_controller_icon_mode"):
		_select_icon_mode(String(_gamepad_manager.call("get_controller_icon_mode")))
	var hint_config: ConfigFile = ConfigFile.new()
	if hint_config.load(SETTINGS_FILE_PATH) == OK:
		_select_key_hint_mode(int(hint_config.get_value(GAMEPLAY_SETTINGS_SECTION, PREJUDGE_HINT_MODE_KEY, PREJUDGE_HINT_MODE_ALWAYS)))


func _setup_icon_options() -> void:
	icon_button.clear()
	for i in range(ICON_MODE_ITEMS.size()):
		var item: Dictionary = ICON_MODE_ITEMS[i]
		icon_button.add_item(String(item["label"]), i)
		icon_button.set_item_metadata(i, String(item["mode"]))
	_select_icon_mode("auto")


func _setup_key_hint_options() -> void:
	key_hint_button.clear()
	for i in range(KEY_HINT_MODE_ITEMS.size()):
		var item: Dictionary = KEY_HINT_MODE_ITEMS[i]
		key_hint_button.add_item(String(item["label"]), i)
		key_hint_button.set_item_metadata(i, int(item["mode"]))
	_select_key_hint_mode(PREJUDGE_HINT_MODE_ALWAYS)


func _select_icon_mode(mode: String) -> void:
	var normalized: String = mode.strip_edges().to_lower()
	for i in range(icon_button.get_item_count()):
		if String(icon_button.get_item_metadata(i)) == normalized:
			icon_button.select(i)
			return
	icon_button.select(0)


func _select_key_hint_mode(mode: int) -> void:
	var normalized: int = clampi(mode, PREJUDGE_HINT_MODE_ALWAYS, PREJUDGE_HINT_MODE_LIMITED)
	for i in range(key_hint_button.get_item_count()):
		if int(key_hint_button.get_item_metadata(i)) == normalized:
			key_hint_button.select(i)
			return
	key_hint_button.select(0)


func _setup_focus() -> void:
	var focus_style: StyleBoxFlat = _make_focus_style()
	for control in [rumble_check, strength_slider, icon_button, key_hint_button, latency_button, back_button]:
		control.focus_mode = Control.FOCUS_ALL
		control.add_theme_stylebox_override("focus", focus_style)

	rumble_check.focus_neighbor_bottom = rumble_check.get_path_to(strength_slider)
	strength_slider.focus_neighbor_top = strength_slider.get_path_to(rumble_check)
	strength_slider.focus_neighbor_bottom = strength_slider.get_path_to(icon_button)
	icon_button.focus_neighbor_top = icon_button.get_path_to(strength_slider)
	icon_button.focus_neighbor_bottom = icon_button.get_path_to(key_hint_button)
	key_hint_button.focus_neighbor_top = key_hint_button.get_path_to(icon_button)
	key_hint_button.focus_neighbor_bottom = key_hint_button.get_path_to(latency_button)
	latency_button.focus_neighbor_top = latency_button.get_path_to(key_hint_button)
	latency_button.focus_neighbor_bottom = latency_button.get_path_to(back_button)
	back_button.focus_neighbor_top = back_button.get_path_to(latency_button)


func _make_focus_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.draw_center = false
	style.border_color = Color(0.35, 0.90, 0.78, 1.0)
	style.set_border_width_all(2)
	style.set_expand_margin_all(4)
	return style


func _focus_first_control() -> void:
	if rumble_check != null and is_instance_valid(rumble_check):
		rumble_check.grab_focus()


func _on_rumble_toggled(pressed: bool) -> void:
	if _gamepad_manager != null and _gamepad_manager.has_method("set_rumble_enabled"):
		_gamepad_manager.call("set_rumble_enabled", pressed)


func _on_strength_changed(value: float) -> void:
	_update_strength_label(value)
	if _gamepad_manager != null and _gamepad_manager.has_method("set_rumble_strength"):
		_gamepad_manager.call("set_rumble_strength", value)


func _on_icon_mode_selected(index: int) -> void:
	if _gamepad_manager == null or not _gamepad_manager.has_method("set_controller_icon_mode"):
		return
	var mode: String = String(icon_button.get_item_metadata(index))
	_gamepad_manager.call("set_controller_icon_mode", mode)
	_rumble_ui(&"ui_confirm")


func _on_key_hint_mode_selected(index: int) -> void:
	var mode: int = int(key_hint_button.get_item_metadata(index))
	_save_key_hint_mode(mode)
	_rumble_ui(&"ui_confirm")


func _save_key_hint_mode(mode: int) -> void:
	var config: ConfigFile = ConfigFile.new()
	var load_err: int = config.load(SETTINGS_FILE_PATH)
	if load_err != OK and load_err != ERR_FILE_NOT_FOUND:
		return
	config.set_value(GAMEPLAY_SETTINGS_SECTION, PREJUDGE_HINT_MODE_KEY, clampi(mode, PREJUDGE_HINT_MODE_ALWAYS, PREJUDGE_HINT_MODE_LIMITED))
	config.save(SETTINGS_FILE_PATH)


func _update_strength_label(value: float) -> void:
	strength_label.text = "Vibration Strength: %d%%" % int(round(value * 100.0))


func _on_latency_pressed() -> void:
	_rumble_ui(&"ui_confirm")
	get_tree().set_meta(RETURN_SCENE_META, "res://scenes/settings.tscn")
	get_tree().change_scene_to_file("res://scenes/OffsetCalibration.tscn")


func _on_back_pressed() -> void:
	_rumble_ui(&"ui_back")
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _rumble_ui(preset: StringName) -> void:
	if _gamepad_manager != null and _gamepad_manager.has_method("rumble"):
		_gamepad_manager.call("rumble", preset)
