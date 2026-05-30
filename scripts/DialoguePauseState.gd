extends RefCounted

var previous_tree_paused: bool = false
var previous_ui_process_mode: int = Node.PROCESS_MODE_INHERIT
var previous_layer_process_mode: int = Node.PROCESS_MODE_INHERIT
var _has_layer_state: bool = false


func enter(tree: SceneTree, dialogue_ui: Node) -> void:
	if tree == null or dialogue_ui == null:
		return

	previous_tree_paused = tree.paused
	previous_ui_process_mode = dialogue_ui.process_mode
	dialogue_ui.process_mode = Node.PROCESS_MODE_ALWAYS

	var dialogue_layer: Node = dialogue_ui.get_parent()
	_has_layer_state = dialogue_layer != null
	if _has_layer_state:
		previous_layer_process_mode = dialogue_layer.process_mode
		dialogue_layer.process_mode = Node.PROCESS_MODE_ALWAYS

	tree.paused = true


func exit(tree: SceneTree, dialogue_ui: Node) -> void:
	if tree != null:
		tree.paused = previous_tree_paused

	if dialogue_ui == null or not is_instance_valid(dialogue_ui):
		_has_layer_state = false
		return

	dialogue_ui.process_mode = previous_ui_process_mode
	var dialogue_layer: Node = dialogue_ui.get_parent()
	if _has_layer_state and dialogue_layer != null:
		dialogue_layer.process_mode = previous_layer_process_mode
	_has_layer_state = false
