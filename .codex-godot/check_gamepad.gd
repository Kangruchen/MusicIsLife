extends SceneTree

func _initialize() -> void:
	var script := load("res://scripts/GamepadManager.gd") as Script
	if script == null:
		print("LOAD_FAILED")
		quit(1)
		return

	var instance: Object = script.new()
	if instance == null:
		print("NEW_FAILED")
		quit(1)
		return

	root.add_child(instance)
	print("INSTANCE_OK")
	quit(0)
