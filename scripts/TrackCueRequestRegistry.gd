extends RefCounted

var _missile_notes: Array[Note] = []
var _charge_notes: Array[Note] = []


func clear() -> void:
	_missile_notes.clear()
	_charge_notes.clear()


func erase(note: Note) -> void:
	if note == null:
		return
	_missile_notes.erase(note)
	_charge_notes.erase(note)


func has_missile_request(note: Note) -> bool:
	return _missile_notes.has(note)


func mark_missile_request(note: Note) -> void:
	if note == null or _missile_notes.has(note):
		return
	_missile_notes.append(note)


func has_charge_request(note: Note) -> bool:
	return _charge_notes.has(note)


func mark_charge_request(note: Note) -> void:
	if note == null or _charge_notes.has(note):
		return
	_charge_notes.append(note)
