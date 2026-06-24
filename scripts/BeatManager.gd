extends Node

const RhythmClock := preload("res://scripts/RhythmClock.gd")

@export var bpm: float = 128.0
@export var offset: float = 0.0
@export var generate_test_chart: bool = false
@export_file("*.sm") var chart_sm_path: String = ""
@export_group("Debug Laser Pattern Layers")
@export var debug_enable_laser_pattern_layers: bool = false
@export_group("")

# Global player/device calibration in seconds.
@export var user_offset: float = 0.0

var current_chart: Chart = null
var beat_interval: float = 0.0
var next_beat_time: float = 0.0
var current_beat: float = 0.0
var is_playing: bool = false
var is_paused: bool = false
var pause_start_time: float = 0.0
var total_pause_duration: float = 0.0

@onready var music_player: Node = get_node("../MusicPlayer")


func load_user_offset() -> void:
	if user_offset != 0.0:
		print("Using editor audio calibration: ", user_offset, " sec (", user_offset * 1000.0, " ms)")
		return

	var config := ConfigFile.new()
	var err := config.load("user://settings.cfg")
	if err == OK:
		var user_offset_ms: float = config.get_value("audio", "offset", 0.0)
		user_offset = user_offset_ms / 1000.0
		print("Loaded audio calibration: ", user_offset_ms, " ms (", user_offset, " sec)")


func _ready() -> void:
	load_user_offset()

	beat_interval = 60.0 / bpm if bpm > 0.0 else 0.0
	EventBus.music_started.connect(_on_music_started)
	print("BeatManager connected to music_started")


func _process(_delta: float) -> void:
	if not is_playing or is_paused:
		return
	if beat_interval <= 0.0:
		return

	var current_time: float = RhythmClock.get_music_time(music_player)
	while current_time >= next_beat_time:
		_on_beat()
		next_beat_time += beat_interval


func _on_music_started() -> void:
	is_playing = true
	current_beat = 0.0

	if chart_sm_path != "":
		current_chart = SMFileLoader.load_from_sm(chart_sm_path, "", debug_enable_laser_pattern_layers)
		if current_chart:
			bpm = current_chart.bpm
			var original_offset := current_chart.offset
			offset = original_offset + user_offset
			beat_interval = 60.0 / bpm
			_recalculate_note_times(current_chart, original_offset, offset)
			print("SM raw offset: ", current_chart.source_offset,
				" -> runtime beat0 time: ", original_offset,
				" + user offset: ", user_offset,
				" = effective beat0 time: ", offset)
			print("Chart mode: ",
				"standard + laser pattern layers" if debug_enable_laser_pattern_layers else "standard",
				", path=", chart_sm_path)
	elif generate_test_chart:
		offset += user_offset
		_generate_test_chart()
		print("Generated test chart, effective beat0 time: ", offset)

	EventBus.beat_interval = beat_interval

	if current_chart:
		EventBus.chart_loaded.emit(current_chart)

	next_beat_time = offset
	print("BeatManager started - BPM: ", bpm, ", beat0 time: ", offset, " sec")


func _recalculate_note_times(chart: Chart, old_offset: float, new_offset: float) -> void:
	var offset_diff := new_offset - old_offset
	chart.offset = new_offset
	chart.call("shift_times", offset_diff)
	var laser_patterns: Array = chart.get("laser_patterns")
	print("Recalculated ", chart.notes.size(), " notes and ", laser_patterns.size(), " laser patterns, timing delta: ", offset_diff, " sec")


func _generate_test_chart() -> void:
	current_chart = Chart.new()
	current_chart.chart_name = "Test Chart"
	current_chart.bpm = bpm
	current_chart.offset = offset
	current_chart.source_offset = -offset

	for i in range(1, 101):
		var note := Note.new()
		note.beat_number = float(i)
		note.beat_time = offset + i * beat_interval
		note.type = randi() % 3 as Note.NoteType
		current_chart.add_note(note)

	print("Generated test chart with ", current_chart.notes.size(), " notes")


func _on_beat() -> void:
	current_beat += 1.0

	var note: Note = null
	if current_chart:
		note = current_chart.get_note_at_beat(current_beat)

	if note:
		print("Beat #", current_beat, " time: ", "%.3f" % next_beat_time, " sec - note: ", note.get_type_string())
	else:
		print("Beat #", current_beat, " time: ", "%.3f" % next_beat_time, " sec - no note")

	EventBus.beat_hit.emit(current_beat, note)


func pause_beat_detection() -> void:
	is_paused = true
	print("Beat detection paused")


func resume_beat_detection() -> void:
	is_paused = false
	print("Beat detection resumed")
