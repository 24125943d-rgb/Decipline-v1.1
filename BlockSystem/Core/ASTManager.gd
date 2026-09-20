class_name ASTManager
extends RefCounted
## AST 序列化 / 反序列化门面 —— 纯数据层（Core）。
##
## 全局调用方式（无需注册 Autoload）：
##     var ast: AST_Node = ASTManager.parse_json_to_ast(json_text)
##     var json: String = ASTManager.serialize_ast_to_json(ast)
##
## 为什么不做成 Autoload：Godot 要求 Autoload 脚本必须继承 Node，否则启动时报
##     "Failed to instantiate an autoload, script '...' does not inherit from 'Node'."
## 而 Core 层按架构规范必须保持纯 RefCounted、零场景依赖。ASTManager 的全部
## API 都是静态方法，经 class_name 全局可见，使用体验与单例一致，且可在
## headless 测试中直接调用。
##
## 失败语义：解析出错时 push_error 并返回 null（序列化出错返回空串），
## 调用方只需做 null / 空串判断。

## JSON 输出的缩进字符。
const INDENT: String = "\t"


## 反序列化：JSON 文本 -> AST 树。失败时返回 null。
static func parse_json_to_ast(json_string: String) -> AST_Node:
	if json_string.strip_edges().is_empty():
		push_error("ASTManager.parse_json_to_ast: 输入为空字符串。")
		return null
	var parser: JSON = JSON.new()
	var error: Error = parser.parse(json_string)
	if error != OK:
		push_error("ASTManager.parse_json_to_ast: 第 %d 行解析失败（错误码 %d）：%s" % [
			maxi(parser.get_error_line(), 1), error, parser.get_error_message(),
		])
		return null
	return from_dictionary(parser.data)


## 把已解析的 JSON 数据还原成 AST 树（按 type 字段派发到具体子类）。
static func from_dictionary(payload: Variant) -> AST_Node:
	if typeof(payload) != TYPE_DICTIONARY:
		push_error("ASTManager.from_dictionary: 期望节点为 Dictionary，实际为 %s。" % type_string(typeof(payload)))
		return null
	var data: Dictionary = payload
	var kind: String = String(data.get("type", ""))
	match kind:
		AST_Statement.TYPE_STATEMENT:
			return _read_statement(data)
		AST_Command.TYPE_COMMAND:
			return _read_command(data)
		AST_Expression.TYPE_EXPRESSION:
			return _read_expression(data)
		_:
			push_error("ASTManager.from_dictionary: 未知节点类型 '%s'。" % kind)
			return null


## 序列化：AST 树 -> JSON 文本。缩进输出、键名排序，结果稳定可比对。失败时返回空串。
static func serialize_ast_to_json(ast_root: AST_Node) -> String:
	if ast_root == null:
		push_error("ASTManager.serialize_ast_to_json: 根节点为 null。")
		return ""
	return JSON.stringify(ast_root.to_dictionary(), INDENT, true)


static func _read_statement(data: Dictionary) -> AST_Statement:
	var statement: AST_Statement = AST_Statement.new()

	var raw_condition: Variant = data.get("condition", null)
	if raw_condition != null:
		statement.condition = from_dictionary(raw_condition) as AST_Expression
		if statement.condition == null:
			push_error("ASTManager: statement.condition 必须是 expression 节点。")
			return null

	var raw_body: Variant = data.get("body", [])
	if raw_body != null:
		if typeof(raw_body) != TYPE_ARRAY:
			push_error("ASTManager: statement.body 必须是数组。")
			return null
		var entries: Array = raw_body
		var body: Array[AST_Node] = []
		for entry: Variant in entries:
			var child: AST_Node = from_dictionary(entry)
			if child == null:
				push_error("ASTManager: statement.body 中存在无法解析的子节点。")
				return null
			body.append(child)
		statement.body = body

	return statement


static func _read_command(data: Dictionary) -> AST_Command:
	var command: AST_Command = AST_Command.new()
	command.opcode = String(data.get("opcode", ""))

	var raw_args: Variant = data.get("args", [])
	if raw_args != null:
		if typeof(raw_args) != TYPE_ARRAY:
			push_error("ASTManager: command.args 必须是数组。")
			return null
		# 归一化并深拷贝：让 AST 与外部 JSON 解析结果不共享容器引用。
		var args: Array = _normalize_value(raw_args)
		command.args = args

	return command


static func _read_expression(data: Dictionary) -> AST_Expression:
	var expression: AST_Expression = AST_Expression.new()
	expression.operator = String(data.get("operator", ""))
	expression.value = _normalize_value(data.get("value", null))

	var raw_left: Variant = data.get("left", null)
	if raw_left != null:
		expression.left = from_dictionary(raw_left) as AST_Expression
		if expression.left == null:
			push_error("ASTManager: expression.left 必须是 expression 节点。")
			return null

	var raw_right: Variant = data.get("right", null)
	if raw_right != null:
		expression.right = from_dictionary(raw_right) as AST_Expression
		if expression.right == null:
			push_error("ASTManager: expression.right 必须是 expression 节点。")
			return null

	return expression


## 归一化 JSON 读回的值，并深拷贝容器（避免 AST 与解析结果共享引用）。
##
## 归一化的原因：JSON 规范不区分整数与浮点数，Godot 的 JSON 解析器把所有数字
## 一律读成 float，于是 3 会变成 3.0。对积木语言而言（重复次数、步数、坐标）
## 这既会让序列化往返比对失败，也会让 UI 显示成 "3.0"。此处把「值为整数的
## float」还原成 int —— 由于 JSON.stringify 对 3 与 3.0 输出的文本完全相同，
## 这一步不丢失任何文件里本来就不存在的信息。
static func _normalize_value(p_value: Variant) -> Variant:
	match typeof(p_value):
		TYPE_FLOAT:
			return _normalize_number(p_value)
		TYPE_ARRAY:
			var source: Array = p_value
			var normalized: Array = []
			for item: Variant in source:
				normalized.append(_normalize_value(item))
			return normalized
		TYPE_DICTIONARY:
			var source_dict: Dictionary = p_value
			var normalized_dict: Dictionary = {}
			for key: Variant in source_dict:
				normalized_dict[key] = _normalize_value(source_dict[key])
			return normalized_dict
		_:
			return p_value


## 把整数值的 float 还原为 int；其余（含 2.5、inf、nan、超精度大数）原样保留。
##
## 上限 2^53(9007199254740992)：这是 double 能精确表示的最大整数。超过它的整数
## 在 JSON 往返回路上本就已经丢失精度，此时保持 float，绝不 int() 转换 ——
## 否则会溢出回绕成负数（如 int64 最大值会变成 -9223372036854775808）。
static func _normalize_number(p_value: Variant) -> Variant:
	var number: float = p_value
	if not is_finite(number):
		return p_value
	if number != floor(number):
		return p_value
	if absf(number) > 9007199254740992.0:
		return p_value
	return int(number)
