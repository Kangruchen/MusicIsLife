extends Control
class_name MainMenu

@onready var new_game_btn: Button = $CenterContainer/MenuVBox/NewGameBtn
@onready var tutorial_btn: Button = $CenterContainer/MenuVBox/TutorialBtn
@onready var guide_btn: Button = $CenterContainer/MenuVBox/GuideBtn
@onready var settings_btn: Button = $CenterContainer/MenuVBox/SettingsBtn
@onready var quit_btn: Button = $CenterContainer/MenuVBox/QuitBtn

@export_file("*.tscn") var game_scene_path: String = "res://scenes/Main.tscn"
@export_file("*.tscn") var tutorial_scene_path: String = "res://scenes/tutorial.tscn"
@export_file("*.tscn") var guide_scene_path: String = "res://scenes/guide.tscn"
@export_file("*.tscn") var settings_scene_path: String = "res://scenes/OffsetCalibration.tscn"

var _menu_buttons: Array[Button] = []


func _ready() -> void:
	_menu_buttons = [new_game_btn, tutorial_btn, guide_btn, settings_btn, quit_btn]

	new_game_btn.pressed.connect(_on_new_game_pressed)
	tutorial_btn.pressed.connect(_on_tutorial_pressed)
	guide_btn.pressed.connect(_on_guide_pressed)
	settings_btn.pressed.connect(_on_settings_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)

	_setup_focus_navigation()
	call_deferred("_focus_first_button")


func _setup_focus_navigation() -> void:
	for i in range(_menu_buttons.size()):
		var button: Button = _menu_buttons[i]
		if button == null:
			continue
		button.focus_mode = Control.FOCUS_ALL
		button.add_theme_stylebox_override("focus", _make_focus_style())
		if not button.focus_entered.is_connected(_on_button_focus_entered.bind(button)):
			button.focus_entered.connect(_on_button_focus_entered.bind(button))
		if not button.focus_exited.is_connected(_on_button_focus_exited.bind(button)):
			button.focus_exited.connect(_on_button_focus_exited.bind(button))

		var previous_button: Button = _menu_buttons[(i - 1 + _menu_buttons.size()) % _menu_buttons.size()]
		var next_button: Button = _menu_buttons[(i + 1) % _menu_buttons.size()]
		button.focus_neighbor_top = button.get_path_to(previous_button)
		button.focus_neighbor_bottom = button.get_path_to(next_button)


func _focus_first_button() -> void:
	if new_game_btn != null and is_instance_valid(new_game_btn):
		new_game_btn.grab_focus()


func _make_focus_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.draw_center = false
	style.set_border_width_all(2)
	style.border_color = Color(1.0, 0.8, 0.0, 1.0)
	style.set_expand_margin_all(6)
	return style


func _on_button_focus_entered(button: Button) -> void:
	if button == null:
		return
	button.add_theme_color_override("font_color", Color("#FFCC00"))
	var tween: Tween = create_tween()
	tween.tween_property(button, "scale", Vector2(1.08, 1.08), 0.08).set_trans(Tween.TRANS_BACK)


func _on_button_focus_exited(button: Button) -> void:
	if button == null:
		return
	button.remove_theme_color_override("font_color")
	var tween: Tween = create_tween()
	tween.tween_property(button, "scale", Vector2.ONE, 0.08)


func _on_new_game_pressed() -> void:
	if not game_scene_path.is_empty():
		get_tree().change_scene_to_file(game_scene_path)


func _on_tutorial_pressed() -> void:
	if not tutorial_scene_path.is_empty():
		get_tree().change_scene_to_file(tutorial_scene_path)


func _on_guide_pressed() -> void:
	if not guide_scene_path.is_empty():
		get_tree().change_scene_to_file(guide_scene_path)


func _on_settings_pressed() -> void:
	if not settings_scene_path.is_empty():
		get_tree().change_scene_to_file(settings_scene_path)


func _on_quit_pressed() -> void:
	get_tree().quit()
