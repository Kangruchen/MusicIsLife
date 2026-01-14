extends Node
class_name ChartLoader
## 铺面加载器 - 从不同格式加载铺面数据


## 从 JSON 文件加载铺面
static func load_from_json(json_path: String) -> Chart:
	var file := FileAccess.open(json_path, FileAccess.READ)
	if not file:
		push_error("无法打开 JSON 文件: ", json_path)
		return null
	
	var json_string := file.get_as_text()
	file.close()
	
	var json := JSON.new()
	var error := json.parse(json_string)
	if error != OK:
		push_error("JSON 解析错误: ", json.get_error_message(), " at line ", json.get_error_line())
		return null
	
	var data: Dictionary = json.data
	
	# 创建 Chart 对象
	var chart := Chart.new()
	chart.chart_name = data.get("chart_name", "")
	chart.music_path = data.get("music_path", "")
	chart.bpm = data.get("bpm", 120.0)
	chart.offset = data.get("offset", 0.0)
	
	# 解析音符数据
	var notes_data: Array = data.get("notes", [])
	var beat_interval := 60.0 / chart.bpm
	
	for note_data in notes_data:
		if note_data is Dictionary:
			var note := Note.new()
			note.beat_number = float(note_data.get("beat", 0.0))  # 确保为浮点数，支持半拍、三连音等
			note.beat_time = chart.offset + note.beat_number * beat_interval
			
			# 解析音符类型
			var note_type_str: String = note_data.get("type", "HIT")
			note.type = _parse_note_type(note_type_str)
			
			chart.add_note(note)
	
	chart.sort_notes()
	print("从 JSON 加载铺面成功: ", chart.chart_name, "，共 ", chart.notes.size(), " 个音符")
	return chart


## 解析音符类型字符串
static func _parse_note_type(note_type_str: String) -> Note.NoteType:
	match note_type_str.to_upper():
		"HIT":
			return Note.NoteType.HIT
		"GUARD":
			return Note.NoteType.GUARD
		"DODGE":
			return Note.NoteType.DODGE
		_:
			push_warning("未知的音符类型: ", note_type_str, "，使用默认值 HIT")
			return Note.NoteType.HIT


## 导出铺面为 JSON（可选功能）
static func save_to_json(chart: Chart, json_path: String) -> bool:
	var data := {
		"chart_name": chart.chart_name,
		"music_path": chart.music_path,
		"bpm": chart.bpm,
		"offset": chart.offset,
		"notes": []
	}
	
	for note in chart.notes:
		data.notes.append({
			"beat": note.beat_number,
			"type": note.get_type_string()
		})
	
	var json_string := JSON.stringify(data, "\t")
	var file := FileAccess.open(json_path, FileAccess.WRITE)
	if not file:
		push_error("无法写入 JSON 文件: ", json_path)
		return false
	
	file.store_string(json_string)
	file.close()
	print("铺面已保存到 JSON: ", json_path)
	return true
