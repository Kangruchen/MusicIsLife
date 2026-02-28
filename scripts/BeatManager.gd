extends Node
## 节拍管理器 - 根据 BPM 和 offset 检测音乐节拍

# 音乐配置
@export var bpm: float = 128.0  # 每分钟节拍数
@export var offset: float = 0.0  # 偏移量（秒）
@export var generate_test_chart: bool = true  # 是否生成测试铺面
@export_file("*.sm") var chart_sm_path: String = ""  # StepMania .sm 铺面文件路径

# 用户校准的全局延迟（秒），会叠加到所有铺面的offset上
@export var user_offset: float = 0.0  # 可在编辑器中配置测试，正式运行时从配置文件加载

# 铺面数据
var current_chart: Chart = null

# 内部变量
var beat_interval: float = 0.0  # 每个节拍的时间间隔（秒）
var next_beat_time: float = 0.0  # 下一个节拍的时间
var current_beat: float = 0.0  # 当前节拍数（支持浮点数以精确跟踪节拍）
var is_playing: bool = false
var is_paused: bool = false  # 是否暂停
var pause_start_time: float = 0.0  # 暂停开始时间
var total_pause_duration: float = 0.0  # 累计暂停时长

@onready var music_player: Node = get_node("../MusicPlayer")


func load_user_offset() -> void:
	"""加载用户校准的音频延迟设置"""
	# 如果在编辑器中已设置user_offset，优先使用编辑器的值（便于测试）
	if user_offset != 0.0:
		print("使用编辑器设置的用户延迟: ", user_offset, " 秒 (", user_offset * 1000.0, " ms)")
		return
	
	# 否则从配置文件加载
	var config := ConfigFile.new()
	var err := config.load("user://settings.cfg")
	if err == OK:
		var user_offset_ms: float = config.get_value("audio", "offset", 0.0)
		# 将毫秒转换为秒
		user_offset = user_offset_ms / 1000.0
		print("已加载用户校准延迟: ", user_offset_ms, " ms (", user_offset, " 秒)")


func _ready() -> void:
	# 加载用户校准的延迟设置
	load_user_offset()
	
	# 计算节拍间隔
	beat_interval = 60.0 / bpm
	
	# 通过 EventBus 监听音乐开始信号（替代直连 MusicPlayer）
	EventBus.music_started.connect(_on_music_started)
	print("BeatManager 已通过 EventBus 连接到 music_started")


func _process(delta: float) -> void:
	if not is_playing or is_paused:
		return
	
	# 获取当前音乐播放位置（加上音频延迟补偿）
	var current_time: float = music_player.get_playback_position() + AudioServer.get_time_to_next_mix()
	
	# 检查是否到达下一个节拍
	if current_time >= next_beat_time:
		_on_beat()
		# 计算下一个节拍时间
		next_beat_time += beat_interval


## 音乐开始播放时的回调
func _on_music_started() -> void:
	is_playing = true
	current_beat = 0.0
	
	# 加载铺面（优先级：SM > 测试生成）
	if chart_sm_path != "":
		current_chart = SMFileLoader.load_from_sm(chart_sm_path)
		if current_chart:
			# 从铺面中读取配置
			bpm = current_chart.bpm
			var original_offset := current_chart.offset
			offset = original_offset + user_offset  # 叠加用户校准延迟
			beat_interval = 60.0 / bpm
			# 重新计算所有音符的beat_time
			_recalculate_note_times(current_chart, original_offset, offset)
			print("SM铺面offset: ", original_offset, " + 用户offset: ", user_offset, " = 总offset: ", offset)
	elif generate_test_chart:
		# 先应用用户校准延迟
		offset += user_offset
		# 再生成测试铺面（这样beat_time才能使用正确的offset）
		_generate_test_chart()
		print("测试铺面 + 用户offset: ", user_offset, " = 总offset: ", offset)
	
	# 将 beat_interval 写入 EventBus 供全局读取
	EventBus.beat_interval = beat_interval
	
	# 通过 EventBus 通知铺面已加载
	if current_chart:
		EventBus.chart_loaded.emit(current_chart)
	
	next_beat_time = offset
	print("节拍管理器已启动 - BPM: ", bpm, ", Offset: ", offset, " 秒")


func _recalculate_note_times(chart: Chart, old_offset: float, new_offset: float) -> void:
	"""重新计算铺面中所有音符的beat_time，应用新的offset"""
	var offset_diff := new_offset - old_offset
	for note in chart.notes:
		note.beat_time += offset_diff
	print("已重新计算 ", chart.notes.size(), " 个音符的时间，延迟调整: ", offset_diff, " 秒")


## 生成测试铺面（随机生成音符）
func _generate_test_chart() -> void:
	current_chart = Chart.new()
	current_chart.chart_name = "Test Chart"
	current_chart.bpm = bpm
	current_chart.offset = offset
	
	# 生成前100个节拍的随机音符
	for i in range(1, 101):
		var note := Note.new()
		note.beat_number = float(i)  # 使用浮点数，从1开始
		note.beat_time = offset + i * beat_interval  # 第i拍的时间
		# 随机选择音符类型
		note.type = randi() % 3 as Note.NoteType
		current_chart.add_note(note)
	
	print("已生成测试铺面，共 ", current_chart.notes.size(), " 个音符")


## 节拍触发时的回调
func _on_beat() -> void:
	current_beat += 1.0  # 使用浮点数，递增到下一拍
	
	# 获取当前节拍的音符
	var note: Note = null
	if current_chart:
		note = current_chart.get_note_at_beat(current_beat)
	
	# 打印节拍信息和音符类型
	if note:
		var note_icon := _get_note_icon(note.type)
		print("♪ 节拍 #", current_beat, " - 时间: ", "%.3f" % next_beat_time, " 秒 - 音符: ", note_icon, " ", note.get_type_string())
	else:
		print("♪ 节拍 #", current_beat, " - 时间: ", "%.3f" % next_beat_time, " 秒 - 无音符")
	
	EventBus.beat_hit.emit(current_beat, note)


## 获取音符类型对应的图标
func _get_note_icon(type: Note.NoteType) -> String:
	match type:
		Note.NoteType.GUARD:
			return "🛡️"  # 防御
		Note.NoteType.HIT:
			return "⚔️"  # 攻击
		Note.NoteType.DODGE:
			return "💨"  # 闪避
		_:
			return "❓"


## 暂停节拍检测
func pause_beat_detection() -> void:
	is_paused = true
	print("节拍检测已暂停")


## 恢复节拍检测
func resume_beat_detection() -> void:
	is_paused = false
	print("节拍检测已恢复")
