extends CanvasLayer
## 游戏UI - 管理血条显示和攻击阶段UI

# 轨道配置（游戏逻辑坐标，用于判定计算）
const TRACK_HEIGHT: float = 80.0  # 每条轨道高度
const TRACK_SPACING: float = 10.0  # 轨道间距
const JUDGMENT_LINE_X: float = 100.0  # 判定线X坐标
const TRACK_START_Y: float = 57.0  # 第一条轨道的Y坐标

# 血量条引用
@onready var boss_health_bar: ProgressBar = $MarginContainer/VBoxContainer/BossHealthBar
@onready var boss_guard_bar: ProgressBar = $MarginContainer/VBoxContainer/BossGuardBar
@onready var player_health_bar: ProgressBar = $MarginContainer2/VBoxContainer/PlayerHealthBar

# 暂停阶段视觉效果元素
var countdown_label: Label = null
var beat_flash_effect: ColorRect = null

# 攻击阶段UI元素
var attack_ui_container: Control = null
var attack_hint_label: Label = null
var attack_count: int = 0  # 已发动的攻击次数
var is_next_attack_charged: bool = false  # 下次攻击是否为蓄力版本

# 节拍提示音轨
var beat_track_container: Control = null
var beat_judgment_line: ColorRect = null
var active_beat_notes: Array[ColorRect] = []  # 当前活动的节拍标记
var _beat_note_speed: float = 0.0  # 所有节拍音符的统一移动速度（px/秒）
var _beat_note_width: float = 0.0  # 所有节拍音符的统一宽度（px）


func _ready() -> void:
	# 通过 EventBus 连接所有信号（替代 get_node 硬编码路径）
	EventBus.judgment_made.connect(_on_judgment_made)
	EventBus.attack_performed.connect(_on_attack_performed)
	
	# 血量/精力更新
	EventBus.player_health_updated.connect(_on_player_health_updated)
	EventBus.boss_health_updated.connect(_on_boss_health_updated)
	EventBus.boss_energy_updated.connect(_on_boss_energy_updated)
	
	# UI 指令信号
	EventBus.show_attack_ui_requested.connect(show_attack_ui)
	EventBus.hide_attack_ui_requested.connect(hide_attack_ui)
	EventBus.show_beat_track_requested.connect(show_beat_track)
	EventBus.spawn_beat_note_requested.connect(spawn_beat_note)
	EventBus.show_return_countdown_requested.connect(show_return_countdown)
	EventBus.show_pause_countdown_requested.connect(_on_show_pause_countdown)
	EventBus.play_beat_flash_requested.connect(_on_play_beat_flash)
	EventBus.hide_pause_effects_requested.connect(hide_pause_effects)

	show() # 游戏开始时将UI设为可见
	
	# 创建倒计时标签（初始隐藏）
	countdown_label = Label.new()
	countdown_label.name = "CountdownLabel"
	countdown_label.add_theme_font_size_override("font_size", 120)
	countdown_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 1.0))
	countdown_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	countdown_label.add_theme_constant_override("outline_size", 8)
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	countdown_label.anchor_left = 0.5
	countdown_label.anchor_top = 0.5
	countdown_label.anchor_right = 0.5
	countdown_label.anchor_bottom = 0.5
	countdown_label.offset_left = -150.0
	countdown_label.offset_top = -75.0
	countdown_label.offset_right = 150.0
	countdown_label.offset_bottom = 75.0
	countdown_label.visible = false
	add_child(countdown_label)
	
	# 创建节拍闪光效果（初始隐藏）
	beat_flash_effect = ColorRect.new()
	beat_flash_effect.name = "BeatFlashEffect"
	beat_flash_effect.color = Color(1.0, 1.0, 1.0, 0.0)
	beat_flash_effect.anchor_right = 1.0
	beat_flash_effect.anchor_bottom = 1.0
	beat_flash_effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(beat_flash_effect)
	move_child(beat_flash_effect, 0)  # 移到最底层，避免遮挡其他UI
	
	# 创建攻击 UI容器（初始隐藏）
	_create_attack_ui()


func _process(_delta: float) -> void:
	_update_beat_note_positions()


## 获取指定音符类型的轨道Y坐标
func get_track_y(note_type: Note.NoteType) -> float:
	var track_index := note_type as int
	return TRACK_START_Y + track_index * (TRACK_HEIGHT + TRACK_SPACING) + TRACK_HEIGHT / 2.0


## 获取判定线X坐标
func get_judgment_line_x() -> float:
	return JUDGMENT_LINE_X


## 获取音符容器（音符视觉暂时停用）
func get_notes_container() -> Control:
	return null


## 判定触发回调（判定视觉显示暂时停用）
func _on_judgment_made(_track: Note.NoteType, _judgment: int, _timing_diff: float) -> void:
	pass


## 血量更新回调
func _on_player_health_updated(current: float, maximum: float) -> void:
	if player_health_bar:
		player_health_bar.max_value = maximum
		player_health_bar.value = current


func _on_boss_health_updated(current: float, maximum: float) -> void:
	if boss_health_bar:
		boss_health_bar.max_value = maximum
		boss_health_bar.value = current


func _on_boss_energy_updated(current: float, maximum: float) -> void:
	if boss_guard_bar:
		boss_guard_bar.max_value = maximum
		boss_guard_bar.value = current


## EventBus 包装：接收 beat_interval 参数
func _on_show_pause_countdown(bi: float) -> void:
	_show_pause_countdown_impl(bi)


## 显示暂停倒计时（第一个小节，倒计时4-3-2-1）
func _show_pause_countdown_impl(bi: float) -> void:
	if not countdown_label:
		return
	
	countdown_label.visible = true
	
	# 倒计时序列：4 -> 3 -> 2 -> 1
	for i in range(GameConstants.COUNTDOWN_BEATS):
		var count_num: int = GameConstants.COUNTDOWN_BEATS - i
		countdown_label.text = str(count_num)
		
		# 缩放动画：从大到小
		var scale_tween: Tween = create_tween()
		scale_tween.set_ease(Tween.EASE_OUT)
		scale_tween.set_trans(Tween.TRANS_BACK)
		countdown_label.scale = Vector2(1.5, 1.5)
		scale_tween.tween_property(countdown_label, "scale", Vector2(1.0, 1.0), bi * 0.3)
		
		# 透明度动画：从不透明到半透明
		var alpha_tween: Tween = create_tween()
		alpha_tween.set_ease(Tween.EASE_OUT)
		countdown_label.modulate.a = 1.0
		alpha_tween.tween_property(countdown_label, "modulate:a", 0.5, bi * 0.8)
		
		# 等待一拍
		await get_tree().create_timer(bi).timeout
	
	# 倒计时结束，隐藏标签
	countdown_label.visible = false


## EventBus 包装：接收 beat_interval 和 beat_count 参数
func _on_play_beat_flash(bi: float, beat_count: int) -> void:
	_play_beat_flash_impl(bi, beat_count)


## 播放节拍闪光效果
func _play_beat_flash_impl(bi: float, beat_count: int = 16) -> void:
	if not beat_flash_effect:
		return
	
	for i in range(beat_count):
		# 创建边框闪光效果
		var flash_tween: Tween = create_tween()
		flash_tween.set_ease(Tween.EASE_OUT)
		flash_tween.set_trans(Tween.TRANS_CUBIC)
		
		# 颜色从白色到透明
		beat_flash_effect.color = Color(1.0, 1.0, 0.8, 0.3)
		flash_tween.tween_property(beat_flash_effect, "color:a", 0.0, bi * 0.6)
		
		# 等待一拍
		await get_tree().create_timer(bi).timeout


## 隐藏所有暂停视觉效果
func hide_pause_effects() -> void:
	if countdown_label:
		countdown_label.visible = false
	if beat_flash_effect:
		beat_flash_effect.color.a = 0.0


## 创建攻击UI
func _create_attack_ui() -> void:
	# 创建攻击UI容器
	attack_ui_container = Control.new()
	attack_ui_container.name = "AttackUIContainer"
	attack_ui_container.anchor_left = 0.0
	attack_ui_container.anchor_top = 1.0
	attack_ui_container.anchor_right = 1.0
	attack_ui_container.anchor_bottom = 1.0
	attack_ui_container.offset_top = -150.0
	attack_ui_container.visible = false
	add_child(attack_ui_container)
	
	# 创建背景面板
	var bg_panel: ColorRect = ColorRect.new()
	bg_panel.color = Color(0.1, 0.1, 0.1, 0.8)
	bg_panel.anchor_right = 1.0
	bg_panel.anchor_bottom = 1.0
	attack_ui_container.add_child(bg_panel)
	
	# 创建提示标签
	attack_hint_label = Label.new()
	attack_hint_label.text = "攻击阶段！跟随节拍按键发动攻击"
	attack_hint_label.add_theme_font_size_override("font_size", 20)
	attack_hint_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	attack_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	attack_hint_label.anchor_left = 0.0
	attack_hint_label.anchor_right = 1.0
	attack_hint_label.offset_top = 10.0
	attack_hint_label.offset_bottom = 35.0
	attack_ui_container.add_child(attack_hint_label)
	
	# 创建节拍提示音轨（作为GameUI的直接子节点，不是attack_ui_container的子节点）
	beat_track_container = Control.new()
	beat_track_container.name = "BeatTrackContainer"
	beat_track_container.anchor_left = 0.5
	beat_track_container.anchor_right = 0.5
	beat_track_container.anchor_top = 1.0  # 在屏幕底部
	beat_track_container.anchor_bottom = 1.0
	beat_track_container.offset_left = -400.0
	beat_track_container.offset_right = 400.0
	beat_track_container.offset_top = -230.0  # 在屏幕底部上方
	beat_track_container.offset_bottom = -160.0
	beat_track_container.visible = false  # 默认隐藏
	add_child(beat_track_container)  # 添加到GameUI而非attack_ui_container
	
	# 创建音轨背景
	var track_bg: ColorRect = ColorRect.new()
	track_bg.color = Color(0.2, 0.2, 0.2, 0.5)
	track_bg.anchor_right = 1.0
	track_bg.anchor_bottom = 1.0
	beat_track_container.add_child(track_bg)
	
	# 创建判定线
	beat_judgment_line = ColorRect.new()
	beat_judgment_line.color = Color(1.0, 1.0, 0.3, 0.9)
	beat_judgment_line.anchor_top = 0.0
	beat_judgment_line.anchor_bottom = 1.0
	beat_judgment_line.offset_left = 397.5  # 容器中间（800px/2 - 2.5px）
	beat_judgment_line.offset_right = 402.5  # 5px宽
	beat_track_container.add_child(beat_judgment_line)


## 显示节拍音轨（仅显示音轨，不显示圆圈UI）
func show_beat_track() -> void:
	if beat_track_container:
		beat_track_container.visible = true
		print("节拍音轨已显示")


## 显示攻击UI
func show_attack_ui() -> void:
	if attack_ui_container:
		attack_ui_container.visible = true
		attack_count = 0  # 重置计数器
		is_next_attack_charged = false  # 重置蓄力状态
		# 重置active_beat_notes数组（应该已经有前两个音符）
		print("攻击UI已显示 - 容器可见性: ", attack_ui_container.visible, ", 当前音符数: ", active_beat_notes.size())
	else:
		print("错误：攻击UI容器未创建！")


## 隐藏攻击UI
func hide_attack_ui() -> void:
	if attack_ui_container:
		attack_ui_container.visible = false
		print("攻击UI已隐藏")
	
	# 隐藏节拍音轨
	if beat_track_container:
		beat_track_container.visible = false
	
	# 清理所有节拍标记
	for note in active_beat_notes:
		if is_instance_valid(note):
			note.queue_free()
	active_beat_notes.clear()
	_beat_note_speed = 0.0
	_beat_note_width = 0.0
	
	# 隐藏大屏幕倒计旰标签
	if countdown_label:
		countdown_label.visible = false


## 生成一个节拍标记（基于绝对时间定位，由 _process 统一驱动，消除帧漂移）
## beat_interval: 一拍的时长（秒）
## target_time: 音符中心到达判定线的绝对时间（Time.get_ticks_msec / 1000.0 基准）
func spawn_beat_note(beat_interval: float, target_time: float) -> void:
	if not beat_track_container:
		return
	
	# 计算统一速度和宽度（400px 对应 2 拍移动距离）
	_beat_note_speed = 400.0 / (2.0 * beat_interval)
	_beat_note_width = _beat_note_speed * beat_interval  # 一拍宽度
	
	# 创建节拍标记
	var beat_note: ColorRect = ColorRect.new()
	beat_note.color = Color(1.0, 1.0, 1.0, 0.8)  # 白色（未输入状态）
	beat_note.custom_minimum_size = Vector2(_beat_note_width, 40)
	beat_note.anchor_top = 0.5
	beat_note.anchor_bottom = 0.5
	beat_note.offset_top = -20.0
	beat_note.offset_bottom = 20.0
	# 存储目标时间，由 _process 基于绝对时间计算位置
	beat_note.set_meta("target_time", target_time)
	beat_track_container.add_child(beat_note)
	active_beat_notes.append(beat_note)
	
	# 立即设置初始位置
	_position_single_beat_note(beat_note)


## 统一更新所有节拍音符位置（基于绝对时间，保证相邻音符严格无缝）
func _update_beat_note_positions() -> void:
	if _beat_note_speed <= 0.0 or active_beat_notes.is_empty():
		return
	var hw: float = _beat_note_width / 2.0
	var now: float = Time.get_ticks_msec() / 1000.0
	for note in active_beat_notes:
		if not is_instance_valid(note):
			continue
		var target_time: float = note.get_meta("target_time", 0.0)
		var center_x: float = 400.0 + (target_time - now) * _beat_note_speed
		note.offset_left = center_x - hw
		note.offset_right = center_x + hw
		# 完全移出屏幕左侧后销毁（不从数组移除，保持索引稳定）
		if center_x + hw < -50.0:
			note.queue_free()


## 为单个音符设定初始位置（生成时立即调用）
func _position_single_beat_note(note: ColorRect) -> void:
	if _beat_note_speed <= 0.0:
		return
	var hw: float = _beat_note_width / 2.0
	var now: float = Time.get_ticks_msec() / 1000.0
	var target_time: float = note.get_meta("target_time", 0.0)
	var center_x: float = 400.0 + (target_time - now) * _beat_note_speed
	note.offset_left = center_x - hw
	note.offset_right = center_x + hw


## 显示返回倒计时
func show_return_countdown(count: int) -> void:
	# 使用大屏幕倒计旰标签（与准备阶段相同）
	if countdown_label:
		countdown_label.text = str(count)
		countdown_label.visible = true
		countdown_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.0))  # 橙色
		
		# 缩放动画：从大到小
		var scale_tween: Tween = create_tween()
		scale_tween.set_ease(Tween.EASE_OUT)
		scale_tween.set_trans(Tween.TRANS_BACK)
		countdown_label.scale = Vector2(1.5, 1.5)
		scale_tween.tween_property(countdown_label, "scale", Vector2(1.0, 1.0), 0.3)
		
		# 透明度动画：从不透明到半透明
		var alpha_tween: Tween = create_tween()
		alpha_tween.set_ease(Tween.EASE_OUT)
		countdown_label.modulate.a = 1.0
		alpha_tween.tween_property(countdown_label, "modulate:a", 0.5, 0.6)
	
	# 同时更新攻击面板UI的提示文字
	if attack_hint_label:
		attack_hint_label.text = "返回防御阶段: " + str(count)
		attack_hint_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.0))


## 攻击发动时的回调
func _on_attack_performed(attack_type: int) -> void:
	print("收到攻击信号，类型: ", attack_type)
	
	if not attack_ui_container or not attack_ui_container.visible:
		print("警告：攻击UI未显示！")
		return
	
	# 使用独立的计数器
	var beat_index: int = attack_count
	attack_count += 1  # 递增计数器
	
	if beat_index < 0 or beat_index >= active_beat_notes.size():
		print("错误：节拍索引超出范围: ", beat_index, "/", active_beat_notes.size())
		return
	
	# 根据攻击类型选择颜色
	var fill_color: Color = Color.GRAY
	var attack_name: String = ""
	match attack_type:
		0:  # LIGHT - 蓝色
			fill_color = Color(0.3, 0.5, 1.0, 0.9)
			attack_name = "轻攻击"
		1:  # HEAVY - 黄色
			fill_color = Color(1.0, 0.9, 0.2, 0.9)
			attack_name = "重攻击"
		2:  # HEAL - 绿色
			fill_color = Color(0.2, 1.0, 0.3, 0.9)
			attack_name = "回复"
		3:  # ENHANCE - 红色
			fill_color = Color(1.0, 0.2, 0.2, 0.9)
			attack_name = "蓄力"
	
	# 将对应的音符变色
	var beat_note: ColorRect = active_beat_notes[beat_index]
	if is_instance_valid(beat_note):
		beat_note.color = fill_color
		print("拍", beat_index + 1, ": ", attack_name, " - 音符已变色")
		
		# 处理蓄力逻辑
		if attack_type == 3:  # ENHANCE - 设置蓄力标志
			is_next_attack_charged = true
			print("蓄力激活 - 下次轻/重攻击将显示特效")
		elif attack_type == 0 or attack_type == 1:  # LIGHT 或 HEAVY - 检查是否蓄力
			if is_next_attack_charged:
				_add_charge_visual_effect(beat_note)
				print("蓄力攻击！- 音符", beat_index + 1, "已添加发光效果")
				
				# 重击消耗2拍，给下一个音符也添加特效
				if attack_type == 1:  # HEAVY
					var next_index: int = beat_index + 1
					if next_index < active_beat_notes.size():
						var next_note: ColorRect = active_beat_notes[next_index]
						if is_instance_valid(next_note):
							_add_charge_visual_effect(next_note)
							print("蓄力重击第二拍 - 音符", next_index + 1, "已添加发光效果")
				
				is_next_attack_charged = false  # 消耗蓄力状态
	else:
		print("错误：音符已被销毁")


## 为蓄力政击音符添加发光边框效果
func _add_charge_visual_effect(note: ColorRect) -> void:
	# 创建上边框
	var top_border: ColorRect = ColorRect.new()
	top_border.color = Color(1.0, 0.5, 0.0, 0.8)  # 橙色边框
	top_border.anchor_right = 1.0
	top_border.offset_bottom = 3.0
	top_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.add_child(top_border)
	
	# 创建底边框
	var bottom_border: ColorRect = ColorRect.new()
	bottom_border.color = Color(1.0, 0.5, 0.0, 0.8)
	bottom_border.anchor_top = 1.0
	bottom_border.anchor_right = 1.0
	bottom_border.anchor_bottom = 1.0
	bottom_border.offset_top = -3.0
	bottom_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.add_child(bottom_border)
	
	# 创建左边框
	var left_border: ColorRect = ColorRect.new()
	left_border.color = Color(1.0, 0.5, 0.0, 0.8)
	left_border.offset_right = 3.0
	left_border.anchor_bottom = 1.0
	left_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.add_child(left_border)
	
	# 创建右边框
	var right_border: ColorRect = ColorRect.new()
	right_border.color = Color(1.0, 0.5, 0.0, 0.8)
	right_border.anchor_left = 1.0
	right_border.anchor_right = 1.0
	right_border.anchor_bottom = 1.0
	right_border.offset_left = -3.0
	right_border.offset_right = 0.0
	right_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.add_child(right_border)
	
	# 创建闪烁动画（同时作用于所有边框）
	var tween: Tween = create_tween()
	tween.set_loops(5)  # 循环5次，避免无限循环
	var borders: Array[ColorRect] = [top_border, bottom_border, left_border, right_border]
	for border in borders:
		tween.parallel().tween_property(border, "color:a", 1.0, 0.5)
	for border in borders:
		tween.parallel().tween_property(border, "color:a", 0.3, 0.5)
