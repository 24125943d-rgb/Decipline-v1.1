extends Node
## BlockSystem Core 层（纯数据）单元测试：AST ⇄ JSON 往返与数值归一化。
##
## 运行器约定：extends Node，方法名以 test_ 开头，返回 null = 通过、字符串 = 失败原因。
##
## 覆盖 README §2「Core 零引擎依赖、可 headless 单测」与 §7.4「JSON 数字一律读成 float」
## 的处理结果：整数归一化回 int、超 2^53 的大数保持 float、容器深拷贝不共享引用。
## 失败路径（空串 / 非法 JSON / 未知 type）不在此测 —— 它们按契约 push_error，
## 而测试运行器把任何 stderr 输出判为失败，属于「需要扩展运行器才能覆盖」的部分。

## 演示程序：if (score > 3) { move_forward 3 fast; turn_left 90; repeat { say hello } }
const DEMO_JSON: String = """
{
	"type": "statement",
	"condition": {"type": "expression", "operator": ">", "left": {"type": "expression", "operator": "", "left": null, "right": null, "value": "score"}, "right": {"type": "expression", "operator": "", "left": null, "right": null, "value": 3}, "value": null},
	"body": [
		{"type": "command", "opcode": "move_forward", "args": [3, "fast"]},
		{"type": "command", "opcode": "turn_left", "args": [90]},
		{"type": "statement", "condition": null, "body": [{"type": "command", "opcode": "say", "args": ["hello"]}]}
	]
}
"""

var _failures: PackedStringArray = PackedStringArray()


func before_each() -> void:
	_failures.clear()

# ------------------------------------------------------------------ 往返
func test_json_round_trip_is_stable() -> Variant:
	var first: AST_Node = ASTManager.parse_json_to_ast(DEMO_JSON)
	_check(first != null, "能解析演示程序")
	if first == null:
		return _verdict("test_json_round_trip_is_stable")
	var text: String = ASTManager.serialize_ast_to_json(first)
	var second: AST_Node = ASTManager.parse_json_to_ast(text)
	_check(second != null, "能解析回自己序列化出的文本")
	if second != null:
		_check_eq(second.to_dictionary(), first.to_dictionary(), "往返后结构一致")
		_check_eq(ASTManager.serialize_ast_to_json(second), text, "两次序列化文本完全相同（可直接 diff）")
	return _verdict("test_json_round_trip_is_stable")


func test_from_dictionary_dispatches_to_subclasses() -> Variant:
	var root: AST_Node = ASTManager.parse_json_to_ast(DEMO_JSON)
	_check(root is AST_Statement, "根是 AST_Statement")
	if root is AST_Statement:
		var statement: AST_Statement = root
		_check(statement.condition is AST_Expression, "condition 是 AST_Expression")
		_check_eq(statement.body.size(), 3, "语句体有 3 条")
		if statement.body.size() == 3:
			_check(statement.body[0] is AST_Command, "第 1 条是指令")
			_check(statement.body[2] is AST_Statement, "第 3 条是嵌套语句")
	return _verdict("test_from_dictionary_dispatches_to_subclasses")


func test_body_order_is_preserved() -> Variant:
	var root: AST_Node = ASTManager.parse_json_to_ast(DEMO_JSON)
	var opcodes: PackedStringArray = PackedStringArray()
	if root is AST_Statement:
		for child: AST_Node in (root as AST_Statement).body:
			if child is AST_Command:
				opcodes.append((child as AST_Command).opcode)
	_check_eq(
		opcodes, PackedStringArray(["move_forward", "turn_left"]),
		"前两条指令顺序保持（嵌套语句不算指令）"
	)
	return _verdict("test_body_order_is_preserved")


func test_serialize_sorts_keys_and_indents_with_tab() -> Variant:
	var expression: AST_Expression = AST_Expression.make_binary(
		">", AST_Expression.make_literal("score"), AST_Expression.make_literal(3)
	)
	var text: String = ASTManager.serialize_ast_to_json(expression)
	_check(text.contains("\t"), "缩进用的是制表符（Git 可 diff）")
	# 键名排序（sort_keys=true）：同一个节点的键按字母序输出，文本才稳定可比对
	var left_at: int = text.find("\"left\"")
	var operator_at: int = text.find("\"operator\"")
	var type_at: int = text.find("\"type\"")
	_check(left_at >= 0 and operator_at >= 0 and type_at >= 0, "三个键都在输出里")
	_check(left_at < operator_at and operator_at < type_at, "键按字母序输出（left < operator < type）")
	return _verdict("test_serialize_sorts_keys_and_indents_with_tab")


func test_deep_nesting_survives_round_trip() -> Variant:
	# 30 层 "not"(...) 嵌套：递归构建 + 递归序列化/解析都应正常
	var depth: int = 30
	var node: AST_Expression = AST_Expression.make_literal(true)
	for _i: int in depth:
		node = AST_Expression.make_binary("not", node)
	var root: AST_Node = ASTManager.parse_json_to_ast(ASTManager.serialize_ast_to_json(node))
	_check(root != null, "深层嵌套能解析回来")
	if root != null:
		_check_eq(root.to_dictionary(), node.to_dictionary(), "深层嵌套结构一致")
		var counted: int = 0
		var cursor: AST_Expression = root as AST_Expression
		while cursor != null and cursor.left != null:
			counted += 1
			cursor = cursor.left
		_check_eq(counted, depth, "层数没有丢")
	return _verdict("test_deep_nesting_survives_round_trip")

# ------------------------------------------------------------------ §7.4 数值归一化
func test_json_integers_normalize_to_int() -> Variant:
	var root: AST_Node = ASTManager.parse_json_to_ast(
		"{\"type\": \"command\", \"opcode\": \"m\", \"args\": [3, -2, 3.5, 1e3, true, \"s\"]}"
	)
	_check(root is AST_Command, "解析成指令")
	if not (root is AST_Command):
		return _verdict("test_json_integers_normalize_to_int")
	var args: Array = (root as AST_Command).args
	_check_eq(args.size(), 6, "6 个实参")
	_check_eq(typeof(args[0]), TYPE_INT, "3 读回 int（不显示成 3.0）")
	_check_eq(args[0], 3, "3 的值")
	_check_eq(typeof(args[1]), TYPE_INT, "-2 读回 int")
	_check_eq(args[1], -2, "-2 的值")
	_check_eq(typeof(args[2]), TYPE_FLOAT, "3.5 保持 float")
	_check_eq(args[2], 3.5, "3.5 的值")
	_check_eq(typeof(args[3]), TYPE_INT, "1e3 是整数值 → 归一化成 int")
	_check_eq(args[3], 1000, "1e3 的值")
	_check_eq(typeof(args[4]), TYPE_BOOL, "布尔不受影响")
	_check_eq(typeof(args[5]), TYPE_STRING, "字符串不受影响")
	return _verdict("test_json_integers_normalize_to_int")


func test_big_integer_beyond_double_precision_stays_float() -> Variant:
	# 上限 2^53：超过它的整数在 JSON 往返回路上本就失去精确表示，
	# 强行 int() 会溢出回绕成负数（见 ASTManager._normalize_number 注释）。
	# 取样别用 2^53 + 1：它的 float 值正好舍入回 2^53，此时 int() 仍是精确的，不算越界。
	var root: AST_Node = ASTManager.parse_json_to_ast(
		"{\"type\": \"command\", \"opcode\": \"m\", \"args\": [1e19]}"
	)
	if not (root is AST_Command):
		_check(false, "解析成指令")
		return _verdict("test_big_integer_beyond_double_precision_stays_float")
	var value: Variant = (root as AST_Command).args[0]
	_check_eq(typeof(value), TYPE_FLOAT, "超 2^53 的整数保持 float（不 int() 回绕）")
	_check(float(value) > 9007199254740992.0, "值仍在 2^53 之上")
	_check(float(value) > 0.0, "依然是正数（没有溢出成负数）")
	return _verdict("test_big_integer_beyond_double_precision_stays_float")


func test_container_args_are_deep_copied() -> Variant:
	var source: Dictionary = {
		"type": "command",
		"opcode": "m",
		"args": [{"nested": [1, 2]}, [3]],
	}
	var root: AST_Node = ASTManager.from_dictionary(source)
	if not (root is AST_Command):
		_check(false, "解析成指令")
		return _verdict("test_container_args_are_deep_copied")
	# 改原始字典：AST 里不应跟着变（README：让 AST 与外部解析结果不共享容器引用）
	source["args"] = ["mutated"]
	_check_eq((root as AST_Command).args.size(), 2, "AST 的 args 没被外部改动影响")
	_check((root as AST_Command).args[0] is Dictionary, "嵌套字典仍是字典")
	if (root as AST_Command).args[0] is Dictionary:
		var nested: Dictionary = (root as AST_Command).args[0]
		_check_eq(nested["nested"], [1, 2], "嵌套数组内容保持")
	return _verdict("test_container_args_are_deep_copied")


func test_nested_args_are_normalized_too() -> Variant:
	# 嵌套数组里的数字同样要归一化（_normalize_value 递归处理容器）
	var root: AST_Node = ASTManager.parse_json_to_ast(
		"{\"type\": \"command\", \"opcode\": \"m\", \"args\": [[1]]}"
	)
	if not (root is AST_Command):
		_check(false, "解析成指令")
		return _verdict("test_nested_args_are_normalized_too")
	var inner: Array = (root as AST_Command).args[0]
	_check_eq(inner.size(), 1, "内层数组只有 1 项")
	_check_eq(typeof(inner[0]), TYPE_INT, "内层数字也归一化了")
	return _verdict("test_nested_args_are_normalized_too")

# ------------------------------------------------------------------ 节点自身契约
func test_every_node_carries_its_type_field() -> Variant:
	var statement: AST_Node = ASTManager.from_dictionary({"type": "statement"})
	var command: AST_Node = ASTManager.from_dictionary({"type": "command"})
	var expression: AST_Node = ASTManager.from_dictionary({"type": "expression"})
	_check_eq(statement.to_dictionary().get("type"), AST_Statement.TYPE_STATEMENT, "statement 的 type 字段")
	_check_eq(command.to_dictionary().get("type"), AST_Command.TYPE_COMMAND, "command 的 type 字段")
	_check_eq(
		expression.to_dictionary().get("type"), AST_Expression.TYPE_EXPRESSION,
		"expression 的 type 字段"
	)
	_check_eq(statement.to_dictionary().keys().size(), 3, "statement 序列化出 3 个键")
	_check_eq(command.to_dictionary().keys().size(), 3, "command 序列化出 3 个键")
	_check_eq(expression.to_dictionary().keys().size(), 5, "expression 序列化出 5 个键")
	return _verdict("test_every_node_carries_its_type_field")


func test_expression_helpers_build_expected_shapes() -> Variant:
	var leaf: AST_Expression = AST_Expression.make_literal(7)
	_check(leaf.is_leaf(), "字面量是叶子")
	_check_eq(leaf.value, 7, "字面量值")
	_check(leaf.left == null and leaf.right == null, "叶子没有子表达式")
	var binary: AST_Expression = AST_Expression.make_binary(
		"+", AST_Expression.make_literal(1), AST_Expression.make_literal(2)
	)
	_check(not binary.is_leaf(), "运算符节点不是叶子")
	_check_eq(binary.operator, "+", "运算符")
	_check(binary.left != null and binary.right != null, "两个操作数都在")
	var unary: AST_Expression = AST_Expression.make_binary("not", AST_Expression.make_literal(true))
	_check(not unary.is_leaf(), "一元节点不是叶子")
	_check(unary.right == null, "一元节点没有右操作数")
	return _verdict("test_expression_helpers_build_expected_shapes")

# ------------------------------------------------------------------ 工具
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
