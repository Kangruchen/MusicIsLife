extends RefCounted


static func collect_resolved_notes(
	tracked_notes: Array[Note],
	current_time: float,
	miss_threshold: float,
	should_drop_note: Callable
) -> Dictionary:
	var dropped_notes: Array[Note] = []
	var missed_notes: Array[Note] = []

	for note in tracked_notes:
		if note == null:
			continue
		if should_drop_note.is_valid() and bool(should_drop_note.call(note)):
			dropped_notes.append(note)
			continue
		if current_time - note.beat_time >= miss_threshold:
			missed_notes.append(note)

	return {
		"dropped_notes": dropped_notes,
		"missed_notes": missed_notes
	}
