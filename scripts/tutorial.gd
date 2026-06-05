extends Node2D

@export_file("*.tscn") var main_menu_scene_path: String = "res://scenes/main_menu.tscn"

@export_group("Elevator Areas")
@export var player: CharacterBody2D
@export var door_proximity_area: Area2D
@export var level_end_area: Area2D

@export_group("Exit Elevator Visuals")
@export var left_door: Sprite2D
@export var right_door: Sprite2D
@export var left_door_open_dist: float = 64.0
@export var right_door_open_dist: float = 64.0
@export var mask_left_bound: Marker2D
@export var mask_right_bound: Marker2D

@export_group("Intro Elevator Visuals")
@export var intro_left_door: Sprite2D
@export var intro_right_door: Sprite2D
@export var intro_left_door_open_dist: float = 64.0
@export var intro_right_door_open_dist: float = 64.0
@export var intro_mask_left_bound: Marker2D
@export var intro_mask_right_bound: Marker2D

@export_group("Intro Cutscene")
@export var play_intro_cutscene: bool = true
@export var intro_spawn_point: Marker2D
@export var intro_exit_point: Marker2D
@export var intro_proximity_shape: CollisionShape2D

@export_group("Player Animation")
@export var player_idle_anim: String = "Idle"

var _is_ending_tutorial: bool = false
var _is_waiting_for_intro_exit: bool = false
var _door_tween: Tween
var _intro_door_tween: Tween
var _left_door_closed_x: float = 0.0
var _right_door_closed_x: float = 0.0
var _intro_left_door_closed_x: float = 0.0
var _intro_right_door_closed_x: float = 0.0
var _intro_left_door_original_z: int = 0
var _intro_right_door_original_z: int = 0


func _ready() -> void:
	if left_door and right_door:
		_left_door_closed_x = left_door.position.x
		_right_door_closed_x = right_door.position.x
		left_door_open_dist = _get_door_open_distance(left_door, left_door_open_dist)
		right_door_open_dist = _get_door_open_distance(right_door, right_door_open_dist)
		_setup_door_mask(left_door, right_door, mask_left_bound, mask_right_bound)

	if intro_left_door and intro_right_door:
		_intro_left_door_closed_x = intro_left_door.position.x
		_intro_right_door_closed_x = intro_right_door.position.x
		_intro_left_door_original_z = intro_left_door.z_index
		_intro_right_door_original_z = intro_right_door.z_index
		intro_left_door_open_dist = _get_door_open_distance(intro_left_door, intro_left_door_open_dist)
		intro_right_door_open_dist = _get_door_open_distance(intro_right_door, intro_right_door_open_dist)
		_setup_door_mask(intro_left_door, intro_right_door, intro_mask_left_bound, intro_mask_right_bound)

	if door_proximity_area:
		door_proximity_area.body_entered.connect(_on_door_proximity_entered)
		door_proximity_area.body_exited.connect(_on_door_proximity_exited)

	if level_end_area:
		level_end_area.body_entered.connect(_on_level_end_entered)

	if play_intro_cutscene:
		_start_intro_from_open_elevator()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		get_tree().change_scene_to_file(main_menu_scene_path)


func _get_door_open_distance(door: Sprite2D, fallback: float) -> float:
	if door == null or door.texture == null:
		return fallback
	return door.get_rect().size.x * absf(door.scale.x)


func _setup_door_mask(
	left: Sprite2D,
	right: Sprite2D,
	left_bound: Marker2D,
	right_bound: Marker2D
) -> void:
	if left == null or right == null:
		return
	if left_bound == null or right_bound == null:
		push_warning("Elevator door mask markers are not assigned.")
		return

	var shader: Shader = Shader.new()
	shader.code = """
	shader_type canvas_item;
	varying float world_x;
	uniform float clip_left;
	uniform float clip_right;

	void vertex() {
		world_x = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).x;
	}

	void fragment() {
		if (world_x < clip_left || world_x > clip_right) {
			COLOR.a = 0.0;
		}
	}
	"""

	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("clip_left", left_bound.global_position.x)
	mat.set_shader_parameter("clip_right", right_bound.global_position.x)

	left.material = mat
	right.material = mat


func _on_door_proximity_entered(body: Node2D) -> void:
	if body.name == "Player" and not _is_ending_tutorial and not _is_waiting_for_intro_exit:
		_open_doors()


func _on_door_proximity_exited(body: Node2D) -> void:
	if body.name != "Player" or _is_ending_tutorial:
		return

	if _is_waiting_for_intro_exit:
		_is_waiting_for_intro_exit = false
		_disable_intro_proximity_shape()
		_close_intro_doors()
		return

	if not _is_waiting_for_intro_exit:
		_close_doors()


func _on_level_end_entered(body: Node2D) -> void:
	if body.name == "Player" and not _is_ending_tutorial:
		_play_outro_cutscene()


func _open_doors() -> void:
	if not left_door or not right_door:
		return
	if _door_tween and _door_tween.is_running():
		_door_tween.kill()

	_door_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_door_tween.tween_property(left_door, "position:x", _left_door_closed_x - left_door_open_dist, 0.5)
	_door_tween.tween_property(right_door, "position:x", _right_door_closed_x + right_door_open_dist, 0.5)


func _close_doors() -> void:
	if not left_door or not right_door:
		return
	if _door_tween and _door_tween.is_running():
		_door_tween.kill()

	_door_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_door_tween.tween_property(left_door, "position:x", _left_door_closed_x, 0.5)
	_door_tween.tween_property(right_door, "position:x", _right_door_closed_x, 0.5)


func _set_intro_doors_open() -> void:
	if intro_left_door == null or intro_right_door == null:
		return
	if _intro_door_tween and _intro_door_tween.is_running():
		_intro_door_tween.kill()

	intro_left_door.position.x = _intro_left_door_closed_x - intro_left_door_open_dist
	intro_right_door.position.x = _intro_right_door_closed_x + intro_right_door_open_dist


func _close_intro_doors() -> void:
	if intro_left_door == null or intro_right_door == null:
		return
	if _intro_door_tween and _intro_door_tween.is_running():
		_intro_door_tween.kill()

	_intro_door_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_intro_door_tween.tween_property(intro_left_door, "position:x", _intro_left_door_closed_x, 0.5)
	_intro_door_tween.tween_property(intro_right_door, "position:x", _intro_right_door_closed_x, 0.5)


func _start_intro_from_open_elevator() -> void:
	if player == null or intro_spawn_point == null:
		return

	_is_waiting_for_intro_exit = true
	_enable_intro_proximity_shape()
	_set_intro_doors_open()
	_restore_intro_door_depth()

	player.velocity = Vector2.ZERO
	player.global_position = intro_spawn_point.global_position
	_play_player_anim(player_idle_anim)


func _restore_intro_door_depth() -> void:
	if intro_left_door:
		intro_left_door.z_index = _intro_left_door_original_z
	if intro_right_door:
		intro_right_door.z_index = _intro_right_door_original_z


func _enable_intro_proximity_shape() -> void:
	if intro_proximity_shape:
		intro_proximity_shape.set_deferred("disabled", false)


func _disable_intro_proximity_shape() -> void:
	if intro_proximity_shape:
		intro_proximity_shape.set_deferred("disabled", true)


func _play_player_anim(anim_name: String) -> void:
	var animated_sprite: AnimatedSprite2D = player.get_node_or_null("CharacterVisual/AnimatedSprite2D") as AnimatedSprite2D
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return
	if not animated_sprite.sprite_frames.has_animation(anim_name):
		return
	animated_sprite.play(anim_name)


func _play_outro_cutscene() -> void:
	_is_ending_tutorial = true

	if player:
		player.velocity = Vector2.ZERO
		_enforce_absolute_idle(player)
		_clear_player_trails(player)

	if left_door and right_door:
		left_door.z_index = 10
		right_door.z_index = 10

	_close_doors()

	if _door_tween:
		await _door_tween.finished

	await get_tree().create_timer(1.5).timeout
	get_tree().change_scene_to_file(main_menu_scene_path)


func _enforce_absolute_idle(node: Node) -> void:
	node.set_physics_process(false)
	node.set_process(false)

	if node is AnimatedSprite2D:
		node.play(player_idle_anim)
		node.set_frame_and_progress(0, 0.0)
		node.pause()
	elif node is AnimationPlayer:
		if node.has_animation(player_idle_anim):
			node.play(player_idle_anim)
			node.seek(0.0, true)
			node.pause()
	elif node.has_method("set_active"):
		node.set("active", false)

	for child: Node in node.get_children():
		_enforce_absolute_idle(child)


func _clear_player_trails(node: Node) -> void:
	for child: Node in node.get_children():
		if child is GPUParticles2D or child is CPUParticles2D:
			child.emitting = false
			child.visible = false
		elif child.get_class() == "Trail2D":
			if child.has_method("clear_points"):
				child.call("clear_points")
			child.visible = false

		_clear_player_trails(child)
