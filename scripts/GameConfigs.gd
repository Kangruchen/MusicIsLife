extends Node
## 游戏配置单例 — 通过 Autoload 全局访问
## 消除 4 个节点各自 @export 引用同一资源的冗余

var sound = null
var judgment = null


func _ready() -> void:
	sound = load("res://config/game_sound_config.tres")
	judgment = load("res://config/judgment_config.tres")
