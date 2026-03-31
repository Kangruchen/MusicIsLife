extends Button

func _ready():
    # 初始状态：白色加黑边
    add_theme_color_override("font_outline_color", Color.BLACK)
    add_theme_constant_override("outline_size", 4)

func _on_mouse_entered():
    # 悬停：字体变黄，并利用 Tween 稍微放大 1.1 倍
    var t = create_tween()
    t.tween_property(self, "scale", Vector2(1.1, 1.1), 0.1).set_trans(Tween.TRANS_BACK)
    add_theme_color_override("font_color", Color("#FFCC00"))

func _on_mouse_exited():
    # 恢复原状
    var t = create_tween()
    t.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)
    remove_theme_color_override("font_color")

    # 制作一个呼吸脉冲动画
    var tween = create_tween().set_loops()
    tween.tween_property(self, "theme_override_constants/outline_size", 8, 0.5)
    tween.tween_property(self, "theme_override_constants/outline_size", 4, 0.5)