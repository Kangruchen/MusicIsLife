extends Resource
class_name Chart
## 铺面数据 - 存储整首歌曲的音符序列

@export var chart_name: String = ""  # 铺面名称
@export var music_path: String = ""  # 对应的音乐文件路径
@export var bpm: float = 120.0  # 每分钟节拍数
@export var offset: float = 0.0  # 偏移量（秒）
@export var notes: Array[Note] = []  # 音符数组


## 添加音符
func add_note(note: Note) -> void:
	notes.append(note)


## 按节拍编号排序音符
func sort_notes() -> void:
	notes.sort_custom(func(a: Note, b: Note) -> bool:
		return a.beat_number < b.beat_number
	)


## 获取指定节拍的音符（支持浮点数节拍）
func get_note_at_beat(beat_num: float) -> Note:
	for note in notes:
		if abs(note.beat_number - beat_num) < 0.001:  # 使用小误差比较浮点数
			return note
	return null
