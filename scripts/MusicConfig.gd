extends Resource
class_name MusicConfig
## 音乐配置数据 - 存储每首歌曲的 BPM 和 offset

@export var music_name: String = ""  # 音乐名称
@export var music_path: String = ""  # 音乐文件路径
@export var bpm: float = 120.0  # 每分钟节拍数
@export var offset: float = 0.0  # 偏移量（秒）
