class_name ModifierExpiry
extends Resource
## 结束判定脚本：唯一决定“这条修正什么时候消失”的地方。
##
## 它同时也是[b]持续时间的容身处[/b]——[b]表里没有“持续时间”这个字段[/b]，
## 因为时间在局内（即时战略）和局外（回合制 / 步数制）根本不是一回事。
## 时间怎么写、按什么单位算，全部由脚本自己决定：
##
## [br]· [method advance]：宿主推进世界时调用（[method AttributeCharacter.tick] 推秒、
##   [method AttributeCharacter.advance_steps] 推回合 / 步数），脚本在这里扣自己的计时器。
## [br]· [method is_expired]：宿主每次推进后询问是否该消除。
##
## [br][b]临时修正必须挂一个非空的判定脚本[/b]（不能是基类本身），表登记时会校验。
##
## [codeblock]
## # 局外（回合 / 步数制）：持续 3 步
## extends ModifierExpiry
##
## @export var steps: int = 3
## var _left: int = -1
##
## func advance(_modifier: Resource, _character: Node, amount: float, unit: Unit) -> void:
##     if unit != Unit.STEPS:
##         return
##     if _left < 0:
##         _left = steps
##     _left = maxi(_left - int(amount), 0)
##
## func is_expired(_modifier: Resource, _character: Node) -> bool:
##     return _left == 0
## [/codeblock]

## 世界推进的单位：局内是即时战略（秒），局外是回合 / 步数。
enum Unit {
	SECONDS, ## 秒（即时制）
	STEPS, ## 回合 / 步数（回合制、步数制）
}

## 宿主推进世界时调用，脚本在这里扣自己的计时器。
## [param _amount] 推进量，[param _unit] 单位（秒 / 回合步数）。
func advance(_modifier: Resource, _character: Node, _amount: float, _unit: Unit) -> void:
	pass


## 返回 true 表示应该消除这个改动。
## [param _modifier] 是修正本体（[AttributeModifier]），[param _character] 是它所属的角色。
func is_expired(_modifier: Resource, _character: Node) -> bool:
	return false
