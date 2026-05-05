extends Resource
class_name DialogueLine

@export var speaker_name: String = "旁白"
@export_multiline var content: String = ""
@export var avatar: Texture2D = null # 放主角头像。如果是旁白可以留空(null)