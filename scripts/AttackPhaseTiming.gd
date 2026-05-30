extends RefCounted


static func build(
	beat_interval: float,
	countdown_beats_value: int,
	input_beats_value: int,
	exit_beats_value: int
) -> Dictionary:
	var countdown_beats: int = maxi(1, countdown_beats_value)
	var input_beats: int = maxi(1, input_beats_value)
	var exit_beats: int = maxi(1, exit_beats_value)
	var total_beats: int = countdown_beats + input_beats + exit_beats
	var safe_beat_interval: float = maxf(0.0, beat_interval)

	return {
		"beat_interval": safe_beat_interval,
		"countdown_beats": countdown_beats,
		"input_beats": input_beats,
		"exit_beats": exit_beats,
		"total_beats": total_beats,
		"countdown_duration": safe_beat_interval * float(countdown_beats),
		"input_duration": safe_beat_interval * float(input_beats),
		"exit_duration": safe_beat_interval * float(exit_beats),
		"total_duration": safe_beat_interval * float(total_beats)
	}
