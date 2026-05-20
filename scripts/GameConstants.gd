class_name GameConstants
## 游戏全局常量 - 集中管理共享魔数

# === 攻击阶段节拍配置 ===
const COUNTDOWN_BEATS: int = 4        ## 准备倒计时拍数（第 1 小节）
const INPUT_BEATS: int = 16           ## 攻击输入拍数（第 2-5 小节）
const EXIT_BEATS: int = 4             ## 退出倒计时拍数（第 6 小节）
const TOTAL_ATTACK_BEATS: int = 24    ## 攻击阶段总拍数
const DRUM_START_BEAT: int = 32       ## drum 第 9 小节起拍编号

# === 攻击阶段时间比率 ===
const FIRST_BEAT_DELAY_RATIO: float = 0.5    ## 第一输入拍提前半拍


# === 音乐恢复 ===
const MUSIC_RESUME_LEAD_TIME: float = 0.5    ## 提前淡入秒数

# === 判定时间窗口（秒） ===
const PERFECT_WINDOW: float = 0.050   ## 50 ms
const GREAT_WINDOW: float = 0.100     ## 100 ms
const GOOD_WINDOW: float = 0.150      ## 150 ms

# === 攻击阶段判定窗口（秒） ===
const ATTACK_PERFECT_WINDOW: float = 0.150   ## 150 ms（攻击阶段放宽判定，前后对称）

# === MISS 判定 ===
const MISS_THRESHOLD: float = 0.150   ## 音符过判定线 150 ms 后算 MISS

# === 热度系统 ===
const MAX_HEAT_LEVEL: int = 4               ## 最高热度档位
const PERFECTS_PER_LEVEL: int = 3           ## 每档需要 Perfect 次数
const HEAT_DAMAGE_MULTIPLIER_BASE: float = 1.0   ## 热度伤害基础倍率
const HEAT_DAMAGE_MULTIPLIER_PER_LEVEL: float = 2.0  ## 每档额外倍率


static func get_action_key_label(action: String, fallback: String = "") -> String:
	var gamepad_manager: Node = _get_gamepad_manager()
	if gamepad_manager != null and gamepad_manager.has_method("get_action_prompt"):
		var prompt: String = String(gamepad_manager.call("get_action_prompt", StringName(action), fallback))
		if not prompt.is_empty():
			return prompt

	if not InputMap.has_action(action):
		return fallback
	var events: Array = InputMap.action_get_events(action)
	if events.is_empty():
		return fallback
	for ev in events:
		if ev is InputEventKey:
			var key_ev: InputEventKey = ev as InputEventKey
			var code: int = key_ev.physical_keycode if key_ev.physical_keycode != 0 else key_ev.keycode
			if code == 0:
				continue
			var label: String = OS.get_keycode_string(code)
			if not label.is_empty():
				return label
		elif ev is InputEventMouseButton:
			var mouse_ev: InputEventMouseButton = ev as InputEventMouseButton
			match mouse_ev.button_index:
				MOUSE_BUTTON_LEFT:
					return "Mouse 1"
				MOUSE_BUTTON_RIGHT:
					return "Mouse 2"
				MOUSE_BUTTON_MIDDLE:
					return "Mouse 3"
				_:
					return "Mouse %d" % mouse_ev.button_index
		elif ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
			var label_from_manager: String = _format_input_event_with_manager(ev)
			if not label_from_manager.is_empty():
				return label_from_manager
	return fallback


static func get_note_action_label(note_type: int, fallback: String = "") -> String:
	var gamepad_manager: Node = _get_gamepad_manager()
	if gamepad_manager != null and gamepad_manager.has_method("get_note_prompt"):
		var prompt: String = String(gamepad_manager.call("get_note_prompt", note_type, fallback))
		if not prompt.is_empty():
			return prompt

	match note_type:
		Note.NoteType.GUARD:
			return get_action_key_label("note_guard", "J" if fallback.is_empty() else fallback)
		Note.NoteType.HIT:
			return get_action_key_label("note_hit", "I" if fallback.is_empty() else fallback)
		Note.NoteType.DODGE:
			return get_action_key_label("note_dodge", "L" if fallback.is_empty() else fallback)
		_:
			return fallback


static func _get_gamepad_manager() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("GamepadManager")


static func _format_input_event_with_manager(event: InputEvent) -> String:
	var gamepad_manager: Node = _get_gamepad_manager()
	if gamepad_manager != null and gamepad_manager.has_method("format_input_event"):
		return String(gamepad_manager.call("format_input_event", event))
	return ""
