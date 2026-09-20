extends ModifierExpiry
## 结束判定脚本示例：角色倒地时消除这条修正。
##
## 用法：把它做成一个资源实例，填进临时修正表元素的 [member TemporaryModifier.expiry]
## （见 res://data/temporary_modifiers/blessing.tres）。
## 抄一份改 [method is_expired] 就是自己的判定脚本，例如“离开区域时消除”“san 归零时消除”；
## 要做“持续 N 秒 / N 回合”就再实现 [method ModifierExpiry.advance]
## （现成例子：expires_after_seconds.gd / expires_after_steps.gd）。

func is_expired(_modifier: Resource, character: Node) -> bool:
	var target: Character = character as Character
	return target != null and target.is_downed
