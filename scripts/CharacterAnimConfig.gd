extends Resource
class_name CharacterAnimConfig
## 角色动画配置 - 定义防御阶段和攻击阶段各动作对应的动画名称
## 动画名称会优先在 AnimatedSprite2D 中查找，若不存在则尝试 AnimationPlayer

# === 防御阶段动画 ===
@export_group("防御阶段")
## 格挡动画（GUARD 轨道，J键）
@export var guard_anim: String = ""
## 攻击动画（HIT 轨道，I键）
@export var hit_anim: String = ""
## 闪避动画（DODGE 轨道，L键）
@export var dodge_anim: String = ""

# === 攻击阶段动画 ===
@export_group("攻击阶段")
## 轻攻击动画（J键/GUARD）
@export var light_attack_anim: String = ""
## 重攻击动画（I键/HIT）
@export var heavy_attack_anim: String = ""
## 蓄力动画（无输入时自动触发）
@export var charge_anim: String = ""
## 恢复动画（L键/DODGE）
@export var heal_anim: String = ""

# === 基础动画 ===
@export_group("基础")
## 待机动画名称
@export var idle_anim: String = "idle"


## 获取防御阶段动画名称
func get_defense_anim(track: Note.NoteType) -> String:
	match track:
		Note.NoteType.GUARD: return guard_anim
		Note.NoteType.HIT:   return hit_anim
		Note.NoteType.DODGE: return dodge_anim
	return ""


## 获取攻击阶段动画名称（参数为 InputManager.AttackType 的 int 值）
func get_attack_anim(attack_type: int) -> String:
	match attack_type:
		0: return light_attack_anim   # LIGHT
		1: return heavy_attack_anim   # HEAVY
		2: return heal_anim           # HEAL
		3: return charge_anim         # ENHANCE
	return ""
