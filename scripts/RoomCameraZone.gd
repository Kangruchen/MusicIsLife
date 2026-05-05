extends Area2D
class_name RoomCameraZone

@export var room_name: String = ""
@export var zoom: Vector2 = Vector2(0.6, 0.6)
@export var transition_duration: float = 0.5
@export var transition_ease: Tween.EaseType = Tween.EASE_IN_OUT
@export var transition_trans: Tween.TransitionType = Tween.TRANS_SINE
@export var lock_player_in_room: bool = false

var _camera: Camera2D = null
var _tween: Tween = null
var _player: CharacterBody2D = null
var _room_rect: Rect2 = Rect2()
var _is_active: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_calculate_room_rect()


func _calculate_room_rect() -> void:
	for child in get_children():
		var cs: CollisionShape2D = child as CollisionShape2D
		if cs and cs.shape:
			var room_rect: Rect2 = rect2_from_shape(cs)
			if room_rect != Rect2():
				_room_rect = room_rect
				return


func rect2_from_shape(cs: CollisionShape2D) -> Rect2:
	var shape: Shape2D = cs.shape
	var rect_shape := shape as RectangleShape2D
	if rect_shape == null:
		return Rect2()
	var center: Vector2 = global_position + cs.position
	var half_size: Vector2 = rect_shape.size * 0.5
	return Rect2(center - half_size, rect_shape.size)


func _on_body_entered(body: Node2D) -> void:
	if body.name != "Player":
		return
	_player = body as CharacterBody2D
	_camera = _get_camera()
	if _camera == null:
		return
	_is_active = true
	_apply_room_camera()


func _on_body_exited(body: Node2D) -> void:
	if body.name != "Player":
		return
	if body == _player:
		_is_active = false


func _get_camera() -> Camera2D:
	if _camera != null and is_instance_valid(_camera):
		return _camera
	if _player:
		var cam: Camera2D = _player.find_child("Camera2D", true, false) as Camera2D
		if cam:
			return cam
	return get_viewport().get_camera_2d()


func _apply_room_camera() -> void:
	if _camera == null:
		return

	_camera.limit_left = int(_room_rect.position.x)
	_camera.limit_top = int(_room_rect.position.y)
	_camera.limit_right = int(_room_rect.end.x)
	_camera.limit_bottom = int(_room_rect.end.y)

	if _tween:
		_tween.kill()
	_tween = create_tween().set_ease(transition_ease).set_trans(transition_trans)
	_tween.tween_property(_camera, "zoom", zoom, transition_duration)


func get_room_rect() -> Rect2:
	return _room_rect


func is_active() -> bool:
	return _is_active
