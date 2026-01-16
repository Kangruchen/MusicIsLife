extends Control
## 延迟校准场景 - 用于测试和配置音频延迟

# 校准配置
const BPM: float = 120.0  # 固定BPM
const BEAT_INTERVAL: float = 60.0 / BPM  # 节拍间隔（秒）
const NOTE_SPEED: float = 300.0  # 音符移动速度（像素/秒）
const DEFAULT_JUDGMENT_LINE_X: float = 576.0  # 默认判定线X坐标（屏幕中央）
const NOTE_SPAWN_X: float = 1200.0  # 音符生成X坐标
const OFFSET_STEP: float = 10.0  # 每次调整的延迟步长（毫秒）

# 音效
var block_sound: AudioStream

# 当前延迟设置（毫秒）正数表示音频滞后，需要判定线右移
var current_offset: float = 0.0

# 当前判定线X坐标（会根据延迟调整）
var current_judgment_x: float = DEFAULT_JUDGMENT_LINE_X

# 节拍计时器
var beat_timer: float = 0.0

# 节点引用
@onready var judgment_line: ColorRect = $JudgmentLine
@onready var notes_container: Control = $NotesContainer
@onready var offset_label: Label = $OffsetLabel
@onready var hint_label: Label = $HintLabel
@onready var decrease_button: Button = $DecreaseButton
@onready var increase_button: Button = $IncreaseButton
@onready var audio_player: AudioStreamPlayer = $AudioStreamPlayer
@onready var metronome_label: Label = $MetronomeLabel


func _ready() -> void:
	# 加载音效
	block_sound = load("res://assets/SFX/block.wav")
	audio_player.stream = block_sound
	
	# 加载已保存的延迟设置
	load_offset_config()
	
	# 设置UI
	update_offset_display()
	update_judgment_line_position()
	
	# 连接按钮信号
	decrease_button.pressed.connect(_on_decrease_pressed)
	increase_button.pressed.connect(_on_increase_pressed)
	
	# 初始化节拍计时器
	beat_timer = 0.0


func _process(delta: float) -> void:
	# 更新节拍计时器
	beat_timer += delta
	
	# 当到达节拍时间时
	if beat_timer >= BEAT_INTERVAL:
		beat_timer -= BEAT_INTERVAL
		_spawn_note()
		_play_metronome()
	
	# 移动并清理音符
	_update_notes(delta)


func _input(event: InputEvent) -> void:
	# 按O键返回主场景
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_O:
			_return_to_main()


func _spawn_note() -> void:
	"""生成一个新音符"""
	var note_visual := ColorRect.new()
	note_visual.size = Vector2(20, 80)
	note_visual.color = Color(1.0, 1.0, 0.0, 0.8)  # 黄色
	note_visual.position = Vector2(NOTE_SPAWN_X, 284)  # 垂直居中
	notes_container.add_child(note_visual)


func _play_metronome() -> void:
	"""播放节拍音效"""
	audio_player.play()
	_flash_metronome()


func _flash_metronome() -> void:
	"""节拍视觉反馈"""
	metronome_label.modulate = Color(1.0, 1.0, 0.0, 1.0)
	await get_tree().create_timer(0.1).timeout
	metronome_label.modulate = Color(1.0, 1.0, 1.0, 1.0)


func _update_notes(delta: float) -> void:
	"""更新所有音符位置并清理超出屏幕的音符"""
	for note in notes_container.get_children():
		if note is ColorRect:
			# 移动音符
			note.position.x -= NOTE_SPEED * delta
			
			# 当音符通过判定线时闪烁判定线
			if note.position.x + note.size.x >= current_judgment_x and note.position.x <= current_judgment_x:
				_flash_judgment_line()
			
			# 清理超出屏幕的音符
			if note.position.x < -100:
				note.queue_free()


func _flash_judgment_line() -> void:
	"""判定线闪烁效果"""
	judgment_line.color = Color(0.0, 1.0, 0.0, 1.0)
	await get_tree().create_timer(0.05).timeout
	judgment_line.color = Color(1.0, 1.0, 1.0, 0.8)


func _on_decrease_pressed() -> void:
	"""减小延迟"""
	current_offset -= OFFSET_STEP
	update_offset_display()
	update_judgment_line_position()


func _on_increase_pressed() -> void:
	"""增大延迟"""
	current_offset += OFFSET_STEP
	update_offset_display()
	update_judgment_line_position()


func update_offset_display() -> void:
	"""更新延迟显示"""
	offset_label.text = "当前延迟: %.0f ms" % current_offset


func update_judgment_line_position() -> void:
	"""根据延迟更新判定线位置"""
	var offset_pixels: float = (current_offset / 1000.0) * NOTE_SPEED
	current_judgment_x = DEFAULT_JUDGMENT_LINE_X + offset_pixels
	judgment_line.position.x = current_judgment_x - judgment_line.size.x / 2.0


func load_offset_config() -> void:
	"""加载保存的延迟配置"""
	var config := ConfigFile.new()
	var err := config.load("user://settings.cfg")
	if err == OK:
		current_offset = config.get_value("audio", "offset", 0.0)
		print("已加载延迟设置: ", current_offset, " ms")


func save_offset_config() -> void:
	"""保存延迟配置到用户数据目录"""
	var config := ConfigFile.new()
	# 尝试加载现有配置
	config.load("user://settings.cfg")
	# 设置延迟值（转换为秒）
	config.set_value("audio", "offset", current_offset)
	config.set_value("audio", "offset_ms", current_offset)  # 同时保存毫秒值方便调试
	# 保存到文件
	var err := config.save("user://settings.cfg")
	if err == OK:
		print("延迟设置已保存: ", current_offset, " ms")
	else:
		push_error("保存延迟设置失败: ", err)


func _return_to_main() -> void:
	"""返回主场景"""
	save_offset_config()
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
