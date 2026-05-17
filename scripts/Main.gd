extends Node
## 主场景 - 处理场景切换和游戏流程

@onready var music_player: Node = $GameManager/MusicPlayer
@onready var camera: Camera2D = $Camera2D
@onready var player: Node2D = $Character

@export_group("Attack Camera")
@export var enable_attack_camera: bool = true
@export_range(1.0, 3.0, 0.05) var attack_camera_magnification: float = 1.8
@export var attack_camera_focus_offset: Vector2 = Vector2.ZERO
@export var attack_camera_keep_player_centered: bool = true
@export_range(0.0, 1.0, 0.01) var attack_camera_focus_weight: float = 0.35
@export_range(0.05, 1.0, 0.01) var attack_camera_enter_duration: float = 0.28
@export_range(0.05, 1.5, 0.01) var attack_camera_restore_duration: float = 0.35
@export_range(1.0, 20.0, 0.5) var attack_camera_follow_speed: float = 10.0

var _camera_default_global_position: Vector2 = Vector2.ZERO
var _camera_default_zoom: Vector2 = Vector2.ONE
var _camera_tween: Tween = null
var _attack_camera_active: bool = false
var _attack_zoom_target: Vector2 = Vector2.ONE
const CAMERA_POSITION_DEADZONE: float = 0.35


func _enter_tree() -> void:
	EventBus.boss_intro_completed = false


func _ready() -> void:
	if camera != null:
		_camera_default_global_position = camera.global_position
		_camera_default_zoom = camera.zoom

	if not EventBus.attack_movement_enabled_changed.is_connected(_on_attack_movement_enabled_changed):
		EventBus.attack_movement_enabled_changed.connect(_on_attack_movement_enabled_changed)
	if not EventBus.attack_phase_ended.is_connected(_on_attack_phase_ended):
		EventBus.attack_phase_ended.connect(_on_attack_phase_ended)
	if not EventBus.player_died.is_connected(_on_player_died):
		EventBus.player_died.connect(_on_player_died)


func _process(delta: float) -> void:
	if camera == null or player == null:
		return

	if not _attack_camera_active:
		return

	var safe_zoom: Vector2 = _clamp_zoom_to_default(camera.zoom)
	camera.zoom = safe_zoom

	var focus_target: Vector2 = _get_attack_camera_focus_target()
	var target_pos: Vector2 = _clamp_camera_position(focus_target, safe_zoom)
	var weight: float = clampf(delta * attack_camera_follow_speed, 0.0, 1.0)
	var blended_pos: Vector2 = camera.global_position.lerp(target_pos, weight)
	if blended_pos.distance_to(target_pos) <= CAMERA_POSITION_DEADZONE:
		blended_pos = target_pos
	camera.global_position = _clamp_camera_position(blended_pos, safe_zoom)


func _on_attack_movement_enabled_changed(enabled: bool) -> void:
	if not enable_attack_camera:
		return
	if camera == null or player == null:
		return

	if enabled:
		# 真正开放攻击输入时再切入攻击镜头，避免把前置缓冲也算进去。
		_attack_camera_active = true
		_attack_zoom_target = _get_attack_camera_zoom()
		var start_target_pos: Vector2 = _get_attack_camera_target_pos(_attack_zoom_target)
		_start_camera_tween(start_target_pos, _attack_zoom_target, attack_camera_enter_duration)


func _on_attack_phase_ended() -> void:
	if camera == null:
		return

	_attack_camera_active = false
	_start_camera_tween(_camera_default_global_position, _camera_default_zoom, attack_camera_restore_duration)


func _on_player_died() -> void:
	# 死亡演出期间关闭攻击镜头跟随，避免覆盖 Character 的死亡镜头控制。
	_attack_camera_active = false
	if _camera_tween != null:
		_camera_tween.kill()
		_camera_tween = null


func _start_camera_tween(target_pos: Vector2, target_zoom: Vector2, duration: float) -> void:
	if _camera_tween != null:
		_camera_tween.kill()
		_camera_tween = null

	var safe_zoom: Vector2 = _clamp_zoom_to_default(target_zoom)
	var safe_target_pos: Vector2 = _clamp_camera_position(target_pos, safe_zoom)
	var tween_duration: float = maxf(0.01, duration)
	_camera_tween = create_tween()
	_camera_tween.tween_property(camera, "global_position", safe_target_pos, tween_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_camera_tween.parallel().tween_property(camera, "zoom", safe_zoom, tween_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _build_default_camera_bound_rect() -> Rect2:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var half_size: Vector2 = Vector2(
		viewport_size.x / maxf(0.01, _camera_default_zoom.x) * 0.5,
		viewport_size.y / maxf(0.01, _camera_default_zoom.y) * 0.5
	)
	return Rect2(_camera_default_global_position - half_size, half_size * 2.0)


func _clamp_zoom_to_default(value: Vector2) -> Vector2:
	var safe_zoom: Vector2 = value
	safe_zoom.x = clampf(safe_zoom.x, _camera_default_zoom.x, _camera_default_zoom.x * 4.0)
	safe_zoom.y = clampf(safe_zoom.y, _camera_default_zoom.y, _camera_default_zoom.y * 4.0)
	return safe_zoom


func _get_attack_camera_zoom() -> Vector2:
	var magnification: float = maxf(1.0, attack_camera_magnification)
	return Vector2(_camera_default_zoom.x * magnification, _camera_default_zoom.y * magnification)


func _get_attack_camera_target_pos(zoom_value: Vector2) -> Vector2:
	var focus_target: Vector2 = _get_attack_camera_focus_target()
	return _clamp_camera_position(focus_target, zoom_value)


func _get_attack_camera_focus_target() -> Vector2:
	var raw_focus_target: Vector2 = player.global_position + attack_camera_focus_offset
	if attack_camera_keep_player_centered:
		return raw_focus_target
	return _camera_default_global_position.lerp(raw_focus_target, clampf(attack_camera_focus_weight, 0.0, 1.0))


func _clamp_camera_position(target_pos: Vector2, zoom_value: Vector2) -> Vector2:
	var bound_rect: Rect2 = _build_default_camera_bound_rect()
	if bound_rect.size.length_squared() <= 0.0:
		return target_pos

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var half_size: Vector2 = Vector2(
		viewport_size.x / maxf(0.01, zoom_value.x) * 0.5,
		viewport_size.y / maxf(0.01, zoom_value.y) * 0.5
	)

	var min_center: Vector2 = bound_rect.position + half_size
	var max_center: Vector2 = bound_rect.position + bound_rect.size - half_size

	var clamped_x: float
	if min_center.x > max_center.x:
		clamped_x = _camera_default_global_position.x
	else:
		clamped_x = clampf(target_pos.x, min_center.x, max_center.x)

	var clamped_y: float
	if min_center.y > max_center.y:
		clamped_y = _camera_default_global_position.y
	else:
		clamped_y = clampf(target_pos.y, min_center.y, max_center.y)

	return Vector2(clamped_x, clamped_y)


func _input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed("offset"):
		get_tree().change_scene_to_file("res://scenes/OffsetCalibration.tscn")
	elif event.is_action_pressed("restart"):
		get_tree().reload_current_scene()
