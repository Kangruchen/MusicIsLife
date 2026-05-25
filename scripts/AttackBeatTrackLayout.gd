extends RefCounted


static func build(
	screen_width: float,
	width_ratio: float,
	input_beats: int,
	beat_interval: float,
	perfect_window: float
) -> Dictionary:
	if screen_width <= 0.0 or width_ratio <= 0.0 or input_beats <= 0 or beat_interval <= 0.0:
		return {}

	var track_width: float = screen_width * width_ratio
	var segment_width: float = track_width / float(input_beats)
	var perfect_ratio: float = perfect_window / beat_interval
	var perfect_width: float = segment_width * perfect_ratio
	var miss_side_width: float = (segment_width - perfect_width) / 2.0

	return {
		"track_width": track_width,
		"segment_width": segment_width,
		"perfect_width": perfect_width,
		"miss_side_width": miss_side_width
	}


static func get_cursor_x(now: float, first_beat_time: float, beat_interval: float, segment_width: float) -> float:
	if beat_interval <= 0.0:
		return 0.0
	return (now - first_beat_time + beat_interval * 0.5) / beat_interval * segment_width


static func is_cursor_visible(cursor_x: float, track_width: float, segment_width: float) -> bool:
	return cursor_x >= -segment_width and cursor_x <= track_width + segment_width
