extends Node
## 临时修正表（TemporaryModifierTable / TemporaryModifier）的单元测试。
##
## 约定同测试运行器：extends Node，方法名以 test_ 开头，返回 null = 通过、字符串 = 失败原因。

const AttributeScene: PackedScene = preload("res://scenes/attribute_character.tscn")
const DownedExpiry: GDScript = preload("res://scripts/modifiers/expires_when_downed.gd")
const TABLE_DIR: String = "res://data/temporary_modifiers"


## 判定脚本示例：永远不主动消除。
class NeverExpires:
	extends ModifierExpiry

	func is_expired(_modifier: Resource, _character: Node) -> bool:
		return false


## 判定脚本示例：按回合 / 步数计时（时间写在脚本里）。
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


## 判定脚本示例：按秒计时（时间写在脚本里）。
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

var _failures: PackedStringArray = PackedStringArray()
var _spawned: Array[Node] = []


func before_each() -> void:
	_failures.clear()
	# 先消费掉“首次自动装载”，再清空 → 每个用例都从一张空表开始
	TemporaryModifierTable.ensure_loaded()
	TemporaryModifierTable.clear()


func after_each() -> void:
	for node: Node in _spawned:
		if is_instance_valid(node):
			node.free()
	_spawned.clear()
	TemporaryModifierTable.clear()

# ------------------------------------------------------------------ 用例
func test_register_and_lookup() -> Variant:
	var entry: TemporaryModifier = _make_entry(1, "虚弱")
	entry.strength = -3
	_check(TemporaryModifierTable.register(entry).is_empty(), "登记成功返回空字符串")

	_check(TemporaryModifierTable.has(1), "按主键能查到")
	_check(TemporaryModifierTable.has("虚弱"), "按候选键能查到")
	_check(TemporaryModifierTable.find(1) == entry, "find(主键) 拿到同一个元素")
	_check(TemporaryModifierTable.find("虚弱") == entry, "find(候选键) 拿到同一个元素")
	_check_eq(TemporaryModifierTable.size(), 1, "表里一个元素")
	_check_eq(TemporaryModifierTable.keys(), [1] as Array[int], "keys")
	_check_eq(TemporaryModifierTable.names(), PackedStringArray(["虚弱"]), "names")
	_check(TemporaryModifierTable.find(99) == null, "查不到的主键返回 null")
	_check(TemporaryModifierTable.find("不存在") == null, "查不到的候选键返回 null")
	_check(TemporaryModifierTable.find_by_key(1) == entry, "find_by_key")
	_check(TemporaryModifierTable.find_by_name("虚弱") == entry, "find_by_name")
	return _verdict("test_register_and_lookup")


func test_register_rejects_bad_keys() -> Variant:
	_check(TemporaryModifierTable.register(_make_entry(1, "虚弱")).is_empty(), "第一个登记成功")

	var duplicate_key: TemporaryModifier = _make_entry(1, "别的名字")
	_check(not TemporaryModifierTable.register(duplicate_key).is_empty(), "主键重复被拒绝")
	var duplicate_name: TemporaryModifier = _make_entry(2, "虚弱")
	_check(not TemporaryModifierTable.register(duplicate_name).is_empty(), "候选键重复被拒绝")
	var negative_key: TemporaryModifier = _make_entry(-1, "负数主键")
	_check(not TemporaryModifierTable.register(negative_key).is_empty(), "负数主键被拒绝")
	var no_name: TemporaryModifier = _make_entry(3, "")
	_check(not TemporaryModifierTable.register(no_name).is_empty(), "没有候选键被拒绝")
	_check(not TemporaryModifierTable.register(null).is_empty(), "空元素被拒绝")
	_check_eq(TemporaryModifierTable.size(), 1, "被拒绝的都没进表")
	return _verdict("test_register_rejects_bad_keys")


func test_table_rules_for_kinds() -> Variant:
	# 局外永久改动是“直接写变量本体”的，不属于临时修正表
	var outside_permanent: TemporaryModifier = _make_entry(1, "升级", AttributeModifier.Kind.OUT_RUN_PERMANENT)
	outside_permanent.expiry = null
	_check(not TemporaryModifierTable.register(outside_permanent).is_empty(), "局外永久改动进不了临时修正表")

	# 临时修正必须挂一个非空的结束判定脚本
	var no_script: TemporaryModifier = _make_entry(2, "没有判定的临时", AttributeModifier.Kind.IN_RUN_TEMPORARY)
	no_script.expiry = null
	_check(not TemporaryModifierTable.register(no_script).is_empty(), "临时修正没挂判定脚本 → 拒绝")

	var base_only: TemporaryModifier = _make_entry(3, "只挂了基类", AttributeModifier.Kind.IN_RUN_TEMPORARY)
	base_only.expiry = ModifierExpiry.new()
	_check(not base_only.is_expiry_valid(), "光挂基类不算有效判定")
	_check(not TemporaryModifierTable.register(base_only).is_empty(), "只挂 ModifierExpiry 基类 → 拒绝")

	var real_script: TemporaryModifier = _make_entry(4, "挂了真脚本", AttributeModifier.Kind.IN_RUN_TEMPORARY)
	real_script.expiry = _make_step_expiry(2)
	_check(real_script.is_expiry_valid(), "真脚本算有效判定")
	_check(TemporaryModifierTable.register(real_script).is_empty(), "有判定脚本就能进表")

	# 局内永久是“一直生效到局结束”，不该挂判定脚本
	var run_permanent: TemporaryModifier = _make_entry(5, "战意", AttributeModifier.Kind.IN_RUN_PERMANENT)
	_check(not TemporaryModifierTable.register(run_permanent).is_empty(), "局内永久挂了判定脚本 → 拒绝")
	run_permanent.expiry = null
	_check(TemporaryModifierTable.register(run_permanent).is_empty(), "去掉判定脚本就能进表")

	# 局外临时同样必须挂判定脚本（局结束不停是宿主的行为，不是登记规则）
	var out_temporary: TemporaryModifier = _make_entry(6, "鼓舞", AttributeModifier.Kind.OUT_RUN_TEMPORARY)
	out_temporary.expiry = DownedExpiry.new()
	_check(TemporaryModifierTable.register(out_temporary).is_empty(), "局外临时挂了判定脚本 → 通过")

	_check_eq(TemporaryModifierTable.size(), 3, "表里 3 个元素")
	return _verdict("test_table_rules_for_kinds")


func test_instantiate_fixed_value() -> Variant:
	var entry: TemporaryModifier = _make_entry(1, "虚弱")
	entry.strength = -3
	entry.expiry = _make_seconds_expiry(8.0)
	_check(TemporaryModifierTable.register(entry).is_empty(), "登记成功")

	var modifier: AttributeModifier = TemporaryModifierTable.instantiate(1)
	_check(modifier != null, "按主键实例化成功")
	if modifier == null:
		return _verdict("test_instantiate_fixed_value")
	_check_eq(modifier.kind, AttributeModifier.Kind.IN_RUN_TEMPORARY, "种类继承")
	_check_eq(modifier.strength, -3, "固定值取自模板")
	_check(modifier.expiry != null, "继承了结束判定脚本")
	_check(modifier.expiry != entry.expiry, "判定脚本是复制出来的，不与模板共用")
	_check_eq(modifier.expiry.get(&"seconds"), 8.0, "脚本上的参数一起继承")
	_check_eq(modifier.id, &"虚弱", "来源 id = 候选键")
	_check_eq(modifier.label, "虚弱", "显示名 = 候选键")
	_check(modifier.expiry is ModifierExpiry, "判定脚本实例类型正确")

	var by_name: AttributeModifier = TemporaryModifierTable.instantiate("虚弱")
	_check(by_name != null, "按候选键也能实例化")
	_check(by_name != modifier, "每次实例化都是一个新对象")

	var with_parameters: AttributeModifier = TemporaryModifierTable.instantiate(
		1, {AttributeCharacter.ATTR_STR: -99}
	)
	_check_eq(with_parameters.strength, -3, "固定值修正忽略传进来的参数")
	return _verdict("test_instantiate_fixed_value")


func test_instantiate_with_parameters() -> Variant:
	var entry: TemporaryModifier = _make_entry(2, "镣铐")
	entry.fixed_value = false
	entry.strength = -2
	_check(TemporaryModifierTable.register(entry).is_empty(), "登记成功")

	var default_modifier: AttributeModifier = TemporaryModifierTable.instantiate(2)
	_check_eq(default_modifier.strength, -2, "不传参数 → 用模板默认档位")

	var custom: AttributeModifier = TemporaryModifierTable.instantiate(2, {AttributeCharacter.ATTR_STR: -5})
	_check_eq(custom.strength, -5, "传参数 → 覆盖默认档位")
	_check_eq(custom.dexterity, 0, "没提到的属性不受影响")
	_check(custom.expiry != null, "结束判定脚本也复制给了实例")
	_check_eq(default_modifier.strength, -2, "两个实例互不影响")
	return _verdict("test_instantiate_with_parameters")


func test_expiry_script_is_mandatory_and_works() -> Variant:
	var entry: TemporaryModifier = _make_entry(3, "鼓舞", AttributeModifier.Kind.OUT_RUN_TEMPORARY)
	entry.polarity = TemporaryModifier.Polarity.POSITIVE
	entry.wisdom = 2
	entry.expiry = DownedExpiry.new()
	_check(TemporaryModifierTable.register(entry).is_empty(), "带结束判定脚本的元素能进表")

	var modifier: AttributeModifier = TemporaryModifierTable.instantiate(3)
	_check(modifier.expiry != null, "实例拿到了结束判定脚本的实例")
	_check(modifier.expiry is ModifierExpiry, "判定脚本继承自 ModifierExpiry")

	var character: AttributeCharacter = _spawn()
	var applied: AttributeModifier = TemporaryModifierTable.instantiate_for(character, 3)
	_check(applied != null, "instantiate_for 返回生效的那一份")
	_check_eq(character.get_attribute(AttributeCharacter.ATTR_WIS), 12, "施加后感知 +2")
	_check_eq(character.active_modifiers.size(), 1, "挂在角色身上的叠加改动")

	character.tick(0.1)
	_check_eq(character.get_attribute(AttributeCharacter.ATTR_WIS), 12, "没倒地就不消除")
	character.take_damage(999)
	_check(character.is_downed, "角色已倒地")
	character.tick(0.1)
	_check_eq(character.get_attribute(AttributeCharacter.ATTR_WIS), 10, "判定脚本指针生效：倒地即消除")
	return _verdict("test_expiry_script_is_mandatory_and_works")


func test_queries_and_unregister() -> Variant:
	var negative: TemporaryModifier = _make_entry(1, "虚弱")
	negative.strength = -3
	var positive: TemporaryModifier = _make_entry(2, "祝福")
	positive.polarity = TemporaryModifier.Polarity.POSITIVE
	positive.wisdom = 2
	var run_permanent: TemporaryModifier = _make_entry(3, "战意", AttributeModifier.Kind.IN_RUN_PERMANENT)
	run_permanent.expiry = null
	TemporaryModifierTable.register(negative)
	TemporaryModifierTable.register(positive)
	TemporaryModifierTable.register(run_permanent)

	_check_eq(TemporaryModifierTable.size(), 3, "三个元素")
	_check_eq(
		TemporaryModifierTable.find_by_polarity(TemporaryModifier.Polarity.NEGATIVE).size(), 2, "两个负面"
	)
	_check_eq(
		TemporaryModifierTable.find_by_polarity(TemporaryModifier.Polarity.POSITIVE).size(), 1, "一个正面"
	)
	_check_eq(
		TemporaryModifierTable.find_by_kind(AttributeModifier.Kind.IN_RUN_PERMANENT).size(), 1, "一个局内永久"
	)
	_check_eq(TemporaryModifierTable.all_entries().size(), 3, "all_entries")
	_check_eq(TemporaryModifierTable.all_entries()[0].primary_key, 1, "all_entries 按主键排序")
	_check_eq(TemporaryModifierTable.all_entries()[2].name, "战意", "排序正确")
	_check(negative.is_negative(), "is_negative")
	_check(positive.is_positive(), "is_positive")
	_check_eq(negative.describe(), "虚弱#1", "describe")

	_check(TemporaryModifierTable.unregister(1), "按主键注销")
	_check(TemporaryModifierTable.unregister("祝福"), "按候选键注销")
	_check(not TemporaryModifierTable.unregister("不存在"), "注销不存在的返回 false")
	_check_eq(TemporaryModifierTable.size(), 1, "注销后只剩一个")
	_check(not TemporaryModifierTable.has(1), "原主键查不到了")
	_check(not TemporaryModifierTable.has("祝福"), "原候选键查不到了")
	return _verdict("test_queries_and_unregister")


func test_load_example_data() -> Variant:
	var loaded: int = TemporaryModifierTable.load_directory(TABLE_DIR)
	_check_eq(loaded, 5, "默认目录里的 5 个示例元素都装进来了")
	_check_eq(TemporaryModifierTable.size(), 5, "表里 5 个元素")

	var weakness: TemporaryModifier = TemporaryModifierTable.find("虚弱")
	_check(weakness != null, "按候选键读到虚弱")
	if weakness != null:
		_check_eq(weakness.primary_key, 1, "虚弱主键")
		_check_eq(weakness.strength, -3, "虚弱：固定 -3 力量")
		_check(weakness.fixed_value, "虚弱是固定值修正")
		_check_eq(weakness.polarity, TemporaryModifier.Polarity.NEGATIVE, "虚弱是负面")
		_check_eq(weakness.kind, AttributeModifier.Kind.IN_RUN_TEMPORARY, "虚弱是局内临时")
		_check(weakness.is_expiry_valid(), "虚弱挂了有效的结束判定脚本")
		_check_eq(weakness.expiry.get(&"seconds"), 8.0, "虚弱的秒数写在判定脚本里")

	var shackles: TemporaryModifier = TemporaryModifierTable.find_by_key(2)
	_check(shackles != null, "按主键读到镣铐")
	if shackles != null:
		_check_eq(shackles.name, "镣铐", "镣铐的候选键")
		_check(not shackles.fixed_value, "镣铐是非固定值修正")

	var battle_focus: TemporaryModifier = TemporaryModifierTable.find("战意")
	_check(battle_focus != null, "读到战意")
	if battle_focus != null:
		_check_eq(battle_focus.kind, AttributeModifier.Kind.IN_RUN_PERMANENT, "战意是局内永久")
		_check(not battle_focus.has_expiry_rule(), "局内永久没有消除规则")

	var inspired: TemporaryModifier = TemporaryModifierTable.find("鼓舞")
	_check(inspired != null, "读到鼓舞")
	if inspired != null:
		_check_eq(inspired.kind, AttributeModifier.Kind.OUT_RUN_TEMPORARY, "鼓舞是局外临时")
		_check_eq(inspired.expiry.get(&"steps"), 3, "鼓舞的步数写在判定脚本里")
		_check(inspired.has_expiry_rule(), "挂了判定脚本")

	var blessing: TemporaryModifier = TemporaryModifierTable.find("祝福")
	_check(blessing != null, "读到祝福")
	if blessing != null:
		_check(blessing.expiry.get_script() == DownedExpiry, "祝福的判定脚本是“倒地即消”")
	return _verdict("test_load_example_data")


func test_example_data_end_to_end() -> Variant:
	TemporaryModifierTable.load_directory(TABLE_DIR)
	var character: AttributeCharacter = _spawn()
	character.begin_run(&"demo")

	# 虚弱：固定 -3 力量，3 回合后消失
	TemporaryModifierTable.instantiate_for(character, "虚弱")
	_check_eq(character.get_attribute(AttributeCharacter.ATTR_STR), 7, "虚弱扣 3 点力量")
	character.advance_steps(9)
	_check_eq(character.get_attribute(AttributeCharacter.ATTR_STR), 7, "推回合 / 步数不影响按秒计时的虚弱")
	character.tick(8.0)
	_check_eq(character.get_attribute(AttributeCharacter.ATTR_STR), 10, "8 秒后虚弱消失")

	# 镣铐：施加时才收集参数
	TemporaryModifierTable.instantiate_for(character, "镣铐", {AttributeCharacter.ATTR_STR: -6})
	_check_eq(character.get_attribute(AttributeCharacter.ATTR_STR), 4, "镣铐按参数扣 6 点")

	# 战意：局内永久，一直生效到局结束
	TemporaryModifierTable.instantiate_for(character, "战意")
	_check_eq(character.get_attribute(AttributeCharacter.ATTR_STR), 6, "战意 +2 力量")
	_check_eq(character.get_attribute(AttributeCharacter.ATTR_CON), 11, "战意 +1 体质")

	character.end_run()
	_check_eq(character.get_attribute(AttributeCharacter.ATTR_STR), 10, "局结束：局内修正全部停止")
	_check_eq(character.get_attribute(AttributeCharacter.ATTR_CON), 10, "体质也回到本体")

	# 鼓舞：局外临时，局结束不停，倒地才由判定脚本消除
	TemporaryModifierTable.instantiate_for(character, "鼓舞")
	_check_eq(character.get_attribute(AttributeCharacter.ATTR_WIS), 12, "鼓舞 +2 感知")
	_check_eq(character.get_attribute(AttributeCharacter.ATTR_CHM), 11, "鼓舞 +1 魅力")
	character.end_run()
	_check_eq(character.get_attribute(AttributeCharacter.ATTR_WIS), 12, "局结束不影响局外临时")
	character.tick(99.0)
	_check_eq(character.get_attribute(AttributeCharacter.ATTR_WIS), 12, "推秒不影响按步数计时的鼓舞")

	character.advance_steps(3)
	_check_eq(character.get_attribute(AttributeCharacter.ATTR_WIS), 10, "推 3 步后鼓舞消失")
	_check_eq(character.get_attribute(AttributeCharacter.ATTR_CHM), 10, "魅力也回到本体")

	# 祝福：局外临时，倒地时由判定脚本消除
	TemporaryModifierTable.instantiate_for(character, "祝福")
	_check_eq(character.get_attribute(AttributeCharacter.ATTR_WIS), 11, "祝福 +1 感知")
	_check_eq(character.get_attribute(AttributeCharacter.ATTR_CHM), 12, "祝福 +2 魅力")
	character.take_damage(999)
	character.tick(0.1)
	_check_eq(character.get_attribute(AttributeCharacter.ATTR_WIS), 10, "倒地后判定脚本消除祝福")
	_check_eq(character.get_attribute(AttributeCharacter.ATTR_CHM), 10, "魅力也回到本体")
	return _verdict("test_example_data_end_to_end")


func test_instances_are_independent() -> Variant:
	TemporaryModifierTable.load_directory(TABLE_DIR)
	var first: AttributeCharacter = _spawn()
	var second: AttributeCharacter = _spawn()

	var on_first: AttributeModifier = TemporaryModifierTable.instantiate_for(first, "虚弱")
	var on_second: AttributeModifier = TemporaryModifierTable.instantiate_for(second, "虚弱")
	_check(on_first != on_second, "两个角色各拿到一份独立实例")
	_check(on_first != TemporaryModifierTable.find("虚弱"), "实例不是表里的模板元素")

	first.tick(8.0)
	_check(first.active_modifiers.is_empty(), "第一个角色的计时走完，修正消失")
	second.tick(0.1)
	_check_eq(second.active_modifiers.size(), 1, "第二个角色的计时器没被影响")
	_check_eq(second.get_attribute(AttributeCharacter.ATTR_STR), 7, "第二个角色的 -3 还在")
	_check(TemporaryModifierTable.find("虚弱").is_expiry_valid(), "模板本身没被改")

	# 同一个角色再施加同一条：来源 id = 候选键，非叠加 → 替换而不是叠两份
	TemporaryModifierTable.instantiate_for(first, "虚弱")
	_check_eq(first.active_modifiers.size(), 1, "同名修正不会叠加")
	_check_eq(first.get_attribute(AttributeCharacter.ATTR_STR), 7, "只算一份")
	return _verdict("test_instances_are_independent")

func test_time_units_are_up_to_the_script() -> Variant:
	# 同一张表里可以并存：局内按秒、局外按回合 / 步数，单位由脚本自己决定
	var by_seconds: TemporaryModifier = _make_entry(1, "按秒", AttributeModifier.Kind.IN_RUN_TEMPORARY)
	by_seconds.strength = -1
	by_seconds.expiry = _make_seconds_expiry(2.0)
	var by_steps: TemporaryModifier = _make_entry(2, "按步", AttributeModifier.Kind.OUT_RUN_TEMPORARY)
	by_steps.dexterity = 3
	by_steps.expiry = _make_step_expiry(2)
	_check(TemporaryModifierTable.register(by_seconds).is_empty(), "按秒的元素进表")
	_check(TemporaryModifierTable.register(by_steps).is_empty(), "按步的元素进表")

	var character: AttributeCharacter = _spawn()
	character.begin_run(&"units")
	TemporaryModifierTable.instantiate_for(character, 1)
	TemporaryModifierTable.instantiate_for(character, 2)
	_check_eq(character.active_modifiers.size(), 2, "两条都挂上了")

	character.advance_steps(2)
	_check_eq(character.active_modifiers.size(), 1, "推 2 步：按步的消失，按秒的还在")
	_check_eq(character.get_attribute(AttributeCharacter.ATTR_STR), 9, "按秒的 -1 力量还在")
	_check_eq(character.get_attribute(AttributeCharacter.ATTR_DEX), 10, "按步的 +3 敏捷随步数消失")

	character.tick(2.0)
	_check(character.active_modifiers.is_empty(), "推 2 秒：按秒的也消失")
	_check_eq(character.get_attribute(AttributeCharacter.ATTR_STR), 10, "力量回到本体")
	return _verdict("test_time_units_are_up_to_the_script")


# ------------------------------------------------------------------ 工具
func _make_entry(
	key: int, name: String, kind: AttributeModifier.Kind = AttributeModifier.Kind.IN_RUN_TEMPORARY
) -> TemporaryModifier:
	var entry: TemporaryModifier = TemporaryModifier.new()
	entry.primary_key = key
	entry.name = name
	entry.kind = kind
	entry.polarity = TemporaryModifier.Polarity.NEGATIVE
	entry.fixed_value = true
	entry.expiry = NeverExpires.new()  # 临时修正必须挂判定脚本
	return entry


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
