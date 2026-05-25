extends Node2D

const CharacterAttackHitboxRules := preload("res://scripts/CharacterAttackHitboxRules.gd")
## 玩家控制器（阶段状态机 + 动作状态机 + 按动画帧控制判定框）

enum PlayerState {
	DEFENSE,
	ATTACK,
}

enum ActionState {
	IDLE,
	MOVE,
	ATTACK,
}

const ATTACK_TYPE_LIGHT: int = 0
const ATTACK_TYPE_HEAVY: int = 1
const ATTACK_TYPE_HEAL: int = 2
const ATTACK_TYPE_ENHANCE: int = 3

@export var anim_config: CharacterAnimConfig = null

@export_group("Movement")
@export var attack_move_speed: float = 280.0
@export var move_action_left: StringName = &"move_left"
@export var move_action_right: StringName = &"move_right"
@export var move_action_up: StringName = &"move_up"
@export var move_action_down: StringName = &"move_down"
@export var lock_movement_during_attack: bool = true

@export_group("Hitbox Timing")
@export var attack_hitbox_enabled: bool = true
@export_range(0.0, 120.0, 1.0) var attack_back_hit_tolerance_px: float = 8.0
@export_range(0, 60, 1) var light_hitbox_open_frame: int = 1
@export_range(0, 60, 1) var light_hitbox_close_frame: int = 3
@export_range(0, 60, 1) var heavy_hitbox_open_frame: int = 1
@export_range(0, 60, 1) var heavy_hitbox_close_frame: int = 4
@export_range(0, 60, 1) var charged_light_hitbox_open_frame: int = 1
@export_range(0, 60, 1) var charged_light_hitbox_close_frame: int = 3
@export_range(0, 60, 1) var charged_heavy_hitbox_open_frame: int = 1
@export_range(0, 60, 1) var charged_heavy_hitbox_close_frame: int = 4

@export_group("Debug Hitbox")
@export var debug_show_combat_hitboxes: bool = false
@export var debug_hitbox_hotkey_enabled: bool = true

@export_group("Hitbox Presets")
@export var light_hitbox_preset_name: StringName = &"Light"
@export var heavy_hitbox_preset_name: StringName = &"Heavy"
@export var charged_light_hitbox_preset_name: StringName = &""
@export var charged_heavy_hitbox_preset_name: StringName = &""

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var attack_hitbox_shape: CollisionShape2D = $AttackHitbox/CollisionShape2D
@onready var hitbox_presets_root: Node2D = get_node_or_null("HitboxPresets") as Node2D

var _state: PlayerState = PlayerState.DEFENSE
var _action_state: ActionState = ActionState.IDLE
var _is_dead: bool = false

var _is_next_attack_charged: bool = false
var _is_attack_anim_playing: bool = false
var _pending_attack_phase_start_transition: bool = false
var _pending_attack_phase_end_transition: bool = false
var _facing_sign: float = -1.0
var _prep_movement_enabled: bool = false
var _attack_movement_enabled: bool = true

var _is_attack_hitbox_active: bool = false
var _attack_hitbox_attack_type: int = -1
var _attack_hit_targets: Dictionary = {}

var _current_attack_type: int = -1
var _current_attack_charged: bool = false
var _current_hitbox_open_frame: int = 0
var _current_hitbox_close_frame: int = 0
var _current_hitbox_size: Vector2 = Vector2(120.0, 90.0)
var _current_hitbox_offset: Vector2 = Vector2(90.0, 0.0)
var _death_anim_token: int = 0
var _death_blackout_active: bool = false
var _death_restart_input_enabled: bool = false
var _death_fx_layer: CanvasLayer = null
var _death_black_rect: ColorRect = null
var _death_hint_line_top: Label = null
var _death_hint_line_bottom: Label = null
var _defense_miss_flash_tween: Tween = null
var _status_flash_tween: Tween = null
@onready var music_player_node: Node = get_node_or_null("../GameManager/MusicPlayer")
@onready var main_camera: Camera2D = get_node_or_null("../Camera2D") as Camera2D

var velocity: Vector2 = Vector2.ZERO


func _ready() -> void:
	if not EventBus.defense_key_pressed.is_connected(_on_defense_action):
		EventBus.defense_key_pressed.connect(_on_defense_action)
	if not EventBus.attack_performed.is_connected(_on_attack_action):
		EventBus.attack_performed.connect(_on_attack_action)
	if not EventBus.attack_result_display.is_connected(_on_attack_result_display):
		EventBus.attack_result_display.connect(_on_attack_result_display)
	if not EventBus.attack_phase_started.is_connected(_on_attack_phase_started):
		EventBus.attack_phase_started.connect(_on_attack_phase_started)
	if not EventBus.attack_phase_ended.is_connected(_on_attack_phase_ended):
		EventBus.attack_phase_ended.connect(_on_attack_phase_ended)
	if not EventBus.attack_movement_enabled_changed.is_connected(_on_attack_movement_enabled_changed):
		EventBus.attack_movement_enabled_changed.connect(_on_attack_movement_enabled_changed)
	if not EventBus.player_died.is_connected(_on_player_died):
		EventBus.player_died.connect(_on_player_died)
	if not EventBus.judgment_made.is_connected(_on_judgment_made):
		EventBus.judgment_made.connect(_on_judgment_made)

	if attack_hitbox != null and not attack_hitbox.area_entered.is_connected(_on_attack_hitbox_area_entered):
		attack_hitbox.area_entered.connect(_on_attack_hitbox_area_entered)

	if animated_sprite != null and not animated_sprite.animation_finished.is_connected(_on_animation_finished):
		animated_sprite.animation_finished.connect(_on_animation_finished)
	if animated_sprite != null and not animated_sprite.frame_changed.is_connected(_on_animation_frame_changed):
		animated_sprite.frame_changed.connect(_on_animation_frame_changed)

	_set_attack_hitbox_enabled(false)
	_enter_state(_state)


func _on_judgment_made(_track: int, judgment: int, _timing_diff: float) -> void:
	if _is_dead:
		return
	if _state != PlayerState.DEFENSE:
		return
	if judgment != 3:
		return
	_play_defense_miss_flash()


func _play_defense_miss_flash() -> void:
	if animated_sprite == null:
		return

	# 连续 MISS 时，终止旧 tween 并从红色重新开始。
	if _defense_miss_flash_tween != null:
		_defense_miss_flash_tween.kill()

	animated_sprite.modulate = Color(1.0, 0.28, 0.28, 1.0)
	_defense_miss_flash_tween = create_tween()
	_defense_miss_flash_tween.set_trans(Tween.TRANS_SINE)
	_defense_miss_flash_tween.set_ease(Tween.EASE_OUT)
	_defense_miss_flash_tween.tween_property(animated_sprite, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.14)
	_defense_miss_flash_tween.finished.connect(func() -> void:
		_defense_miss_flash_tween = null
	)


func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	if _state == PlayerState.ATTACK or _prep_movement_enabled:
		_update_attack_movement(delta)
	if _is_attack_hitbox_active:
		_update_attack_hitbox_transform()
	_clamp_position_inside_screen()


func _process(_delta: float) -> void:
	if debug_show_combat_hitboxes:
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return

	if debug_hitbox_hotkey_enabled and event.is_action_pressed("debug_hitbox"):
		debug_show_combat_hitboxes = not debug_show_combat_hitboxes
		queue_redraw()
		print("[HitboxDebug] 可视化: ", "ON" if debug_show_combat_hitboxes else "OFF")
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		_return_to_main_menu()
		return

	if event.is_action_pressed("restart"):
		get_viewport().set_input_as_handled()
		_quick_restart_current_scene()
		return


func _draw() -> void:
	if not debug_show_combat_hitboxes:
		return

	_draw_attack_hitbox_debug()
	_draw_enemy_hurtboxes_debug()


func _draw_attack_hitbox_debug() -> void:
	if attack_hitbox == null or attack_hitbox_shape == null:
		return
	if attack_hitbox_shape.shape == null:
		return

	var global_xform: Transform2D = attack_hitbox.global_transform * attack_hitbox_shape.transform
	var active_color: Color = Color(0.95, 0.25, 0.25, 1.0) if _is_attack_hitbox_active else Color(0.75, 0.75, 0.75, 1.0)
	_draw_shape_debug(global_xform, attack_hitbox_shape.shape, active_color, 0.14, 2.0)


func _draw_enemy_hurtboxes_debug() -> void:
	var selected_area: Area2D = null
	if attack_hitbox != null and attack_hitbox.monitoring:
		selected_area = _pick_frontmost_attack_target_area()

	for node in get_tree().get_nodes_in_group(&"enemy_hurtbox"):
		var enemy_area: Area2D = node as Area2D
		if enemy_area == null or not is_instance_valid(enemy_area):
			continue

		for child in enemy_area.get_children():
			var shape_node: CollisionShape2D = child as CollisionShape2D
			if shape_node == null or shape_node.shape == null:
				continue

			var global_xform: Transform2D = enemy_area.global_transform * shape_node.transform
			var is_selected: bool = (selected_area != null and enemy_area == selected_area)
			var color: Color = Color(1.0, 0.95, 0.2, 1.0) if is_selected else Color(0.2, 0.95, 1.0, 1.0)
			var fill_alpha: float = 0.16 if is_selected else 0.08
			_draw_shape_debug(global_xform, shape_node.shape, color, fill_alpha, 2.0)


func _draw_shape_debug(global_xform: Transform2D, shape: Shape2D, color: Color, fill_alpha: float, line_width: float) -> void:
	var local_xform: Transform2D = global_transform.affine_inverse() * global_xform

	if shape is RectangleShape2D:
		var rect_shape: RectangleShape2D = shape as RectangleShape2D
		var half: Vector2 = rect_shape.size * 0.5
		var points: PackedVector2Array = PackedVector2Array([
			local_xform * Vector2(-half.x, -half.y),
			local_xform * Vector2(half.x, -half.y),
			local_xform * Vector2(half.x, half.y),
			local_xform * Vector2(-half.x, half.y)
		])
		draw_colored_polygon(points, Color(color.r, color.g, color.b, fill_alpha))
		var outline: PackedVector2Array = PackedVector2Array([points[0], points[1], points[2], points[3], points[0]])
		draw_polyline(outline, color, line_width, true)
		return

	if shape is CircleShape2D:
		var circle_shape: CircleShape2D = shape as CircleShape2D
		var radius_scale: float = maxf(local_xform.x.length(), local_xform.y.length())
		var center: Vector2 = local_xform.origin
		var radius: float = circle_shape.radius * radius_scale
		draw_circle(center, radius, Color(color.r, color.g, color.b, fill_alpha))
		draw_arc(center, radius, 0.0, TAU, 48, color, line_width, true)


func _on_defense_action(track: Note.NoteType) -> void:
	if _is_dead:
		return
	if _state != PlayerState.DEFENSE:
		return
	if anim_config == null:
		return

	var anim_name: String = anim_config.get_defense_anim(track)
	_play_anim(anim_name, true)


func _on_attack_action(attack_type: int, _heat_level: int) -> void:
	if _is_dead:
		return
	if _state != PlayerState.ATTACK:
		push_warning("[Character] _on_attack_action 忽略: state=%d (非ATTACK), attack_type=%d" % [_state, attack_type])
		return

	var use_charged: bool = _is_next_attack_charged
	if _is_attack_anim_playing:
		_interrupt_attack_animation()

	_start_attack_action(attack_type, use_charged)
	if _attack_type_uses_hitbox(attack_type):
		_is_next_attack_charged = false


func _on_attack_result_display(attack_type: int, is_perfect: bool, heat_level: int) -> void:
	if _is_dead:
		return
	if _state != PlayerState.ATTACK:
		return

	var text: String = ""
	var color: Color = Color.WHITE

	match attack_type:
		ATTACK_TYPE_LIGHT:
			if is_perfect:
				text = "Hit"
				color = Color(0.4, 0.7, 1.0)
			else:
				text = "Miss"
				color = Color(0.7, 0.7, 0.7)
		ATTACK_TYPE_HEAVY:
			text = "Critical x%d" % (heat_level + 1)
			color = Color(1.0, 0.4, 0.1)
		ATTACK_TYPE_HEAL:
			text = "Heal"
			color = Color(0.2, 1.0, 0.4)

	_spawn_floating_text(text, color)


func _spawn_floating_text(text: String, color: Color) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	label.add_theme_constant_override("outline_size", 3)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.z_index = 100
	label.position = _get_floating_text_origin()
	label.modulate.a = 1.0
	add_child(label)

	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_EXPO)
	tween.tween_property(label, "position:y", label.position.y - 40.0, 0.45)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.4).set_delay(0.08)
	tween.tween_callback(label.queue_free)


func _get_floating_text_origin() -> Vector2:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return Vector2(0.0, -80.0)
	var anim_name: String = String(animated_sprite.animation)
	if anim_name.is_empty() or not animated_sprite.sprite_frames.has_animation(anim_name):
		return Vector2(0.0, -80.0)
	var frame_texture: Texture2D = animated_sprite.sprite_frames.get_frame_texture(anim_name, animated_sprite.frame)
	if frame_texture == null:
		return Vector2(0.0, -80.0)
	var tex_height: float = frame_texture.get_size().y * absf(animated_sprite.global_scale.y)
	return Vector2(0.0, -tex_height * 0.5 - 20.0)


func _on_attack_phase_started() -> void:
	if _is_dead:
		return
	_pending_attack_phase_end_transition = false
	_is_next_attack_charged = false
	_prep_movement_enabled = false
	if _should_defer_attack_phase_start_transition():
		_pending_attack_phase_start_transition = true
		return
	_complete_attack_phase_start_transition()


func _on_attack_phase_ended() -> void:
	if _is_dead:
		return
	_pending_attack_phase_start_transition = false
	_pending_attack_phase_end_transition = false
	_is_next_attack_charged = false
	_prep_movement_enabled = false
	_attack_movement_enabled = false
	if _is_attack_anim_playing:
		_pending_attack_phase_end_transition = true
		return
	_complete_attack_phase_end_transition()


func _complete_attack_phase_end_transition() -> void:
	_clear_attack_action_runtime()
	_transition_to_state(PlayerState.DEFENSE)
	_facing_sign = -1.0
	if animated_sprite != null:
		animated_sprite.flip_h = false
	velocity = Vector2.ZERO


func _complete_attack_phase_start_transition() -> void:
	_pending_attack_phase_start_transition = false
	_attack_movement_enabled = true
	_clear_attack_action_runtime()
	_transition_to_state(PlayerState.ATTACK)


func _should_defer_attack_phase_start_transition() -> bool:
	if anim_config == null or animated_sprite == null:
		return false
	if not animated_sprite.is_playing():
		return false

	var current_anim: String = String(animated_sprite.animation)
	if current_anim.is_empty():
		return false

	return current_anim == anim_config.guard_anim or current_anim == anim_config.hit_anim or current_anim == anim_config.dodge_anim


func _transition_to_state(next_state: PlayerState) -> void:
	if next_state == _state:
		return

	_exit_state(_state)
	_state = next_state
	_enter_state(_state)


func _enter_state(state: PlayerState) -> void:
	match state:
		PlayerState.DEFENSE:
			_action_state = ActionState.IDLE
			velocity = Vector2.ZERO
			_clear_attack_action_runtime()
			_play_idle()
		PlayerState.ATTACK:
			_action_state = ActionState.IDLE
			velocity = Vector2.ZERO
			_clear_attack_action_runtime()
			_play_idle()


func _exit_state(state: PlayerState) -> void:
	match state:
		PlayerState.ATTACK:
			_clear_attack_action_runtime()
		_:
			pass


func _update_attack_movement(delta: float) -> void:
	if _is_attack_anim_playing and (lock_movement_during_attack or not _attack_movement_enabled):
		velocity = Vector2.ZERO
		_action_state = ActionState.ATTACK
		return

	if _state == PlayerState.ATTACK and not _attack_movement_enabled:
		velocity = Vector2.ZERO
		_action_state = ActionState.IDLE
		_play_idle()
		return

	var input_dir: Vector2 = Input.get_vector(move_action_left, move_action_right, move_action_up, move_action_down)
	velocity = input_dir * maxf(0.0, attack_move_speed)
	global_position += velocity * delta

	if absf(input_dir.x) > 0.001:
		_facing_sign = signf(input_dir.x)
		if animated_sprite != null:
			animated_sprite.flip_h = _facing_sign > 0.0

	if _is_attack_anim_playing:
		_action_state = ActionState.ATTACK
	elif input_dir.length_squared() > 0.0001:
		_action_state = ActionState.MOVE
		_play_move()
	else:
		_action_state = ActionState.IDLE
		_play_idle()


func _clamp_position_inside_screen() -> void:
	var visible_world_rect: Rect2 = _get_visible_world_rect()
	var half_extents: Vector2 = _get_character_half_extents()

	var min_x: float = visible_world_rect.position.x + half_extents.x
	var max_x: float = visible_world_rect.position.x + visible_world_rect.size.x - half_extents.x
	var min_y: float = visible_world_rect.position.y + half_extents.y
	var max_y: float = visible_world_rect.position.y + visible_world_rect.size.y - half_extents.y

	if max_x < min_x:
		var center_x: float = visible_world_rect.position.x + visible_world_rect.size.x * 0.5
		min_x = center_x
		max_x = center_x
	if max_y < min_y:
		var center_y: float = visible_world_rect.position.y + visible_world_rect.size.y * 0.5
		min_y = center_y
		max_y = center_y

	global_position = Vector2(
		clampf(global_position.x, min_x, max_x),
		clampf(global_position.y, min_y, max_y)
	)


func _get_visible_world_rect() -> Rect2:
	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	var inv_canvas: Transform2D = get_viewport().get_canvas_transform().affine_inverse()

	var p1: Vector2 = inv_canvas * viewport_rect.position
	var p2: Vector2 = inv_canvas * Vector2(viewport_rect.position.x + viewport_rect.size.x, viewport_rect.position.y)
	var p3: Vector2 = inv_canvas * Vector2(viewport_rect.position.x, viewport_rect.position.y + viewport_rect.size.y)
	var p4: Vector2 = inv_canvas * (viewport_rect.position + viewport_rect.size)

	var min_x: float = minf(minf(p1.x, p2.x), minf(p3.x, p4.x))
	var max_x: float = maxf(maxf(p1.x, p2.x), maxf(p3.x, p4.x))
	var min_y: float = minf(minf(p1.y, p2.y), minf(p3.y, p4.y))
	var max_y: float = maxf(maxf(p1.y, p2.y), maxf(p3.y, p4.y))

	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))


func _get_character_half_extents() -> Vector2:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return Vector2(24.0, 24.0)

	var anim_name: String = String(animated_sprite.animation)
	if anim_name.is_empty() or not animated_sprite.sprite_frames.has_animation(anim_name):
		return Vector2(24.0, 24.0)

	var frame_texture: Texture2D = animated_sprite.sprite_frames.get_frame_texture(anim_name, animated_sprite.frame)
	if frame_texture == null:
		return Vector2(24.0, 24.0)

	var tex_size: Vector2 = frame_texture.get_size()
	var scale_abs: Vector2 = Vector2(absf(animated_sprite.global_scale.x), absf(animated_sprite.global_scale.y))
	return Vector2(tex_size.x * scale_abs.x * 0.5, tex_size.y * scale_abs.y * 0.5)


func _start_attack_action(attack_type: int, is_charged: bool) -> void:
	_current_attack_type = attack_type
	_current_attack_charged = is_charged
	_current_hitbox_open_frame = CharacterAttackHitboxRules.get_open_frame(
		attack_type,
		is_charged,
		light_hitbox_open_frame,
		heavy_hitbox_open_frame,
		charged_light_hitbox_open_frame,
		charged_heavy_hitbox_open_frame
	)
	_current_hitbox_close_frame = CharacterAttackHitboxRules.get_close_frame(
		attack_type,
		is_charged,
		light_hitbox_close_frame,
		heavy_hitbox_close_frame,
		charged_light_hitbox_close_frame,
		charged_heavy_hitbox_close_frame
	)

	_is_attack_anim_playing = true
	_action_state = ActionState.ATTACK

	_set_attack_hitbox_enabled(false)
	_apply_hitbox_preset_for_current_attack()

	if anim_config == null:
		_finish_attack_action()
		return

	var anim_name: String = anim_config.get_attack_anim_with_charge(attack_type, is_charged)
	if not _has_anim(anim_name):
		push_warning("[Character] 动画不存在: '%s'，回退到 idle" % anim_name)
		_finish_attack_action()
		return

	_play_anim(anim_name, false)
	_try_open_hitbox_at_current_frame()


func _finish_attack_action() -> void:
	if not _is_attack_anim_playing:
		return

	_is_attack_anim_playing = false
	_action_state = ActionState.IDLE
	_set_attack_hitbox_enabled(false)
	_play_idle()


func _interrupt_attack_animation() -> void:
	_set_attack_hitbox_enabled(false)
	if animated_sprite != null and animated_sprite.is_playing():
		animated_sprite.stop()
	_is_attack_anim_playing = false


func _apply_hitbox_preset_for_current_attack() -> void:
	var preset_name: StringName = CharacterAttackHitboxRules.get_preset_name(
		_current_attack_type,
		_current_attack_charged,
		light_hitbox_preset_name,
		heavy_hitbox_preset_name,
		charged_light_hitbox_preset_name,
		charged_heavy_hitbox_preset_name
	)
	var default_offset: Vector2 = CharacterAttackHitboxRules.get_default_offset(_current_attack_type)
	var default_size: Vector2 = CharacterAttackHitboxRules.get_default_size(_current_attack_type)

	if hitbox_presets_root == null:
		_current_hitbox_offset = default_offset
		_current_hitbox_size = default_size
		return

	var preset_node: Node2D = hitbox_presets_root.get_node_or_null(String(preset_name)) as Node2D
	if preset_node == null:
		_current_hitbox_offset = default_offset
		_current_hitbox_size = default_size
		return

	var preset_shape_node: CollisionShape2D = preset_node.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if preset_shape_node == null:
		_current_hitbox_offset = default_offset
		_current_hitbox_size = default_size
		return

	var rect_shape: RectangleShape2D = preset_shape_node.shape as RectangleShape2D
	if rect_shape == null:
		_current_hitbox_offset = default_offset
		_current_hitbox_size = default_size
		return

	var scale_abs: Vector2 = Vector2(absf(preset_shape_node.scale.x), absf(preset_shape_node.scale.y))
	_current_hitbox_offset = preset_node.position + preset_shape_node.position
	_current_hitbox_size = Vector2(
		rect_shape.size.x * maxf(0.001, scale_abs.x),
		rect_shape.size.y * maxf(0.001, scale_abs.y)
	)


func _open_attack_hitbox() -> void:
	if not attack_hitbox_enabled:
		return
	if attack_hitbox == null or attack_hitbox_shape == null:
		return

	var shape: RectangleShape2D = attack_hitbox_shape.shape as RectangleShape2D
	if shape == null:
		shape = RectangleShape2D.new()
		attack_hitbox_shape.shape = shape

	shape.size = _current_hitbox_size
	_update_attack_hitbox_transform()
	_attack_hitbox_attack_type = _current_attack_type
	_attack_hit_targets.clear()
	_set_attack_hitbox_enabled(true)
	_process_attack_overlap_once()


func _close_attack_hitbox() -> void:
	_set_attack_hitbox_enabled(false)


func _process_attack_overlap_once() -> void:
	if attack_hitbox == null or not attack_hitbox.monitoring:
		return

	var best_area: Area2D = _pick_frontmost_attack_target_area()
	if best_area == null:
		return
	_process_single_attack_overlap(best_area)


func _on_attack_hitbox_area_entered(_area: Area2D) -> void:
	# 进入回调也走统一筛选，保证只命中前方最近目标。
	_process_attack_overlap_once()


func _pick_frontmost_attack_target_area() -> Area2D:
	var candidates: Array[Area2D] = []
	for overlap in attack_hitbox.get_overlapping_areas():
		var candidate_area: Area2D = overlap as Area2D
		if candidate_area == null or not is_instance_valid(candidate_area):
			continue
		if not candidate_area.is_in_group(&"enemy_hurtbox"):
			continue

		var candidate_id: int = candidate_area.get_instance_id()
		if _attack_hit_targets.has(candidate_id):
			continue

		candidates.append(candidate_area)

	if candidates.is_empty():
		return null
	if candidates.size() == 1:
		return candidates[0]

	var best_area: Area2D = null
	var best_distance_sq: float = INF
	var attack_center: Vector2 = _get_attack_hitbox_center_global()
	var forward_sign: float = signf(attack_hitbox.position.x)
	if forward_sign == 0.0:
		forward_sign = _facing_sign if _facing_sign != 0.0 else -1.0
	var back_tolerance: float = maxf(0.0, attack_back_hit_tolerance_px)

	for area in candidates:

		var target_point: Vector2 = _get_enemy_hurtbox_target_point(area, attack_center)
		var dx: float = target_point.x - attack_center.x
		if dx * forward_sign < -back_tolerance:
			continue

		var distance_sq: float = attack_center.distance_squared_to(target_point)
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best_area = area

	return best_area


func _get_attack_hitbox_center_global() -> Vector2:
	if attack_hitbox == null:
		return global_position
	if attack_hitbox_shape == null:
		return attack_hitbox.global_position
	return (attack_hitbox.global_transform * attack_hitbox_shape.transform).origin


func _get_enemy_hurtbox_target_point(area: Area2D, reference_point: Vector2) -> Vector2:
	var best_point: Vector2 = area.global_position
	var best_distance_sq: float = INF

	for child in area.get_children():
		var shape_node: CollisionShape2D = child as CollisionShape2D
		if shape_node == null or shape_node.shape == null:
			continue
		if shape_node.disabled:
			continue

		var shape_center: Vector2 = (area.global_transform * shape_node.transform).origin
		var distance_sq: float = reference_point.distance_squared_to(shape_center)
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best_point = shape_center

	return best_point


func _process_single_attack_overlap(area: Area2D) -> void:
	if _state != PlayerState.ATTACK:
		return
	if not _is_attack_hitbox_active:
		return
	if area == null or not is_instance_valid(area):
		return
	if not area.is_in_group(&"enemy_hurtbox"):
		return

	var area_id: int = area.get_instance_id()
	if _attack_hit_targets.has(area_id):
		return
	_attack_hit_targets[area_id] = true

	# 传递真实受击 Area，避免中间层级变化导致部位识别丢失。
	var target: Node = area
	EventBus.attack_hit_confirmed.emit(_attack_hitbox_attack_type, target)


func _get_attack_forward_sign() -> float:
	return _facing_sign if _facing_sign != 0.0 else -1.0


func _update_attack_hitbox_transform() -> void:
	if attack_hitbox == null:
		return
	attack_hitbox.position = Vector2(-_get_attack_forward_sign() * _current_hitbox_offset.x, _current_hitbox_offset.y)


func _set_attack_hitbox_enabled(enabled: bool) -> void:
	if attack_hitbox == null:
		return
	attack_hitbox.monitoring = enabled
	attack_hitbox.monitorable = enabled
	if attack_hitbox_shape != null:
		attack_hitbox_shape.disabled = not enabled
	_is_attack_hitbox_active = enabled
	if not enabled:
		_attack_hitbox_attack_type = -1
		_attack_hit_targets.clear()


func _clear_attack_action_runtime() -> void:
	_is_attack_anim_playing = false
	_current_attack_type = -1
	_current_attack_charged = false
	_current_hitbox_open_frame = 0
	_current_hitbox_close_frame = 0
	_set_attack_hitbox_enabled(false)


func _play_idle() -> void:
	if anim_config == null:
		return
	if anim_config.idle_anim.is_empty():
		return
	_play_anim_if_needed(anim_config.idle_anim, false)


func _play_move() -> void:
	if anim_config == null:
		return
	var move_anim_name: String = anim_config.move_anim
	if move_anim_name.is_empty():
		move_anim_name = anim_config.idle_anim
	if move_anim_name.is_empty():
		return
	_play_anim_if_needed(move_anim_name, false)


func _play_anim_if_needed(anim_name: String, beat_sync: bool) -> void:
	if anim_name.is_empty():
		return
	if animated_sprite == null:
		return
	if String(animated_sprite.animation) == anim_name and animated_sprite.is_playing():
		return
	_play_anim(anim_name, beat_sync)


func _has_anim(anim_name: String) -> bool:
	if anim_name.is_empty():
		return false
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return false
	return animated_sprite.sprite_frames.has_animation(anim_name)


func _play_anim(anim_name: String, beat_sync: bool) -> void:
	if anim_name.is_empty():
		return
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return
	if not animated_sprite.sprite_frames.has_animation(anim_name):
		push_warning("[Character] AnimatedSprite2D 缺少动画: %s" % anim_name)
		return

	if beat_sync:
		_apply_beat_sync_speed(anim_name)
	else:
		animated_sprite.speed_scale = 1.0

	animated_sprite.frame = 0
	animated_sprite.play(anim_name)


func _apply_beat_sync_speed(anim_name: String) -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return

	var bi: float = EventBus.beat_interval
	if bi <= 0.0:
		animated_sprite.speed_scale = 1.0
		return

	var sprite_frames: SpriteFrames = animated_sprite.sprite_frames
	var frame_count: int = sprite_frames.get_frame_count(anim_name)
	var base_fps: float = sprite_frames.get_animation_speed(anim_name)
	if frame_count <= 0 or base_fps <= 0.0:
		animated_sprite.speed_scale = 1.0
		return

	var total_duration_weight: float = 0.0
	for i in range(frame_count):
		total_duration_weight += sprite_frames.get_frame_duration(anim_name, i)

	var original_duration: float = total_duration_weight / base_fps
	animated_sprite.speed_scale = clampf(original_duration / bi, 0.1, 10.0)


func _on_animation_finished() -> void:
	if _is_dead:
		return

	if _state == PlayerState.DEFENSE:
		EventBus.defense_feedback_finished.emit()
		if _pending_attack_phase_start_transition:
			_complete_attack_phase_start_transition()
			return
		_play_idle()
		return

	if _state == PlayerState.ATTACK and _is_attack_anim_playing:
		_finish_attack_action()
		if _pending_attack_phase_end_transition and not _is_attack_anim_playing:
			_pending_attack_phase_end_transition = false
			_complete_attack_phase_end_transition()


func _on_animation_frame_changed() -> void:
	if not _is_attack_anim_playing:
		return
	if not _attack_type_uses_hitbox(_current_attack_type):
		return
	if animated_sprite == null:
		return

	var frame: int = animated_sprite.frame
	var open_frame: int = _current_hitbox_open_frame
	var close_frame: int = _current_hitbox_close_frame

	if close_frame < open_frame:
		close_frame = open_frame

	if frame == open_frame and not _is_attack_hitbox_active:
		_open_attack_hitbox()
	elif frame >= close_frame and _is_attack_hitbox_active:
		_close_attack_hitbox()


func _try_open_hitbox_at_current_frame() -> void:
	_on_animation_frame_changed()


func _play_status_flash(color: Color, duration: float = 0.22) -> void:
	# Simple sprite-based VFX only
	var tex_path: String = "res://assets/VFX/chargebullet.png"
	if color.g > color.r:
		tex_path = "res://assets/VFX/bling_green.png"
	_spawn_status_vfx(tex_path, color, duration)


func _spawn_status_vfx(tex_path: String, color: Color, duration: float = 0.22) -> void:
	var tex: Texture2D = null
	if ResourceLoader.exists(tex_path):
		tex = load(tex_path)
	if tex == null:
		return

	var v: Sprite2D = Sprite2D.new()
	v.texture = tex
	v.centered = true
	v.position = Vector2.ZERO
	v.modulate = color
	v.scale = Vector2.ONE * 0.6
	v.z_index = 50
	add_child(v)

	var tw: Tween = create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(v, "scale", Vector2.ONE * 1.6, duration)
	tw.tween_property(v, "modulate:a", 0.0, duration)
	tw.finished.connect(func() -> void:
		if v != null and v.is_inside_tree():
			v.queue_free()
	)


func _on_player_died() -> void:
	if _is_dead:
		return

	_is_dead = true
	_death_restart_input_enabled = false
	_pending_attack_phase_start_transition = false
	_pending_attack_phase_end_transition = false
	velocity = Vector2.ZERO
	_is_next_attack_charged = false
	_prep_movement_enabled = false
	_attack_movement_enabled = false
	_clear_attack_action_runtime()
	_state = PlayerState.DEFENSE
	_action_state = ActionState.IDLE
	_hide_death_restart_hints()
	_start_death_music_fadeout()

	_play_dead_fail_sequence()


func _play_dead_fail_sequence() -> void:
	if anim_config == null:
		return

	var dead_anim: String = anim_config.fail_anim
	if dead_anim.is_empty():
		dead_anim = anim_config.guard_anim
	if not _has_anim(dead_anim):
		return

	_death_anim_token += 1
	var token: int = _death_anim_token
	_start_death_camera_focus_intro(token, dead_anim)


func _start_death_camera_focus_intro(token: int, dead_anim: String) -> void:
	if main_camera == null:
		_play_fail_after_camera_focus(token, dead_anim)
		return

	var target_zoom: Vector2 = Vector2(1.28, 1.28)
	var target_position: Vector2 = _get_clamped_camera_focus_position(global_position, target_zoom)

	var focus_tween: Tween = create_tween()
	focus_tween.set_parallel(true)
	focus_tween.set_trans(Tween.TRANS_SINE)
	focus_tween.set_ease(Tween.EASE_OUT)
	focus_tween.tween_property(main_camera, "global_position", target_position, 0.45)
	focus_tween.tween_property(main_camera, "zoom", target_zoom, 0.45)
	focus_tween.finished.connect(func() -> void:
		if token != _death_anim_token:
			return
		_play_fail_after_camera_focus(token, dead_anim)
	)


func _play_fail_after_camera_focus(token: int, dead_anim: String) -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return
	if not animated_sprite.sprite_frames.has_animation(dead_anim):
		return

	animated_sprite.visible = true
	_play_anim(dead_anim, false)

	var fail_duration: float = _get_animation_duration_seconds(dead_anim)
	if fail_duration <= 0.0:
		_freeze_current_animation_last_frame()
		_fade_to_black_after_fail(token)
		return

	get_tree().create_timer(fail_duration).timeout.connect(func() -> void:
		if token != _death_anim_token:
			return
		_freeze_current_animation_last_frame()
		_fade_to_black_after_fail(token)
	)


func _fade_to_black_after_fail(token: int) -> void:
	if _death_black_rect == null or not is_instance_valid(_death_black_rect):
		var host: Node = get_tree().current_scene
		if host == null:
			host = get_tree().root
		if host == null:
			return

		if _death_fx_layer == null or not is_instance_valid(_death_fx_layer):
			_death_fx_layer = CanvasLayer.new()
			_death_fx_layer.layer = 100
			host.add_child(_death_fx_layer)

		_death_black_rect = ColorRect.new()
		_death_black_rect.color = Color(0.0, 0.0, 0.0, 0.0)
		_death_black_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_death_fx_layer.add_child(_death_black_rect)

	_configure_blackout_hole_for_player()

	_death_blackout_active = true
	var fade_tween: Tween = create_tween()
	fade_tween.set_trans(Tween.TRANS_SINE)
	fade_tween.set_ease(Tween.EASE_IN_OUT)
	if _death_black_rect.material is ShaderMaterial:
		fade_tween.tween_property(_death_black_rect.material, "shader_parameter/blackout_alpha", 1.0, 0.55)
	else:
		fade_tween.tween_property(_death_black_rect, "color:a", 1.0, 0.55)
	fade_tween.tween_callback(func() -> void:
		if token != _death_anim_token:
			return
		_death_restart_input_enabled = true
		_show_death_restart_hints()
	)


func _show_death_restart_hints() -> void:
	if _death_fx_layer == null or not is_instance_valid(_death_fx_layer):
		return

	_hide_death_restart_hints()

	_death_hint_line_top = Label.new()
	_death_hint_line_top.text = "按 %s 重新开始" % GameConstants.get_action_key_label("restart", "R")
	_death_hint_line_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_hint_line_top.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_death_hint_line_top.add_theme_font_size_override("font_size", 26)
	_death_hint_line_top.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
	_death_hint_line_top.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	_death_hint_line_top.add_theme_constant_override("shadow_offset_x", 2)
	_death_hint_line_top.add_theme_constant_override("shadow_offset_y", 2)
	_death_hint_line_top.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_death_hint_line_top.offset_left = -220.0
	_death_hint_line_top.offset_right = 220.0
	_death_hint_line_top.offset_top = -48.0
	_death_hint_line_top.offset_bottom = 0.0
	_death_fx_layer.add_child(_death_hint_line_top)

	_death_hint_line_bottom = Label.new()
	_death_hint_line_bottom.text = "按 %s 返回主菜单" % GameConstants.get_action_key_label("menu", "Esc")
	_death_hint_line_bottom.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_hint_line_bottom.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_death_hint_line_bottom.add_theme_font_size_override("font_size", 22)
	_death_hint_line_bottom.add_theme_color_override("font_color", Color(0.93, 0.93, 0.93, 0.92))
	_death_hint_line_bottom.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	_death_hint_line_bottom.add_theme_constant_override("shadow_offset_x", 2)
	_death_hint_line_bottom.add_theme_constant_override("shadow_offset_y", 2)
	_death_hint_line_bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_death_hint_line_bottom.offset_left = -260.0
	_death_hint_line_bottom.offset_right = 260.0
	_death_hint_line_bottom.offset_top = 8.0
	_death_hint_line_bottom.offset_bottom = 56.0
	_death_fx_layer.add_child(_death_hint_line_bottom)


func _hide_death_restart_hints() -> void:
	if _death_hint_line_top != null and is_instance_valid(_death_hint_line_top):
		_death_hint_line_top.queue_free()
	if _death_hint_line_bottom != null and is_instance_valid(_death_hint_line_bottom):
		_death_hint_line_bottom.queue_free()
	_death_hint_line_top = null
	_death_hint_line_bottom = null


func _quick_restart_current_scene() -> void:
	_death_restart_input_enabled = false
	_hide_death_restart_hints()
	var err: int = get_tree().reload_current_scene()
	if err != OK:
		push_warning("[Character] 重开场景失败: %d" % err)


func _return_to_main_menu() -> void:
	_death_restart_input_enabled = false
	_hide_death_restart_hints()
	var err: int = get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	if err != OK:
		push_warning("[Character] 返回主菜单失败: %d" % err)


func _freeze_current_animation_last_frame() -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return

	var current_anim: String = String(animated_sprite.animation)
	if current_anim.is_empty() or not animated_sprite.sprite_frames.has_animation(current_anim):
		return

	var frame_count: int = animated_sprite.sprite_frames.get_frame_count(current_anim)
	if frame_count <= 0:
		return

	animated_sprite.stop()
	animated_sprite.frame = frame_count - 1
	animated_sprite.frame_progress = 0.0


func _get_animation_duration_seconds(anim_name: String) -> float:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return 0.0

	var sprite_frames: SpriteFrames = animated_sprite.sprite_frames
	if not sprite_frames.has_animation(anim_name):
		return 0.0

	var frame_count: int = sprite_frames.get_frame_count(anim_name)
	var base_fps: float = sprite_frames.get_animation_speed(anim_name)
	if frame_count <= 0 or base_fps <= 0.0:
		return 0.0

	var total_units: float = 0.0
	for i in range(frame_count):
		total_units += sprite_frames.get_frame_duration(anim_name, i)

	return total_units / base_fps


func _start_death_music_fadeout() -> void:
	if music_player_node != null and music_player_node.has_method("fade_out_all_for_death"):
		music_player_node.call("fade_out_all_for_death", 1.25, -40.0)


func _get_clamped_camera_focus_position(desired_position: Vector2, target_zoom: Vector2) -> Vector2:
	if main_camera == null:
		return desired_position

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return desired_position

	var safe_zoom: Vector2 = Vector2(maxf(0.001, target_zoom.x), maxf(0.001, target_zoom.y))
	var half_world_size: Vector2 = Vector2(viewport_size.x * safe_zoom.x * 0.5, viewport_size.y * safe_zoom.y * 0.5)

	var min_x: float = float(main_camera.limit_left) + half_world_size.x
	var max_x: float = float(main_camera.limit_right) - half_world_size.x
	var min_y: float = float(main_camera.limit_top) + half_world_size.y
	var max_y: float = float(main_camera.limit_bottom) - half_world_size.y

	var clamped: Vector2 = desired_position
	if min_x <= max_x:
		clamped.x = clampf(clamped.x, min_x, max_x)
	if min_y <= max_y:
		clamped.y = clampf(clamped.y, min_y, max_y)

	return clamped


func _configure_blackout_hole_for_player() -> void:
	if _death_black_rect == null or not is_instance_valid(_death_black_rect):
		return
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return

	var anim_name: String = String(animated_sprite.animation)
	if anim_name.is_empty() or not animated_sprite.sprite_frames.has_animation(anim_name):
		return

	var frame_texture: Texture2D = animated_sprite.sprite_frames.get_frame_texture(anim_name, animated_sprite.frame)
	if frame_texture == null:
		return

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	var texture_size: Vector2 = frame_texture.get_size()
	var scale_abs: Vector2 = Vector2(absf(animated_sprite.global_scale.x), absf(animated_sprite.global_scale.y))
	var radius_px: float = maxf(texture_size.x * scale_abs.x, texture_size.y * scale_abs.y) * 0.35
	var softness_px: float = maxf(20.0, radius_px * 0.18)
	var min_side: float = minf(viewport_size.x, viewport_size.y)

	var hole_center_screen: Vector2 = get_viewport().get_canvas_transform() * animated_sprite.global_position
	var hole_center_uv: Vector2 = Vector2(hole_center_screen.x / viewport_size.x, hole_center_screen.y / viewport_size.y)
	var hole_radius_uv: float = radius_px / viewport_size.y
	var hole_softness_uv: float = softness_px / viewport_size.y
	var viewport_aspect: float = viewport_size.x / viewport_size.y

	var shader: Shader = Shader.new()
	shader.code = """
shader_type canvas_item;

uniform vec2 hole_center = vec2(0.5, 0.5);
uniform float hole_radius = 0.2;
uniform float hole_softness = 0.05;
uniform float blackout_alpha = 1.0;
uniform float viewport_aspect = 1.0;

void fragment() {
	vec2 delta = SCREEN_UV - hole_center;
	delta.x *= viewport_aspect;
	float d = length(delta);
	float mask = smoothstep(hole_radius, hole_radius + hole_softness, d);
	COLOR = vec4(0.0, 0.0, 0.0, blackout_alpha * mask);
}
"""

	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("hole_center", hole_center_uv)
	mat.set_shader_parameter("hole_radius", hole_radius_uv)
	mat.set_shader_parameter("hole_softness", hole_softness_uv)
	mat.set_shader_parameter("blackout_alpha", 0.0)
	mat.set_shader_parameter("viewport_aspect", viewport_aspect)
	_death_black_rect.material = mat


func _attack_type_uses_hitbox(attack_type: int) -> bool:
	return attack_type == ATTACK_TYPE_LIGHT or attack_type == ATTACK_TYPE_HEAVY


func _on_attack_movement_enabled_changed(enabled: bool) -> void:
	if _state == PlayerState.ATTACK:
		_attack_movement_enabled = enabled
		if not enabled:
			velocity = Vector2.ZERO
		return

	_prep_movement_enabled = enabled
	if not enabled:
		velocity = Vector2.ZERO
	elif _pending_attack_phase_start_transition:
		_complete_attack_phase_start_transition()
