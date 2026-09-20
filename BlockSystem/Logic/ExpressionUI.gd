class_name ExpressionUI
extends PanelContainer
## 表达式积木的挂载脚本（组件基座）。
##
## 设计原则：**不生成任何节点**。节点树完全由 Prefabs/*.tscn 提供，
## 美术可以自由增删非核心节点、调整布局，脚本只认下面这几个插槽。
##
## 脚本只做三件事：
##   1. 校验必需插槽是否已挂载；
##   2. 把 AST_Expression 的数据映射到插槽；
##   3. 从 BlockPalette 注入颜色。
##
## 硬约束：本文件不得出现任何颜色或尺寸字面量 ——
## 几何取自 Theme 的 StyleBoxFlat（含 theme_type_variation），
## 颜色取自 BlockPalette，脚本只做「合并」，从不「决定」外观。

## 调色板资源（Art 侧提供）。未挂载时颜色无法注入，_ready 会报错。
@export var palette: BlockPalette

## 颜色类别键：决定取调色板里的哪一支颜色。
@export var category: StringName = BlockPalette.CATEGORY_LOGIC

## 运算符文本标签（可选，一元与二元共用）。
@export var operator_label: Label

## 叶子操作数的文本标签（可选）：显示字面量或变量名，仅叶子积木可见。
@export var value_label: Label

## 左操作数挂载点。
@export var left_slot: Container

## 右操作数挂载点（一元运算符或叶子积木可以为空）。
@export var right_slot: Container

## 作为落点被悬停时切换到的 theme type variation。名字是美术资源，可随意改。
@export var hovered_variation: StringName = &"ExpressionBlock_Hovered"

## 即将被包裹时切换到的 theme type variation。
@export var wrapped_variation: StringName = &"ExpressionBlock_Wrapped"

## 视图重排完成后发出的「模型变更意图」。
## 视图改动由本脚本完成，AST 改动交给工厂（阶段四）接手：
##     block.reorder_requested.connect(_on_reorder.bind(block))
## action 取值见 BlockDragDrop.Action，index 为同级容器中的目标下标。
signal reorder_requested(action: int, index: int, payload: Dictionary)

## 只读数据源：UI 只负责渲染，业务状态始终由 Core 层持有。
var _model: AST_Expression = null

## 常态变体：_ready 时从场景记录，作为状态回退目标（避免两处重复配置）。
var _base_variation: StringName = &""

## 当前交互状态。
var _state: BlockDragDrop.State = BlockDragDrop.State.NORMAL

## 本次拖拽是否由本节点发起（用于拖拽被取消时恢复隐藏的源节点）。
var _drag_source_active: bool = false


func _ready() -> void:
	_base_variation = get_theme_type_variation()
	_validate_mount_points()
	apply_palette()


## 注入数据并刷新视图（不新建节点，操作数由同步引擎挂到 left_slot / right_slot）。
func bind_expression(expression: AST_Expression) -> void:
	_model = expression
	if expression == null:
		return
	var is_leaf: bool = expression.is_leaf()
	if operator_label != null:
		operator_label.text = expression.operator
		# 叶子操作数（如变量名）没有运算符，隐藏以免留出空位。
		operator_label.visible = not expression.operator.is_empty()
	if value_label != null:
		# 只有叶子才有值可显示：运算符节点的 value 恒为 null。
		value_label.visible = is_leaf
		value_label.text = str(expression.value) if is_leaf else ""
	apply_palette()


## 积木 UI 协议入口：同步引擎只认这个方法，不认具体类。
func bind_model(model: AST_Node) -> void:
	var expression: AST_Expression = model as AST_Expression
	if expression == null:
		push_error("ExpressionUI (%s): bind_model 收到非 expression 节点。" % name)
		return
	# 类别由 Core 的 schema 判定（运算符 / 叶子语义），视图不重复做一遍语义判断。
	category = AST_BlockSchema.palette_category(expression)
	bind_expression(expression)


## 运行时替换调色板（例如主题皮肤切换）后立即重新着色。
func set_palette(new_palette: BlockPalette) -> void:
	palette = new_palette
	apply_palette()


## 用调色板着色：几何取自 Theme，只覆盖 bg_color。
## 只在常态下生效 —— 悬停 / 包裹态的外观由美术的状态变体完全接管。
func apply_palette() -> void:
	if _state != BlockDragDrop.State.NORMAL:
		return
	if palette == null:
		push_error("ExpressionUI (%s): 未挂载 BlockPalette，颜色无法注入。" % name)
		return
	# 必须显式传入 theme type：Godot 4.7 实测 get_theme_stylebox(name) 单参调用
	# 不会查 theme_type_variation，会静默回退成默认主题的样式（bg 0.1/0.1/0.1/0.6、
	# margin 0、border 0），从而丢掉美术配的几何。传 &"ExpressionBlock" 或类名都能正确解析。
	var base: StyleBox = get_theme_stylebox(&"panel", get_theme_type_variation())
	if not base is StyleBoxFlat:
		push_error("ExpressionUI (%s): theme type '%s' 没有 StyleBoxFlat('panel')，几何无从取得。" % [
			name, get_theme_type_variation(),
		])
		return
	# 复制主题样式：几何原样保留，只替换底色，绝不触碰 margin / border。
	var styled: StyleBoxFlat = (base as StyleBoxFlat).duplicate() as StyleBoxFlat
	styled.bg_color = palette.get_background_color(category)
	add_theme_stylebox_override(&"panel", styled)
	_report_style_violations(styled)


## 只读当前绑定的表达式（调试与测试用）。
func get_model() -> AST_Expression:
	return _model


func _validate_mount_points() -> void:
	if palette == null:
		push_error("ExpressionUI (%s): 缺少 palette，请在 Prefab 中挂载 Art/Palettes/*.tres。" % name)
	if left_slot == null:
		push_warning("ExpressionUI (%s): left_slot 未挂载（叶子积木可忽略此提示）。" % name)
	if right_slot == null:
		push_warning("ExpressionUI (%s): right_slot 未挂载（一元/叶子积木可忽略此提示）。" % name)


## 把主题样式与规范的偏差暴露出来，避免美术改坏几何却无人察觉。
func _report_style_violations(stylebox: StyleBoxFlat) -> void:
	var problems: PackedStringArray = BlockStyleSpec.validate(stylebox)
	if not problems.is_empty():
		push_warning("ExpressionUI (%s): StyleBoxFlat 不符合规范 -> %s" % [name, ", ".join(problems)])


# ------------------------------------------------------------------ 交互状态

## 切换积木的交互状态。视觉一律交给 theme_type_variation，绝不改 modulate。
func _set_interaction_state(state: BlockDragDrop.State) -> void:
	if _state == state:
		return
	_state = state
	set_theme_type_variation(BlockDragDrop.variation_for_state(
		state, _base_variation, hovered_variation, wrapped_variation))
	if state == BlockDragDrop.State.NORMAL:
		apply_palette()  # 回到常态：重新用调色板上色
	else:
		# 悬停 / 包裹：外观完全交给美术的状态变体。
		# 必须撤掉本地样式覆盖 —— 本地 override 的优先级高于主题（README §7.6），
		# 不撤的话切换变体不会有任何视觉变化。
		remove_theme_stylebox_override(&"panel")


## 当前交互状态（测试与调试用）。
func get_interaction_state() -> BlockDragDrop.State:
	return _state


## 第一个空闲的表达式槽位（包裹落点用）；没有空位返回 null。
## 注意：槽里只有占位插槽（SlotUI）时同样算空闲。
func first_empty_slot() -> Container:
	for slot: Container in [left_slot, right_slot]:
		if slot != null and not _slot_has_block(slot):
			return slot
	return null


## 槽位里是否已经有积木（占位插槽不算）。
static func _slot_has_block(slot: Node) -> bool:
	for child: Node in slot.get_children():
		if BlockSyncEngine.as_block(child) != null:
			return true
	return false


## 容器 -> 角色。视图侧映射，供结构退化与类型校验使用。
func role_of_slot(container: Node) -> StringName:
	if container != null and container == left_slot:
		return AST_BlockSchema.ROLE_LEFT
	if container != null and container == right_slot:
		return AST_BlockSchema.ROLE_RIGHT
	return &""


## 结构退化协议：本积木的某个必填槽位被摘空时补上占位插槽。
## 必填与否由 Core 的 AST_BlockSchema.required_roles() 判定（`a + b` 的左右都必填，
## `not x` 只必填左操作数，叶子没有必填位）。
func repair_slot(container: Node) -> void:
	if container == null or _model == null:
		return
	var role: StringName = role_of_slot(container)
	if role.is_empty():
		return
	if not AST_BlockSchema.required_roles(_model).has(role):
		return
	SlotUI.ensure_in(container, role)


# ------------------------------------------------------------------ 拖放回调

## 拖拽数据生成：载荷就是 AST 数据本身；同时生成半透明快照并临时隐藏自己。
func _get_drag_data(_at_position: Vector2) -> Variant:
	if _model == null:
		return null
	# 快照挂不上（例如节点不在场景树里）就干脆不启动拖拽 ——
	# 否则源节点已经被 hide() 了却拖不动，会永久留在隐藏状态。
	if BlockDragDrop.begin_drag(self) == null:
		return null
	_drag_source_active = true
	return BlockDragDrop.make_payload(_model, self)


## 表达式横向三分区碰撞：左 15% 同级前插 / 中 70% 包裹 / 右 15% 同级后插。
func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not BlockDragDrop.is_block_payload(data):
		return false
	var source: Control = BlockDragDrop.payload_source(data)
	if not BlockDragDrop.can_drop_into(source, self):
		return false

	var zone: BlockDragDrop.Zone = BlockDragDrop.classify_zone(at_position.x, size.x)
	if zone == BlockDragDrop.Zone.WRAP:
		# 包裹：拖拽的积木必须还有空槽位装得下本积木，否则不接收
		var wrapping: ExpressionUI = source as ExpressionUI
		if wrapping == null or wrapping.first_empty_slot() == null:
			return false
		_set_interaction_state(BlockDragDrop.State.WRAPPED)
		return true

	# 左 / 右同级插入：必须先有同级容器
	if not (_sibling_container() is Container):
		return false
	_set_interaction_state(BlockDragDrop.State.HOVERED)
	return true


func _drop_data(at_position: Vector2, data: Variant) -> void:
	# 复用准入判断：正常流程里 Godot 只会对返回 true 的落点调用 _drop_data，
	# 但本方法也可能被直接调用；少了这一步就会做出自包含的非法重排
	# （实测会触发引擎的 "would result in a cyclic dependency"）。
	var accepted: bool = _can_drop_data(at_position, data)
	_set_interaction_state(BlockDragDrop.State.NORMAL)
	if not accepted:
		return
	var source: Control = BlockDragDrop.payload_source(data)
	BlockDragDrop.end_drag(source)  # 恢复被隐藏的源节点（成功的落点）
	var zone: BlockDragDrop.Zone = BlockDragDrop.classify_zone(at_position.x, size.x)
	match zone:
		BlockDragDrop.Zone.WRAP:
			_apply_wrap(source, data)
		BlockDragDrop.Zone.LEFT:
			_apply_sibling_insert(source, false, data)
		_:
			_apply_sibling_insert(source, true, data)


func _notification(what: int) -> void:
	if what != NOTIFICATION_DRAG_END:
		return
	_set_interaction_state(BlockDragDrop.State.NORMAL)
	if _drag_source_active:
		# 拖拽被取消（丢在空处）时恢复被 hide() 的源节点
		_drag_source_active = false
		BlockDragDrop.end_drag(self)


## 同级容器：父节点是 Container 才算数。
func _sibling_container() -> Node:
	var parent: Node = get_parent()
	if parent is Container:
		return parent
	return null


## 把源积木插到本积木的左 / 右侧（同级重排）。
func _apply_sibling_insert(source: Control, after: bool, data: Dictionary) -> void:
	var container: Node = _sibling_container()
	if container == null:
		return
	var old_parent: Node = source.get_parent()
	if old_parent != null:
		old_parent.remove_child(source)
	# 先摘再定位：同容器内摘掉源节点会让本积木下标前移，先算下标会差一位。
	container.add_child(source)
	var index: int = get_index() + (1 if after else 0)
	container.move_child(source, index)
	# 槽里若还留着占位插槽（原先空的必填位），真积木补进来后要撤掉
	SlotUI.clear_from(container)
	# 源积木原来待的地方可能被摘空了，检查要不要补占位
	BlockDragDrop.repair_after_removal(old_parent)
	reorder_requested.emit(
		BlockDragDrop.Action.INSERT_AFTER if after else BlockDragDrop.Action.INSERT_BEFORE, index, data)


## 把本积木装进源积木的空槽位里（包裹）。
func _apply_wrap(source: Control, data: Dictionary) -> void:
	var wrapping: ExpressionUI = source as ExpressionUI
	if wrapping == null:
		return
	var slot: Container = wrapping.first_empty_slot()
	if slot == null:
		return
	SlotUI.clear_from(slot)  # 先撤掉那个空位的占位
	var old_parent: Node = get_parent()
	if old_parent != null:
		old_parent.remove_child(self)
	slot.add_child(self)
	# 本积木离开后，原来的槽位可能也需要补占位
	BlockDragDrop.repair_after_removal(old_parent)
	reorder_requested.emit(BlockDragDrop.Action.WRAP_INTO, slot.get_index(), data)
