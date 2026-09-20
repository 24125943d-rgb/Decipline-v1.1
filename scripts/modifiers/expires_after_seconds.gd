extends ModifierExpiry
## 结束判定脚本：局内（即时战略）按[b]秒[/b]计时。
##
## 秒数配在元素自己的结束判定上（见 res://data/temporary_modifiers/weakness.tres，seconds = 8.0）。
## 宿主推秒时（[method AttributeCharacter.tick]，或 [method _process] 自动按帧推）扣计时器。
## 表里没有“持续时间”字段——时间就是写在这里的。

## 持续多少秒。
@export var seconds: float = 8.0

var _left: float = 0.0
var _started: bool = false


func advance(_modifier: Resource, _character: Node, amount: float, unit: Unit) -> void:
	if unit != Unit.SECONDS:
		return
	if not _started:
		_started = true
		_left = seconds
	_left = maxf(_left - amount, 0.0)


func is_expired(_modifier: Resource, _character: Node) -> bool:
	return _started and _left <= 0.0


## 还剩多少秒（调试 / UI 用）。
func remaining() -> float:
	return _left
