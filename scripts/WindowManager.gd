extends Node
## 窗口管理器 - 支持 Alt+Enter 切换全屏/窗口模式
## 注册为 Autoload，全局生效（包括打包后的运行环境）


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER and event.alt_pressed:
			_toggle_fullscreen()
			get_viewport().set_input_as_handled()


## 切换全屏与窗口模式
func _toggle_fullscreen() -> void:
	var mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
