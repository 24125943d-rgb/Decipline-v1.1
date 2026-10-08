class_name StatementUI
extends VBoxContainer
## 控制流积木（如 IfBlockUI）的挂载脚本（组件基座）。
##
## 与 ExpressionUI 同一原则：**不生成任何节点**。
## 本脚本要求 Prefab 是一个挂好脚本的 VBoxContainer，
## 并在 Inspector 里把下面两个插槽指向场景内的节点，美术即可自由调整其余结构。
##
## 必需插槽：
##   condition_slot —— 条件区挂载点（PanelContainer，用于放一个表达式积木）
##   body_container —— 语句体挂载点（VBoxContainer，按顺序放子积木）
##
## 硬约束：本文件不得出现任何颜色或尺寸字面量，外观全部来自 Art/。

## 条件区挂载点。
@export var condition_slot: PanelContainer

## 语句体挂载点。
@export var body_container: VBoxContainer

## ELSE 分支挂载点（可选：预制体里加一个 ElseContainer 即可支持 IF-ELSE）。
@export var else_container: VBoxContainer

## C / E / 梳型外框（StatementFrame）。形状由语句体容器的实际布局决定，
## 颜色由调色板注入：本文件不写颜色，也不写形状。
@export var frame: StatementFrame

@export var header_label: Label

## ELSE 关键字标签（与 Header 同层显示）。
@export var else_label: Label
@export var add_else_button: Button

## UI-only expansion state; never serialized into AST.
var else_expanded: bool = false

## 可选：调色板。挂上后本组件会用它校验子组件的注入是否到位。
@export var palette: BlockPalette

## 作为落点（有积木正要被吸附进来）时切换到的 theme type variation。
## 名字是美术资源，可改成任何你想要的反馈方式（例如加大 separation 把缝隙撑开）。
@export var hovered_variation: StringName = &"StatementBlock_Hovered"

## 视图重排完成后发出的「模型变更意图」。
## 视图改动由本脚本完成，AST 改动交给工厂（阶段四）接手：
##     block.reorder_requested.connect(_on_reorder.bind(block))
## action 取值见 BlockDragDrop.Action，index 为 body_container 中的目标下标。
signal reorder_requested(action: int, index: int, payload: Dictionary)

## 只读数据源：UI 只负责渲染，业务状态始终由 Core 层持有。
var _model: AST_Statement = null

## 常态变体：_ready 时从场景记录，作为状态回退目标。
var _base_variation: StringName = &""

## 当前交互状态。
var _state: BlockDragDrop.State = BlockDragDrop.State.NORMAL

## 本次拖拽是否由本节点发起（用于拖拽被取消时恢复隐藏的源节点）。
var _drag_source_active: bool = false


func _ready() -> void:
	if frame == null:
		frame = get_node_or_null(^"CFrame") as StatementFrame
	_base_variation = get_theme_type_variation()
	_validate_mount_points()


## 注入数据并刷新视图。脚本不创建子积木，只负责让插槽与数据状态一致。
func bind_statement(statement: AST_Statement) -> void:
	_model = statement
	if condition_slot != null:
		condition_slot.visible = statement != null and statement.condition != null
	if body_container != null:
		body_container.visible = statement != null
	if statement != null and not statement.else_body.is_empty():
		else_expanded = true
	_refresh_else()
	if header_label != null:
		header_label.text = statement_keyword(statement)
	if frame != null:
		frame.set_mouth_nodes(frame_mouth_nodes())
		_apply_frame_colors()


func expand_else() -> void:
	else_expanded = true
	_refresh_else()


func _refresh_else() -> void:
	var is_if: bool = statement_keyword(_model) == "if"
	if else_container != null:
		else_container.visible = is_if and else_expanded
		(else_container.get_parent() as Control).visible = is_if and else_expanded
	if else_label != null:
		else_label.visible = is_if and else_expanded
	if add_else_button != null:
		add_else_button.visible = is_if and not else_expanded
	if frame != null:
		frame.set_mouth_nodes(frame_mouth_nodes())


## 积木 UI 协议入口：同步引擎只认这个方法，不认具体类。
func bind_model(model: AST_Node) -> void:
	var statement: AST_Statement = model as AST_Statement
	if statement == null:
		push_error("StatementUI (%s): bind_model 收到非 statement 节点。" % name)
		return
	bind_statement(statement)


## 运行时替换调色板。本组件自身不画底色（VBox 没有 panel 样式），
## 只保存它供子积木与工厂取用。
## 语句类型关键字：让积木自己说明它是什么。
## [br]· loop + condition → while（每轮重新判定）
## [br]· loop + 无 condition → repeat（无条件循环）
## [br]· 其余带 condition → if
func statement_keyword(statement: AST_Statement) -> String:
	if statement == null:
		return ""
	if statement.loop:
		return "while" if statement.condition != null else "repeat"
	return "if"


## 外框要挖成凹口的「行」：语句体容器自己（包着它的缩进容器由外框自动并上来）。
## 返回数组 → 传几个就是几个凹口，所以梳型（多臂）在这里是免费的。
func frame_mouth_nodes() -> Array[Node]:
	var nodes: Array[Node] = []
	for candidate: Node in [body_container, else_container]:
		if candidate != null:
			nodes.append(candidate)
	return nodes


## 用调色板刷外框颜色（颜色只来自 Art 的 BlockPalette，本文件不写颜色字面量）。
func _apply_frame_colors() -> void:
	if frame == null or palette == null:
		return
	var base: Color = palette.get_color_for_category(BlockPalette.CATEGORY_STATEMENT)
	frame.set_colors(palette.get_background_color(BlockPalette.CATEGORY_STATEMENT), base.darkened(0.3))


func set_palette(new_palette: BlockPalette) -> void:
	palette = new_palette
	_apply_frame_colors()


## 结构退化协议：条件槽被摘空时补上占位插槽。
## 语句体（body_container）不需要占位 —— 空语句体本来就是合法的。
func repair_slot(container: Node) -> void:
	if container == null or _model == null:
		return
	if container != condition_slot:
		return
	if not AST_BlockSchema.required_roles(_model).has(AST_BlockSchema.ROLE_CONDITION):
		return
	if container is SlotUI:
		# 条件槽本身就是常驻插槽：空了它自己就切成空位外观，不必再塞一个占位进去
		return
	SlotUI.ensure_in(container, AST_BlockSchema.ROLE_CONDITION)


## 语句体挂载 API：由积木工厂把已构造好的子积木加进来。
func add_body_block(block: Control) -> void:
	if body_container == null:
		push_error("StatementUI (%s): body_container 未挂载，无法添加子积木。" % name)
		return
	body_container.add_child(block)


## 清空语句体（只删子节点，不动插槽本身）。
func clear_body() -> void:
	if body_container == null:
		push_error("StatementUI (%s): body_container 未挂载，无法清空语句体。" % name)
		return
	for child: Node in body_container.get_children():
		body_container.remove_child(child)
		child.queue_free()


## 当前语句体里的子积木数量（测试与排版校验用）。
func body_block_count() -> int:
	if body_container == null:
		return 0
	return body_container.get_child_count()


## 只读当前绑定的语句（调试与测试用）。
func get_model() -> AST_Statement:
	return _model


func _validate_mount_points() -> void:
	if condition_slot == null:
		push_error("StatementUI (%s): 必需插槽 condition_slot 未挂载。" % name)
	if body_container == null:
		push_error("StatementUI (%s): 必需插槽 body_container 未挂载。" % name)
	if palette == null:
		push_warning("StatementUI (%s): 未挂载 palette，子积木需各自持有调色板。" % name)


# ------------------------------------------------------------------ 交互状态

## 切换交互状态。视觉一律交给 theme_type_variation，绝不改 modulate。
func _set_interaction_state(state: BlockDragDrop.State) -> void:
	if _state == state:
		return
	_state = state
	# 垂直吸附只有「常态 / 有落点」两种外观，包裹态不适用，故 hovered 复用两次。
	set_theme_type_variation(BlockDragDrop.variation_for_state(
		state, _base_variation, hovered_variation, hovered_variation))


## 当前交互状态（测试与调试用）。
func get_interaction_state() -> BlockDragDrop.State:
	return _state


# ------------------------------------------------------------------ 拖放回调

## 拖拽数据生成：载荷就是 AST 数据本身；同时生成半透明快照并临时隐藏自己。
func _get_drag_data(_at_position: Vector2) -> Variant:
	if _model == null:
		return null
	# 快照挂不上（例如节点不在场景树里）就不启动拖拽，
	# 否则源节点已 hide() 却拖不动，会永久留在隐藏状态。
	if BlockDragDrop.begin_drag(self) == null:
		return null
	_drag_source_active = true
	return BlockDragDrop.make_payload(_model, self)


## 垂直吸附：命中区是整个语句体，插入位由鼠标 Y 与同级子块的中线比较得出。
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return can_drop_block(data)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	drop_block(data)


## 公开的落点判断。除了引擎把事件派发到本组件，嵌套的指令块也会转发到这里
## （见 CommandUI.enclosing_statement()），所以它必须是公开 API 而不是内联在回调里。
func branch_at_pointer() -> VBoxContainer:
	if else_container != null and else_container.is_visible_in_tree() and else_container.get_global_rect().has_point(get_global_mouse_position()):
		return else_container
	return body_container


func can_drop_block(data: Variant) -> bool:
	if condition_slot != null and condition_slot.get_global_rect().has_point(get_global_mouse_position()):
		return false
	return can_drop_in(data, branch_at_pointer())


func can_drop_in(data: Variant, destination: VBoxContainer) -> bool:
	var accepted: bool = BlockDragDrop.is_block_payload(data) and destination != null and (destination == body_container or destination == else_container) and destination.is_visible_in_tree() and BlockDragDrop.can_drop_into(BlockDragDrop.payload_source(data), destination)
	_set_interaction_state(BlockDragDrop.State.HOVERED if accepted else BlockDragDrop.State.NORMAL)
	return accepted


## 公开的落点执行：重排视图 + 发「模型变更意图」。
func drop_block(data: Variant) -> void:
	if can_drop_block(data):
		drop_in(data, branch_at_pointer())


func drop_in(data: Variant, destination: VBoxContainer) -> void:
	var accepted: bool = can_drop_in(data, destination)
	_set_interaction_state(BlockDragDrop.State.NORMAL)
	if not accepted:
		return
	var source: Control = BlockDragDrop.payload_source(data)
	var index: int = BlockDragDrop.compute_insert_index(destination, get_global_mouse_position().y, source)
	BlockDragDrop.commit_drag(source)
	var old_parent: Node = source.get_parent()
	if old_parent != null:
		old_parent.remove_child(source)
	destination.add_child(source)
	destination.move_child(source, index)
	# 源积木原来待的地方可能被摘空了（例如它是某个表达式的必填操作数）
	BlockDragDrop.repair_after_removal(old_parent)
	reorder_requested.emit(BlockDragDrop.Action.INSERT_BEFORE, index, data)


func _notification(what: int) -> void:
	if what != NOTIFICATION_DRAG_END:
		return
	_set_interaction_state(BlockDragDrop.State.NORMAL)
	if _drag_source_active:
		# 拖拽被取消（丢在空处）时恢复被 hide() 的源节点
		_drag_source_active = false
		BlockDragDrop.end_drag(self)


## 鼠标当前对应的插入位；源不可用时返回 -1。
func _insert_index_for(source: Control) -> int:
	if body_container == null:
		return -1
	# 连语句体一起做祖先校验：不能把积木塞进它自己的后代里。
	if not BlockDragDrop.can_drop_into(source, body_container):
		return -1
	# 鼠标落在条件槽范围内就打住：那片区域归 ConditionSlot（SlotUI）自己管。
	# 没有这道闸，拖到条件区会被误判成「往语句体里插」，而且这个过程依赖
	# Godot 是否会把拖放事件回溯到父节点 —— 显式拦住才不依赖引擎细节。
	if condition_slot != null and condition_slot.get_global_rect().has_point(get_global_mouse_position()):
		return -1
	return BlockDragDrop.compute_insert_index(body_container, get_global_mouse_position().y, source)
