extends RefCounted

const SIDE_NONE: int = -1
const SIDE_LEFT: int = 0
const SIDE_RIGHT: int = 1

var _origin_nodes: Dictionary = {}
var _origin_positions: Dictionary = {}
var _tweens: Dictionary = {}


func cache_origin(side: int, recoil_node: Node2D) -> void:
	if side == SIDE_NONE or recoil_node == null:
		return
	if _origin_nodes.get(side) == recoil_node:
		return
	_origin_nodes[side] = recoil_node
	_origin_positions[side] = recoil_node.position


func get_origin(side: int, fallback_position: Vector2) -> Vector2:
	if side == SIDE_NONE:
		return fallback_position
	return _origin_positions.get(side, fallback_position)


func set_tween(side: int, tween: Tween) -> void:
	if side == SIDE_NONE:
		return
	_tweens[side] = tween


func kill_tween(side: int) -> void:
	if side == SIDE_NONE:
		return
	var tween: Tween = _tweens.get(side) as Tween
	if tween != null:
		tween.kill()
	_tweens.erase(side)


func clear_tween(side: int) -> void:
	if side == SIDE_NONE:
		return
	_tweens.erase(side)


func reset_side(side: int) -> void:
	if side == SIDE_NONE:
		return
	kill_tween(side)
	var origin_node: Node2D = _origin_nodes.get(side) as Node2D
	if origin_node != null and is_instance_valid(origin_node):
		origin_node.position = get_origin(side, origin_node.position)
