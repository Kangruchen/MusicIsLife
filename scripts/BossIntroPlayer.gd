extends CanvasLayer
## Boss 开场动画播放器
## 在 Boss 战开始时播放开场动画视频，播放完毕后通过 EventBus 通知游戏逻辑启动
##
## 过渡流程：
##   1. 黑屏 → 淡入视频（fade_in_duration）
##   2. 视频播放
##   3. 视频即将结束前，淡出到黑屏（fade_out_duration）
##   4. 停止视频，发射 boss_intro_finished 信号，游戏逻辑在黑屏期间启动
##   5. 黑屏淡出，露出游戏场景（reveal_duration）
##
## 若未配置视频路径，则立即发射信号，游戏正常启动。

@export var enable_intro: bool = true
@export var show_character_during_intro: bool = true
@export_node_path("Node2D") var character_source_path: NodePath = NodePath("../Character")
@export var intro_character_idle_animation: StringName = &"Idle"
@export_file("*.ogv", "*.webm") var intro_video_path: String = ""
@export_range(0.1, 3.0, 0.1) var fade_in_duration: float = 0.5
@export_range(0.1, 3.0, 0.1) var fade_out_duration: float = 1.0
@export_range(0.1, 3.0, 0.1) var reveal_duration: float = 0.8
@export_group("Skip")
@export var skip_action: StringName = &"restart"
@export_range(0.2, 3.0, 0.1) var skip_hold_seconds: float = 1.0

var _video_player: VideoStreamPlayer = null
var _fade_rect: ColorRect = null
var _skip_hint: Label = null
var _skip_progress: ProgressBar = null
var _skip_hold_time: float = 0.0
var _transition_started: bool = false
var _signal_emitted: bool = false
var _character: CanvasItem = null


func _ready() -> void:
	layer = 1  # 视频在中间图层
	EventBus.boss_intro_completed = false

	if get_tree().get_meta("skip_boss_intro_once", false):
		get_tree().set_meta("skip_boss_intro_once", false)
		_emit_intro_finished()
		queue_free()
		return

	if not enable_intro:
		push_warning("[BossIntroPlayer] 开场动画已禁用")
		_emit_intro_finished()
		queue_free()
		return

	if intro_video_path.is_empty():
		push_warning("[BossIntroPlayer] 没有配置视频路径，跳过开场动画")
		_emit_intro_finished()
		queue_free()
		return

	print("[BossIntroPlayer] 开始加载视频: ", intro_video_path)
	var video_stream: VideoStream = load(intro_video_path)
	if video_stream == null:
		push_error("[BossIntroPlayer] 无法加载开场动画视频: " + intro_video_path)
		_emit_intro_finished()
		queue_free()
		return

	print("[BossIntroPlayer] 视频加载成功")
	
	_build_ui(video_stream)
	_start_playback()


func _build_ui(stream: VideoStream) -> void:
	_video_player = VideoStreamPlayer.new()
	_video_player.name = "IntroVideo"
	_video_player.expand = true
	_video_player.visible = true
	_video_player.set_anchors_preset(Control.PRESET_FULL_RECT)
	_video_player.stream = stream
	add_child(_video_player)

	if show_character_during_intro:
		_build_character_overlay()

	_fade_rect = ColorRect.new()
	_fade_rect.name = "FadeOverlay"
	_fade_rect.color = Color.BLACK
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_fade_rect.z_index = 100
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade_rect)

	_build_skip_hint()


func _build_skip_hint() -> void:
	var skip_box: VBoxContainer = VBoxContainer.new()
	skip_box.name = "SkipHint"
	skip_box.z_index = 130
	skip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skip_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	skip_box.offset_left = -280.0
	skip_box.offset_top = -76.0
	skip_box.offset_right = -24.0
	skip_box.offset_bottom = -24.0
	add_child(skip_box)

	_skip_hint = Label.new()
	_skip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skip_hint.text = "Hold %s to skip" % GameConstants.get_action_key_label(String(skip_action), "R")
	_skip_hint.add_theme_font_size_override("font_size", 16)
	_skip_hint.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.88))
	_skip_hint.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.75))
	_skip_hint.add_theme_constant_override("shadow_offset_x", 1)
	_skip_hint.add_theme_constant_override("shadow_offset_y", 1)
	skip_box.add_child(_skip_hint)

	_skip_progress = ProgressBar.new()
	_skip_progress.custom_minimum_size = Vector2(240.0, 6.0)
	_skip_progress.min_value = 0.0
	_skip_progress.max_value = 1.0
	_skip_progress.value = 0.0
	_skip_progress.show_percentage = false
	_skip_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skip_box.add_child(_skip_progress)


func _build_character_overlay() -> void:
	var source_character: Node2D = _resolve_character_source()
	if source_character == null:
		push_warning("[BossIntroPlayer] Character source not found; intro character overlay skipped.")
		return

	var source_sprite: AnimatedSprite2D = source_character.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if source_sprite == null:
		source_sprite = source_character.find_child("AnimatedSprite2D", true, false) as AnimatedSprite2D
	if source_sprite == null or source_sprite.sprite_frames == null:
		push_warning("[BossIntroPlayer] Character sprite not found; intro character overlay skipped.")
		return

	var overlay_sprite: AnimatedSprite2D = AnimatedSprite2D.new()
	overlay_sprite.name = "IntroCharacter"
	overlay_sprite.sprite_frames = source_sprite.sprite_frames
	overlay_sprite.centered = source_sprite.centered
	overlay_sprite.offset = source_sprite.offset
	overlay_sprite.flip_h = source_sprite.flip_h
	overlay_sprite.flip_v = source_sprite.flip_v
	overlay_sprite.texture_filter = source_sprite.texture_filter
	overlay_sprite.modulate = Color(
		source_character.modulate.r * source_sprite.modulate.r,
		source_character.modulate.g * source_sprite.modulate.g,
		source_character.modulate.b * source_sprite.modulate.b,
		source_character.modulate.a * source_sprite.modulate.a
	)
	overlay_sprite.self_modulate = source_sprite.self_modulate
	overlay_sprite.z_index = 10

	var anim_name: StringName = _resolve_character_idle_animation(source_sprite)
	if String(anim_name).is_empty():
		push_warning("[BossIntroPlayer] Character idle animation not found; intro character overlay skipped.")
		return
	overlay_sprite.animation = anim_name
	overlay_sprite.frame = 0
	overlay_sprite.frame_progress = 0.0
	add_child(overlay_sprite)
	overlay_sprite.global_transform = get_viewport().get_canvas_transform() * source_sprite.global_transform
	overlay_sprite.play(anim_name)
	_character = overlay_sprite


func _resolve_character_source() -> Node2D:
	if not character_source_path.is_empty():
		var configured_character: Node2D = get_node_or_null(character_source_path) as Node2D
		if configured_character != null:
			return configured_character

	var parent_node: Node = get_parent()
	if parent_node != null:
		var sibling_character: Node2D = parent_node.get_node_or_null("Character") as Node2D
		if sibling_character != null:
			return sibling_character

	var scene_root: Node = get_tree().current_scene
	if scene_root != null:
		return scene_root.find_child("Character", true, false) as Node2D

	return null


func _resolve_character_idle_animation(source_sprite: AnimatedSprite2D) -> StringName:
	var frames: SpriteFrames = source_sprite.sprite_frames
	if frames == null:
		return &""
	if not String(intro_character_idle_animation).is_empty() and frames.has_animation(intro_character_idle_animation):
		return intro_character_idle_animation
	if frames.has_animation(&"Idle"):
		return &"Idle"
	if frames.has_animation(&"idle"):
		return &"idle"
	return source_sprite.animation


func _start_playback() -> void:
	# 确保视频播放器可见并处于正确状态
	_video_player.paused = false
	_video_player.bus = "Master"
	
	print("[BossIntroPlayer] 正在播放视频...")
	print("  - 播放器可见: ", _video_player.visible)
	print("  - 播放器暂停状态: ", _video_player.paused)
	print("  - 视频流: ", _video_player.stream)
	
	_video_player.play()
	print("  - 播放方法已调用，当前状态: 正在播放 = ", _video_player.is_playing())
	
	if not _video_player.finished.is_connected(_on_video_finished):
		_video_player.finished.connect(_on_video_finished)

	var tween: Tween = create_tween()
	# 淡入视频
	tween.tween_property(_fade_rect, "color:a", 0.0, fade_in_duration)
	
	set_process(true)


func _input(event: InputEvent) -> void:
	if event.is_action(skip_action):
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _transition_started:
		return

	_update_skip_hold(delta)

	if _video_player == null or not _video_player.is_playing():
		_begin_transition()
		return

	var stream_length: float = _video_player.get_stream_length()
	if stream_length <= 0.0:
		return

	var current_pos: float = _video_player.stream_position
	var time_remaining: float = stream_length - current_pos

	if time_remaining <= fade_out_duration:
		_begin_transition()


func _update_skip_hold(delta: float) -> void:
	if not InputMap.has_action(skip_action):
		return

	if Input.is_action_pressed(skip_action):
		_skip_hold_time = minf(skip_hold_seconds, _skip_hold_time + delta)
	else:
		_skip_hold_time = 0.0

	if _skip_progress != null:
		var safe_hold_seconds: float = maxf(0.01, skip_hold_seconds)
		_skip_progress.value = clampf(_skip_hold_time / safe_hold_seconds, 0.0, 1.0)

	if _skip_hold_time >= skip_hold_seconds:
		_begin_transition()


func _on_video_finished() -> void:
	_begin_transition()


func _begin_transition() -> void:
	if _transition_started:
		return
	_transition_started = true
	set_process(false)

	var current_alpha: float = _fade_rect.color.a
	var remaining: float = fade_out_duration * (1.0 - current_alpha)

	var tween: Tween = create_tween()
	tween.tween_property(_fade_rect, "color:a", 1.0, maxf(0.05, remaining))
	tween.tween_callback(_on_video_fade_complete)


func _on_video_fade_complete() -> void:
	if _video_player:
		_video_player.stop()

	_emit_intro_finished()

	var tween: Tween = create_tween()
	tween.tween_property(_fade_rect, "color:a", 0.0, reveal_duration)
	tween.tween_callback(_cleanup)


func _emit_intro_finished() -> void:
	if _signal_emitted:
		return
	_signal_emitted = true
	EventBus.boss_intro_completed = true
	EventBus.boss_intro_finished.emit()


func _cleanup() -> void:
	if _fade_rect:
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	queue_free()
