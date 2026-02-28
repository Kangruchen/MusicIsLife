extends Resource
class_name TrackAnimationConfig
## 轨道动画配置 - 定义每种音符类型生成时自动播放的动画
## 每个轨道可独立配置动画场景、动画名称和播放位置
## 未配置则使用默认 Bling 特效

# === GUARD 轨道（2拍，J键） ===
@export_group("GUARD 轨道动画")
## 预警场景（在主动画前1拍显示），为 null 时不显示预警
@export var guard_warn_scene: PackedScene = null
## 自定义动画场景（需包含 AnimatedSprite2D 子节点），为 null 时使用默认 Bling
@export var guard_scene: PackedScene = null
## 自定义动画名称，为空时使用默认 Bling 动画名 (bling_blue)
@export var guard_animation_name: String = ""
## 攻击结束帧（从 0 计）：动画以原始速度播放，通过延迟启动使该帧恰好在判定时刻开始播放。设为 -1 则不做对齐，立即以原始速度播放
@export var guard_attack_end_frame: int = -1

# === HIT 轨道（3拍，I键） ===
@export_group("HIT 轨道动画")
## 预警场景（在主动画前1拍显示），为 null 时不显示预警
@export var hit_warn_scene: PackedScene = null
## 自定义动画场景（需包含 AnimatedSprite2D 子节点），为 null 时使用默认 Bling
@export var hit_scene: PackedScene = null
## 自定义动画名称，为空时使用默认 Bling 动画名 (bling_red)
@export var hit_animation_name: String = ""
## 攻击结束帧（从 0 计）：动画以原始速度播放，通过延迟启动使该帧恰好在判定时刻开始播放。设为 -1 则不做对齐，立即以原始速度播放
@export var hit_attack_end_frame: int = -1

# === DODGE 轨道（4拍） ===
@export_group("DODGE 轨道动画")
## 预警场景（在主动画前1拍显示），为 null 时不显示预警
@export var dodge_warn_scene: PackedScene = null
## 自定义动画场景（需包含 AnimatedSprite2D 子节点），为 null 时使用默认 Bling
@export var dodge_scene: PackedScene = null
## 自定义动画名称，为空时使用默认 Bling 动画名 (bling_green)
@export var dodge_animation_name: String = ""
## 攻击结束帧（从 0 计）：动画以原始速度播放，通过延迟启动使该帧恰好在判定时刻开始播放。设为 -1 则不做对齐，立即以原始速度播放
@export var dodge_attack_end_frame: int = -1


## 获取指定音符类型的预警场景，未配置返回 null
func get_warn_scene(note_type: Note.NoteType) -> PackedScene:
	match note_type:
		Note.NoteType.GUARD:
			return guard_warn_scene
		Note.NoteType.HIT:
			return hit_warn_scene
		Note.NoteType.DODGE:
			return dodge_warn_scene
	return null


## 获取指定音符类型的动画场景，未配置返回 null
func get_scene(note_type: Note.NoteType) -> PackedScene:
	match note_type:
		Note.NoteType.GUARD:
			return guard_scene
		Note.NoteType.HIT:
			return hit_scene
		Note.NoteType.DODGE:
			return dodge_scene
	return null


## 获取指定音符类型的动画名称，未配置返回空字符串
func get_animation_name(note_type: Note.NoteType) -> String:
	match note_type:
		Note.NoteType.GUARD:
			return guard_animation_name
		Note.NoteType.HIT:
			return hit_animation_name
		Note.NoteType.DODGE:
			return dodge_animation_name
	return ""


## 获取指定音符类型的攻击结束帧索引，-1 表示不设置（全帧均在目标拍数内播完）
func get_attack_end_frame(note_type: Note.NoteType) -> int:
	match note_type:
		Note.NoteType.GUARD:
			return guard_attack_end_frame
		Note.NoteType.HIT:
			return hit_attack_end_frame
		Note.NoteType.DODGE:
			return dodge_attack_end_frame
	return -1
