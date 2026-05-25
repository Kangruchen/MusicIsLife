static func get_music_time(music_player: Node, fallback: float = 0.0) -> float:
	if music_player == null or not is_instance_valid(music_player):
		return fallback
	if music_player.has_method("get_song_time"):
		return float(music_player.get_song_time())
	if music_player.has_method("get_playback_position"):
		return float(music_player.get_playback_position())
	return fallback


static func get_wall_time_seconds() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


static func get_music_or_wall_time(music_player: Node) -> float:
	return get_music_time(music_player, get_wall_time_seconds())
