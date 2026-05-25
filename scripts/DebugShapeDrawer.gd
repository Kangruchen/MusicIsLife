extends RefCounted


static func draw_shape(
	canvas: CanvasItem,
	canvas_global_transform: Transform2D,
	global_xform: Transform2D,
	shape: Shape2D,
	color: Color,
	fill_alpha: float,
	line_width: float
) -> void:
	if canvas == null or shape == null:
		return

	var local_xform: Transform2D = canvas_global_transform.affine_inverse() * global_xform

	if shape is RectangleShape2D:
		_draw_rectangle(canvas, local_xform, shape as RectangleShape2D, color, fill_alpha, line_width)
		return

	if shape is CircleShape2D:
		_draw_circle(canvas, local_xform, shape as CircleShape2D, color, fill_alpha, line_width)


static func _draw_rectangle(
	canvas: CanvasItem,
	local_xform: Transform2D,
	rect_shape: RectangleShape2D,
	color: Color,
	fill_alpha: float,
	line_width: float
) -> void:
	var half: Vector2 = rect_shape.size * 0.5
	var points: PackedVector2Array = PackedVector2Array([
		local_xform * Vector2(-half.x, -half.y),
		local_xform * Vector2(half.x, -half.y),
		local_xform * Vector2(half.x, half.y),
		local_xform * Vector2(-half.x, half.y)
	])
	canvas.draw_colored_polygon(points, Color(color.r, color.g, color.b, fill_alpha))
	var outline: PackedVector2Array = PackedVector2Array([points[0], points[1], points[2], points[3], points[0]])
	canvas.draw_polyline(outline, color, line_width, true)


static func _draw_circle(
	canvas: CanvasItem,
	local_xform: Transform2D,
	circle_shape: CircleShape2D,
	color: Color,
	fill_alpha: float,
	line_width: float
) -> void:
	var radius_scale: float = maxf(local_xform.x.length(), local_xform.y.length())
	var center: Vector2 = local_xform.origin
	var radius: float = circle_shape.radius * radius_scale
	canvas.draw_circle(center, radius, Color(color.r, color.g, color.b, fill_alpha))
	canvas.draw_arc(center, radius, 0.0, TAU, 48, color, line_width, true)
