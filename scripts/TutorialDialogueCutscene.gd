extends Node
class_name TutorialDialogueCutscene

signal finished

@export_group("Nodes")
@export var player_node: Node2D
@export var speaker_sprite: Sprite2D
@export var player_sprite: Sprite2D
@export var audio_player: AudioStreamPlayer

@export_group("Player Binding")
@export var attach_sprites_to_player: bool = true
@export var player_anchor_path: NodePath = NodePath("CharacterVisual")
@export var hide_existing_player_visual: bool = true
@export var existing_player_visual_path: NodePath = NodePath("CharacterVisual/AnimatedSprite2D")
@export var freeze_player_during_cutscene: bool = true
@export var speaker_local_position: Vector2 = Vector2(0, -80)
@export var player_local_position: Vector2 = Vector2.ZERO

@export_group("Assets")
@export var speaker_frames: Array[Texture2D] = []
@export var player_frames: Array[Texture2D] = []
@export var sound_effect: AudioStream

@export_group("Timing")
@export_range(1.0, 60.0, 1.0) var speaker_fps: float = 12.0
@export_range(1.0, 60.0, 1.0) var player_fps: float = 6.0
@export var wait_for_sound_to_finish: bool = true
@export var hide_sprites_when_finished: bool = true

var _is_playing: bool = false
var _previous_player_input_process: bool = true
var _previous_player_visual_visible: bool = true


func play() -> void:
	if _is_playing:
		return

	_is_playing = true
	_prepare_player_state()
	_attach_sprites_to_player()
	_show_first_frames()

	if audio_player != null and sound_effect != null:
		audio_player.stream = sound_effect
		audio_player.play()

	var speaker_time: float = _get_animation_seconds(speaker_frames, speaker_fps)
	var player_time: float = _get_animation_seconds(player_frames, player_fps)
	var animation_time: float = maxf(speaker_time, player_time)

	var speaker_tween: Tween = _play_frame_sequence(speaker_sprite, speaker_frames, speaker_fps)
	var player_tween: Tween = _play_frame_sequence(player_sprite, player_frames, player_fps)

	if animation_time > 0.0:
		await get_tree().create_timer(animation_time).timeout
	if wait_for_sound_to_finish and audio_player != null and audio_player.playing:
		await audio_player.finished

	if is_instance_valid(speaker_tween) and speaker_tween.is_running():
		speaker_tween.kill()
	if is_instance_valid(player_tween) and player_tween.is_running():
		player_tween.kill()

	if hide_sprites_when_finished:
		if speaker_sprite != null:
			speaker_sprite.hide()
		if player_sprite != null:
			player_sprite.hide()

	_restore_player_state()
	_is_playing = false
	finished.emit()


func play_for_player(trigger_player: Node2D) -> void:
	if player_node == null:
		player_node = trigger_player
	await play()


func _prepare_player_state() -> void:
	if player_node == null:
		return

	_previous_player_input_process = player_node.is_processing_input()
	if freeze_player_during_cutscene:
		player_node.set_process_input(false)
		if player_node.has_method("freeze_movement"):
			player_node.freeze_movement()

	var existing_visual: CanvasItem = _get_existing_player_visual()
	if existing_visual != null:
		_previous_player_visual_visible = existing_visual.visible
		if hide_existing_player_visual:
			existing_visual.hide()


func _restore_player_state() -> void:
	if player_node == null:
		return

	var existing_visual: CanvasItem = _get_existing_player_visual()
	if existing_visual != null:
		existing_visual.visible = _previous_player_visual_visible

	if freeze_player_during_cutscene:
		player_node.set_process_input(_previous_player_input_process)
		if player_node.has_method("unfreeze_movement"):
			player_node.unfreeze_movement()


func _attach_sprites_to_player() -> void:
	if not attach_sprites_to_player or player_node == null:
		return

	var anchor: Node = player_node.get_node_or_null(player_anchor_path)
	if anchor == null:
		anchor = player_node

	_reparent_sprite_to_anchor(speaker_sprite, anchor, speaker_local_position)
	_reparent_sprite_to_anchor(player_sprite, anchor, player_local_position)


func _reparent_sprite_to_anchor(sprite: Sprite2D, anchor: Node, local_position: Vector2) -> void:
	if sprite == null or anchor == null:
		return
	if sprite.get_parent() != anchor:
		if sprite.get_parent() != null:
			sprite.get_parent().remove_child(sprite)
		anchor.add_child(sprite)
	sprite.position = local_position


func _get_existing_player_visual() -> CanvasItem:
	if player_node == null:
		return null
	return player_node.get_node_or_null(existing_player_visual_path) as CanvasItem


func _show_first_frames() -> void:
	if speaker_sprite != null:
		if not speaker_frames.is_empty():
			speaker_sprite.texture = speaker_frames[0]
		speaker_sprite.show()

	if player_sprite != null:
		if not player_frames.is_empty():
			player_sprite.texture = player_frames[0]
		player_sprite.show()


func _play_frame_sequence(sprite: Sprite2D, frames: Array[Texture2D], fps: float) -> Tween:
	if sprite == null or frames.is_empty():
		return null

	var frame_seconds: float = 1.0 / maxf(1.0, fps)
	var tween: Tween = create_tween()
	for texture in frames:
		tween.tween_callback(func() -> void:
			if sprite != null:
				sprite.texture = texture
		)
		tween.tween_interval(frame_seconds)
	return tween


func _get_animation_seconds(frames: Array[Texture2D], fps: float) -> float:
	if frames.is_empty():
		return 0.0
	return float(frames.size()) / maxf(1.0, fps)
