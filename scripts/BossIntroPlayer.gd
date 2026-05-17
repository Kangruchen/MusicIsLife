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
@export_file("*.ogv", "*.webm") var intro_video_path: String = ""
@export_range(0.1, 3.0, 0.1) var fade_in_duration: float = 0.5
@export_range(0.1, 3.0, 0.1) var fade_out_duration: float = 1.0
@export_range(0.1, 3.0, 0.1) var reveal_duration: float = 0.8

var _video_player: VideoStreamPlayer = null
var _fade_rect: ColorRect = null
var _transition_started: bool = false
var _signal_emitted: bool = false
var _character: CanvasItem = null


func _ready() -> void:
	layer = 1  # 视频在中间图层
	EventBus.boss_intro_completed = false

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

	_fade_rect = ColorRect.new()
	_fade_rect.name = "FadeOverlay"
	_fade_rect.color = Color.BLACK
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade_rect)


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


func _process(_delta: float) -> void:
	if _transition_started:
		return

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
