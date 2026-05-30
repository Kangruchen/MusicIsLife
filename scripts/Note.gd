extends Resource
class_name Note

enum NoteType {
	GUARD,
	HIT,
	DODGE
}

@export var beat_time: float = 0.0
@export var beat_number: float = 0.0
@export var type: NoteType = NoteType.HIT
@export var slot_index: int = -1
@export var source_layer: String = ""


func get_type_string() -> String:
	match type:
		NoteType.GUARD:
			return "GUARD"
		NoteType.HIT:
			return "HIT"
		NoteType.DODGE:
			return "DODGE"
		_:
			return "UNKNOWN"
