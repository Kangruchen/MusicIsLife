extends Control
## 游戏UI - 管理三条轨道和判定线

# 轨道配置
const TRACK_HEIGHT: float = 100.0  # 每条轨道高度
const TRACK_SPACING: float = 20.0  # 轨道间距
const JUDGMENT_LINE_X: float = 150.0  # 判定线X坐标
const TRACK_START_Y: float = 100.0  # 第一条轨道的Y坐标

# 轨道颜色
const TRACK_COLORS := {
	Note.NoteType.HIT: Color(1.0, 0.3, 0.3, 0.3),    # 红色
	Note.NoteType.GUARD: Color(0.3, 0.3, 1.0, 0.3),  # 蓝色
	Note.NoteType.DODGE: Color(0.3, 1.0, 0.3, 0.3)   # 绿色
}

# 判定线颜色
const JUDGMENT_LINE_COLOR := Color(1.0, 1.0, 1.0, 0.8)

# 判定显示预制场景
const JUDGMENT_DISPLAY_SCENE := preload("res://scenes/JudgmentDisplay.tscn")

# 血量条配置
const HEALTH_BAR_HEIGHT: float = 30.0
const HEALTH_BAR_MARGIN: float = 20.0
const HEALTH_BAR_SPACING: float = 10.0

@onready var tracks_container: Control = $TracksContainer
@onready var judgment_line: ColorRect = $JudgmentLine
@onready var notes_container: Control = $NotesContainer
@onready var judgment_container: Control = $JudgmentContainer
@onready var player_health_bar: Control = $PlayerHealthBar
@onready var boss_health_bar: Control = $BossHealthBar
@onready var boss_energy_bar: Control = $BossEnergyBar


func _ready() -> void:
	# 连接输入管理器信号
	var input_manager: Node = get_node("../InputManager")
	if input_manager:
		input_manager.judgment_made.connect(_on_judgment_made)


## 获取指定音符类型的轨道Y坐标
func get_track_y(note_type: Note.NoteType) -> float:
	var track_index := note_type as int
	return TRACK_START_Y + track_index * (TRACK_HEIGHT + TRACK_SPACING) + TRACK_HEIGHT / 2


## 获取判定线X坐标
func get_judgment_line_x() -> float:
	return JUDGMENT_LINE_X


## 获取音符容器
func get_notes_container() -> Control:
	return notes_container


## 判定触发回调
func _on_judgment_made(track: Note.NoteType, judgment: int, _timing_diff: float) -> void:
	# 创建判定显示
	var judgment_display: Node2D = JUDGMENT_DISPLAY_SCENE.instantiate()
	
	# 获取判定颜色
	var input_manager: Node = get_node("../InputManager")
	var color: Color = Color.WHITE
	if input_manager:
		color = input_manager.get_judgment_color(judgment)
	
	# 获取轨道Y坐标
	var track_y: float = get_track_y(track)
	
	# 初始化判定显示
	judgment_display.initialize(judgment, track, color, track_y)
	judgment_display.position.x = JUDGMENT_LINE_X
	
	# 添加到判定容器
	judgment_container.add_child(judgment_display)
