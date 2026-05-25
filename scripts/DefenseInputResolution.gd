extends RefCounted

const DefenseNoteSearch := preload("res://scripts/DefenseNoteSearch.gd")

const KIND_TRACKED_NOTE: int = 0
const KIND_WRONG_NOTE: int = 1
const KIND_EMPTY_IGNORED: int = 2
const KIND_EMPTY_MISS: int = 3


static func resolve(
	tracked_notes: Array,
	track_type: int,
	current_time: float,
	good_window: float,
	ignore_empty_press_without_nearby_notes: bool,
	empty_press_note_check_window: float
) -> Dictionary:
	var closest_tracked: Note = DefenseNoteSearch.find_tracked_note(
		tracked_notes,
		track_type,
		current_time,
		good_window
	)
	if closest_tracked != null:
		var timing_diff: float = current_time - closest_tracked.beat_time
		return {
			"kind": KIND_TRACKED_NOTE,
			"note": closest_tracked,
			"timing_diff": timing_diff,
			"abs_diff": abs(timing_diff)
		}

	var wrong_note: Note = DefenseNoteSearch.find_wrong_tracked_note(
		tracked_notes,
		track_type,
		current_time,
		good_window
	)
	if wrong_note != null:
		return {
			"kind": KIND_WRONG_NOTE,
			"note": wrong_note
		}

	if ignore_empty_press_without_nearby_notes:
		var has_nearby_note := DefenseNoteSearch.has_any_nearby_note(
			tracked_notes,
			current_time,
			empty_press_note_check_window
		)
		if not has_nearby_note:
			return {
				"kind": KIND_EMPTY_IGNORED
			}

	return {
		"kind": KIND_EMPTY_MISS
	}
