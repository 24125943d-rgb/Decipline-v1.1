class_name ASTCompiler
extends RefCounted
## AST → GDScript 转译器（Logic 层）：把积木程序翻译成一段可执行的 GDScript 文本。
##
## [br][b]为什么是「转译 + 探针注入」而不是解释执行[/b]：逐节点解释要走一遍通用调度，
## 转译出来的代码由 GDScript 虚拟机直接跑，数量级更快；而「哪个积木正在执行」这个信息
## 不需要靠解释器查栈，只要在生成的代码里按节点插一行探针即可。
##
## [br][b]探针注入规则[/b]：任何一个 AST 节点，在它自己的代码行之前，先发出一次
## [code]trace_block[/code]。表达式子节点因此必须先落到临时变量上（形如 [code]_t0[/code]），
## 否则子表达式会被内联进父节点的那一行，没有属于自己的「上一行」可插：
## [codeblock]
## trace_block.emit("root.condition.left")
## var _t0 = target.get("score")
## trace_block.emit("root.condition.right")
## var _t1 = 3
## trace_block.emit("root.condition")
## var _t2 = (_t0 > _t1)
## trace_block.emit("root")
## if _t2:
##     trace_block.emit("root.body.0")
##     await target.call("move_forward", 3, "fast")
## [/codeblock]
## 探针因此天然反映[b]真实执行顺序[/b]：先读操作数，再算运算符，最后语句本体。
##
## [br][b]节点 id[/b]：用「结构路径」当 uuid —— [code]root[/code]、[code]root.condition[/code]、
## [code]root.condition.left[/code]、[code]root.body.0[/code]、[code]root.body.2.body.0[/code]。
## 它由节点在 AST 中的位置唯一决定，不需要给 [AST_Node] 加字段、重编译也稳定；
## UI 侧按同一路径就能找到对应的积木节点（[method find_block_by_id]）。
## 以后若给 [AST_Node] 加上 uuid 字段，只需改 [method _child_id] 一处。
##
## [br][b]两种探针模式[/b]
## [br]· [constant TraceMode.SIGNAL]（默认）：[code]trace_block.emit(id)[/code]，不打断执行，
##   适合「记录执行轨迹」。缺点是跑得太快，发光高亮肉眼看不见。
## [br]· [constant TraceMode.AWAIT]：生成 [code]await _probe(id)[/code]，由宿主节点的
##   [code]trace(id)[/code] 决定每块停多久（例如 await 一个 50ms 定时器）——真正「看得见」的
##   单步高亮用这个模式；宿主没实现 [code]trace()[/code] 时自动退化成只发信号。
##
## [br][b]循环[/b]：语句块的 condition 为 null 时按「无条件循环」编译（README §2：condition 为
## null 表示循环体）。循环体内强制注入 [code]await target.get_tree().process_frame[/code]，
## 保证不卡死主线程；另外生成 [code]stop_requested[/code] / [code]max_iterations[/code]
## 两个可控开关，给 UI 的停止按钮和跑飞保护用。要求 [member target] 在场景树里。
##
## [br][b]与其余各层的边界[/b]：本文件属于 Logic 层 —— 依赖 Core 的 [AST_BlockSchema]（角色名、
## 种类）与 Logic 的 [BlockSyncEngine]（角色 → 插槽属性名），[b]不含任何颜色 / 字号字面量[/b]；
## 高亮外观来自 Art（theme type variation），逻辑只负责切换变体名。

## 探针的两种注入方式。
enum TraceMode {
	SIGNAL, ## trace_block.emit(id)：不打断执行，适合记录轨迹
	AWAIT,  ## await _probe(id)：由宿主 trace() 决定节奏，适合看得见的单步高亮
}

## 根节点的结构路径。
const ROOT_ID: String = "root"

## 每块积木的缩进字符。
const INDENT: String = "\t"

## 探针模式。改它只影响之后新生成的代码。
var trace_mode: TraceMode = TraceMode.SIGNAL

## 生成出来的执行器的默认迭代上限（会被写进 runner.max_iterations）：
## > 0 时每个循环最多转这么多圈，防跑飞。0 = 不限制。
var max_iterations: int = 0

## 变量读不到时给什么默认值（只在 [member guard_variable_reads] 打开时生效）。
## 默认 0：既能在比较 / 算术里用，在 and / or / not 里又是「假」。
var missing_variable_value: Variant = 0

## 是否给变量读取套护栏。
## [br]关闭（默认）时生成的是干净的 [code]target.get("名字")[/code]——名字写错、
## 或宿主没提供这个变量，读回 null 参与比较会直接抛运行时错误（[code]null > 3[/code]）。
## [br]打开后会生成 [code]_read_var("名字")[/code]，读不到就用
## [member missing_variable_value]，代价是多一层函数调用。做给孩子用的沙盒建议打开。
var guard_variable_reads: bool = false

## 上一次生成时发现的问题（未知运算符、无法序列化的字面量……）。
## 空数组表示干净；有问题时仍会产出一份「能编译、能跑」的代码，只是该节点退化成 null。
var problems: PackedStringArray = PackedStringArray()

var _lines: PackedStringArray = PackedStringArray()
var _temp_index: int = 0
var _loop_index: int = 0

# ------------------------------------------------------------------ 转译

## 把 AST 递归编译成一段完整的 GDScript 源码文本。
## 返回的文本可以直接 [method compile] / [method compile_and_run]。
func generate_gdscript(ast_root: AST_Node) -> String:
	problems = PackedStringArray()
	_lines = PackedStringArray()
	_temp_index = 0
	_loop_index = 0

	if ast_root == null:
		problems.append("AST 根节点为 null，生成的是空程序。")

	_line("# 由 res://BlockSystem/Logic/ASTCompiler.gd 生成 —— 请勿手改。", 0)
	_line("# 探针模式：%s" % _mode_name(), 0)
	_line("extends RefCounted", 0)
	_line("", 0)
	_line("## 每个 AST 节点执行前发出，参数是结构路径 id（见 ASTCompiler）。", 0)
	_line("signal trace_block(block_uuid: String)", 0)
	_line("", 0)
	_line("## 指令与变量访问的宿主节点（必须在场景树里：循环要 await 它的 process_frame）。", 0)
	_line("var target: Node", 0)
	_line("", 0)
	_line("## 置为 true 可让正在运行的循环退出（UI 的停止按钮用）。", 0)
	_line("var stop_requested: bool = false:", 0)
	_line("set(value):", 1)
	_line("stop_requested = value", 2)
	_line("if value and is_instance_valid(target) and target.has_method(&\"cancel_ast_execution\"):", 2)
	_line("target.call(&\"cancel_ast_execution\")", 3)
	_line("", 0)
	_line("func stop() -> void:", 0)
	_line("stop_requested = true", 1)
	_line("", 0)
	_line("## > 0 时限制「每次循环」的迭代次数，防止跑飞。0 = 不限制。", 0)
	_line("var max_iterations: int = 0", 0)
	if guard_variable_reads:
		_line("", 0)
		_line("## 变量读不到时用的默认值（见 _read_var）。", 0)
		_line(
			"var missing_variable_value: Variant = %s" % var_to_str(missing_variable_value), 0
		)
	_line("", 0)

	if trace_mode == TraceMode.AWAIT:
		_line("", 0)
		_line("## AWAIT 模式的探针：先发信号，再请宿主决定停多久。", 0)
		_line("func _probe(block_uuid: String) -> void:", 0)
		_line("trace_block.emit(block_uuid)", 1)
		_line("if target != null and target.has_method(&\"trace\"):", 1)
		_line("await target.trace(block_uuid)", 2)
		_line("", 0)

	if guard_variable_reads:
		_line("", 0)
		_line("## 读目标上的变量；读不到时给默认值，避免 null 参与运算直接报错。", 0)
		_line("func _read_var(variable_name: String) -> Variant:", 0)
		_line("var value: Variant = target.get(variable_name)", 1)
		_line("return value if value != null else missing_variable_value", 1)

	_line("", 0)
	_line("func execute() -> void:", 0)
	if ast_root == null:
		_line("pass", 1)
	else:
		_emit_node(ast_root, ROOT_ID, 1)
	return "\n".join(_lines) + "\n"


## 把源码文本编译成 [GDScript]。失败返回 null（并已在 [member problems] 里记一条）。
static func compile(source: String) -> GDScript:
	var script: GDScript = GDScript.new()
	script.source_code = source
	if script.reload() != OK:
		return null
	return script


## 一站式：转译 → 编译 → 实例化 → 接好探针 → 跑完。
##
## [br][b]必须 await 调用[/b]：生成出来的 [code]execute()[/code] 里可能有 await，
## 不 await 会在第一个 await 处被丢弃（后面的积木永远不执行）。
## [br][param on_trace] 会被连到 [code]trace_block[/code] 信号上，通常传
## [method ExecutionHighlighter.highlight]（SIGNAL 模式下的高亮入口）。
## 返回实例化出来的执行器；执行结束后可以读它的字段、或置 stop_requested 中断。
func compile_and_run(ast_root: AST_Node, target_node: Node, on_trace: Callable = Callable()) -> Object:
	var source: String = generate_gdscript(ast_root)
	var script: GDScript = compile(source)
	if script == null:
		problems.append("生成的源码没通过 GDScript 编译，请看输出面板的报错。")
		return null
	var runner: Object = script.new()
	if runner == null:
		problems.append("GDScript.new() 失败：生成的脚本无法实例化。")
		return null
	runner.set(&"target", target_node)
	runner.set(&"max_iterations", max_iterations)
	if guard_variable_reads:
		runner.set(&"missing_variable_value", missing_variable_value)
	if on_trace.is_valid():
		runner.connect(&"trace_block", on_trace)
	await runner.call(&"execute")
	return runner

# ------------------------------------------------------------------ id → UI 节点

## 按结构路径 id 找到 UI 里对应的那块积木。找不到返回 null。
##
## [br]路径与 [AST_BlockSchema] 的角色名一一对应，插槽名复用 [constant BlockSyncEngine.ROLE_SLOTS]：
## [code]root[/code]、[code]root.condition[/code]、[code]root.condition.left[/code]、
## [code]root.body.0[/code]（body 后面跟的是「第几块积木」，装饰节点不计入）。
static func find_block_by_id(ui_root: Control, block_uuid: String) -> Control:
	if ui_root == null or block_uuid.is_empty():
		return null
	var segments: PackedStringArray = block_uuid.split(".")
	if segments.is_empty() or segments[0] != ROOT_ID:
		return null
	var current: Control = BlockSyncEngine.as_block(ui_root)
	if current == null:
		# 允许把「画布」节点直接传进来：取它里面的第一块积木当根
		current = _first_block(ui_root)
	var index: int = 1
	while index < segments.size() and current != null:
		var role: String = segments[index]
		var slot_property: StringName = BlockSyncEngine.ROLE_SLOTS.get(StringName(role), &"")
		if slot_property.is_empty():
			return null
		var slot: Node = current.get(slot_property) as Node
		if slot == null:
			return null
		index += 1
		if role == String(AST_BlockSchema.ROLE_BODY) or role == String(AST_BlockSchema.ROLE_ARG):
			if index >= segments.size():
				return null
			current = _block_at(slot, segments[index].to_int())
			index += 1
		else:
			current = _first_block(slot)
	return current


static func _first_block(parent: Node) -> Control:
	for child: Node in parent.get_children():
		var block: Control = BlockSyncEngine.as_block(child)
		if block != null:
			return block
	return null


## 容器里第 n 块积木（装饰节点 / 插槽不计入）。
static func _block_at(parent: Node, wanted: int) -> Control:
	var seen: int = 0
	for child: Node in parent.get_children():
		var block: Control = BlockSyncEngine.as_block(child)
		if block == null:
			continue
		if seen == wanted:
			return block
		seen += 1
	return null

# ------------------------------------------------------------------ 内部：生成
func _mode_name() -> String:
	return "AWAIT（await target.trace）" if trace_mode == TraceMode.AWAIT else "SIGNAL（trace_block.emit）"


## 探针用的 id：优先用节点自己的 [member AST_Node.uuid]，没有就退回结构路径。
## [br]两种 id 可以混用：给 statement / command 分配了 uuid 的树，表达式子节点
## 仍然用结构路径（root.condition.left 这种），UI 侧两种都认得。
static func probe_id(model: AST_Node, path: String) -> String:
	if model != null and not model.uuid.is_empty():
		return model.uuid
	return path


func _emit_node(model: AST_Node, block_id: String, depth: int) -> void:
	if model is AST_Statement:
		_emit_statement(model as AST_Statement, block_id, depth)
	elif model is AST_Command:
		_emit_command(model as AST_Command, block_id, depth)
	elif model is AST_Expression:
		_emit_expression(model as AST_Expression, block_id, depth)
	else:
		problems.append("未知节点种类（%s）：已跳过。" % AST_BlockSchema.kind_of(model))
		_line("pass  # 未知节点", depth)


func _emit_statement(statement: AST_Statement, block_id: String, depth: int) -> void:
	var probe: String = probe_id(statement, block_id)
	var body: Array[AST_Node] = _real_body(statement.body)
	var else_body: Array[AST_Node] = _real_body(statement.else_body)

	# 循环：显式 loop=true，或沿用「condition 为 null = 无条件循环」的旧口径
	if statement.loop or statement.condition == null:
		_emit_loop(statement, probe, body, block_id, depth)
		return

	# 条件先求值（它自己的探针在它的代码行之前），再执行语句本体
	var condition_temp: String = _emit_expression(
		statement.condition, _child_id(block_id, String(AST_BlockSchema.ROLE_CONDITION)), depth
	)
	_emit_probe(probe, depth)
	_line("if %s:" % condition_temp, depth)
	_emit_block(body, _body_entries(body, block_id), depth + 1)
	if not else_body.is_empty():
		_line("else:", depth)
		_emit_block(
			else_body,
			_body_entries(else_body, block_id, AST_BlockSchema.ROLE_ELSE),
			depth + 1
		)


## 循环（loop = true，或 condition 为空）。
## [br]condition 非空时是 while —— 条件[b]必须每轮重新求值[/b]，所以展开成
## [code]while not stop_requested:[/code] + [code]if not <条件>: break[/code]，
## 而不是直接写 [code]while <条件>:[/code]：后者会让条件的探针与临时变量只算一次，
## 第二圈开始用的就是过期值（而且 UI 上条件积木只会亮一次）。
func _emit_loop(
	statement: AST_Statement, probe: String, body: Array[AST_Node], block_id: String, depth: int
) -> void:
	var loop_name: String = "_iter_%d" % _loop_index
	_loop_index += 1
	_line("var %s: int = 0" % loop_name, depth)
	_line("while not stop_requested:", depth)
	_emit_probe(probe, depth + 1)  # 每一轮都重新点亮循环积木（重复点亮是幂等的）
	if statement.condition != null:
		var condition_temp: String = _emit_expression(
			statement.condition,
			_child_id(block_id, String(AST_BlockSchema.ROLE_CONDITION)),
			depth + 1,
		)
		_line("if not %s:" % condition_temp, depth + 1)
		_line("break", depth + 2)
	_emit_block(body, _body_entries(body, block_id), depth + 1)
	# 防死循环：每轮让出一帧，主线程与 UI 才有机会刷新
	_line("await target.get_tree().process_frame", depth + 1)
	_line("%s += 1" % loop_name, depth + 1)
	_line("if max_iterations > 0 and %s >= max_iterations:" % loop_name, depth + 1)
	_line("break", depth + 2)


## 一组语句体（空则 pass）。
func _emit_block(body: Array[AST_Node], entries: Array[Dictionary], depth: int) -> void:
	if body.is_empty():
		_line("pass", depth)
		return
	for entry: Dictionary in entries:
		var child_model: AST_Node = entry["model"]
		_emit_node(child_model, String(entry["id"]), depth)


func _emit_command(command: AST_Command, block_id: String, depth: int) -> void:
	var arguments: PackedStringArray = PackedStringArray()
	for i: int in command.args.size():
		var entry: Variant = command.args[i]
		var nested: AST_Node = null
		if entry is AST_Node:
			nested = entry
		if nested != null:
			# 对象参数（例如「攻击哪个角色」）：先求值，它自己的探针在它自己的代码行之前
			arguments.append(_emit_expression(nested, _arg_id(block_id, i), depth))
		else:
			arguments.append(_gd_literal(entry))
	_emit_probe(probe_id(command, block_id), depth)
	# opcode 也过一遍 var_to_str：万一它含引号，直接拼字符串会破坏生成出来的源码
	var opcode_literal: String = var_to_str(command.opcode)
	var call_text: String = "target.call(%s)" % opcode_literal
	if not arguments.is_empty():
		call_text = "target.call(%s, %s)" % [opcode_literal, ", ".join(arguments)]
	# await：指令可以是协程（例如边移动边播放动画），await 一个非协程值在本引擎里是合法的
	_line("await %s" % call_text, depth)


## 表达式 → 临时变量名。会先把自己的子节点（以及自己）按「代码行之前的探针」规则展开。
## [br]注意子节点的路径仍然按[结构路径]拼（block_id），只有探针 id 会优先用 uuid ——
## 这样「只给 statement / command 分配 uuid」的树也能正常工作。
func _emit_expression(expression: AST_Expression, block_id: String, depth: int) -> String:
	var probe: String = probe_id(expression, block_id)
	if expression.is_leaf():
		var temp: String = _new_temp()
		_emit_probe(probe, depth)
		_line("var %s = %s" % [temp, _leaf_code(expression.value)], depth)
		return temp

	var left_code: String = "null"
	if expression.left != null:
		left_code = _emit_expression(
			expression.left, _child_id(block_id, String(AST_BlockSchema.ROLE_LEFT)), depth
		)
	var right_code: String = "null"
	if expression.right != null:
		right_code = _emit_expression(
			expression.right, _child_id(block_id, String(AST_BlockSchema.ROLE_RIGHT)), depth
		)

	var operator: String = expression.operator
	if expression.right == null:
		# 一元
		if operator == "not":
			return _emit_expression_line(probe, "(not %s)" % left_code, depth)
		_emit_problem_operator(operator, probe)
		return _emit_expression_line(probe, "null", depth)
	return _emit_binary(probe, operator, left_code, right_code, depth)


func _emit_binary(block_id: String, operator: String, left_code: String, right_code: String, depth: int) -> String:
	if operator == "attach":
		return _emit_expression_line(block_id, '(bool(target.call("attach", %s, %s)) if target.has_method("attach") else false)' % [left_code, right_code], depth)
	if operator == "in":
		# 「左 IN 右」：右侧是带 contains() 的范围对象（CharacterRange / CharacterAttack）
		return _emit_expression_line(block_id, "(%s).contains(%s)" % [right_code, left_code], depth)
	if operator in AST_BlockSchema.MATH_OPERATORS:
		if operator == "/":
			# 块语言的除法是实数除法；GDScript 里整数相除会截断，统一提升为 float
			return _emit_expression_line(block_id, "(float(%s) / float(%s))" % [left_code, right_code], depth)
		return _emit_expression_line(block_id, "(%s %s %s)" % [left_code, operator, right_code], depth)
	if operator in AST_BlockSchema.LOGIC_OPERATORS:
		return _emit_expression_line(block_id, "(%s %s %s)" % [left_code, operator, right_code], depth)
	_emit_problem_operator(operator, block_id)
	return _emit_expression_line(block_id, "null", depth)


func _emit_expression_line(block_id: String, code: String, depth: int) -> String:
	var temp: String = _new_temp()
	_emit_probe(block_id, depth)
	_line("var %s = %s" % [temp, code], depth)
	return temp


func _emit_problem_operator(operator: String, block_id: String) -> void:
	problems.append("节点 %s 使用了未知运算符 '%s'，该处按 null 处理。" % [block_id, operator])


## 叶子操作数的 GDScript 代码。
## 字符串按「变量名」处理（与 [AST_TypeInference] 的口径一致：阶段一的模型里 value 同时
## 承载字面量与变量名），因此走 target.get()；其余类型是真正的字面量。
func _leaf_code(value: Variant) -> String:
	if typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME:
		if guard_variable_reads:
			return "_read_var(%s)" % var_to_str(String(value))
		return "target.get(%s)" % var_to_str(String(value))
	return _gd_literal(value)


## 任意值 → GDScript 字面量文本。var_to_str 保持浮点的 .0 尾巴与字符串引号，正好合用。
func _gd_literal(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
			return var_to_str(value)
		TYPE_ARRAY, TYPE_DICTIONARY:
			return var_to_str(value)
		_:
			problems.append("字面量 %s（类型 %s）无法转成 GDScript 字面量，按 null 处理。" % [
				str(value), type_string(typeof(value)),
			])
			return "null"


func _emit_probe(block_id: String, depth: int) -> void:
	if trace_mode == TraceMode.AWAIT:
		_line("await _probe(%s)" % var_to_str(block_id), depth)
	else:
		_line("trace_block.emit(%s)" % var_to_str(block_id), depth)


func _new_temp() -> String:
	var temp: String = "_t%d" % _temp_index
	_temp_index += 1
	return temp


## 语句体里真正存在的子节点（body / else_body 允许含 null，UI 侧同样只数真积木）。
func _real_body(children: Array[AST_Node]) -> Array[AST_Node]:
	var result: Array[AST_Node] = []
	for child: AST_Node in children:
		if child != null:
			result.append(child)
	return result


## 语句体的 (id, model) 列表：下标按「第几块真积木」计，与 UI 侧一致。
func _body_entries(
	body: Array[AST_Node], block_id: String, role_name: StringName = AST_BlockSchema.ROLE_BODY
) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for i: int in body.size():
		entries.append({
			"id": "%s.%s.%d" % [block_id, role_name, i],
			"model": body[i],
		})
	return entries


func _child_id(block_id: String, role_name: String) -> String:
	return "%s.%s" % [block_id, role_name]


## 对象参数的探针 id：挂在指令下面，形如 <指令id>.args.<下标>。
func _arg_id(block_id: String, index: int) -> String:
	return "%s.%s.%d" % [block_id, AST_BlockSchema.ROLE_ARG, index]


func _line(source: String, depth: int) -> void:
	if source.is_empty():
		_lines.append("")
		return
	_lines.append(INDENT.repeat(depth) + source)

# ------------------------------------------------------------------ UI 高亮对接

## 执行高亮器：把 [code]trace_block[/code] 信号变成「当前积木发光」。
##
## [br]它只做一件事：把被点到的那块积木的 theme type variation 换成
## [member executing_variation]，并负责把上一块还原回去 —— 外观本身（发光长什么样）
## 全部在 Art 的 theme 里定义，逻辑侧不写任何颜色（README §2 硬约束）。
##
## [br]用法：
## [codeblock]
## var highlighter := ASTCompiler.ExecutionHighlighter.new()
## highlighter.ui_root = workspace            # 积木树所在的根控件
## runner.connect(&"trace_block", highlighter.highlight)
## [/codeblock]
## [br]注意：常驻插槽（SlotUI）与装饰节点不吃 variation，只有真积木会发光。
class ExecutionHighlighter:
	## 积木树所在的根控件（[method ASTCompiler.find_block_by_id] 的查找起点）。
	var ui_root: Control = null
	## 执行中优先切换到哪个 theme type variation（在 Art 的 block_theme.tres 里注册）。
	## 主题里没注册它时，自动改用 [member fallback_stylebox_path] 做局部覆盖。
	var executing_variation: StringName = &"BlockExecuting"
	## 兜底的发光样式（Art 资源）。与 [ExpressionUI.apply_palette] 同一套路：
	## 样式本体来自 Art，逻辑侧只负责贴上去 / 撤下来，不写任何颜色。
	var fallback_stylebox_path: String = "res://BlockSystem/Art/Themes/block_stylebox_executing.tres"

	var _lit: Control = null
	var _previous_variation: StringName = &""
	var _used_override: bool = false

	## 点亮某块积木（可直接连到 trace_block 信号），返回被点亮的控件。
	func highlight(block_uuid: String) -> Control:
		var block: Control = preload("res://BlockSystem/Logic/BlockPathLookup.gd").find_block_by_id(ui_root, block_uuid)
		if block == _lit:
			return block  # 同一块（例如循环每轮重复点亮）不必重来
		restore()
		if block == null:
			return null
		_previous_variation = block.get_theme_type_variation()
		_used_override = not _theme_has_variation(block)
		if _used_override:
			var box: StyleBox = load(fallback_stylebox_path) as StyleBox
			if box == null:
				return null
			block.add_theme_stylebox_override(&"panel", box)
		else:
			block.set_theme_type_variation(executing_variation)
		_lit = block
		return block

	## 还原最后点亮的那块（执行结束 / 被中断时调用）。
	func restore() -> void:
		if _lit != null and is_instance_valid(_lit):
			if _used_override:
				# 撤掉局部覆盖后，请积木按调色板重新着色（apply_palette 是积木的公开 API）
				_lit.remove_theme_stylebox_override(&"panel")
				if _lit.has_method(&"apply_palette"):
					_lit.call(&"apply_palette")
			else:
				_lit.set_theme_type_variation(_previous_variation)
		_lit = null
		_used_override = false
		_previous_variation = &""

	## 当前正在发光的积木。
	func current_block() -> Control:
		return _lit

	## 主题里是否已经注册了执行中的变体（预制体自带 theme 是常见情形）。
	func _theme_has_variation(block: Control) -> bool:
		if executing_variation.is_empty():
			return false
		var theme: Theme = block.get_theme()
		if theme == null:
			return false
		return theme.has_stylebox(&"panel", executing_variation)
