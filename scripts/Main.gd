extends Node
## 主场景 - 处理场景切换和游戏流程

@onready var music_player: Node = $MusicPlayer


func _input(event: InputEvent) -> void:
	# 按O键切换到延迟校准场景
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_O:
			get_tree().change_scene_to_file("res://scenes/OffsetCalibration.tscn")
		elif event.keycode == KEY_SPACE:
			# 按空格键重新播放音乐
			if music_player:
				music_player.stop()
				music_player.load_and_play_music()
				print("重新播放音乐")
