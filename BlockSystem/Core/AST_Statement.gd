class_name AST_Statement
extends AST_Node
## 控制流节点：condition 成立时，顺序执行 body 中的子节点。
##
## 序列化结构：
##     { "type": "statement", "condition": <expression|null>, "body": [<node>, ...] }

const TYPE_STATEMENT: String = "statement"

## 判定条件。为 null 表示无条件（例如循环体、else 分支）。
var condition: AST_Expression = null

## 语句体：按顺序执行的子节点，可自由嵌套 AST_Statement。
var body: Array[AST_Node] = []

## ELSE 分支：condition 不成立时执行的子节点。空数组表示没有 else。
var else_body: Array[AST_Node] = []

## 循环标记：true + condition 非空 = while（每轮重新求值）；true + 空 = 无条件循环。
var loop: bool = false


func _init() -> void:
	type = TYPE_STATEMENT


func to_dictionary() -> Dictionary:
	var payload: Dictionary = _payload()
	var condition_payload: Variant = null
	if condition != null:
		condition_payload = condition.to_dictionary()
	payload["condition"] = condition_payload
	payload["body"] = _children_payload(body)
	if not else_body.is_empty():
		payload["else_body"] = _children_payload(else_body)
	if loop:
		payload["loop"] = true
	return payload


static func _children_payload(children: Array[AST_Node]) -> Array:
	var result: Array = []
	for child: AST_Node in children:
		if child == null:
			result.append(null)
		else:
			result.append(child.to_dictionary())
	return result


func _to_string() -> String:
	return "<AST_Statement condition=%s body=%d>" % [condition, body.size()]
