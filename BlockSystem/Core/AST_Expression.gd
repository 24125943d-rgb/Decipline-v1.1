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


## Variant factory signatures avoid self-referencing static-method script cycles.
## The independent helper loads at runtime; results remain AST_Expression instances,
## and typed left/right still enforce the expression-child contract.
static func make_literal(p_value: Variant) -> Variant:
	return preload("res://BlockSystem/Core/ASTExpressionFactory.gd").make_literal(p_value)


static func make_binary(p_operator: String, p_left: Variant, p_right: Variant = null) -> Variant:
	return preload("res://BlockSystem/Core/ASTExpressionFactory.gd").make_binary(p_operator, p_left, p_right)


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

