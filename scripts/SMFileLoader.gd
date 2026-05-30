extends Node
class_name SMFileLoader

const LASER_ECHO_LAYER := "laser_echo"
const LASER_CHORD_LAYER := "laser_chord"
const BEATS_PER_MEASURE := 4.0
const LaserPatternEventScript := preload("res://scripts/LaserPatternEvent.gd")


static func load_from_sm(sm_path: String, difficulty: String = "") -> Chart:
	var file := FileAccess.open(sm_path, FileAccess.READ)
	if not file:
		push_error("Cannot open .sm file: ", sm_path)
		return null

	var content := file.get_as_text()
	file.close()

	var chart := Chart.new()
	chart.chart_name = _extract_tag(content, "TITLE")
	var artist := _extract_tag(content, "ARTIST")
	if not artist.is_empty():
		chart.chart_name += " - " + artist

	var bpms_str := _extract_tag(content, "BPMS")
	chart.bpm = _parse_first_bpm(bpms_str)

	var offset_str := _extract_tag(content, "OFFSET")
	var sm_offset := offset_str.to_float()
	chart.source_offset = sm_offset
	chart.offset = -sm_offset

	var sections := _extract_notes_sections(content)
	var standard_section := _select_standard_notes_section(sections, difficulty)
	if not standard_section.is_empty():
		_parse_standard_notes(standard_section, chart)

	for section in sections:
		var layer_kind := String(section.get("layer_kind", ""))
		if layer_kind == LASER_ECHO_LAYER:
			_parse_laser_echo_layer(section, chart)
		elif layer_kind == LASER_CHORD_LAYER:
			_parse_laser_chord_layer(section, chart)

	chart.sort_notes()
	chart.call("sort_laser_patterns")

	var laser_patterns: Array = chart.get("laser_patterns")
	print("Loaded .sm chart: ", chart.chart_name,
		", notes=", chart.notes.size(),
		", laser_patterns=", laser_patterns.size())
	return chart


static func _extract_tag(content: String, tag: String) -> String:
	var pattern := "#" + tag + ":"
	var start_idx := content.find(pattern)
	if start_idx == -1:
		return ""

	start_idx += pattern.length()
	var end_idx := content.find(";", start_idx)
	if end_idx == -1:
		return ""

	return content.substr(start_idx, end_idx - start_idx).strip_edges()


static func _parse_first_bpm(bpms_str: String) -> float:
	var parts := bpms_str.split("=")
	if parts.size() < 2:
		return 120.0

	var bpm_part := parts[1].split(",")[0]
	return bpm_part.to_float()


static func _extract_notes_sections(content: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw_sections := content.split("#NOTES:")

	for i in range(1, raw_sections.size()):
		var body := String(raw_sections[i])
		var end_idx := body.find(";")
		if end_idx != -1:
			body = body.substr(0, end_idx)

		var parsed := _parse_notes_section_header(body)
		if not parsed.is_empty():
			result.append(parsed)

	return result


static func _parse_notes_section_header(section_body: String) -> Dictionary:
	var lines := section_body.split("\n")
	var metadata: Array[String] = []
	var note_lines: Array[String] = []
	var in_notes := false

	for line in lines:
		var trimmed := String(line).strip_edges()
		if trimmed.is_empty():
			continue

		if not in_notes:
			if _is_note_row(trimmed):
				in_notes = true
			elif trimmed.contains(":"):
				var metadata_value := trimmed
				if metadata_value.ends_with(":"):
					metadata_value = metadata_value.substr(0, metadata_value.length() - 1)
				metadata.append(metadata_value.strip_edges())
				continue
			else:
				continue

		if in_notes:
			note_lines.append(trimmed)

	if note_lines.is_empty():
		return {}

	var description := String(metadata[1]) if metadata.size() > 1 else ""
	var chart_difficulty := String(metadata[2]) if metadata.size() > 2 else ""
	var layer_kind := _detect_layer_kind(metadata)

	return {
		"metadata": metadata,
		"description": description,
		"difficulty": chart_difficulty,
		"layer_kind": layer_kind,
		"body": "\n".join(note_lines)
	}


static func _detect_layer_kind(metadata: Array[String]) -> String:
	for value in metadata:
		var normalized := _normalize_layer_name(value)
		if normalized.contains("laserecho"):
			return LASER_ECHO_LAYER
		if normalized.contains("laserchord"):
			return LASER_CHORD_LAYER
	return ""


static func _normalize_layer_name(value: String) -> String:
	return value.to_lower().replace(" ", "").replace("_", "").replace("-", "")


static func _select_standard_notes_section(sections: Array[Dictionary], difficulty: String) -> Dictionary:
	if not difficulty.is_empty():
		for section in sections:
			if not String(section.get("layer_kind", "")).is_empty():
				continue
			if _section_matches_difficulty(section, difficulty):
				return section

	for section in sections:
		if String(section.get("layer_kind", "")).is_empty():
			return section

	return {}


static func _section_matches_difficulty(section: Dictionary, difficulty: String) -> bool:
	var needle := difficulty.to_lower()
	var metadata: Array = section.get("metadata", [])
	for value in metadata:
		if String(value).to_lower().contains(needle):
			return true
	return false


static func _parse_standard_notes(section: Dictionary, chart: Chart) -> void:
	var measures := _collect_measures(String(section["body"]))
	var beat_interval := 60.0 / chart.bpm

	for measure in range(measures.size()):
		_process_standard_measure(measures[measure], measure, chart, beat_interval)


static func _process_standard_measure(measure_lines: Array, measure: int, chart: Chart, beat_interval: float) -> void:
	var lines_count := measure_lines.size()
	if lines_count <= 0:
		return

	var beats_per_line := BEATS_PER_MEASURE / float(lines_count)
	for i in range(lines_count):
		var line := String(measure_lines[i])
		if line.length() < 4:
			continue

		var beat_in_measure := float(i) * beats_per_line
		var total_beats := float(measure) * BEATS_PER_MEASURE + beat_in_measure
		var beat_time := chart.offset + total_beats * beat_interval

		for track_idx in range(min(4, line.length())):
			var note_char := line.substr(track_idx, 1)
			if _is_active_note_char(note_char):
				var note := Note.new()
				note.beat_number = total_beats
				note.beat_time = beat_time

				match track_idx:
					0, 1:
						note.type = Note.NoteType.HIT
					2:
						note.type = Note.NoteType.GUARD
					3:
						note.type = Note.NoteType.DODGE

				chart.add_note(note)


static func _parse_laser_echo_layer(section: Dictionary, chart: Chart) -> void:
	var measures := _collect_measures(String(section["body"]))
	var beat_interval := 60.0 / chart.bpm
	var source_layer := _get_source_layer_name(section, "LaserEcho")

	for measure in range(measures.size()):
		var measure_lines: Array = measures[measure]
		if measure_lines.is_empty():
			continue

		var event: Resource = LaserPatternEventScript.new()
		event.kind = LaserPatternEventScript.PatternKind.ECHO
		event.source_layer = source_layer
		event.beat_number = float(measure) * BEATS_PER_MEASURE
		event.beat_time = chart.offset + event.beat_number * beat_interval

		var lines_count := measure_lines.size()
		var beats_per_line := BEATS_PER_MEASURE / float(lines_count)
		for i in range(lines_count):
			var line := String(measure_lines[i])
			var beat_in_measure := float(i) * beats_per_line
			var warning_beat := float(measure) * BEATS_PER_MEASURE + beat_in_measure
			var fire_beat := warning_beat + BEATS_PER_MEASURE

			for slot_idx in range(min(4, line.length())):
				if _is_active_note_char(line.substr(slot_idx, 1)):
					event.add_warning_step(warning_beat, chart.offset + warning_beat * beat_interval, slot_idx)
					event.add_fire_step(fire_beat, chart.offset + fire_beat * beat_interval, slot_idx)

		if not event.warning_steps.is_empty():
			event.sort_steps()
			chart.call("add_laser_pattern", event)


static func _parse_laser_chord_layer(section: Dictionary, chart: Chart) -> void:
	var measures := _collect_measures(String(section["body"]))
	var beat_interval := 60.0 / chart.bpm
	var source_layer := _get_source_layer_name(section, "LaserChord")

	for measure in range(measures.size()):
		var measure_lines: Array = measures[measure]
		if measure_lines.is_empty():
			continue

		var lines_count := measure_lines.size()
		var beats_per_line := BEATS_PER_MEASURE / float(lines_count)
		var next_measure_start := (float(measure) + 1.0) * BEATS_PER_MEASURE

		for i in range(lines_count):
			var line := String(measure_lines[i])
			var slots := _get_active_slots(line)
			if slots.is_empty():
				continue

			var warning_beat := float(measure) * BEATS_PER_MEASURE + float(i) * beats_per_line
			var event: Resource = LaserPatternEventScript.new()
			event.kind = LaserPatternEventScript.PatternKind.CHORD
			event.source_layer = source_layer
			event.beat_number = warning_beat
			event.beat_time = chart.offset + warning_beat * beat_interval

			for slot_idx in slots:
				event.add_warning_step(warning_beat, chart.offset + warning_beat * beat_interval, slot_idx)
				var fire_beat := next_measure_start + float(slot_idx)
				event.add_fire_step(fire_beat, chart.offset + fire_beat * beat_interval, slot_idx)

			event.sort_steps()
			chart.call("add_laser_pattern", event)


static func _get_source_layer_name(section: Dictionary, fallback: String) -> String:
	var description := String(section.get("description", ""))
	if not description.is_empty():
		return description
	var chart_difficulty := String(section.get("difficulty", ""))
	if not chart_difficulty.is_empty():
		return chart_difficulty
	return fallback


static func _collect_measures(notes_data: String) -> Array:
	var measures: Array = []
	var measure_lines: Array[String] = []
	var lines := notes_data.split("\n")

	for line in lines:
		var trimmed := String(line).strip_edges()
		if trimmed.is_empty():
			continue

		if trimmed == "," or trimmed == ";":
			measures.append(measure_lines.duplicate())
			measure_lines.clear()
		elif _is_note_row(trimmed):
			measure_lines.append(trimmed)

	if not measure_lines.is_empty():
		measures.append(measure_lines.duplicate())

	return measures


static func _get_active_slots(line: String) -> Array[int]:
	var slots: Array[int] = []
	for slot_idx in range(min(4, line.length())):
		if _is_active_note_char(line.substr(slot_idx, 1)):
			slots.append(slot_idx)
	return slots


static func _is_note_row(line: String) -> bool:
	if line.length() < 4:
		return false
	for i in range(min(4, line.length())):
		if not _is_sm_note_char(line.substr(i, 1)):
			return false
	return true


static func _is_sm_note_char(note_char: String) -> bool:
	return note_char == "0" or note_char == "1" or note_char == "2" or note_char == "3" or note_char == "4" or note_char == "M" or note_char == "F"


static func _is_active_note_char(note_char: String) -> bool:
	return note_char == "1" or note_char == "2" or note_char == "4"
