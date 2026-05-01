extends Area2D

# 开启调试测试（挂载节点后在属性面板勾选）
@export var enable_debug_test: bool = false

# Boss room trigger: when the player enters this Area2D, trigger the boss_fight dialogue
# and disable the area to avoid repeated triggers.

var dialogue_ui: Node = null

func _ready() -> void:
	# Try to find a global DialogueUI (AutoLoad) at /root/DialogueUI
	dialogue_ui = get_node_or_null("/root/DialogueUI")
	if not dialogue_ui and not enable_debug_test:
		push_error("找不到DialogueUI节点！请检查是否配置为AutoLoad或路径正确")

	# Connect the body_entered signal to our handler.
	connect("body_entered", Callable(self, "_on_body_entered"))

	# 如果开启了调试，延时执行测试逻辑
	if enable_debug_test:
		call_deferred("_run_debug_simulation")

func _on_body_entered(body: Node) -> void:
	if body == null:
		return

	# 由于测试中我们要手动调用此方法，为了防御性编程，我们增加一条显式的 monitoring 检查
	# （正式引擎环境下 monitoring = false 会自动停止发出信号，但手动调用不会拦截）
	if not self.monitoring:
		print("触发器已禁用，阻止 body_entered 被手动调用")
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

# ===============================
# 以下为调试与测试模拟逻辑
# ===============================
func _run_debug_simulation() -> void:
	print("\n--- 🟢 [DEBUG] 开始 BossRoomTrigger 模拟测试 ---")
	
	# 如果找不到真实 DialogueUI，我们给一个 mock 以免报错中断测试
	if not dialogue_ui:
		print("[DEBUG] 注入 Mock DialogueUI 以保证测试顺利进行...")
		var mock_ui = Node.new()
		var script = GDScript.new()
		script.source_code = "extends Node\n\nfunc start_dialogue(scene_name: String):\n\tprint(\"[Mock UI 接收] 触发对话，场景名: \", scene_name)"
		script.reload()
		mock_ui.set_script(script)
		self.add_child(mock_ui)
		dialogue_ui = mock_ui

	# 1. 模拟非玩家进入
	print("\n[测试1] 模拟非玩家(Enemy)进入触发区...")
	var dummy_enemy = Node.new()
	dummy_enemy.name = "Enemy"
	_on_body_entered(dummy_enemy)
	
	# 2. 模拟玩家初次进入
	print("\n[测试2] 模拟玩家(Player)首次进入触发区...")
	var dummy_player = Node.new()
	dummy_player.name = "Player"
	_on_body_entered(dummy_player)
	
	# 3. 验证触发器属性是否已改变
	print("\n[测试验证] 验证触发区状态: monitoring = ", self.monitoring)
	
	# 4. 模拟玩家重复进入
	print("\n[测试3] 模拟玩家(Player)再次进入触发区...")
	_on_body_entered(dummy_player)
	
	print("\n--- 🔴 [DEBUG] 测试结束 ---\n")
	
	# 清理测试使用的临时节点
	dummy_enemy.queue_free()
	dummy_player.queue_free()
	if dialogue_ui and dialogue_ui.get_parent() == self:
		dialogue_ui.queue_free()
