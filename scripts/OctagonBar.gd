extends Control
class_name OctagonBar

enum FillDirection {
	LEFT_TO_RIGHT,
	RIGHT_TO_LEFT,
}

@export var max_value: float = 100.0:
	set(new_value):
		max_value = maxf(new_value, 0.001)
		value = clampf(value, 0.0, max_value)
		queue_redraw()

@export var value: float = 100.0:
	set(new_value):
		value = clampf(new_value, 0.0, max_value)
		queue_redraw()

@export var fill_color: Color = Color(0.85, 0.1, 0.1, 1.0):
	set(new_value):
		fill_color = new_value
		queue_redraw()

@export var empty_color: Color = Color(0.05, 0.06, 0.07, 0.9):
	set(new_value):
		empty_color = new_value
		queue_redraw()

@export var border_color: Color = Color(0.01, 0.015, 0.02, 1.0):
	set(new_value):
		border_color = new_value
		queue_redraw()

@export var border_highlight_color: Color = Color(0.55, 0.62, 0.7, 1.0):
	set(new_value):
		border_highlight_color = new_value
		queue_redraw()

@export_range(1.0, 24.0, 0.5) var border_thickness: float = 5.0:
	set(new_value):
		border_thickness = new_value
		queue_redraw()

@export_range(0.0, 64.0, 0.5) var side_cut: float = 13.0:
	set(new_value):
		side_cut = new_value
		queue_redraw()

@export var fill_direction: FillDirection = FillDirection.LEFT_TO_RIGHT:
	set(new_value):
		fill_direction = new_value
		queue_redraw()


func _draw() -> void:
	if size.x <= 2.0 or size.y <= 2.0:
		return

	var outer_rect := Rect2(Vector2.ZERO, size)
	var outer_polygon := _make_octagon(outer_rect, side_cut)
	draw_colored_polygon(outer_polygon, border_highlight_color)

	var border_inset: float = minf(border_thickness, minf(size.x, size.y) * 0.45)
	var border_rect := outer_rect.grow(-border_inset * 0.45)
	draw_colored_polygon(_make_octagon(border_rect, maxf(side_cut - border_inset * 0.45, 0.0)), border_color)

	var inner_rect := outer_rect.grow(-border_inset)
	if inner_rect.size.x <= 0.0 or inner_rect.size.y <= 0.0:
		return

	var inner_polygon := _make_octagon(inner_rect, maxf(side_cut - border_inset, 0.0))
	draw_colored_polygon(inner_polygon, empty_color)

	var ratio: float = clampf(value / max_value, 0.0, 1.0)
	if ratio <= 0.0:
		return

	var fill_polygon: PackedVector2Array
	if fill_direction == FillDirection.RIGHT_TO_LEFT:
		var left_clip: float = inner_rect.position.x + inner_rect.size.x * (1.0 - ratio)
		fill_polygon = _clip_polygon_by_x(inner_polygon, left_clip, true)
	else:
		var right_clip: float = inner_rect.position.x + inner_rect.size.x * ratio
		fill_polygon = _clip_polygon_by_x(inner_polygon, right_clip, false)

	if fill_polygon.size() >= 3:
		draw_colored_polygon(fill_polygon, fill_color)


func _make_octagon(rect: Rect2, cut: float) -> PackedVector2Array:
	var clamped_cut: float = minf(cut, minf(rect.size.x, rect.size.y) * 0.5)
	var left: float = rect.position.x
	var top: float = rect.position.y
	var right: float = rect.position.x + rect.size.x
	var bottom: float = rect.position.y + rect.size.y

	return PackedVector2Array([
		Vector2(left + clamped_cut, top),
		Vector2(right - clamped_cut, top),
		Vector2(right, top + clamped_cut),
		Vector2(right, bottom - clamped_cut),
		Vector2(right - clamped_cut, bottom),
		Vector2(left + clamped_cut, bottom),
		Vector2(left, bottom - clamped_cut),
		Vector2(left, top + clamped_cut),
	])


func _clip_polygon_by_x(points: PackedVector2Array, clip_x: float, keep_right: bool) -> PackedVector2Array:
	var clipped := PackedVector2Array()
	if points.is_empty():
		return clipped

	var previous: Vector2 = points[points.size() - 1]
	var previous_inside: bool = _is_inside_x(previous, clip_x, keep_right)

	for current in points:
		var current_inside: bool = _is_inside_x(current, clip_x, keep_right)
		if current_inside:
			if not previous_inside:
				clipped.append(_intersect_x(previous, current, clip_x))
			clipped.append(current)
		elif previous_inside:
			clipped.append(_intersect_x(previous, current, clip_x))
		previous = current
		previous_inside = current_inside

	return clipped


func _is_inside_x(point: Vector2, clip_x: float, keep_right: bool) -> bool:
	if keep_right:
		return point.x >= clip_x
	return point.x <= clip_x


func _intersect_x(from: Vector2, to: Vector2, clip_x: float) -> Vector2:
	if is_equal_approx(from.x, to.x):
		return Vector2(clip_x, from.y)
	var t: float = (clip_x - from.x) / (to.x - from.x)
	return from.lerp(to, t)
