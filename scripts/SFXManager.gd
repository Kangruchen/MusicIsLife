extends Node
## SFXManager - 全局音效播放管理器（Autoload）
## 集中管理所有 SFX 播放，使用对象池复用 AudioStreamPlayer
## 所有 SFX 默认路由到 "SFX" 总线，与 BGM 总线分离
##
## 使用方式：
##   SFXManager.play_pool(config.guard_sound)             # 播放随机音效池
##   SFXManager.play_entry(entry)                          # 播放单条音效条目
##   SFXManager.play_stream(stream)                        # 播放原始音频流
##   SFXManager.play_pool_delayed(pool, 0.1)               # 延迟0.1秒播放
##   SFXManager.stop_all()                                 # 停止所有SFX

var _pool = []
const INITIAL_POOL_SIZE = 8


func _ready() -> void:
	for i in range(INITIAL_POOL_SIZE):
		var player = AudioStreamPlayer.new()
		player.bus = &"SFX"
		add_child(player)
		_pool.append(player)


func play_entry(entry, bus = &"SFX"):
	if entry == null or entry.stream == null:
		return null
	var player = _acquire_player()
	player.stream = entry.stream
	player.volume_db = entry.volume_db
	player.pitch_scale = maxf(0.01, entry.pitch_scale)
	player.bus = String(bus)
	player.play(maxf(0.0, entry.time_offset))
	return player


func play_pool(pool, bus = &"SFX"):
	if pool == null:
		return null
	var entry = pool.pick_random()
	if entry == null:
		return null
	return play_entry(entry, bus)


func play_stream(stream, volume_db = 0.0, pitch_scale = 1.0, time_offset = 0.0, bus = &"SFX"):
	if stream == null:
		return null
	var player = _acquire_player()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = maxf(0.01, pitch_scale)
	player.bus = String(bus)
	player.play(maxf(0.0, time_offset))
	return player


func play_pool_delayed(pool, delay_sec, bus = &"SFX") -> void:
	if pool == null or delay_sec <= 0.0:
		play_pool(pool, bus)
		return
	var token = _delay_token
	get_tree().create_timer(delay_sec).timeout.connect(func() -> void:
		if token != _delay_token:
			return
		play_pool(pool, bus)
	)


func play_entry_delayed(entry, delay_sec, bus = &"SFX") -> void:
	if entry == null or entry.stream == null:
		return
	if delay_sec <= 0.0:
		play_entry(entry, bus)
		return
	var token = _delay_token
	get_tree().create_timer(delay_sec).timeout.connect(func() -> void:
		if token != _delay_token:
			return
		play_entry(entry, bus)
	)


func stop_all() -> void:
	for player in _pool:
		if player != null and is_instance_valid(player):
			player.stop()


func invalidate_delayed() -> void:
	_delay_token += 1


func _acquire_player():
	for player in _pool:
		if player != null and is_instance_valid(player) and not player.playing:
			return player
	var player = AudioStreamPlayer.new()
	player.bus = &"SFX"
	add_child(player)
	_pool.append(player)
	return player


var _delay_token = 0
