extends RefCounted

const PERFECT: int = 0
const GREAT: int = 1
const GOOD: int = 2
const MISS: int = 3


static func good_window() -> float:
	return GameConstants.GOOD_WINDOW


static func calculate(time_diff: float) -> int:
	if time_diff < GameConstants.PERFECT_WINDOW:
		return PERFECT
	if time_diff < GameConstants.GREAT_WINDOW:
		return GREAT
	if time_diff < GameConstants.GOOD_WINDOW:
		return GOOD
	return MISS


static func get_text(judgment: int) -> String:
	match judgment:
		PERFECT:
			return "PERFECT"
		GREAT:
			return "GREAT"
		GOOD:
			return "GOOD"
		MISS:
			return "MISS"
		_:
			return "UNKNOWN"


static func get_color(judgment: int) -> Color:
	match judgment:
		PERFECT:
			return Color(1.0, 0.84, 0.0)
		GREAT:
			return Color(0.0, 1.0, 0.5)
		GOOD:
			return Color(0.5, 0.5, 1.0)
		MISS:
			return Color(0.7, 0.7, 0.7)
		_:
			return Color.WHITE
