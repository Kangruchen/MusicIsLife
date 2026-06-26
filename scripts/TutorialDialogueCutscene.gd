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
@export var speaker_anchor: Node2D
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
@export_range(0.0, 10.0, 0.001) var sound_effect_start_seconds: float = 0.0
@export var hide_sprites_when_finished: bool = true
@export_range(0.0, 1.0, 0.01) var fade_in_seconds: float = 0.12
@export_range(0.0, 1.0, 0.01) var fade_out_seconds: float = 0.12
@export_range(0.0, 1.0, 0.01) var end_hold_seconds: float = 0.08
@export var restore_sprite_parents_when_finished: bool = true
@export var loop_speaker_until_sound_finished: bool = false
@export var queue_free_when_finished: bool = false

var _is_playing: bool = false
var _previous_player_input_process: bool = true
var _previous_player_visual_visible: bool = true
var _previous_player_visual_modulate: Color = Color.WHITE
var _original_sprite_states: Dictionary = {}


func play() -> void:
	if _is_playing:
		return

	_is_playing = true
	_prepare_player_state()
	_attach_cutscene_sprites()
	_show_first_frames()
	await _fade_cutscene_sprites(1.0, fade_in_seconds)

	if audio_player != null and sound_effect != null:
		audio_player.stream = sound_effect
		audio_player.play(maxf(0.0, sound_effect_start_seconds))

	var speaker_time: float = _get_animation_seconds(speaker_frames, speaker_fps)
	var player_time: float = _get_animation_seconds(player_frames, player_fps)
	var animation_time: float = maxf(speaker_time, player_time)

	var should_loop_speaker: bool = (
		loop_speaker_until_sound_finished
		and wait_for_sound_to_finish
		and audio_player != null
		and audio_player.playing
	)

	var speaker_tween: Tween = _play_frame_sequence(speaker_sprite, speaker_frames, speaker_fps, should_loop_speaker)
	var player_tween: Tween = _play_frame_sequence(player_sprite, player_frames, player_fps)

	if animation_time > 0.0:
		await get_tree().create_timer(animation_time).timeout
	if wait_for_sound_to_finish and audio_player != null and audio_player.playing:
		await audio_player.finished
	if end_hold_seconds > 0.0:
		await get_tree().create_timer(end_hold_seconds).timeout

	if is_instance_valid(speaker_tween) and speaker_tween.is_running():
		speaker_tween.kill()
	if is_instance_valid(player_tween) and player_tween.is_running():
		player_tween.kill()

	await _fade_cutscene_sprites(0.0, fade_out_seconds)

	_restore_player_state()
	_restore_sprite_parents()
	if hide_sprites_when_finished:
		_hide_cutscene_sprites()
	_is_playing = false
	finished.emit()
	if queue_free_when_finished:
		queue_free()


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
		_previous_player_visual_modulate = existing_visual.modulate
		if hide_existing_player_visual:
			existing_visual.hide()


func _restore_player_state() -> void:
	if player_node == null:
		return

	var existing_visual: CanvasItem = _get_existing_player_visual()
	if existing_visual != null:
		existing_visual.visible = _previous_player_visual_visible
		existing_visual.modulate = _previous_player_visual_modulate

	if freeze_player_during_cutscene:
		player_node.set_process_input(_previous_player_input_process)
		if player_node.has_method("unfreeze_movement"):
			player_node.unfreeze_movement()


func _attach_cutscene_sprites() -> void:
	var player_anchor: Node = _get_player_anchor()
	var speaker_parent: Node = speaker_anchor
	if speaker_parent == null:
		speaker_parent = player_anchor

	_reparent_sprite_to_anchor(speaker_sprite, speaker_parent, speaker_local_position)
	_reparent_sprite_to_anchor(player_sprite, player_anchor, player_local_position)


func _get_player_anchor() -> Node:
	if not attach_sprites_to_player or player_node == null:
		return null

	var anchor: Node = player_node.get_node_or_null(player_anchor_path)
	if anchor == null:
		anchor = player_node
	return anchor


func _reparent_sprite_to_anchor(sprite: Sprite2D, anchor: Node, local_position: Vector2) -> void:
	if sprite == null or anchor == null:
		return
	_remember_sprite_state(sprite)
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
		speaker_sprite.modulate.a = 0.0 if fade_in_seconds > 0.0 else 1.0
		speaker_sprite.show()

	if player_sprite != null:
		if not player_frames.is_empty():
			player_sprite.texture = player_frames[0]
		player_sprite.modulate.a = 0.0 if fade_in_seconds > 0.0 else 1.0
		player_sprite.show()


func _play_frame_sequence(sprite: Sprite2D, frames: Array[Texture2D], fps: float, loop: bool = false) -> Tween:
	if sprite == null or frames.is_empty():
		return null

	var frame_seconds: float = 1.0 / maxf(1.0, fps)
	var tween: Tween = create_tween()
	if loop and frames.size() > 1:
		tween.set_loops()
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


func _fade_cutscene_sprites(target_alpha: float, duration: float) -> void:
	var fade_duration: float = maxf(0.0, duration)
	if fade_duration <= 0.0:
		_set_cutscene_sprites_alpha(target_alpha)
		return

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	if speaker_sprite != null:
		tween.tween_property(speaker_sprite, "modulate:a", target_alpha, fade_duration)
	if player_sprite != null:
		tween.tween_property(player_sprite, "modulate:a", target_alpha, fade_duration)
	await tween.finished


func _set_cutscene_sprites_alpha(alpha: float) -> void:
	if speaker_sprite != null:
		speaker_sprite.modulate.a = alpha
	if player_sprite != null:
		player_sprite.modulate.a = alpha


func _hide_cutscene_sprites() -> void:
	if speaker_sprite != null:
		speaker_sprite.hide()
		speaker_sprite.modulate.a = 0.0
	if player_sprite != null:
		player_sprite.hide()
		player_sprite.modulate.a = 0.0


func _remember_sprite_state(sprite: Sprite2D) -> void:
	if _original_sprite_states.has(sprite):
		return
	_original_sprite_states[sprite] = {
		"parent": sprite.get_parent(),
		"index": sprite.get_index(),
		"position": sprite.position,
		"visible": sprite.visible,
		"modulate": sprite.modulate,
	}


func _restore_sprite_parents() -> void:
	if not restore_sprite_parents_when_finished:
		return

	for sprite in _original_sprite_states.keys():
		var sprite_node: Sprite2D = sprite as Sprite2D
		if sprite_node == null or not is_instance_valid(sprite_node):
			continue
		var state: Dictionary = _original_sprite_states[sprite_node]
		var original_parent: Node = state.get("parent") as Node
		if original_parent != null and is_instance_valid(original_parent) and sprite_node.get_parent() != original_parent:
			if sprite_node.get_parent() != null:
				sprite_node.get_parent().remove_child(sprite_node)
			original_parent.add_child(sprite_node)
			original_parent.move_child(sprite_node, int(state.get("index", sprite_node.get_index())))
		sprite_node.position = state.get("position", sprite_node.position)
		sprite_node.visible = bool(state.get("visible", sprite_node.visible))
		sprite_node.modulate = state.get("modulate", sprite_node.modulate)
	_original_sprite_states.clear()
