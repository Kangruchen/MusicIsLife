extends Resource
class_name TutorialBattleConfig

enum AttackType {
	LASER,
	MISSILE,
	CHARGE,
	ALTERNATING_MISSILE_CHARGE,
}

@export var battle_id: int = 1
@export var attack_type: AttackType = AttackType.LASER
@export var required_successes: int = 4
@export var max_notes: int = 12
@export var beat_interval_beats: int = 4
@export var bpm: float = 128.0
@export var offset: float = 0.0
@export var start_delay_beats: int = 2
@export_file("*.mp3", "*.ogg", "*.wav") var music_path: String = ""
@export var camera_zoom: Vector2 = Vector2(0.6, 0.6)
@export var camera_stick_bottom: bool = false
