extends Control
class_name HealthBar
## 血量条/体力条 - 显示数值条

@export var max_value: float = 100.0
@export var current_value: float = 100.0
@export var bar_color: Color = Color.GREEN
@export var background_color: Color = Color(0.2, 0.2, 0.2, 0.8)
@export var label_text: String = "HP"

@onready var bar_rect: ColorRect = $BarRect
@onready var background_rect: ColorRect = $BackgroundRect
@onready var label: Label = $Label
@onready var value_label: Label = $ValueLabel


func _ready() -> void:
	_update_bar()


## 更新血量条显示
func _update_bar() -> void:
	if not bar_rect or not value_label:
		return
	
	# 限制数值范围
	current_value = clampf(current_value, 0.0, max_value)
	
	# 更新条的宽度
	var ratio: float = current_value / max_value
	bar_rect.size.x = size.x * ratio
	
	# 更新数值文本
	value_label.text = "%d / %d" % [int(current_value), int(max_value)]
	
	# 根据比例改变颜色
	if ratio > 0.5:
		bar_rect.color = bar_color
	elif ratio > 0.25:
		bar_rect.color = Color.YELLOW
	else:
		bar_rect.color = Color.RED


## 设置当前值
func set_value(value: float) -> void:
	current_value = value
	_update_bar()


## 增加值
func add_value(amount: float) -> void:
	current_value += amount
	_update_bar()


## 减少值
func subtract_value(amount: float) -> void:
	current_value -= amount
	_update_bar()


## 获取当前值
func get_value() -> float:
	return current_value


## 是否已空
func is_empty() -> bool:
	return current_value <= 0.0


## 是否已满
func is_full() -> bool:
	return current_value >= max_value
