extends Resource
class_name KeySoundConfig
## 按键音效配置 - 定义三种音符的按键音效

# 三种音符的按键音效（按轨道顺序：J=guard, I=hit, L=dodge）
@export var guard_sound: AudioStream = null  # 防御音符音效 (J键)
@export var hit_sound: AudioStream = null    # 攻击音符音效 (I键)
@export var dodge_sound: AudioStream = null  # 闪避音符音效 (L键)

# 各音符独立音量（dB）
@export_range(-80, 24, 0.1) var guard_volume_db: float = 0.0  # 防御音符音量 (J键)
@export_range(-80, 24, 0.1) var hit_volume_db: float = 0.0    # 攻击音符音量 (I键)
@export_range(-80, 24, 0.1) var dodge_volume_db: float = 0.0  # 闪避音符音量 (L键)


## 根据音符类型获取对应的音效
func get_sound_for_type(note_type: Note.NoteType) -> AudioStream:
	match note_type:
		Note.NoteType.GUARD:
			return guard_sound
		Note.NoteType.HIT:
			return hit_sound
		Note.NoteType.DODGE:
			return dodge_sound
		_:
			return null


## 根据音符类型获取对应的音量
func get_volume_for_type(note_type: Note.NoteType) -> float:
	match note_type:
		Note.NoteType.GUARD:
			return guard_volume_db
		Note.NoteType.HIT:
			return hit_volume_db
		Note.NoteType.DODGE:
			return dodge_volume_db
		_:
			return 0.0
