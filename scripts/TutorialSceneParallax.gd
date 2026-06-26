extends Node2D

const RhythmClock := preload("res://scripts/RhythmClock.gd")

@export var camera_path: NodePath = NodePath("../Player/Camera2D")
@export var background_path: NodePath = NodePath("Background")
@export var machine_path: NodePath = NodePath("Machine")
@export var fan_path: NodePath = NodePath("Fan")
@export var music_player_path: NodePath = NodePath("../GameManager/MusicPlayer")
@export var beat_manager_path: NodePath = NodePath("../GameManager/BeatManager")

@export_range(0.0, 1.0, 0.01) var background_camera_follow_x: float = 0.93
@export_range(0.0, 1.0, 0.01) var background_camera_follow_y: float = 0.0
@export_range(0.0, 1.0, 0.01) var machine_camera_follow_x: float = 0.85
@export_range(0.0, 1.0, 0.01) var machine_camera_follow_y: float = 0.0
@export var fan_spin_speed: float = 3.6
@export var hide_original_fan_layer: bool = true
@export_node_path("Sprite2D") var warn_light_path: NodePath = NodePath("WarnLight")
@export_range(0.0, 1.0, 0.01) var warn_light_dark_alpha: float = 0.0
@export_range(0.0, 1.0, 0.01) var warn_light_lit_alpha: float = 1.0
@export_range(0.01, 0.45, 0.01) var warn_light_fade_ratio: float = 0.12
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
var _warn_light: Sprite2D = null
var _music_player: Node = null
var _beat_manager: Node = null
var _warn_light_base_modulate: Color = Color.WHITE
var _warn_light_tween: Tween = null
var _warn_light_elapsed: float = 0.0
var _warn_light_last_beat_index: int = -1


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
	_setup_warn_light()


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

	_process_warn_light(delta)


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


func _setup_warn_light() -> void:
	_warn_light = get_node_or_null(warn_light_path) as Sprite2D
	if _warn_light == null:
		return

	_music_player = get_node_or_null(music_player_path)
	_beat_manager = get_node_or_null(beat_manager_path)
	_warn_light_base_modulate = _warn_light.self_modulate
	_set_warn_light_alpha(warn_light_dark_alpha)


func _process_warn_light(delta: float) -> void:
	if _warn_light == null or not is_instance_valid(_warn_light):
		return

	var beat_interval: float = EventBus.beat_interval
	if beat_interval <= 0.0:
		return

	var clock_time: float = _get_warn_light_clock_time(delta)
	var beat_zero_time: float = _get_warn_light_beat_zero_time()
	var beat_index: int = int(floor((clock_time - beat_zero_time) / beat_interval))
	if beat_index < 0 or beat_index == _warn_light_last_beat_index:
		return

	_warn_light_last_beat_index = beat_index
	var target_alpha: float = warn_light_lit_alpha if beat_index % 2 == 0 else warn_light_dark_alpha
	var fade_seconds: float = 0.06
	fade_seconds = clampf(beat_interval * warn_light_fade_ratio, 0.03, beat_interval * 0.45)

	if _warn_light_tween:
		_warn_light_tween.kill()
	_warn_light_tween = create_tween()
	_warn_light_tween.set_ease(Tween.EASE_OUT)
	_warn_light_tween.set_trans(Tween.TRANS_SINE)
	_warn_light_tween.tween_property(
		_warn_light,
		"self_modulate:a",
		_warn_light_base_modulate.a * target_alpha,
		fade_seconds
	)


func _get_warn_light_clock_time(delta: float) -> float:
	if _music_player == null or not is_instance_valid(_music_player):
		_music_player = get_node_or_null(music_player_path)
	if _music_player != null:
		return RhythmClock.get_music_time(_music_player)

	_warn_light_elapsed += delta
	return _warn_light_elapsed


func _get_warn_light_beat_zero_time() -> float:
	if _beat_manager == null or not is_instance_valid(_beat_manager):
		_beat_manager = get_node_or_null(beat_manager_path)
	if _beat_manager == null:
		return 0.0
	return float(_beat_manager.offset)


func _set_warn_light_alpha(alpha: float) -> void:
	if _warn_light == null:
		return
	var modulate_color: Color = _warn_light_base_modulate
	modulate_color.a = _warn_light_base_modulate.a * alpha
	_warn_light.self_modulate = modulate_color


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
