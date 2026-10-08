class_name BlockDragDrop
extends RefCounted
const UIType: GDScript = preload("res://BlockSystem/Logic/BlockUIType.gd")
## 拖放交互的通用计算与动作（Logic 层，纯逻辑，不生成任何 UI 结构）。
##
## 三个回调（_get_drag_data / _can_drop_data / _drop_data）必须写在具体预制体的脚本上 ——
## Godot 只会把它们派发给鼠标下的那个 Control。本类把其中可复用、可单测的部分抽出来，
## 供 ExpressionUI / StatementUI 调用，因此这里没有任何 Node 生命周期逻辑。
##
## 视觉约定（硬约束）：积木的状态反馈一律通过切换 theme_type_variation 完成，
## **禁止用 modulate 改色**。唯一例外是拖拽快照本身的半透明 —— 它不是积木的状态，
## 而是快照，且透明度取自主题项 `BlockDrag/preview_modulate`，不是代码里的颜色字面量。

## 拖拽载荷的键名。
const KEY_MODEL: StringName = &"block_model"
const KEY_SOURCE: StringName = &"block_source"

## 表达式横向三分区的边界（规范值：左 15% / 右 85%）。
const ZONE_LEFT_END: float = 0.15
const ZONE_WRAP_END: float = 0.85

## 拖拽快照透明度的主题项（type / 条目名）。
const PREVIEW_THEME_TYPE: StringName = &"BlockDrag"
const PREVIEW_MODULATE: StringName = &"preview_modulate"

## 积木 / 插槽的交互状态。REJECTED = 载荷类型不符，落点拒绝（见 SlotUI）。
enum State { NORMAL, HOVERED, WRAPPED, REJECTED }

## 表达式落点分区。
enum Zone { LEFT, WRAP, RIGHT }

## 视图变更意图。视图改动由预制体脚本执行，AST 改动交给上层工厂（见 reorder_requested）。
enum Action { INSERT_BEFORE, INSERT_AFTER, WRAP_INTO }


# ------------------------------------------------------------------ 载荷

## 组装拖拽载荷：核心是 AST 数据本身，附带源控件以便落点做祖先校验与善后。
static func make_payload(model: AST_Node, source: Control) -> Dictionary:
	return {KEY_MODEL: model, KEY_SOURCE: source}


static func payload_model(data: Variant) -> AST_Node:
	if typeof(data) != TYPE_DICTIONARY:
		return null
	return (data as Dictionary).get(KEY_MODEL, null)


static func payload_source(data: Variant) -> Control:
	if typeof(data) != TYPE_DICTIONARY:
		return null
	return (data as Dictionary).get(KEY_SOURCE, null) as Control


## 合法载荷 = 既有 AST 数据又有源控件。
static func is_block_payload(data: Variant) -> bool:
	return payload_model(data) != null and payload_source(data) != null


## 源能否落在 target 上：禁止落在自己或自己的后代里，
## 否则会造出「自己是自己的孩子」的节点环，重排时死循环。
static func can_drop_into(source: Control, target: Control) -> bool:
	if source == null or target == null:
		return false
	if source == target:
		return false
	if source.is_ancestor_of(target):
		return false
	return _kind_fits(source, target)


## 语法闸门：这一拖有没有「立足之地」。
## 判据是「会落进哪个容器」——只看落点是什么控件不够，因为落在某一行积木上时，
## 插入动作是由那个积木把载荷当作兄弟节点放进它所在的容器里的。
## 注意：这里只回答「能不能」，拒绝的视觉反馈由各控件自己给（见 SlotUI._can_drop_data），
## 两件事必须分开 —— 否则一旦拒收就连高亮都没了。
static func _kind_fits(source: Control, target: Control) -> bool:
	var model: AST_Node = _model_of(source)
	if model == null:
		return true
	var kind: StringName = AST_BlockSchema.kind_of(model)
	var is_expression: bool = kind == AST_BlockSchema.KIND_EXPRESSION

	if UIType.matches(target, UIType.SLOT):
		return true  # 插槽的容量与种类由 SlotUI 自己管
	if UIType.matches(target, UIType.STATEMENT):
		return not is_expression  # 语句体只收指令与语句：表达式在语法上不是「一行」
	if UIType.matches(target, UIType.EXPRESSION):
		return is_expression  # Actual wrap/capacity checks belong to ExpressionUI.
	if UIType.matches(target, UIType.COMMAND):
		return not is_expression  # Command forwards to its enclosing statement, not args.

	var owner: Node = _owning_block(target)
	if UIType.matches(owner, UIType.STATEMENT):
		return not is_expression
	if UIType.matches(owner, UIType.COMMAND):
		return is_expression
	if UIType.matches(owner, UIType.EXPRESSION):
		return false
	return true


## 从落点往上找「掌管这个容器的积木」。容器自己算不上属主，所以从父节点起找。
static func _owning_block(node: Node) -> Node:
	var walker: Node = node.get_parent() if node != null else null
	while walker != null:
		if UIType.matches(walker, UIType.STATEMENT) or UIType.matches(walker, UIType.COMMAND) or UIType.matches(walker, UIType.EXPRESSION):
			return walker
		walker = walker.get_parent()
	return null


## 取控件对应的模型（UI 协议里的 get_model）。
static func _model_of(control: Control) -> AST_Node:
	if control != null and control.has_method(&"get_model"):
		return control.call(&"get_model") as AST_Node
	return null


# ------------------------------------------------------------------ 拖拽快照

## 生成半透明快照、挂到源节点上，并临时隐藏源节点。
##
## 快照会摘掉脚本：它只是像素级拷贝，不该再跑一遍 _ready / 插槽校验 / 调色板注入。
##
## 返回快照控件；返回 null 表示这次拖拽不应启动（源不在场景树里，挂不上快照）。
## 调用方必须据此放弃拖拽 —— 否则源节点被 hide() 了却拖不动，就永久消失了。
static func begin_drag(source: Control) -> Control:
	if source == null or not source.is_inside_tree():
		return null
	# set_drag_preview 要求视口正处于拖拽中。引擎发起拖拽时它已经是 true；
	# 若为 false（例如 _get_drag_data 被直接调用），必须放弃 —— 否则源节点被 hide()
	# 却不会再有 DRAG_END 来恢复它，那块积木就永久消失了。
	var viewport: Viewport = source.get_viewport()
	if viewport == null or not viewport.gui_is_dragging():
		return null
	var preview: Control = source.duplicate() as Control
	if preview == null:
		return null
	preview.set_script(null)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.modulate = resolve_preview_modulate(source)
	source.set_drag_preview(preview)
	reserve_drag_origin(source)
	return preview


## 拖拽结束（成功落点或中途取消）时恢复源节点。幂等。
static func end_drag(source: Control) -> void:
	if source == null or not is_instance_valid(source):
		return
	var placeholder: Node = source.get_meta(&"drag_placeholder", null) as Node
	if is_instance_valid(placeholder) and placeholder.get_parent() != null:
		placeholder.get_parent().remove_child(placeholder)
		placeholder.queue_free()
	commit_drag(source)


## Reserve the exact parameter position while retaining the source for cancellation.
static func reserve_drag_origin(source: Control) -> void:
	source.set_meta(&"drag_active", true)
	source.hide()
	var parent: Node = source.get_parent()
	if UIType.matches(parent, UIType.SLOT):
		parent.call(&"_refresh_look")
		return
	var owner: Node = _owning_block(source)
	var role: StringName = &""
	if UIType.matches(owner, UIType.EXPRESSION):
		role = StringName(owner.call(&"role_of_slot", parent))
	elif UIType.matches(owner, UIType.COMMAND) and parent == (owner.get(&"args_container") as Node):
		role = AST_BlockSchema.ROLE_ARG
	if role.is_empty():
		return
	var slot_script: GDScript = load(UIType.SLOT) as GDScript
	var placeholder: Control = slot_script.call(&"create", role) as Control
	parent.add_child(placeholder)
	parent.move_child(placeholder, source.get_index())
	source.set_meta(&"drag_placeholder", placeholder)


static func is_drag_source(node: Node) -> bool:
	return bool(node.get_meta(&"drag_active", false))


## Successful move keeps the reserved hole. The destination consumes it on a return drop.
static func commit_drag(source: Control) -> void:
	if source == null or not is_instance_valid(source):
		return
	source.remove_meta(&"drag_active")
	source.remove_meta(&"drag_placeholder")
	source.show()
	if UIType.matches(source.get_parent(), UIType.SLOT):
		source.get_parent().call(&"_refresh_look")


## 快照透明度：从主题项读取；条目缺席时退化为 Color.WHITE（不写死颜色字面量）。
static func resolve_preview_modulate(node: Control) -> Color:
	if node.has_theme_color(PREVIEW_MODULATE, PREVIEW_THEME_TYPE):
		return node.get_theme_color(PREVIEW_MODULATE, PREVIEW_THEME_TYPE)
	return Color.WHITE


# ------------------------------------------------------------------ 垂直语句吸附

## 计算插入位：把鼠标全局 Y 与参与排布的 Control 子节点「中线」比较，数出应排在前面的块数。
##
## 用中线而不是上边缘：以第 0 块为例，鼠标停在它中部时，按上边缘会算出 index=1
## （插到它后面），手感明显错位；中线判定才符合「停在下半部分就插在它后面」的直觉。
##
## 被拖拽的节点（excluded）与不可见节点都会跳过 —— 源节点此刻正被 hide()，
## 不跳过的话它的旧坐标会被算进去，插入位就会错一位。
##
## 返回值语义：先 remove_child 掉源节点，再把它插到该下标处，即为正确落点。
static func compute_insert_index(container: Node, mouse_global_y: float, excluded: Node = null) -> int:
	if container == null:
		return 0
	var index: int = 0
	for child: Node in container.get_children():
		if child == excluded:
			continue
		var control: Control = child as Control
		if control == null or not control.visible:
			continue
		if mouse_global_y > control.global_position.y + control.size.y * 0.5:
			index += 1
	return index


# ------------------------------------------------------------------ 表达式横向三分区

## 按鼠标本地 X 与节点宽度分区。区间完整覆盖且无重叠：
## [0, 15%) 左同级 / [15%, 85%) 包裹 / [85%, 100%] 右同级。
## 宽度为 0（尚未排版）时退化为 WRAP。
static func classify_zone(local_x: float, width: float) -> Zone:
	if width <= 0.0:
		return Zone.WRAP
	var ratio: float = clampf(local_x / width, 0.0, 1.0)
	if ratio < ZONE_LEFT_END:
		return Zone.LEFT
	if ratio < ZONE_WRAP_END:
		return Zone.WRAP
	return Zone.RIGHT


## 分区 -> 视图变更意图。
static func action_for_zone(zone: Zone) -> Action:
	match zone:
		Zone.LEFT:
			return Action.INSERT_BEFORE
		Zone.RIGHT:
			return Action.INSERT_AFTER
		_:
			return Action.WRAP_INTO


# ------------------------------------------------------------------ 状态变体

## 状态 -> 变体名。名字由预制体导出（美术可改），本函数只做选择，不碰任何颜色。
## rejected 省略时退化为 normal（不认识拒绝态的组件不受影响）。
static func variation_for_state(state: State, normal: StringName, hovered: StringName, wrapped: StringName, rejected: StringName = &"") -> StringName:
	match state:
		State.HOVERED:
			return hovered
		State.WRAPPED:
			return wrapped
		State.REJECTED:
			return rejected if not rejected.is_empty() else normal
		_:
			return normal


# ------------------------------------------------------------------ 结构退化

## 结构退化：某个槽位因为积木被拖走而变空后，请它的属主积木补上占位插槽。
##
## 调用点固定为「把某个积木从原容器摘走之后」。属主通过可选协议方法
## `repair_slot(container)` 自行判断：这个容器是不是我的必填槽位？现在是空的吗？
## 判断依据是 Core 的 `AST_BlockSchema.required_roles()`。
##
## 注意要**向上查找**属主，不能只看父节点：槽位未必是积木的直接子节点 ——
## ExpressionBlockUI 里左操作数槽是 `Row/LeftSlot`，中间还隔着一层布局容器。
## 每个 repair_slot 实现都会自己确认「这个容器是不是我的」，所以多走几层是安全的。
static func repair_after_removal(container: Node) -> void:
	if container == null:
		return
	var candidate: Node = container.get_parent()
	while candidate != null:
		if candidate.has_method(&"repair_slot"):
			candidate.call(&"repair_slot", container)
			return
		candidate = candidate.get_parent()
