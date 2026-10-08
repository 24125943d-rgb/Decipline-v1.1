extends Node
## BlockSystem Core 层「AST 结构化描述」与「结果类型推断」单元测试。
##
## 运行器约定：extends Node，方法名以 test_ 开头，返回 null = 通过、字符串 = 失败原因。
##
## 覆盖 README §2 阶段四 / 阶段五的三条纯静态知识：
##   AST_BlockSchema.kind_of / child_roles / palette_category / required_roles / role_requires_boolean
##   AST_TypeInference.result_type / is_boolean_result / describe
## 另含一条跨层契约测试：Core 的类别键必须与 Art 的 BlockPalette.CATEGORY_* 取值一致
## —— README 明说这是「由 Logic 侧负责对接」的人工耦合，没有编译器保护，
## 改一侧忘另一侧会静默变色，所以值得钉住。

var _failures: PackedStringArray = PackedStringArray()


func before_each() -> void:
	_failures.clear()

# ------------------------------------------------------------------ 种类
func test_kind_of_the_three_node_kinds() -> Variant:
	_check_eq(AST_BlockSchema.kind_of(AST_Statement.new()), AST_BlockSchema.KIND_STATEMENT, "语句")
	_check_eq(AST_BlockSchema.kind_of(AST_Command.new()), AST_BlockSchema.KIND_COMMAND, "指令")
	_check_eq(AST_BlockSchema.kind_of(AST_Expression.new()), AST_BlockSchema.KIND_EXPRESSION, "表达式")
	# 未知（裸基类）返回空串，供视图侧判断「没有模板可用」
	_check_eq(AST_BlockSchema.kind_of(AST_Node.new()), &"", "裸 AST_Node → 空串")
	return _verdict("test_kind_of_the_three_node_kinds")

# ------------------------------------------------------------------ 子节点角色
func test_child_roles_of_statement_put_condition_first() -> Variant:
	var statement: AST_Statement = AST_Statement.new()
	statement.condition = _literal("flag")
	statement.body = [_command("a"), _command("b"), _command("c")] as Array[AST_Node]
	var roles: Array[Dictionary] = AST_BlockSchema.child_roles(statement)
	_check_eq(roles.size(), 4, "1 个条件 + 3 条语句体")
	if roles.size() == 4:
		_check_eq(roles[0]["role"], AST_BlockSchema.ROLE_CONDITION, "第一个是 condition")
		_check_eq(roles[1]["role"], AST_BlockSchema.ROLE_BODY, "之后都是 body")
		var opcodes: PackedStringArray = PackedStringArray()
		for entry: Dictionary in roles:
			var model: AST_Node = entry["model"]
			if model is AST_Command:
				opcodes.append((model as AST_Command).opcode)
		_check_eq(opcodes, PackedStringArray(["a", "b", "c"]), "语句体顺序保持")
		_check_eq(roles[0]["model"], statement.condition, "condition 槽指向同一个对象")
	return _verdict("test_child_roles_of_statement_put_condition_first")


func test_child_roles_ignore_missing_or_empty_children() -> Variant:
	var bare_statement: AST_Statement = AST_Statement.new()
	_check_eq(AST_BlockSchema.child_roles(bare_statement).size(), 0, "无条件无体的语句没有子节点")
	var with_null: AST_Statement = AST_Statement.new()
	with_null.body = [null, _command("only"), null] as Array[AST_Node]
	_check_eq(AST_BlockSchema.child_roles(with_null).size(), 1, "body 里的 null 会被跳过")
	_check_eq(AST_BlockSchema.child_roles(AST_Command.new()).size(), 0, "指令没有子节点角色")
	_check_eq(AST_BlockSchema.child_roles(_literal(1)).size(), 0, "叶子没有子节点角色")
	return _verdict("test_child_roles_ignore_missing_or_empty_children")


func test_child_roles_of_expression() -> Variant:
	var binary: AST_Expression = AST_Expression.make_binary("+", _literal(1), _literal(2))
	var roles: Array[Dictionary] = AST_BlockSchema.child_roles(binary)
	_check_eq(roles.size(), 2, "二元表达式两个操作数")
	if roles.size() == 2:
		_check_eq(roles[0]["role"], AST_BlockSchema.ROLE_LEFT, "先 left")
		_check_eq(roles[1]["role"], AST_BlockSchema.ROLE_RIGHT, "后 right")
	var unary: AST_Expression = AST_Expression.make_binary("not", _literal(true))
	_check_eq(AST_BlockSchema.child_roles(unary).size(), 1, "一元只有 left")
	return _verdict("test_child_roles_of_expression")

# ------------------------------------------------------------------ 调色板类别
func test_palette_category_of_operators() -> Variant:
	for operator: String in AST_BlockSchema.LOGIC_OPERATORS:
		_check_eq(
			AST_BlockSchema.palette_category(_binary(operator)), AST_BlockSchema.CATEGORY_LOGIC,
			"逻辑运算符 '%s' 归逻辑色" % operator
		)
	for operator: String in AST_BlockSchema.MATH_OPERATORS:
		_check_eq(
			AST_BlockSchema.palette_category(_binary(operator)), AST_BlockSchema.CATEGORY_MATH,
			"算术运算符 '%s' 归数学色" % operator
		)
	return _verdict("test_palette_category_of_operators")


func test_palette_category_of_leaves_by_value_type() -> Variant:
	_check_eq(AST_BlockSchema.palette_category(_literal("score")), AST_BlockSchema.CATEGORY_VARIABLE, "变量名")
	_check_eq(AST_BlockSchema.palette_category(_literal(&"flag")), AST_BlockSchema.CATEGORY_VARIABLE, "StringName 同样按变量名")
	_check_eq(AST_BlockSchema.palette_category(_literal(true)), AST_BlockSchema.CATEGORY_LOGIC, "布尔字面量")
	_check_eq(AST_BlockSchema.palette_category(_literal(3)), AST_BlockSchema.CATEGORY_MATH, "整数字面量")
	_check_eq(AST_BlockSchema.palette_category(_literal(3.5)), AST_BlockSchema.CATEGORY_MATH, "浮点字面量")
	return _verdict("test_palette_category_of_leaves_by_value_type")


func test_palette_category_of_nodes_and_fallbacks() -> Variant:
	_check_eq(AST_BlockSchema.palette_category(AST_Command.new()), AST_BlockSchema.CATEGORY_COMMAND, "指令")
	_check_eq(AST_BlockSchema.palette_category(AST_Statement.new()), AST_BlockSchema.CATEGORY_STATEMENT, "语句")
	# 未知运算符不能没颜色：保守归到逻辑色（README 明确写了这条降级策略）
	_check_eq(AST_BlockSchema.palette_category(_binary("??")), AST_BlockSchema.CATEGORY_LOGIC, "未知运算符降级到逻辑色")
	return _verdict("test_palette_category_of_nodes_and_fallbacks")


## 跨层契约：Core 不引用 Art，二者靠「取值一致」对齐，只能靠测试守住。
func test_category_keys_match_palette_constants() -> Variant:
	_check_eq(AST_BlockSchema.CATEGORY_VARIABLE, BlockPalette.CATEGORY_VARIABLE, "variable 键")
	_check_eq(AST_BlockSchema.CATEGORY_MATH, BlockPalette.CATEGORY_MATH, "math 键")
	_check_eq(AST_BlockSchema.CATEGORY_LOGIC, BlockPalette.CATEGORY_LOGIC, "logic 键")
	_check_eq(AST_BlockSchema.CATEGORY_COMMAND, BlockPalette.CATEGORY_COMMAND, "command 键")
	_check_eq(AST_BlockSchema.CATEGORY_STATEMENT, BlockPalette.CATEGORY_STATEMENT, "statement 键")
	# 反向也要成立：schema 判出的每个类别，调色板都得有对应颜色可用
	var palette: BlockPalette = load(BlockSyncEngine.DEFAULT_PALETTE) as BlockPalette
	_check(palette != null, "默认调色板能加载")
	if palette != null:
		for category: StringName in [
			AST_BlockSchema.palette_category(AST_Command.new()),
			AST_BlockSchema.palette_category(AST_Statement.new()),
			AST_BlockSchema.palette_category(_binary("+")),
			AST_BlockSchema.palette_category(_binary(">")),
			AST_BlockSchema.palette_category(_literal("x")),
		]:
			_check(palette.validate().is_empty(), "默认调色板自检通过")
			_check_eq(
				palette.get_color_for_category(category), palette.get(category + "_color"),
				"类别 '%s' 取到的颜色就是对应的颜色字段" % category
			)
	return _verdict("test_category_keys_match_palette_constants")

# ------------------------------------------------------------------ 必填角色
func test_required_roles_follow_the_current_model() -> Variant:
	var binary: AST_Expression = AST_Expression.make_binary("+", _literal(1), _literal(2))
	_check_eq(
		AST_BlockSchema.required_roles(binary),
		[AST_BlockSchema.ROLE_LEFT, AST_BlockSchema.ROLE_RIGHT] as Array[StringName],
		"a + b：左右都必填"
	)
	var unary: AST_Expression = AST_Expression.make_binary("not", _literal(true))
	_check_eq(
		AST_BlockSchema.required_roles(unary), [AST_BlockSchema.ROLE_LEFT] as Array[StringName],
		"not x：只有 left 必填（right 本来就是空的）"
	)
	_check_eq(AST_BlockSchema.required_roles(_literal(3)).size(), 0, "叶子没有必填位")
	_check_eq(AST_BlockSchema.required_roles(AST_Command.new()).size(), 0, "指令没有必填位")
	var with_condition: AST_Statement = AST_Statement.new()
	with_condition.condition = _literal("flag")
	_check_eq(
		AST_BlockSchema.required_roles(with_condition), [AST_BlockSchema.ROLE_CONDITION] as Array[StringName],
		"有条件的语句：condition 必填"
	)
	_check_eq(AST_BlockSchema.required_roles(AST_Statement.new()).size(), 0, "无条件语句（循环 / else）不要求占位")
	return _verdict("test_required_roles_follow_the_current_model")


func test_role_requires_boolean_only_for_condition() -> Variant:
	_check(AST_BlockSchema.role_requires_boolean(AST_BlockSchema.ROLE_CONDITION), "condition 要求布尔")
	_check(not AST_BlockSchema.role_requires_boolean(AST_BlockSchema.ROLE_BODY), "body 不限")
	_check(not AST_BlockSchema.role_requires_boolean(AST_BlockSchema.ROLE_LEFT), "left 不限")
	_check(not AST_BlockSchema.role_requires_boolean(AST_BlockSchema.ROLE_RIGHT), "right 不限")
	return _verdict("test_role_requires_boolean_only_for_condition")

# ------------------------------------------------------------------ 结果类型推断
func test_result_type_of_operators_and_leaves() -> Variant:
	_check_eq(
		AST_TypeInference.result_type(_binary(">")), AST_TypeInference.ResultType.BOOLEAN, "比较 → 布尔"
	)
	_check_eq(
		AST_TypeInference.result_type(AST_Expression.make_binary("and", _literal(true), _literal(false))),
		AST_TypeInference.ResultType.BOOLEAN, "逻辑运算 → 布尔"
	)
	_check_eq(AST_TypeInference.result_type(_binary("+")), AST_TypeInference.ResultType.NUMBER, "算术 → 数值")
	_check_eq(AST_TypeInference.result_type(_literal(3)), AST_TypeInference.ResultType.NUMBER, "整数字面量 → 数值")
	_check_eq(AST_TypeInference.result_type(_literal(3.5)), AST_TypeInference.ResultType.NUMBER, "浮点字面量 → 数值")
	_check_eq(AST_TypeInference.result_type(_literal(true)), AST_TypeInference.ResultType.BOOLEAN, "布尔字面量 → 布尔")
	# 裸字符串既可能是变量名也可能是文本字面量（阶段一没有符号表）→ 只能判成 UNKNOWN
	_check_eq(AST_TypeInference.result_type(_literal("flag")), AST_TypeInference.ResultType.UNKNOWN, "裸名字 → 未知")
	return _verdict("test_result_type_of_operators_and_leaves")


func test_result_type_of_unrelated_nodes_is_unknown() -> Variant:
	_check_eq(AST_TypeInference.result_type(AST_Command.new()), AST_TypeInference.ResultType.UNKNOWN, "指令 → 未知")
	_check_eq(AST_TypeInference.result_type(AST_Statement.new()), AST_TypeInference.ResultType.UNKNOWN, "语句 → 未知")
	# 非叶子 + 未知运算符：运算符表里查不到，也不能当叶子处理
	_check_eq(AST_TypeInference.result_type(_binary("??")), AST_TypeInference.ResultType.UNKNOWN, "未知运算符 → 未知")
	return _verdict("test_result_type_of_unrelated_nodes_is_unknown")


func test_boolean_slot_acceptance() -> Variant:
	_check(AST_TypeInference.is_boolean_result(_binary(">")), "比较结果放行")
	_check(AST_TypeInference.is_boolean_result(_literal(true)), "布尔字面量放行")
	_check(AST_TypeInference.is_boolean_result(_literal("flag")), "未知类型放行（否则 if flag 永远填不进去）")
	_check(not AST_TypeInference.is_boolean_result(_literal(3)), "数字被拦下")
	_check(not AST_TypeInference.is_boolean_result(_binary("+")), "算术表达式被拦下")
	# 指令的结果类型是 UNKNOWN，按「放行 UNKNOWN」的策略这道类型闸会放行 ——
	# 拦下指令是 SlotUI 种类白名单的职责（见 Logic 层的插槽拒绝原因用例），两道闸各管一件事
	_check(
		AST_TypeInference.is_boolean_result(AST_Command.new()),
		"指令是 UNKNOWN：类型闸放行，由种类闸拦截"
	)
	return _verdict("test_boolean_slot_acceptance")


func test_describe_names() -> Variant:
	_check_eq(AST_TypeInference.describe(AST_TypeInference.ResultType.BOOLEAN), "Boolean", "布尔类型名")
	_check_eq(AST_TypeInference.describe(AST_TypeInference.ResultType.NUMBER), "Number", "数值类型名")
	_check_eq(AST_TypeInference.describe(AST_TypeInference.ResultType.TEXT), "Text", "文本类型名")
	_check_eq(AST_TypeInference.describe(AST_TypeInference.ResultType.UNKNOWN), "Unknown", "未知类型名")
	return _verdict("test_describe_names")

# ------------------------------------------------------------------ 工具
func _literal(value: Variant) -> AST_Expression:
	return AST_Expression.make_literal(value)


func _binary(operator: String) -> AST_Expression:
	return AST_Expression.make_binary(operator, _literal(1), _literal(2))


func _command(opcode: String) -> AST_Command:
	return AST_Command.new(opcode)


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
