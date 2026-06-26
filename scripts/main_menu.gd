extends Control
class_name MainMenu

const MENU_HINT_FONT: FontFile = preload("res://assets/UI/Orbitron-VariableFont_wght.ttf")

@onready var new_game_btn: Button = $CenterContainer/MenuVBox/NewGameBtn
@onready var main_menu_container: CenterContainer = $CenterContainer
@onready var new_game_choice_overlay: Control = $NewGameChoiceOverlay
@onready var new_game_choice_title: Label = $NewGameChoiceOverlay/ChoiceCenter/ChoiceVBox/ChoiceTitle
@onready var start_with_tutorial_btn: Button = $NewGameChoiceOverlay/ChoiceCenter/ChoiceVBox/ChoiceHBox/StartWithTutorialBtn
@onready var skip_tutorial_btn: Button = $NewGameChoiceOverlay/ChoiceCenter/ChoiceVBox/ChoiceHBox/SkipTutorialBtn
@onready var guide_btn: Button = $CenterContainer/MenuVBox/GuideBtn
@onready var settings_btn: Button = $CenterContainer/MenuVBox/SettingsBtn
@onready var quit_btn: Button = $CenterContainer/MenuVBox/QuitBtn

const MENU_HINT_TEXT_COLOR: Color = Color(0.92, 0.92, 0.86, 0.92)
const MENU_HINT_ACCENT_COLOR: Color = Color(1.0, 0.78, 0.18, 1.0)

@export_file("*.tscn") var game_scene_path: String = "res://scenes/Main.tscn"
@export_file("*.tscn") var tutorial_scene_path: String = "res://scenes/tutorial.tscn"
@export_file("*.tscn") var guide_scene_path: String = "res://scenes/guide.tscn"
@export_file("*.tscn") var settings_scene_path: String = "res://scenes/settings.tscn"

var _menu_buttons: Array[Button] = []
var _main_menu_buttons: Array[Button] = []
var _menu_input_hint: RichTextLabel = null
var _is_new_game_choice_open: bool = false


func _ready() -> void:
	_main_menu_buttons = [new_game_btn, guide_btn, settings_btn, quit_btn]
	_menu_buttons = _main_menu_buttons.duplicate()
	_set_new_game_choice_open(false)

	new_game_btn.pressed.connect(_on_new_game_pressed)
	start_with_tutorial_btn.pressed.connect(_on_start_with_tutorial_pressed)
	skip_tutorial_btn.pressed.connect(_on_skip_tutorial_pressed)
	guide_btn.pressed.connect(_on_guide_pressed)
	settings_btn.pressed.connect(_on_settings_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)

	_setup_focus_navigation()
	_create_menu_input_hint()
	_connect_gamepad_prompt_updates()
	_connect_localization_updates()
	_apply_translations()
	call_deferred("_focus_first_button")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _is_new_game_choice_open:
			_hide_new_game_choice()
			return
		_on_quit_pressed()


func _setup_focus_navigation() -> void:
	if _menu_buttons.is_empty():
		return

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
		button.focus_neighbor_left = button.get_path_to(previous_button)
		button.focus_neighbor_right = button.get_path_to(next_button)


func _focus_first_button() -> void:
	if new_game_btn != null and is_instance_valid(new_game_btn):
		new_game_btn.grab_focus()


func _focus_first_new_game_choice() -> void:
	if start_with_tutorial_btn != null and is_instance_valid(start_with_tutorial_btn):
		start_with_tutorial_btn.grab_focus()


func _create_menu_input_hint() -> void:
	_menu_input_hint = RichTextLabel.new()
	_menu_input_hint.name = "MenuInputHint"
	_menu_input_hint.bbcode_enabled = true
	_menu_input_hint.fit_content = true
	_menu_input_hint.scroll_active = false
	_menu_input_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_input_hint.anchor_left = 0.0
	_menu_input_hint.anchor_top = 1.0
	_menu_input_hint.anchor_right = 1.0
	_menu_input_hint.anchor_bottom = 1.0
	_menu_input_hint.offset_left = 24.0
	_menu_input_hint.offset_top = -74.0
	_menu_input_hint.offset_right = -380.0
	_menu_input_hint.offset_bottom = -18.0
	_menu_input_hint.add_theme_font_override("normal_font", MENU_HINT_FONT)
	_menu_input_hint.add_theme_font_size_override("normal_font_size", 14)
	_menu_input_hint.add_theme_color_override("default_color", MENU_HINT_TEXT_COLOR)
	add_child(_menu_input_hint)
	_update_menu_input_hint()


func _connect_gamepad_prompt_updates() -> void:
	var gamepad_manager: Node = get_node_or_null("/root/GamepadManager")
	if gamepad_manager == null:
		return
	if gamepad_manager.has_signal("input_scheme_changed"):
		gamepad_manager.connect("input_scheme_changed", func(_is_gamepad: bool) -> void:
			_update_menu_input_hint()
		)
	if gamepad_manager.has_signal("controller_icon_family_changed"):
		gamepad_manager.connect("controller_icon_family_changed", func(_family: String) -> void:
			_update_menu_input_hint()
		)


func _connect_localization_updates() -> void:
	var localization_manager: Node = get_node_or_null("/root/LocalizationManager")
	if localization_manager == null or not localization_manager.has_signal("locale_changed"):
		return
	localization_manager.connect("locale_changed", func(_locale: String) -> void:
		_apply_translations()
	)


func _apply_translations() -> void:
	new_game_btn.text = tr("MENU_NEW_GAME")
	guide_btn.text = tr("MENU_GUIDE")
	settings_btn.text = tr("MENU_SETTINGS")
	quit_btn.text = tr("MENU_QUIT")
	new_game_choice_title.text = tr("MENU_NEW_GAME")
	start_with_tutorial_btn.text = tr("MENU_PLAY_TUTORIAL")
	skip_tutorial_btn.text = tr("MENU_SKIP_TUTORIAL")
	_update_menu_input_hint()


func _update_menu_input_hint() -> void:
	if _menu_input_hint == null:
		return
	var confirm_prompt: String = GameConstants.get_action_key_label("ui_accept", "Enter")
	var cancel_prompt: String = GameConstants.get_action_key_label("ui_cancel", "Esc")
	_menu_input_hint.text = "[color=%s]%s[/color]  %s\n[color=%s]%s[/color]  %s" % [
		"#" + MENU_HINT_ACCENT_COLOR.to_html(false),
		confirm_prompt,
		tr("INPUT_CONFIRM"),
		"#" + MENU_HINT_ACCENT_COLOR.to_html(false),
		cancel_prompt,
		tr("INPUT_CANCEL"),
	]


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
	_rumble_ui(&"ui_confirm")
	_show_new_game_choice()


func _on_start_with_tutorial_pressed() -> void:
	_rumble_ui(&"ui_confirm")
	if not tutorial_scene_path.is_empty():
		get_tree().change_scene_to_file(tutorial_scene_path)


func _on_skip_tutorial_pressed() -> void:
	_rumble_ui(&"ui_confirm")
	if not game_scene_path.is_empty():
		get_tree().change_scene_to_file(game_scene_path)


func _on_guide_pressed() -> void:
	_rumble_ui(&"ui_confirm")
	if not guide_scene_path.is_empty():
		get_tree().change_scene_to_file(guide_scene_path)


func _on_settings_pressed() -> void:
	_rumble_ui(&"ui_confirm")
	if not settings_scene_path.is_empty():
		get_tree().change_scene_to_file(settings_scene_path)


func _on_quit_pressed() -> void:
	_rumble_ui(&"ui_back")
	get_tree().quit()


func _rumble_ui(preset: StringName) -> void:
	var gamepad_manager: Node = get_node_or_null("/root/GamepadManager")
	if gamepad_manager != null and gamepad_manager.has_method("rumble"):
		gamepad_manager.call("rumble", preset)


func _show_new_game_choice() -> void:
	_set_new_game_choice_open(true)
	_menu_buttons = [start_with_tutorial_btn, skip_tutorial_btn]
	_setup_focus_navigation()
	call_deferred("_focus_first_new_game_choice")


func _hide_new_game_choice() -> void:
	_set_new_game_choice_open(false)
	_menu_buttons = _main_menu_buttons.duplicate()
	_setup_focus_navigation()
	call_deferred("_focus_first_button")


func _set_new_game_choice_open(is_open: bool) -> void:
	_is_new_game_choice_open = is_open
	main_menu_container.visible = not is_open
	new_game_choice_overlay.visible = is_open
