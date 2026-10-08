extends RefCounted
## Deliberately has no AST class references: runtime loading breaks script-resource
## factory return-type dependency cycles while preserving concrete instances.

static func make_literal(p_value: Variant) -> Variant:
	var script: GDScript = load("res://BlockSystem/Core/AST_Expression.gd") as GDScript
	var expression: Variant = script.new()
	expression.value = p_value
	return expression

static func make_binary(p_operator: String, p_left: Variant, p_right: Variant = null) -> Variant:
	var script: GDScript = load("res://BlockSystem/Core/AST_Expression.gd") as GDScript
	var expression: Variant = script.new()
	expression.operator = p_operator
	expression.left = p_left
	expression.right = p_right
	return expression
