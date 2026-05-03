extends Resource
class_name RandomSoundPool
## 随机音效池 - 从多个 SoundEntry 中随机选取一条播放
## 每个配置项可挂载多个候选音效，播放时随机挑选，增加听觉丰富度

@export var sounds: Array[SoundEntry] = []


func pick_random() -> SoundEntry:
	if sounds.is_empty():
		return null
	return sounds.pick_random()


func is_empty() -> bool:
	return sounds.is_empty()
