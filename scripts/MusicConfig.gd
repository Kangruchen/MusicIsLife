extends Resource
class_name MusicConfig
## 音乐配置数据 - 存储每首歌曲的多轨道配置

@export var music_name: String = ""  # 音乐名称

@export_group("主旋律轨道")
@export var main_track: AudioStream = null  # 主旋律音频
@export_range(-80, 24, 0.1) var main_volume_db: float = 0.0  # 主旋律音量
@export var main_enabled: bool = true  # 是否启用主旋律

@export_group("鼓点轨道")
@export var drum_track: AudioStream = null  # 鼓点音频
@export_range(-80, 24, 0.1) var drum_volume_db: float = 0.0  # 鼓点音量
@export var drum_enabled: bool = true  # 是否启用鼓点

@export_group("贝斯轨道")
@export var bass_track: AudioStream = null  # 贝斯音频
@export_range(-80, 24, 0.1) var bass_volume_db: float = 0.0  # 贝斯音量
@export var bass_enabled: bool = true  # 是否启用贝斯

@export_group("铺面信息")
@export var bpm: float = 120.0  # 每分钟节拍数
@export var offset: float = 0.0  # 偏移量（秒）
