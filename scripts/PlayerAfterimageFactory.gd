extends RefCounted


static func create_from_sprite(
	player_sprite: AnimatedSprite2D,
	group_name: StringName,
	base_color: Color,
	alpha: float
) -> Sprite2D:
	if player_sprite == null:
		return null
	if player_sprite.sprite_frames == null:
		return null
	if not player_sprite.sprite_frames.has_animation(player_sprite.animation):
		return null

	var frame_texture: Texture2D = player_sprite.sprite_frames.get_frame_texture(player_sprite.animation, player_sprite.frame)
	if frame_texture == null:
		return null

	var ghost: Sprite2D = Sprite2D.new()
	ghost.texture = frame_texture
	ghost.centered = player_sprite.centered
	ghost.offset = player_sprite.offset
	ghost.flip_h = player_sprite.flip_h
	ghost.flip_v = player_sprite.flip_v
	ghost.global_transform = player_sprite.global_transform
	ghost.add_to_group(group_name)

	var color: Color = base_color
	color.a = alpha
	ghost.modulate = color
	return ghost
