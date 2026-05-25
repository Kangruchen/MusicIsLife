extends RefCounted


static func pick(
	current_position: Vector2,
	player_position: Vector2,
	spawn_position: Vector2,
	max_move_left: float,
	max_move_right: float,
	max_move_up: float,
	max_move_down: float,
	distance_from_player: float,
	pick_attempts: int
) -> Dictionary:
	var radius: float = maxf(1.0, distance_from_player)
	var sample_count: int = maxi(96, pick_attempts)
	var best_ring_target: Vector2 = Vector2.ZERO
	var best_ring_distance: float = INF
	var found_ring_target: bool = false

	for i in range(sample_count):
		var angle: float = (TAU * float(i)) / float(sample_count)
		var candidate: Vector2 = player_position + Vector2.RIGHT.rotated(angle) * radius
		if not _is_within_move_area(candidate, spawn_position, max_move_left, max_move_right, max_move_up, max_move_down):
			continue

		var travel_distance: float = current_position.distance_to(candidate)
		if travel_distance < best_ring_distance:
			best_ring_distance = travel_distance
			best_ring_target = candidate
			found_ring_target = true

	if found_ring_target:
		return {
			"found_on_ring": true,
			"target": best_ring_target
		}

	return {
		"found_on_ring": false,
		"target": _clamp_to_move_area(player_position, spawn_position, max_move_left, max_move_right, max_move_up, max_move_down)
	}


static func _clamp_to_move_area(
	value: Vector2,
	spawn_position: Vector2,
	max_move_left: float,
	max_move_right: float,
	max_move_up: float,
	max_move_down: float
) -> Vector2:
	return Vector2(
		clampf(value.x, spawn_position.x - max_move_left, spawn_position.x + max_move_right),
		clampf(value.y, spawn_position.y - max_move_up, spawn_position.y + max_move_down)
	)


static func _is_within_move_area(
	candidate: Vector2,
	spawn_position: Vector2,
	max_move_left: float,
	max_move_right: float,
	max_move_up: float,
	max_move_down: float
) -> bool:
	var clamped_candidate: Vector2 = _clamp_to_move_area(
		candidate,
		spawn_position,
		max_move_left,
		max_move_right,
		max_move_up,
		max_move_down
	)
	return candidate.is_equal_approx(clamped_candidate)
