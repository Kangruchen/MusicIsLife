extends Node
## 音乐播放器 - 负责加载和播放多轨道音乐
## BGM 轨道路由到 "BGM" 总线（受 LowPass 滤镜影响）
## Miss 音效通过 SFXManager 路由到 "SFX" 总线（不受 LowPass 影响）

@export var music_config: MusicConfig = null
@export_file("*.mp3", "*.ogg", "*.wav") var music_path: String = ""
@export var auto_play: bool = true

@export var enable_miss_audio_effect: bool = false

const NORMAL_CUTOFF: float = 20000.0
const MISS_CUTOFF: float = 500.0
const MISS_DURATION: float = 0.3

const NORMAL_VOLUME_DB: float = 0.0
const MISS_VOLUME_DB: float = -10.46

var lowpass_filter: AudioEffectLowPassFilter = null
var filter_tween: Tween = null
var volume_tween: Tween = null
var _attack_mix_tween: Tween = null
var _attack_mix_active: bool = false
var _cached_main_volume_db: float = 0.0
var _cached_drum_volume_db: float = 0.0
var _cached_bass_volume_db: float = 0.0

const ATTACK_DRUM_PATH: String = "res://assets/music/AISample/AISample_drum.mp3"
var _pre_attack_drum_stream: AudioStream = null
var _pre_attack_drum_volume_db: float = 0.0

var main_player: AudioStreamPlayer = null
var drum_player: AudioStreamPlayer = null
var bass_player: AudioStreamPlayer = null
var paused_position: float = 0.0

func _ready() -> void:
	main_player = AudioStreamPlayer.new()
	drum_player = AudioStreamPlayer.new()
	bass_player = AudioStreamPlayer.new()

	main_player.name = "MainPlayer"
	drum_player.name = "DrumPlayer"
	bass_player.name = "BassPlayer"

	add_child(main_player)
	add_child(drum_player)
	add_child(bass_player)

	main_player.bus = "BGM"
	drum_player.bus = "BGM"
	bass_player.bus = "BGM"

	var bus_index: int = AudioServer.get_bus_index("BGM")
	if bus_index != -1:
		var effect_count: int = AudioServer.get_bus_effect_count(bus_index)
		for i in range(effect_count):
			var effect: AudioEffect = AudioServer.get_bus_effect(bus_index, i)
			if effect is AudioEffectLowPassFilter:
				lowpass_filter = effect
				print("已找到 Lowpass Filter on BGM bus, 当前频率: ", lowpass_filter.cutoff_hz, " Hz")
				break

	if not lowpass_filter:
		push_warning("未在 BGM 总线上找到 Lowpass Filter 效果器")

	if auto_play:
		call_deferred("load_and_play_music")


func load_and_play_music(custom_path: String = "") -> void:
	if music_config:
		_load_from_config()
	elif custom_path != "" or music_path != "":
		_load_single_track(custom_path if custom_path != "" else music_path)
	else:
		push_warning("未配置音乐文件路径或配置资源, 无法播放音乐")
		return

	_play_all_tracks()
	EventBus.music_started.emit()
	print("音乐开始播放")


func _load_from_config() -> void:
	if not music_config:
		return

	if music_config.main_track and music_config.main_enabled:
		main_player.stream = music_config.main_track
		main_player.volume_db = music_config.main_volume_db
		print("已加载主旋律轨道, 音量: ", music_config.main_volume_db, " dB")

	if music_config.drum_track and music_config.drum_enabled:
		drum_player.stream = music_config.drum_track
		drum_player.volume_db = music_config.drum_volume_db
		print("已加载鼓点轨道, 音量: ", music_config.drum_volume_db, " dB")

	if music_config.bass_track and music_config.bass_enabled:
		bass_player.stream = music_config.bass_track
		bass_player.volume_db = music_config.bass_volume_db
		print("已加载贝斯轨道, 音量: ", music_config.bass_volume_db, " dB")


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


func _play_all_tracks() -> void:
	if main_player.stream:
		main_player.play()
	if drum_player.stream:
		drum_player.play()
	if bass_player.stream:
		bass_player.play()


func stop_music() -> void:
	main_player.stop()
	drum_player.stop()
	bass_player.stop()


func fade_out_all_for_death(duration: float = 1.2, target_volume_db: float = -40.0) -> void:
	var fade_duration: float = maxf(0.05, duration)
	var target_db: float = clampf(target_volume_db, -80.0, 0.0)

	if volume_tween != null:
		volume_tween.kill()

	volume_tween = create_tween()
	volume_tween.set_parallel(true)
	volume_tween.set_ease(Tween.EASE_OUT)
	volume_tween.set_trans(Tween.TRANS_SINE)

	if main_player != null:
		volume_tween.tween_property(main_player, "volume_db", target_db, fade_duration)
	if drum_player != null:
		volume_tween.tween_property(drum_player, "volume_db", target_db, fade_duration)
	if bass_player != null:
		volume_tween.tween_property(bass_player, "volume_db", target_db, fade_duration)


func pause_music() -> void:
	main_player.stream_paused = true
	drum_player.stream_paused = true
	bass_player.stream_paused = true
	print("音乐已暂停")


func pause_music_keep_drum(drum_seek_time: float = -1.0) -> void:
	begin_attack_mix_mode()


func resume_music() -> void:
	end_attack_mix_mode()


func begin_attack_mix_mode() -> void:
	if music_config == null:
		return
	if bass_player == null or bass_player.stream == null:
		return

	_cached_main_volume_db = main_player.volume_db if main_player != null else 0.0
	_cached_drum_volume_db = drum_player.volume_db if drum_player != null else 0.0
	_cached_bass_volume_db = bass_player.volume_db

	if _attack_mix_tween != null:
		_attack_mix_tween.kill()

	_attack_mix_tween = create_tween()
	_attack_mix_tween.set_parallel(true)
	_attack_mix_tween.set_ease(Tween.EASE_OUT)
	_attack_mix_tween.set_trans(Tween.TRANS_CUBIC)

	if main_player != null and main_player.stream:
		_attack_mix_tween.tween_property(main_player, "volume_db", -80.0, 0.12)
	if drum_player != null and drum_player.stream:
		_attack_mix_tween.tween_property(drum_player, "volume_db", -80.0, 0.12)
	if bass_player.stream:
		_attack_mix_tween.tween_property(bass_player, "volume_db", _cached_bass_volume_db, 0.12)

	_attack_mix_active = true


func end_attack_mix_mode() -> void:
	if not _attack_mix_active:
		return

	if _attack_mix_tween != null:
		_attack_mix_tween.kill()

	_attack_mix_tween = create_tween()
	_attack_mix_tween.set_parallel(true)
	_attack_mix_tween.set_ease(Tween.EASE_IN)
	_attack_mix_tween.set_trans(Tween.TRANS_CUBIC)

	if main_player != null and main_player.stream:
		_attack_mix_tween.tween_property(main_player, "volume_db", _cached_main_volume_db, 0.12)
	if drum_player != null and drum_player.stream:
		_attack_mix_tween.tween_property(drum_player, "volume_db", _cached_drum_volume_db, 0.12)
	if bass_player != null and bass_player.stream:
		_attack_mix_tween.tween_property(bass_player, "volume_db", _cached_bass_volume_db, 0.12)

	_attack_mix_active = false


func get_playback_position() -> float:
	if main_player.stream and main_player.playing:
		return main_player.get_playback_position()
	elif drum_player.stream and drum_player.playing:
		return drum_player.get_playback_position()
	elif bass_player.stream and bass_player.playing:
		return bass_player.get_playback_position()
	return 0.0


var playing: bool:
	get:
		return main_player.playing or drum_player.playing or bass_player.playing


func set_main_volume(volume_db: float) -> void:
	main_player.volume_db = volume_db


func set_drum_volume(volume_db: float) -> void:
	drum_player.volume_db = volume_db


func set_bass_volume(volume_db: float) -> void:
	bass_player.volume_db = volume_db


func get_drum_playback_position() -> float:
	if drum_player and drum_player.stream and drum_player.playing:
		return drum_player.get_playback_position() + AudioServer.get_time_to_next_mix()
	return -1.0


func toggle_main_track(enabled: bool) -> void:
	if enabled and main_player.stream and not main_player.playing:
		main_player.play()
	elif not enabled and main_player.playing:
		main_player.stop()


func toggle_drum_track(enabled: bool) -> void:
	if enabled and drum_player.stream and not drum_player.playing:
		drum_player.play()
	elif not enabled and drum_player.playing:
		drum_player.stop()


func toggle_bass_track(enabled: bool) -> void:
	if enabled and bass_player.stream and not bass_player.playing:
		bass_player.play()
	elif not enabled and bass_player.playing:
		bass_player.stop()


func apply_miss_effect() -> void:
	if not enable_miss_audio_effect:
		return

	if not lowpass_filter:
		return

	if GameConfigs.sound and GameConfigs.sound.miss_sound:
		SFXManager.play_stream(GameConfigs.sound.miss_sound, GameConfigs.sound.miss_sound_volume_db)

	if filter_tween:
		filter_tween.kill()
	if volume_tween:
		volume_tween.kill()

	filter_tween = create_tween()
	filter_tween.set_ease(Tween.EASE_OUT)
	filter_tween.set_trans(Tween.TRANS_CUBIC)

	filter_tween.tween_property(lowpass_filter, "cutoff_hz", MISS_CUTOFF, 0.1)
	filter_tween.tween_property(lowpass_filter, "cutoff_hz", NORMAL_CUTOFF, 0.2)

	volume_tween = create_tween()
	volume_tween.set_ease(Tween.EASE_OUT)
	volume_tween.set_trans(Tween.TRANS_CUBIC)

	volume_tween.tween_property(main_player, "volume_db", MISS_VOLUME_DB, 0.1)
	volume_tween.parallel().tween_property(drum_player, "volume_db", MISS_VOLUME_DB, 0.1)
	volume_tween.parallel().tween_property(bass_player, "volume_db", MISS_VOLUME_DB, 0.1)

	var main_normal_vol: float = music_config.main_volume_db if music_config else NORMAL_VOLUME_DB
	var drum_normal_vol: float = music_config.drum_volume_db if music_config else NORMAL_VOLUME_DB
	var bass_normal_vol: float = music_config.bass_volume_db if music_config else NORMAL_VOLUME_DB

	volume_tween.tween_property(main_player, "volume_db", main_normal_vol, 0.2)
	volume_tween.parallel().tween_property(drum_player, "volume_db", drum_normal_vol, 0.2)
	volume_tween.parallel().tween_property(bass_player, "volume_db", bass_normal_vol, 0.2)


func apply_track_miss_effect(note_type: int) -> void:
	if GameConfigs.sound and GameConfigs.sound.miss_sound:
		SFXManager.play_stream(GameConfigs.sound.miss_sound, GameConfigs.sound.miss_sound_volume_db)

	var main_normal_vol: float = music_config.main_volume_db if music_config else NORMAL_VOLUME_DB
	var bass_normal_vol: float = music_config.bass_volume_db if music_config else NORMAL_VOLUME_DB

	var track_tween: Tween = create_tween()
	track_tween.set_ease(Tween.EASE_OUT)
	track_tween.set_trans(Tween.TRANS_CUBIC)

	track_tween.tween_property(main_player, "volume_db", -80.0, 0.0)
	track_tween.parallel().tween_property(bass_player, "volume_db", -80.0, 0.0)

	track_tween.tween_interval(0.5)

	track_tween.tween_property(main_player, "volume_db", main_normal_vol, 0.25)
	track_tween.parallel().tween_property(bass_player, "volume_db", bass_normal_vol, 0.25)
