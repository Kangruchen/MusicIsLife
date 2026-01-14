extends Node2D
class_name NoteVisual
## 可视化音符 - 在轨道上移动的音符

var note_data: Note = null  # 音符数据
var target_time: float = 0.0  # 到达判定线的目标时间
var spawn_time: float = 0.0  # 生成时间
var start_x: float = 0.0  # 起始X坐标
var target_x: float = 0.0  # 目标X坐标（判定线）
var track_y: float = 0.0  # 轨道Y坐标
var is_active: bool = true  # 是否活跃

# 音符颜色
const NOTE_COLORS := {
	Note.NoteType.HIT: Color.RED,
	Note.NoteType.GUARD: Color.CYAN,
	Note.NoteType.DODGE: Color.GREEN
}

@onready var sprite: ColorRect = $Sprite


func _ready() -> void:
	if note_data:
		_setup_visual()


## 初始化音符
func initialize(note: Note, spawn_pos: Vector2, target_pos: Vector2, spawn_t: float, target_t: float) -> void:
	note_data = note
	position = spawn_pos
	start_x = spawn_pos.x
	target_x = target_pos.x
	track_y = spawn_pos.y
	spawn_time = spawn_t
	target_time = target_t
	
	if is_node_ready():
		_setup_visual()


## 设置视觉效果
func _setup_visual() -> void:
	# 设置音符颜色和形状
	sprite.color = NOTE_COLORS[note_data.type]
	
	# 根据类型设置不同的大小
	match note_data.type:
		Note.NoteType.HIT:
			sprite.size = Vector2(40, 40)  # 正方形
		Note.NoteType.GUARD:
			sprite.size = Vector2(50, 30)  # 横向矩形
		Note.NoteType.DODGE:
			sprite.size = Vector2(30, 50)  # 纵向矩形
	
	# 居中
	sprite.position = -sprite.size / 2


## 更新音符位置
func update_position(current_time: float) -> void:
	if not is_active:
		return
	
	# 计算移动进度（0到1）
	var total_duration := target_time - spawn_time
	if total_duration <= 0:
		return
	
	var elapsed := current_time - spawn_time
	var progress := clampf(elapsed / total_duration, 0.0, 1.0)
	
	# 线性插值移动
	position.x = lerpf(start_x, target_x, progress)
	position.y = track_y
	
	# 注意：不在这里标记为非活跃，让判定系统或 MISS 检测来处理


## 销毁音符
func destroy() -> void:
	queue_free()
