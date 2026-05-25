extends RefCounted


static func find_visible_note(active_notes: Array, track_type: int, current_time: float, window: float) -> NoteVisual:
	var closest_note: NoteVisual = null
	var min_time_diff: float = INF

	for note_visual in active_notes:
		if not note_visual or not is_instance_valid(note_visual):
			continue
		if note_visual.note_data.type != track_type:
			continue
		if not note_visual.is_active:
			continue

		var time_diff: float = abs(current_time - note_visual.target_time)
		if time_diff <= window and time_diff < min_time_diff:
			min_time_diff = time_diff
			closest_note = note_visual

	return closest_note


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


static func has_any_nearby_note(active_notes: Array, tracked_notes: Array, current_time: float, window: float) -> bool:
	for note_visual in active_notes:
		if not note_visual or not is_instance_valid(note_visual):
			continue
		if not note_visual.is_active:
			continue
		if abs(current_time - note_visual.target_time) <= window:
			return true

	for note in tracked_notes:
		if abs(current_time - note.beat_time) <= window:
			return true

	return false
