extends RefCounted
## Exact script ancestry checks without retaining UI script dependencies.
const SLOT: String = "res://BlockSystem/Logic/SlotUI.gd"
const STATEMENT: String = "res://BlockSystem/Logic/StatementUI.gd"
const EXPRESSION: String = "res://BlockSystem/Logic/ExpressionUI.gd"
const COMMAND: String = "res://BlockSystem/Logic/CommandUI.gd"

static func matches(node: Node, path: String) -> bool:
	if node == null:
		return false
	var script: Script = node.get_script() as Script
	while script != null:
		if script.resource_path == path:
			return true
		script = script.get_base_script()
	return false
