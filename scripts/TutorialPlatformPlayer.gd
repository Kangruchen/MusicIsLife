extends CharacterBody2D

@export_group("Movement")
@export var move_speed: float = 260.0

@export_group("Slope")
@export_range(1.0, 89.0, 0.1) var walkable_slope_angle_degrees: float = 45.0

@export_group("Input")
@export var move_action_left: StringName = &"move_left"
@export var move_action_right: StringName = &"move_right"
@export var drop_down_action: StringName = &"move_down"

@export_group("Drop Through")
@export_range(0.05, 0.5, 0.01) var drop_through_duration: float = 0.16
@export var drop_down_push_speed: float = 140.0

@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("CharacterVisual/AnimatedSprite2D") as AnimatedSprite2D

var _gravity: float = 980.0
var _drop_through_timer: float = 0.0
var _disabled_one_way_shapes: Array[CollisionShape2D] = []


func _ready() -> void:
	_gravity = ProjectSettings.get_setting("physics/2d/default_gravity") as float
	floor_max_angle = deg_to_rad(walkable_slope_angle_degrees)
	_play_idle()


func _physics_process(delta: float) -> void:
	_update_drop_through_timer(delta)

	if not is_on_floor():
		velocity.y += _gravity * delta
	else:
		velocity.y = 0.0

	if Input.is_action_just_pressed(drop_down_action):
		_try_start_drop_through_one_way()

	var input_axis: float = Input.get_action_strength(move_action_right) - Input.get_action_strength(move_action_left)
	velocity.x = input_axis * move_speed

	move_and_slide()
	_update_visual_animation(input_axis)
	_update_visual_facing()


func _update_drop_through_timer(delta: float) -> void:
	if _drop_through_timer <= 0.0:
		return

	_drop_through_timer -= delta
	if _drop_through_timer > 0.0:
		return

	for shape_node in _disabled_one_way_shapes:
		if shape_node != null and is_instance_valid(shape_node):
			shape_node.set_deferred("disabled", false)
	_disabled_one_way_shapes.clear()


func _try_start_drop_through_one_way() -> void:
	if not is_on_floor():
		return

	var one_way_shapes: Array[CollisionShape2D] = _find_current_floor_one_way_shapes()
	if one_way_shapes.is_empty():
		return

	for shape_node in _disabled_one_way_shapes:
		if shape_node != null and is_instance_valid(shape_node):
			shape_node.set_deferred("disabled", false)
	_disabled_one_way_shapes.clear()

	for shape_node in one_way_shapes:
		shape_node.set_deferred("disabled", true)
	_disabled_one_way_shapes = one_way_shapes
	_drop_through_timer = maxf(0.01, drop_through_duration)
	velocity.y = maxf(velocity.y, drop_down_push_speed)


func _find_current_floor_one_way_shapes() -> Array[CollisionShape2D]:
	for i: int in range(get_slide_collision_count()):
		var collision: KinematicCollision2D = get_slide_collision(i)
		if collision == null:
			continue

		# 与 up_direction 同向（默认向上）可视作地面碰撞。
		if collision.get_normal().dot(up_direction) < 0.6:
			continue

		var collider_obj: CollisionObject2D = collision.get_collider() as CollisionObject2D
		if collider_obj == null:
			continue

		var one_way_shapes: Array[CollisionShape2D] = _get_one_way_shapes_from_collider(collider_obj)
		if not one_way_shapes.is_empty():
			return one_way_shapes

	return []


func _get_one_way_shapes_from_collider(collider_obj: CollisionObject2D) -> Array[CollisionShape2D]:
	var result: Array[CollisionShape2D] = []
	for child in collider_obj.get_children():
		var shape_node: CollisionShape2D = child as CollisionShape2D
		if shape_node == null:
			continue
		if not shape_node.one_way_collision:
			continue
		if shape_node.disabled:
			continue
		result.append(shape_node)
	return result


func _update_visual_animation(input_axis: float) -> void:
	if absf(input_axis) > 0.001:
		_play_move()
	else:
		_play_idle()


func _play_idle() -> void:
	if animated_sprite == null:
		return
	if animated_sprite.sprite_frames == null:
		return
	if not animated_sprite.sprite_frames.has_animation(&"Idle"):
		return
	if animated_sprite.animation == &"Idle" and animated_sprite.is_playing():
		return
	animated_sprite.play(&"Idle")


func _play_move() -> void:
	if animated_sprite == null:
		return
	if animated_sprite.sprite_frames == null:
		return
	if not animated_sprite.sprite_frames.has_animation(&"Run"):
		return
	if animated_sprite.animation == &"Run" and animated_sprite.is_playing():
		return
	animated_sprite.play(&"Run")


func _update_visual_facing() -> void:
	if animated_sprite == null:
		return
	if absf(velocity.x) < 1.0:
		return

	# 与 Character.gd 保持一致：向右移动时 flip_h = true。
	animated_sprite.flip_h = velocity.x > 0.0