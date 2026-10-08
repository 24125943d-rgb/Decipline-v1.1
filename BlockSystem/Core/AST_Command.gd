class_name AST_Command
extends AST_Node
## 单行指令节点。
##
## 序列化结构：
##     { "type": "command", "opcode": "move_forward", "args": [...] }
##
## 说明：规范要求本节点包含 args；opcode 是为让指令可被识别而补充的字段 ——
## 只有 args 无法区分「前进 3 步」与「后退 3 步」。

const TYPE_COMMAND: String = "command"

## 指令标识（积木 opcode），例如 "move_forward"、"turn_left"。
var opcode: String = ""

## 指令实参，可含任意 JSON 可序列化的值（数字 / 字符串 / 布尔 / 数组 / 字典）。
var args: Array = []


func _init(p_opcode: String = "") -> void:
	type = TYPE_COMMAND
	opcode = p_opcode


func to_dictionary() -> Dictionary:
	var payload: Dictionary = _payload()
	payload["opcode"] = opcode
	var args_payload: Array = []
	for entry: Variant in args:
		if entry is AST_Node:
			args_payload.append((entry as AST_Node).to_dictionary())
		else:
			args_payload.append(entry)
	payload["args"] = args_payload
	return payload


func _to_string() -> String:
	return '<AST_Command opcode="%s" args=%d>' % [opcode, args.size()]
