class_name BlockSyncEngine
extends Node
const UIType: GDScript = preload("res://BlockSystem/Logic/BlockUIType.gd")
## AST ⇄ UI 双向同步引擎（视图层）。
##
## 关于「为什么不在 Core/」：
## 这两个函数天生要碰引擎的场景层 —— instantiate() 场景、add_child()、
## await get_tree().process_frame。而 Core 按架构规范必须保持纯 RefCounted、
## 零场景依赖（README §2）：RefCounted 上连 get_tree() 都不存在。
## 所以这里只做视图侧的事，全部**纯 AST 知识**（种类、子节点角色、调色板类别）
## 放在 Core/AST_BlockSchema.gd，两边可以各自单测。
##
## 积木 UI 协议 —— 新增一种积木只要满足它，不需要改本引擎：
##     set_palette(palette: BlockPalette) -> void
##     bind_model(model: AST_Node) -> void
##     get_model() -> AST_Node
##
## 用法：
##     var engine := BlockSyncEngine.new()
##     add_child(engine)                              # 必须在场景树里
##     var block_ui := await engine.build_ui_from_ast(ast)   # 注意 await
##     workspace.add_child(block_ui)
## 也可以注册成 Autoload（它是 Node，符合 Godot 对 Autoload 的要求）。

## 种类 -> 模板场景。视图侧知识，Core 不参与。
const TEMPLATES: Dictionary = {
	AST_BlockSchema.KIND_STATEMENT: "res://BlockSystem/Prefabs/IfBlockUI.tscn",
	AST_BlockSchema.KIND_COMMAND: "res://BlockSystem/Prefabs/CommandBlockUI.tscn",
	AST_BlockSchema.KIND_EXPRESSION: "res://BlockSystem/Prefabs/ExpressionBlockUI.tscn",
}

## 角色 -> UI 脚本上 @export 的插槽属性名。同为视图侧知识。
const ROLE_SLOTS: Dictionary = {
	AST_BlockSchema.ROLE_CONDITION: &"condition_slot",
	AST_BlockSchema.ROLE_BODY: &"body_container",
	AST_BlockSchema.ROLE_ELSE: &"else_container",
	AST_BlockSchema.ROLE_ARG: &"args_container",
	AST_BlockSchema.ROLE_LEFT: &"left_slot",
	AST_BlockSchema.ROLE_RIGHT: &"right_slot",
}

const DEFAULT_PALETTE: String = "res://BlockSystem/Art/Palettes/palette_default.tres"

## UI -> AST 全量重建完成。接住它可以拿到「编辑器里当前真实的程序」。
signal ast_rebuilt(ast_root: AST_Node)

## 注入给所有积木的调色板；留空则用 DEFAULT_PALETTE。
@export var palette: BlockPalette

## 每帧最多构建几块积木。1 = 每块都等一帧（最平滑，但大程序慢），调大可加快加载。
@export var blocks_per_frame: int = 1

## 拖拽重排结束后是否自动全量重建 AST。
@export var rebuild_on_reorder: bool = true

## 构建代际号：一次构建被更晚的构建取代时，前者自行放弃半成品。
var _generation: int = 0
var _built_since_yield: int = 0
var _last_root: Control = null


func _ready() -> void:
	if palette == null:
		palette = load(DEFAULT_PALETTE) as BlockPalette


# ------------------------------------------------------------------ AST -> UI

## 由 AST 递归构建 UI 树，返回根控件；调用方负责把它挂到自己的位置上。
##
## **必须 await 调用**，否则拿到的是协程而不是控件。
##
## 分帧加载：每构建 blocks_per_frame 块积木就 await 一次 process_frame
## （默认 1，即每块都等一帧），避免一次性实例化整棵积木树造成掉帧。
##
## 返回 null 表示：入参为 null / 引擎不在场景树里 / 模板缺失 / 本次构建已被更晚的构建取消。
func build_ui_from_ast(ast_node: AST_Node) -> Control:
	if ast_node == null:
		push_error("BlockSyncEngine.build_ui_from_ast: 传入 null。")
		return null
	if not is_inside_tree():
		push_error("BlockSyncEngine.build_ui_from_ast: 引擎不在场景树里，无法 await process_frame。")
		return null
	_generation += 1
	_built_since_yield = 0
	var root: Control = await _build_node(ast_node, _generation)
	_last_root = root
	return root


func _build_node(model: AST_Node, generation: int) -> Control:
	var kind: StringName = AST_BlockSchema.kind_of(model)
	var template_path: String = TEMPLATES.get(kind, "")
	if template_path.is_empty():
		push_error("BlockSyncEngine: 没有为种类 '%s' 注册模板。" % kind)
		return null
	var scene: PackedScene = load(template_path) as PackedScene
	if scene == null:
		push_error("BlockSyncEngine: 模板加载失败 %s" % template_path)
		return null

	var ui: Control = scene.instantiate() as Control
	if ui == null:
		push_error("BlockSyncEngine: 模板 %s 的根节点不是 Control。" % template_path)
		return null
	_inject_palette(ui)
	_bind_model(ui, model)

	await _yield_frame()
	if generation != _generation:
		ui.free()  # 已被更新的构建取代，丢掉半成品
		return null

	for entry: Dictionary in AST_BlockSchema.child_roles(model):
		var child_model: AST_Node = entry["model"]
		var child_ui: Control = await _build_node(child_model, generation)
		if generation != _generation:
			if child_ui != null:
				child_ui.free()
			ui.free()
			return null
		if child_ui == null:
			continue
		var slot: Node = _slot_for(ui, entry["role"])
		if slot == null:
			child_ui.free()
			continue
		slot.add_child(child_ui)

	_wire_reorder(ui)
	return ui


## 分帧：累积到 blocks_per_frame 块就等一帧。
func _yield_frame() -> void:
	_built_since_yield += 1
	if _built_since_yield < maxi(blocks_per_frame, 1):
		return
	_built_since_yield = 0
	await get_tree().process_frame


func _inject_palette(ui: Control) -> void:
	if palette == null or not ui.has_method(&"set_palette"):
		return
	ui.call(&"set_palette", palette)


func _bind_model(ui: Control, model: AST_Node) -> void:
	if not ui.has_method(&"bind_model"):
		push_error("BlockSyncEngine: %s 没有实现 bind_model()，不符合积木 UI 协议。" % ui.get_scene_file_path())
		return
	ui.call(&"bind_model", model)


func _slot_for(ui: Control, role: StringName) -> Node:
	var property: StringName = ROLE_SLOTS.get(role, &"")
	if property.is_empty():
		push_error("BlockSyncEngine: 角色 '%s' 没有注册插槽属性。" % role)
		return null
	var slot: Node = ui.get(property) as Node
	if slot == null:
		push_error("BlockSyncEngine: %s 上取不到插槽 '%s'。" % [ui.name, property])
	return slot


## 把积木的拖拽重排信号接到本引擎，一次有效拖拽结束后全量重建 AST。
func _wire_reorder(ui: Control) -> void:
	if not rebuild_on_reorder or not ui.has_signal(&"reorder_requested"):
		return
	var handler: Callable = _on_reorder_requested.bind(ui)
	if not ui.is_connected(&"reorder_requested", handler):
		ui.connect(&"reorder_requested", handler)


func _on_reorder_requested(_action: int, _index: int, _payload: Dictionary, _source: Node) -> void:
	if _last_root == null:
		return
	var rebuilt: AST_Node = build_ast_from_ui(_last_root)
	if rebuilt != null:
		ast_rebuilt.emit(rebuilt)


# ------------------------------------------------------------------ UI -> AST

## 由 UI 树全量重建 AST（每次都是全新对象，不复用旧节点）。
##
## 结构（嵌套与顺序）完全由 UI 的层级与挂载关系决定；
## 原子数据（opcode / args / 字面量 / 运算符）取自各积木当前绑定的模型 ——
## 目前没有文本编辑 UI，这些值在界面上改不了，只能沿用。
func build_ast_from_ui(ui_root: Node) -> AST_Node:
	if ui_root == null:
		push_error("BlockSyncEngine.build_ast_from_ui: 传入 null。")
		return null
	var block: Control = as_block(ui_root)
	if block == null:
		push_error("BlockSyncEngine.build_ast_from_ui: %s 不是积木控件。" % ui_root.name)
		return null
	return _compile_node(block)


## 上一次构建出来的根控件（测试与外部取用）。
func get_last_root() -> Control:
	return _last_root


func _compile_node(block: Control) -> AST_Node:
	if UIType.matches(block, UIType.STATEMENT):
		return _compile_statement(block)
	if UIType.matches(block, UIType.EXPRESSION):
		return _compile_expression(block)
	if UIType.matches(block, UIType.COMMAND):
		return _compile_command(block)
	push_error("BlockSyncEngine: 无法编译未知积木 %s。" % block.get_scene_file_path())
	return null


func _compile_statement(ui: Control) -> AST_Statement:
	var statement: AST_Statement = AST_Statement.new()
	# body 的顺序由容器里的实际排列决定 —— 拖拽改的正是它
	if (ui.get(&"body_container") as Node) != null:
		for child: Node in (ui.get(&"body_container") as Node).get_children():
			var child_block: Control = as_block(child)
			if child_block == null:
				continue
			var compiled: AST_Node = _compile_node(child_block)
			if compiled != null:
				statement.body.append(compiled)
	var original: AST_Statement = ui.call(&"get_model")
	if original != null:
		statement.loop = original.loop
	if (ui.get(&"else_container") as Node) != null:
		for child: Node in (ui.get(&"else_container") as Node).get_children():
			var block: Control = as_block(child)
			if block != null:
				statement.else_body.append(_compile_node(block))
	var condition_block: Control = _first_block_in((ui.get(&"condition_slot") as Node))
	if condition_block != null:
		statement.condition = _compile_node(condition_block) as AST_Expression
	return statement


func _compile_expression(ui: Control) -> AST_Expression:
	var expression: AST_Expression = AST_Expression.new()
	# 原子数据沿用原模型（运算符 / 字面量在界面上不可编辑）
	var model: AST_Expression = ui.call(&"get_model")
	if model != null:
		expression.operator = model.operator
		expression.value = model.value
	# 结构取 UI 的挂载关系
	var left_block: Control = _first_block_in((ui.get(&"left_slot") as Node))
	if left_block != null:
		expression.left = _compile_node(left_block) as AST_Expression
	var right_block: Control = _first_block_in((ui.get(&"right_slot") as Node))
	if right_block != null:
		expression.right = _compile_node(right_block) as AST_Expression
	return expression


func _compile_command(ui: Control) -> AST_Command:
	var command: AST_Command = AST_Command.new()
	var model: AST_Command = ui.call(&"get_model")
	if model != null:
		command.opcode = model.opcode
		var entries: Array[Node] = []
		if (ui.get(&"args_container") as Node) != null:
			for child: Node in (ui.get(&"args_container") as Node).get_children():
				if as_block(child) != null or UIType.matches(child, UIType.SLOT):
					entries.append(child)
		var cursor: int = 0
		for arg: Variant in model.args:
			if arg is AST_Node:
				var compiled: AST_Node = null
				if cursor < entries.size() and as_block(entries[cursor]) != null:
					compiled = _compile_node(entries[cursor] as Control)
				command.args.append(compiled)
				cursor += 1
			else:
				command.args.append(arg)
	return command


## 只把三类积木控件当成积木；标签、容器、装饰节点一概忽略。
static func as_block(node: Node) -> Control:
	if UIType.matches(node, UIType.STATEMENT) or UIType.matches(node, UIType.EXPRESSION) or UIType.matches(node, UIType.COMMAND):
		return node as Control
	return null


## 挂载点里的第一个积木子节点（槽位里可能还混着装饰节点）。
static func _first_block_in(slot: Node) -> Control:
	if slot == null:
		return null
	for child: Node in slot.get_children():
		var block: Control = as_block(child)
		if block != null:
			return block
	return null
