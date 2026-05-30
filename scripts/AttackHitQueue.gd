extends RefCounted

var timeout_seconds: float = 0.6
var _pending_hits: Array[Dictionary] = []


func _init(hit_timeout_seconds: float = 0.6) -> void:
	timeout_seconds = maxf(0.0, hit_timeout_seconds)


func clear() -> void:
	_pending_hits.clear()


func queue_hit(attack_type: int, damage: float, music_time: float) -> void:
	_pending_hits.append({
		"type": attack_type,
		"damage": damage,
		"time": music_time
	})


func take_damage_for_type(attack_type: int, music_time: float) -> float:
	cleanup(music_time)
	var hit_index: int = _find_first_hit_index(attack_type)
	if hit_index < 0:
		return 0.0

	var damage: float = float(_pending_hits[hit_index].get("damage", 0.0))
	_pending_hits.remove_at(hit_index)
	return damage


func cleanup(music_time: float) -> void:
	for i in range(_pending_hits.size() - 1, -1, -1):
		var pending_time: float = float(_pending_hits[i].get("time", 0.0))
		if music_time - pending_time > timeout_seconds:
			_pending_hits.remove_at(i)


func _find_first_hit_index(attack_type: int) -> int:
	for i in range(_pending_hits.size()):
		var pending: Dictionary = _pending_hits[i]
		if int(pending.get("type", -1)) == attack_type:
			return i
	return -1
