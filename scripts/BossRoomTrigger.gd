extends Area2D

# Boss room trigger: when the player enters this Area2D, trigger the boss_fight dialogue
# and disable the area to avoid repeated triggers.

var dialogue_ui: Node = null

func _ready() -> void:
	# Try to find a global DialogueUI (AutoLoad) at /root/DialogueUI
	dialogue_ui = get_node_or_null("/root/DialogueUI")
	if not dialogue_ui:
		push_error("找不到DialogueUI节点！请检查是否配置为AutoLoad或路径正确")

	# Connect the body_entered signal to our handler.
	connect("body_entered", Callable(self, "_on_body_entered"))


func _on_body_entered(body: Node) -> void:
	if body == null:
		return

	# Only respond to the player node (named "Player")
	if body.name == "Player":
		if dialogue_ui:
			dialogue_ui.start_dialogue("boss_fight")
			# Disable the area to prevent repeated triggers
			monitoring = false
			print("玩家进入Boss区域，触发对话，禁用触发区")
		else:
			push_error("DialogueUI未找到，无法触发Boss对话")
	else:
		# Ignore other bodies
		print("非玩家物体进入：%s，忽略" % body.name)
