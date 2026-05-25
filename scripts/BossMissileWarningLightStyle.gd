extends RefCounted

var _texture: Texture2D = null
var _texture_signature: String = ""


func blink_once(
	warning_light: Sprite2D,
	owner_node: Node2D,
	beat_seconds: float,
	flash_ratio: float,
	light_color: Color,
	peak_alpha: float,
	radius_px: float,
	falloff_power: float,
	light_scale: float,
	additive_blend: bool
) -> void:
	if warning_light == null or not is_instance_valid(warning_light):
		return

	configure_sprite(
		warning_light,
		owner_node,
		radius_px,
		falloff_power,
		light_scale,
		light_color,
		additive_blend
	)

	var safe_beat_seconds: float = beat_seconds
	if safe_beat_seconds <= 0.0:
		safe_beat_seconds = 0.5
	var safe_flash_ratio: float = clampf(flash_ratio, 0.05, 0.95)
	var flash_duration: float = maxf(0.03, safe_beat_seconds * safe_flash_ratio)

	var safe_peak_alpha: float = clampf(peak_alpha, 0.0, 1.0)
	var off_color: Color = Color(light_color.r, light_color.g, light_color.b, 0.0)
	var on_color: Color = Color(light_color.r, light_color.g, light_color.b, safe_peak_alpha)

	warning_light.modulate = off_color
	if warning_light.get_tree() == null:
		return

	var flash_tween: Tween = warning_light.create_tween()
	flash_tween.tween_property(warning_light, "modulate", on_color, flash_duration * 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	flash_tween.tween_property(warning_light, "modulate", off_color, flash_duration * 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func configure_sprite(
	warning_light: Sprite2D,
	owner_node: Node2D,
	radius_px: float,
	falloff_power: float,
	light_scale: float,
	light_color: Color,
	additive_blend: bool
) -> void:
	if warning_light == null:
		return

	warning_light.texture = _get_texture(radius_px, falloff_power)
	warning_light.centered = true
	warning_light.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	warning_light.z_index = 10

	var diameter_px: float = maxf(2.0, radius_px * 2.0 * maxf(0.1, light_scale))
	var texture_width: float = maxf(1.0, warning_light.texture.get_size().x)
	var local_scale: float = diameter_px / texture_width

	var owner_scale_x: float = 1.0
	var owner_scale_y: float = 1.0
	if owner_node != null:
		owner_scale_x = absf(owner_node.scale.x)
		owner_scale_y = absf(owner_node.scale.y)
	var owner_scale_avg: float = maxf(0.001, (owner_scale_x + owner_scale_y) * 0.5)

	warning_light.scale = Vector2.ONE * (local_scale / owner_scale_avg)
	warning_light.modulate = Color(light_color.r, light_color.g, light_color.b, 0.0)

	if additive_blend:
		var add_material: CanvasItemMaterial = warning_light.material as CanvasItemMaterial
		if add_material == null:
			add_material = CanvasItemMaterial.new()
			warning_light.material = add_material
		add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	else:
		warning_light.material = null


func _get_texture(radius_px: float, falloff_power: float) -> Texture2D:
	var texture_size_px: int = clampi(int(round(radius_px * 4.0)), 48, 256)
	var safe_falloff_power: float = maxf(0.6, falloff_power)
	var signature: String = "%d|%.3f" % [texture_size_px, safe_falloff_power]
	if _texture != null and _texture_signature == signature:
		return _texture

	_texture_signature = signature

	var image: Image = Image.create(texture_size_px, texture_size_px, false, Image.FORMAT_RGBA8)
	var center: Vector2 = Vector2(float(texture_size_px) * 0.5, float(texture_size_px) * 0.5)
	var radius: float = maxf(1.0, float(texture_size_px) * 0.5)

	for y in range(texture_size_px):
		for x in range(texture_size_px):
			var sample_pos: Vector2 = Vector2(float(x) + 0.5, float(y) + 0.5)
			var d_norm: float = center.distance_to(sample_pos) / radius
			if d_norm >= 1.0:
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.0))
				continue

			var t: float = 1.0 - d_norm
			var alpha: float = pow(t, safe_falloff_power)
			alpha += smoothstep(0.62, 1.0, t) * 0.22
			alpha = clampf(alpha, 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))

	_texture = ImageTexture.create_from_image(image)
	return _texture
