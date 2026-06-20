extends Node2D

@export var camera_path: NodePath = NodePath("../Player/Camera2D")
@export var background_path: NodePath = NodePath("Background")
@export var machine_path: NodePath = NodePath("Machine")
@export var fan_path: NodePath = NodePath("Fan")

@export_range(0.0, 1.0, 0.01) var background_camera_follow_x: float = 0.93
@export_range(0.0, 1.0, 0.01) var background_camera_follow_y: float = 0.0
@export_range(0.0, 1.0, 0.01) var machine_camera_follow_x: float = 0.85
@export_range(0.0, 1.0, 0.01) var machine_camera_follow_y: float = 0.0
@export var fan_spin_speed: float = 3.6
@export var hide_original_fan_layer: bool = true
@export var fan_rotor_regions: Array[Rect2] = [
	Rect2(1036, 190, 44, 44),
	Rect2(1036, 246, 44, 44),
	Rect2(1036, 302, 44, 44),
	Rect2(3130, 247, 128, 132),
]

var _camera: Camera2D = null
var _camera_origin: Vector2 = Vector2.ZERO
var _background: Node2D = null
var _machine: Node2D = null
var _fan: Sprite2D = null
var _background_origin: Vector2 = Vector2.ZERO
var _machine_origin: Vector2 = Vector2.ZERO
var _fan_rotors: Array[Node2D] = []


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as Camera2D
	if _camera == null:
		_camera = get_viewport().get_camera_2d()
	if _camera != null:
		_camera_origin = _get_camera_center()

	_background = get_node_or_null(background_path) as Node2D
	_machine = get_node_or_null(machine_path) as Node2D
	_fan = get_node_or_null(fan_path) as Sprite2D

	if _background != null:
		_background_origin = _background.position
	if _machine != null:
		_machine_origin = _machine.position
	_setup_fan_rotors()


func _process(delta: float) -> void:
	if _camera != null:
		var camera_offset: Vector2 = _get_camera_center() - _camera_origin
		if _background != null:
			_background.position = _get_layer_position(
				_background_origin,
				camera_offset,
				Vector2(background_camera_follow_x, background_camera_follow_y)
			)
		if _machine != null:
			_machine.position = _get_layer_position(
				_machine_origin,
				camera_offset,
				Vector2(machine_camera_follow_x, machine_camera_follow_y)
			)

	for rotor in _fan_rotors:
		rotor.rotation += fan_spin_speed * delta


func _setup_fan_rotors() -> void:
	if _fan == null or _fan.texture == null:
		return

	var source_texture: Texture2D = _fan.texture
	var texture_size: Vector2 = source_texture.get_size()
	for child in _fan_rotors:
		child.queue_free()
	_fan_rotors.clear()

	for index in range(fan_rotor_regions.size()):
		var region: Rect2 = fan_rotor_regions[index]
		var pivot := Node2D.new()
		pivot.name = "FanRotor%d" % (index + 1)
		pivot.position = _texture_point_to_sprite_local(region.get_center(), texture_size)

		var blade := Sprite2D.new()
		blade.name = "Blades"
		blade.texture = source_texture
		blade.region_enabled = true
		blade.region_rect = region
		blade.centered = true
		blade.texture_filter = _fan.texture_filter

		pivot.add_child(blade)
		_fan.add_child(pivot)
		_fan_rotors.append(pivot)

	if hide_original_fan_layer:
		_fan.texture = null


func _texture_point_to_sprite_local(texture_point: Vector2, texture_size: Vector2) -> Vector2:
	var local_point: Vector2 = texture_point
	if _fan.centered:
		local_point -= texture_size * 0.5
	return local_point + _fan.offset


func _get_layer_position(origin: Vector2, camera_offset: Vector2, camera_follow: Vector2) -> Vector2:
	return origin + Vector2(
		camera_offset.x * camera_follow.x,
		camera_offset.y * camera_follow.y
	)


func _get_camera_center() -> Vector2:
	return _camera.get_screen_center_position()
