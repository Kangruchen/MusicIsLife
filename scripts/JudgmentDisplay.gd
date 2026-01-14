extends Node2D
class_name JudgmentDisplay
## 判定结果显示 - 在判定线位置显示判定文字

var judgment_type: int = -1  # InputManager.JudgmentType
var track_type: int = -1  # Note.NoteType
var lifetime: float = 1.0  # 显示时长（秒）
var elapsed_time: float = 0.0
var judgment_color: Color = Color.WHITE
var y_position: float = 0.0

@onready var label: Label = $Label


## 初始化判定显示
func initialize(judgment: int, track: int, color: Color, y_pos: float) -> void:
	judgment_type = judgment
	track_type = track
	judgment_color = color
	y_position = y_pos
	
	# 设置位置（在判定线上）
	position.y = y_pos


func _ready() -> void:
	# 设置文本和颜色
	if label:
		label.text = _get_judgment_text(judgment_type)
		label.add_theme_color_override("font_color", judgment_color)
		label.add_theme_font_size_override("font_size", 32)


func _process(delta: float) -> void:
	elapsed_time += delta
	
	# 淡出效果
	var alpha: float = 1.0 - (elapsed_time / lifetime)
	modulate.a = alpha
	
	# 轻微上浮
	position.x += delta * 50.0
	
	# 时间到后销毁
	if elapsed_time >= lifetime:
		queue_free()


## 获取判定文本
func _get_judgment_text(judgment: int) -> String:
	match judgment:
		0:  # PERFECT
			return "PERFECT"
		1:  # GREAT
			return "GREAT"
		2:  # GOOD
			return "GOOD"
		3:  # MISS
			return "MISS"
		_:
			return ""
