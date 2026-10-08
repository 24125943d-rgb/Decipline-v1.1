class_name AST_Variable
extends AST_Expression

## type 字段取值：与 [constant AST_Expression.TYPE_EXPRESSION] 并列的第四种节点种类。
const TYPE_VARIABLE: String = "variable"
## 变量引用节点：明确表达「读某个变量」，而不是一个含义模糊的字符串叶子。
##
## [br][b]为什么继承 [AST_Expression][/b]：刻意的选择。变量在语法上就是一个叶子操作数，
## 继承它之后 [member AST_Expression.left] / [member AST_Expression.right] 的类型不用放宽成
## [AST_Node]，于是既有的一切照旧工作、一行都不用改：
## [br]· [AST_TypeInference]：裸变量名判成 UNKNOWN（有符号表时再收紧）
## [br]· [AST_BlockSchema.palette_category]：字符串叶子 → 变量色
## [br]· 视图层：复用表达式积木（[code]kind_of()[/code] 仍返回 expression），不用新做预制体
##
## [br]序列化形状：[code]{ "type": "variable", "name": "enemies_visible" }[/code]
## [br]变量名存在 [member AST_Expression.value] 里（与叶子操作数同形），
## [member variable_name] 只是它的具名读写入口。

## 变量名（与 [member AST_Expression.value] 是同一份存储，双向同步）。
var variable_name: String:
	get:
		return String(value) if value != null else ""
	set(new_name):
		value = new_name


func _init(p_variable_name: String = "") -> void:
	type = TYPE_VARIABLE
	value = p_variable_name


func to_dictionary() -> Dictionary:
	var payload: Dictionary = _payload()
	payload["name"] = variable_name
	return payload


func _to_string() -> String:
	return "<AST_Variable %s>" % variable_name
