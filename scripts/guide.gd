extends Control
class_name GuideMenu

@onready var back_btn: Button = $BackButton
@onready var title_label: Label = $Title
@onready var defense_text: RichTextLabel = $Content
@onready var shield_text: RichTextLabel = $Content2
@onready var energy_text: RichTextLabel = $Content3
@onready var health_text: RichTextLabel = $Content4
@onready var attack_text: RichTextLabel = $Content5


func _ready() -> void:
	if back_btn:
		back_btn.pressed.connect(_on_back_pressed)
		back_btn.focus_mode = Control.FOCUS_ALL
		back_btn.add_theme_stylebox_override("focus", _make_focus_style())
		call_deferred("_focus_back_button")
	else:
		push_error("Guide scene is missing BackButton.")

	var gamepad_manager: Node = get_node_or_null("/root/GamepadManager")
	if gamepad_manager != null and gamepad_manager.has_signal("input_scheme_changed"):
		gamepad_manager.connect("input_scheme_changed", func(_is_gamepad: bool) -> void:
			_update_input_text()
		)
	_connect_localization_updates()
	_apply_translations()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()


func _update_input_text() -> void:
	var guard_prompt: String = GameConstants.get_action_key_label("note_guard", "J")
	var hit_prompt: String = GameConstants.get_action_key_label("note_hit", "I")
	var dodge_prompt: String = GameConstants.get_action_key_label("note_dodge", "L")
	var left_prompt: String = GameConstants.get_action_key_label("move_left", "A")
	var right_prompt: String = GameConstants.get_action_key_label("move_right", "D")

	if defense_text:
		defense_text.text = tr("GUIDE_DEFENSE_WITH_KEYS") % [
			guard_prompt,
			hit_prompt,
			dodge_prompt,
		]

	if attack_text:
		attack_text.text = tr("GUIDE_ATTACK_WITH_KEYS") % [
			left_prompt,
			right_prompt,
			guard_prompt,
			hit_prompt,
			dodge_prompt,
		]


func _connect_localization_updates() -> void:
	var localization_manager: Node = get_node_or_null("/root/LocalizationManager")
	if localization_manager == null or not localization_manager.has_signal("locale_changed"):
		return
	localization_manager.connect("locale_changed", func(_locale: String) -> void:
		_apply_translations()
	)


func _apply_translations() -> void:
	title_label.text = tr("GUIDE_TITLE")
	if shield_text:
		shield_text.text = tr("GUIDE_SHIELD")
	if energy_text:
		energy_text.text = tr("GUIDE_ENERGY")
	if health_text:
		health_text.text = tr("GUIDE_HEALTH")
	if back_btn:
		back_btn.text = tr("GUIDE_BACK_TO_MENU")
	_update_input_text()


func _focus_back_button() -> void:
	if back_btn != null and is_instance_valid(back_btn):
		back_btn.grab_focus()


func _make_focus_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.draw_center = false
	style.set_border_width_all(2)
	style.border_color = Color(1.0, 0.7, 0.25, 1.0)
	style.set_expand_margin_all(4)
	return style


func _on_back_pressed() -> void:
	_rumble_ui(&"ui_back")
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _rumble_ui(preset: StringName) -> void:
	var gamepad_manager: Node = get_node_or_null("/root/GamepadManager")
	if gamepad_manager != null and gamepad_manager.has_method("rumble"):
		gamepad_manager.call("rumble", preset)
