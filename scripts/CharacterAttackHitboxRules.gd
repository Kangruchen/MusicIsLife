extends RefCounted

const ATTACK_TYPE_LIGHT: int = 0
const ATTACK_TYPE_HEAVY: int = 1


static func get_open_frame(
	attack_type: int,
	is_charged: bool,
	light_frame: int,
	heavy_frame: int,
	charged_light_frame: int,
	charged_heavy_frame: int
) -> int:
	if attack_type == ATTACK_TYPE_LIGHT:
		return charged_light_frame if is_charged else light_frame
	if attack_type == ATTACK_TYPE_HEAVY:
		return charged_heavy_frame if is_charged else heavy_frame
	return 999


static func get_close_frame(
	attack_type: int,
	is_charged: bool,
	light_frame: int,
	heavy_frame: int,
	charged_light_frame: int,
	charged_heavy_frame: int
) -> int:
	if attack_type == ATTACK_TYPE_LIGHT:
		return charged_light_frame if is_charged else light_frame
	if attack_type == ATTACK_TYPE_HEAVY:
		return charged_heavy_frame if is_charged else heavy_frame
	return 1000


static func get_preset_name(
	attack_type: int,
	is_charged: bool,
	light_preset_name: StringName,
	heavy_preset_name: StringName,
	charged_light_preset_name: StringName,
	charged_heavy_preset_name: StringName
) -> StringName:
	if attack_type == ATTACK_TYPE_LIGHT:
		if is_charged and not charged_light_preset_name.is_empty():
			return charged_light_preset_name
		return light_preset_name
	if attack_type == ATTACK_TYPE_HEAVY:
		if is_charged and not charged_heavy_preset_name.is_empty():
			return charged_heavy_preset_name
		return heavy_preset_name
	return light_preset_name


static func get_default_offset(attack_type: int) -> Vector2:
	if attack_type == ATTACK_TYPE_HEAVY:
		return Vector2(105.0, 0.0)
	return Vector2(90.0, 0.0)


static func get_default_size(attack_type: int) -> Vector2:
	if attack_type == ATTACK_TYPE_HEAVY:
		return Vector2(180.0, 120.0)
	return Vector2(120.0, 90.0)
