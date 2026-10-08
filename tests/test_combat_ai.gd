extends Node
## 第一个实战业务逻辑：AI 战斗决策（WHILE / IF-ELSE / ATTACK / CHASE）的端到端测试。
##
## 运行器约定：extends Node，方法名以 test_ 开头，返回 null = 通过、字符串 = 失败原因。
##
## 覆盖三件事：
##   1. 手写 Dictionary 的 AST 能解析成对象、能原样往返（uuid / loop / else_body / variable 都在）
##   2. 编译出来的 GDScript 文本符合预期（逐字符黄金文本：uuid 探针 + 循环里的帧让出）
##   3. 真的跑起来：ATTACK 分支、CHASE 分支、以及【while 条件每轮重新求值】——
##      最后一条是这个设计的核心正确性，用「每次读 distance_to_enemy 都变远」的宿主来证明。

const EXPECTED_EXECUTE: String = (
	"func execute() -> void:\n"
	+ "\tvar _iter_0: int = 0\n"
	+ "\twhile not stop_requested:\n"
	+ "\t\ttrace_block.emit(\"uuid_while_1\")\n"
	+ "\t\ttrace_block.emit(\"root.condition\")\n"
	+ "\t\tvar _t0 = target.get(\"enemies_visible\")\n"
	+ "\t\tif not _t0:\n"
	+ "\t\t\tbreak\n"
	+ "\t\ttrace_block.emit(\"root.body.0.condition.left\")\n"
	+ "\t\tvar _t1 = target.get(\"closest_enemy\")\n"
	+ "\t\ttrace_block.emit(\"root.body.0.condition.right\")\n"
	+ "\t\tvar _t2 = target.get(\"attack_range\")\n"
	+ "\t\ttrace_block.emit(\"root.body.0.condition\")\n"
	+ "\t\tvar _t3 = (_t2).contains(_t1)\n"
	+ "\t\ttrace_block.emit(\"uuid_if_1\")\n"
	+ "\t\tif _t3:\n"
	+ "\t\t\ttrace_block.emit(\"root.body.0.body.0.args.0\")\n"
	+ "\t\t\tvar _t4 = target.get(\"closest_enemy\")\n"
	+ "\t\t\ttrace_block.emit(\"uuid_attack_1\")\n"
	+ "\t\t\tawait target.call(\"attack\", _t4)\n"
	+ "\t\telse:\n"
	+ "\t\t\ttrace_block.emit(\"root.body.0.else_body.0.args.0\")\n"
	+ "\t\t\tvar _t5 = target.get(\"closest_enemy\")\n"
	+ "\t\t\ttrace_block.emit(\"uuid_chase_1\")\n"
	+ "\t\t\tawait target.call(\"chase\", _t5)\n"
	+ "\t\tawait target.get_tree().process_frame\n"
	+ "\t\t_iter_0 += 1\n"
	+ "\t\tif max_iterations > 0 and _iter_0 >= max_iterations:\n"
	+ "\t\t\tbreak\n"
)

var _failures: PackedStringArray = PackedStringArray()
var _spawned: Array[Node] = []


func before_each() -> void:
	_failures.clear()


func after_each() -> void:
	for node: Node in _spawned:
		if is_instance_valid(node):
			node.free()
	_spawned.clear()

# ------------------------------------------------------------------ 数据模型
func test_mock_ast_is_the_described_shape() -> Variant:
	var data: Dictionary = CombatAIMock.get_combat_ai_ast()
	_check_eq(data.get("type"), "statement", "根是语句")
	_check_eq(data.get("uuid"), CombatAIMock.UUID_WHILE, "根带 uuid")
	_check(data.get("loop") == true, "根是循环（loop = true）")
	_check_eq((data.get("condition") as Dictionary).get("type"), "variable", "条件是变量节点")
	_check_eq((data.get("condition") as Dictionary).get("name"), "enemies_visible", "条件变量名")
	var if_node: Dictionary = (data.get("body") as Array)[0]
	_check_eq(if_node.get("uuid"), CombatAIMock.UUID_IF, "IF 带 uuid")
	_check(not if_node.has("loop"), "IF 不是循环")
	_check_eq((if_node.get("else_body") as Array).size(), 1, "IF 有 else 分支")
	var attack: Dictionary = (if_node.get("body") as Array)[0]
	var chase: Dictionary = (if_node.get("else_body") as Array)[0]
	_check_eq(attack.get("opcode"), "attack", "IF 分支是 ATTACK")
	_check_eq(attack.get("uuid"), CombatAIMock.UUID_ATTACK, "ATTACK 带 uuid")
	var attack_arg: Dictionary = (attack.get("args") as Array)[0]
	_check_eq(attack_arg.get("type"), "variable", "ATTACK 的目标参数是对象参数")
	_check_eq(attack_arg.get("name"), "closest_enemy", "目标变量名")
	_check_eq(chase.get("opcode"), "chase", "ELSE 分支是 CHASE")
	_check_eq(chase.get("uuid"), CombatAIMock.UUID_CHASE, "CHASE 带 uuid")
	return _verdict("test_mock_ast_is_the_described_shape")


func test_mock_ast_parses_and_round_trips() -> Variant:
	var data: Dictionary = CombatAIMock.get_combat_ai_ast()
	var ast: AST_Node = ASTManager.from_dictionary(data)
	_check(ast is AST_Statement, "解析成 AST_Statement")
	if not (ast is AST_Statement):
		return _verdict("test_mock_ast_parses_and_round_trips")
	var root: AST_Statement = ast
	_check_eq(root.uuid, CombatAIMock.UUID_WHILE, "uuid 读进来了")
	_check(root.loop, "loop 读进来了")
	_check(root.condition is AST_Variable, "条件是 AST_Variable")
	_check_eq(root.body.size(), 1, "循环体 1 块")
	_check_eq(root.else_body.size(), 0, "循环没有 else")
	var if_node: AST_Statement = root.body[0] as AST_Statement
	_check(if_node != null, "循环体是语句")
	if if_node == null:
		return _verdict("test_mock_ast_parses_and_round_trips")
	_check_eq(if_node.else_body.size(), 1, "else 分支读进来了")
	_check(if_node.condition is AST_Expression, "IF 条件是表达式")
	_check(not if_node.loop, "IF 不是循环")
	_check_eq(if_node.condition.left, if_node.condition.left, "left 存在")
	_check(if_node.condition.left is AST_Variable, "左操作数是变量节点")
	_check(if_node.condition.right is AST_Variable, "右操作数是变量节点")
	# 往返：字典 → AST → 字典，必须与手写的完全一致
	_check_eq(ast.to_dictionary(), data, "往返后与手写的 Dictionary 完全一致")
	return _verdict("test_mock_ast_parses_and_round_trips")


func test_uuid_and_new_fields_survive_json_round_trip() -> Variant:
	var ast: AST_Node = ASTManager.from_dictionary(CombatAIMock.get_combat_ai_ast())
	var text: String = ASTManager.serialize_ast_to_json(ast)
	var again: AST_Node = ASTManager.parse_json_to_ast(text)
	_check(again != null, "序列化文本能解析回来")
	if again == null:
		return _verdict("test_uuid_and_new_fields_survive_json_round_trip")
	_check_eq(again.to_dictionary(), ast.to_dictionary(), "JSON 往返不丢 uuid / loop / else_body")
	_check_eq(
		ASTManager.serialize_ast_to_json(again), text, "两次序列化文本逐字符相同"
	)
	return _verdict("test_uuid_and_new_fields_survive_json_round_trip")


func test_variable_node_behaves_like_an_expression_leaf() -> Variant:
	var variable: AST_Variable = AST_Variable.new("enemies_visible")
	_check(variable.is_leaf(), "变量是叶子操作数")
	_check_eq(variable.variable_name, "enemies_visible", "变量名可读")
	_check_eq(variable.value, "enemies_visible", "与 value 同一份存储")
	variable.variable_name = "other"
	_check_eq(variable.value, "other", "写变量名也同步到 value")
	# 视图 / 类型推断 / 调色板：因为继承了 AST_Expression，这些全都不用改
	_check_eq(
		AST_BlockSchema.kind_of(variable), AST_BlockSchema.KIND_EXPRESSION,
		"视图层按表达式积木渲染"
	)
	_check_eq(
		AST_BlockSchema.palette_category(variable), AST_BlockSchema.CATEGORY_VARIABLE,
		"调色板类别是变量色"
	)
	_check_eq(
		AST_TypeInference.result_type(variable), AST_TypeInference.ResultType.UNKNOWN,
		"裸变量名类型未知（有符号表时再收紧）"
	)
	return _verdict("test_variable_node_behaves_like_an_expression_leaf")


func test_else_branch_is_visible_to_the_schema() -> Variant:
	var ast: AST_Node = ASTManager.from_dictionary(CombatAIMock.get_combat_ai_ast())
	var if_node: AST_Statement = (ast as AST_Statement).body[0] as AST_Statement
	var roles: Array[Dictionary] = AST_BlockSchema.child_roles(if_node)
	var role_names: PackedStringArray = PackedStringArray()
	for entry: Dictionary in roles:
		role_names.append(String(entry["role"]))
	_check_eq(
		role_names,
		PackedStringArray(["condition", "body", "else_body"]),
		"子节点角色按 条件 → 语句体 → else 顺序暴露"
	)
	_check(
		BlockSyncEngine.ROLE_SLOTS.has(AST_BlockSchema.ROLE_ELSE),
		"视图侧注册了 else 的插槽属性名（If 预制体补上 else_container 即可渲染）"
	)
	_check(
		not AST_BlockSchema.required_roles(if_node).has(AST_BlockSchema.ROLE_ELSE),
		"else 永远不是必填（没有 else 的 if 是合法的）"
	)
	return _verdict("test_else_branch_is_visible_to_the_schema")

# ------------------------------------------------------------------ 编译结果
func test_compiled_text_is_the_expected_gdscript() -> Variant:
	var compiler: ASTCompiler = ASTCompiler.new()
	var source: String = compiler.generate_gdscript(
		ASTManager.from_dictionary(CombatAIMock.get_combat_ai_ast())
	)
	_check(compiler.problems.is_empty(), "编译无问题：%s" % str(compiler.problems))
	_check(source.contains(EXPECTED_EXECUTE), "逐字符匹配期望的 execute()：\n%s" % source)
	_check(source.contains("trace_block.emit(\"uuid_while_1\")"), "循环积木的 uuid 探针在")
	_check(source.contains("trace_block.emit(\"uuid_if_1\")"), "IF 的 uuid 探针在")
	_check(source.contains("trace_block.emit(\"uuid_attack_1\")"), "ATTACK 的 uuid 探针在")
	_check(source.contains("trace_block.emit(\"uuid_chase_1\")"), "CHASE 的 uuid 探针在")
	_check(
		source.contains("await target.get_tree().process_frame"), "循环体内强制让出一帧"
	)
	_check(source.contains("while not stop_requested:"), "循环可被 stop_requested 打断")
	return _verdict("test_compiled_text_is_the_expected_gdscript")


func test_compiled_combat_ai_compiles() -> Variant:
	var compiler: ASTCompiler = ASTCompiler.new()
	var script: GDScript = ASTCompiler.compile(
		compiler.generate_gdscript(ASTManager.from_dictionary(CombatAIMock.get_combat_ai_ast()))
	)
	_check(script != null, "生成的源码能编译")
	if script != null:
		_check(script.can_instantiate(), "编译结果可以实例化")
	return _verdict("test_compiled_combat_ai_compiles")

# ------------------------------------------------------------------ 真的跑起来
## 敌人在范围内 → 走 ATTACK 分支。
func test_runs_the_attack_branch() -> Variant:
	var target: CombatTarget = _spawn_target()
	target.reach = 3.0
	target.fixed_distance = 1.0  # 一直够得着
	var compiler: ASTCompiler = ASTCompiler.new()
	compiler.max_iterations = 2
	var seen: Array = []
	await compiler.compile_and_run(
		ASTManager.from_dictionary(CombatAIMock.get_combat_ai_ast()),
		target,
		func(block_uuid: String) -> void: seen.append(block_uuid)
	)
	_check_eq(target.calls, ["attack:closest_enemy", "attack:closest_enemy"], "两轮都走 ATTACK")
	_check(seen.has("uuid_attack_1"), "ATTACK 的探针亮了")
	_check(not seen.has("uuid_chase_1"), "CHASE 的探针没亮")
	# 循环每轮都重新点亮循环积木、并重新求值条件
	_check_eq(seen.count("uuid_while_1"), 2, "循环积木每轮亮一次")
	_check_eq(seen.count("root.body.0.condition"), 2, "条件每轮重新求值")
	return _verdict("test_runs_the_attack_branch")


## 敌人太远 → 走 ELSE 的 CHASE 分支。
func test_runs_the_chase_branch() -> Variant:
	var target: CombatTarget = _spawn_target()
	target.reach = 1.0
	target.fixed_distance = 5.0  # 够不着
	var compiler: ASTCompiler = ASTCompiler.new()
	compiler.max_iterations = 2
	var seen: Array = []
	await compiler.compile_and_run(
		ASTManager.from_dictionary(CombatAIMock.get_combat_ai_ast()),
		target,
		func(block_uuid: String) -> void: seen.append(block_uuid)
	)
	_check_eq(target.calls, ["chase:closest_enemy", "chase:closest_enemy"], "两轮都走 CHASE")
	_check(seen.has("uuid_chase_1"), "CHASE 的探针亮了")
	_check(not seen.has("uuid_attack_1"), "ATTACK 的探针没亮")
	return _verdict("test_runs_the_chase_branch")


## 【核心】while 的条件必须每轮重新求值：
## 让 distance_to_enemy 每次被读都变远，于是第 1 轮 ATTACK、第 2 轮起 CHASE。
## 如果条件只在循环外算一次（`while <条件>:` 的写法），这里会一直是 ATTACK。
func test_while_condition_is_reevaluated_every_iteration() -> Variant:
	var target: CombatTarget = _spawn_target()
	target.reach = 2.0
	target.growing_distance = true  # 每次读都更远：1.0 → 2.0 → 3.0 …
	var compiler: ASTCompiler = ASTCompiler.new()
	compiler.max_iterations = 3
	await compiler.compile_and_run(
		ASTManager.from_dictionary(CombatAIMock.get_combat_ai_ast()), target, Callable()
	)
	_check_eq(
		target.calls,
		["attack:closest_enemy", "attack:closest_enemy", "chase:closest_enemy"],
		"第 1、2 轮够得着（2.0 <= 2.0 仍成立）打，第 3 轮够不着就追 —— 说明条件每轮重算"
	)
	_check_eq(target.distance_reads, 3, "条件里的变量被读了 3 次（每轮一次）")
	return _verdict("test_while_condition_is_reevaluated_every_iteration")


## 看不见敌人 → 循环条件为假，直接退出，一次指令都不发。
func test_loop_exits_when_no_enemies_are_visible() -> Variant:
	var target: CombatTarget = _spawn_target()
	target.enemies_visible = false
	var compiler: ASTCompiler = ASTCompiler.new()
	var runner: Object = await compiler.compile_and_run(
		ASTManager.from_dictionary(CombatAIMock.get_combat_ai_ast()), target, Callable()
	)
	_check(runner != null, "执行器跑完并返回")
	_check_eq(target.calls, [], "一条指令都没发")
	_check_eq(target.visible_reads, 1, "条件只读了一次就退出了")
	return _verdict("test_loop_exits_when_no_enemies_are_visible")

# ------------------------------------------------------------------ 工具
func _spawn_target() -> CombatTarget:
	var target: CombatTarget = CombatTarget.new()
	add_child(target)
	_spawned.append(target)
	var range_stub: RangeStub = RangeStub.new()
	range_stub.owner_target = target
	target.attack_range = range_stub
	return target


## 测试用的 AI 宿主：用真实属性承载变量，于是 target.get("名字") 直接生效。
## 范围对象替身：生成代码对它的唯一要求是有 contains(目标)。
class RangeStub extends RefCounted:
	var owner_target: CombatTarget = null

	func contains(_node: Variant) -> bool:
		if owner_target == null:
			return false
		return owner_target.distance_to_enemy <= owner_target.reach


class CombatTarget extends Node:
	var calls: Array = []
	## 指令的对象参数现在是从宿主读出来的值（不再是字面量）。
	var closest_enemy: String = "closest_enemy"
	## 够得着的阈值（夹具内部用；真实项目里由 CharacterRange 的几何判定承担）。
	var reach: float = 2.0
	## 宿主提供的范围对象：生成代码会调它的 contains()。
	var attack_range: RangeStub = null
	## 固定距离（growing_distance 为 false 时使用）。
	var fixed_distance: float = 1.0
	## true 时每次读取都更远，用来证明 while 条件每轮重新求值。
	var growing_distance: bool = false
	var distance_reads: int = 0
	var visible_reads: int = 0

	var _visible: bool = true

	## 同样用真实属性：读一次计一次，方便断言「条件每轮重新求值」。
	var enemies_visible: bool:
		get:
			visible_reads += 1
			return _visible
		set(value):
			_visible = value

	var distance_to_enemy: float:
		get:
			distance_reads += 1
			if growing_distance:
				return float(distance_reads)
			return fixed_distance

	func attack(who: String) -> void:
		calls.append("attack:" + who)

	func chase(who: String) -> void:
		calls.append("chase:" + who)


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
