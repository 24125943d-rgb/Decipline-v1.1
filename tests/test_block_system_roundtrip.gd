extends Node
## BlockSystem Logic 层「AST ⇄ UI 双向同步」集成测试。
##
## 运行器约定：extends Node，方法名以 test_ 开头，返回 null = 通过、字符串 = 失败原因。
##
## 覆盖 README §2「Logic 交互层」的主链路与 §7 的几条引擎坑：
##   · BlockSyncEngine 的 AST → UI → AST 往返：结构由 UI 决定、原子数据沿用模型
##   · 积木 UI 协议（set_palette / bind_model / get_model）与「引擎不认识具体类名」
##   · 类别来自 Core 的 schema（视图不重复做语义判断）
##   · §7.7 begin_drag 在「非真实拖拽」时必须放弃，否则源积木会永久隐藏
##   · §7.10 找槽位属主必须向上查找（表达式槽藏在布局容器里）
##   · §7.11 子节点进出时立刻读到的还是旧状态，外观刷新必须延到帧末
##   · 插槽的强类型落点（拒绝原因来自 Core 的 required_roles / 类型推断）
##
## 这些用例需要在场景树里跑（引擎要 await process_frame），所以统一把节点挂到本测试节点下，
## after_each 里回收。

## 演示程序：if (score > 3) { move_forward 3 fast; turn_left 90; repeat { say hello } }
const DEMO: Dictionary = {
	"type": "statement",
	"condition": {
		"type": "expression", "operator": ">",
		"left": {"type": "expression", "operator": "", "left": null, "right": null, "value": "score"},
		"right": {"type": "expression", "operator": "", "left": null, "right": null, "value": 3},
		"value": null,
	},
	"body": [
		{"type": "command", "opcode": "move_forward", "args": [3, "fast"]},
		{"type": "command", "opcode": "turn_left", "args": [90]},
		{
			"type": "statement",
			"condition": null,
			"body": [{"type": "command", "opcode": "say", "args": ["hello"]}],
		},
	],
}

## 二元表达式 a + 2（用于考「必填操作数被拖走后补占位」）。
const BINARY: Dictionary = {
	"type": "expression", "operator": "+",
	"left": {"type": "expression", "operator": "", "left": null, "right": null, "value": "a"},
	"right": {"type": "expression", "operator": "", "left": null, "right": null, "value": 2},
	"value": null,
}

var _failures: PackedStringArray = PackedStringArray()
var _spawned: Array[Node] = []
var _engine: BlockSyncEngine = null


func before_each() -> void:
	_failures.clear()
	_engine = null


func after_each() -> void:
	for node: Node in _spawned:
		if is_instance_valid(node):
			node.free()
	_spawned.clear()
	_engine = null

# ------------------------------------------------------------------ 主链路
func test_ast_to_ui_to_ast_round_trip() -> Variant:
	var source: AST_Node = ASTManager.from_dictionary(DEMO)
	var ui: Control = await _build(source)
	_check(ui != null, "能由 AST 构建出积木 UI")
	if ui == null:
		return _verdict("test_ast_to_ui_to_ast_round_trip")
	var rebuilt: AST_Node = _engine.build_ast_from_ui(ui)
	_check(rebuilt != null, "能由 UI 重建 AST")
	if rebuilt != null:
		_check_eq(
			rebuilt.to_dictionary(), source.to_dictionary(),
			"往返后结构完全一致（嵌套与顺序都由 UI 决定）"
		)
		_check_eq(
			ASTManager.serialize_ast_to_json(rebuilt), ASTManager.serialize_ast_to_json(source),
			"序列化文本逐字符相同"
		)
	return _verdict("test_ast_to_ui_to_ast_round_trip")


func test_built_ui_structure_matches_ast() -> Variant:
	var ui: Control = await _build(ASTManager.from_dictionary(DEMO))
	if ui == null or not (ui is StatementUI):
		_check(false, "根节点是 StatementUI")
		return _verdict("test_built_ui_structure_matches_ast")
	var statement: StatementUI = ui
	_check(statement.condition_slot != null and statement.body_container != null, "两个插槽都挂上了")
	if statement.condition_slot == null or statement.body_container == null:
		return _verdict("test_built_ui_structure_matches_ast")
	# 条件槽是常驻插槽（SlotUI），里面除了积木还有提示文本等装饰节点，不能直接数 children
	var condition_block: Control = _block_in(statement.condition_slot)
	_check(condition_block != null, "条件槽里挂了积木")
	_check_eq(_block_count(statement.condition_slot), 1, "条件槽里正好 1 块积木")
	_check(condition_block is ExpressionUI, "条件是表达式积木")
	if condition_block is ExpressionUI:
		_check_eq((condition_block as ExpressionUI).operator_label.text, ">", "运算符标签显示 >")
	var kinds: PackedStringArray = PackedStringArray()
	for child: Node in statement.body_container.get_children():
		var kind: StringName = _kind_of(child as Control)
		if not kind.is_empty():
			kinds.append(String(kind))
	_check_eq(kinds, PackedStringArray(["command", "command", "statement"]), "语句体 3 块、顺序与种类正确")
	# 嵌套语句没有条件：它的条件槽应该被藏起来（视图由数据决定，不是硬编码）
	var nested: Control = null
	for child: Node in statement.body_container.get_children():
		if _kind_of(child as Control) == AST_BlockSchema.KIND_STATEMENT:
			nested = child as Control
	if nested is StatementUI:
		_check(not (nested as StatementUI).condition_slot.visible, "无条件语句把条件槽藏起来")
		_check_eq((nested as StatementUI).body_container.get_child_count(), 1, "嵌套语句体 1 块")
	return _verdict("test_built_ui_structure_matches_ast")


func test_models_are_bound_and_categories_come_from_core() -> Variant:
	var ui: Control = await _build(ASTManager.from_dictionary(DEMO))
	if ui == null:
		_check(false, "构建出 UI")
		return _verdict("test_models_are_bound_and_categories_come_from_core")
	var statement: StatementUI = ui as StatementUI
	var condition: ExpressionUI = _block_in(statement.condition_slot) as ExpressionUI
	_check(condition != null, "条件槽里是表达式积木")
	if condition == null:
		return _verdict("test_models_are_bound_and_categories_come_from_core")
	_check(condition.get_model() != null, "表达式积木读得到绑定的模型")
	if condition.get_model() != null:
		_check_eq(condition.get_model().operator, ">", "绑定的是原始模型（原子数据沿用，界面上不可编辑）")
		_check_eq(
			condition.category, AST_BlockSchema.palette_category(condition.get_model()),
			"类别来自 Core 的 schema，不重复判断"
		)
	# 左操作数是变量名 → 变量色；右操作数是数字字面量 → 数学色
	var left_leaf: ExpressionUI = _block_in(condition.left_slot) as ExpressionUI
	var right_leaf: ExpressionUI = _block_in(condition.right_slot) as ExpressionUI
	_check(left_leaf != null and right_leaf != null, "两个操作数都挂上了")
	if left_leaf == null or right_leaf == null:
		return _verdict("test_models_are_bound_and_categories_come_from_core")
	_check_eq(left_leaf.category, AST_BlockSchema.CATEGORY_VARIABLE, "变量名叶子用变量色")
	_check_eq(right_leaf.category, AST_BlockSchema.CATEGORY_MATH, "数字字面量用数学色")
	return _verdict("test_models_are_bound_and_categories_come_from_core")


func test_engine_injects_the_palette_into_blocks() -> Variant:
	var ui: Control = await _build(ASTManager.from_dictionary(DEMO))
	if ui == null:
		_check(false, "构建出 UI")
		return _verdict("test_engine_injects_the_palette_into_blocks")
	_check(_engine.palette != null, "引擎自己有调色板（没配就用默认的）")
	var condition: ExpressionUI = _block_in((ui as StatementUI).condition_slot) as ExpressionUI
	_check(condition != null, "找到条件积木")
	if condition == null:
		return _verdict("test_engine_injects_the_palette_into_blocks")
	_check(condition.palette != null, "表达式积木拿到了调色板")
	_check(condition.palette == _engine.palette, "注入的就是引擎那一份")
	return _verdict("test_engine_injects_the_palette_into_blocks")

# ------------------------------------------------------------------ 引擎 / 模板契约
func test_templates_and_slots_cover_every_kind_and_role() -> Variant:
	for kind: StringName in [
		AST_BlockSchema.KIND_STATEMENT, AST_BlockSchema.KIND_COMMAND, AST_BlockSchema.KIND_EXPRESSION,
	]:
		_check(BlockSyncEngine.TEMPLATES.has(kind), "注册了模板：%s" % kind)
		var path: String = BlockSyncEngine.TEMPLATES.get(kind, "")
		var scene: PackedScene = load(path) as PackedScene
		if scene == null:
			_check(false, "模板能加载：%s" % path)
			continue
		var instance: Node = scene.instantiate()
		_check(instance is Control, "模板根是 Control：%s" % path)
		for method: StringName in [&"set_palette", &"bind_model", &"get_model"]:
			_check(instance.has_method(method), "%s 实现了积木 UI 协议 %s" % [path.get_file(), method])
		instance.free()
	for role: StringName in [
		AST_BlockSchema.ROLE_CONDITION, AST_BlockSchema.ROLE_BODY,
		AST_BlockSchema.ROLE_LEFT, AST_BlockSchema.ROLE_RIGHT,
	]:
		_check(BlockSyncEngine.ROLE_SLOTS.has(role), "注册了插槽属性：%s" % role)
	return _verdict("test_templates_and_slots_cover_every_kind_and_role")


func test_block_detection_ignores_decoration_and_slots() -> Variant:
	var label: Label = Label.new()
	_check(BlockSyncEngine.as_block(label) == null, "普通控件不算积木")
	label.free()
	var slot: SlotUI = SlotUI.create(AST_BlockSchema.ROLE_LEFT)
	# 占位插槽不参与 AST 编译（README：空槽在编译结果里就是 left = null）
	_check(BlockSyncEngine.as_block(slot) == null, "插槽不算积木")
	slot.free()
	var command: CommandUI = CommandUI.new()
	_check(BlockSyncEngine.as_block(command) != null, "三类积木控件都算积木")
	command.free()
	return _verdict("test_block_detection_ignores_decoration_and_slots")

# ------------------------------------------------------------------ §7.7 拖拽启动守卫
func test_begin_drag_refuses_outside_a_real_drag() -> Variant:
	var ui: Control = await _build(ASTManager.from_dictionary(DEMO))
	if ui == null:
		_check(false, "构建出 UI")
		return _verdict("test_begin_drag_refuses_outside_a_real_drag")
	# 测试代码直接调用时视口并没有在拖拽中，set_drag_preview 会失败并报错；
	# begin_drag 必须先自己判定并返回 null，而且不能把源节点 hide() 掉。
	var preview: Control = BlockDragDrop.begin_drag(ui)
	_check(preview == null, "非拖拽状态下放弃启动")
	_check(ui.visible, "源积木没有被隐藏（否则会永久消失）")
	_check(not ui.is_inside_tree() or ui.get_viewport() != null, "节点仍在正常的场景里")
	return _verdict("test_begin_drag_refuses_outside_a_real_drag")

# ------------------------------------------------------------------ 插槽强类型
func test_slot_factory_follows_core_rules() -> Variant:
	var condition_slot: SlotUI = SlotUI.create(AST_BlockSchema.ROLE_CONDITION)
	var left_slot: SlotUI = SlotUI.create(AST_BlockSchema.ROLE_LEFT)
	_check(condition_slot != null and left_slot != null, "能造出两种插槽")
	if condition_slot == null or left_slot == null:
		return _verdict("test_slot_factory_follows_core_rules")
	_check_eq(condition_slot.role, AST_BlockSchema.ROLE_CONDITION, "角色写进去了")
	_check(condition_slot.boolean_required, "条件槽要求布尔（规则来自 Core）")
	_check(not left_slot.boolean_required, "左操作数槽不要求布尔")
	_check(condition_slot.transient_placeholder, "create() 造出来的是临时占位")
	_check_eq(condition_slot.accepted_kinds, [AST_BlockSchema.KIND_EXPRESSION], "默认只收表达式")
	condition_slot.free()
	left_slot.free()
	return _verdict("test_slot_factory_follows_core_rules")


func test_slot_rejection_reasons() -> Variant:
	var slot: SlotUI = SlotUI.create(AST_BlockSchema.ROLE_CONDITION)
	if slot == null:
		_check(false, "能造出条件槽")
		return _verdict("test_slot_rejection_reasons")
	_check_eq(
		slot.rejection_reason(AST_Expression.make_binary(">", _literal(1), _literal(2))), "",
		"比较表达式放行"
	)
	_check_eq(slot.rejection_reason(_literal("flag")), "", "未知类型放行（if flag 要能用）")
	var number_reason: String = slot.rejection_reason(_literal(3))
	_check(not number_reason.is_empty(), "数字被拒绝")
	_check(number_reason.contains("Boolean") or number_reason.contains("布尔"), "拒绝原因说明要求布尔：%s" % number_reason)
	var command_reason: String = slot.rejection_reason(AST_Command.new("move_forward"))
	_check(not command_reason.is_empty(), "指令被拒绝（种类白名单）")
	slot.free()

	var loose: SlotUI = SlotUI.create(AST_BlockSchema.ROLE_LEFT)
	loose.accepted_kinds = []
	if loose != null:
		_check_eq(loose.rejection_reason(AST_Command.new("m")), "", "白名单为空表示不限种类")
		loose.free()
	return _verdict("test_slot_rejection_reasons")


func test_placeholder_ensure_in_and_clear_from() -> Variant:
	var container: Container = VBoxContainer.new()
	add_child(container)
	_spawned.append(container)
	var first: SlotUI = SlotUI.ensure_in(container, AST_BlockSchema.ROLE_LEFT)
	_check(first != null, "空容器会补一个占位")
	_check_eq(container.get_child_count(), 1, "只补一个")
	_check(SlotUI.ensure_in(container, AST_BlockSchema.ROLE_LEFT) == first, "已有占位就不重复补")
	# 槽里已经有真积木时不补（用预制体积木，避免裸 new 出来的控件缺插槽而报错）
	var with_block: Container = VBoxContainer.new()
	add_child(with_block)
	_spawned.append(with_block)
	var real_block: Control = (
		load(BlockSyncEngine.TEMPLATES[AST_BlockSchema.KIND_COMMAND]) as PackedScene
	).instantiate() as Control
	with_block.add_child(real_block)
	_check(SlotUI.ensure_in(with_block, AST_BlockSchema.ROLE_LEFT) == null, "有积木就不补占位")
	# clear_from 只清临时占位：常驻插槽有归属，不能被顺手删掉（README §2）
	var permanent: SlotUI = SlotUI.create(AST_BlockSchema.ROLE_LEFT)
	permanent.transient_placeholder = false
	container.add_child(permanent)
	SlotUI.clear_from(container)
	_check(container.get_child_count() == 1, "临时占位被清掉、常驻插槽留下")
	if container.get_child_count() == 1:
		_check_eq(container.get_child(0), permanent, "留下的是常驻插槽")
	return _verdict("test_placeholder_ensure_in_and_clear_from")

# ------------------------------------------------------------------ §7.10 / §7.11
func test_repair_after_removal_finds_owner_by_walking_up() -> Variant:
	var ui: Control = await _build(ASTManager.from_dictionary(BINARY))
	if ui == null or not (ui is ExpressionUI):
		_check(false, "构建出表达式积木")
		return _verdict("test_repair_after_removal_finds_owner_by_walking_up")
	var block: ExpressionUI = ui
	_check(block.left_slot != null, "左槽已挂载")
	if block.left_slot == null:
		return _verdict("test_repair_after_removal_finds_owner_by_walking_up")
	var operand: Control = _block_in(block.left_slot)
	_check(operand != null, "左槽里有操作数")
	if operand == null:
		return _verdict("test_repair_after_removal_finds_owner_by_walking_up")
	# 模拟被拖走：先出容器，再请属主补位（属主在 Row 之上，所以必须向上查找）
	block.left_slot.remove_child(operand)
	operand.queue_free()
	BlockDragDrop.repair_after_removal(block.left_slot)
	var placeholder: SlotUI = null
	for child: Node in block.left_slot.get_children():
		if child is SlotUI:
			placeholder = child as SlotUI
	_check(placeholder != null, "必填的左操作数空了 → 补上占位插槽")
	if placeholder != null:
		_check_eq(placeholder.role, AST_BlockSchema.ROLE_LEFT, "占位角色是 left")
		_check(placeholder.transient_placeholder, "是临时占位")
		_check(not placeholder.boolean_required, "左槽不要求布尔")
	# 占位不参与编译：空槽在 AST 里就是 null
	var rebuilt: AST_Node = _engine.build_ast_from_ui(block)
	if rebuilt is AST_Expression:
		var expression: AST_Expression = rebuilt
		_check(expression.left == null, "左操作数编译成 null")
		_check(expression.right != null, "右操作数还在")
	return _verdict("test_repair_after_removal_finds_owner_by_walking_up")


func test_slot_look_refresh_is_deferred() -> Variant:
	var slot: SlotUI = SlotUI.create(AST_BlockSchema.ROLE_LEFT)
	if slot == null:
		_check(false, "能造出插槽")
		return _verdict("test_slot_look_refresh_is_deferred")
	add_child(slot)
	_spawned.append(slot)
	_check_eq(slot.get_theme_type_variation(), slot.empty_variation, "初始是空位外观")
	_check(slot.is_empty(), "初始是空的")
	var scene: PackedScene = load(BlockSyncEngine.TEMPLATES[AST_BlockSchema.KIND_EXPRESSION]) as PackedScene
	var block: Control = scene.instantiate() as Control
	slot.add_child(block)
	# §7.11：child_entered_tree 触发时子节点还没真正就位，刷新被推后到帧末
	_check_eq(slot.get_theme_type_variation(), slot.empty_variation, "同一帧内外观还没刷新")
	_check(not slot.is_empty(), "但内容判断已经是准的（读的是实时子节点）")
	await get_tree().process_frame
	_check_eq(slot.get_theme_type_variation(), slot.filled_variation, "帧末刷新成已填外观")
	return _verdict("test_slot_look_refresh_is_deferred")

# ------------------------------------------------------------------ 纯计算
func test_classify_zone_covers_the_whole_width() -> Variant:
	_check_eq(BlockDragDrop.classify_zone(0.0, 100.0), BlockDragDrop.Zone.LEFT, "0% 左分区")
	_check_eq(BlockDragDrop.classify_zone(14.9, 100.0), BlockDragDrop.Zone.LEFT, "15% 之前是左分区")
	_check_eq(BlockDragDrop.classify_zone(15.0, 100.0), BlockDragDrop.Zone.WRAP, "正好 15% 归包裹")
	_check_eq(BlockDragDrop.classify_zone(50.0, 100.0), BlockDragDrop.Zone.WRAP, "中间是包裹")
	_check_eq(BlockDragDrop.classify_zone(84.9, 100.0), BlockDragDrop.Zone.WRAP, "85% 之前仍是包裹")
	_check_eq(BlockDragDrop.classify_zone(85.0, 100.0), BlockDragDrop.Zone.RIGHT, "85% 起是右分区")
	_check_eq(BlockDragDrop.classify_zone(-20.0, 100.0), BlockDragDrop.Zone.LEFT, "越界负数夹到左")
	_check_eq(BlockDragDrop.classify_zone(120.0, 100.0), BlockDragDrop.Zone.RIGHT, "越界超宽夹到右")
	_check_eq(BlockDragDrop.classify_zone(50.0, 0.0), BlockDragDrop.Zone.WRAP, "宽度 0（未排版）退化为包裹")
	_check_eq(BlockDragDrop.action_for_zone(BlockDragDrop.Zone.LEFT), BlockDragDrop.Action.INSERT_BEFORE, "左 → 前插")
	_check_eq(BlockDragDrop.action_for_zone(BlockDragDrop.Zone.RIGHT), BlockDragDrop.Action.INSERT_AFTER, "右 → 后插")
	_check_eq(BlockDragDrop.action_for_zone(BlockDragDrop.Zone.WRAP), BlockDragDrop.Action.WRAP_INTO, "中 → 包裹")
	return _verdict("test_classify_zone_covers_the_whole_width")


func test_compute_insert_index_uses_half_height() -> Variant:
	var host: Control = Control.new()  # 普通 Control 不做布局，手动摆的位置不会被覆盖
	add_child(host)
	_spawned.append(host)
	var rows: Array[Control] = []
	for i: int in 3:
		var row: Control = Control.new()
		row.position = Vector2(0.0, float(i) * 100.0)
		row.size = Vector2(50.0, 100.0)
		host.add_child(row)
		rows.append(row)
	_check_eq(BlockDragDrop.compute_insert_index(host, 0.0), 0, "在最上面 → 插到最前")
	_check_eq(BlockDragDrop.compute_insert_index(host, 150.0), 1, "中线判定：150 只越过第 1 块")
	_check_eq(BlockDragDrop.compute_insert_index(host, 1000.0), 3, "在最下面 → 插到最后")
	_check_eq(
		BlockDragDrop.compute_insert_index(host, 150.0, rows[0]), 0,
		"被拖拽的节点要排除（它此刻是隐藏的，旧坐标不能算进去）"
	)
	rows[0].visible = false
	_check_eq(BlockDragDrop.compute_insert_index(host, 150.0), 0, "不可见节点同样跳过")
	rows[0].visible = true
	var empty: Control = Control.new()
	add_child(empty)
	_spawned.append(empty)
	_check_eq(BlockDragDrop.compute_insert_index(empty, 100.0), 0, "空容器 → 0")
	_check_eq(BlockDragDrop.compute_insert_index(null, 100.0), 0, "null 容器 → 0（不崩）")
	return _verdict("test_compute_insert_index_uses_half_height")


func test_variation_for_state_picks_the_right_name() -> Variant:
	_check_eq(
		BlockDragDrop.variation_for_state(BlockDragDrop.State.NORMAL, &"n", &"h", &"w"), &"n", "常态"
	)
	_check_eq(
		BlockDragDrop.variation_for_state(BlockDragDrop.State.HOVERED, &"n", &"h", &"w"), &"h", "悬停"
	)
	_check_eq(
		BlockDragDrop.variation_for_state(BlockDragDrop.State.WRAPPED, &"n", &"h", &"w"), &"w", "包裹"
	)
	_check_eq(
		BlockDragDrop.variation_for_state(BlockDragDrop.State.REJECTED, &"n", &"h", &"w"), &"n",
		"没给拒绝变体时退化为常态"
	)
	_check_eq(
		BlockDragDrop.variation_for_state(BlockDragDrop.State.REJECTED, &"n", &"h", &"w", &"r"), &"r",
		"给了就用拒绝变体"
	)
	return _verdict("test_variation_for_state_picks_the_right_name")


func test_can_drop_into_rejects_self_and_descendants() -> Variant:
	var parent: Control = Control.new()
	var child: Control = Control.new()
	parent.add_child(child)
	_check(BlockDragDrop.can_drop_into(child, parent), "子能落到父上")
	_check(not BlockDragDrop.can_drop_into(parent, child), "不能落进自己的后代（会造出节点环）")
	_check(not BlockDragDrop.can_drop_into(parent, parent), "不能落到自己身上")
	_check(not BlockDragDrop.can_drop_into(null, parent), "null 源不放行")
	_check(not BlockDragDrop.can_drop_into(parent, null), "null 目标不放行")
	var payload: Dictionary = BlockDragDrop.make_payload(AST_Command.new("m"), parent)
	_check(BlockDragDrop.is_block_payload(payload), "载荷合法")
	_check(BlockDragDrop.payload_source(payload) == parent, "载荷带源控件")
	_check(BlockDragDrop.payload_model(payload) is AST_Command, "载荷带 AST 数据")
	_check(not BlockDragDrop.is_block_payload({}), "空字典不是合法载荷")
	_check(not BlockDragDrop.is_block_payload("nope"), "非字典不是合法载荷")
	parent.free()
	return _verdict("test_can_drop_into_rejects_self_and_descendants")

# ------------------------------------------------------------------ 工具
## 构建积木 UI 并挂进场景树（引擎必须待在树里才能 await process_frame）。
func _build(source: AST_Node) -> Control:
	if source == null:
		return null
	_engine = BlockSyncEngine.new()
	_engine.blocks_per_frame = 64  # 测试里不需要一帧一块地慢慢长
	add_child(_engine)
	_spawned.append(_engine)
	var ui: Control = await _engine.build_ui_from_ast(source)
	if ui != null:
		add_child(ui)
		_spawned.append(ui)
	return ui


## 挂载点里真正的那块积木（槽里除了积木还可能有提示文本等装饰节点）。
func _block_in(container: Node) -> Control:
	if container == null:
		return null
	for child: Node in container.get_children():
		var block: Control = BlockSyncEngine.as_block(child)
		if block != null:
			return block
	return null


## 挂载点里有几块积木（装饰节点不算）。
func _block_count(container: Node) -> int:
	var count: int = 0
	if container == null:
		return 0
	for child: Node in container.get_children():
		if BlockSyncEngine.as_block(child) != null:
			count += 1
	return count


## 某个节点（可能是装饰节点）对应的 AST 种类；不是积木返回空串。
func _kind_of(node: Control) -> StringName:
	if node == null or not node.has_method(&"get_model"):
		return &""
	return AST_BlockSchema.kind_of(node.call(&"get_model") as AST_Node)


func _literal(value: Variant) -> AST_Expression:
	return AST_Expression.make_literal(value)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)


func _check_eq(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s（期望 %s，实际 %s）" % [label, expected, actual])


func _verdict(test_name: String) -> Variant:
	if _failures.is_empty():
		print("PASS  ", test_name)
		return null
	var message: String = ""
	for failure: String in _failures:
		message += "\n   - " + failure
	print("FAIL  ", test_name, message)
	return message
