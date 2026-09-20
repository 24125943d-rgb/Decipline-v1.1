class_name AST_BlockSchema
extends RefCounted
## AST 结构化描述 —— 纯数据层，零 Node / 零场景依赖。
##
## 只回答「AST 层面的事实」：
##   - 这个节点是什么种类（kind）
##   - 它哪些字段是子节点、按什么顺序（role）
##   - 它该归到哪个调色板类别（category）
##
## 它**不知道**任何视图事实：不知道 .tscn 路径，也不知道 UI 脚本的插槽属性名。
## 那些属于视图层（Logic/BlockSyncEngine.gd 的 TEMPLATES / ROLE_SLOTS）。
## 这样分层的好处：新增一种积木时，Core 只需说清它的数据结构，
## 视图只需给出模板与插槽，两边可各自演进、各自测试。
##
## 注意：本文件不引用 Art/ 的 BlockPalette（保持 Core 只依赖自身），
## 类别键与 BlockPalette.CATEGORY_* 取值一致，由 Logic 侧负责对接。

## 种类标识（与视图层的模板注册表一一对应）。
const KIND_STATEMENT: StringName = &"statement"
const KIND_COMMAND: StringName = &"command"
const KIND_EXPRESSION: StringName = &"expression"

## 子节点角色名：直接取自 AST 的字段名，不是 UI 插槽名。
const ROLE_CONDITION: StringName = &"condition"
const ROLE_BODY: StringName = &"body"
const ROLE_LEFT: StringName = &"left"
const ROLE_RIGHT: StringName = &"right"

## 调色板类别键。
const CATEGORY_VARIABLE: StringName = &"variable"
const CATEGORY_MATH: StringName = &"math"
const CATEGORY_LOGIC: StringName = &"logic"
const CATEGORY_COMMAND: StringName = &"command"
const CATEGORY_STATEMENT: StringName = &"statement"

## 运算符分组表（数据表，不是分支逻辑）。
const MATH_OPERATORS: PackedStringArray = ["+", "-", "*", "/", "%"]
const LOGIC_OPERATORS: PackedStringArray = [">", "<", ">=", "<=", "==", "!=", "and", "or", "not"]


## 节点种类。未知类型返回空串。
static func kind_of(model: AST_Node) -> StringName:
	if model is AST_Statement:
		return KIND_STATEMENT
	if model is AST_Command:
		return KIND_COMMAND
	if model is AST_Expression:
		return KIND_EXPRESSION
	return &""


## 子节点清单，顺序为：先 condition / 操作数，再 body 里的各条语句（保持原有顺序）。
## 每项形如 {"role": &"body", "model": <AST_Node>}。
static func child_roles(model: AST_Node) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if model is AST_Statement:
		var statement: AST_Statement = model
		if statement.condition != null:
			entries.append({"role": ROLE_CONDITION, "model": statement.condition})
		for child: AST_Node in statement.body:
			if child != null:
				entries.append({"role": ROLE_BODY, "model": child})
	elif model is AST_Expression:
		var expression: AST_Expression = model
		if expression.left != null:
			entries.append({"role": ROLE_LEFT, "model": expression.left})
		if expression.right != null:
			entries.append({"role": ROLE_RIGHT, "model": expression.right})
	return entries


## 调色板类别：由节点自身语义决定，与视图无关。
static func palette_category(model: AST_Node) -> StringName:
	if model is AST_Command:
		return CATEGORY_COMMAND
	if model is AST_Statement:
		return CATEGORY_STATEMENT
	if model is AST_Expression:
		var expression: AST_Expression = model
		if expression.is_leaf():
			return _leaf_category(expression.value)
		if expression.operator in LOGIC_OPERATORS:
			return CATEGORY_LOGIC
		if expression.operator in MATH_OPERATORS:
			return CATEGORY_MATH
		# 未知运算符归到逻辑色：宁可保守，也不要让它在界面上没有颜色。
		return CATEGORY_LOGIC
	return CATEGORY_STATEMENT


## 叶子操作数的类别：变量名 / 布尔 / 数值各有归属。
static func _leaf_category(value: Variant) -> StringName:
	match typeof(value):
		TYPE_STRING, TYPE_STRING_NAME:
			return CATEGORY_VARIABLE
		TYPE_BOOL:
			return CATEGORY_LOGIC
		_:
			return CATEGORY_MATH


## 必填角色：这些角色一旦变空，视图必须补占位，否则表达式 / 语句会断裂
## （结构退化为 `[空槽] + b`，而不是 `+ b`）。
##
## 判定规则：**模型当前在该位置有子节点**，就说明这个位置是必填的。
## 于是：
##   - `a + b`  → left、right 都是必填，任一被拖走都要补占位
##   - `not x`  → 只有 left（一元，right 本来就是空的，不要求）
##   - 叶子     → 没有必填位
##   - 有条件的语句 → condition 必填；无条件语句（循环 / else）不要求
##
## 注意这里有个已知边界：如果 AST 从一开始就是残缺的（二元运算符但 left 为 null），
## 本函数不会要求补占位 —— 因为模型从未声明那里有过东西。残缺 AST 的校验
## 属于另一个关注点（需要独立于当前取值的「期望槽位」描述），本阶段不做。
static func required_roles(model: AST_Node) -> Array[StringName]:
	var roles: Array[StringName] = []
	if model is AST_Statement:
		if (model as AST_Statement).condition != null:
			roles.append(ROLE_CONDITION)
	elif model is AST_Expression:
		var expression: AST_Expression = model
		if expression.left != null:
			roles.append(ROLE_LEFT)
		if expression.right != null:
			roles.append(ROLE_RIGHT)
	return roles


## 该角色是否要求「布尔结果」的载荷。
## 这是插槽强类型校验的唯一真相来源：If 条件槽要求布尔，其余不限。
static func role_requires_boolean(role: StringName) -> bool:
	return role == ROLE_CONDITION
