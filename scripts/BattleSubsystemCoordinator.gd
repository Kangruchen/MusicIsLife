extends RefCounted


static func pause_for_attack_phase(beat_manager: Node, track_manager: Node, input_manager: Node) -> void:
	_pause_beat_detection(beat_manager)
	_pause_and_clear_tracks(track_manager)
	_pause_input(input_manager)


static func pause_for_dialogue(music_player: Node, beat_manager: Node, track_manager: Node, input_manager: Node) -> void:
	if music_player != null and music_player.has_method("pause_music"):
		music_player.pause_music()
	pause_for_attack_phase(beat_manager, track_manager, input_manager)


static func resume_after_attack_phase(beat_manager: Node, track_manager: Node, input_manager: Node, music_player: Node) -> void:
	if beat_manager != null and beat_manager.has_method("resume_beat_detection"):
		beat_manager.resume_beat_detection()
	if input_manager != null and input_manager.has_method("resume_input"):
		input_manager.resume_input()
	if track_manager != null and track_manager.has_method("resume_note_spawning"):
		track_manager.resume_note_spawning()
	if music_player != null and music_player.has_method("end_attack_mix_mode"):
		music_player.end_attack_mix_mode()


static func force_end_attack_phase(input_manager: Node, music_player: Node) -> void:
	if input_manager != null and input_manager.has_method("force_end_attack_phase"):
		input_manager.force_end_attack_phase()
	if music_player != null and music_player.has_method("end_attack_mix_mode"):
		music_player.end_attack_mix_mode()


static func stop_for_game_over(beat_manager: Node, track_manager: Node, input_manager: Node) -> void:
	pause_for_attack_phase(beat_manager, track_manager, input_manager)


static func stop_for_boss_defeat(music_player: Node, beat_manager: Node, track_manager: Node, input_manager: Node) -> void:
	if music_player != null and music_player.has_method("fade_out_all_for_death"):
		music_player.fade_out_all_for_death()
	pause_for_attack_phase(beat_manager, track_manager, input_manager)


static func _pause_beat_detection(beat_manager: Node) -> void:
	if beat_manager != null and beat_manager.has_method("pause_beat_detection"):
		beat_manager.pause_beat_detection()


static func _pause_and_clear_tracks(track_manager: Node) -> void:
	if track_manager == null:
		return
	if track_manager.has_method("pause_note_spawning"):
		track_manager.pause_note_spawning()
	if track_manager.has_method("clear_all_notes"):
		track_manager.clear_all_notes()


static func _pause_input(input_manager: Node) -> void:
	if input_manager != null and input_manager.has_method("pause_input"):
		input_manager.pause_input()
