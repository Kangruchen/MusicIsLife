extends RefCounted

const SIDE_NONE: int = -1
const SIDE_LEFT: int = 0
const SIDE_RIGHT: int = 1

var turn_index: int = 0
var forced_sides: Array[int] = []


func clear_forced_sides() -> void:
	forced_sides.clear()


func get_next_turn_side() -> int:
	return SIDE_LEFT if (turn_index % 2 == 0) else SIDE_RIGHT


func consume_turn() -> void:
	turn_index += 1


func enqueue_forced_side(side: int) -> void:
	if side != SIDE_LEFT and side != SIDE_RIGHT:
		return
	forced_sides.append(side)


func pick_launch_side(left_available: bool, right_available: bool) -> int:
	if not forced_sides.is_empty():
		var forced_side: int = int(forced_sides.pop_front())
		return _side_if_available(forced_side, left_available, right_available)

	var launch_side: int = get_next_turn_side()
	consume_turn()
	return _side_if_available(launch_side, left_available, right_available)


func _side_if_available(side: int, left_available: bool, right_available: bool) -> int:
	if side == SIDE_LEFT and left_available:
		return SIDE_LEFT
	if side == SIDE_RIGHT and right_available:
		return SIDE_RIGHT
	return SIDE_NONE
