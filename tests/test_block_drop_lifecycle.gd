extends Node
const EXPR: PackedScene = preload("res://BlockSystem/Prefabs/ExpressionBlockUI.tscn")
const STMT: PackedScene = preload("res://BlockSystem/Prefabs/IfBlockUI.tscn")
const CMD: PackedScene = preload("res://BlockSystem/Prefabs/CommandBlockUI.tscn")
var nodes: Array[Node] = []

func after_each() -> void:
	for node: Node in nodes:
		if is_instance_valid(node):
			node.free()
	nodes.clear()

func spawn(scene: PackedScene, model: AST_Node) -> Control:
	var ui: Control = scene.instantiate() as Control
	add_child(ui)
	nodes.append(ui)
	ui.call(&"bind_model", model)
	return ui

func mount(ui: Node, parent: Node) -> void:
	ui.get_parent().remove_child(ui)
	parent.add_child(ui)

func test_in_operand_return_and_cancel() -> Variant:
	var model: AST_Expression = AST_Expression.new()
	model.operator = "in"
	model.left = AST_Variable.new()
	model.right = AST_Variable.new()
	var ui: ExpressionUI = spawn(EXPR, model) as ExpressionUI
	for destination: Container in [ui.left_slot, ui.right_slot]:
		var arg: Control = spawn(EXPR, AST_Variable.new())
		mount(arg, destination)
		BlockDragDrop.reserve_drag_origin(arg)
		var hole: SlotUI = destination.get_child(0) as SlotUI
		if hole == null or hole.hint_label.text != "Drop block" or arg.visible:
			return "Missing immediate English placeholder"
		var payload: Dictionary = BlockDragDrop.make_payload(arg.get_model(), arg)
		if not hole._can_drop_data(Vector2.ZERO, payload):
			return "Same drag cannot return"
		hole._drop_data(Vector2.ZERO, payload)
		if destination.get_child_count() != 1 or not arg.visible:
			return "Return duplicated operand or hole"
		BlockDragDrop.reserve_drag_origin(arg)
		BlockDragDrop.end_drag(arg)
		if destination.get_child_count() != 1 or not arg.visible:
			return "Cancellation did not restore exact origin"
	return null

func test_command_forwarding_and_else_refill() -> Variant:
	var ui: StatementUI = spawn(STMT, AST_Statement.new()) as StatementUI
	if ui.else_container.visible or not ui.add_else_button.visible:
		return "Else should initially be optional UI"
	ui.add_else_button.pressed.emit()
	var row: CommandUI = spawn(CMD, AST_Command.new()) as CommandUI
	mount(row, ui.else_container)
	var next: Control = spawn(CMD, AST_Command.new())
	var payload: Dictionary = BlockDragDrop.make_payload(next.get_model(), next)
	if not row._can_drop_data(Vector2.ZERO, payload):
		return "Command row should forward command, not treat it as an argument"
	row._drop_data(Vector2.ZERO, payload)
	if next.get_parent() != ui.else_container:
		return "Command forwarding used wrong branch"
	mount(row, self)
	mount(next, self)
	var branch: BodyDropUI = ui.else_container as BodyDropUI
	if not branch._can_drop_data(Vector2.ZERO, payload):
		return "Empty expanded else cannot refill"
	branch._drop_data(Vector2.ZERO, payload)
	var leaf: Control = spawn(EXPR, AST_Variable.new())
	if branch._can_drop_data(Vector2.ZERO, BlockDragDrop.make_payload(leaf.get_model(), leaf)):
		return "Expression became a statement row"
	var engine: BlockSyncEngine = BlockSyncEngine.new()
	var rebuilt: AST_Statement = engine.build_ast_from_ui(ui) as AST_Statement
	engine.free()
	if rebuilt.else_body.size() != 1 or not rebuilt.body.is_empty():
		return "Else compilation lost actual insertion"
	return null

func test_wrap_highlight_and_single_operand_capacity() -> Variant:
	var outer_model: AST_Expression = AST_Expression.new()
	outer_model.operator = "in"
	var outer: ExpressionUI = spawn(EXPR, outer_model) as ExpressionUI
	var leaf: ExpressionUI = spawn(EXPR, AST_Variable.new()) as ExpressionUI
	mount(leaf, outer.left_slot)
	var wrapper_model: AST_Expression = AST_Expression.new()
	wrapper_model.operator = "+"
	var wrapper: ExpressionUI = spawn(EXPR, wrapper_model) as ExpressionUI
	var payload: Dictionary = BlockDragDrop.make_payload(wrapper_model, wrapper)
	leaf.size = Vector2(100, 40)
	if leaf._can_drop_data(Vector2.ZERO, payload):
		return "Operand edge allowed a second sibling"
	if not leaf._can_drop_data(Vector2(50, 20), payload) or leaf.get_interaction_state() != BlockDragDrop.State.WRAPPED:
		return "Legal combination highlight missing"
	leaf._drop_data(Vector2(50, 20), payload)
	if wrapper.get_parent() != outer.left_slot or leaf.get_parent() != wrapper.left_slot or outer.left_slot.get_child_count() != 1:
		return "Wrap did not replace the original operand"
	return null

func test_multi_argument_hole_preserves_position() -> Variant:
	var model: AST_Command = AST_Command.new()
	model.args = [AST_Variable.new(), AST_Variable.new()]
	var command: CommandUI = spawn(CMD, model) as CommandUI
	var a: Control = spawn(EXPR, model.args[0])
	var b: Control = spawn(EXPR, model.args[1])
	mount(a, command.args_container)
	mount(b, command.args_container)
	BlockDragDrop.reserve_drag_origin(a)
	BlockDragDrop.commit_drag(a)
	mount(a, self)
	var hole: SlotUI = command.args_container.get_child(0) as SlotUI
	if hole == null or command.args_container.get_child(1) != b:
		return "Missing hole for one of several arguments"
	hole._drop_data(Vector2.ZERO, BlockDragDrop.make_payload(a.get_model(), a))
	if command.args_container.get_child_count() != 2 or command.args_container.get_child(0) != a:
		return "Argument order changed on refill"
	return null
