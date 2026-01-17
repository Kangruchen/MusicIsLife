extends Node
## 音乐播放器 - 负责加载和播放多轨道音乐

signal music_started

# 音乐配置
@export var music_config: MusicConfig = null  # 音乐配置资源
@export_file("*.mp3", "*.ogg", "*.wav") var music_path: String = ""  # 单轨音乐文件路径（兼容旧系统）
@export var auto_play: bool = true  # 是否在场景加载后自动播放

# Miss 音效开关
@export var enable_miss_audio_effect: bool = false
@export var miss_sound: AudioStream = null  # Miss 时播放的音效

# Lowpass Filter 配置
const NORMAL_CUTOFF: float = 20000.0  # 正常频率
const MISS_CUTOFF: float = 500.0      # Miss时的低频率
const MISS_DURATION: float = 0.3      # Miss效果持续时间（秒）

# 音量配置
const NORMAL_VOLUME_DB: float = 0.0   # 正常音量 (0 dB = 100%)
const MISS_VOLUME_DB: float = -10.46  # Miss时的音量 (-10.46 dB ≈ 30%)

var lowpass_filter: AudioEffectLowPassFilter = null
var filter_tween: Tween = null
var volume_tween: Tween = null

# 多轨道播放器
var main_player: AudioStreamPlayer = null
var drum_player: AudioStreamPlayer = null
var bass_player: AudioStreamPlayer = null
var miss_sfx_player: AudioStreamPlayer = null  # miss 音效播放器
var paused_position: float = 0.0  # 暂停时的播放位置

func _ready() -> void:
	# 创建音频播放器
	main_player = AudioStreamPlayer.new()
	drum_player = AudioStreamPlayer.new()
	bass_player = AudioStreamPlayer.new()
	miss_sfx_player = AudioStreamPlayer.new()
	
	main_player.name = "MainPlayer"
	drum_player.name = "DrumPlayer"
	bass_player.name = "BassPlayer"
	miss_sfx_player.name = "MissSFXPlayer"
	
	add_child(main_player)
	add_child(drum_player)
	add_child(bass_player)
	add_child(miss_sfx_player)
	
	# 设置所有播放器使用 Master 总线
	main_player.bus = "Master"
	drum_player.bus = "Master"
	bass_player.bus = "Master"
	miss_sfx_player.bus = "Master"
	
	# 加载 miss 音效
	if miss_sound:
		miss_sfx_player.stream = miss_sound
	
	# 获取 Lowpass Filter 引用
	var bus_index: int = AudioServer.get_bus_index("Master")
	if bus_index != -1:
		var effect_count: int = AudioServer.get_bus_effect_count(bus_index)
		for i in range(effect_count):
			var effect: AudioEffect = AudioServer.get_bus_effect(bus_index, i)
			if effect is AudioEffectLowPassFilter:
				lowpass_filter = effect
				print("已找到 Lowpass Filter, 当前频率: ", lowpass_filter.cutoff_hz, " Hz")
				break
	
	if not lowpass_filter:
		push_warning("未找到 Lowpass Filter 效果器")
	
	# 如果开启了自动播放, 延迟一帧播放音乐, 确保所有节点都已准备好
	if auto_play:
		call_deferred("load_and_play_music")


## 加载并播放音乐（可选指定音乐路径或配置）
func load_and_play_music(custom_path: String = "") -> void:
	# 优先使用 MusicConfig
	if music_config:
		_load_from_config()
	# 否则使用单轨模式（兼容旧系统）
	elif custom_path != "" or music_path != "":
		_load_single_track(custom_path if custom_path != "" else music_path)
	else:
		push_warning("未配置音乐文件路径或配置资源, 无法播放音乐")
		return
	
	# 同步播放所有轨道
	_play_all_tracks()
	music_started.emit()
	print("音乐开始播放")


## 从 MusicConfig 加载多轨道音乐
func _load_from_config() -> void:
	if not music_config:
		return
	
	# 加载主旋律轨道
	if music_config.main_track and music_config.main_enabled:
		main_player.stream = music_config.main_track
		main_player.volume_db = music_config.main_volume_db
		print("已加载主旋律轨道, 音量: ", music_config.main_volume_db, " dB")
	
	# 加载鼓点轨道
	if music_config.drum_track and music_config.drum_enabled:
		drum_player.stream = music_config.drum_track
		drum_player.volume_db = music_config.drum_volume_db
		print("已加载鼓点轨道, 音量: ", music_config.drum_volume_db, " dB")
	
	# 加载贝斯轨道
	if music_config.bass_track and music_config.bass_enabled:
		bass_player.stream = music_config.bass_track
		bass_player.volume_db = music_config.bass_volume_db
		print("已加载贝斯轨道, 音量: ", music_config.bass_volume_db, " dB")


## 加载单轨音乐（兼容旧系统）
func _load_single_track(path: String) -> void:
	if path == "":
		return
	
	var music_stream: AudioStream = load(path)
	if music_stream:
		main_player.stream = music_stream
		main_player.volume_db = 0.0
		print("已加载单轨音乐: ", path)
	else:
		push_error("无法加载音乐文件: ", path)


## 播放所有轨道
func _play_all_tracks() -> void:
	if main_player.stream:
		main_player.play()
	if drum_player.stream:
		drum_player.play()
	if bass_player.stream:
		bass_player.play()


## 停止播放音乐
func stop_music() -> void:
	main_player.stop()
	drum_player.stop()
	bass_player.stop()


## 暂停音乐播放（保留播放位置）
func pause_music() -> void:
	main_player.stream_paused = true
	drum_player.stream_paused = true
	bass_player.stream_paused = true
	print("音乐已暂停")


## Boss精力耗尽时的特殊暂停（只保留drum轨道）
func pause_music_keep_drum(drum_seek_time: float = -1.0) -> void:
	# 记录当前播放位置（用于恢复）
	if main_player.stream and main_player.playing:
		paused_position = main_player.get_playback_position()
	elif bass_player.stream and bass_player.playing:
		paused_position = bass_player.get_playback_position()
	
	# 立即让 drum 跳转到指定位置
	if drum_seek_time >= 0.0 and drum_player.stream:
		drum_player.seek(drum_seek_time)
	
	# 创建淡出 Tween（0.5秒）
	var fadeout_tween: Tween = create_tween()
	fadeout_tween.set_parallel(true)
	fadeout_tween.set_ease(Tween.EASE_OUT)
	fadeout_tween.set_trans(Tween.TRANS_CUBIC)
	
	# Main 和 Bass 音量淡出到静音（0.5秒）
	fadeout_tween.tween_property(main_player, "volume_db", -80.0, 0.5)
	fadeout_tween.tween_property(bass_player, "volume_db", -80.0, 0.5)
	
	# 稍微提升 Drum 音量来突出节奏
	var drum_boost_vol: float = min(drum_player.volume_db + 6.0, 0.0)
	fadeout_tween.tween_property(drum_player, "volume_db", drum_boost_vol, 0.5)
	
	# 淡出完成后暂停 main 和 bass 播放
	fadeout_tween.finished.connect(func():
		main_player.stream_paused = true
		bass_player.stream_paused = true
		print("Main和Bass已暂停播放")
	)
	
	print("音乐淡出中（0.5秒后暂停）")


## 恢复音乐播放（提前0.5秒调用以便淡入）
func resume_music() -> void:
	# 恢复 main 和 bass 播放，先设置为静音
	main_player.volume_db = -80.0
	bass_player.volume_db = -80.0
	main_player.stream_paused = false
	bass_player.stream_paused = false
	
	# 所有轨道回到暂停前的位置继续播放
	if paused_position > 0.0:
		if main_player.stream:
			main_player.seek(paused_position)
		if bass_player.stream:
			bass_player.seek(paused_position)
		if drum_player.stream:
			drum_player.seek(paused_position)
		
		print("音乐恢复到暂停前位置: ", paused_position)
		paused_position = 0.0
	
	# 获取正常音量
	var main_normal_vol: float = music_config.main_volume_db if music_config else NORMAL_VOLUME_DB
	var drum_normal_vol: float = music_config.drum_volume_db if music_config else NORMAL_VOLUME_DB
	var bass_normal_vol: float = music_config.bass_volume_db if music_config else NORMAL_VOLUME_DB
	
	# 创建淡入 Tween（0.5秒）
	var fadein_tween: Tween = create_tween()
	fadein_tween.set_parallel(true)
	fadein_tween.set_ease(Tween.EASE_IN)
	fadein_tween.set_trans(Tween.TRANS_CUBIC)
	
	# 从静音淡入到正常音量（0.5秒）
	fadein_tween.tween_property(main_player, "volume_db", main_normal_vol, 0.5)
	fadein_tween.tween_property(bass_player, "volume_db", bass_normal_vol, 0.5)
	fadein_tween.tween_property(drum_player, "volume_db", drum_normal_vol, 0.5)
	
	print("音乐淡入恢复中（0.5秒）")


## 获取当前播放位置（使用主轨道作为参考）
func get_playback_position() -> float:
	if main_player.stream and main_player.playing:
		return main_player.get_playback_position()
	elif drum_player.stream and drum_player.playing:
		return drum_player.get_playback_position()
	elif bass_player.stream and bass_player.playing:
		return bass_player.get_playback_position()
	return 0.0


## 检查是否正在播放
var playing: bool:
	get:
		return main_player.playing or drum_player.playing or bass_player.playing


## 设置主旋律轨道音量
func set_main_volume(volume_db: float) -> void:
	main_player.volume_db = volume_db


## 设置鼓点轨道音量
func set_drum_volume(volume_db: float) -> void:
	drum_player.volume_db = volume_db


## 设置贝斯轨道音量
func set_bass_volume(volume_db: float) -> void:
	bass_player.volume_db = volume_db


## 切换主旋律轨道开关
func toggle_main_track(enabled: bool) -> void:
	if enabled and main_player.stream and not main_player.playing:
		main_player.play()
	elif not enabled and main_player.playing:
		main_player.stop()


## 切换鼓点轨道开关
func toggle_drum_track(enabled: bool) -> void:
	if enabled and drum_player.stream and not drum_player.playing:
		drum_player.play()
	elif not enabled and drum_player.playing:
		drum_player.stop()


## 切换贝斯轨道开关
func toggle_bass_track(enabled: bool) -> void:
	if enabled and bass_player.stream and not bass_player.playing:
		bass_player.play()
	elif not enabled and bass_player.playing:
		bass_player.stop()


## 应用 Miss 音效（所有轨道）
func apply_miss_effect() -> void:
	# 检查是否启用了 Miss 音效
	if not enable_miss_audio_effect:
		return
	
	if not lowpass_filter:
		return
	
	# 如果已有 Tween 在运行, 先停止
	if filter_tween:
		filter_tween.kill()
	if volume_tween:
		volume_tween.kill()
	
	# 创建频率 Tween
	filter_tween = create_tween()
	filter_tween.set_ease(Tween.EASE_OUT)
	filter_tween.set_trans(Tween.TRANS_CUBIC)
	
	# 快速降低频率到 500Hz（0.1秒）
	filter_tween.tween_property(lowpass_filter, "cutoff_hz", MISS_CUTOFF, 0.1)
	# 慢速恢复到正常频率（0.2秒）
	filter_tween.tween_property(lowpass_filter, "cutoff_hz", NORMAL_CUTOFF, 0.2)
	
	# 创建音量 Tween（应用到所有轨道）
	volume_tween = create_tween()
	volume_tween.set_ease(Tween.EASE_OUT)
	volume_tween.set_trans(Tween.TRANS_CUBIC)
	
	# 快速降低音量到 30%（0.1秒）
	volume_tween.tween_property(main_player, "volume_db", MISS_VOLUME_DB, 0.1)
	volume_tween.parallel().tween_property(drum_player, "volume_db", MISS_VOLUME_DB, 0.1)
	volume_tween.parallel().tween_property(bass_player, "volume_db", MISS_VOLUME_DB, 0.1)
	
	# 慢速恢复到各自的正常音量（0.2秒）
	var main_normal_vol: float = music_config.main_volume_db if music_config else NORMAL_VOLUME_DB
	var drum_normal_vol: float = music_config.drum_volume_db if music_config else NORMAL_VOLUME_DB
	var bass_normal_vol: float = music_config.bass_volume_db if music_config else NORMAL_VOLUME_DB
	
	volume_tween.tween_property(main_player, "volume_db", main_normal_vol, 0.2)
	volume_tween.parallel().tween_property(drum_player, "volume_db", drum_normal_vol, 0.2)
	volume_tween.parallel().tween_property(bass_player, "volume_db", bass_normal_vol, 0.2)


## 对单个轨道应用 Miss 音效（根据音符类型）
func apply_track_miss_effect(note_type: int) -> void:
	# 播放 miss 音效
	if miss_sfx_player and miss_sfx_player.stream:
		miss_sfx_player.play()
	
	# 获取各轨道的正常音量
	var main_normal_vol: float = music_config.main_volume_db if music_config else NORMAL_VOLUME_DB
	var bass_normal_vol: float = music_config.bass_volume_db if music_config else NORMAL_VOLUME_DB
	
	# 创建音量衰减 Tween，只影响主旋律和 bass 轨道，鼓点保持播放
	var track_tween: Tween = create_tween()
	track_tween.set_ease(Tween.EASE_OUT)
	track_tween.set_trans(Tween.TRANS_CUBIC)
	
	# 瞬间降低主旋律和 bass 轨道音量到完全静音（0秒），鼓点不受影响
	track_tween.tween_property(main_player, "volume_db", -80.0, 0.0)
	track_tween.parallel().tween_property(bass_player, "volume_db", -80.0, 0.0)
	
	# 等待0.5秒
	track_tween.tween_interval(0.5)
	
	# 恢复主旋律和 bass 到各自的正常音量（0.25秒）
	track_tween.tween_property(main_player, "volume_db", main_normal_vol, 0.25)
	track_tween.parallel().tween_property(bass_player, "volume_db", bass_normal_vol, 0.25)
