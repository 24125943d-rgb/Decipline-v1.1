class_name BodyDropUI
extends VBoxContainer
## An explicit branch destination, including when the branch has no children.
func statement_owner() -> StatementUI:
	var node: Node = get_parent()
	while node != null:
		if node is StatementUI:
			return node as StatementUI
		node = node.get_parent()
	return null

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	var statement: StatementUI = statement_owner()
	return statement != null and statement.can_drop_in(data, self)

func _drop_data(_position: Vector2, data: Variant) -> void:
	var statement: StatementUI = statement_owner()
	if statement != null:
		statement.drop_in(data, self)
