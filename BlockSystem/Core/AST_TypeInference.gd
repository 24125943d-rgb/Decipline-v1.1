class_name AST_TypeInference
extends RefCounted
## AST 结果类型推断 —— 纯数据层，零 Node 依赖。
##
## 只回答一个问题：「这个表达式求值出来是什么类型」，供插槽做强类型校验。
## 没有符号表，所以裸变量名只能判成 UNKNOWN（见 is_boolean_result 的策略说明）。

enum ResultType {
	UNKNOWN,   ## 无法判定（裸变量名、命令、语句）
	BOOLEAN,   ## 比较与逻辑运算的结果
	NUMBER,    ## 算术运算与数值字面量
	TEXT,      ## 保留：等字面量与变量名能被区分时才会用到
}

## 布尔插槽是否放行 UNKNOWN。
##
## 策略说明：阶段一的模型里，叶子 String 既可能是变量名也可能是文本字面量，
## 且没有符号表。如果一律拒绝 UNKNOWN，那么 `if flag` 这类布尔变量将永远无法进入条件槽。
## 因此默认放行 UNKNOWN —— 仍然会拦下**已能确定类型**的不符者（数字、算术表达式）。
## 要改成严格模式，把这里置 false 即可，其它代码无需改动。
const ACCEPT_UNKNOWN_IN_BOOLEAN_SLOTS: bool = true


## 结果类型推断。运算符优先于叶子值。
static func result_type(model: AST_Node) -> ResultType:
	if model is AST_Expression:
		var expression: AST_Expression = model
		if expression.operator in AST_BlockSchema.LOGIC_OPERATORS:
			return ResultType.BOOLEAN  # > < >= <= == != and or not 的结果都是布尔
		if expression.operator in AST_BlockSchema.MATH_OPERATORS:
			return ResultType.NUMBER
		if expression.is_leaf():
			return _leaf_type(expression.value)
		return ResultType.UNKNOWN
	return ResultType.UNKNOWN


## 裸字符串按「变量名」处理（阶段一里 value 同时承载字面量与变量名），
## 类型未知，因此是 UNKNOWN 而不是 TEXT。
static func _leaf_type(value: Variant) -> ResultType:
	match typeof(value):
		TYPE_BOOL:
			return ResultType.BOOLEAN
		TYPE_INT, TYPE_FLOAT:
			return ResultType.NUMBER
		TYPE_STRING, TYPE_STRING_NAME:
			return ResultType.UNKNOWN
		_:
			return ResultType.UNKNOWN


## 能否放进「要求布尔结果」的槽位（If 条件）。
static func is_boolean_result(model: AST_Node) -> bool:
	var result: ResultType = result_type(model)
	if result == ResultType.BOOLEAN:
		return true
	return result == ResultType.UNKNOWN and ACCEPT_UNKNOWN_IN_BOOLEAN_SLOTS


## 类型名，供拒绝提示与日志使用。
static func describe(result: ResultType) -> String:
	match result:
		ResultType.BOOLEAN:
			return "Boolean"
		ResultType.NUMBER:
			return "Number"
		ResultType.TEXT:
			return "Text"
		_:
			return "Unknown"
