extends Node2D

@onready var rect: ColorRect = $ColorRect

func _ready() -> void:
	# 初始隐藏
	rect.visible = false

func start(color: Color, duration: float = 0.4) -> void:
	if rect == null:
		return
	rect.visible = true
	# 设置 shader 参数（颜色）
	if rect.material != null:
		var mat = rect.material as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("glow_color", color)
	# 初始规模
	self.scale = Vector2.ONE * 0.7
	rect.modulate = Color(1, 1, 1, 1)
	# 动画：scale 放大并淡出
	var tw = create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2.ONE * 1.3, duration)
	tw.tween_property(rect, "modulate:a", 0.0, duration)
	tw.finished.connect(func() -> void:
		if is_inside_tree():
			queue_free()
	)
