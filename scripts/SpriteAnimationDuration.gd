extends RefCounted


static func get_duration(sprite_frames: SpriteFrames, anim_name: String, from_frame: int = 0, to_frame: int = -1) -> float:
	if sprite_frames == null:
		return 0.0
	if anim_name.is_empty() or not sprite_frames.has_animation(anim_name):
		return 0.0

	var frame_count: int = sprite_frames.get_frame_count(anim_name)
	var base_fps: float = sprite_frames.get_animation_speed(anim_name)
	if frame_count <= 0 or base_fps <= 0.0:
		return 0.0

	var from_idx: int = maxi(0, from_frame)
	if from_idx >= frame_count:
		return 0.0

	var to_idx: int = frame_count - 1
	if to_frame >= 0:
		to_idx = mini(to_frame, frame_count - 1)
	if to_idx < from_idx:
		return 0.0

	var total_units: float = 0.0
	for i in range(from_idx, to_idx + 1):
		total_units += sprite_frames.get_frame_duration(anim_name, i)

	return total_units / base_fps
