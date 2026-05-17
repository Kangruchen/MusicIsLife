extends Node
## EventBus - 全局信号总线，解耦节点间通信
## 注册为 Autoload，所有跨子树或多监听者信号通过此节点转发

# === 共享状态（由各管理器写入，供全局读取） ===

## 当前节拍间隔（秒），由 BeatManager 在音乐开始后设置
var beat_interval: float = 0.0

## Boss 开场动画是否已完成，由 BossIntroPlayer 写入
var boss_intro_completed: bool = false

# === 音乐 / 节拍 ===
signal music_started
signal beat_hit(beat_number: float, note: Variant)
signal chart_loaded(chart: Variant)

# === 输入 / 判定 ===
signal judgment_made(track: int, judgment: int, timing_diff: float)
signal defense_key_pressed(track: int)
signal miss_triggered(track: int)

# === 攻击阶段 ===
signal attack_performed(attack_type: int, heat_level: int)
signal attack_hit_confirmed(attack_type: int, target: Variant)
signal heat_changed(heat_level: int, heat_counter: int)
signal attack_hit_resolved(applied_damage: float, target: Variant)
signal defense_feedback_finished
signal attack_phase_started
signal attack_phase_ended
signal attack_movement_enabled_changed(enabled: bool)
signal attack_result_display(attack_type: int, is_perfect: bool, heat_level: int)
signal attack_track_setup(bi: float, first_beat_time: float)

# === 血量 / 状态 ===
signal player_health_updated(current: float, maximum: float)
signal boss_health_updated(current: float, maximum: float)
signal boss_energy_updated(current: float, maximum: float)
signal boss_energy_depleted
signal boss_charge_requested(duration_beats: float)
signal boss_missile_requested(duration_beats: float)
signal player_died
signal boss_defeated

# === Boss 开场动画 ===
signal boss_intro_finished

# === UI 请求信号（逻辑层 → UI 层） ===
signal show_attack_ui_requested
signal hide_attack_ui_requested
signal show_return_countdown_requested(count: int)
signal show_pause_countdown_requested(bi: float)
signal play_beat_flash_requested(bi: float, beat_count: int)
signal hide_pause_effects_requested


## 内部占位函数，永远不会被调用。
## 在类内部 emit 所有信号，使 GDScript 认为信号已被使用，
## 从而彻底消除 UNUSED_SIGNAL 警告（无需 @warning_ignore 注解）。
func _suppress_unused_signal_warnings() -> void:
	music_started.emit()
	beat_hit.emit(0.0, null)
	chart_loaded.emit(null)
	judgment_made.emit(0, 0, 0.0)
	defense_key_pressed.emit(0)
	miss_triggered.emit(0)
	attack_performed.emit(0, 0)
	attack_hit_confirmed.emit(0, null)
	attack_hit_resolved.emit(0.0, null)
	heat_changed.emit(0, 0)
	defense_feedback_finished.emit()
	attack_phase_started.emit()
	attack_phase_ended.emit()
	attack_movement_enabled_changed.emit(false)
	attack_result_display.emit(0, false, 0)
	attack_track_setup.emit(0.0, 0.0)
	player_health_updated.emit(0.0, 0.0)
	boss_health_updated.emit(0.0, 0.0)
	boss_energy_updated.emit(0.0, 0.0)
	boss_energy_depleted.emit()
	boss_charge_requested.emit(0.0)
	boss_missile_requested.emit(0.0)
	player_died.emit()
	boss_defeated.emit()
	boss_intro_finished.emit()
	show_attack_ui_requested.emit()
	hide_attack_ui_requested.emit()
	show_return_countdown_requested.emit(0)
	show_pause_countdown_requested.emit(0.0)
	play_beat_flash_requested.emit(0.0, 0)
	hide_pause_effects_requested.emit()
