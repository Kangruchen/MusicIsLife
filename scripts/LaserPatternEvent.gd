extends Resource
class_name LaserPatternEvent

enum PatternKind {
	ECHO,
	CHORD
}

@export var kind: PatternKind = PatternKind.ECHO
@export var source_layer: String = ""
@export var beat_number: float = 0.0
@export var beat_time: float = 0.0

var warning_steps: Array[Dictionary] = []
var fire_steps: Array[Dictionary] = []


func add_warning_step(step_beat_number: float, step_beat_time: float, slot_index: int) -> void:
	warning_steps.append(_make_step(step_beat_number, step_beat_time, slot_index))


func add_fire_step(step_beat_number: float, step_beat_time: float, slot_index: int) -> void:
	fire_steps.append(_make_step(step_beat_number, step_beat_time, slot_index))


func sort_steps() -> void:
	warning_steps.sort_custom(_sort_step_by_time)
	fire_steps.sort_custom(_sort_step_by_time)


func shift_times(offset_delta: float) -> void:
	beat_time += offset_delta
	for step in warning_steps:
		step["beat_time"] = float(step["beat_time"]) + offset_delta
	for step in fire_steps:
		step["beat_time"] = float(step["beat_time"]) + offset_delta


func _make_step(step_beat_number: float, step_beat_time: float, slot_index: int) -> Dictionary:
	return {
		"beat_number": step_beat_number,
		"beat_time": step_beat_time,
		"slot_index": slot_index,
		"source_layer": source_layer
	}


func _sort_step_by_time(a: Dictionary, b: Dictionary) -> bool:
	return float(a["beat_time"]) < float(b["beat_time"])
