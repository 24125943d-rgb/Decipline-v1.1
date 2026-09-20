class_name AttributeCharacter
extends Character
## 有属性角色：在 [Character] 之上加六个自然数属性
## [b]STR 力量 / DEX 敏捷 / CON 体质 / INT 智力 / WIS 感知 / CHM 魅力[/b]。
##
## 每个属性的[b]变量本体[/b]就是类里直接写着的那六个属性（[member strength] … [member charisma]，
## 默认 10，自然数，永远 >= 0）。读[b]最终值[/b]用 [method get_attribute]，
## 它 = 本体 + 所有生效的叠加改动。
##
## [br][b]四种增减[/b]（见 [enum AttributeModifier.Kind]、[method apply_modifier]）：
## [br]· [b]局内临时[/b]：必须挂一个非空的结束判定脚本（[member AttributeModifier.expiry]），
##   并且收到局结束信息后[b]一定停止[/b]。
## [br]· [b]局内永久[/b]：不设消除条件，一直生效到局结束才停止。
## [br]· [b]局外临时[/b]：自带状态消除判定，[b]不会因为局结束而停止[/b]。
## [br]· [b]局外永久[/b]：[b]唯一直接作用于变量值本体的改动[/b]（直接改属性 / 传这个 kind 进来），
##   不进入叠加列表，也不受局结束影响。
##
## [br][b]“局结束信息”[/b]：调 [method end_run]，或用 [method broadcast_run_end] 一次通知全场。
##
## [br][b]六个属性的具体效果还没定[/b]：[method _on_attribute_changed] 是留空的钩子，
## 将来所有效果（命中、闪避、负重、学习…）都接在那里。
##
## [codeblock]
## var buff := AttributeModifier.make(AttributeModifier.Kind.IN_RUN_TEMPORARY, {ATTR_STR: 4}, &"rage")
## # 推荐：从临时修正表来（唯一合法来源）
## TemporaryModifierTable.instantiate_for(character, "虚弱")
## print(character.get_attribute(ATTR_STR))   # 本体 + 4
## [/codeblock]

## 属性落地时广播：属性序号、本体值、最终值。
signal attribute_changed(attribute: int, base_value: int, effective_value: int)
## 有叠加改动被施加（局外永久不广播这个——它直接写本体）。
signal modifier_added(modifier: AttributeModifier)
## 有叠加改动被移除。reason 见 [method remove_modifier]。
signal modifier_removed(modifier: AttributeModifier, reason: String)
## 一局开始。
signal run_started(run_id: StringName)
## 收到局结束信息（局内改动已经停止）。
signal run_ended(run_id: StringName)

## 六个属性。[b]顺序不能改[/b]：存档、[AttributeModifier] 的增减都按这个序号。
enum Attribute {
	STR, ## 力量
	DEX, ## 敏捷
	CON, ## 体质
	INT, ## 智力
	WIS, ## 感知
	CHM, ## 魅力
}

## 属性个数，遍历用。
const ATTRIBUTE_COUNT: int = 6
## 六个属性的默认本体值。
const DEFAULT_ATTRIBUTE_VALUE: int = 10
## 所有有属性角色所在的组，[method broadcast_run_end] 靠它广播。
const GROUP_ATTRIBUTE_CHARACTER: StringName = &"attribute_character"

## 便捷别名，和 [enum Attribute] 等价。
const ATTR_STR: int = Attribute.STR
const ATTR_DEX: int = Attribute.DEX
const ATTR_CON: int = Attribute.CON
const ATTR_INT: int = Attribute.INT
const ATTR_WIS: int = Attribute.WIS
const ATTR_CHM: int = Attribute.CHM

# ------------------------------------------------------------------ 变量本体
@export_group("属性本体 / Base Values")
## 变量本体：力量。只有“局外永久改动”会直接写这里。
@export var strength: int:
	get:
		return _body[Attribute.STR]
	set(value):
		set_base(Attribute.STR, value)

## 变量本体：敏捷。
@export var dexterity: int:
	get:
		return _body[Attribute.DEX]
	set(value):
		set_base(Attribute.DEX, value)

## 变量本体：体质。
@export var constitution: int:
	get:
		return _body[Attribute.CON]
	set(value):
		set_base(Attribute.CON, value)

## 变量本体：智力。
@export var intelligence: int:
	get:
		return _body[Attribute.INT]
	set(value):
		set_base(Attribute.INT, value)

## 变量本体：感知。
@export var wisdom: int:
	get:
		return _body[Attribute.WIS]
	set(value):
		set_base(Attribute.WIS, value)

## 变量本体：魅力。
@export var charisma: int:
	get:
		return _body[Attribute.CHM]
	set(value):
		set_base(Attribute.CHM, value)

# ------------------------------------------------------------------ 状态
## 当前生效的叠加改动（不含局外永久——那个直接写本体）。不要直接改这个数组。
var active_modifiers: Array[AttributeModifier] = []
## 是不是在一局里。
var is_in_run: bool = false
## 当前局 id，由 [method begin_run] 传入、[method end_run] 清空。
var run_id: StringName = &""

var _body: Array[int] = [
	DEFAULT_ATTRIBUTE_VALUE,
	DEFAULT_ATTRIBUTE_VALUE,
	DEFAULT_ATTRIBUTE_VALUE,
	DEFAULT_ATTRIBUTE_VALUE,
	DEFAULT_ATTRIBUTE_VALUE,
	DEFAULT_ATTRIBUTE_VALUE,
]

# ------------------------------------------------------------------ 生命周期
func _ready() -> void:
	super()
	add_to_group(GROUP_ATTRIBUTE_CHARACTER)
	_update_processing()
	# 初始同步：让 UI / 其它系统一开始就能拿到六个属性
	for i in ATTRIBUTE_COUNT:
		_notify_attribute(i)


func _process(delta: float) -> void:
	tick(delta)

# ------------------------------------------------------------------ 读
## 变量本体（只有局外永久改动能改它）。
func get_base(attribute: int) -> int:
	return _body[_attribute_index(attribute)]


## 三种叠加改动的合计（局内临时 + 局内永久 + 局外临时）。
func get_modifier_total(attribute: int) -> int:
	var index: int = _attribute_index(attribute)
	var total: int = 0
	for modifier: AttributeModifier in active_modifiers:
		total += modifier.get_delta(index)
	return total


## 最终值 = 本体 + 叠加改动，[b]保证是自然数[/b]（不会低于 0）。
func get_attribute(attribute: int) -> int:
	var index: int = _attribute_index(attribute)
	return maxi(_body[index] + get_modifier_total(index), 0)


## 拆开看某个属性：[code]{base, in_run_temporary, in_run_permanent, out_run_temporary, modifier_total, effective}[/code]。
func get_breakdown(attribute: int) -> Dictionary:
	var index: int = _attribute_index(attribute)
	var in_run_temporary: int = 0
	var in_run_permanent: int = 0
	var out_run_temporary: int = 0
	for modifier: AttributeModifier in active_modifiers:
		var delta: int = modifier.get_delta(index)
		match modifier.kind:
			AttributeModifier.Kind.IN_RUN_TEMPORARY:
				in_run_temporary += delta
			AttributeModifier.Kind.IN_RUN_PERMANENT:
				in_run_permanent += delta
			AttributeModifier.Kind.OUT_RUN_TEMPORARY:
				out_run_temporary += delta
	return {
		"base": _body[index],
		"in_run_temporary": in_run_temporary,
		"in_run_permanent": in_run_permanent,
		"out_run_temporary": out_run_temporary,
		"modifier_total": in_run_temporary + in_run_permanent + out_run_temporary,
		"effective": get_attribute(index),
	}


## 六个属性的最终值，键是 [enum Attribute]。做 UI 很方便。
func get_all_attributes() -> Dictionary:
	var result: Dictionary = {}
	for i in ATTRIBUTE_COUNT:
		result[i] = get_attribute(i)
	return result


## 某个属性的生效改动列表（只读副本）。
func get_modifiers_for(attribute: int) -> Array[AttributeModifier]:
	var result: Array[AttributeModifier] = []
	var index: int = _attribute_index(attribute)
	for modifier: AttributeModifier in active_modifiers:
		if modifier.get_delta(index) != 0:
			result.append(modifier)
	return result

# ------------------------------------------------------------------ 写：本体
## [b]直接改变量本体[/b]——按设计只有“局外永久改动”该走这里（或直接写 [member strength] 等属性）。
## 会自动夹成自然数（>= 0）。
func set_base(attribute: int, value: int) -> void:
	var index: int = _attribute_index(attribute)
	var clamped: int = maxi(value, 0)
	if _body[index] == clamped:
		return
	_body[index] = clamped
	_notify_attribute(index)

# ------------------------------------------------------------------ 写：增减
## 施加一次属性增减，四种作用域都走这个入口。
## [br]· 局外永久：直接写变量本体，返回传进来的那个对象，不进叠加列表。
## [br]· 其它三种：复制一份挂到本角色身上（剩余倒计时逐角色维护，不能共用同一个 Resource），
##   返回真正生效的那一份——想手动移除请拿这个返回值。
func apply_modifier(modifier: AttributeModifier) -> AttributeModifier:
	if modifier == null:
		return null

	if modifier.kind == AttributeModifier.Kind.OUT_RUN_PERMANENT:
		for i in ATTRIBUTE_COUNT:
			var delta: int = modifier.get_delta(i)
			if delta != 0:
				set_base(i, _body[i] + delta)
		return modifier

	var stored: AttributeModifier = modifier.copy_for_owner()
	if not stored.stackable and stored.id != StringName():
		remove_modifiers_by_id(stored.id, "replaced")

	active_modifiers.append(stored)
	modifier_added.emit(stored)
	_warn_if_never_expires(stored)
	_update_processing()
	_notify_modifier_deltas(stored)
	return stored


## 移除一个叠加改动。reason 常见值："expired"（判定脚本/倒计时）、"run_end"、
## "replaced"（同 id 替换）、"cleared"、"manual"。
func remove_modifier(modifier: AttributeModifier, reason: String = "manual") -> bool:
	if modifier == null:
		return false
	var index: int = active_modifiers.find(modifier)
	if index < 0:
		return false
	active_modifiers.remove_at(index)
	modifier_removed.emit(modifier, reason)
	_update_processing()
	_notify_modifier_deltas(modifier)
	return true


## 按来源 id 批量移除，返回移除数量。
func remove_modifiers_by_id(id: StringName, reason: String = "manual") -> int:
	if id == StringName():
		return 0
	var doomed: Array[AttributeModifier] = []
	for modifier: AttributeModifier in active_modifiers:
		if modifier.id == id:
			doomed.append(modifier)
	for modifier: AttributeModifier in doomed:
		remove_modifier(modifier, reason)
	return doomed.size()


## 清掉全部叠加改动（局外的也清）。局外永久改动写在本体上，不受影响。
func clear_modifiers(reason: String = "cleared") -> int:
	var doomed: Array[AttributeModifier] = active_modifiers.duplicate()
	for modifier: AttributeModifier in doomed:
		remove_modifier(modifier, reason)
	return doomed.size()


## 清掉全部[b]局内[/b]改动（局内临时 + 局内永久）。局外改动不受影响。
func clear_in_run_modifiers(reason: String = "run_end") -> int:
	var doomed: Array[AttributeModifier] = []
	for modifier: AttributeModifier in active_modifiers:
		if modifier.is_in_run():
			doomed.append(modifier)
	for modifier: AttributeModifier in doomed:
		remove_modifier(modifier, reason)
	return doomed.size()

# ------------------------------------------------------------------ 一局的生命周期
## 开一局。会先把上一局的残留局内改动清掉（兜底）。
func begin_run(id: StringName = &"") -> void:
	clear_in_run_modifiers("run_start")
	is_in_run = true
	run_id = id
	run_started.emit(run_id)


## 收到[b]局结束信息[/b]：局内改动（临时 + 永久）立刻停止，局外改动全部保留。
func end_run() -> void:
	var finished: StringName = run_id
	clear_in_run_modifiers("run_end")
	is_in_run = false
	run_id = &""
	run_ended.emit(finished)


## 把“局结束信息”广播给当前场景树里所有 [AttributeCharacter]。
static func broadcast_run_end(tree: SceneTree) -> void:
	if tree == null:
		return
	for node: Node in tree.get_nodes_in_group(GROUP_ATTRIBUTE_CHARACTER):
		var character: AttributeCharacter = node as AttributeCharacter
		if character != null:
			character.end_run()

# ------------------------------------------------------------------ 推进时间
## 推进[b]秒[/b]（局内即时战略用）：把时间交给每个结束判定脚本，再问一遍要不要消除。
## 一般不用手动调（[method _process] 会自动按帧推进）。
func tick(delta_seconds: float) -> void:
	if active_modifiers.is_empty() or delta_seconds <= 0.0:
		return
	for modifier: AttributeModifier in active_modifiers:
		if modifier.expiry != null:
			modifier.expiry.advance(modifier, self, delta_seconds, ModifierExpiry.Unit.SECONDS)
	_expire_due()


## 推进[b]回合 / 步数[/b]（局外回合制、步数制用）：同样交给结束判定脚本，再问一遍。
func advance_steps(steps: int = 1) -> void:
	if active_modifiers.is_empty() or steps <= 0:
		return
	for modifier: AttributeModifier in active_modifiers:
		if modifier.expiry != null:
			modifier.expiry.advance(modifier, self, float(steps), ModifierExpiry.Unit.STEPS)
	_expire_due()

# ------------------------------------------------------------------ 钩子（效果留空）
## 六个属性的[b]具体效果还没定[/b]，这里是留空的钩子。
## 任何改动（本体或增减）落地后都会带最新最终值调用一次；将来所有效果都接在这里，
## 也可以由子类覆盖。
func _on_attribute_changed(_attribute: int, _effective_value: int) -> void:
	pass

# ------------------------------------------------------------------ 内部
func _attribute_index(attribute: int) -> int:
	return clampi(attribute, 0, ATTRIBUTE_COUNT - 1)


func _expire_due() -> void:
	var doomed: Array[AttributeModifier] = []
	for modifier: AttributeModifier in active_modifiers:
		if _is_expired(modifier):
			doomed.append(modifier)
	for modifier: AttributeModifier in doomed:
		remove_modifier(modifier, "expired")


## 只问结束判定脚本。没有挂脚本的改动不会自己消失（施加时会警告）。
func _is_expired(modifier: AttributeModifier) -> bool:
	if modifier.expiry == null:
		return false
	return modifier.expiry.is_expired(modifier, self)


## 只有“还需要逐帧看时间”的改动才开 _process（纯回合制的不用）。
func _update_processing() -> void:
	var needed: bool = false
	for modifier: AttributeModifier in active_modifiers:
		if modifier.expiry != null:
			needed = true
			break
	set_process(needed)


func _notify_attribute(attribute: int) -> void:
	if not is_node_ready():
		return
	var index: int = _attribute_index(attribute)
	attribute_changed.emit(index, _body[index], get_attribute(index))
	_on_attribute_changed(index, get_attribute(index))


func _notify_modifier_deltas(modifier: AttributeModifier) -> void:
	for i in ATTRIBUTE_COUNT:
		if modifier.get_delta(i) != 0:
			_notify_attribute(i)


func _warn_if_never_expires(modifier: AttributeModifier) -> void:
	if not modifier.is_temporary() or modifier.has_expiry_rule():
		return
	push_warning(
		(
			"AttributeCharacter: 临时改动 '%s' 既没有倒计时也没有状态消除判定脚本，它不会自己消失。"
			% modifier.describe()
		)
	)
