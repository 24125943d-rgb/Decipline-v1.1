extends Control
## 2D 画布：把当前的 AST 渲染成代码积木，用来肉眼检查程序结构、配色与探针 id 来源。
##
## [br]数据源：[CombatAIMock]（第一个实战业务逻辑：AI 战斗决策 WHILE / IF-ELSE / ATTACK / CHASE）。
## 渲染走 [BlockSyncEngine]（AST → 积木 UI），与执行器、正式画布用的是同一棵树，
## 所以这里看到的形状就是代码真正会被编译成的形状。
##
## [br]用法：直接运行本场景；或在代码里 [code]await build(ast)[/code] 换成任意一棵 AST。
## 带 IF-ELSE 的树能显示出来，靠的是 [code]IfBlockUI.tscn[/code] 补上的 else_container 插槽。

## 积木树的挂载点（ScrollContainer 里的 VBoxContainer）。
@export var content_path: NodePath = ^"Layout/Column/Scroll/Content"
## 状态行。
@export var status_label_path: NodePath = ^"Layout/Column/Status"
## 每帧最多构建几块积木（越大越快，越小越能看到逐块生长）。
@export var blocks_per_frame: int = 8
## 进场景就自动构建 CombatAIMock 那棵树。
@export var build_on_ready: bool = true

var _engine: BlockSyncEngine = null
var _block_ui: Control = null
var _status: Label = null


func _ready() -> void:
	_status = get_node_or_null(status_label_path) as Label
	if build_on_ready:
		await build_from_combat_ai()


## 把一棵 AST 渲染成积木，返回根控件（失败返回 null）。
func build(ast: AST_Node) -> Control:
	clear()
	if ast == null:
		_set_status("AST is empty - nothing to show.")
		return null
	_engine = BlockSyncEngine.new()
	_engine.blocks_per_frame = maxi(blocks_per_frame, 1)
	add_child(_engine)
	_block_ui = await _engine.build_ui_from_ast(ast)
	if _block_ui == null:
		_set_status("Build failed - see the Output panel for details.")
		return null
	var content: Node = get_node_or_null(content_path)
	if content == null:
		_set_status("Missing mount point: %s" % content_path)
		return null
	content.add_child(_block_ui)
	var counts: Dictionary = count_blocks(_block_ui)
	_set_status(
		"%d blocks  -  statement %d / command %d / expression %d  -  trace ids: uuid first, else structural path"
		% [counts["total"], counts["statement"], counts["command"], counts["expression"]]
	)
	return _block_ui


## 渲染 CombatAIMock 的 AI 战斗决策树（本场景的默认内容）。
func build_from_combat_ai() -> Control:
	return await build(ASTManager.from_dictionary(CombatAIMock.get_combat_ai_ast()))


## 从当前积木 UI 重建 AST；未构建或已清空时静默返回 null。
func get_program_ast() -> AST_Node:
	if not is_instance_valid(_engine) or not is_instance_valid(_block_ui):
		return null
	return _engine.build_ast_from_ui(_block_ui)


## 清掉当前展示。
func clear() -> void:
	if is_instance_valid(_block_ui):
		_block_ui.queue_free()
	_block_ui = null
	if is_instance_valid(_engine):
		_engine.queue_free()
	_engine = null


## 数一数渲染出来的积木（按种类）。占位插槽与装饰节点不算积木。
func count_blocks(root: Node) -> Dictionary:
	var counts: Dictionary = {"total": 0, "statement": 0, "command": 0, "expression": 0}
	_count_into(root, counts)
	return counts


func _count_into(node: Node, counts: Dictionary) -> void:
	if node == null:
		return
	var block: Control = BlockSyncEngine.as_block(node)
	if block != null:
		counts["total"] += 1
		if block is StatementUI:
			counts["statement"] += 1
		elif block is CommandUI:
			counts["command"] += 1
		else:
			counts["expression"] += 1
	for child: Node in node.get_children():
		_count_into(child, counts)


func _set_status(message: String) -> void:
	if _status != null:
		_status.text = message
	print(message)
