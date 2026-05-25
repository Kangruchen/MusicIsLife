extends CanvasLayer

const RhythmClock := preload("res://scripts/RhythmClock.gd")
const HeatBeatFlashStyle := preload("res://scripts/HeatBeatFlashStyle.gd")
## 游戏UI - 管理血条显示和攻击阶段UI

# 轨道配置（游戏逻辑坐标，用于判定计算）
const TRACK_HEIGHT: float = 80.0
const TRACK_SPACING: float = 10.0
const JUDGMENT_LINE_X: float = 100.0
const TRACK_START_Y: float = 57.0

# 节拍轨道视觉配置
const BEAT_TRACK_HEIGHT: float = 24.0
const BEAT_TRACK_TOP_OFFSET: float = 20.0
const BEAT_TRACK_WIDTH_RATIO: float = 0.8
const CURSOR_HALF_WIDTH: float = 2.0

# 血量条引用
@onready var boss_health_bar: ProgressBar = $MarginContainer/VBoxContainer/BossHealthBar
@onready var boss_guard_bar: ProgressBar = $MarginContainer/VBoxContainer/BossGuardBar
@onready var player_health_bar: ProgressBar = $MarginContainer2/VBoxContainer/PlayerHealthBar

# 暂停阶段视觉效果元素
var countdown_label: Label = null
var beat_flash_effect: ColorRect = null
var _countdown_active: bool = false
var _countdown_start_time: float = 0.0
var _countdown_beat_interval: float = 0.0
var _countdown_beat_count: int = 0
var _countdown_last_index: int = -1
var _beat_flash_active: bool = false
var _beat_flash_start_time: float = 0.0
var _beat_flash_interval: float = 0.0
var _beat_flash_count: int = 0
var _beat_flash_last_index: int = -1

# 攻击阶段UI元素
var attack_ui_container: Control = null

# 节拍轨道元素
var beat_track_container: Control = null
var beat_cursor: ColorRect = null
var _track_bi: float = 0.0
var _track_first_beat_time: float = 0.0
var _track_segment_width: float = 0.0
var _track_width: float = 0.0
var _track_input_beats: int = GameConstants.INPUT_BEATS

var _heat_tween: Tween = null
var _shake_intensity: float = 0.0
var _perfect_zones: Array[ColorRect] = []
var _current_heat_level: int = -1
var _resolved_zones: Dictionary = {}
var _heat_dots: Array[ColorRect] = []
var _heat_dots_container: Control = null
var _heavy_heat_consumed: bool = false

var _victory_label: Label = null
var _is_boss_defeated: bool = false

@export var show_on_ready: bool = true

@onready var music_player: Node = get_node_or_null("../GameManager/MusicPlayer")


func _ready() -> void:
	EventBus.judgment_made.connect(_on_judgment_made)

	EventBus.player_health_updated.connect(_on_player_health_updated)
	EventBus.boss_health_updated.connect(_on_boss_health_updated)
	EventBus.boss_energy_updated.connect(_on_boss_energy_updated)

	EventBus.show_attack_ui_requested.connect(show_attack_ui)
	EventBus.hide_attack_ui_requested.connect(hide_attack_ui)
	EventBus.show_return_countdown_requested.connect(show_return_countdown)
	EventBus.show_pause_countdown_requested.connect(_on_show_pause_countdown)
	EventBus.play_beat_flash_requested.connect(_on_play_beat_flash)
	EventBus.hide_pause_effects_requested.connect(hide_pause_effects)
	EventBus.boss_defeated.connect(_on_boss_defeated)
	EventBus.heat_changed.connect(_on_heat_changed)
	EventBus.attack_track_setup.connect(_on_attack_track_setup)
	EventBus.attack_result_display.connect(_on_attack_result_display)

	visible = show_on_ready
	if show_on_ready:
		show()
	else:
		hide()

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

	beat_flash_effect = ColorRect.new()
	beat_flash_effect.name = "BeatFlashEffect"
	beat_flash_effect.color = Color(1.0, 1.0, 1.0, 0.0)
	beat_flash_effect.anchor_right = 1.0
	beat_flash_effect.anchor_bottom = 1.0
	beat_flash_effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(beat_flash_effect)
	move_child(beat_flash_effect, 0)

	_create_attack_ui()


func _process(_delta: float) -> void:
	_update_beat_cursor()
	_update_heat_shake()
	_update_pause_countdown_by_clock()
	_update_beat_flash_by_clock()


func _get_beat_clock_time() -> float:
	return RhythmClock.get_music_or_wall_time(music_player)


func get_track_y(note_type: Note.NoteType) -> float:
	var track_index := note_type as int
	return TRACK_START_Y + track_index * (TRACK_HEIGHT + TRACK_SPACING) + TRACK_HEIGHT / 2.0


func get_judgment_line_x() -> float:
	return JUDGMENT_LINE_X


func get_notes_container() -> Control:
	return null


func _on_judgment_made(_track: Note.NoteType, _judgment: int, _timing_diff: float) -> void:
	pass


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


func _on_show_pause_countdown(bi: float, beat_count: int = GameConstants.COUNTDOWN_BEATS, start_time: float = 0.0) -> void:
	if not countdown_label:
		return
	if bi <= 0.0:
		_countdown_active = false
		countdown_label.visible = false
		return
	_countdown_active = true
	_countdown_start_time = start_time
	_countdown_beat_interval = bi
	_countdown_beat_count = maxi(1, beat_count)
	_countdown_last_index = -1

	countdown_label.visible = true
	_update_pause_countdown_by_clock()


func _update_pause_countdown_by_clock() -> void:
	if not _countdown_active:
		return
	if not countdown_label:
		_countdown_active = false
		return
	if _countdown_beat_interval <= 0.0:
		_countdown_active = false
		countdown_label.visible = false
		return

	var elapsed: float = _get_beat_clock_time() - _countdown_start_time
	var index: int = int(floor(elapsed / _countdown_beat_interval))
	if index < 0:
		return
	if index >= _countdown_beat_count:
		_countdown_active = false
		countdown_label.visible = false
		return
	if index == _countdown_last_index:
		return

	_countdown_last_index = index
	var count_num: int = _countdown_beat_count - index
	_pulse_countdown(count_num, _countdown_beat_interval)


func _pulse_countdown(count_num: int, bi: float) -> void:
	countdown_label.text = str(count_num)

	var scale_tween: Tween = create_tween()
	scale_tween.set_ease(Tween.EASE_OUT)
	scale_tween.set_trans(Tween.TRANS_BACK)
	countdown_label.scale = Vector2(1.5, 1.5)
	scale_tween.tween_property(countdown_label, "scale", Vector2(1.0, 1.0), bi * 0.3)

	var alpha_tween: Tween = create_tween()
	alpha_tween.set_ease(Tween.EASE_OUT)
	countdown_label.modulate.a = 1.0
	alpha_tween.tween_property(countdown_label, "modulate:a", 0.5, bi * 0.8)


func _on_play_beat_flash(bi: float, beat_count: int, start_time: float = 0.0) -> void:
	if _is_boss_defeated:
		return
	if not beat_flash_effect:
		return
	if bi <= 0.0 or beat_count <= 0:
		_beat_flash_active = false
		return
	_beat_flash_active = true
	_beat_flash_start_time = start_time
	_beat_flash_interval = bi
	_beat_flash_count = beat_count
	_beat_flash_last_index = -1
	_update_beat_flash_by_clock()


func _update_beat_flash_by_clock() -> void:
	if not _beat_flash_active:
		return
	if _is_boss_defeated or not beat_flash_effect:
		_beat_flash_active = false
		return
	if _beat_flash_interval <= 0.0:
		_beat_flash_active = false
		return

	var elapsed: float = _get_beat_clock_time() - _beat_flash_start_time
	var index: int = int(floor(elapsed / _beat_flash_interval))
	if index < 0:
		return
	if index >= _beat_flash_count:
		_beat_flash_active = false
		return
	if index == _beat_flash_last_index:
		return

	_beat_flash_last_index = index
	_pulse_beat_flash(_beat_flash_interval)


func _pulse_beat_flash(bi: float) -> void:
	var flash_tween: Tween = create_tween()
	flash_tween.set_ease(Tween.EASE_OUT)
	flash_tween.set_trans(Tween.TRANS_CUBIC)
	beat_flash_effect.color = Color(1.0, 1.0, 0.8, 0.3)
	flash_tween.tween_property(beat_flash_effect, "color:a", 0.0, bi * 0.6)


func hide_pause_effects() -> void:
	_countdown_active = false
	_beat_flash_active = false
	if countdown_label:
		countdown_label.visible = false
	if beat_flash_effect:
		beat_flash_effect.color.a = 0.0


func _create_attack_ui() -> void:
	attack_ui_container = Control.new()
	attack_ui_container.name = "AttackUIContainer"
	attack_ui_container.anchor_left = 0.0
	attack_ui_container.anchor_top = 0.0
	attack_ui_container.anchor_right = 1.0
	attack_ui_container.anchor_bottom = 1.0
	attack_ui_container.visible = false
	attack_ui_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(attack_ui_container)

	_create_heat_dots()


func _create_heat_dots() -> void:
	const DOT_SIZE: float = 14.0
	const DOT_SPACING: float = 8.0
	const TOTAL_WIDTH: float = GameConstants.PERFECTS_PER_LEVEL * DOT_SIZE + (GameConstants.PERFECTS_PER_LEVEL - 1) * DOT_SPACING
	const DOTS_Y: float = BEAT_TRACK_TOP_OFFSET + BEAT_TRACK_HEIGHT + 12.0

	_heat_dots_container = Control.new()
	_heat_dots_container.name = "HeatDotsContainer"
	_heat_dots_container.anchor_left = 0.5
	_heat_dots_container.anchor_right = 0.5
	_heat_dots_container.offset_left = -TOTAL_WIDTH / 2.0
	_heat_dots_container.offset_right = TOTAL_WIDTH / 2.0
	_heat_dots_container.offset_top = DOTS_Y
	_heat_dots_container.offset_bottom = DOTS_Y + DOT_SIZE
	_heat_dots_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heat_dots_container.visible = false
	attack_ui_container.add_child(_heat_dots_container)

	for i in range(GameConstants.PERFECTS_PER_LEVEL):
		var dot: ColorRect = ColorRect.new()
		dot.name = "HeatDot%d" % i
		dot.size = Vector2(DOT_SIZE, DOT_SIZE)
		dot.position.x = i * (DOT_SIZE + DOT_SPACING)
		dot.color = Color(0.2, 0.2, 0.2, 0.5)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_heat_dots_container.add_child(dot)
		_heat_dots.append(dot)


func _update_heat_dots(heat_counter: int) -> void:
	for i in range(_heat_dots.size()):
		var dot: ColorRect = _heat_dots[i]
		if not is_instance_valid(dot):
			continue
		if i < heat_counter:
			dot.color = Color(1.0, 0.65, 0.0, 1.0)
		else:
			dot.color = Color(0.2, 0.2, 0.2, 0.5)


func _on_attack_track_setup(
	bi: float,
	first_beat_time: float,
	_countdown_beats: int = GameConstants.COUNTDOWN_BEATS,
	input_beats: int = GameConstants.INPUT_BEATS,
	_exit_beats: int = GameConstants.EXIT_BEATS
) -> void:
	_track_input_beats = maxi(1, input_beats)
	_clear_beat_track()
	_create_beat_track(bi, first_beat_time)


func _create_beat_track(bi: float, first_beat_time: float) -> void:
	if bi <= 0.0:
		return

	_track_bi = bi
	_track_first_beat_time = first_beat_time

	var screen_width: float = get_viewport().get_visible_rect().size.x
	_track_width = screen_width * BEAT_TRACK_WIDTH_RATIO
	_track_segment_width = _track_width / float(_track_input_beats)

	var perfect_ratio: float = GameConstants.ATTACK_PERFECT_WINDOW / bi
	var perfect_width: float = _track_segment_width * perfect_ratio
	var miss_side_width: float = (_track_segment_width - perfect_width) / 2.0

	beat_track_container = Control.new()
	beat_track_container.name = "BeatTrackContainer"
	beat_track_container.anchor_left = 0.5
	beat_track_container.anchor_right = 0.5
	beat_track_container.offset_left = -_track_width / 2.0
	beat_track_container.offset_right = _track_width / 2.0
	beat_track_container.offset_top = BEAT_TRACK_TOP_OFFSET
	beat_track_container.offset_bottom = BEAT_TRACK_TOP_OFFSET + BEAT_TRACK_HEIGHT
	beat_track_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	attack_ui_container.add_child(beat_track_container)

	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.08, 0.6)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	beat_track_container.add_child(bg)

	for i in range(_track_input_beats):
		var x: float = i * _track_segment_width

		var left_miss: ColorRect = ColorRect.new()
		left_miss.color = Color(0.25, 0.12, 0.12, 0.7)
		left_miss.position = Vector2(x, 0.0)
		left_miss.size = Vector2(miss_side_width, BEAT_TRACK_HEIGHT)
		left_miss.mouse_filter = Control.MOUSE_FILTER_IGNORE
		beat_track_container.add_child(left_miss)

		var perfect_zone: ColorRect = ColorRect.new()
		perfect_zone.color = Color(0.9, 0.9, 0.9, 0.9)
		perfect_zone.position = Vector2(x + miss_side_width, 0.0)
		perfect_zone.size = Vector2(perfect_width, BEAT_TRACK_HEIGHT)
		perfect_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
		beat_track_container.add_child(perfect_zone)
		_perfect_zones.append(perfect_zone)

		var right_miss: ColorRect = ColorRect.new()
		right_miss.color = Color(0.25, 0.12, 0.12, 0.7)
		right_miss.position = Vector2(x + miss_side_width + perfect_width, 0.0)
		right_miss.size = Vector2(miss_side_width, BEAT_TRACK_HEIGHT)
		right_miss.mouse_filter = Control.MOUSE_FILTER_IGNORE
		beat_track_container.add_child(right_miss)

		if i > 0:
			var border: ColorRect = ColorRect.new()
			border.color = Color(0.0, 0.0, 0.0, 0.6)
			border.position = Vector2(x - 1.0, 0.0)
			border.size = Vector2(2.0, BEAT_TRACK_HEIGHT)
			border.mouse_filter = Control.MOUSE_FILTER_IGNORE
			beat_track_container.add_child(border)

	beat_cursor = ColorRect.new()
	beat_cursor.name = "BeatCursor"
	beat_cursor.color = Color(1.0, 1.0, 1.0, 1.0)
	beat_cursor.position = Vector2(-CURSOR_HALF_WIDTH, -4.0)
	beat_cursor.size = Vector2(CURSOR_HALF_WIDTH * 2.0, BEAT_TRACK_HEIGHT + 8.0)
	beat_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	beat_track_container.add_child(beat_cursor)


func _clear_beat_track() -> void:
	if beat_track_container != null and is_instance_valid(beat_track_container):
		beat_track_container.queue_free()
	beat_track_container = null
	beat_cursor = null
	_track_bi = 0.0
	_track_first_beat_time = 0.0
	_track_segment_width = 0.0
	_track_width = 0.0
	_perfect_zones.clear()
	_resolved_zones.clear()


func _update_beat_cursor() -> void:
	if beat_cursor == null or _track_bi <= 0.0 or _track_segment_width <= 0.0:
		return

	var now: float = _get_beat_clock_time()
	var cursor_x: float = (now - _track_first_beat_time + _track_bi * 0.5) / _track_bi * _track_segment_width

	beat_cursor.position.x = cursor_x - CURSOR_HALF_WIDTH

	if cursor_x < -_track_segment_width or cursor_x > _track_width + _track_segment_width:
		beat_cursor.visible = false
	else:
		beat_cursor.visible = true


func _update_heat_shake() -> void:
	if _shake_intensity > 0.0 and attack_ui_container and attack_ui_container.visible:
		attack_ui_container.position = Vector2(
			randf_range(-_shake_intensity, _shake_intensity),
			randf_range(-_shake_intensity, _shake_intensity)
		)
	elif attack_ui_container:
		attack_ui_container.position = Vector2.ZERO


func _flash_perfect_zones_on_heat_change(prev_level: int, new_level: int) -> void:
	if _perfect_zones.is_empty():
		return
	if prev_level == new_level:
		return

	var flash_color: Color
	if new_level > prev_level:
		flash_color = Color(1.0, 0.9, 0.4, 1.0)
	else:
		flash_color = Color(0.4, 0.5, 0.8, 0.9)

	for i in range(_perfect_zones.size()):
		if _resolved_zones.has(i):
			continue
		var zone: ColorRect = _perfect_zones[i]
		if not is_instance_valid(zone):
			continue
		var saved_color: Color = zone.color
		zone.color = flash_color
		var tween: Tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(zone, "color", saved_color, 0.3)


func _update_perfect_zone_glow(heat_level: int) -> void:
	for i in range(_perfect_zones.size()):
		if _resolved_zones.has(i):
			continue
		var zone: ColorRect = _perfect_zones[i]
		if not is_instance_valid(zone):
			continue
		match heat_level:
			0, 1, 2:
				zone.color = Color(0.9, 0.9, 0.9, 0.9)
			3:
				zone.color = Color(1.0, 0.8, 0.6, 0.95)
			4:
				zone.color = Color(1.0, 0.95, 0.85, 1.0)


func _on_attack_result_display(attack_type: int, is_perfect: bool, _heat_level: int) -> void:
	if attack_type == 1:  # HEAVY
		_heavy_heat_consumed = true
	if _track_bi <= 0.0 or _perfect_zones.is_empty():
		return

	var now: float = _get_beat_clock_time()
	var beat_idx: int = int((now - _track_first_beat_time + _track_bi * 0.5) / _track_bi)
	if beat_idx < 0 or beat_idx >= _perfect_zones.size():
		return
	if _resolved_zones.has(beat_idx):
		return

	var zone: ColorRect = _perfect_zones[beat_idx]
	if not is_instance_valid(zone):
		return

	if is_perfect:
		zone.color = Color(0.2, 0.9, 0.3, 0.95)
		_resolved_zones[beat_idx] = true
	else:
		zone.color = Color(0.9, 0.15, 0.15, 0.9)
		_resolved_zones[beat_idx] = true


func _show_center_text(text: String, color: Color) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 42)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	label.add_theme_constant_override("outline_size", 5)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.anchor_left = 0.5
	label.anchor_top = 0.38
	label.anchor_right = 0.5
	label.anchor_bottom = 0.38
	label.offset_left = -220.0
	label.offset_top = -40.0
	label.offset_right = 220.0
	label.offset_bottom = 40.0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 80
	label.modulate.a = 0.0
	label.scale = Vector2(0.7, 0.7)
	add_child(label)

	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(label, "modulate:a", 1.0, 0.2)
	tween.parallel().tween_property(label, "scale", Vector2(1.0, 1.0), 0.25)
	tween.tween_property(label, "scale", Vector2(1.05, 1.05), 0.5)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(label.queue_free)


func _cleanup_heat_effects() -> void:
	if _heat_tween != null and _heat_tween.is_valid():
		_heat_tween.kill()
	_heat_tween = null
	_shake_intensity = 0.0
	_current_heat_level = -1
	_resolved_zones.clear()
	if beat_flash_effect:
		beat_flash_effect.color = Color(1.0, 1.0, 1.0, 0.0)
	if attack_ui_container:
		attack_ui_container.position = Vector2.ZERO


func show_attack_ui() -> void:
	if attack_ui_container:
		attack_ui_container.visible = true
	if _heat_dots_container:
		_heat_dots_container.visible = true


func show_return_countdown(count: int) -> void:
	if countdown_label:
		countdown_label.text = str(count)
		countdown_label.visible = true
		countdown_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.0))

		var scale_tween: Tween = create_tween()
		scale_tween.set_ease(Tween.EASE_OUT)
		scale_tween.set_trans(Tween.TRANS_BACK)
		countdown_label.scale = Vector2(1.5, 1.5)
		scale_tween.tween_property(countdown_label, "scale", Vector2(1.0, 1.0), 0.3)

		var alpha_tween: Tween = create_tween()
		alpha_tween.set_ease(Tween.EASE_OUT)
		countdown_label.modulate.a = 1.0
		alpha_tween.tween_property(countdown_label, "modulate:a", 0.5, 0.6)


func hide_attack_ui() -> void:
	if attack_ui_container:
		attack_ui_container.visible = false
		attack_ui_container.position = Vector2.ZERO
	if _heat_dots_container:
		_heat_dots_container.visible = false
		_update_heat_dots(0)
	if countdown_label:
		countdown_label.visible = false
	_clear_beat_track()
	_cleanup_heat_effects()


func _on_heat_changed(heat_level: int, heat_counter: int) -> void:
	_update_heat_dots(heat_counter)

	if heat_level != _current_heat_level:
		var prev_level: int = _current_heat_level
		_current_heat_level = heat_level

		if heat_level > prev_level:
			_show_center_text("Heat Up! Lv%d" % (heat_level + 1), Color(1.0, 0.85, 0.2))
		elif heat_level < prev_level and prev_level >= 0:
			if _heavy_heat_consumed and heat_level == 0:
				_heavy_heat_consumed = false
			else:
				_show_center_text("Heat Down", Color(0.5, 0.6, 0.8))

		if beat_flash_effect:
			if _heat_tween != null and _heat_tween.is_valid():
				_heat_tween.kill()
			_heat_tween = null

			_flash_perfect_zones_on_heat_change(prev_level, heat_level)
			_update_perfect_zone_glow(heat_level)
			_apply_heat_beat_flash(heat_level, prev_level)


func _apply_heat_beat_flash(heat_level: int, prev_level: int) -> void:

	var is_level_up: bool = heat_level > prev_level

	if heat_level == 0:
		if prev_level > 0:
			beat_flash_effect.color = Color(0.3, 0.4, 0.6, 0.25)
			_heat_tween = create_tween()
			_heat_tween.tween_property(beat_flash_effect, "color:a", 0.0, 0.5)
		else:
			beat_flash_effect.color = Color(1.0, 1.0, 1.0, 0.0)
		_shake_intensity = 0.0
		return

	var style: Dictionary = HeatBeatFlashStyle.get_style(heat_level, is_level_up)
	if style.is_empty():
		return

	var flash_color: Color = style["flash_color"]
	var flash_alpha: float = style["flash_alpha"]
	var pulse_low: float = style["pulse_low"]
	var pulse_high: float = style["pulse_high"]
	var pulse_period: float = style["pulse_period"]
	_shake_intensity = style["shake_intensity"]

	if is_level_up and prev_level >= 0:
		beat_flash_effect.color = Color(flash_color.r, flash_color.g, flash_color.b, flash_alpha)
		_heat_tween = create_tween()
		_heat_tween.tween_property(beat_flash_effect, "color:a", pulse_high, 0.35).set_ease(Tween.EASE_OUT)
		_heat_tween.tween_property(beat_flash_effect, "color:a", pulse_low, pulse_period)
		_heat_tween.tween_property(beat_flash_effect, "color:a", pulse_high, pulse_period)
		_heat_tween.set_loops(0)
	else:
		beat_flash_effect.color = Color(0.3, 0.4, 0.6, 0.20)
		_heat_tween = create_tween()
		_heat_tween.tween_property(beat_flash_effect, "color", Color(flash_color.r, flash_color.g, flash_color.b, pulse_high), 0.3)
		_heat_tween.tween_property(beat_flash_effect, "color:a", pulse_low, pulse_period)
		_heat_tween.tween_property(beat_flash_effect, "color:a", pulse_high, pulse_period)
		_heat_tween.set_loops(0)


func _on_boss_defeated() -> void:
	_is_boss_defeated = true

	hide_pause_effects()
	hide_attack_ui()

	if beat_flash_effect:
		beat_flash_effect.color.a = 0.0
		beat_flash_effect.visible = false

	if _victory_label != null and is_instance_valid(_victory_label):
		_victory_label.queue_free()
	_victory_label = Label.new()
	_victory_label.name = "VictoryLabel"
	_victory_label.add_theme_font_size_override("font_size", 72)
	_victory_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
	_victory_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_victory_label.add_theme_constant_override("outline_size", 6)
	_victory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_victory_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_victory_label.anchor_left = 0.0
	_victory_label.anchor_top = 0.35
	_victory_label.anchor_right = 1.0
	_victory_label.anchor_bottom = 0.55
	_victory_label.text = "通关！"
	_victory_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_victory_label)

	var restart_hint: Label = Label.new()
	restart_hint.name = "RestartHint"
	restart_hint.add_theme_font_size_override("font_size", 28)
	restart_hint.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	restart_hint.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	restart_hint.add_theme_constant_override("outline_size", 4)
	restart_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	restart_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	restart_hint.anchor_left = 0.0
	restart_hint.anchor_top = 0.55
	restart_hint.anchor_right = 1.0
	restart_hint.anchor_bottom = 0.65
	restart_hint.text = "按 %s 重新开始" % GameConstants.get_action_key_label("restart", "R")
	restart_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(restart_hint)

	_victory_label.modulate.a = 0.0
	var fade_in: Tween = create_tween()
	fade_in.set_ease(Tween.EASE_OUT)
	fade_in.set_trans(Tween.TRANS_SINE)
	fade_in.tween_property(_victory_label, "modulate:a", 1.0, 0.8)

	restart_hint.modulate.a = 0.0
	var hint_fade: Tween = create_tween()
	hint_fade.set_ease(Tween.EASE_OUT)
	hint_fade.set_trans(Tween.TRANS_SINE)
	hint_fade.tween_property(restart_hint, "modulate:a", 1.0, 0.8).set_delay(1.0)
