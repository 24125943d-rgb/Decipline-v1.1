class_name TemporaryModifier
extends Resource
## 临时修正表（[TemporaryModifierTable]）里的一个元素：一种【数值变更型】buff / debuff 的模板。
##
## 元素本身不是修正，只是图纸——[method instantiate] 出来的 [AttributeModifier] 才是能真正施加到
## [AttributeCharacter] 身上的东西。游戏里所有非永久修正都该由
## [method TemporaryModifierTable.instantiate] / [method TemporaryModifierTable.instantiate_for] 产出。
##
## [br][b]字段一览[/b]
## [br]· [member primary_key] 主键：表内的索引（整数，唯一）
## [br]· [member name] 候选键：唯一的字符串名称，也是实例化后的来源 id 与显示名
## [br]· [member kind] 种类：前三种修正之一（局内临时 / 局内永久 / 局外临时）
## [br]· [member polarity] 正面 / 负面
## [br]· [member fixed_value] 是否固定值修正
## [br]· [member expiry] 结束判定脚本（临时修正必填，且不能是基类本身）——
##   时间相关和别的结束条件都写在它里面

## 正面还是负面。给 UI / AI / 掉落表当分类用，不参与数值结算。
enum Polarity {
	POSITIVE, ## 正面：buff
	NEGATIVE, ## 负面：debuff
}

@export_group("主键与名称")
## 主键：在临时修正表里的索引，必须 >= 0 且表内唯一。
@export var primary_key: int = -1
## 候选键：唯一的字符串名称（例："虚弱"）。实例化后也会成为修正的来源 id 与显示名。
@export var name: String = ""
## 说明，给策划和 UI 看，不参与结算。
@export var description: String = ""

@export_group("种类")
## 修正的种类：只能是前三种之一。局外永久是“直接写变量本体”的改动，不属于临时修正表。
@export var kind: AttributeModifier.Kind = AttributeModifier.Kind.IN_RUN_TEMPORARY
## 正面还是负面。
@export var polarity: Polarity = Polarity.NEGATIVE
## 是否固定值修正：true = 数值写死在这里（"虚弱"总是扣 3 点力量）；
## false = 施加时才收集参数（"镣铐"的减值由调用方传进来），下面六个增减当默认档位用。
@export var fixed_value: bool = true

@export_group("修正值")
## 力量增减（非固定值修正时作为默认档位）。
@export var strength: int = 0
## 敏捷增减。
@export var dexterity: int = 0
## 体质增减。
@export var constitution: int = 0
## 智力增减。
@export var intelligence: int = 0
## 感知增减。
@export var wisdom: int = 0
## 魅力增减。
@export var charisma: int = 0

@export_group("结束判定（临时修正必填）")
## 结束判定脚本：一个继承 [ModifierExpiry] 的资源实例——在检视器里选一个脚本，
## 参数就配在它自己身上（例如 seconds = 8.0 / steps = 3）。
## [br]表里[b]没有“持续时间”这个字段[/b]：时间怎么写、按秒还是按回合 / 步数算，
## 完全由这个脚本决定（局内是即时战略，局外是回合 / 步数制）。
@export var expiry: ModifierExpiry

# ------------------------------------------------------------------ 查询
## 取某个属性序号的增减（序号见 [enum AttributeCharacter.Attribute] / [constant AttributeModifier.STR]）。
func get_delta(attribute: int) -> int:
	match attribute:
		AttributeModifier.STR:
			return strength
		AttributeModifier.DEX:
			return dexterity
		AttributeModifier.CON:
			return constitution
		AttributeModifier.INT:
			return intelligence
		AttributeModifier.WIS:
			return wisdom
		AttributeModifier.CHM:
			return charisma
	return 0


## 设置某个属性序号的增减。
func set_delta(attribute: int, value: int) -> void:
	match attribute:
		AttributeModifier.STR:
			strength = value
		AttributeModifier.DEX:
			dexterity = value
		AttributeModifier.CON:
			constitution = value
		AttributeModifier.INT:
			intelligence = value
		AttributeModifier.WIS:
			wisdom = value
		AttributeModifier.CHM:
			charisma = value


## 正面？
func is_positive() -> bool:
	return polarity == Polarity.POSITIVE


## 负面？
func is_negative() -> bool:
	return polarity == Polarity.NEGATIVE


## 是不是两种“临时修正”（局内临时 / 局外临时）——只有它们必须自带消除规则。
func is_temporary() -> bool:
	return kind == AttributeModifier.Kind.IN_RUN_TEMPORARY or kind == AttributeModifier.Kind.OUT_RUN_TEMPORARY


## 有没有结束判定脚本。
func has_expiry_rule() -> bool:
	return expiry != null


## 结束判定脚本是否真的可用：非空、带脚本，而且不是 [ModifierExpiry] 基类本身
## （光挂基类等于没有判定，它将永远返回 false）。
func is_expiry_valid() -> bool:
	if expiry == null:
		return false
	var script: Script = expiry.get_script()
	return script != null and script != ModifierExpiry


## 这个种类能不能进临时修正表（只有前三种“非永久修正”可以）。
static func is_allowed_kind(kind: AttributeModifier.Kind) -> bool:
	return kind != AttributeModifier.Kind.OUT_RUN_PERMANENT


## "虚弱#1" 之类的可读描述，用于日志。
func describe() -> String:
	return "%s#%d" % [name, primary_key]

# ------------------------------------------------------------------ 实例化
## 造一个真正的修正（[AttributeModifier]）出来。游戏里请走
## [method TemporaryModifierTable.instantiate]，不要直接调这里。
## [br][param parameters] 只在 [member fixed_value] 为 false 时生效：属性序号 → 值，
## 会覆盖模板里的默认档位；固定值修正会忽略它。
func instantiate(parameters: Dictionary = {}) -> AttributeModifier:
	var modifier: AttributeModifier = AttributeModifier.new()
	modifier.kind = kind
	modifier.id = StringName(name)
	modifier.label = name
	modifier.expiry = _copy_expiry()
	for i in AttributeModifier.ATTRIBUTE_COUNT:
		modifier.set_delta(i, get_delta(i))
	if not fixed_value:
		for key: Variant in parameters:
			modifier.set_delta(int(key), int(parameters[key]))
	return modifier


## 每个实例拿一份独立的结束判定脚本（深拷贝）：
## 计时器写在脚本里，不能被多个修正共用。
func _copy_expiry() -> ModifierExpiry:
	if expiry == null:
		return null
	return expiry.duplicate(true) as ModifierExpiry
