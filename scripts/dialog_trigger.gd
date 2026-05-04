extends Area2D
class_name DialogueTrigger

# 在编辑器右侧配置这个触发器播放第几段对话 (1, 2, 3, 4)
@export var dialogue_id: int = 1
# 把你场景里的 DialogueUi_tscn 节点拖到这个槽位里
@export var dialogue_ui: DialogueUI 

func _ready() -> void:
	# 使用信号解耦，连接碰撞进入事件
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	# 确保是排查玩家触发的，假设你的玩家节点叫 "Player"
	if body.name == "Player":
		if dialogue_ui and not dialogue_ui.is_busy:
			_trigger_dialogue()
			# 触发后销毁该触发器，防止再次走进来重复触发
			queue_free()

func _trigger_dialogue() -> void:
	match dialogue_id:
		1:
			dialogue_ui.show_dialog1()
		2:
			dialogue_ui.show_dialog2()
		3:
			dialogue_ui.show_dialog3()
		4:
			dialogue_ui.show_dialog4()
		_:
			push_warning("未知的 Dialogue ID")
