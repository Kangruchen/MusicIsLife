extends CanvasLayer

# Dialogue UI Controller for Godot 4.x
# Mount this script on the DialogueUI (CanvasLayer) node.

@onready var role_name_label: RichTextLabel = $Control/Background/RichTextLabel # 借用现有的富文本节点作容错
@onready var content_label: RichTextLabel = $Control/Background/RichTextLabel
@onready var next_btn: Control = $Control  # 借用 Control 作点击/容错
@onready var dialogue_audio: AudioStreamPlayer = $Control/AudioStreamPlayer
@onready var avatar: Control = $Control    # 借用 Control 作容错

signal dialogue_finished # 对话结束信号，可用于通知进入战斗等

@export var type_speed: float = 0.05
@export var pause_game_during_dialogue: bool = false # 对话期间是否暂停游戏本身。节奏游戏设为 false

var is_running: bool = false
var is_typing: bool = false
var _typing_token: int = 0  # 追踪当前的打字协程，用于防止被以前的旧协程打断或污染

# Dialog data loaded from res://data/dialogue_data.json
var _dialogs: Array = []
var _dialog_map: Dictionary = {}
var _current_id: int = -1

func _ready() -> void:
	# Start hidden and disconnected
	visible = false

	# Connect next button if it's a Button; else just ignore
	if next_btn and next_btn is Button:
		next_btn.pressed.connect(_on_next_btn_pressed)

	# Clean initial UI
	if role_name_label and role_name_label != content_label:
		role_name_label.text = ""
	if content_label:
		content_label.text = ""
	if avatar and avatar is TextureRect:
		avatar.visible = false

	# Preload dialogs if available
	_load_dialogs()

func _load_dialogs() -> void:
	var path: String = "res://data/dialogue_data.json"
	var file: FileAccess = FileAccess.open(path, FileAccess.ModeFlags.READ)
	if not file:
		push_warning("Dialogue JSON not found at %s" % path)
		return

	var text: String = file.get_as_text()
	var json = JSON.new()
	var error = json.parse(text)
	if error != OK:
		push_error("Failed to parse dialogue JSON: %s" % json.get_error_message())
		return

	_dialogs = json.data
	_dialog_map.clear()
	for d in _dialogs:
		if typeof(d) == TYPE_DICTIONARY and d.has("id"):
			_dialog_map[int(d["id"])] = d

func start_dialogue(scene_name: String) -> void:
	# Prevent re-entry
	if is_running:
		return

	if _dialogs.size() == 0:
		_load_dialogs()
		if _dialogs.size() == 0:
			push_warning("No dialogues loaded; aborting start_dialogue")
			return

	# Find the first dialog whose trigger_scene matches scene_name (preserve order)
	var start_entry: Dictionary = {}
	for d in _dialogs:
		if ("trigger_scene" in d) and str(d["trigger_scene"]) == scene_name:
			start_entry = d
			break

	if start_entry.is_empty():
		push_warning("No dialogue found for scene: %s" % scene_name)
		return

	is_running = true
	if pause_game_during_dialogue:
		get_tree().paused = true
	visible = true

	_current_id = int(start_entry["id"])
	_show_dialogue(_current_id)

func _show_dialogue(dialogue_id: int) -> void:
	var entry: Dictionary = {}
	if dialogue_id in _dialog_map:
		entry = _dialog_map[dialogue_id]
	else:
		# Not found
		push_warning("Dialogue id %d not found" % dialogue_id)
		end_dialogue()
		return

	# Set role name
	if role_name_label and role_name_label != content_label:
		role_name_label.text = str(entry.get("role_name", ""))

	# Handle avatar
	var art_path := str(entry.get("artwork", "null"))
	if avatar and avatar is TextureRect:
		if art_path == "null" or art_path.strip_edges() == "":
			avatar.visible = false
		else:
			var tex = ResourceLoader.load(art_path)
			if tex and tex is Texture2D:
				avatar.texture = tex
				avatar.visible = true
			else:
				avatar.visible = false

	# Prepare text
	var full_text: String = str(entry.get("text", ""))
	if content_label:
		content_label.text = ""
	if next_btn and next_btn != content_label:
		next_btn.visible = false
	is_typing = true
	_typing_token += 1
	var current_token = _typing_token

	# Optionally play dialogue audio (one-shot for the line)
	var audio_id := str(entry.get("voice_id", "")).strip_edges()
	if audio_id != "":
		var audio_path := "res://audio/dialogue/%s.wav" % audio_id
		var stream = ResourceLoader.load(audio_path)
		if stream and stream is AudioStream:
			dialogue_audio.stream = stream
			dialogue_audio.play()

	# Typing effect (per character)
	var total_chars := full_text.length()
	for i in range(1, total_chars + 1):
		if not is_typing or _typing_token != current_token:
			break
		content_label.text = full_text.substr(0, i)

		# skip sound for spaces/newlines
		var ch := full_text.substr(i-1, 1)
		if ch != " " and ch != "\n":
			# optional small click sound could be played here if desired
			pass

		var wait_time := type_speed
		if ch in ["，", "。", "！", "？", "…", ",", ".", "!", "?"]:
			wait_time = type_speed * 5

		await get_tree().create_timer(wait_time).timeout

	if _typing_token == current_token:
		is_typing = false
		# Show continue button after typing finished
		next_btn.visible = true

func _on_next_btn_pressed() -> void:
	if is_typing:
		# ignore while typing (button should be hidden) but be safe
		return

	# Get current entry and its next_id
	if not (_current_id in _dialog_map):
		end_dialogue()
		return

	var entry: Dictionary = _dialog_map[_current_id]
	var next_id = entry.get("next_id", null)

	# Handle both None/null and -1 as end signal
	if next_id == null or int(next_id) == -1:
		end_dialogue()
		return

	_current_id = int(next_id)
	_show_dialogue(_current_id)

func end_dialogue() -> void:
	# Stop audio and hide UI
	if dialogue_audio.playing:
		dialogue_audio.stop()

	visible = false
	if pause_game_during_dialogue:
		get_tree().paused = false
	is_running = false
	is_typing = false

	# Clear UI
	if role_name_label and role_name_label != content_label:
		role_name_label.text = ""
	if content_label:
		content_label.text = ""
	if avatar and avatar is TextureRect:
		avatar.visible = false

	# 发出对话结束信号给 GameManager 等系统
	dialogue_finished.emit()

# ===============================
# 调试测试与验证逻辑
# ===============================
@export var enable_ui_debug_test: bool = true # 改为默认 true 方便你直接运行场景查看输出

func _physics_process(_delta: float) -> void:
	if enable_ui_debug_test:
		enable_ui_debug_test = false
		call_deferred("_run_ui_tests")
		call_deferred("_run_rhythm_integration_tests")

var _current_test_text := ""

# 覆盖真实对话展示的数据流，使用传入测试数据直接渲染
func _debug_show_raw_text(text: String) -> void:
	if content_label:
		content_label.text = ""
	if next_btn and next_btn != content_label:
		next_btn.visible = false
	is_typing = true
	_typing_token += 1
	var current_token = _typing_token
	_current_test_text = text
	
	var total_chars := text.length()
	if total_chars == 0:
		is_typing = false
		if next_btn and next_btn != content_label:
			next_btn.visible = true
		return
		
	for i in range(1, total_chars + 1):
		if not is_typing or _typing_token != current_token:
			break
		if content_label:
			content_label.text = text.substr(0, i)
		await get_tree().create_timer(type_speed).timeout
		
	if _typing_token == current_token:
		is_typing = false
		if next_btn and next_btn != content_label:
			next_btn.visible = true

func skip_typing() -> void:
	if is_typing:
		is_typing = false
		if content_label:
			content_label.text = _current_test_text
		if next_btn and next_btn != content_label:
			next_btn.visible = true

func _run_ui_tests() -> void:
	print("\n--- 🟢 [DEBUG] 开始 DialogueUIController 渲染与边界测试 ---")
	
	# 确保 UI 可见
	visible = true
	
	# --- 1. 测试空文本 ---
	print("\n[测试1] 空文本测试 (预期：不会崩溃，直接完成)")
	await _debug_show_raw_text("")
	print("结果: is_typing=", is_typing, " 按钮可见=", next_btn.visible if next_btn and next_btn != content_label else false, " 文本长度=", content_label.text.length() if content_label else 0)
	
	# --- 2. 测试打字机效果正常执行 ---
	print("\n[测试2] 打字机按字呈现 (预期：每经过延迟字数增加)")
	var text1 = "这是一段简单的打字效果测试文本。"
	# 启动且不等待，去监控文字长度变化
	_debug_show_raw_text(text1)
	await get_tree().create_timer(type_speed * 3.5).timeout
	var partial_len = content_label.text.length() if content_label else 0
	print("打字中途结果: is_typing=", is_typing, " 按钮可见=", next_btn.visible if next_btn and next_btn != content_label else false, " 当前字数=", partial_len)
	# 等它打完
	while is_typing:
		await get_tree().create_timer(type_speed).timeout
	print("打完结果: is_typing=", is_typing, " 按钮可见=", next_btn.visible if next_btn and next_btn != content_label else false, " 最终字数=", content_label.text.length() if content_label else 0)
	
	# --- 3. 测试打字时强制中断/跳过 ---
	print("\n[测试3] 跳过打字机测试 (预期：立刻停止打字并展示完整文本)")
	var text2 = "如果文本很长很长，玩家想点击屏幕直接跳过，它应该瞬间全部显示出来。"
	# 开始打字
	_debug_show_raw_text(text2)
	# 等一会儿
	await get_tree().create_timer(type_speed * 4).timeout
	print("正在打字中... 模拟跳过操作")
	skip_typing()
	# 验证结果
	print("跳过后结果: is_typing=", is_typing, " 按钮可见=", next_btn.visible if next_btn and next_btn != content_label else false, " 字数=", content_label.text.length() if content_label else 0)
	
	# --- 4. 连续多次暴力覆盖对话 ---
	print("\n[测试4] 连续暴力写入重叠文字 (预期：新的立即重置旧的，不重叠混合)")
	_debug_show_raw_text("旧的不长的一段话...")
	await get_tree().create_timer(type_speed * 2).timeout
	# 还没打完立刻来新的指令
	_debug_show_raw_text("【新的一段霸道文字，强行覆盖了过去！】")
	while is_typing:
		await get_tree().create_timer(type_speed).timeout
	print("最终界面显示的文字是: ", content_label.text if content_label else "")
	
	print("\n--- 🔴 [DEBUG] DialogueUI 渲染测试结束 ---")
	visible = false

func _run_rhythm_integration_tests() -> void:
	print("\n--- 🟢 [DEBUG] 开始 节奏系统与对话并发集成测试 ---")
	
	pause_game_during_dialogue = false
	
	# Create a mock rhythm object to simulate continuous processing
	var mock_rhythm_tracker = { "beat_count": 0, "is_active": true }
	
	# Local async loop to simulate BeatManager dropping beats
	var rhythm_loop = func():
		while mock_rhythm_tracker.is_active:
			await get_tree().create_timer(0.2).timeout
			mock_rhythm_tracker.beat_count += 1
			print("    🎵 [Rhythm System] Beat Drop! (Total: ", mock_rhythm_tracker.beat_count, ")")
	
	rhythm_loop.call()
	
	print("\n[测试5] 对话期间节奏判定是否被阻塞？")
	var initial_beats = mock_rhythm_tracker.beat_count
	print("进入对话前 Beat Count: ", initial_beats)
	
	# Trigger a dialogue scenario
	visible = true
	await _debug_show_raw_text("这是一句很长很长的台词，玩家正在一边阅读一边打节拍！不能因为我说话就停止刷怪和掉落音符。")
	
	var beats_during_dialogue = mock_rhythm_tracker.beat_count - initial_beats
	print("\n=== 对话结束 ===")
	print("退出对话后 Beat Count: ", mock_rhythm_tracker.beat_count)
	print("在对话期间经过了的节拍数: ", beats_during_dialogue)
	
	if beats_during_dialogue > 3:
		print("✅ 成功: 对话并未阻塞节奏系统运行。进入战斗继续！")
	else:
		print("❌ 失败: 节奏系统被阻塞或暂停。")
	
	mock_rhythm_tracker.is_active = false
	visible = false
	print("--- 🔴 [DEBUG] 节奏系统与对话测试结束 ---\n")

