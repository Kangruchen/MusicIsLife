extends Resource
class_name KeySoundConfig
## 按键音效配置 - 定义三种音符的按键音效

# 三种音符的按键音效
@export var hit_sound: AudioStream = null    # 攻击音符音效
@export var guard_sound: AudioStream = null  # 防御音符音效
@export var dodge_sound: AudioStream = null  # 闪避音符音效

# 音效音量（dB）
@export_range(-80, 24, 0.1) var volume_db: float = 0.0


## 根据音符类型获取对应的音效
func get_sound_for_type(note_type: Note.NoteType) -> AudioStream:
	match note_type:
		Note.NoteType.HIT:
			return hit_sound
		Note.NoteType.GUARD:
			return guard_sound
		Note.NoteType.DODGE:
			return dodge_sound
		_:
			return null
