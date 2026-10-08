class_name CharacterProgramContract
extends RefCounted
## Character tool contract v1. Keys are stable public IDs (case sensitive).
## Reads are synchronous, zero-argument, evaluated independently at every occurrence.
## Character? accepts null. Range.contains(Character?) -> bool is pure geometry.
## Enemy.visible is a Character[] snapshot, NOT a boolean; use .exists for conditions.
## Commands evaluate their argument once; Chase follows that object's live position.
## No Core dependency on gameplay: this outer-layer validator clones before mapping.
const TOOLS: Dictionary = {
	"Self": {"kind":"read", "result":"Character?", "map":"character", "needs":["Character"], "async":false, "args":[]},
	"Enemy.visible.closest": {"kind":"read", "result":"Character?", "map":"program_visible_closest", "needs":["Character", "Vision"], "async":false, "args":[]},
	"Enemy.visible": {"kind":"read", "result":"Character[]", "map":"program_visible", "needs":["Character", "Vision"], "async":false, "args":[]},
	"Enemy.visible.exists": {"kind":"read", "result":"bool", "map":"program_visible_exists", "needs":["Character", "Vision"], "async":false, "args":[]},
	"Attack-range": {"kind":"read", "result":"Range", "map":"attack_range", "needs":["Character", "Attack"], "async":false, "args":[]},
	"Attack": {"kind":"command", "result":"bool", "map":"program_attack", "needs":["Character", "Attack", "Vision"], "async":false, "args":["Character?"]},
	"Chase": {"kind":"command", "result":"ChaseResult", "map":"program_chase", "needs":["Character", "Attack", "Movement", "Vision"], "async":true, "args":["Character?"]}
}
var problems: PackedStringArray = []
var required_capabilities: PackedStringArray = []
var _active: Array[AST_Node] = []

## Empty source means rejected. host optional for offline validation; binding must
## be validated again before execution. This method never starts a runner.
func generate_strict(root: AST_Node, host: Node = null) -> String:
	problems.clear()
	required_capabilities.clear()
	_active.clear()
	var mapped: AST_Node = _clone(root, "root")
	if host != null:
		if not host.has_method("validate_program_bindings"):
			problems.append("root: Host does not implement character program bindings.")
		else:
			var binding_errors: PackedStringArray = host.call("validate_program_bindings", required_capabilities)
			problems.append_array(binding_errors)
	if not problems.is_empty():
		return ""
	var compiler: ASTCompiler = ASTCompiler.new()
	var source: String = compiler.generate_gdscript(mapped)
	if not compiler.problems.is_empty():
		problems.append("root: Compiler rejected the validated program.")
		return ""
	# Strict runners guard every execution boundary, including resumption after Chase.
	var safe_lines: PackedStringArray = []
	for line: String in source.split("\n"):
		var trimmed: String = line.strip_edges()
		var indent: String = ""
		for character: String in line:
			if character != "\t":
				break
			indent += "\t"
		if trimmed.begins_with("trace_block.emit") or trimmed == "await target.get_tree().process_frame":
			safe_lines.append(indent + "if stop_requested or not is_instance_valid(target) or not target.is_inside_tree(): return")
		safe_lines.append(line)
		if trimmed.begins_with("await "):
			safe_lines.append(indent + "if stop_requested or not is_instance_valid(target) or not target.is_inside_tree(): return")
	return "\n".join(safe_lines)

func _error(node: AST_Node, path: String, text: String) -> void:
	problems.append("%s: %s" % [node.uuid if node != null and not node.uuid.is_empty() else path, text])

func _tool(id: String, kind: String, node: AST_Node, path: String) -> Dictionary:
	var definition: Dictionary = TOOLS.get(id, {})
	if definition.is_empty() or definition.get("kind") != kind:
		_error(node, path, "Unknown %s tool '%s'." % [kind, id])
		return {}
	for capability: String in definition.needs:
		if not required_capabilities.has(capability):
			required_capabilities.append(capability)
	return definition

func _clone(node: AST_Node, path: String) -> AST_Node:
	if node == null or _active.has(node):
		_error(node, path, "Missing or cyclic AST node.")
		return null
	_active.append(node)
	var result: AST_Node = null
	if node is AST_Expression:
		var expression: AST_Expression = node as AST_Expression
		var copy: AST_Expression = AST_Expression.new()
		copy.operator = expression.operator
		copy.value = expression.value
		if expression.is_leaf():
			if expression.value is String or expression.value is StringName:
				var definition: Dictionary = _tool(str(expression.value), "read", node, path)
				copy.value = definition.get("map", "")
		else:
			copy.left = _clone(expression.left, path + ".left") as AST_Expression
			if expression.operator != "not":
				copy.right = _clone(expression.right, path + ".right") as AST_Expression
			elif expression.right != null:
				_error(node, path, "not expects one operand.")
		_type(expression, path)
		result = copy
	elif node is AST_Command:
		var command: AST_Command = node as AST_Command
		var definition: Dictionary = _tool(command.opcode, "command", node, path)
		var copy: AST_Command = AST_Command.new(str(definition.get("map", "")))
		if command.args.size() != 1:
			_error(node, path, "Command expects exactly one Character? argument.")
		for index: int in command.args.size():
			var arg: Variant = command.args[index]
			var arg_path: String = path + ".args." + str(index)
			var arg_type: String = _type(arg, arg_path)
			if arg_type not in ["Character?", "null"]:
				_error(arg as AST_Node if arg is AST_Node else null, arg_path, "Expected Character?, got " + arg_type)
			copy.args.append(_clone(arg, arg_path) if arg is AST_Node else arg)
		result = copy
	elif node is AST_Statement:
		var statement: AST_Statement = node as AST_Statement
		var copy: AST_Statement = AST_Statement.new()
		copy.loop = statement.loop
		if statement.condition != null:
			if _type(statement.condition, path + ".condition") != "bool":
				_error(statement.condition, path + ".condition", "Condition requires bool; use Enemy.visible.exists.")
			copy.condition = _clone(statement.condition, path + ".condition") as AST_Expression
		for index: int in statement.body.size():
			copy.body.append(_clone(statement.body[index], path + ".body." + str(index)))
		for index: int in statement.else_body.size():
			copy.else_body.append(_clone(statement.else_body[index], path + ".else_body." + str(index)))
		result = copy
	else:
		_error(node, path, "Unsupported AST node.")
	if result != null:
		result.uuid = node.uuid
	_active.erase(node)
	return result

func _type(value: Variant, path: String, depth: int = 0) -> String:
	if depth > 128:
		_error(null, path, "Expression nesting limit exceeded.")
		return "invalid"
	if value is AST_Expression:
		var expression: AST_Expression = value as AST_Expression
		if expression.is_leaf():
			if expression.value is String or expression.value is StringName:
				var definition: Dictionary = TOOLS.get(str(expression.value), {})
				return str(definition.get("result", "unknown"))
			return _type(expression.value, path, depth + 1)
		var left: String = _type(expression.left, path + ".left", depth + 1)
		var right: String = _type(expression.right, path + ".right", depth + 1)
		var valid: bool = false
		var result: String = "bool"
		match expression.operator:
			"attach": valid = left in ["Character?", "null"] and right in ["Character?", "null"]
			"in": valid = left in ["Character?", "null"] and right == "Range"
			"not": valid = left == "bool"
			"and", "or": valid = left == "bool" and right == "bool"
			"==", "!=": valid = left == right or (left in ["Character?", "null"] and right in ["Character?", "null"])
			">", "<", ">=", "<=": valid = left == "number" and right == "number"
			"+", "-", "*", "/":
				valid = left == "number" and right == "number"
				result = "number"
		if not valid:
			_error(expression, path, "Invalid operator or operand types: %s %s %s." % [left, expression.operator, right])
		return result if valid else "invalid"
	match typeof(value):
		TYPE_NIL: return "null"
		TYPE_BOOL: return "bool"
		TYPE_INT, TYPE_FLOAT: return "number"
	return "invalid"
