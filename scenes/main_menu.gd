# === 本次任务：专业化美化 UI 主菜单 ===
extends Control
class_name MainMenu

# === 导出变量，可以在编辑器中修改 ===
@export_file("*.tscn") var game_scene_path: String = "res://scenes/Main.tscn"
@export var background_texture: Texture2D

func _ready() -> void:
	# 确保根节点撑满全屏、并随窗口缩放
	set_anchors_preset(PRESET_FULL_RECT)
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	
	# === 1. 构建全屏背景 ===
	var bg_rect = TextureRect.new()
	bg_rect.name = "Background"
	bg_rect.set_anchors_preset(PRESET_FULL_RECT)
	bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	
	# 跟随全屏
	bg_rect.custom_minimum_size = get_viewport_rect().size
	bg_rect.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	if background_texture:
		bg_rect.texture = background_texture
	add_child(bg_rect)
	
	# 让根节点调整时也更新背景（自适应拉伸窗口）
	resized.connect(func(): 
		if bg_rect: bg_rect.custom_minimum_size = self.size
	)

	# === 2. 居中对齐容器 ===
	var center_container = CenterContainer.new()
	center_container.name = "CenterContainer"
	center_container.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center_container)

	# === 3. 垂直排列容器 ===
	var vbox = VBoxContainer.new()
	vbox.name = "VBoxContainer"
	vbox.add_theme_constant_override("separation", 20) # 按钮间距微调，避免过大被遮挡
	center_container.add_child(vbox)

	# === 4. 生成按钮 ===
	_create_menu_button(vbox, "New Game", _on_new_game_pressed)
	_create_menu_button(vbox, "Guide", _on_guide_pressed)
	_create_menu_button(vbox, "Settings", _on_options_pressed)
	_create_menu_button(vbox, "Quit", _on_quit_pressed)


# === 核心 UI 美化生成逻辑 ===
func _create_menu_button(parent: Control, btn_text: String, callable: Callable) -> void:
	var btn = Button.new()
	btn.text = btn_text
	btn.custom_minimum_size = Vector2(360, 65) # 稍微减小尺寸，防止小分辨率下超屏
	
	# 动态系统字体
	var sys_font = SystemFont.new()
	sys_font.font_names = PackedStringArray(["Montserrat", "Microsoft YaHei", "sans-serif"])
	sys_font.font_weight = 700 
	
	btn.add_theme_font_override("font", sys_font)
	btn.add_theme_font_size_override("font_size", 28) 
	btn.add_theme_color_override("font_color", Color.WHITE) 
	
	# 文字阴影
	btn.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	btn.add_theme_constant_override("shadow_offset_x", 2)
	btn.add_theme_constant_override("shadow_offset_y", 2)
	btn.add_theme_constant_override("shadow_outline_size", 1)

	# 样式盒 (StyleBoxFlat) 配置：黑透底，带16px圆角
	var normal_style = _create_button_style(Color(0, 0, 0, 0.45)) 
	var hover_style = _create_button_style(Color(0.2, 0.2, 0.2, 0.7)) 
	var pressed_style = _create_button_style(Color(0, 0, 0, 0.8)) 
	var focus_style = StyleBoxEmpty.new() # 去掉丑陋边框
	
	btn.add_theme_stylebox_override("normal", normal_style)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", pressed_style)
	btn.add_theme_stylebox_override("focus", focus_style)

	# 绑定点击
	btn.pressed.connect(callable)
	parent.add_child(btn)

func _create_button_style(bg_color: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_right = 16
	style.corner_radius_bottom_left = 16
	return style

func _on_new_game_pressed() -> void:
	if game_scene_path != "":
		get_tree().change_scene_to_file(game_scene_path)

func _on_guide_pressed() -> void:
	print("Welcome to Music Is Life!")

func _on_options_pressed() -> void:
	print("Settings Menu")

func _on_quit_pressed() -> void:
	get_tree().quit()
