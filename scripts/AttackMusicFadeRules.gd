extends RefCounted


static func base_fade_seconds(legacy_fade_seconds: float, base_fade_seconds_value: float) -> float:
	return maxf(legacy_fade_seconds, base_fade_seconds_value)


static func segment_crossfade_seconds(
	legacy_fade_seconds: float,
	segment_crossfade_seconds_value: float,
	segment_crossfade_beats: float,
	beat_interval: float
) -> float:
	var beat_fade: float = _beats_to_seconds(segment_crossfade_beats, beat_interval)
	return maxf(maxf(legacy_fade_seconds, segment_crossfade_seconds_value), beat_fade)


static func return_fade_seconds(legacy_fade_seconds: float, return_fade_seconds_value: float) -> float:
	return maxf(legacy_fade_seconds, return_fade_seconds_value)


static func base_crossfade_seconds(
	legacy_fade_seconds: float,
	base_fade_seconds_value: float,
	base_crossfade_beats: float,
	intro_delay_beats: float,
	beat_interval: float
) -> float:
	var beat_fade: float = _beats_to_seconds(base_crossfade_beats, beat_interval)
	var intro_delay_fade: float = _beats_to_seconds(intro_delay_beats, beat_interval)
	return maxf(maxf(base_fade_seconds(legacy_fade_seconds, base_fade_seconds_value), beat_fade), intro_delay_fade)


static func intro_fade_seconds(base_crossfade_seconds_value: float, segment_crossfade_seconds_value: float, available_seconds: float) -> float:
	var available: float = maxf(0.0, available_seconds)
	if available <= 0.0:
		return segment_crossfade_seconds_value
	return minf(base_crossfade_seconds_value, maxf(segment_crossfade_seconds_value, available))


static func return_crossfade_seconds(
	legacy_fade_seconds: float,
	return_fade_seconds_value: float,
	return_crossfade_beats: float,
	beat_interval: float
) -> float:
	var beat_fade: float = _beats_to_seconds(return_crossfade_beats, beat_interval)
	return maxf(return_fade_seconds(legacy_fade_seconds, return_fade_seconds_value), beat_fade)


static func clamp_return_restore_seconds(remaining_outro_seconds: float, return_crossfade_seconds_value: float) -> float:
	var remaining: float = maxf(0.0, remaining_outro_seconds)
	if remaining <= 0.0:
		return 0.0
	return minf(remaining, maxf(0.0, return_crossfade_seconds_value))


static func _beats_to_seconds(beats: float, beat_interval: float) -> float:
	return maxf(0.0, beats) * maxf(0.0, beat_interval)
