extends Node2D

@export var lifetime: float = 0.5
@onready var particles: CPUParticles2D = $CPUParticles2D

func _ready() -> void:
	particles.one_shot = true
	particles.emitting = true
	particles.lifetime = lifetime
	get_tree().create_timer(lifetime + 0.05).timeout.connect(func() -> void:
		if is_inside_tree():
			queue_free()
	)

func start(color: Color, duration: float = 0.5) -> void:
	lifetime = duration
	if particles != null:
		particles.lifetime = duration
		particles.modulate = color
		particles.emitting = true
	# safety free in case ready already passed
	get_tree().create_timer(duration + 0.05).timeout.connect(func() -> void:
		if is_inside_tree():
			queue_free()
	)
