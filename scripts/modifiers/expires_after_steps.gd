extends ModifierExpiry
## 结束判定脚本：局外（回合制 / 步数制）按[b]回合或步数[/b]计时。
##
## 步数配在元素自己的结束判定上（见 res://data/temporary_modifiers/inspired.tres，steps = 3）。
## 宿主推回合 / 步数时（[method AttributeCharacter.advance_steps]）扣计时器。
## 表里没有“持续时间”字段——时间就是写在这里的。

## 持续多少回合 / 步。
@export var steps: int = 3

var _left: int = 0
var _started: bool = false


func advance(_modifier: Resource, _character: Node, amount: float, unit: Unit) -> void:
	if unit != Unit.STEPS:
		return
	if not _started:
		_started = true
		_left = steps
	_left = maxi(_left - int(amount), 0)


func is_expired(_modifier: Resource, _character: Node) -> bool:
	return _started and _left <= 0


## 还剩多少回合 / 步（调试 / UI 用）。
func remaining() -> int:
	return _left
