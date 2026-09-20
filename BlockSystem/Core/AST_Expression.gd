class_name AST_Expression
extends AST_Node
## 逻辑 / 算术表达式节点，可无限嵌套。
##
## 序列化结构：
##     运算符节点：{ "type": "expression", "operator": ">", "left": {...}, "right": {...}, "value": null }
##     叶子操作数：{ "type": "expression", "operator": "",  "left": null,  "right": null,  "value": 3 }
##
## 说明：规范要求 left / right 均为 AST_Expression，因此叶子操作数用
## 「operator 为空串 + value 承载字面量/变量名」表示，保证递归能够终止。

const TYPE_EXPRESSION: String = "expression"

## 运算符，例如 ">"、"=="、"and"、"+",。空串表示本节点是叶子操作数。
var operator: String = ""

## 左子表达式。仅当本节点为叶子时为 null。
var left: AST_Expression = null

## 右子表达式。一元运算符（如 "not"）与叶子节点时为 null。
var right: AST_Expression = null

## 叶子操作数：字面量（int / float / String / bool）或变量名。operator 非空时忽略。
var value: Variant = null


func _init() -> void:
	type = TYPE_EXPRESSION


## 构造叶子操作数，例如字面量 3 或变量名 "score"。
static func make_literal(p_value: Variant) -> AST_Expression:
	var expression: AST_Expression = AST_Expression.new()
	expression.value = p_value
	return expression


## 构造运算符节点，例如 make_binary(">", make_literal("score"), make_literal(3))。
## p_right 可省略以构造一元表达式，如 make_binary("not", make_literal("done"))。
static func make_binary(p_operator: String, p_left: AST_Expression, p_right: AST_Expression = null) -> AST_Expression:
	var expression: AST_Expression = AST_Expression.new()
	expression.operator = p_operator
	expression.left = p_left
	expression.right = p_right
	return expression


## 是否为叶子操作数（无运算符、无子表达式）。
func is_leaf() -> bool:
	return operator.is_empty() and left == null and right == null


func to_dictionary() -> Dictionary:
	var payload: Dictionary = {
		"type": type,
		"operator": operator,
		"left": null,
		"right": null,
		"value": value,
	}
	if left != null:
		payload["left"] = left.to_dictionary()
	if right != null:
		payload["right"] = right.to_dictionary()
	return payload


func _to_string() -> String:
	if is_leaf():
		return "<AST_Expression leaf=%s>" % str(value)
	return "<AST_Expression %s %s %s>" % [left, operator, right]
