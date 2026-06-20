extends Node

const MusicClockEventQueue := preload("res://scripts/MusicClockEventQueue.gd")
const AttackMusicFadeRules := preload("res://scripts/AttackMusicFadeRules.gd")
const RhythmClock := preload("res://scripts/RhythmClock.gd")
## 音乐播放器 - 负责加载和播放多轨道音乐
## BGM 轨道路由到 "BGM" 总线（受 LowPass 滤镜影响）
## Miss 音效通过 SFXManager 路由到 "SFX" 总线（不受 LowPass 影响）

@export var music_config: MusicConfig = null
@export_file("*.mp3", "*.ogg", "*.wav") var music_path: String = ""
@export_file("*.mp3", "*.ogg", "*.wav") var attack_music_path: String = ""
@export var auto_play: bool = true

@export_group("Attack Phase Music")
@export_file("*.mp3", "*.ogg", "*.wav") var attack_intro_music_path: String = ""
@export_file("*.mp3", "*.ogg", "*.wav") var attack_loop_music_path: String = ""
@export_file("*.mp3", "*.ogg", "*.wav") var attack_outro_music_path: String = ""
@export_range(-80.0, 24.0, 0.1) var attack_music_volume_db: float = 0.0
@export_range(0.0, 0.5, 0.01) var attack_music_fade_seconds: float = 0.08
@export_range(0.0, 1.5, 0.01) var attack_base_fade_seconds: float = 0.35
@export_range(0.0, 1.0, 0.01) var attack_segment_crossfade_seconds: float = 0.18
@export_range(0.0, 1.5, 0.01) var attack_return_fade_seconds: float = 0.35
@export_range(1, 64, 1) var attack_loop_phrase_beats: int = GameConstants.INPUT_BEATS
@export_range(0.0, 8.0, 0.25) var attack_base_crossfade_beats: float = 2.0
@export_range(0.0, 4.0, 0.25) var attack_segment_crossfade_beats: float = 1.0
@export_range(0.0, 8.0, 0.25) var attack_return_crossfade_beats: float = 2.0
@export_range(0.0, 8.0, 0.25) var attack_intro_delay_beats: float = 1.0
@export_range(-10.0, 10.0, 0.001) var attack_intro_offset_seconds: float = 0.0
@export_range(-10.0, 10.0, 0.001) var attack_loop_offset_seconds: float = 0.0
@export_range(-10.0, 10.0, 0.001) var attack_outro_offset_seconds: float = 0.0
@export var attack_keep_bass_track: bool = false

@export var enable_miss_audio_effect: bool = false

const NORMAL_CUTOFF: float = 20000.0
const MISS_CUTOFF: float = 500.0
const MISS_DURATION: float = 0.3

const NORMAL_VOLUME_DB: float = 0.0
const MISS_VOLUME_DB: float = -10.46

var lowpass_filter: AudioEffectLowPassFilter = null
var filter_tween: Tween = null
var volume_tween: Tween = null
var _base_music_tween: Tween = null
var _attack_mix_tween: Tween = null
var _attack_mix_active: bool = false
var _cached_main_volume_db: float = 0.0
var _cached_drum_volume_db: float = 0.0
var _cached_bass_volume_db: float = 0.0

var main_player: AudioStreamPlayer = null
var drum_player: AudioStreamPlayer = null
var bass_player: AudioStreamPlayer = null
var attack_player: AudioStreamPlayer = null
var attack_loop_player_a: AudioStreamPlayer = null
var attack_loop_player_b: AudioStreamPlayer = null
var attack_outro_player: AudioStreamPlayer = null
var _attack_music_stream: AudioStream = null
var _attack_intro_stream: AudioStream = null
var _attack_loop_stream: AudioStream = null
var _attack_outro_stream: AudioStream = null
var _attack_music_active: bool = false
var _waiting_for_boss_intro: bool = false
var _attack_base_return_started: bool = false
var _attack_schedule_token: int = 0
var _attack_track_setup_valid: bool = false
var _attack_beat_interval: float = 0.0
var _attack_first_input_time: float = 0.0
var _attack_countdown_beats: int = GameConstants.COUNTDOWN_BEATS
var _attack_input_beats: int = GameConstants.INPUT_BEATS
var _attack_exit_beats: int = GameConstants.EXIT_BEATS
var _attack_intro_start_time: float = 0.0
var _attack_loop_start_time: float = 0.0
var _attack_outro_start_time: float = 0.0
var _attack_phase_end_time: float = 0.0
var _active_attack_loop_player: AudioStreamPlayer = null
var _attack_player_fade_tweens: Dictionary = {}
var _attack_clock_callbacks: RefCounted = MusicClockEventQueue.new()
var _output_latency_seconds: float = 0.0
var _last_song_time: float = 0.0
var _song_time_frozen: bool = false
var _frozen_song_time: float = 0.0
var _attack_music_clock_active: bool = false
var _attack_music_clock_base_time: float = 0.0
var _attack_music_clock_wall_start: float = 0.0
var _base_pause_token: int = 0
var _ambient_attack_loop_active: bool = false
var _ambient_transition_token: int = 0

func _ready() -> void:
	_output_latency_seconds = AudioServer.get_output_latency()

	main_player = AudioStreamPlayer.new()
	drum_player = AudioStreamPlayer.new()
	bass_player = AudioStreamPlayer.new()
	attack_player = AudioStreamPlayer.new()
	attack_loop_player_a = AudioStreamPlayer.new()
	attack_loop_player_b = AudioStreamPlayer.new()
	attack_outro_player = AudioStreamPlayer.new()

	main_player.name = "MainPlayer"
	drum_player.name = "DrumPlayer"
	bass_player.name = "BassPlayer"
	attack_player.name = "AttackPlayer"
	attack_loop_player_a.name = "AttackLoopPlayerA"
	attack_loop_player_b.name = "AttackLoopPlayerB"
	attack_outro_player.name = "AttackOutroPlayer"

	add_child(main_player)
	add_child(drum_player)
	add_child(bass_player)
	add_child(attack_player)
	add_child(attack_loop_player_a)
	add_child(attack_loop_player_b)
	add_child(attack_outro_player)

	if not attack_loop_player_a.finished.is_connected(_on_ambient_attack_loop_finished):
		attack_loop_player_a.finished.connect(_on_ambient_attack_loop_finished)

	main_player.bus = "BGM"
	drum_player.bus = "BGM"
	bass_player.bus = "BGM"
	attack_player.bus = "BGM"
	attack_loop_player_a.bus = "BGM"
	attack_loop_player_b.bus = "BGM"
	attack_outro_player.bus = "BGM"

	if not EventBus.attack_phase_started.is_connected(_on_attack_phase_started):
		EventBus.attack_phase_started.connect(_on_attack_phase_started)
	if not EventBus.attack_phase_ended.is_connected(_on_attack_phase_ended):
		EventBus.attack_phase_ended.connect(_on_attack_phase_ended)
	if not EventBus.attack_track_setup.is_connected(_on_attack_track_setup):
		EventBus.attack_track_setup.connect(_on_attack_track_setup)

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


func _process(_delta: float) -> void:
	_process_attack_clock_callbacks()


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


func play_ambient_attack_loop(fade_seconds: float = 1.0) -> bool:
	var stream: AudioStream = _load_ambient_attack_loop_stream()
	if stream == null:
		return false

	if _base_music_tween != null:
		_base_music_tween.kill()
		_base_music_tween = null

	_stop_attack_music_clock()
	_attack_schedule_token += 1
	_attack_clock_callbacks.clear()
	_attack_music_active = false
	_attack_mix_active = false
	_attack_base_return_started = false
	_ambient_attack_loop_active = true
	_last_song_time = 0.0

	if attack_loop_player_a.stream == stream and attack_loop_player_a.playing:
		_fade_in_attack_player(attack_loop_player_a, fade_seconds)
		return true

	_stop_attack_players()
	attack_loop_player_a.stream = stream
	attack_loop_player_a.stream_paused = false
	attack_loop_player_a.pitch_scale = 1.0
	attack_loop_player_a.volume_db = -80.0 if fade_seconds > 0.0 else attack_music_volume_db
	attack_loop_player_a.play()
	_active_attack_loop_player = attack_loop_player_a
	if fade_seconds > 0.0:
		_fade_in_attack_player(attack_loop_player_a, fade_seconds)
	return true


func crossfade_ambient_attack_loop_to_base_music(fade_seconds: float = 1.0) -> bool:
	if not _load_base_music_for_playback():
		return false

	var fade_duration: float = maxf(0.0, fade_seconds)
	var main_target: float = main_player.volume_db
	var drum_target: float = drum_player.volume_db
	var bass_target: float = bass_player.volume_db

	_ambient_transition_token += 1
	_ambient_attack_loop_active = false
	_stop_attack_music_clock()
	_attack_schedule_token += 1
	_attack_clock_callbacks.clear()
	_attack_music_active = false
	_attack_mix_active = false
	_attack_base_return_started = false

	_fade_out_attack_players(fade_duration)
	_play_base_tracks_from_start(main_target, drum_target, bass_target, fade_duration)
	EventBus.music_started.emit()
	print("Base battle music crossfaded in from ambient attack loop")
	return true


func crossfade_base_music_to_ambient_attack_loop(fade_seconds: float = 1.0) -> bool:
	var stream: AudioStream = _load_ambient_attack_loop_stream()
	if stream == null:
		return false

	var fade_duration: float = maxf(0.0, fade_seconds)
	var ambient_offset: float = 0.0
	var stream_length: float = _get_stream_length(stream)
	if stream_length > 0.0:
		ambient_offset = fposmod(get_song_time(), stream_length)

	_ambient_transition_token += 1
	_ambient_attack_loop_active = true
	_stop_attack_music_clock()
	_attack_schedule_token += 1
	_attack_clock_callbacks.clear()
	_attack_music_active = false
	_attack_mix_active = false
	_attack_base_return_started = false
	_last_song_time = 0.0

	_fade_out_base_tracks(fade_duration, true)
	_start_attack_player_from_offset(attack_loop_player_a, stream, ambient_offset, fade_duration)
	_active_attack_loop_player = attack_loop_player_a
	print("Ambient attack loop crossfaded back in")
	return true


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


func _load_base_music_for_playback() -> bool:
	if music_config:
		_load_from_config()
	elif music_path != "":
		_load_single_track(music_path)
	else:
		push_warning("No base battle music configured.")
		return false

	return main_player.stream != null or drum_player.stream != null or bass_player.stream != null


func _load_ambient_attack_loop_stream() -> AudioStream:
	var loop_path: String = attack_loop_music_path
	if loop_path.is_empty():
		loop_path = attack_music_path
	if loop_path.is_empty():
		push_warning("No ambient attack loop music configured.")
		return null
	var stream: AudioStream = _load_attack_stream_from_path(loop_path)
	return _make_looping_stream(stream)


func _make_looping_stream(stream: AudioStream) -> AudioStream:
	if stream == null:
		return null

	var looping_stream: AudioStream = stream.duplicate() as AudioStream
	if looping_stream == null:
		return stream

	for property in looping_stream.get_property_list():
		var property_name: String = String(property.get("name", ""))
		if property_name == "loop":
			looping_stream.set("loop", true)
		elif property_name == "loop_mode":
			looping_stream.set("loop_mode", 1)
	return looping_stream


func _on_ambient_attack_loop_finished() -> void:
	if not _ambient_attack_loop_active:
		return
	if attack_loop_player_a == null or attack_loop_player_a.stream == null:
		return
	if _active_attack_loop_player != attack_loop_player_a:
		return
	attack_loop_player_a.volume_db = attack_music_volume_db
	attack_loop_player_a.play()


func _play_base_tracks_from_start(
	main_target_db: float,
	drum_target_db: float,
	bass_target_db: float,
	fade_seconds: float
) -> void:
	if _base_music_tween != null:
		_base_music_tween.kill()
		_base_music_tween = null

	_base_pause_token += 1
	_song_time_frozen = false
	_frozen_song_time = 0.0
	_last_song_time = 0.0

	for player in [main_player, drum_player, bass_player]:
		var audio_player: AudioStreamPlayer = player as AudioStreamPlayer
		if audio_player == null or audio_player.stream == null:
			continue
		audio_player.stop()
		audio_player.stream_paused = false

	if main_player.stream:
		main_player.volume_db = -80.0 if fade_seconds > 0.0 else main_target_db
		main_player.play()
	if drum_player.stream:
		drum_player.volume_db = -80.0 if fade_seconds > 0.0 else drum_target_db
		drum_player.play()
	if bass_player.stream:
		bass_player.volume_db = -80.0 if fade_seconds > 0.0 else bass_target_db
		bass_player.play()

	if fade_seconds <= 0.0:
		return

	_base_music_tween = create_tween()
	_base_music_tween.set_parallel(true)
	_base_music_tween.set_ease(Tween.EASE_OUT)
	_base_music_tween.set_trans(Tween.TRANS_SINE)
	if main_player.stream:
		_base_music_tween.tween_property(main_player, "volume_db", main_target_db, fade_seconds)
	if drum_player.stream:
		_base_music_tween.tween_property(drum_player, "volume_db", drum_target_db, fade_seconds)
	if bass_player.stream:
		_base_music_tween.tween_property(bass_player, "volume_db", bass_target_db, fade_seconds)
	_base_music_tween.finished.connect(func() -> void:
		_base_music_tween = null
	)


func _fade_out_base_tracks(duration: float, stop_after: bool) -> void:
	if _base_music_tween != null:
		_base_music_tween.kill()
		_base_music_tween = null

	var fade_duration: float = maxf(0.0, duration)
	var token: int = _ambient_transition_token
	if fade_duration <= 0.0:
		_set_base_track_volumes(-80.0, -80.0, -80.0)
		if stop_after:
			_stop_base_tracks_if_current(token)
		return

	_base_music_tween = create_tween()
	_base_music_tween.set_parallel(true)
	_base_music_tween.set_ease(Tween.EASE_OUT)
	_base_music_tween.set_trans(Tween.TRANS_SINE)
	if main_player.stream and main_player.playing:
		_base_music_tween.tween_property(main_player, "volume_db", -80.0, fade_duration)
	if drum_player.stream and drum_player.playing:
		_base_music_tween.tween_property(drum_player, "volume_db", -80.0, fade_duration)
	if bass_player.stream and bass_player.playing:
		_base_music_tween.tween_property(bass_player, "volume_db", -80.0, fade_duration)
	_base_music_tween.finished.connect(func() -> void:
		if token != _ambient_transition_token:
			return
		_base_music_tween = null
		if stop_after:
			_stop_base_tracks_if_current(token)
	)


func _stop_base_tracks_if_current(token: int) -> void:
	if token != _ambient_transition_token:
		return
	for player in [main_player, drum_player, bass_player]:
		var audio_player: AudioStreamPlayer = player as AudioStreamPlayer
		if audio_player == null:
			continue
		audio_player.stream_paused = false
		audio_player.stop()


func _play_all_tracks() -> void:
	_last_song_time = 0.0
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
	if _base_music_tween != null:
		_base_music_tween.kill()
		_base_music_tween = null
	_attack_schedule_token += 1
	_ambient_transition_token += 1
	_attack_clock_callbacks.clear()
	main_player.stop()
	drum_player.stop()
	bass_player.stop()
	_stop_attack_players()
	_attack_music_active = false
	_attack_mix_active = false
	_ambient_attack_loop_active = false
	_last_song_time = 0.0


func fade_out_all_for_death(duration: float = 1.2, target_volume_db: float = -40.0) -> void:
	var fade_duration: float = maxf(0.05, duration)
	var target_db: float = clampf(target_volume_db, -80.0, 0.0)

	if volume_tween != null:
		volume_tween.kill()
	if _base_music_tween != null:
		_base_music_tween.kill()
		_base_music_tween = null

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
	if attack_loop_player_a != null and attack_loop_player_a.stream:
		volume_tween.tween_property(attack_loop_player_a, "volume_db", target_db, fade_duration)
	if attack_loop_player_b != null and attack_loop_player_b.stream:
		volume_tween.tween_property(attack_loop_player_b, "volume_db", target_db, fade_duration)
	if attack_outro_player != null and attack_outro_player.stream:
		volume_tween.tween_property(attack_outro_player, "volume_db", target_db, fade_duration)


func pause_music() -> void:
	_frozen_song_time = get_song_time()
	_song_time_frozen = true
	main_player.stream_paused = true
	drum_player.stream_paused = true
	bass_player.stream_paused = true
	if attack_player != null:
		attack_player.stream_paused = true
	if attack_loop_player_a != null:
		attack_loop_player_a.stream_paused = true
	if attack_loop_player_b != null:
		attack_loop_player_b.stream_paused = true
	if attack_outro_player != null:
		attack_outro_player.stream_paused = true
	print("音乐已暂停")


func resume_music() -> void:
	main_player.stream_paused = false
	drum_player.stream_paused = false
	bass_player.stream_paused = false
	if attack_player != null:
		attack_player.stream_paused = false
	if attack_loop_player_a != null:
		attack_loop_player_a.stream_paused = false
	if attack_loop_player_b != null:
		attack_loop_player_b.stream_paused = false
	if attack_outro_player != null:
		attack_outro_player.stream_paused = false
	_last_song_time = maxf(_last_song_time, _frozen_song_time)
	_song_time_frozen = false
	print("Music resumed")


func pause_base_music_for_attack() -> void:
	_frozen_song_time = get_song_time()
	_song_time_frozen = true
	main_player.stream_paused = true
	drum_player.stream_paused = true
	bass_player.stream_paused = true
	print("Base music paused for attack phase")


func freeze_base_music_clock_for_attack() -> void:
	_frozen_song_time = get_song_time()
	_song_time_frozen = true
	_base_pause_token += 1


func pause_base_tracks_after_attack_fade(duration: float) -> void:
	var token: int = _base_pause_token
	var delay: float = maxf(0.0, duration)
	if delay <= 0.0:
		_pause_and_rewind_base_tracks_for_attack(token)
		return

	get_tree().create_timer(delay).timeout.connect(func() -> void:
		_pause_and_rewind_base_tracks_for_attack(token)
	)


func _pause_and_rewind_base_tracks_for_attack(token: int) -> void:
	if token != _base_pause_token:
		return
	if not _song_time_frozen:
		return

	for player in [main_player, drum_player, bass_player]:
		var audio_player: AudioStreamPlayer = player as AudioStreamPlayer
		if audio_player == null or audio_player.stream == null:
			continue
		audio_player.seek(maxf(0.0, _frozen_song_time))
		audio_player.stream_paused = true


func begin_attack_mix_mode() -> void:
	_begin_attack_mix_mode()


func end_attack_mix_mode() -> void:
	_end_attack_mix_mode()


func _on_attack_track_setup(
	bi: float,
	first_beat_time: float,
	countdown_beats: int = GameConstants.COUNTDOWN_BEATS,
	input_beats: int = GameConstants.INPUT_BEATS,
	exit_beats: int = GameConstants.EXIT_BEATS
) -> void:
	_attack_track_setup_valid = bi > 0.0
	_attack_beat_interval = bi
	_attack_first_input_time = first_beat_time
	_attack_countdown_beats = maxi(1, countdown_beats)
	_attack_input_beats = maxi(1, input_beats)
	_attack_exit_beats = maxi(1, exit_beats)


func _on_attack_phase_started() -> void:
	freeze_base_music_clock_for_attack()
	_start_attack_music_clock(_frozen_song_time)
	begin_attack_mix_mode()
	pause_base_tracks_after_attack_fade(_get_attack_entry_base_fade_seconds())


func _on_attack_phase_ended() -> void:
	end_attack_mix_mode()
	_stop_attack_music_clock()
	resume_music()


func _begin_attack_mix_mode() -> void:
	if _attack_music_active:
		return
	if main_player == null or drum_player == null or bass_player == null:
		return
	if main_player.stream == null and drum_player.stream == null and bass_player.stream == null:
		return

	if not _load_attack_phase_streams():
		push_warning("Attack phase music is not configured; keep current BGM mix.")
		return

	if _attack_mix_tween != null:
		_attack_mix_tween.kill()
		_attack_mix_tween = null
	if _attack_mix_active:
		_set_base_track_volumes(_cached_main_volume_db, _cached_drum_volume_db, _cached_bass_volume_db)
		_attack_mix_active = false
		_attack_base_return_started = false

	_cached_main_volume_db = main_player.volume_db if main_player != null else 0.0
	_cached_drum_volume_db = drum_player.volume_db if drum_player != null else 0.0
	_cached_bass_volume_db = bass_player.volume_db if bass_player != null else 0.0

	_stop_attack_players()
	_attack_schedule_token += 1
	_attack_clock_callbacks.clear()
	_attack_music_active = true
	_attack_mix_active = true
	_attack_base_return_started = false
	_fade_base_tracks_for_attack()

	var token: int = _attack_schedule_token
	if _is_single_attack_music_mode():
		_start_single_attack_music(token)
	else:
		_start_split_attack_music(token)


func _end_attack_mix_mode() -> void:
	_attack_schedule_token += 1
	_attack_clock_callbacks.clear()
	_attack_track_setup_valid = false
	_attack_music_active = false
	_resume_base_tracks_for_attack_return()
	var return_fade_duration: float = attack_music_fade_seconds if _attack_base_return_started else _get_attack_return_fade_seconds()
	_fade_out_attack_players(return_fade_duration)

	if not _attack_mix_active:
		return

	if _attack_mix_tween != null:
		_attack_mix_tween.kill()
		_attack_mix_tween = null

	if _attack_base_return_started:
		_set_base_track_volumes(_cached_main_volume_db, _cached_drum_volume_db, _cached_bass_volume_db)
		_attack_mix_active = false
		_attack_base_return_started = false
		return

	var fade_duration: float = return_fade_duration
	if fade_duration <= 0.0:
		_set_base_track_volumes(_cached_main_volume_db, _cached_drum_volume_db, _cached_bass_volume_db)
		_attack_mix_active = false
		_attack_base_return_started = false
		return

	_attack_mix_tween = create_tween()
	_attack_mix_tween.set_parallel(true)
	_attack_mix_tween.set_ease(Tween.EASE_IN)
	_attack_mix_tween.set_trans(Tween.TRANS_CUBIC)

	if main_player != null and main_player.stream:
		_attack_mix_tween.tween_property(main_player, "volume_db", _cached_main_volume_db, fade_duration)
	if drum_player != null and drum_player.stream:
		_attack_mix_tween.tween_property(drum_player, "volume_db", _cached_drum_volume_db, fade_duration)
	if bass_player != null and bass_player.stream:
		_attack_mix_tween.tween_property(bass_player, "volume_db", _cached_bass_volume_db, fade_duration)
	_attack_mix_tween.finished.connect(func() -> void:
		_set_base_track_volumes(_cached_main_volume_db, _cached_drum_volume_db, _cached_bass_volume_db)
		_attack_mix_active = false
		_attack_base_return_started = false
		_attack_mix_tween = null
	)


func _load_attack_phase_streams() -> bool:
	_attack_music_stream = null
	_attack_intro_stream = null
	_attack_loop_stream = null
	_attack_outro_stream = null

	if _is_single_attack_music_mode():
		_attack_music_stream = _load_attack_stream_from_path(attack_music_path)
		return _attack_music_stream != null

	_attack_intro_stream = _load_attack_stream_from_path(attack_intro_music_path)

	var loop_path: String = attack_loop_music_path
	if loop_path.is_empty() and not attack_music_path.is_empty():
		loop_path = attack_music_path
	_attack_loop_stream = _load_attack_stream_from_path(loop_path)

	_attack_outro_stream = _load_attack_stream_from_path(attack_outro_music_path)

	return _attack_intro_stream != null or _attack_loop_stream != null or _attack_outro_stream != null


func _load_attack_stream_from_path(path: String) -> AudioStream:
	if path.is_empty():
		return null

	var stream: AudioStream = load(path)
	if stream == null:
		push_error("Unable to load attack phase music: " + path)
	return stream


func _is_single_attack_music_mode() -> bool:
	return attack_intro_music_path.is_empty() and attack_loop_music_path.is_empty() and attack_outro_music_path.is_empty()


func _fade_base_tracks_for_attack() -> void:
	var fade_duration: float = _get_attack_entry_base_fade_seconds()
	var bass_target_db: float = _cached_bass_volume_db if attack_keep_bass_track else -80.0

	if _attack_mix_tween != null:
		_attack_mix_tween.kill()
		_attack_mix_tween = null

	if fade_duration <= 0.0:
		if main_player != null and main_player.stream:
			main_player.volume_db = -80.0
		if drum_player != null and drum_player.stream:
			drum_player.volume_db = -80.0
		if bass_player != null and bass_player.stream:
			bass_player.volume_db = bass_target_db
		return

	_attack_mix_tween = create_tween()
	_attack_mix_tween.set_parallel(true)
	_attack_mix_tween.set_ease(Tween.EASE_OUT)
	_attack_mix_tween.set_trans(Tween.TRANS_CUBIC)

	if main_player != null and main_player.stream:
		_attack_mix_tween.tween_property(main_player, "volume_db", -80.0, fade_duration)
	if drum_player != null and drum_player.stream:
		_attack_mix_tween.tween_property(drum_player, "volume_db", -80.0, fade_duration)
	if bass_player != null and bass_player.stream:
		_attack_mix_tween.tween_property(bass_player, "volume_db", bass_target_db, fade_duration)


func _restore_base_tracks_for_attack(duration: float) -> void:
	if not _attack_mix_active:
		return

	_attack_base_return_started = true
	if _attack_mix_tween != null:
		_attack_mix_tween.kill()
		_attack_mix_tween = null

	var fade_duration: float = maxf(0.0, duration)
	if fade_duration <= 0.0:
		_set_base_track_volumes(_cached_main_volume_db, _cached_drum_volume_db, _cached_bass_volume_db)
		return

	_attack_mix_tween = create_tween()
	_attack_mix_tween.set_parallel(true)
	_attack_mix_tween.set_ease(Tween.EASE_IN)
	_attack_mix_tween.set_trans(Tween.TRANS_CUBIC)

	if main_player != null and main_player.stream:
		_attack_mix_tween.tween_property(main_player, "volume_db", _cached_main_volume_db, fade_duration)
	if drum_player != null and drum_player.stream:
		_attack_mix_tween.tween_property(drum_player, "volume_db", _cached_drum_volume_db, fade_duration)
	if bass_player != null and bass_player.stream:
		_attack_mix_tween.tween_property(bass_player, "volume_db", _cached_bass_volume_db, fade_duration)


func _set_base_track_volumes(main_db: float, drum_db: float, bass_db: float) -> void:
	if main_player != null and main_player.stream:
		main_player.volume_db = main_db
	if drum_player != null and drum_player.stream:
		drum_player.volume_db = drum_db
	if bass_player != null and bass_player.stream:
		bass_player.volume_db = bass_db


func _start_single_attack_music(token: int) -> void:
	if token != _attack_schedule_token or _attack_music_stream == null:
		return

	var sync_position: float = _get_music_clock_time()
	_start_attack_player_from_offset(attack_player, _attack_music_stream, sync_position, _get_attack_base_crossfade_seconds())
	print("Attack phase single-track BGM started at: ", sync_position)


func _start_split_attack_music(token: int) -> void:
	if token != _attack_schedule_token:
		return

	var bi: float = _resolve_attack_beat_interval()
	var now: float = _get_music_clock_time()
	if not _attack_track_setup_valid:
		_attack_countdown_beats = GameConstants.COUNTDOWN_BEATS
		_attack_input_beats = GameConstants.INPUT_BEATS
		_attack_exit_beats = GameConstants.EXIT_BEATS
		_attack_first_input_time = now + float(_attack_countdown_beats) * bi

	_attack_loop_start_time = _attack_first_input_time
	_attack_outro_start_time = _attack_first_input_time + float(_attack_input_beats) * bi
	_attack_phase_end_time = _attack_outro_start_time + float(_attack_exit_beats) * bi

	_attack_intro_start_time = _get_attack_intro_start_time(bi)
	if _attack_intro_stream != null and now < _attack_loop_start_time:
		var intro_stream_start_time: float = _get_attack_stream_start_time(_attack_intro_start_time, attack_intro_offset_seconds)
		if now < intro_stream_start_time:
			_schedule_attack_clock_callback(intro_stream_start_time, Callable(self, "_start_attack_intro"), token)
		else:
			_start_attack_intro(token)

	if _attack_loop_stream != null:
		var initial_loop_phrase_index: int = _get_loop_phrase_index_for_time(now)
		var initial_loop_grid_start: float = _get_loop_phrase_grid_start(initial_loop_phrase_index, bi)
		var initial_loop_stream_start: float = _get_attack_stream_start_time(initial_loop_grid_start, attack_loop_offset_seconds)
		if now < initial_loop_stream_start:
			_schedule_attack_clock_callback(initial_loop_stream_start, Callable(self, "_start_attack_loop"), token, [initial_loop_phrase_index])
		elif now < _attack_outro_start_time:
			_start_attack_loop(token, initial_loop_phrase_index)

	if _attack_outro_stream != null:
		var outro_stream_start_time: float = _get_attack_stream_start_time(_attack_outro_start_time, attack_outro_offset_seconds)
		if now < outro_stream_start_time:
			_schedule_attack_clock_callback(outro_stream_start_time, Callable(self, "_start_attack_outro"), token)
		elif now < _attack_phase_end_time:
			_start_attack_outro(token)
	else:
		if now < _attack_outro_start_time:
			_schedule_attack_clock_callback(_attack_outro_start_time, Callable(self, "_start_attack_return"), token)
		elif now < _attack_phase_end_time:
			_start_attack_return(token)

	print("Attack phase split BGM scheduled. bi=", bi,
		" input=", _attack_loop_start_time,
		" outro=", _attack_outro_start_time,
		" end=", _attack_phase_end_time)


func _get_attack_intro_start_time(bi: float) -> float:
	var intro_window_start: float = _attack_loop_start_time - float(_attack_countdown_beats) * bi
	var delay_seconds: float = maxf(0.0, attack_intro_delay_beats) * maxf(0.0, bi)
	var latest_start_before_loop: float = _attack_loop_start_time - maxf(0.01, minf(_get_attack_segment_crossfade_seconds(), bi * 0.5))
	return minf(intro_window_start + delay_seconds, latest_start_before_loop)


func _start_attack_intro(token: int) -> void:
	if token != _attack_schedule_token or not _attack_music_active:
		return
	if _attack_intro_stream == null:
		return
	if _get_music_clock_time() >= _attack_loop_start_time:
		return
	_play_attack_stream_at_clock(
		attack_player,
		_attack_intro_stream,
		_attack_intro_start_time,
		false,
		attack_intro_offset_seconds,
		_get_attack_intro_fade_seconds()
	)


func _start_attack_loop(token: int, phrase_index: int = -1) -> void:
	if token != _attack_schedule_token or not _attack_music_active:
		return
	if _attack_loop_stream == null:
		return
	if _get_music_clock_time() >= _attack_outro_start_time:
		return

	if phrase_index < 0:
		phrase_index = _get_loop_phrase_index_for_time(_get_music_clock_time())

	var crossfade_duration: float = _get_attack_segment_crossfade_seconds()
	_fade_out_attack_player(attack_player, crossfade_duration, true)
	_fade_out_attack_player(attack_outro_player, crossfade_duration, true)

	_active_attack_loop_player = attack_loop_player_a
	_play_attack_loop_player(_active_attack_loop_player, phrase_index, 0.0)
	_schedule_next_attack_loop_restart(token, phrase_index)


func _restart_attack_loop(token: int, phrase_index: int = -1) -> void:
	if token != _attack_schedule_token or not _attack_music_active:
		return
	if _attack_loop_stream == null:
		return
	if _get_music_clock_time() >= _attack_outro_start_time:
		return

	if phrase_index < 0:
		phrase_index = _get_loop_phrase_index_for_time(_get_music_clock_time())

	var old_player: AudioStreamPlayer = _active_attack_loop_player
	var next_player: AudioStreamPlayer = attack_loop_player_b
	if old_player == attack_loop_player_b:
		next_player = attack_loop_player_a

	var crossfade_duration: float = _get_attack_segment_crossfade_seconds()
	_play_attack_loop_player(next_player, phrase_index, crossfade_duration)
	_active_attack_loop_player = next_player

	if old_player != null and old_player != next_player:
		_fade_out_attack_player(old_player, crossfade_duration, true)

	_schedule_next_attack_loop_restart(token, phrase_index)


func _start_attack_outro(token: int) -> void:
	if token != _attack_schedule_token or not _attack_music_active:
		return
	if _attack_outro_stream == null:
		return

	var crossfade_duration: float = _get_attack_segment_crossfade_seconds()
	_begin_attack_return_transition(crossfade_duration, true)

	_play_attack_stream_at_clock(
		attack_outro_player,
		_attack_outro_stream,
		_attack_outro_start_time,
		false,
		attack_outro_offset_seconds,
		crossfade_duration
	)


func _start_attack_return(token: int) -> void:
	if token != _attack_schedule_token or not _attack_music_active:
		return

	_begin_attack_return_transition(_get_attack_segment_crossfade_seconds(), false)


func _begin_attack_return_transition(crossfade_duration: float, defer_base_return: bool) -> void:
	_fade_out_attack_player(attack_player, crossfade_duration, true)
	_fade_out_attack_player(attack_loop_player_a, crossfade_duration, true)
	_fade_out_attack_player(attack_loop_player_b, crossfade_duration, true)
	_active_attack_loop_player = null
	if defer_base_return:
		_schedule_base_return_for_attack()
		return
	_start_base_return_for_attack()


func _schedule_base_return_for_attack() -> void:
	var restore_duration: float = _get_attack_return_restore_seconds()
	if restore_duration <= 0.0:
		_start_base_return_for_attack()
		return

	var return_start_time: float = _attack_phase_end_time - restore_duration
	if _get_music_clock_time() >= return_start_time:
		_start_base_return_for_attack()
		return

	var token: int = _attack_schedule_token
	_schedule_attack_clock_callback(return_start_time, Callable(self, "_on_base_return_time"), token)


func _on_base_return_time(token: int) -> void:
	if token != _attack_schedule_token or not _attack_music_active:
		return
	_start_base_return_for_attack()


func _start_base_return_for_attack() -> void:
	_resume_base_tracks_for_attack_return()
	_restore_base_tracks_for_attack(_get_attack_return_restore_seconds())


func _resume_base_tracks_for_attack_return() -> void:
	_base_pause_token += 1
	for player in [main_player, drum_player, bass_player]:
		var audio_player: AudioStreamPlayer = player as AudioStreamPlayer
		if audio_player == null or audio_player.stream == null:
			continue
		audio_player.stream_paused = false


func _play_attack_loop_player(player: AudioStreamPlayer, phrase_index: int, fade_in_seconds: float = 0.0) -> bool:
	var bi: float = _resolve_attack_beat_interval()
	var phrase_grid_start: float = _get_loop_phrase_grid_start(phrase_index, bi)
	return _play_attack_stream_at_clock(
		player,
		_attack_loop_stream,
		phrase_grid_start,
		true,
		attack_loop_offset_seconds,
		fade_in_seconds
	)


func _play_attack_stream_at_clock(
	player: AudioStreamPlayer,
	stream: AudioStream,
	start_time: float,
	wrap: bool,
	stream_offset_seconds: float = 0.0,
	fade_in_seconds: float = -1.0
) -> bool:
	if stream == null:
		return false

	var offset: float = _get_music_clock_time() - start_time - stream_offset_seconds
	if offset < 0.0:
		return false

	var stream_length: float = _get_stream_length(stream)
	if stream_length > 0.0:
		if wrap:
			offset = fposmod(offset, stream_length)
		elif offset >= stream_length:
			return false

	return _start_attack_player_from_offset(player, stream, offset, fade_in_seconds)


func _start_attack_player_from_offset(player: AudioStreamPlayer, stream: AudioStream, offset: float, fade_in_seconds: float = -1.0) -> bool:
	if player == null or stream == null:
		return false

	_kill_attack_player_fade(player)
	player.stop()
	player.stream = stream
	player.stream_paused = false
	player.pitch_scale = 1.0
	var fade_duration: float = _get_attack_segment_crossfade_seconds() if fade_in_seconds < 0.0 else maxf(0.0, fade_in_seconds)
	player.volume_db = -80.0 if fade_duration > 0.0 else attack_music_volume_db
	player.play(maxf(0.0, offset))
	if fade_duration > 0.0:
		_fade_in_attack_player(player, fade_duration)
	return true


func _schedule_next_attack_loop_restart(token: int, current_phrase_index: int) -> void:
	var bi: float = _resolve_attack_beat_interval()
	var phrase_duration: float = maxf(0.01, float(maxi(1, attack_loop_phrase_beats)) * bi)
	var next_phrase_index: int = maxi(0, current_phrase_index + 1)
	var next_phrase_grid_start: float = _attack_loop_start_time + float(next_phrase_index) * phrase_duration

	if next_phrase_grid_start >= _attack_outro_start_time - 0.01:
		return

	var next_stream_start_time: float = _get_attack_stream_start_time(next_phrase_grid_start, attack_loop_offset_seconds)
	_schedule_attack_clock_callback(next_stream_start_time, Callable(self, "_restart_attack_loop"), token, [next_phrase_index])


func _schedule_attack_clock_callback(target_time: float, callback: Callable, token: int, args: Array = []) -> void:
	_attack_clock_callbacks.schedule(target_time, Callable(self, "_on_attack_clock_callback_due"), [token, callback, args])


func _process_attack_clock_callbacks() -> void:
	_attack_clock_callbacks.process(_get_music_clock_time())


func _on_attack_clock_callback_due(token: int, callback: Callable, args: Array) -> void:
	if token != _attack_schedule_token or not _attack_music_active:
		return
	if callback.is_valid():
		var callback_args: Array = [token]
		callback_args.append_array(args)
		callback.callv(callback_args)


func _resolve_attack_beat_interval() -> float:
	if _attack_beat_interval > 0.0:
		return _attack_beat_interval
	if EventBus.beat_interval > 0.0:
		return EventBus.beat_interval
	return 0.5


func _get_attack_stream_start_time(grid_start_time: float, stream_offset_seconds: float) -> float:
	return grid_start_time + stream_offset_seconds


func _get_loop_phrase_grid_start(phrase_index: int, bi: float) -> float:
	var phrase_duration: float = maxf(0.01, float(maxi(1, attack_loop_phrase_beats)) * bi)
	return _attack_loop_start_time + float(maxi(0, phrase_index)) * phrase_duration


func _get_loop_phrase_index_for_time(time: float) -> int:
	var bi: float = _resolve_attack_beat_interval()
	var phrase_duration: float = maxf(0.01, float(maxi(1, attack_loop_phrase_beats)) * bi)
	var elapsed: float = maxf(0.0, time - _attack_loop_start_time)
	return int(floor(elapsed / phrase_duration))


func _get_music_clock_time() -> float:
	if _attack_music_clock_active:
		return _attack_music_clock_base_time + (RhythmClock.get_wall_time_seconds() - _attack_music_clock_wall_start)
	return get_song_time()


func _start_attack_music_clock(base_time: float) -> void:
	_attack_music_clock_base_time = base_time
	_attack_music_clock_wall_start = RhythmClock.get_wall_time_seconds()
	_attack_music_clock_active = true


func _stop_attack_music_clock() -> void:
	_attack_music_clock_active = false


func _get_stream_length(stream: AudioStream) -> float:
	if stream == null:
		return 0.0
	return maxf(0.0, stream.get_length())


func _fade_out_attack_players(duration: float) -> void:
	for candidate in _get_attack_players():
		var player: AudioStreamPlayer = candidate as AudioStreamPlayer
		_fade_out_attack_player(player, duration, true)
	_active_attack_loop_player = null


func _fade_in_attack_player(player: AudioStreamPlayer, duration: float) -> void:
	if player == null:
		return
	_kill_attack_player_fade(player)

	var fade_duration: float = maxf(0.0, duration)
	if fade_duration <= 0.0:
		player.volume_db = attack_music_volume_db
		return

	var player_id: int = player.get_instance_id()
	var tween: Tween = create_tween()
	_attack_player_fade_tweens[player_id] = tween
	tween.tween_property(player, "volume_db", attack_music_volume_db, fade_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.finished.connect(func() -> void:
		if _attack_player_fade_tweens.get(player_id) != tween:
			return
		_attack_player_fade_tweens.erase(player_id)
	)


func _fade_out_attack_player(player: AudioStreamPlayer, duration: float, stop_after: bool) -> void:
	if player == null:
		return
	_kill_attack_player_fade(player)
	if not player.playing:
		if stop_after:
			player.stop()
		return

	var fade_duration: float = maxf(0.0, duration)
	if fade_duration <= 0.0:
		player.volume_db = -80.0
		if stop_after:
			player.stop()
		return

	var player_id: int = player.get_instance_id()
	var tween: Tween = create_tween()
	_attack_player_fade_tweens[player_id] = tween
	tween.tween_property(player, "volume_db", -80.0, fade_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if stop_after:
		tween.finished.connect(func() -> void:
			if _attack_player_fade_tweens.get(player_id) != tween:
				return
			_attack_player_fade_tweens.erase(player_id)
			if player != null and is_instance_valid(player):
				player.stop()
		)


func _kill_attack_player_fade(player: AudioStreamPlayer) -> void:
	if player == null:
		return
	var player_id: int = player.get_instance_id()
	var tween: Tween = _attack_player_fade_tweens.get(player_id) as Tween
	if tween != null:
		tween.kill()
	_attack_player_fade_tweens.erase(player_id)


func _stop_attack_players() -> void:
	for candidate in _get_attack_players():
		var player: AudioStreamPlayer = candidate as AudioStreamPlayer
		if player == null:
			continue
		_kill_attack_player_fade(player)
		player.stream_paused = false
		player.stop()
	_active_attack_loop_player = null


func _get_attack_players() -> Array:
	return [attack_player, attack_loop_player_a, attack_loop_player_b, attack_outro_player]


func _get_attack_base_fade_seconds() -> float:
	return AttackMusicFadeRules.base_fade_seconds(attack_music_fade_seconds, attack_base_fade_seconds)


func _get_attack_segment_crossfade_seconds() -> float:
	return AttackMusicFadeRules.segment_crossfade_seconds(
		attack_music_fade_seconds,
		attack_segment_crossfade_seconds,
		attack_segment_crossfade_beats,
		_resolve_attack_beat_interval()
	)


func _get_attack_return_fade_seconds() -> float:
	return AttackMusicFadeRules.return_fade_seconds(attack_music_fade_seconds, attack_return_fade_seconds)


func _get_attack_base_crossfade_seconds() -> float:
	return AttackMusicFadeRules.base_crossfade_seconds(
		attack_music_fade_seconds,
		attack_base_fade_seconds,
		attack_base_crossfade_beats,
		attack_intro_delay_beats,
		_resolve_attack_beat_interval()
	)


func _get_attack_entry_base_fade_seconds() -> float:
	var intro_window_seconds: float = float(maxi(1, _attack_countdown_beats)) * _resolve_attack_beat_interval()
	return maxf(_get_attack_base_crossfade_seconds(), intro_window_seconds)


func _get_attack_intro_fade_seconds() -> float:
	var available: float = maxf(0.0, _attack_loop_start_time - _attack_intro_start_time)
	return minf(maxf(0.0, attack_music_fade_seconds), available)


func _get_attack_return_crossfade_seconds() -> float:
	return AttackMusicFadeRules.return_crossfade_seconds(
		attack_music_fade_seconds,
		attack_return_fade_seconds,
		attack_return_crossfade_beats,
		_resolve_attack_beat_interval()
	)


func _get_attack_return_restore_seconds() -> float:
	return AttackMusicFadeRules.clamp_return_restore_seconds(
		_get_remaining_attack_outro_time(),
		_get_attack_return_crossfade_seconds()
	)


func _get_remaining_attack_outro_time() -> float:
	return maxf(0.0, _attack_phase_end_time - _get_music_clock_time())


func get_playback_position() -> float:
	if _ambient_attack_loop_active and attack_loop_player_a.stream and attack_loop_player_a.playing:
		return attack_loop_player_a.get_playback_position()
	if main_player.stream and main_player.playing:
		return main_player.get_playback_position()
	elif drum_player.stream and drum_player.playing:
		return drum_player.get_playback_position()
	elif bass_player.stream and bass_player.playing:
		return bass_player.get_playback_position()
	return 0.0


func get_song_time() -> float:
	if _song_time_frozen:
		return _frozen_song_time

	if _ambient_attack_loop_active and attack_loop_player_a.stream and attack_loop_player_a.playing:
		return maxf(0.0, attack_loop_player_a.get_playback_position() + AudioServer.get_time_since_last_mix() - _output_latency_seconds)

	var song_time: float = get_playback_position() + AudioServer.get_time_since_last_mix() - _output_latency_seconds
	song_time = maxf(0.0, song_time)
	if song_time < _last_song_time:
		return _last_song_time
	_last_song_time = song_time
	return song_time


var playing: bool:
	get:
		return (
			main_player.playing
			or drum_player.playing
			or bass_player.playing
			or (attack_player != null and attack_player.playing)
			or (attack_loop_player_a != null and attack_loop_player_a.playing)
			or (attack_loop_player_b != null and attack_loop_player_b.playing)
			or (attack_outro_player != null and attack_outro_player.playing)
		)


func set_main_volume(volume_db: float) -> void:
	main_player.volume_db = volume_db


func set_drum_volume(volume_db: float) -> void:
	drum_player.volume_db = volume_db


func set_bass_volume(volume_db: float) -> void:
	bass_player.volume_db = volume_db


func get_drum_playback_position() -> float:
	if drum_player and drum_player.stream and drum_player.playing:
		return maxf(0.0, drum_player.get_playback_position() + AudioServer.get_time_since_last_mix() - _output_latency_seconds)
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
			var miss_time_offset: float = GameConfigs.sound.player_defense.get_miss_time_offset(0)
			SFXManager.play_pool(pool, GameConfigs.sound.player_defense.sfx_bus, miss_time_offset)

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
			var miss_time_offset: float = GameConfigs.sound.player_defense.get_miss_time_offset(note_type)
			SFXManager.play_pool(pool, GameConfigs.sound.player_defense.sfx_bus, miss_time_offset)

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
