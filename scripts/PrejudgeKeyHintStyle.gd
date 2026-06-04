extends RefCounted


static func get_style(note_type: Note.NoteType) -> Dictionary:
	match note_type:
		Note.NoteType.GUARD:
			return _make_style(GameConstants.get_note_action_label(int(note_type), "J"), Color(0.22, 0.56, 0.98, 0.9))
		Note.NoteType.HIT:
			return _make_style(GameConstants.get_note_action_label(int(note_type), "I"), Color(0.95, 0.24, 0.24, 0.9))
		Note.NoteType.DODGE:
			return _make_style(GameConstants.get_note_action_label(int(note_type), "L"), Color(0.20, 0.78, 0.38, 0.9))
		_:
			return _make_style(GameConstants.get_note_action_label(int(note_type), "J"), Color(0.22, 0.56, 0.98, 0.9))


static func _make_style(key_text: String, core_color: Color) -> Dictionary:
	return {
		"key_text": key_text,
		"core_color": core_color,
		"glyph_family": _get_controller_glyph_family()
	}


static func _get_controller_glyph_family() -> String:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return ""

	var gamepad_manager: Node = tree.root.get_node_or_null("GamepadManager")
	if gamepad_manager == null:
		return ""
	if not gamepad_manager.has_method("is_gamepad_active"):
		return ""
	if not bool(gamepad_manager.call("is_gamepad_active")):
		return ""
	if gamepad_manager.has_method("get_controller_icon_family"):
		return String(gamepad_manager.call("get_controller_icon_family"))
	return "playstation"
