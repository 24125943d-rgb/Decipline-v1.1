extends Node
## 拖放的**语法规则**测试（不是外观）：
##   1. 表达式/参数积木不能单独占语句体的一行（它不是「一行」）
##   2. 表达式积木本体不接受落点（操作数是它自己的插槽）
##   3. 插槽只放一个积木：满槽拒绝、空槽接受（这条同时锁住 IN 两侧「一边两个、一边空」）
##   4. else 槽空着也要在，否则摘空之后再也没地方拖回去
##   5. 指令的参数被摘走后要补回一个空插槽，否则这格永久失去落点

const STATEMENT_SCENE: PackedScene = preload("res://BlockSystem/Prefabs/IfBlockUI.tscn")
const COMMAND_SCENE: PackedScene = preload("res://BlockSystem/Prefabs/CommandBlockUI.tscn")
const EXPRESSION_SCENE: PackedScene = preload("res://BlockSystem/Prefabs/ExpressionBlockUI.tscn")

var _spawned: Array[Node] = []


func before_each() -> void:
	_spawned.clear()


func after_each() -> void:
	for node: Node in _spawned:
		if is_instance_valid(node):
			node.free()
	_spawned.clear()


func _spawn(scene: PackedScene, model: AST_Node) -> Control:
	var ui: Control = scene.instantiate() as Control
	add_child(ui)
	_spawned.append(ui)
	ui.call(&"bind_model", model)
	return ui


func _spawn_command() -> Control:
	return _spawn(COMMAND_SCENE, AST_Command.new())


## 控件已经有父节点时直接 add_child 会被引擎拒绝，所以先摘下来再挂。
func _detach(node: Node) -> void:
	var parent: Node = node.get_parent()
	if parent != null:
		parent.remove_child(node)


func _spawn_expression() -> Control:
	return _spawn(EXPRESSION_SCENE, AST_Variable.new())


func _if_statement() -> AST_Statement:
	var statement: AST_Statement = AST_Statement.new()
	statement.condition = AST_Variable.new()
	return statement


# ---------------------------------------------------------------- 1 / 2：落在「本体」上的语法
func test_expression_cannot_take_a_row_of_a_body() -> Variant:
	var statement_ui: Control = _spawn(STATEMENT_SCENE, _if_statement())
	var expression_ui: Control = _spawn_expression()
	if BlockDragDrop.can_drop_into(expression_ui, statement_ui):
		return "表达式积木不该能当成语句体的一行"
	var command_ui: Control = _spawn_command()
	if not BlockDragDrop.can_drop_into(command_ui, statement_ui):
		return "指令积木应该能放进语句体"
	return null


func test_expression_body_itself_is_not_a_drop_target() -> Variant:
	var expression_ui: Control = _spawn_expression()
	var command_ui: Control = _spawn_command()
	if BlockDragDrop.can_drop_into(command_ui, expression_ui):
		return "表达式积木本体不该接受落点：操作数要落进它的插槽（否则会拼出 [[x] y] 这种嵌套）"
	return null


# ---------------------------------------------------------------- 3：插槽容量 = 1
func test_a_full_slot_refuses_a_second_block() -> Variant:
	var slot: SlotUI = SlotUI.create(AST_BlockSchema.ROLE_LEFT)
	add_child(slot)
	_spawned.append(slot)
	var held: Control = _spawn_command()
	_detach(held)
	slot.add_child(held)
	if slot.is_empty():
		return "插入积木后插槽不该还是空的（is_empty 判断有问题）"
	var newcomer: Control = _spawn_command()
	var payload: Dictionary = BlockDragDrop.make_payload(AST_Variable.new(), newcomer)
	if slot._can_drop_data(Vector2.ZERO, payload):
		return "已经装着积木的插槽不该再收第二个（IN 一边放两个就是这么来的）"
	return null


func test_an_empty_slot_accepts_one_block() -> Variant:
	var slot: SlotUI = SlotUI.create(AST_BlockSchema.ROLE_LEFT)
	add_child(slot)
	_spawned.append(slot)
	var newcomer: Control = _spawn_command()
	var payload: Dictionary = BlockDragDrop.make_payload(AST_Variable.new(), newcomer)
	if not slot._can_drop_data(Vector2.ZERO, payload):
		return "空插槽应该收下这个表达式（否则 IN 缺的一侧永远补不上）"
	return null


# ---------------------------------------------------------------- 4：else 槽常驻
func test_else_slot_stays_when_empty() -> Variant:
	var statement_ui: Node = _spawn(STATEMENT_SCENE, _if_statement())
	var else_container: Node = statement_ui.get(&"else_container")
	if else_container == null:
		return "预制体上没有 else_container"
	if (else_container as CanvasItem).visible:
		return "Empty else must start collapsed"
	(statement_ui as StatementUI).expand_else()
	if not (else_container as CanvasItem).visible:
		return "Expanded else must stay visible"
	var else_label: Node = statement_ui.get(&"else_label")
	if else_label != null and not (else_label as CanvasItem).visible:
		return "else 关键字标签应随槽一起显示"
	return null


# ---------------------------------------------------------------- 5：参数位修补
func test_removed_command_argument_leaves_a_slot_behind() -> Variant:
	var command_ui: Node = _spawn_command()
	var container: Node = command_ui.get(&"args_container")
	if container == null:
		return "预制体上没有 args_container"
	var argument: Control = _spawn_command()
	_detach(argument)
	container.add_child(argument)
	_detach(argument)
	BlockDragDrop.repair_after_removal(container)
	var found: bool = false
	for child: Node in container.get_children():
		if child is SlotUI:
			found = true
	if not found:
		return "参数被摘走后应留下一个空插槽，否则 attack / chase 这格永久失去落点"
	return null
