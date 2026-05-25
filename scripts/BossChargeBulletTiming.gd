extends RefCounted


static func are_frame_markers_valid(
	fire_frame: int,
	move_start_frame: int,
	hit_frame: int,
	despawn_frame: int
) -> bool:
	if move_start_frame < fire_frame:
		return false
	if hit_frame <= move_start_frame:
		return false
	if despawn_frame <= hit_frame:
		return false
	return true


static func get_phase_duration(
	timing_sprite: AnimatedSprite2D,
	requested_animation_name: StringName,
	from_frame: int,
	to_frame_exclusive: int,
	fallback_duration: float
) -> float:
	if to_frame_exclusive <= from_frame:
		return 0.0
	if timing_sprite == null or timing_sprite.sprite_frames == null:
		return fallback_duration

	var anim_name: StringName = _resolve_animation_name(timing_sprite.sprite_frames, requested_animation_name)
	if anim_name.is_empty():
		return fallback_duration

	var anim_text: String = String(anim_name)
	var frame_count: int = timing_sprite.sprite_frames.get_frame_count(anim_text)
	if frame_count <= 0:
		return fallback_duration

	var clamped_from_frame: int = clampi(from_frame, 0, frame_count - 1)
	var clamped_to_frame_exclusive: int = clampi(to_frame_exclusive, 0, frame_count)
	if clamped_to_frame_exclusive <= clamped_from_frame:
		return 0.0

	var base_fps: float = timing_sprite.sprite_frames.get_animation_speed(anim_text)
	if base_fps <= 0.0:
		return fallback_duration

	var units: float = 0.0
	for i in range(clamped_from_frame, clamped_to_frame_exclusive):
		units += timing_sprite.sprite_frames.get_frame_duration(anim_text, i)

	var base_duration: float = units / base_fps
	var speed_scale: float = maxf(0.01, timing_sprite.speed_scale)
	return maxf(0.0, base_duration / speed_scale)


static func _resolve_animation_name(sprite_frames: SpriteFrames, requested_animation_name: StringName) -> StringName:
	if sprite_frames == null:
		return StringName()
	if sprite_frames.has_animation(requested_animation_name):
		return requested_animation_name
	if sprite_frames.has_animation(&"default"):
		return &"default"
	return StringName()
