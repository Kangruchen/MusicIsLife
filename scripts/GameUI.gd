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

# 暂停阶段视觉效果元素
var countdown_label: Label = null
var beat_flash_effect: ColorRect = null


func _ready() -> void:
	# 连接输入管理器信号
	var input_manager: Node = get_node("../InputManager")
	if input_manager:
		input_manager.judgment_made.connect(_on_judgment_made)
	
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


## 显示暂停倒计时（第一个小节，倒计时4-3-2-1）
func show_pause_countdown(beat_manager: Node) -> void:
	if not countdown_label or not beat_manager:
		return
	
	countdown_label.visible = true
	var beat_interval: float = beat_manager.beat_interval
	
	# 倒计时序列：4 -> 3 -> 2 -> 1
	for i in range(4):
		var count_num: int = 4 - i
		countdown_label.text = str(count_num)
		
		# 缩放动画：从大到小
		var scale_tween: Tween = create_tween()
		scale_tween.set_ease(Tween.EASE_OUT)
		scale_tween.set_trans(Tween.TRANS_BACK)
		countdown_label.scale = Vector2(1.5, 1.5)
		scale_tween.tween_property(countdown_label, "scale", Vector2(1.0, 1.0), beat_interval * 0.3)
		
		# 透明度动画：从不透明到半透明
		var alpha_tween: Tween = create_tween()
		alpha_tween.set_ease(Tween.EASE_OUT)
		countdown_label.modulate.a = 1.0
		alpha_tween.tween_property(countdown_label, "modulate:a", 0.5, beat_interval * 0.8)
		
		# 等待一拍
		await get_tree().create_timer(beat_interval).timeout
	
	# 倒计时结束，隐藏标签
	countdown_label.visible = false


## 播放节拍闪光效果（后四个小节，每拍闪一次）
func play_beat_flash_effects(beat_manager: Node, beat_count: int = 16) -> void:
	if not beat_flash_effect or not beat_manager:
		return
	
	var beat_interval: float = beat_manager.beat_interval
	
	for i in range(beat_count):
		# 创建边框闪光效果
		var flash_tween: Tween = create_tween()
		flash_tween.set_ease(Tween.EASE_OUT)
		flash_tween.set_trans(Tween.TRANS_CUBIC)
		
		# 颜色从白色到透明
		beat_flash_effect.color = Color(1.0, 1.0, 0.8, 0.3)
		flash_tween.tween_property(beat_flash_effect, "color:a", 0.0, beat_interval * 0.6)
		
		# 等待一拍
		await get_tree().create_timer(beat_interval).timeout


## 隐藏所有暂停视觉效果
func hide_pause_effects() -> void:
	if countdown_label:
		countdown_label.visible = false
	if beat_flash_effect:
		beat_flash_effect.color.a = 0.0
