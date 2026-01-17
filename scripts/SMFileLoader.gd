extends Node
class_name SMFileLoader
## StepMania .sm 文件加载器 - 将 .sm 格式转换为 Chart


## 从 .sm 文件加载铺面
static func load_from_sm(sm_path: String, difficulty: String = "") -> Chart:
	var file := FileAccess.open(sm_path, FileAccess.READ)
	if not file:
		push_error("无法打开 .sm 文件: ", sm_path)
		return null
	
	var content := file.get_as_text()
	file.close()
	
	var chart := Chart.new()
	
	# 解析基础信息
	chart.chart_name = _extract_tag(content, "TITLE")
	var artist := _extract_tag(content, "ARTIST")
	if artist:
		chart.chart_name += " - " + artist
	
	chart.music_path = "res://music/" + _extract_tag(content, "MUSIC")
	
	# 解析 BPM（只取第一个 BPM 值，暂不支持变速）
	var bpms_str := _extract_tag(content, "BPMS")
	chart.bpm = _parse_first_bpm(bpms_str)
	
	# 解析 OFFSET
	# StepMania offset: 负值 = 第一拍在音频开始后，正值 = 第一拍在音频开始前
	# 我们直接使用绝对值，因为负的 offset 在我们系统中表示提前（不常用）
	var offset_str := _extract_tag(content, "OFFSET")
	var sm_offset := offset_str.to_float()
	# 取绝对值，确保第一拍总是在音频开始后
	chart.offset = abs(sm_offset)
	
	# 解析音符数据
	var notes_data := _extract_notes_section(content, difficulty)
	if notes_data:
		_parse_notes(notes_data, chart)
	
	print("从 .sm 文件加载铺面成功: ", chart.chart_name, "，共 ", chart.notes.size(), " 个音符")
	return chart


## 提取标签值
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


## 解析第一个 BPM 值
static func _parse_first_bpm(bpms_str: String) -> float:
	# 格式: "0.000=120.000,..." 取第一个 BPM
	var parts := bpms_str.split("=")
	if parts.size() < 2:
		return 120.0
	
	var bpm_part := parts[1].split(",")[0]
	return bpm_part.to_float()


## 提取 NOTES 区段
static func _extract_notes_section(content: String, difficulty: String) -> String:
	var sections := content.split("#NOTES:")
	
	# 如果没有指定难度，返回第一个 NOTES 区段
	if difficulty.is_empty() and sections.size() > 1:
		var end_idx := sections[1].find("#", 1)
		if end_idx == -1:
			return sections[1]
		return sections[1].substr(0, end_idx)
	
	# 搜索匹配的难度
	for i in range(1, sections.size()):
		if difficulty and sections[i].to_lower().contains(difficulty.to_lower()):
			var end_idx := sections[i].find("#", 1)
			if end_idx == -1:
				return sections[i]
			return sections[i].substr(0, end_idx)
	
	# 默认返回第一个
	if sections.size() > 1:
		var end_idx := sections[1].find("#", 1)
		if end_idx == -1:
			return sections[1]
		return sections[1].substr(0, end_idx)
	
	return ""


## 解析音符数据
static func _parse_notes(notes_data: String, chart: Chart) -> void:
	var lines := notes_data.split("\n")
	var in_notes := false
	var measure := 0
	var measure_lines: Array[String] = []
	var beat_interval := 60.0 / chart.bpm
	
	for line in lines:
		var trimmed := line.strip_edges()
		
		# 跳过前面的元数据行（用冒号分隔）
		if not in_notes:
			if trimmed.contains(":"):
				continue
			elif trimmed.length() > 0 and (trimmed[0] in ["0", "1", "2", "3", "4"]):
				in_notes = true
			else:
				continue
		
		# 处理音符行
		if trimmed == "," or trimmed == ";":
			# 小节结束
			if measure_lines.size() > 0:
				_process_measure(measure_lines, measure, chart, beat_interval)
				measure += 1
				measure_lines.clear()
		elif trimmed.length() >= 4:
			measure_lines.append(trimmed)
	
	# 处理最后一个小节
	if measure_lines.size() > 0:
		_process_measure(measure_lines, measure, chart, beat_interval)
	
	chart.sort_notes()


## 处理一个小节的音符
static func _process_measure(measure_lines: Array[String], measure: int, chart: Chart, beat_interval: float) -> void:
	var lines_count := measure_lines.size()
	var beats_per_line := 4.0 / lines_count  # 每行代表多少拍
	
	for i in range(lines_count):
		var line := measure_lines[i]
		if line.length() < 4:
			continue
		
		# StepMania 格式: LDUR (左、下、上、右)
		# 我们映射为: L/D=HIT, U=GUARD, R=DODGE
		var beat_in_measure := i * beats_per_line
		var total_beats := measure * 4 + beat_in_measure
		var beat_time := chart.offset + total_beats * beat_interval
		
		# 检查每个轨道
		for track_idx in range(min(4, line.length())):
			var note_char := line[track_idx]
			if note_char == "1" or note_char == "2" or note_char == "4":  # 1=普通, 2=hold头, 4=roll
				var note := Note.new()
				note.beat_number = total_beats  # 保留浮点精度，支持半拍、三连音等
				note.beat_time = beat_time
				
				# 映射轨道到音符类型
				match track_idx:
					0, 1:  # 左、下 -> HIT
						note.type = Note.NoteType.HIT
					2:     # 上 -> GUARD
						note.type = Note.NoteType.GUARD
					3:     # 右 -> DODGE
						note.type = Note.NoteType.DODGE
				
				chart.add_note(note)
