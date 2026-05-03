extends Resource
class_name SoundEntry
## 单条音效条目 - 包含音频流、音量、音调和时间偏移
## 用于 RandomSoundPool 的组成单元，也可独立使用

@export var stream: AudioStream = null
@export_range(-80.0, 24.0, 0.1) var volume_db: float = 0.0
@export_range(0.01, 4.0, 0.01) var pitch_scale: float = 1.0
@export_range(-2.0, 2.0, 0.01) var time_offset: float = 0.0
