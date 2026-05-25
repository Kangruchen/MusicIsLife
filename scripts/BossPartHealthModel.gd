extends RefCounted

const PART_NONE: int = -1
const PART_MIDDLE: int = 0
const PART_LEFT: int = 1
const PART_RIGHT: int = 2

var middle_damage: float = 0.0
var left_damage: float = 0.0
var right_damage: float = 0.0

var middle_threshold: float = 1000.0
var left_threshold: float = 500.0
var right_threshold: float = 500.0


func configure(new_middle_threshold: float, new_left_threshold: float, new_right_threshold: float) -> void:
	middle_threshold = maxf(1.0, new_middle_threshold)
	left_threshold = maxf(1.0, new_left_threshold)
	right_threshold = maxf(1.0, new_right_threshold)


func reset() -> void:
	middle_damage = 0.0
	left_damage = 0.0
	right_damage = 0.0


func is_destroyed(part: int) -> bool:
	if part == PART_MIDDLE:
		return middle_damage >= middle_threshold
	if part == PART_LEFT:
		return left_damage >= left_threshold
	if part == PART_RIGHT:
		return right_damage >= right_threshold
	return false


func apply_damage(part: int, damage: float) -> bool:
	var was_destroyed := is_destroyed(part)
	if part == PART_MIDDLE:
		middle_damage += damage
	elif part == PART_LEFT:
		left_damage += damage
	elif part == PART_RIGHT:
		right_damage += damage
	else:
		return false

	return not was_destroyed and is_destroyed(part)


func set_destroyed_for_debug(part: int, destroyed: bool) -> bool:
	if is_destroyed(part) == destroyed:
		return false

	if part == PART_MIDDLE:
		middle_damage = middle_threshold if destroyed else 0.0
	elif part == PART_LEFT:
		left_damage = left_threshold if destroyed else 0.0
	elif part == PART_RIGHT:
		right_damage = right_threshold if destroyed else 0.0
	else:
		return false

	return true


func are_missile_parts_all_destroyed() -> bool:
	return is_destroyed(PART_LEFT) and is_destroyed(PART_RIGHT)
