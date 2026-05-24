extends RefCounted

var _events: Array[Dictionary] = []


func clear() -> void:
	_events.clear()


func schedule(target_time: float, callback: Callable, args: Array = []) -> void:
	if not callback.is_valid():
		return
	_events.append({
		"time": target_time,
		"callback": callback,
		"args": args
	})
	_events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["time"]) < float(b["time"])
	)


func process(now: float) -> void:
	while not _events.is_empty():
		var event: Dictionary = _events[0]
		if float(event["time"]) > now:
			return
		_events.pop_front()

		var callback: Callable = event["callback"]
		if callback.is_valid():
			var args: Array = event["args"]
			callback.callv(args)
