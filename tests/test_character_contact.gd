extends Node

func test_contact_geometry() -> Variant:
	var helper: Script = load("res://scripts/character_contact.gd")
	for kind: int in 3:
		var a: CharacterBody3D = CharacterBody3D.new()
		var b: CharacterBody3D = CharacterBody3D.new()
		var shape: Shape3D
		if kind == 0:
			shape = SphereShape3D.new()
			shape.radius = 0.5
		elif kind == 1:
			shape = CapsuleShape3D.new()
			shape.radius = 0.5
			shape.height = 2.0
		else:
			shape = BoxShape3D.new()
			shape.size = Vector3.ONE
		for body: CharacterBody3D in [a, b]:
			var collider: CollisionShape3D = CollisionShape3D.new()
			collider.shape = shape.duplicate()
			body.add_child(collider)
			add_child(body)
		b.position.x = 1.0
		var contact: bool = helper.attach(a, b)
		b.position.x = 1.02
		var gap: bool = helper.attach(a, b)
		b.position = Vector3(0, 3, 0)
		var height_gap: bool = helper.attach(a, b)
		var invalid: bool = helper.attach(a, a) or helper.attach(a, null)
		a.scale = Vector3.ONE * 2.0
		b.position = Vector3(1.5, 0, 0)
		var scaled: bool = helper.attach(a, b)
		a.free()
		b.free()
		if not contact or gap or height_gap or invalid or not scaled:
			return "Contact/gap/height/null/scaled shape failed: %s" % kind
	return null

func test_attach_ui_roundtrip() -> Variant:
	var ast: AST_Node = ASTManager.from_dictionary(CombatAIMock.get_character_attach_program_ast())
	var engine: BlockSyncEngine = BlockSyncEngine.new()
	engine.blocks_per_frame = 64
	add_child(engine)
	var ui: Control = await engine.build_ui_from_ast(ast)
	if ui == null:
		engine.free()
		return "Attach UI construction failed."
	add_child(ui)
	var rebuilt: AST_Node = engine.build_ast_from_ui(ui)
	var contract: CharacterProgramContract = CharacterProgramContract.new()
	# Variable nodes normalize to expression leaves when mounted in UI slots.
	var original_source: String = contract.generate_strict(ast)
	var source: String = contract.generate_strict(rebuilt)
	var same: bool = source == original_source
	ui.free()
	engine.free()
	if not same or source.is_empty() or ASTCompiler.compile(source) == null:
		return "Attach AST/UI/compile roundtrip failed: same=%s problems=%s source=%s" % [same, contract.problems, source]
	return null

func test_attach_contract_and_schema() -> Variant:
	var ast: AST_Node = ASTManager.from_dictionary(CombatAIMock.get_character_attach_program_ast())
	var contract: CharacterProgramContract = CharacterProgramContract.new()
	var source: String = contract.generate_strict(ast)
	if source.is_empty() or not source.contains('target.call("attach",') or ASTCompiler.compile(source) == null:
		return "Attach strict program failed to compile: " + str(contract.problems)
	var expression: AST_Expression = (ast as AST_Statement).body[0].condition
	if AST_TypeInference.result_type(expression) != AST_TypeInference.ResultType.BOOLEAN or AST_BlockSchema.child_roles(expression).size() != 2:
		return "Attach must have two nested operands and boolean result."
	expression.left = AST_Expression.make_literal(123)
	if not contract.generate_strict(ast).is_empty():
		return "Attach accepted a numeric operand."
	return null
