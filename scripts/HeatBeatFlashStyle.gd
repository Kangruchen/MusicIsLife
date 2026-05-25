extends RefCounted


static func get_style(heat_level: int, is_level_up: bool) -> Dictionary:
	match heat_level:
		1:
			return _make_style(Color(1.0, 0.65, 0.0), 0.35 if is_level_up else 0.15, 0.06, 0.18, 0.6, 0.4)
		2:
			return _make_style(Color(1.0, 0.4, 0.0), 0.45 if is_level_up else 0.20, 0.10, 0.28, 0.45, 0.9)
		3:
			return _make_style(Color(1.0, 0.2, 0.0), 0.55 if is_level_up else 0.25, 0.14, 0.38, 0.3, 1.4)
		4:
			return _make_style(Color(1.0, 0.0, 0.0), 0.65 if is_level_up else 0.30, 0.18, 0.48, 0.18, 2.0)
		_:
			return {}


static func _make_style(
	flash_color: Color,
	flash_alpha: float,
	pulse_low: float,
	pulse_high: float,
	pulse_period: float,
	shake_intensity: float
) -> Dictionary:
	return {
		"flash_color": flash_color,
		"flash_alpha": flash_alpha,
		"pulse_low": pulse_low,
		"pulse_high": pulse_high,
		"pulse_period": pulse_period,
		"shake_intensity": shake_intensity
	}
