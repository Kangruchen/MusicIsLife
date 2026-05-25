extends RefCounted

var beat_times: PackedFloat64Array = PackedFloat64Array()
var beat_input_states: Dictionary = {}
var next_beat_idx: int = 0
var beat_interval: float = 0.0
var input_beats: int = 0
var exit_beats: int = 0


func configure(first_beat_time: float, interval: float, input_count: int, exit_count: int) -> void:
	clear()
	beat_interval = interval
	input_beats = maxi(1, input_count)
	exit_beats = maxi(1, exit_count)
	beat_times.resize(input_beats + exit_beats)
	for i in range(beat_times.size()):
		beat_times[i] = first_beat_time + i * beat_interval


func clear() -> void:
	beat_times.clear()
	beat_input_states.clear()
	next_beat_idx = 0


func advance_due_beats(now: float, callback: Callable) -> void:
	while next_beat_idx < beat_times.size() and now >= beat_times[next_beat_idx]:
		callback.call(next_beat_idx)
		next_beat_idx += 1


func get_input_judge_beat(now: float) -> int:
	if beat_interval <= 0.0:
		return -1
	if beat_times.size() < input_beats:
		return -1

	var best_beat: int = -1
	var best_dist: float = INF
	for i in range(input_beats):
		var dist: float = absf(now - beat_times[i])
		if dist < best_dist:
			best_dist = dist
			best_beat = i + 1

	if best_beat > 0 and best_dist < beat_interval * 0.5:
		return best_beat
	return -1


func get_beat_time(beat_number: int) -> float:
	var index := beat_number - 1
	if index < 0 or index >= beat_times.size():
		return 0.0
	return beat_times[index]


func get_beat_time_by_index(index: int) -> float:
	if index < 0 or index >= beat_times.size():
		return 0.0
	return beat_times[index]


func is_beat_used(beat_number: int) -> bool:
	return bool(beat_input_states.get(beat_number, false))


func set_beat_used(beat_number: int, used: bool = true) -> void:
	beat_input_states[beat_number] = used
