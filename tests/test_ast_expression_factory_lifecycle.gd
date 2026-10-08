extends Node
## Factory API retains concrete types, recursive serialization and unary default.
func test_factory_preserves_expression_contract() -> Variant:
	var expression_script: GDScript = load("res://BlockSystem/Core/AST_Expression.gd") as GDScript
	var left: Variant = expression_script.make_literal(3)
	var right: Variant = expression_script.make_literal(5)
	var binary: Variant = expression_script.make_binary("+", left, right)
	var unary: Variant = expression_script.make_binary("not", left)
	if not is_instance_of(left, expression_script) or not is_instance_of(binary, expression_script) or not is_instance_of(unary, expression_script):
		return "Factory lost concrete AST_Expression instance type"
	if binary.left != left or binary.right != right or unary.right != null:
		return "Factory changed child identity or default argument"
	if not left.is_leaf() or binary.is_leaf():
		return "Factory changed leaf behavior"
	var payload: Dictionary = binary.to_dictionary()
	if payload.get("operator") != "+" or payload["left"]["value"] != 3 or payload["right"]["value"] != 5:
		return "Factory changed serialization"
	return null
