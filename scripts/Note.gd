extends Resource
class_name Note
## 音符数据 - 表示铺面中的一个音符

enum NoteType {
	HIT,    # 攻击音符
	GUARD,  # 防御音符
	DODGE   # 闪避音符
}

@export var beat_time: float = 0.0  # 音符所在的节拍时间（秒）
@export var beat_number: float = 0.0  # 音符所在的节拍编号（支持浮点数，如 0.5 表示半拍，0.333 表示三连音）
@export var type: NoteType = NoteType.HIT  # 音符类型


## 获取音符类型的字符串表示
func get_type_string() -> String:
	match type:
		NoteType.HIT:
			return "HIT"
		NoteType.GUARD:
			return "GUARD"
		NoteType.DODGE:
			return "DODGE"
		_:
			return "UNKNOWN"
