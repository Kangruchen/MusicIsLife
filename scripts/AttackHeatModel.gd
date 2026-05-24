extends RefCounted

var heat_counter: int = 0
var heat_level: int = 0


func reset() -> void:
	heat_counter = 0
	heat_level = 0


func record_light_result(is_perfect: bool) -> void:
	if is_perfect:
		heat_counter += 1
		if heat_counter >= GameConstants.PERFECTS_PER_LEVEL:
			heat_counter = 0
			heat_level = mini(heat_level + 1, GameConstants.MAX_HEAT_LEVEL)
	else:
		heat_counter = 0
		if heat_level > 0:
			heat_level -= 1


func consume_heavy_heat() -> int:
	var consumed_heat := heat_level
	reset()
	return consumed_heat
