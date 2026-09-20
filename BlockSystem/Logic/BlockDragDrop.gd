class_name BlockDragDrop
extends RefCounted
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
	return not source.is_ancestor_of(target)


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
	source.hide()
	return preview


## 拖拽结束（成功落点或中途取消）时恢复源节点。幂等。
static func end_drag(source: Control) -> void:
	if source != null and is_instance_valid(source):
		source.show()


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
