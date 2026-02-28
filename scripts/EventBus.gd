extends Node
## EventBus - 全局信号总线，解耦节点间通信
## 注册为 Autoload，所有跨子树或多监听者信号通过此节点转发

# === 共享状态（由各管理器写入，供全局读取） ===

## 当前节拍间隔（秒），由 BeatManager 在音乐开始后设置
var beat_interval: float = 0.0

# === 音乐 / 节拍 ===
signal music_started
signal beat_hit(beat_number: float, note: Note)
signal chart_loaded(chart: Chart)

# === 输入 / 判定 ===
signal judgment_made(track: int, judgment: int, timing_diff: float)
signal defense_key_pressed(track: int)
signal miss_triggered(track: int)

# === 攻击阶段 ===
signal attack_performed(attack_type: int)
signal attack_phase_started
signal attack_phase_ended

# === 血量 / 状态 ===
signal player_health_updated(current: float, maximum: float)
signal boss_health_updated(current: float, maximum: float)
signal boss_energy_updated(current: float, maximum: float)
signal boss_energy_depleted
signal player_died
signal boss_defeated

# === UI 请求信号（逻辑层 → UI 层） ===
signal show_attack_ui_requested
signal hide_attack_ui_requested
signal show_beat_track_requested
signal spawn_beat_note_requested(beat_interval: float, target_time: float)
signal show_return_countdown_requested(count: int)
signal show_pause_countdown_requested(bi: float)
signal play_beat_flash_requested(bi: float, beat_count: int)
signal hide_pause_effects_requested
