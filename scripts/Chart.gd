extends Resource
class_name Chart

@export var chart_name: String = ""
@export var bpm: float = 120.0

# Runtime beat-0 time in song seconds. For SM files this is -source_offset.
@export var offset: float = 0.0

# Raw offset value from the source chart before project-specific conversion.
@export var source_offset: float = 0.0

@export var notes: Array[Note] = []
@export var laser_patterns: Array = []


func add_note(note: Note) -> void:
	notes.append(note)


func add_laser_pattern(pattern: Resource) -> void:
	laser_patterns.append(pattern)


func sort_notes() -> void:
	notes.sort_custom(func(a: Note, b: Note) -> bool:
		return a.beat_number < b.beat_number
	)


func sort_laser_patterns() -> void:
	for pattern in laser_patterns:
		if pattern != null and pattern.has_method("sort_steps"):
			pattern.sort_steps()
	laser_patterns.sort_custom(func(a: Resource, b: Resource) -> bool:
		return float(a.get("beat_number")) < float(b.get("beat_number"))
	)


func shift_times(offset_delta: float) -> void:
	for note in notes:
		note.beat_time += offset_delta
	for pattern in laser_patterns:
		if pattern != null and pattern.has_method("shift_times"):
			pattern.shift_times(offset_delta)


func get_note_at_beat(beat_num: float) -> Note:
	for note in notes:
		if abs(note.beat_number - beat_num) < 0.001:
			return note
	return null
