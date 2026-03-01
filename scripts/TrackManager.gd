extends Node
## 轨道管理器 - 负责生成和管理音符的可视化


# 预制场景
const NOTE_VISUAL_SCENE := preload("res://scenes/NoteVisual.tscn")
const BLING_SCENE := preload("res://scenes/bling.tscn")

# Bling 特效配置
const BLING_BASE_X: float = 50.0  # 特效基础X坐标（屏幕左侧）
const BLING_OFFSET_X: float = 50.0  # 同行多个特效的水平偏移
const BLING_ROW_HEIGHT: float = 50.0  # 每行高度
const BLING_START_Y: float = 230.0  # 第一行Y坐标
const BLING_ANIMATIONS: Dictionary = {
	Note.NoteType.GUARD: "bling_blue",
	Note.NoteType.HIT: "bling_red",
	Note.NoteType.DODGE: "bling_green"
}
# 特效行排列顺序：blue第一排(J键)、red第二排(I键)、green第三排(L键)
const BLING_ROW_ORDER: Dictionary = {
	Note.NoteType.GUARD: 0,  # blue - 第一排 (J键)
	Note.NoteType.HIT: 1,    # red - 第二排 (I键)
	Note.NoteType.DODGE: 2   # green - 第三排 (L键)
}

# 生成提前量（拍数）
const SPAWN_ADVANCE := {
	Note.NoteType.GUARD: 2,  # 提前2拍（生成后1拍不动，1拍移动）(J键，第一轨道)
	Note.NoteType.HIT: 3,    # 提前3拍（生成后1拍不动，2拍移动）(I键，第二轨道)
	Note.NoteType.DODGE: 4   # 提前4拍（生成后1拍不动，3拍移动）(L键，第三轨道)
}

# 音符生成位置X坐标（动态计算，在 _ready 中初始化）
var spawn_x: float = 900.0

# MISS 判定窗口 — 值与 GameConstants.MISS_THRESHOLD 同步
const MISS_THRESHOLD: float = 0.200

# 音符视觉生成开关（暂时停用）
var note_visual_enabled: bool = false

# 非可视音符追踪（用于判定和 MISS 检测）
var tracked_notes: Array[Note] = []

# 音符生成音效配置
@export var key_sound_config: KeySoundConfig = null

# 轨道动画配置（可配置每种音符类型的攻击动画，未配置则使用默认 Bling）
@export var track_animation_config: TrackAnimationConfig = null

# 各轨道动画轮换播放位置节点（在场景中放置 Marker2D/Node2D 并拖拽到此处）
# GUARD 建议配置 2 个、HIT 3 个、DODGE 4 个，使连续动画不重合
@export_group("动画位置节点")
@export var guard_position_nodes: Array[Node2D] = []
@export var hit_position_nodes: Array[Node2D] = []
@export var dodge_position_nodes: Array[Node2D] = []

# 预警特效轮换播放位置节点（在主动画前1拍显示，数量应与对应轨道动画位置节点一致）
@export_subgroup("预警位置节点")
@export var guard_warn_position_nodes: Array[Node2D] = []
@export var hit_warn_position_nodes: Array[Node2D] = []
@export var dodge_warn_position_nodes: Array[Node2D] = []
@export_group("")

# CanvasLayer 引用（用于添加动画实例，在场景编辑器中设置指向 GameUI）
@export var game_ui: CanvasLayer = null

# 同级兄弟节点引用
@onready var music_player: Node = get_node("../MusicPlayer")

var current_chart: Chart = null
var active_notes: Array[NoteVisual] = []
var scheduled_notes: Array[Note] = []  # 待生成的音符
var current_time: float = 0.0
var is_paused: bool = false  # 是否暂停生成音符
var pause_start_time: float = 0.0  # 暂停开始的时间

# 音符生成音效播放器
var spawn_audio_player_hit: AudioStreamPlayer = null
var spawn_audio_player_guard: AudioStreamPlayer = null
var spawn_audio_player_dodge: AudioStreamPlayer = null

# 活跃的 Bling 特效追踪（按轨道分组，用于避免重叠）
var _active_blings: Dictionary = {}

# 活跃的预警特效追踪
var _active_warns: Array[Node2D] = []

# 轨道动画轮换计数器（用于循环使用不同位置，避免连续动画重叠）
var _spawn_counters: Dictionary = {
	Note.NoteType.GUARD: 0,
	Note.NoteType.HIT: 0,
	Note.NoteType.DODGE: 0
}


func _ready() -> void:
	# 根据实际视口宽度动态计算音符生成X坐标（屏幕右侧外100px）
	spawn_x = get_viewport().get_visible_rect().size.x + 100.0
	
	# 通过 EventBus 连接信号（替代 get_node 硬编码路径）
	EventBus.beat_hit.connect(_on_beat_hit)
	EventBus.chart_loaded.connect(set_chart)
	
	if not game_ui:
		push_warning("[TrackManager] game_ui 未设置，请在编辑器中拖拽 GameUI 节点到 @export")
	
	# 创建音符生成音效播放器
	spawn_audio_player_hit = AudioStreamPlayer.new()
	spawn_audio_player_guard = AudioStreamPlayer.new()
	spawn_audio_player_dodge = AudioStreamPlayer.new()
	
	spawn_audio_player_guard.name = "SpawnAudioGuard"
	spawn_audio_player_hit.name = "SpawnAudioHit"
	spawn_audio_player_dodge.name = "SpawnAudioDodge"
	
	add_child(spawn_audio_player_guard)
	add_child(spawn_audio_player_hit)
	add_child(spawn_audio_player_dodge)
	
	spawn_audio_player_guard.bus = "Master"
	spawn_audio_player_hit.bus = "Master"
	spawn_audio_player_dodge.bus = "Master"
	
	# 加载音符生成音效
	if key_sound_config:
		if key_sound_config.guard_sound:
			spawn_audio_player_guard.stream = key_sound_config.guard_sound
			spawn_audio_player_guard.volume_db = key_sound_config.guard_volume_db
		if key_sound_config.hit_sound:
			spawn_audio_player_hit.stream = key_sound_config.hit_sound
			spawn_audio_player_hit.volume_db = key_sound_config.hit_volume_db
		if key_sound_config.dodge_sound:
			spawn_audio_player_dodge.stream = key_sound_config.dodge_sound
			spawn_audio_player_dodge.volume_db = key_sound_config.dodge_volume_db


func _process(_delta: float) -> void:
	# 如果暂停，不生成新音符
	if is_paused:
		return
	
	# 获取当前音乐时间
	if music_player and music_player.playing:
		current_time = music_player.get_playback_position() + AudioServer.get_time_to_next_mix()
		
		# 检查是否需要生成音符（基于时间）
		_check_and_spawn_notes_by_time(current_time)
		
		# 更新所有活跃音符
		for note_visual in active_notes:
			if note_visual and note_visual.is_active:
				note_visual.update_position(current_time)
				
				# 检查是否到达判定线前两拍，播放音符音效
				var time_before_target: float = note_visual.target_time - current_time
				var two_beats_duration: float = 2.0 * EventBus.beat_interval
				if not note_visual.spawn_sound_played and time_before_target <= two_beats_duration:
					_play_spawn_sound(note_visual.note_data.type)
					note_visual.spawn_sound_played = true
				
				# 检查是否超过判定窗口（自动 MISS）
				var time_past_target: float = current_time - note_visual.target_time
				if time_past_target > MISS_THRESHOLD:
					EventBus.miss_triggered.emit(note_visual.note_data.type)
					note_visual.is_active = false
					note_visual.destroy()
			elif note_visual:
				# 清理非活跃音符
				note_visual.destroy()
		
		# 移除已销毁的音符
		active_notes = active_notes.filter(func(n): return n != null and is_instance_valid(n))
		
		# 检查非可视追踪音符的 MISS
		for i in range(tracked_notes.size() - 1, -1, -1):
			var note: Note = tracked_notes[i]
			var time_past: float = current_time - note.beat_time
			if time_past > MISS_THRESHOLD:
				EventBus.miss_triggered.emit(note.type)
				tracked_notes.remove_at(i)


## 设置铺面数据
func set_chart(chart: Chart) -> void:
	current_chart = chart
	scheduled_notes = chart.notes.duplicate()
	print("轨道管理器已加载铺面，共 ", scheduled_notes.size(), " 个音符待生成")


## 节拍触发回调
func _on_beat_hit(beat_number: float, _note: Note) -> void:
	if not current_chart:
		return
	
	# 检查是否需要提前生成音符
	_check_and_spawn_notes(beat_number)


## 检查并生成需要提前生成的音符（基于时间）
func _check_and_spawn_notes_by_time(current_time: float) -> void:
	for note in scheduled_notes.duplicate():
		var advance_beats: int = SPAWN_ADVANCE[note.type]
		var spawn_time: float = note.beat_time - advance_beats * EventBus.beat_interval
		
		# 如果当前时间已经到达或超过音符的生成时间
		if current_time >= spawn_time:
			_spawn_note(note)
			scheduled_notes.erase(note)


## 检查并生成需要提前生成的音符（已废弃，保留用于节拍信号触发）
func _check_and_spawn_notes(current_beat: float) -> void:
	# 此方法已被 _check_and_spawn_notes_by_time 替代
	# 但保留用于兼容 beat_hit 信号的调用
	pass


## 生成音符
func _spawn_note(note: Note) -> void:
	# 生成屏幕左侧特效动画（无论音符可视化是否启用）
	_spawn_track_animation(note)
	
	if note_visual_enabled:
		# 可视模式：创建 NoteVisual 实例
		if not game_ui:
			return
		var notes_container: Control = game_ui.get_notes_container()
		if not notes_container:
			return
		
		var note_visual := NOTE_VISUAL_SCENE.instantiate() as NoteVisual
		var track_y: float = game_ui.get_track_y(note.type)
		var judgment_x: float = game_ui.get_judgment_line_x()
		var spawn_pos := Vector2(spawn_x, track_y)
		var target_pos := Vector2(judgment_x, track_y)
		
		var advance_beats: int = SPAWN_ADVANCE[note.type]
		var spawn_time: float = note.beat_time - advance_beats * EventBus.beat_interval
		var move_start_time: float = spawn_time + EventBus.beat_interval
		var target_time: float = note.beat_time
		
		note_visual.initialize(note, spawn_pos, target_pos, move_start_time, target_time)
		notes_container.add_child(note_visual)
		active_notes.append(note_visual)
		print("生成音符: 节拍 #", note.beat_number, " ", note.get_type_string(), " 在时间 ", "%.3f" % spawn_time)
	else:
		# 非可视模式：仅追踪音符用于判定
		tracked_notes.append(note)


## 清除所有活跃的音符
func clear_all_notes() -> void:
	for note_visual in active_notes:
		if note_visual and is_instance_valid(note_visual):
			note_visual.destroy()
	active_notes.clear()
	tracked_notes.clear()
	# 清除所有活跃的 Bling 特效
	for track_type in _active_blings:
		for bling in _active_blings[track_type]:
			if bling and is_instance_valid(bling):
				bling.queue_free()
	_active_blings.clear()
	# 清除所有活跃的预警特效
	for warn in _active_warns:
		if warn and is_instance_valid(warn):
			warn.queue_free()
	_active_warns.clear()
	# 重置轮换计数器
	for key in _spawn_counters:
		_spawn_counters[key] = 0
	print("已清除所有活跃音符")


## 暂停音符生成
func pause_note_spawning() -> void:
	is_paused = true
	pause_start_time = current_time
	print("音符生成已暂停，时间: ", pause_start_time)


## 恢复音符生成
func resume_note_spawning() -> void:
	# 先更新当前时间到最新值（避免使用暂停前的旧时间）
	if music_player and music_player.playing:
		current_time = music_player.get_playback_position() + AudioServer.get_time_to_next_mix()
	
	# 只清理判定时间在当前时间之前的音符（已经来不及打了）
	# 保留判定时间还在未来的音符，即使它们的生成时间已过
	var removed_count: int = 0
	var buffer_time: float = 0.2  # 0.2秒缓冲，太接近当前时间的也跳过
	
	for note in scheduled_notes.duplicate():
		# 如果音符的判定时间已经过去（加上小缓冲），则跳过
		if note.beat_time < (current_time - buffer_time):
			scheduled_notes.erase(note)
			removed_count += 1
	
	if removed_count > 0:
		print("已跳过 ", removed_count, " 个判定时间已过的音符")
	
	# 清理已过期的追踪音符
	for i in range(tracked_notes.size() - 1, -1, -1):
		if tracked_notes[i].beat_time < (current_time - buffer_time):
			tracked_notes.remove_at(i)
	
	# 最后才恢复生成（避免_process在清理前执行）
	is_paused = false
	pause_start_time = 0.0
	
	print("音符生成已恢复")


## 生成轨道动画（音符生成时自动播放，attack_end_frame 对齐判定时刻）
func _spawn_track_animation(note: Note) -> void:
	if not game_ui:
		return
	
	# 获取当前轮换计数器并递增（warn 和主动画共用同一计数器以保持位置配对）
	var counter: int = _spawn_counters[note.type]
	_spawn_counters[note.type] = counter + 1
	
	# 检查是否配置了预警场景（仅自定义动画支持预警）
	var warn_scene: PackedScene = null
	if track_animation_config:
		if track_animation_config.get_scene(note.type) != null:
			warn_scene = track_animation_config.get_warn_scene(note.type)
	
	var advance_beats: int = SPAWN_ADVANCE[note.type]
	
	if warn_scene and advance_beats > 1:
		# 先播放预警特效（持续1拍），然后延迟1拍播放主动画
		_spawn_warn(note, warn_scene, counter)
		get_tree().create_timer(EventBus.beat_interval).timeout.connect(func() -> void:
			_spawn_main_animation(note, advance_beats - 1, counter)
		)
	else:
		# 无预警，直接播放主动画
		_spawn_main_animation(note, advance_beats, counter)


## 生成预警特效（在主动画之前显示，持续1拍后自动销毁）
func _spawn_warn(note: Note, warn_scene: PackedScene, counter: int) -> void:
	var instance: Node2D = warn_scene.instantiate()
	
	# 获取预警位置节点
	var warn_pos_nodes: Array[Node2D]
	match note.type:
		Note.NoteType.GUARD: warn_pos_nodes = guard_warn_position_nodes
		Note.NoteType.HIT:   warn_pos_nodes = hit_warn_position_nodes
		Note.NoteType.DODGE: warn_pos_nodes = dodge_warn_position_nodes
	
	if warn_pos_nodes.size() > 0:
		var pos_node: Node2D = warn_pos_nodes[counter % warn_pos_nodes.size()]
		game_ui.add_child(instance)
		instance.position = get_viewport().get_canvas_transform() * pos_node.global_position
	else:
		# 无预警位置节点时回退到主动画位置节点
		var pos_nodes: Array[Node2D]
		match note.type:
			Note.NoteType.GUARD: pos_nodes = guard_position_nodes
			Note.NoteType.HIT:   pos_nodes = hit_position_nodes
			Note.NoteType.DODGE: pos_nodes = dodge_position_nodes
		if pos_nodes.size() > 0:
			var pos_node: Node2D = pos_nodes[counter % pos_nodes.size()]
			game_ui.add_child(instance)
			instance.position = get_viewport().get_canvas_transform() * pos_node.global_position
		else:
			game_ui.add_child(instance)
	
	# 追踪预警实例（用于攻击阶段强制清除）
	_active_warns.append(instance)

	# 1拍后自动销毁
	var warn_duration: float = EventBus.beat_interval
	get_tree().create_timer(warn_duration).timeout.connect(func() -> void:
		if instance and is_instance_valid(instance):
			instance.queue_free()
		_active_warns.erase(instance)
	)
	
	print("[Warn] %s | counter=%d | duration=%.4fs" % [note.get_type_string(), counter, warn_duration])


## 生成主轨道动画（原始速度播放，通过延迟启动对齐判定时刻）
func _spawn_main_animation(note: Note, target_beats: int, counter: int) -> void:
	if not game_ui:
		return
	
	# 决定使用自定义动画还是默认 Bling
	var scene: PackedScene = null
	var anim_name: String = ""
	
	if track_animation_config:
		scene = track_animation_config.get_scene(note.type)
		anim_name = track_animation_config.get_animation_name(note.type)
	
	# 未配置自定义动画时回退到默认 Bling
	var use_default_bling: bool = (scene == null)
	if use_default_bling:
		scene = BLING_SCENE
		anim_name = BLING_ANIMATIONS[note.type]
	
	var instance: Node2D = scene.instantiate()
	var anim_sprite: AnimatedSprite2D = instance.get_node("AnimatedSprite2D")
	
	if not anim_sprite:
		push_warning("轨道动画场景缺少 AnimatedSprite2D 子节点")
		instance.queue_free()
		return
	
	# === 计算播放延迟 ===
	# 动画保持原始速度播放，通过延迟开始时间使 attack_end_frame 对齐判定时刻
	var target_duration: float = target_beats * EventBus.beat_interval
	var start_delay: float = 0.0
	
	var sprite_frames: SpriteFrames = anim_sprite.sprite_frames
	if sprite_frames and sprite_frames.has_animation(anim_name):
		# 获取攻击结束帧配置（-1 表示不设置）
		var attack_end_frame: int = -1
		if track_animation_config and not use_default_bling:
			attack_end_frame = track_animation_config.get_attack_end_frame(note.type)
		
		var frame_count: int = sprite_frames.get_frame_count(anim_name)
		
		if attack_end_frame > 0 and attack_end_frame < frame_count:
			# 计算帧 0 到 attack_end_frame-1 在原始速度下的播放时长
			var partial_duration: float = _get_animation_duration(sprite_frames, anim_name, 0, attack_end_frame - 1)
			# 延迟 = 可用时间 - 动画前摇时长，使 attack_end_frame 恰好对齐判定时刻
			start_delay = target_duration - partial_duration
			if start_delay < 0.0:
				start_delay = 0.0
			
			print("[TrackAnim] %s | anim=%s | total_frames=%d | attack_end_frame=%d | partial_dur=%.4fs | target_dur=%.4fs | start_delay=%.4fs" % [
				note.get_type_string(), anim_name, frame_count, attack_end_frame,
				partial_duration, target_duration, start_delay
			])
		else:
			print("[TrackAnim] %s | anim=%s | total_frames=%d | no attack_end_frame | target_dur=%.4fs | original speed" % [
				note.get_type_string(), anim_name, frame_count, target_duration
			])
	else:
		push_warning("动画 '%s' 不存在于 SpriteFrames 中" % anim_name)
	
	# 连接动画完成信号，播放结束后自动销毁
	anim_sprite.animation_finished.connect(func() -> void: instance.queue_free())
	
	# === 计算播放位置 ===
	# 根据音符类型获取对应的位置节点数组
	var pos_nodes: Array[Node2D]
	match note.type:
		Note.NoteType.GUARD: pos_nodes = guard_position_nodes
		Note.NoteType.HIT:   pos_nodes = hit_position_nodes
		Note.NoteType.DODGE: pos_nodes = dodge_position_nodes
	
	if pos_nodes.size() > 0:
		# 使用传入的计数器轮换位置，避免连续动画重叠
		var pos_node: Node2D = pos_nodes[counter % pos_nodes.size()]
		# 先 add_child 再赋位置，将世界坐标转换为屏幕坐标（CanvasLayer 使用屏幕坐标系）
		game_ui.add_child(instance)
		instance.position = get_viewport().get_canvas_transform() * pos_node.global_position
	else:
		# 默认 Bling 位置：固定行排列 + 同行槽位偏移
		var row_index: int = BLING_ROW_ORDER[note.type]
		var row_y: float = BLING_START_Y + row_index * BLING_ROW_HEIGHT
		var x_offset: float = _get_bling_x_offset(note.type)
		game_ui.add_child(instance)
		instance.position = Vector2(BLING_BASE_X + x_offset, row_y)
	
	# === 播放动画（可能延迟启动） ===
	if start_delay > 0.01:
		# 延迟期间隐藏实例，到时间后显示并播放
		instance.visible = false
		get_tree().create_timer(start_delay).timeout.connect(func() -> void:
			if is_instance_valid(instance):
				instance.visible = true
				anim_sprite.play(anim_name)
		)
	else:
		anim_sprite.play(anim_name)
	
	# 追踪活跃特效（用于默认 Bling 槽位避重）
	if not _active_blings.has(note.type):
		_active_blings[note.type] = []
	_active_blings[note.type].append(instance)


## 计算 SpriteFrames 中指定动画帧范围 [from_frame, to_frame] 的播放时长（秒）
## to_frame 不传则计算全部帧
func _get_animation_duration(sprite_frames: SpriteFrames, anim_name: String, from_frame: int = 0, to_frame: int = -1) -> float:
	var frame_count: int = sprite_frames.get_frame_count(anim_name)
	var base_fps: float = sprite_frames.get_animation_speed(anim_name)
	if frame_count <= 0 or base_fps <= 0:
		return 0.0
	var end: int = to_frame if (to_frame >= 0 and to_frame < frame_count) else frame_count - 1
	var total: float = 0.0
	for i in range(from_frame, end + 1):
		total += sprite_frames.get_frame_duration(anim_name, i)
	return total / base_fps


## 获取 Bling 特效的X偏移量（找到第一个没有被占据的位置）
func _get_bling_x_offset(note_type: Note.NoteType) -> float:
	if not _active_blings.has(note_type):
		return 0.0
	
	# 清理已销毁的特效引用
	_active_blings[note_type] = _active_blings[note_type].filter(
		func(e): return e != null and is_instance_valid(e)
	)
	
	# 收集所有已占据的X位置（取整到槽位索引避免浮点误差）
	var occupied_slots: Array[int] = []
	for existing_bling in _active_blings[note_type]:
		var slot: int = roundi((existing_bling.position.x - BLING_BASE_X) / BLING_OFFSET_X)
		if slot not in occupied_slots:
			occupied_slots.append(slot)
	
	# 找到第一个未被占据的槽位
	var target_slot: int = 0
	while target_slot in occupied_slots:
		target_slot += 1
	
	return target_slot * BLING_OFFSET_X


## 播放音符生成音效
func _play_spawn_sound(note_type: Note.NoteType) -> void:
	if not key_sound_config:
		return
	
	match note_type:
		Note.NoteType.GUARD:
			if spawn_audio_player_guard and spawn_audio_player_guard.stream:
				spawn_audio_player_guard.play()
		Note.NoteType.HIT:
			if spawn_audio_player_hit and spawn_audio_player_hit.stream:
				spawn_audio_player_hit.play()
		Note.NoteType.DODGE:
			if spawn_audio_player_dodge and spawn_audio_player_dodge.stream:
				spawn_audio_player_dodge.play()
