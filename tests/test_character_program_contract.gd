extends Node

func test_contract_unknown_args_types_and_null() -> Variant:
	var contract: RefCounted = load("res://scripts/character_program_contract.gd").new()
	var unknown: AST_Command = AST_Command.new("free")
	unknown.uuid = "bad-command"
	if not contract.generate_strict(unknown).is_empty() or not str(contract.problems).contains("bad-command"):
		return "Unknown command must fail with block ID."
	var command: AST_Command = AST_Command.new("Attack")
	if not contract.generate_strict(command).is_empty():
		return "Wrong arity accepted."
	command.args = [true]
	if not contract.generate_strict(command).is_empty():
		return "Wrong type accepted."
	command.args = [null]
	var source: String = contract.generate_strict(command)
	if source.is_empty() or ASTCompiler.compile(source) == null:
		return "Nullable target rejected."
	command.args = [AST_Expression.make_literal("Enemy.visible.closest")]
	source = contract.generate_strict(command)
	if source.is_empty() or not source.contains('target.get("program_visible_closest")') or command.opcode != "Attack":
		return "Strict mapping or immutable clone failed."
	if ASTCompiler.compile(source) == null:
		return "Mapped code failed to compile."
	if not contract.generate_strict(AST_Expression.make_literal("closest_enemy")).is_empty():
		return "Legacy read escaped whitelist."
	var statement: AST_Statement = AST_Statement.new()
	statement.condition = AST_Expression.make_literal("Enemy.visible")
	if not contract.generate_strict(statement).is_empty():
		return "Collection accepted as bool."
	return null

func test_missing_vision_fails_closed_even_legacy_bypass() -> Variant:
	var host: CharacterCombatHost = CharacterCombatHost.new()
	host.require_vision = false
	var errors: PackedStringArray = host.validate_program_bindings(["Character", "Vision"])
	var closed: bool = host.program_visible_closest == null and not host.program_visible_exists
	host.free()
	if errors.size() != 2 or not closed:
		return "Missing bindings did not fail closed."
	return null
