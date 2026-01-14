extends AudioStreamPlayer
## 音乐播放器 - 负责加载和播放音乐文件

signal music_started

# 音乐配置
@export_file("*.mp3", "*.ogg", "*.wav") var music_path: String = ""  # 音乐文件路径
@export var auto_play: bool = true  # 是否在场景加载后自动播放

# Miss 音效开关
@export var enable_miss_audio_effect: bool = false

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


func _ready() -> void:
	# 获取 Lowpass Filter 引用
	var bus_index: int = AudioServer.get_bus_index("Master")
	if bus_index != -1:
		var effect_count: int = AudioServer.get_bus_effect_count(bus_index)
		for i in range(effect_count):
			var effect: AudioEffect = AudioServer.get_bus_effect(bus_index, i)
			if effect is AudioEffectLowPassFilter:
				lowpass_filter = effect
				print("已找到 Lowpass Filter，当前频率: ", lowpass_filter.cutoff_hz, " Hz")
				break
	
	if not lowpass_filter:
		push_warning("未找到 Lowpass Filter 效果器")
	
	# 如果开启了自动播放，延迟一帧播放音乐，确保所有节点都已准备好
	if auto_play:
		call_deferred("load_and_play_music")

##（可选指定音乐路径）
func load_and_play_music(custom_path: String = "") -> void:
	# 如果提供了自定义路径，使用自定义路径；否则使用配置的路径
	var path_to_load: String = custom_path if custom_path != "" else music_path
	
	# 检查路径是否为空
	if path_to_load == "":
		push_warning("未配置音乐文件路径，无法播放音乐")
		return
	
	var music_stream: AudioStream = load(path_to_load)
	if music_stream:
		stream = music_stream
		play()
		music_started.emit()
		print("音乐开始播放: ", path_to_load)
	else:
		push_error("无法加载音乐文件: ", path_to_load)


## 播放指定路径的音乐（用于外部调用）
func play_music(path: String) -> void:
	load_and_play_music(path)


## 停止播放音乐
func stop_music() -> void:
	stop()


	# 检查是否启用了 Miss 音效
	if not enable_miss_audio_effect:
		return
	
	if not lowpass_filter:
		return
	
	# 如果已有 Tween 在运行，先停止
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
	
	# 创建音量 Tween
	volume_tween = create_tween()
	volume_tween.set_ease(Tween.EASE_OUT)
	volume_tween.set_trans(Tween.TRANS_CUBIC)
	
	# 快速降低音量到 30%（0.1秒）
	volume_tween.tween_property(self, "volume_db", MISS_VOLUME_DB, 0.1)
	# 慢速恢复到正常音量（0.2秒）
	volume_tween.tween_property(self, "volume_db", NORMAL_VOLUME_DB, 0.2)
