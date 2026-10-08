extends Node
## ASTCompiler（AST → GDScript 转译器）的单元测试。
##
## 运行器约定：extends Node，方法名以 test_ 开头，返回 null = 通过、字符串 = 失败原因。
##
## 覆盖四件事：
##   1. 生成的源码骨架正确（extends RefCounted / trace_block 信号 / target / execute）
##   2. 【探针注入规则】逐个节点的代码比对：每个 AST 节点自己的那一行之前必须有一行探针
##      —— 用逐字符比对的「黄金文本」钉住，避免以后重构悄悄漏掉某个节点的探针
##   3. 【防死循环注入】无条件循环体内必须有 await target.get_tree().process_frame
##   4. 生成出来的代码真的能编译、能跑：编译通过 → 实例化 → 接探针 → 执行顺序正确；
##      id → UI 积木的解析与高亮切换/还原
##
## 说明：测试运行器把任何 stderr 输出判为失败，所以「生成非法源码」这类错误路径不在此测
## （[member ASTCompiler.problems] 只在确实生成了退化代码时才非空，属于可安全断言的路径）。

## if (score > 3) { move_forward 3 fast } —— 探针注入的黄金文本
const EXPECTED_EXECUTE: String = (
	"func execute() -> void:\n"
	+ "\ttrace_block.emit(\"root.condition.left\")\n"
	+ "\tvar _t0 = target.get(\"score\")\n"
	+ "\ttrace_block.emit(\"root.condition.right\")\n"
	+ "\tvar _t1 = 3\n"
	+ "\ttrace_block.emit(\"root.condition\")\n"
	+ "\tvar _t2 = (_t0 > _t1)\n"
	+ "\ttrace_block.emit(\"root\")\n"
	+ "\tif _t2:\n"
	+ "\t\ttrace_block.emit(\"root.body.0\")\n"
	+ "\t\tawait target.call(\"move_forward\", 3, \"fast\")\n"
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

# ------------------------------------------------------------------ 骨架与探针
func test_generated_skeleton() -> Variant:
	var source: String = _compile_only(_if_program())
	_check(source.begins_with("# 由 res://BlockSystem/Logic/ASTCompiler.gd 生成"), "带生成来源说明")
	_check(source.contains("extends RefCounted"), "基类是 RefCounted")
	_check(source.contains("signal trace_block(block_uuid: String)"), "声明了 trace_block 信号")
	_check(source.contains("var target: Node"), "有 target 节点引用")
	_check(source.contains("var stop_requested: bool = false"), "有停止开关")
	_check(source.contains("var max_iterations: int = 0"), "有迭代上限开关")
	_check(source.contains("func execute() -> void:"), "有 execute()")
	_check(not source.contains("func _probe"), "SIGNAL 模式下不生成 _probe 辅助函数")
	return _verdict("test_generated_skeleton")


## 黄金文本：每个节点自己的代码行之前，必须有一行属于它的探针。
func test_probe_precedes_every_nodes_own_line() -> Variant:
	var source: String = _compile_only(_if_program())
	_check(source.contains(EXPECTED_EXECUTE), "逐字符匹配期望的 execute() 文本：\n%s" % source)
	# 顺序也值得钉住：先读两个操作数，再算比较，最后才是语句本体（探针 = 真实执行顺序）
	var left_at: int = source.find("trace_block.emit(\"root.condition.left\")")
	var right_at: int = source.find("trace_block.emit(\"root.condition.right\")")
	var operator_at: int = source.find("trace_block.emit(\"root.condition\")")
	var statement_at: int = source.find("trace_block.emit(\"root\")\n")
	var body_at: int = source.find("trace_block.emit(\"root.body.0\")")
	_check(left_at < right_at, "左操作数在右操作数之前")
	_check(right_at < operator_at, "操作数在运算符之前")
	_check(operator_at < statement_at, "条件在语句本体之前")
	_check(statement_at < body_at, "语句本体在它的语句体之前")
	return _verdict("test_probe_precedes_every_nodes_own_line")


func test_loop_gets_the_frame_guard_and_per_iteration_probe() -> Variant:
	var program: AST_Statement = AST_Statement.new()
	program.body = [_command("say", ["hi"])] as Array[AST_Node]
	var source: String = _compile_only(program)
	_check(source.contains("while not stop_requested:"), "无条件语句编译成循环")
	_check(source.contains("await target.get_tree().process_frame"), "循环体内强制让出一帧")
	# 探针在循环体内部：每转一圈都重新点亮循环积木（重复点亮是幂等的）
	var loop_at: int = source.find("while not stop_requested:")
	var probe_at: int = source.find("trace_block.emit(\"root\")")
	_check(loop_at >= 0 and probe_at > loop_at, "循环积木的探针在循环体内")
	_check(source.contains("if max_iterations > 0 and _iter_0 >= max_iterations:"), "带迭代上限保护")
	_check(source.contains("\tbreak\n"), "超限时 break")
	return _verdict("test_loop_gets_the_frame_guard_and_per_iteration_probe")


func test_expressions_forms() -> Variant:
	var compiler: ASTCompiler = ASTCompiler.new()
	var source: String = compiler.generate_gdscript(
		AST_Expression.make_binary("/", _literal(3), _literal(2))
	)
	_check(source.contains("(float(_t0) / float(_t1))"), "除法提升为实数除法（块语言不是整除）")
	_check(compiler.problems.is_empty(), "没有报问题")

	source = compiler.generate_gdscript(
		AST_Expression.make_binary("not", _literal("done"))
	)
	_check(source.contains("(not _t0)"), "一元 not 只用一个操作数")
	_check(source.contains("target.get(\"done\")"), "字符串叶子按变量名读取")

	source = compiler.generate_gdscript(
		AST_Expression.make_binary("and", AST_Expression.make_binary(">", _literal(1), _literal(2)), _literal(true))
	)
	_check(source.contains("(_t2 and _t3)"), "嵌套表达式按临时变量串联")
	_check(source.find("var _t0") < source.find("var _t2"), "子表达式先于父表达式")
	return _verdict("test_expressions_forms")


func test_problems_are_reported_without_breaking_the_output() -> Variant:
	var compiler: ASTCompiler = ASTCompiler.new()
	var source: String = compiler.generate_gdscript(AST_Expression.make_binary("??", _literal(1), _literal(2)))
	_check(not compiler.problems.is_empty(), "未知运算符被记录下来")
	_check(compiler.problems[0].contains("??"), "问题里带上原始运算符：%s" % compiler.problems[0])
	_check(source.contains("= null"), "该节点退化成 null，而不是生成非法源码")
	_check(ASTCompiler.compile(source) != null, "退化后的代码仍然能编译")

	compiler.problems.clear()
	source = compiler.generate_gdscript(_command("m", [Vector3(1, 2, 3)]))
	_check(not compiler.problems.is_empty(), "无法序列化的实参被记录下来")
	_check(source.contains("target.call(\"m\", null)"), "实参退化成 null")
	_check(ASTCompiler.compile(source) != null, "退化后的代码仍然能编译")
	return _verdict("test_problems_are_reported_without_breaking_the_output")


func test_generated_source_compiles() -> Variant:
	var source: String = _compile_only(_if_program())
	var script: GDScript = ASTCompiler.compile(source)
	_check(script != null, "生成的源码能编译")
	if script != null:
		_check(script.can_instantiate(), "编译结果可以实例化")
	return _verdict("test_generated_source_compiles")

# ------------------------------------------------------------------ 真的跑起来
func test_signal_mode_runs_and_reports_the_order() -> Variant:
	var target: TracingTarget = TracingTarget.new()
	add_child(target)
	_spawned.append(target)
	var compiler: ASTCompiler = ASTCompiler.new()
	var seen: Array = []  # Array 是引用类型：lambda 按值捕获也照样能看到 append
	var runner: Object = await compiler.compile_and_run(
		_if_program(), target, func(block_uuid: String) -> void: seen.append(block_uuid)
	)
	_check(runner != null, "拿到执行器实例")
	_check(target.calls.size() == 1, "指令被调用了一次（%d）" % target.calls.size())
	if target.calls.size() == 1:
		_check_eq(target.calls[0], ["move_forward", 3, "fast"], "指令名与实参都对上了")
	_check_eq(
		seen,
		["root.condition.left", "root.condition.right", "root.condition", "root", "root.body.0"],
		"探针顺序 = 真实执行顺序"
	)
	return _verdict("test_signal_mode_runs_and_reports_the_order")


func test_await_mode_asks_the_host_to_pace() -> Variant:
	var target: TracingTarget = TracingTarget.new()
	add_child(target)
	_spawned.append(target)
	var compiler: ASTCompiler = ASTCompiler.new()
	compiler.trace_mode = ASTCompiler.TraceMode.AWAIT
	var source: String = compiler.generate_gdscript(_if_program())
	_check(source.contains("await _probe(\"root\")"), "AWAIT 模式的探针走辅助函数")
	_check(source.contains("await target.trace(block_uuid)"), "辅助函数请宿主决定节奏")
	await compiler.compile_and_run(_if_program(), target, Callable())
	_check_eq(
		target.traced,
		PackedStringArray([
			"root.condition.left", "root.condition.right", "root.condition", "root", "root.body.0",
		]),
		"宿主 trace() 收到的顺序一致"
	)
	return _verdict("test_await_mode_asks_the_host_to_pace")


func test_loop_guard_can_be_stopped_or_capped() -> Variant:
	var target: TracingTarget = TracingTarget.new()
	add_child(target)
	_spawned.append(target)
	var program: AST_Statement = AST_Statement.new()
	program.body = [_command("tick", [])] as Array[AST_Node]

	# 1) 迭代上限：循环必须真的跑两轮然后自己停（否则这个用例自己就死循环了）
	var compiler: ASTCompiler = ASTCompiler.new()
	compiler.max_iterations = 2
	var runner: Object = await compiler.compile_and_run(program, target, Callable())
	_check(runner != null, "拿到执行器")
	_check_eq(target.calls.size(), 2, "被迭代上限截停在第 2 轮")
	if runner != null:
		_check_eq(int(runner.get(&"max_iterations")), 2, "上限写进了执行器")

	# 2) 停止开关：置位后循环立刻退出，语句体一次都不执行
	target.calls.clear()
	var script: GDScript = ASTCompiler.compile(compiler.generate_gdscript(program))
	var stopped: Object = script.new()
	stopped.set(&"target", target)
	stopped.set(&"stop_requested", true)
	await stopped.call(&"execute")
	_check_eq(target.calls.size(), 0, "停止请求生效：循环体没有执行")
	return _verdict("test_loop_guard_can_be_stopped_or_capped")

func test_guarded_variable_reads_survive_a_missing_variable() -> Variant:
	# 关掉护栏时：变量读不到 → null 参与比较 → 引擎直接报错（所以给孩子用的沙盒建议打开）
	var compiler: ASTCompiler = ASTCompiler.new()
	compiler.guard_variable_reads = true
	compiler.missing_variable_value = 0
	var source: String = compiler.generate_gdscript(_if_program())
	_check(source.contains("func _read_var(variable_name: String) -> Variant:"), "生成读取护栏")
	_check(source.contains("var missing_variable_value: Variant = 0"), "默认值写进执行器")
	_check(source.contains("_read_var(\"score\")"), "变量读取改走护栏")
	_check(not source.contains("target.get(\"score\")"), "不再直接读 target")

	# 用「没有 score 属性」的裸 Node 当宿主演一遍：不该崩，条件为假 → 跳过语句体
	var bare: Node = Node.new()
	add_child(bare)
	_spawned.append(bare)
	var seen: Array = []
	var runner: Object = await compiler.compile_and_run(
		_if_program(), bare, func(block_uuid: String) -> void: seen.append(block_uuid)
	)
	_check(runner != null, "执行完成并返回实例")
	_check_eq(
		seen, ["root.condition.left", "root.condition.right", "root.condition", "root"],
		"读不到变量按 0 处理 → 条件为假 → 语句体不执行"
	)
	return _verdict("test_guarded_variable_reads_survive_a_missing_variable")


# ------------------------------------------------------------------ id → UI 积木
func test_find_block_by_id_resolves_structural_paths() -> Variant:
	var ui: Control = await _build_ui(_if_program())
	if ui == null:
		_check(false, "构建出积木 UI")
		return _verdict("test_find_block_by_id_resolves_structural_paths")
	var root_block: Control = ASTCompiler.find_block_by_id(ui, "root")
	_check_eq(root_block, ui, "root 就是根积木")
	var condition: Control = ASTCompiler.find_block_by_id(ui, "root.condition")
	_check(condition is ExpressionUI, "root.condition 找到条件表达式积木")
	var left: Control = ASTCompiler.find_block_by_id(ui, "root.condition.left")
	_check(left is ExpressionUI, "root.condition.left 找到左操作数")
	if left is ExpressionUI:
		_check_eq((left as ExpressionUI).get_model().value, "score", "左操作数确实是 score")
	var body_zero: Control = ASTCompiler.find_block_by_id(ui, "root.body.0")
	_check(body_zero is CommandUI, "root.body.0 找到语句体里的指令")
	_check(ASTCompiler.find_block_by_id(ui, "root.body.9") == null, "越界的语句体下标返回 null")
	_check(ASTCompiler.find_block_by_id(ui, "not_root") == null, "根 id 不对返回 null")
	_check(ASTCompiler.find_block_by_id(ui, "root.nope") == null, "未知角色返回 null")
	_check(ASTCompiler.find_block_by_id(null, "root") == null, "空根返回 null")
	return _verdict("test_find_block_by_id_resolves_structural_paths")


func test_highlighter_lights_then_restores() -> Variant:
	var ui: Control = await _build_ui(_if_program())
	if ui == null:
		_check(false, "构建出积木 UI")
		return _verdict("test_highlighter_lights_then_restores")
	var highlighter: ASTCompiler.ExecutionHighlighter = ASTCompiler.ExecutionHighlighter.new()
	highlighter.ui_root = ui
	var first: Control = ASTCompiler.find_block_by_id(ui, "root.condition")
	var second: Control = ASTCompiler.find_block_by_id(ui, "root.body.0")
	if first == null or second == null:
		_check(false, "两块积木都找得到")
		return _verdict("test_highlighter_lights_then_restores")
	var first_before: Color = _panel_color(first)
	var second_before: Color = _panel_color(second)

	_check_eq(highlighter.highlight("root.condition"), first, "点亮条件积木")
	var first_lit: Color = _panel_color(first)
	_check(first_lit != first_before, "外观确实变了")
	_check(highlighter.current_block() == first, "记住当前发光的积木")

	highlighter.highlight("root.body.0")
	_check_eq(_panel_color(first), first_before, "上一块被还原")
	_check(_panel_color(second) != second_before, "新的一块亮了")

	highlighter.restore()
	_check_eq(_panel_color(second), second_before, "收尾时全部还原")
	_check(highlighter.current_block() == null, "不再记着任何积木")
	return _verdict("test_highlighter_lights_then_restores")


func test_highlighter_uses_the_art_stylebox() -> Variant:
	var ui: Control = await _build_ui(_if_program())
	if ui == null:
		_check(false, "构建出积木 UI")
		return _verdict("test_highlighter_uses_the_art_stylebox")
	var highlighter: ASTCompiler.ExecutionHighlighter = ASTCompiler.ExecutionHighlighter.new()
	highlighter.ui_root = ui
	var block: Control = highlighter.highlight("root.condition")
	_check(block != null, "点亮条件积木")
	if block == null:
		return _verdict("test_highlighter_uses_the_art_stylebox")
	# 主题里没注册 BlockExecuting 时走局部覆盖：样式本体取自 Art，不是代码里的颜色
	var from_art: StyleBoxFlat = load(highlighter.fallback_stylebox_path) as StyleBoxFlat
	_check(from_art != null, "兜底样式能加载：%s" % highlighter.fallback_stylebox_path)
	if from_art != null:
		_check_eq(_panel_color(block), from_art.bg_color, "用上了 Art 里的发光样式")
		_check(from_art.shadow_size > 0, "发光靠 shadow 实现（StyleBoxFlat 没有虚线，但有阴影）")
	highlighter.restore()
	return _verdict("test_highlighter_uses_the_art_stylebox")

# ------------------------------------------------------------------ 工具
## 只生成源码（SIGNAL 模式），并断言没有 problems。
func _compile_only(ast_root: AST_Node) -> String:
	var compiler: ASTCompiler = ASTCompiler.new()
	var source: String = compiler.generate_gdscript(ast_root)
	_check(compiler.problems.is_empty(), "生成过程无问题：%s" % str(compiler.problems))
	return source


## if (score > 3) { move_forward 3 fast }
func _if_program() -> AST_Statement:
	var statement: AST_Statement = AST_Statement.new()
	statement.condition = AST_Expression.make_binary(">", _literal("score"), _literal(3))
	statement.body = [_command("move_forward", [3, "fast"])] as Array[AST_Node]
	return statement


func _literal(value: Variant) -> AST_Expression:
	return AST_Expression.make_literal(value)


func _command(opcode: String, args: Array) -> AST_Command:
	var command: AST_Command = AST_Command.new(opcode)
	command.args = args
	return command


## 用同步引擎把 AST 变成积木 UI，挂进场景树（id 解析与高亮都需要真实的 UI 树）。
func _build_ui(source: AST_Node) -> Control:
	var engine: BlockSyncEngine = BlockSyncEngine.new()
	engine.blocks_per_frame = 64
	add_child(engine)
	_spawned.append(engine)
	var ui: Control = await engine.build_ui_from_ast(source)
	if ui != null:
		add_child(ui)
		_spawned.append(ui)
	return ui


## 积木当前用的 panel 底色（局部覆盖优先，见主题查询顺序）。
func _panel_color(block: Control) -> Color:
	var box: StyleBox = block.get_theme_stylebox(&"panel")
	if box is StyleBoxFlat:
		return (box as StyleBoxFlat).bg_color
	return Color.TRANSPARENT


## 测试用的宿主节点：记录被调用的指令，并实现 await 探针要用的 trace()。
class TracingTarget extends Node:
	var calls: Array = []
	var traced: PackedStringArray = PackedStringArray()
	## 供测试程序当变量读（if (score > 3)）。
	var score: int = 5

	func move_forward(steps: int, speed: String) -> void:
		calls.append(["move_forward", steps, speed])

	func tick() -> void:
		calls.append(["tick"])

	func trace(block_uuid: String) -> void:
		traced.append(block_uuid)


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
