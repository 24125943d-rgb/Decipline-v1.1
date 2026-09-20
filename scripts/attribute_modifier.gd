class_name AttributeModifier
extends Resource
## 一次“属性增减”的记录。[AttributeCharacter] 按 [member kind] 决定它怎么起作用、什么时候停止。
##
## [br][b]四种作用域[/b]：
## [br]· [constant Kind.IN_RUN_TEMPORARY] 局内临时：必须挂一个非空的结束判定脚本
##   （[member expiry]），并且收到局结束信息后一定停止。
## [br]· [constant Kind.IN_RUN_PERMANENT] 局内永久：不设消除条件，持续到局结束才停止。
## [br]· [constant Kind.OUT_RUN_TEMPORARY] 局外临时：自带状态消除判定，局结束不会停止。
## [br]· [constant Kind.OUT_RUN_PERMANENT] 局外永久：[b]唯一直接作用于变量值本体的改动[/b]，
##   不进入叠加列表（等价于直接改 [member AttributeCharacter.strength] 等属性）。
##
## [codeblock]
## # 局内临时：狂暴 3 回合，STR +4
## var buff := AttributeModifier.make(AttributeModifier.Kind.IN_RUN_TEMPORARY, {AttributeCharacter.ATTR_STR: 4}, &"rage")
## # 游戏里推荐从临时修正表来（唯一合法来源）
## TemporaryModifierTable.instantiate_for(character, "虚弱")
## character.apply_modifier(buff)
## [/codeblock]

enum Kind {
	IN_RUN_TEMPORARY, ## 局内临时：自带消除判定 + 局结束必停
	IN_RUN_PERMANENT, ## 局内永久：持续到局结束
	OUT_RUN_TEMPORARY, ## 局外临时：自带消除判定，局结束不停
	OUT_RUN_PERMANENT, ## 局外永久：直接写变量本体
}

## 属性序号。顺序与 [enum AttributeCharacter.Attribute] 一一对应，不要改动。
const STR: int = 0
const DEX: int = 1
const CON: int = 2
const INT: int = 3
const WIS: int = 4
const CHM: int = 5
const ATTRIBUTE_COUNT: int = 6

@export_group("标识 / Identity")
## 来源标识：同一个 id 的非叠加改动会互相替换（刷新），也方便整批移除。
@export var id: StringName = &""
## 显示名（“狂暴”“祝福”…），只用于日志和调试。
@export var label: String = ""
## 作用域，见 [enum Kind]。
@export var kind: Kind = Kind.IN_RUN_TEMPORARY
## true = 同 id 也各自独立叠加（可叠多层）；false = 同 id 替换。
@export var stackable: bool = false

@export_group("增减 / Deltas")
## 六个属性各自的增减。变量本体是自然数，但这里的增减可以是负数。
@export var strength: int = 0
@export var dexterity: int = 0
@export var constitution: int = 0
@export var intelligence: int = 0
@export var wisdom: int = 0
@export var charisma: int = 0

@export_group("结束判定 / Expiry")
## 结束判定脚本，见 [ModifierExpiry]。[b]计时也归它管[/b]——修正本身不记录持续时间
## （局内是即时战略，局外是回合 / 步数制，时间单位由脚本自己决定）。
## 临时修正必须非空，从临时修正表登记时会校验。
@export var expiry: ModifierExpiry

# ------------------------------------------------------------------ 读写
## 取某个属性序号的增减。
func get_delta(attribute: int) -> int:
	match attribute:
		STR:
			return strength
		DEX:
			return dexterity
		CON:
			return constitution
		INT:
			return intelligence
		WIS:
			return wisdom
		CHM:
			return charisma
	return 0


## 设置某个属性序号的增减。
func set_delta(attribute: int, value: int) -> void:
	match attribute:
		STR:
			strength = value
		DEX:
			dexterity = value
		CON:
			constitution = value
		INT:
			intelligence = value
		WIS:
			wisdom = value
		CHM:
			charisma = value


## 六个增减是否全为 0。
func is_empty() -> bool:
	for i in ATTRIBUTE_COUNT:
		if get_delta(i) != 0:
			return false
	return true


## 是不是“临时”作用域（两种临时改动都必须自带消除判定）。
func is_temporary() -> bool:
	return kind == Kind.IN_RUN_TEMPORARY or kind == Kind.OUT_RUN_TEMPORARY


## 是不是局内改动（局结束信息一来就停止）。
func is_in_run() -> bool:
	return kind == Kind.IN_RUN_TEMPORARY or kind == Kind.IN_RUN_PERMANENT


## 有没有结束判定脚本（临时修正必须为 true）。
func has_expiry_rule() -> bool:
	return expiry != null


## "狂暴/stun#3" 之类的可读描述，用于日志。
func describe() -> String:
	if not label.is_empty():
		return label
	if id != StringName():
		return String(id)
	return "attribute_modifier"


## 复制一份给某个角色独占。[b]深拷贝[/b]：连结束判定脚本一起复制
## （计时器就写在脚本里），所以同一个修正施加给多个角色也不会互相干扰。
func copy_for_owner() -> AttributeModifier:
	return duplicate(true) as AttributeModifier

# ------------------------------------------------------------------ 构造
## 低层构造器（测试 / 表内部用）。
## [br][b]游戏里不要直接调这个[/b]：非永久修正唯一合法的来源是临时修正表——
## [method TemporaryModifierTable.instantiate] / [method TemporaryModifierTable.instantiate_for]。
## [param deltas] 的键是属性序号（[constant STR] … [constant CHM]）。
static func make(
	modifier_kind: Kind,
	deltas: Dictionary = {},
	source_id: StringName = &"",
	display_label: String = ""
) -> AttributeModifier:
	var modifier: AttributeModifier = AttributeModifier.new()
	modifier.kind = modifier_kind
	modifier.id = source_id
	modifier.label = display_label
	for key: Variant in deltas:
		modifier.set_delta(int(key), int(deltas[key]))
	return modifier
