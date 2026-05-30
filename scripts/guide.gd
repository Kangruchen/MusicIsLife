extends Control
class_name GuideMenu

@onready var back_btn: Button = $BackButton
@onready var defense_text: RichTextLabel = $Content
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
	_update_input_text()


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
		defense_text.text = "[u][color=red]Defense Phase[/color] - Match the attack color on the beat: [color=blue]%s[/color] / [color=yellow]%s[/color] / [color=green]%s[/color].[/u]" % [
			guard_prompt,
			hit_prompt,
			dodge_prompt,
		]

	if attack_text:
		attack_text.text = "[u][color=red]Attack Phase[/color] - Move with %s/%s and attack on the beat.[/u]\n[color=blue]Blue (%s) = Light[/color]  [color=yellow]Yellow (%s) = Heavy[/color]\n[color=red]Red (%s) = Boost[/color]  [color=green]Green (No Input) = Heal[/color]" % [
			left_prompt,
			right_prompt,
			guard_prompt,
			hit_prompt,
			dodge_prompt,
		]


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
