extends RefCounted

const SIDE_LEFT: int = 0
const SIDE_RIGHT: int = 1

var _side_by_note: Dictionary = {}
var _next_side: int = SIDE_LEFT


func clear() -> void:
	_side_by_note.clear()
	_next_side = SIDE_LEFT


func assign_notes(notes: Array) -> void:
	clear()
	for note in notes:
		append_note(note)


func append_note(note: Note) -> void:
	if note == null or note.type != Note.NoteType.HIT:
		return
	_side_by_note[note] = _next_side
	_next_side = SIDE_RIGHT if _next_side == SIDE_LEFT else SIDE_LEFT


func get_side(note: Note) -> int:
	return int(_side_by_note.get(note, SIDE_LEFT))


func erase(note: Note) -> void:
	if note == null:
		return
	_side_by_note.erase(note)
