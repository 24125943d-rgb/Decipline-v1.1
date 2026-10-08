class_name SlotUI
extends PanelContainer
## 插槽 / 空位占位积木。两个职责合一：
##
## 1. **强类型落点**：`_can_drop_data` 检查拖拽载荷是否符合本槽位的类型规则
##    （种类白名单 + 是否要求布尔结果），不符就返回 false 并切到「拒绝」视觉变体。
##    类型规则本身来自 Core（`AST_BlockSchema.role_requires_boolean` /
##    `AST_TypeInference`），本脚本只负责执行与反馈。
##
## 2. **退化占位**：某个必填操作数被拖走时，由属主积木实例化它填补空位，
##    让结构退化成 `[空插槽] + b` 而不是断成 `+ b`。
##    它自己不参与 AST 编译（`BlockSyncEngine.as_block()` 不认它），
##    所以「空槽」在编译结果里就是 `left = null`。
##
## 视觉：空 / 已填 / 拒绝 三态各对应一个 theme type variation，全部由美术在
## Art/Themes 里定义，脚本不写任何颜色与尺寸。

const TEMPLATE: String = "res://BlockSystem/Prefabs/SlotUI.tscn"
const UIType: GDScript = preload("res://BlockSystem/Logic/BlockUIType.gd")

## 本槽位承担的角色（Core/AST_BlockSchema 的 ROLE_*）。
@export var role: StringName = AST_BlockSchema.ROLE_LEFT

## 是否要求载荷是「布尔结果的表达式」（If 条件槽为 true）。
@export var boolean_required: bool = false

## 允许的积木种类白名单；空数组表示不限种类。
@export var accepted_kinds: Array = [AST_BlockSchema.KIND_EXPRESSION]

## 三个状态的变体名（美术可改）。
@export var empty_variation: StringName = &"SlotPlaceholder"
@export var filled_variation: StringName = &"SlotFilled"
@export var rejected_variation: StringName = &"SlotRejected"

## 空位提示文本（可选）。
@export var hint_label: Label

## 是否「临时占位」。
## - false（预制体里手搭的常驻插槽，例如 If 的条件槽）：装进积木后自己留在原地承接。
## - true（`create()` 造出来的退化占位）：装进积木后自我销毁。
## 二者绝对不能混：常驻插槽一销毁，属主积木的 `condition_slot` 引用就悬空了。
@export var transient_placeholder: bool = false

## 当前是否处于「拒绝」反馈。
var _rejected: bool = false
var _accepted: bool = false


func _ready() -> void:
	child_entered_tree.connect(_on_children_changed)
	child_exiting_tree.connect(_on_children_changed)
	_refresh_look()


# ------------------------------------------------------------------ 状态

## 槽里挂着的积木（装饰节点一律忽略）。
func get_slot_block() -> Control:
	for child: Node in get_children():
		var block: Control = BlockSyncEngine.as_block(child)
		if block != null and not BlockDragDrop.is_drag_source(block):
			return block
	return null


func is_empty() -> bool:
	return get_slot_block() == null


func is_rejected() -> bool:
	return _rejected


func _refresh_look() -> void:
	var look: StringName = empty_variation
	if _rejected:
		look = rejected_variation
	elif _accepted or not is_empty():
		look = filled_variation
	set_theme_type_variation(look)
	if hint_label != null:
		# 空槽靠提示文本撑出体积，否则 PanelContainer 会塌成 0 宽而无法作为落点。
		hint_label.visible = is_empty()


func _on_children_changed(_node: Node) -> void:
	# child_exiting_tree / child_entered_tree 触发时，子节点还没真正进出完毕，
	# 此刻 get_children() 看到的仍是旧状态（实测：拖走条件后槽位仍显示"已填"）。
	# 延后到帧末再刷新才准。
	_refresh_look.call_deferred()


# ------------------------------------------------------------------ 强类型落点

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var model: AST_Node = BlockDragDrop.payload_model(data)
	var source: Control = BlockDragDrop.payload_source(data)
	if model == null or source == null:
		return _set_rejected(false)
	if not BlockDragDrop.can_drop_into(source, self):
		return _set_rejected(true)  # 拒收也要看得见（否则会以为高亮坏了）
	# 槽里已经有积木时，落点应该由那个积木接管（3 分区 / 垂直吸附），本槽位让位。
	if not is_empty():
		return _set_rejected(true)  # 满槽：红一下，明确告诉玩家这里放不下第二个

	var reason: String = rejection_reason(model)
	if not reason.is_empty():
		if not _rejected:
			# 只在「刚进入拒绝态」时报一次：_can_drop_data 每帧都会被调，不能刷屏。
			push_warning("SlotUI(%s): 拒绝落点 -> %s" % [role, reason])
		return _set_rejected(true)
	return _set_rejected(false, true)


## 返回空串表示接受；否则返回人类可读的拒绝原因。
## 这是本插槽的**类型规则**，与视觉无关，可单独单测。
func rejection_reason(model: AST_Node) -> String:
	var kind: StringName = AST_BlockSchema.kind_of(model)
	if not accepted_kinds.is_empty() and not accepted_kinds.has(kind):
		return "本槽位只接受 %s，收到 %s" % [str(accepted_kinds), kind]
	if boolean_required and not AST_TypeInference.is_boolean_result(model):
		return "本槽位要求布尔结果，实际是 %s" % AST_TypeInference.describe(
			AST_TypeInference.result_type(model))
	return ""


func _set_rejected(rejected: bool, accepted: bool = false) -> bool:
	_rejected = rejected
	_accepted = accepted
	_refresh_look()
	return accepted


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var accepted: bool = _can_drop_data(_at_position, data)
	_rejected = false
	_refresh_look()
	if not accepted:
		return
	var source: Control = BlockDragDrop.payload_source(data)
	BlockDragDrop.commit_drag(source)
	var container: Node = get_parent()
	if container == null:
		return
	var old_parent: Node = source.get_parent()
	if old_parent != null:
		old_parent.remove_child(source)
	if transient_placeholder:
		# 退化占位：让真积木顶替自己的位置，然后退场
		var index: int = get_index()
		container.add_child(source)
		container.move_child(source, index)
		container.remove_child(self)
		queue_free()
	else:
		# 常驻插槽：积木成为本槽自己的子节点（槽留在原地承接，不能被顶替或销毁）
		add_child(source)
	# 源积木原来那个槽可能也被摘空了，同样要补占位（递归一层即够）
	BlockDragDrop.repair_after_removal(old_parent)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_accepted = false
		_rejected = false
		_refresh_look()


# ------------------------------------------------------------------ 工厂

## 实例化一个占位插槽（供属主积木在「必填槽位被摘空」时调用）。
static func create(p_role: StringName) -> Control:
	var scene: PackedScene = load(TEMPLATE) as PackedScene
	if scene == null:
		push_error("SlotUI: 占位模板加载失败 %s" % TEMPLATE)
		return null
	var slot: Control = scene.instantiate() as Control
	if not UIType.matches(slot, UIType.SLOT):
		push_error("SlotUI: 模板 %s 的根节点不是 SlotUI。" % TEMPLATE)
		return null
	slot.role = p_role
	# 类型规则来自 Core，视图不重复判断
	slot.boolean_required = AST_BlockSchema.role_requires_boolean(p_role)
	# create() 造出来的一律是临时占位
	slot.transient_placeholder = true
	return slot


## 保证容器里有一个占位；已有积木或已有占位就不动。返回该占位。
static func ensure_in(container: Node, p_role: StringName) -> Control:
	if container == null:
		return null
	for child: Node in container.get_children():
		if UIType.matches(child, UIType.SLOT):
			return child as Control
		if BlockSyncEngine.as_block(child) != null:
			return null  # 槽里已经有积木，不需要占位
	var slot: Control = create(p_role)
	if slot != null:
		container.add_child(slot)
	return slot


## 撤掉容器里的**临时**占位插槽（真积木填进来之后调用）。
## 常驻插槽不会被清掉 —— 它们有归属，不能被顺手删掉。
static func clear_from(container: Node) -> void:
	if container == null:
		return
	for child: Node in container.get_children():
		if UIType.matches(child, UIType.SLOT) and bool(child.get(&"transient_placeholder")):
			container.remove_child(child)
			child.queue_free()
