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


func _init() -> void:
	type = TYPE_STATEMENT


func to_dictionary() -> Dictionary:
	var body_payload: Array = []
	for child: AST_Node in body:
		if child == null:
			body_payload.append(null)
		else:
			body_payload.append(child.to_dictionary())
	var condition_payload: Variant = null
	if condition != null:
		condition_payload = condition.to_dictionary()
	return {
		"type": type,
		"condition": condition_payload,
		"body": body_payload,
	}


func _to_string() -> String:
	return "<AST_Statement condition=%s body=%d>" % [condition, body.size()]
