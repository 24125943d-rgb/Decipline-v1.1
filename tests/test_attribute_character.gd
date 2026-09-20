extends Node
## AttributeCharacter（有属性角色）的单元测试。
##
## 约定同测试运行器：extends Node，方法名以 test_ 开头，返回 null = 通过、字符串 = 失败原因。

const AttributeScene: PackedScene = preload("res://scenes/attribute_character.tscn")

var _failures: PackedStringArray = PackedStringArray()
var _spawned: Array[Node] = []
var _added: Array = []
var _removed: Array = []
var _changed: Array = []


## 状态消除判定脚本示例：角色倒地时消除。
class ExpiresWhenDowned:
	extends ModifierExpiry

	func is_expired(_modifier: Resource, character: Node) -> bool:
		var target: Character = character as Character
		return target != null and target.is_downed


## 状态消除判定脚本示例：永远不主动消除（用来验证其它消除路径）。
class NeverExpires:
	extends ModifierExpiry

	func is_expired(_modifier: Resource, _character: Node) -> bool:
		return false


## 状态消除判定脚本示例：按回合 / 步数计时（时间写在脚本里）。
class ExpiresAfterSteps:
	extends ModifierExpiry

	@export var steps: int = 1

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


## 状态消除判定脚本示例：按秒计时（时间写在脚本里）。
class ExpiresAfterSeconds:
	extends ModifierExpiry

	@export var seconds: float = 1.0

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


func before_each() -> void:
	_failures.clear()
	_added.clear()
	_removed.clear()
	_changed.clear()


func after_each() -> void:
	for node: Node in _spawned:
		if is_instance_valid(node):
			node.free()
	_spawned.clear()

# ------------------------------------------------------------------ 用例
func test_defaults_are_natural_numbers() -> Variant:
	var c: AttributeCharacter = _spawn()
	_check_eq(c.get_attribute(AttributeCharacter.ATTR_STR), 10, "默认 STR")
	_check_eq(c.get_attribute(AttributeCharacter.ATTR_DEX), 10, "默认 DEX")
	_check_eq(c.get_attribute(AttributeCharacter.ATTR_CON), 10, "默认 CON")
	_check_eq(c.get_attribute(AttributeCharacter.ATTR_INT), 10, "默认 INT")
	_check_eq(c.get_attribute(AttributeCharacter.ATTR_WIS), 10, "默认 WIS")
	_check_eq(c.get_attribute(AttributeCharacter.ATTR_CHM), 10, "默认 CHM")
	_check_eq(c.get_all_attributes().size(), 6, "六个属性")
	_check(c.active_modifiers.is_empty(), "一开始没有叠加改动")

	# 本体是自然数：写负数会被夹成 0
	c.strength = -5
	_check_eq(c.strength, 0, "本体被夹到 0（自然数）")
	_check_eq(c.get_attribute(AttributeCharacter.ATTR_STR), 0, "最终值也跟着 0")

	# 直接写属性 = 局外永久改动（唯一作用于变量本体的改动）
	c.strength = 14
	_check_eq(c.get_base(AttributeCharacter.ATTR_STR), 14, "直接写本体生效")
	_check_eq(c.get_attribute(AttributeCharacter.ATTR_STR), 14, "最终值 14")
	_check(c.active_modifiers.is_empty(), "直接写本体不产生叠加改动")

	c.set_base(AttributeCharacter.ATTR_CHM, -3)
	_check_eq(c.get_base(AttributeCharacter.ATTR_CHM), 0, "set_base 也夹自然数")
	return _verdict("test_defaults_are_natural_numbers")


func test_four_kinds_of_change() -> Variant:
	var c: AttributeCharacter = _spawn()
	c.begin_run(&"run_1")
	var base: int = c.get_attribute(AttributeCharacter.ATTR_STR)

	# 1) 局外永久：唯一直接写变量本体
	var outside_permanent: AttributeModifier = AttributeModifier.make(
		AttributeModifier.Kind.OUT_RUN_PERMANENT, {AttributeCharacter.ATTR_STR: 2}, &"level_up"
	)
	c.apply_modifier(outside_permanent)
	_check_eq(c.strength, base + 2, "局外永久直接改变量本体")
	_check(c.active_modifiers.is_empty(), "局外永久不进叠加列表")

	# 2) 局内永久
	var in_permanent: AttributeModifier = AttributeModifier.make(
		AttributeModifier.Kind.IN_RUN_PERMANENT, {AttributeCharacter.ATTR_STR: 3}, &"aura"
	)
	c.apply_modifier(in_permanent)

	# 3) 局内临时（回合倒计时当消除判定）
	var in_temporary: AttributeModifier = AttributeModifier.make(
		AttributeModifier.Kind.IN_RUN_TEMPORARY, {AttributeCharacter.ATTR_STR: 4}, &"rage"
	)
	in_temporary.expiry = NeverExpires.new()
	c.apply_modifier(in_temporary)

	# 4) 局外临时（自定义判定脚本）
	var out_temporary: AttributeModifier = AttributeModifier.make(
		AttributeModifier.Kind.OUT_RUN_TEMPORARY, {AttributeCharacter.ATTR_STR: 5}, &"gear"
	)
	out_temporary.expiry = NeverExpires.new()
	c.apply_modifier(out_temporary)

	_check_eq(c.get_attribute(AttributeCharacter.ATTR_STR), base + 2 + 3 + 4 + 5, "四种改动一起生效")
	_check_eq(c.strength, base + 2, "只有局外永久改了变量本体")
	_check_eq(c.active_modifiers.size(), 3, "三条叠加改动在生效")
	_check_eq(c.get_modifiers_for(AttributeCharacter.ATTR_STR).size(), 3, "get_modifiers_for")

	var breakdown: Dictionary = c.get_breakdown(AttributeCharacter.ATTR_STR)
	_check_eq(breakdown["base"], base + 2, "breakdown 本体")
	_check_eq(breakdown["in_run_temporary"], 4, "breakdown 局内临时")
	_check_eq(breakdown["in_run_permanent"], 3, "breakdown 局内永久")
	_check_eq(breakdown["out_run_temporary"], 5, "breakdown 局外临时")
	_check_eq(breakdown["modifier_total"], 12, "breakdown 叠加合计")
	_check_eq(breakdown["effective"], base + 14, "breakdown 最终值")

	# 局结束信息：局内全停，局外全留
	c.end_run()
	_check_eq(c.strength, base + 2, "局结束不改变量本体")
	_check_eq(c.get_attribute(AttributeCharacter.ATTR_STR), base + 2 + 5, "局内改动停止、局外临时保留")
	_check_eq(c.active_modifiers.size(), 1, "只剩局外临时")
	_check_eq(c.active_modifiers[0].id, &"gear", "剩下的是 gear")
	_check(not c.is_in_run, "不在局里了")
	return _verdict("test_four_kinds_of_change")


func test_in_run_temporary_always_stops_at_run_end() -> Variant:
	var c: AttributeCharacter = _spawn()
	c.modifier_removed.connect(func(m: AttributeModifier, reason: String) -> void: _removed.append([m, reason]))
	c.begin_run(&"run_x")

	# 判定脚本死活不消除，但“局结束”依然必须让它停止
	var stubborn: AttributeModifier = AttributeModifier.make(
		AttributeModifier.Kind.IN_RUN_TEMPORARY, {AttributeCharacter.ATTR_CON: 6}, &"stubborn"
	)
	stubborn.expiry = NeverExpires.new()
	c.apply_modifier(stubborn)

	_check_eq(c.get_attribute(AttributeCharacter.ATTR_CON), 16, "局内临时生效中")
	c.advance_steps(10)
	c.tick(99.0)
	_check_eq(c.get_attribute(AttributeCharacter.ATTR_CON), 16, "判定脚本说不消就不消")

	c.end_run()
	_check_eq(c.get_attribute(AttributeCharacter.ATTR_CON), 10, "局结束信息一来，局内临时一定停止")
	_check(c.active_modifiers.is_empty(), "改动被清空")
	_check_eq(_removed.size(), 1, "modifier_removed 广播了一次")
	if _removed.size() == 1:
		_check_eq(_removed[0][1], "run_end", "移除原因是 run_end")
	return _verdict("test_in_run_temporary_always_stops_at_run_end")


func test_custom_expiry_script_drives_removal() -> Variant:
	var c: AttributeCharacter = _spawn()
	var blessing: AttributeModifier = AttributeModifier.make(
		AttributeModifier.Kind.OUT_RUN_TEMPORARY, {AttributeCharacter.ATTR_WIS: 3}, &"blessing"
	)
	blessing.expiry = ExpiresWhenDowned.new()
	c.apply_modifier(blessing)
	_check_eq(c.get_attribute(AttributeCharacter.ATTR_WIS), 13, "局外临时生效")

	c.tick(0.1)
	_check_eq(c.get_attribute(AttributeCharacter.ATTR_WIS), 13, "没倒地就不消除")

	c.take_damage(999)
	_check(c.is_downed, "角色已倒地")
	c.tick(0.1)
	_check_eq(c.get_attribute(AttributeCharacter.ATTR_WIS), 10, "判定脚本说可以消除 → 改动消失")
	_check(c.active_modifiers.is_empty(), "改动被移除")
	return _verdict("test_custom_expiry_script_drives_removal")


func test_out_run_temporary_survives_run_end() -> Variant:
	var c: AttributeCharacter = _spawn()
	c.begin_run(&"run_a")
	var potion: AttributeModifier = AttributeModifier.make(
		AttributeModifier.Kind.OUT_RUN_TEMPORARY, {AttributeCharacter.ATTR_CHM: 2}, &"potion"
	)
	potion.expiry = _make_step_expiry(2)
	c.apply_modifier(potion)
	_check_eq(c.get_attribute(AttributeCharacter.ATTR_CHM), 12, "局外临时生效")

	c.end_run()
	_check_eq(c.get_attribute(AttributeCharacter.ATTR_CHM), 12, "局结束不会停局外临时")
	_check_eq(c.active_modifiers.size(), 1, "改动还在")

	c.advance_steps(2)
	_check_eq(c.get_attribute(AttributeCharacter.ATTR_CHM), 10, "步数走完 → 消除")
	return _verdict("test_out_run_temporary_survives_run_end")


func test_time_based_expiry_lives_in_the_script() -> Variant:
	var c: AttributeCharacter = _spawn()
	var haste: AttributeModifier = AttributeModifier.make(
		AttributeModifier.Kind.OUT_RUN_TEMPORARY, {AttributeCharacter.ATTR_DEX: 4}, &"haste"
	)
	haste.expiry = _make_seconds_expiry(0.5)
	c.apply_modifier(haste)
	_check_eq(c.get_attribute(AttributeCharacter.ATTR_DEX), 14, "生效")

	c.tick(0.25)
	_check_eq(c.get_attribute(AttributeCharacter.ATTR_DEX), 14, "还剩一半时间")

	# 按秒计时的脚本不该被回合 / 步数推进影响
	c.advance_steps(10)
	_check_eq(c.get_attribute(AttributeCharacter.ATTR_DEX), 14, "推步数不影响按秒计时")

	c.tick(0.3)
	_check_eq(c.get_attribute(AttributeCharacter.ATTR_DEX), 10, "秒数走完 → 消除")
	return _verdict("test_time_based_expiry_lives_in_the_script")


func test_expiry_rule_detection() -> Variant:
	var bare: AttributeModifier = AttributeModifier.make(
		AttributeModifier.Kind.OUT_RUN_TEMPORARY, {AttributeCharacter.ATTR_STR: 1}, &"bare"
	)
	_check(not bare.has_expiry_rule(), "没挂脚本 → 没有消除条件")
	_check(bare.is_temporary(), "局外临时属于临时改动")
	_check(not bare.is_empty(), "有增减")

	bare.expiry = NeverExpires.new()
	_check(bare.has_expiry_rule(), "挂了判定脚本 → 有消除条件")

	var in_permanent: AttributeModifier = AttributeModifier.make(
		AttributeModifier.Kind.IN_RUN_PERMANENT, {AttributeCharacter.ATTR_STR: 1}
	)
	_check(in_permanent.is_in_run(), "局内永久属于局内")
	_check(not in_permanent.is_temporary(), "局内永久不是临时")
	_check(not in_permanent.has_expiry_rule(), "局内永久不挂判定脚本")

	var empty_modifier: AttributeModifier = AttributeModifier.make(AttributeModifier.Kind.IN_RUN_PERMANENT)
	_check(empty_modifier.is_empty(), "没有增减的改动是空的")
	return _verdict("test_expiry_rule_detection")


func test_same_id_replaces_unless_stackable() -> Variant:
	var c: AttributeCharacter = _spawn()
	var first: AttributeModifier = AttributeModifier.make(
		AttributeModifier.Kind.OUT_RUN_TEMPORARY, {AttributeCharacter.ATTR_INT: 2}, &"focus"
	)
	first.expiry = NeverExpires.new()
	var second: AttributeModifier = AttributeModifier.make(
		AttributeModifier.Kind.OUT_RUN_TEMPORARY, {AttributeCharacter.ATTR_INT: 3}, &"focus"
	)
	second.expiry = NeverExpires.new()

	c.apply_modifier(first)
	c.apply_modifier(second)
	_check_eq(c.active_modifiers.size(), 1, "同 id 非叠加 → 替换")
	_check_eq(c.get_attribute(AttributeCharacter.ATTR_INT), 13, "只有后一条生效")

	var third: AttributeModifier = AttributeModifier.make(
		AttributeModifier.Kind.OUT_RUN_TEMPORARY, {AttributeCharacter.ATTR_INT: 1}, &"focus"
	)
	third.expiry = NeverExpires.new()
	third.stackable = true
	c.apply_modifier(third)
	_check_eq(c.active_modifiers.size(), 2, "可叠加的另算一条")
	_check_eq(c.get_attribute(AttributeCharacter.ATTR_INT), 14, "两条一起算")

	_check_eq(c.remove_modifiers_by_id(&"focus", "cleared"), 2, "按 id 批量移除")
	_check_eq(c.get_attribute(AttributeCharacter.ATTR_INT), 10, "清完回到本体")
	return _verdict("test_same_id_replaces_unless_stackable")


func test_modifier_resource_is_per_character() -> Variant:
	var a: AttributeCharacter = _spawn()
	var b: AttributeCharacter = _spawn()
	var shared: AttributeModifier = AttributeModifier.make(
		AttributeModifier.Kind.OUT_RUN_TEMPORARY, {AttributeCharacter.ATTR_STR: 2}, &"potion"
	)
	shared.expiry = _make_seconds_expiry(10.0)

	var on_a: AttributeModifier = a.apply_modifier(shared)
	var on_b: AttributeModifier = b.apply_modifier(shared)
	_check(on_a != on_b, "两个角色各拿一份独立副本")
	_check(on_a.expiry != on_b.expiry, "两份副本连判定脚本都是独立的")
	_check_eq(a.active_modifiers.size(), 1, "A 有一条")
	_check_eq(b.active_modifiers.size(), 1, "B 有一条")

	a.tick(10.0)
	_check(a.active_modifiers.is_empty(), "A 的计时走完，修正消失")
	b.tick(0.1)
	_check_eq(b.active_modifiers.size(), 1, "B 的计时器没被 A 影响")
	_check_eq(b.get_attribute(AttributeCharacter.ATTR_STR), 12, "B 的加成还在")
	return _verdict("test_modifier_resource_is_per_character")


func test_effective_value_never_goes_negative() -> Variant:
	var c: AttributeCharacter = _spawn()
	c.wisdom = 1
	var curse: AttributeModifier = AttributeModifier.make(
		AttributeModifier.Kind.OUT_RUN_TEMPORARY, {AttributeCharacter.ATTR_WIS: -5}, &"curse"
	)
	curse.expiry = NeverExpires.new()
	c.apply_modifier(curse)
	_check_eq(c.get_base(AttributeCharacter.ATTR_WIS), 1, "本体还是 1")
	_check_eq(c.get_modifier_total(AttributeCharacter.ATTR_WIS), -5, "叠加是 -5")
	_check_eq(c.get_attribute(AttributeCharacter.ATTR_WIS), 0, "最终值夹到 0（自然数）")
	_check_eq(c.get_breakdown(AttributeCharacter.ATTR_WIS)["effective"], 0, "breakdown 也是 0")
	return _verdict("test_effective_value_never_goes_negative")


func test_begin_run_clears_leftovers() -> Variant:
	var c: AttributeCharacter = _spawn()
	var leftover: AttributeModifier = AttributeModifier.make(
		AttributeModifier.Kind.IN_RUN_TEMPORARY, {AttributeCharacter.ATTR_STR: 3}, &"leftover"
	)
	leftover.expiry = NeverExpires.new()
	c.apply_modifier(leftover)

	var keep: AttributeModifier = AttributeModifier.make(
		AttributeModifier.Kind.OUT_RUN_TEMPORARY, {AttributeCharacter.ATTR_STR: 1}, &"keep"
	)
	keep.expiry = NeverExpires.new()
	c.apply_modifier(keep)

	c.begin_run(&"run_2")
	_check_eq(c.active_modifiers.size(), 1, "开新局清掉上一局的局内残留")
	_check_eq(c.active_modifiers[0].id, &"keep", "局外改动保留")
	_check_eq(c.get_attribute(AttributeCharacter.ATTR_STR), 11, "最终值只算局外那条")
	_check(c.is_in_run, "在局里")
	_check_eq(c.run_id, &"run_2", "局 id")

	_check_eq(c.clear_modifiers("cleared"), 1, "clear_modifiers 清掉全部叠加")
	_check_eq(c.get_attribute(AttributeCharacter.ATTR_STR), 10, "回到本体")
	return _verdict("test_begin_run_clears_leftovers")


func test_signals_and_broadcast() -> Variant:
	var a: AttributeCharacter = _spawn()
	var b: AttributeCharacter = _spawn()
	a.modifier_added.connect(func(m: AttributeModifier) -> void: _added.append(m))
	a.modifier_removed.connect(func(m: AttributeModifier, reason: String) -> void: _removed.append([m, reason]))
	a.attribute_changed.connect(
		func(attribute: int, base: int, effective: int) -> void: _changed.append([attribute, base, effective])
	)
	a.begin_run(&"r")
	b.begin_run(&"r")

	var dash: AttributeModifier = AttributeModifier.make(
		AttributeModifier.Kind.IN_RUN_TEMPORARY, {AttributeCharacter.ATTR_DEX: 2}, &"dash"
	)
	dash.expiry = _make_step_expiry(1)
	a.apply_modifier(dash)
	_check_eq(_added.size(), 1, "modifier_added 广播")
	_check(_changed.size() >= 1, "attribute_changed 广播")
	if not _changed.is_empty():
		var last: Array = _changed[_changed.size() - 1]
		_check_eq(last[0], AttributeCharacter.ATTR_DEX, "变化的属性是 DEX")
		_check_eq(last[1], 10, "本体值 10")
		_check_eq(last[2], 12, "最终值 12")

	a.advance_steps(1)
	_check_eq(_removed.size(), 1, "modifier_removed 广播")
	if _removed.size() == 1:
		_check_eq(_removed[0][1], "expired", "移除原因 expired")

	# 一次广播“局结束信息”，全场局内改动停止
	var a_buff: AttributeModifier = AttributeModifier.make(
		AttributeModifier.Kind.IN_RUN_PERMANENT, {AttributeCharacter.ATTR_STR: 5}, &"aura"
	)
	var b_buff: AttributeModifier = AttributeModifier.make(
		AttributeModifier.Kind.IN_RUN_PERMANENT, {AttributeCharacter.ATTR_CON: 5}, &"aura"
	)
	a.apply_modifier(a_buff)
	b.apply_modifier(b_buff)
	_check_eq(a.get_attribute(AttributeCharacter.ATTR_STR), 15, "A 的局内永久生效")

	AttributeCharacter.broadcast_run_end(get_tree())
	_check_eq(a.get_attribute(AttributeCharacter.ATTR_STR), 10, "广播后 A 的局内改动停止")
	_check_eq(b.get_attribute(AttributeCharacter.ATTR_CON), 10, "广播后 B 的局内改动停止")
	_check(not a.is_in_run and not b.is_in_run, "两个角色都出局了")
	return _verdict("test_signals_and_broadcast")


func test_scene_is_a_character_with_body() -> Variant:
	var c: AttributeCharacter = _spawn()
	_check(c is Character, "继承 Character")
	_check(c is AttributeCharacter, "是 AttributeCharacter")
	_check(c.hurtbox != null, "受击判定还在")
	_check(c.body_shape != null, "身体碰撞体还在")
	_check(c.get_node_or_null(^"Appearance/ModelRoot/PlaceholderSphere") != null, "外观挂点还在")
	_check(c.animation_player != null, "动画节点还在")
	_check(c.is_in_group(AttributeCharacter.GROUP_ATTRIBUTE_CHARACTER), "加入 attribute_character 组")

	# 继承来的能力仍然有效
	c.take_damage(999)
	_check(c.is_downed, "继承的 HP / 倒地逻辑有效")
	_check_eq(c.get_attribute(AttributeCharacter.ATTR_STR), 10, "倒地不影响属性")
	c.height = 1.2
	_check_eq(snappedf((c.body_shape.shape as CapsuleShape3D).height, 0.001), 1.2, "继承的 height 同步有效")
	return _verdict("test_scene_is_a_character_with_body")

# ------------------------------------------------------------------ 工具
func _make_step_expiry(steps: int) -> ExpiresAfterSteps:
	var expiry: ExpiresAfterSteps = ExpiresAfterSteps.new()
	expiry.steps = steps
	return expiry


func _make_seconds_expiry(seconds: float) -> ExpiresAfterSeconds:
	var expiry: ExpiresAfterSeconds = ExpiresAfterSeconds.new()
	expiry.seconds = seconds
	return expiry


func _spawn() -> AttributeCharacter:
	var character: AttributeCharacter = AttributeScene.instantiate() as AttributeCharacter
	add_child(character)
	_spawned.append(character)
	return character


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)


func _check_eq(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s（期望 %s，实际 %s）" % [label, expected, actual])


func _verdict(test_name: String) -> Variant:
	if _failures.is_empty():
		print("PASS  ", test_name)
		return null
	var message: String = ""
	for failure: String in _failures:
		message += "\n   - " + failure
	print("FAIL  ", test_name, message)
	return message
