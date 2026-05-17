extends Node
## 音乐播放器 - 负责加载和播放多轨道音乐
## BGM 轨道路由到 "BGM" 总线（受 LowPass 滤镜影响）
## Miss 音效通过 SFXManager 路由到 "SFX" 总线（不受 LowPass 影响）

@export var music_config: MusicConfig = null
@export_file("*.mp3", "*.ogg", "*.wav") var music_path: String = ""
@export_file("*.mp3", "*.ogg", "*.wav") var attack_music_path: String = ""
@export var auto_play: bool = true
@export_range(-80.0, 24.0, 0.1) var attack_music_volume_db: float = 0.0

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
var attack_player: AudioStreamPlayer = null
var paused_position: float = 0.0
var _attack_music_stream: AudioStream = null
var _attack_music_active: bool = false
var _waiting_for_boss_intro: bool = false

func _ready() -> void:
	main_player = AudioStreamPlayer.new()
	drum_player = AudioStreamPlayer.new()
	bass_player = AudioStreamPlayer.new()
	attack_player = AudioStreamPlayer.new()

	main_player.name = "MainPlayer"
	drum_player.name = "DrumPlayer"
	bass_player.name = "BassPlayer"
	attack_player.name = "AttackPlayer"

	add_child(main_player)
	add_child(drum_player)
	add_child(bass_player)
	add_child(attack_player)

	main_player.bus = "BGM"
	drum_player.bus = "BGM"
	bass_player.bus = "BGM"
	attack_player.bus = "BGM"

	if not EventBus.attack_phase_started.is_connected(_on_attack_phase_started):
		EventBus.attack_phase_started.connect(_on_attack_phase_started)
	if not EventBus.attack_phase_ended.is_connected(_on_attack_phase_ended):
		EventBus.attack_phase_ended.connect(_on_attack_phase_ended)

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
		if not EventBus.boss_intro_completed:
			_waiting_for_boss_intro = true
			if not EventBus.boss_intro_finished.is_connected(_on_boss_intro_finished):
				EventBus.boss_intro_finished.connect(_on_boss_intro_finished)
		else:
			call_deferred("load_and_play_music")


func _on_boss_intro_finished() -> void:
	if not _waiting_for_boss_intro:
		return
	_waiting_for_boss_intro = false
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
	if _attack_mix_tween != null:
		_attack_mix_tween.kill()
		_attack_mix_tween = null
	main_player.stop()
	drum_player.stop()
	bass_player.stop()
	if attack_player != null:
		attack_player.stop()
	_attack_music_active = false


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
	if attack_player != null and attack_player.stream:
		volume_tween.tween_property(attack_player, "volume_db", target_db, fade_duration)


func pause_music() -> void:
	main_player.stream_paused = true
	drum_player.stream_paused = true
	bass_player.stream_paused = true
	if attack_player != null:
		attack_player.stream_paused = true
	print("音乐已暂停")


func pause_music_keep_drum(drum_seek_time: float = -1.0) -> void:
	begin_attack_mix_mode()


func resume_music() -> void:
	end_attack_mix_mode()


func begin_attack_mix_mode() -> void:
	if _attack_music_active:
		return
	if main_player == null or drum_player == null or bass_player == null:
		return
	if main_player.stream == null and drum_player.stream == null and bass_player.stream == null:
		return

	_attack_music_stream = _load_attack_music_stream()
	if _attack_music_stream == null:
		push_warning("未配置攻击阶段音乐，无法切换到攻击 BGM")
		return

	_cached_main_volume_db = main_player.volume_db if main_player != null else 0.0
	_cached_drum_volume_db = drum_player.volume_db if drum_player != null else 0.0
	_cached_bass_volume_db = bass_player.volume_db

	if attack_player == null:
		attack_player = AudioStreamPlayer.new()
		attack_player.name = "AttackPlayer"
		attack_player.bus = "BGM"
		add_child(attack_player)

	if _attack_mix_tween != null:
		_attack_mix_tween.kill()
	if attack_player.playing:
		attack_player.stop()

	var sync_position: float = get_playback_position()
	attack_player.stream = _attack_music_stream
	attack_player.volume_db = attack_music_volume_db
	attack_player.play(sync_position)

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
	print("攻击阶段 BGM 已切换，起始进度: ", sync_position)


func end_attack_mix_mode() -> void:
	if attack_player != null and attack_player.playing:
		attack_player.stop()

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


func _on_attack_phase_started() -> void:
	begin_attack_mix_mode()


func _on_attack_phase_ended() -> void:
	end_attack_mix_mode()


func _load_attack_music_stream() -> AudioStream:
	if _attack_music_stream != null:
		return _attack_music_stream
	if attack_music_path.is_empty():
		return null

	var music_stream: AudioStream = load(attack_music_path)
	if music_stream == null:
		push_error("无法加载攻击阶段音乐文件: " + attack_music_path)
		return null

	_attack_music_stream = music_stream
	return _attack_music_stream


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

	if GameConfigs.sound and GameConfigs.sound.player_defense:
		var pool: RandomSoundPool = GameConfigs.sound.player_defense.get_miss_sound(0)
		if pool != null:
			SFXManager.play_pool(pool, GameConfigs.sound.player_defense.sfx_bus)

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
	if GameConfigs.sound and GameConfigs.sound.player_defense:
		var pool: RandomSoundPool = GameConfigs.sound.player_defense.get_miss_sound(note_type)
		if pool != null:
			SFXManager.play_pool(pool, GameConfigs.sound.player_defense.sfx_bus)

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
