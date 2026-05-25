extends RefCounted


static func find_tracked_note(tracked_notes: Array, track_type: int, current_time: float, window: float) -> Note:
	var closest_note: Note = null
	var min_time_diff: float = INF

	for note in tracked_notes:
		if note.type != track_type:
			continue

		var time_diff: float = abs(current_time - note.beat_time)
		if time_diff <= window and time_diff < min_time_diff:
			min_time_diff = time_diff
			closest_note = note

	return closest_note


static func find_wrong_tracked_note(tracked_notes: Array, track_type: int, current_time: float, window: float) -> Note:
	var closest_note: Note = null
	var min_time_diff: float = INF

	for note in tracked_notes:
		if note.type == track_type:
			continue

		var time_diff: float = abs(current_time - note.beat_time)
		if time_diff <= window and time_diff < min_time_diff:
			min_time_diff = time_diff
			closest_note = note

	return closest_note


static func has_any_nearby_note(tracked_notes: Array, current_time: float, window: float) -> bool:
	for note in tracked_notes:
		if abs(current_time - note.beat_time) <= window:
			return true

	return false
