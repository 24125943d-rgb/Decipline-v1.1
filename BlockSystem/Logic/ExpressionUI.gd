class_name ExpressionUI
extends PanelContainer

@export var palette: BlockPalette
@export var category: StringName = BlockPalette.CATEGORY_LOGIC
@export var operator_label: Label
@export var value_label: Label
@export var left_slot: Container
@export var right_slot: Container
@export var hovered_variation: StringName = &"ExpressionBlock_Hovered"
@export var wrapped_variation: StringName = &"ExpressionBlock_Wrapped"
signal reorder_requested(action: int, index: int, payload: Dictionary)
var _model: AST_Expression
var _base_variation: StringName = &"ExpressionBlock"
var _state: BlockDragDrop.State = BlockDragDrop.State.NORMAL
var _drag_source_active: bool = false

func _ready() -> void:
	_base_variation = get_theme_type_variation()
	apply_palette()

func bind_model(model: AST_Node) -> void:
	category = AST_BlockSchema.palette_category(model)
	bind_expression(model as AST_Expression)

func bind_expression(expression: AST_Expression) -> void:
	_model = expression
	if expression == null:
		return
	if operator_label != null:
		operator_label.text = expression.operator
		operator_label.visible = not expression.operator.is_empty()
	if value_label != null:
		value_label.visible = expression.is_leaf()
		value_label.text = str(expression.value) if expression.is_leaf() else ""
	apply_palette()

func set_palette(value: BlockPalette) -> void:
	palette = value
	apply_palette()

func apply_palette() -> void:
	if palette == null or _state != BlockDragDrop.State.NORMAL:
		return
	var base: StyleBoxFlat = get_theme_stylebox(&"panel", get_theme_type_variation()) as StyleBoxFlat
	if base == null:
		return
	var styled: StyleBoxFlat = base.duplicate() as StyleBoxFlat
	styled.bg_color = palette.get_background_color(category)
	add_theme_stylebox_override(&"panel", styled)

func get_model() -> AST_Expression:
	return _model

func get_interaction_state() -> BlockDragDrop.State:
	return _state

func _set_interaction_state(state: BlockDragDrop.State) -> void:
	_state = state
	set_theme_type_variation(BlockDragDrop.variation_for_state(state, _base_variation, hovered_variation, wrapped_variation))
	if state == BlockDragDrop.State.NORMAL:
		apply_palette()
	else:
		remove_theme_stylebox_override(&"panel")

static func _slot_has_block(slot: Node) -> bool:
	for child: Node in slot.get_children():
		if BlockSyncEngine.as_block(child) != null:
			return true
	return false

func first_empty_slot() -> Container:
	if _model == null or _model.operator.is_empty():
		return null
	for slot: Container in [left_slot, right_slot]:
		if slot == right_slot and _model.operator == "not":
			continue
		if slot != null and not _slot_has_block(slot):
			return slot
	return null

func role_of_slot(container: Node) -> StringName:
	if container != null and container == left_slot:
		return AST_BlockSchema.ROLE_LEFT
	if container != null and container == right_slot:
		return AST_BlockSchema.ROLE_RIGHT
	return &""

func repair_slot(container: Node) -> void:
	var role: StringName = role_of_slot(container)
	if _model != null and not role.is_empty() and AST_BlockSchema.required_roles(_model).has(role):
		SlotUI.ensure_in(container, role)

func _get_drag_data(_position: Vector2) -> Variant:
	if _model == null or BlockDragDrop.begin_drag(self) == null:
		return null
	_drag_source_active = true
	return BlockDragDrop.make_payload(_model, self)

func _can_drop_data(position: Vector2, data: Variant) -> bool:
	_set_interaction_state(BlockDragDrop.State.NORMAL)
	if not BlockDragDrop.is_block_payload(data):
		return false
	var source: Control = BlockDragDrop.payload_source(data)
	if not BlockDragDrop.can_drop_into(source, self):
		return false
	var zone: BlockDragDrop.Zone = BlockDragDrop.classify_zone(position.x, size.x)
	if zone == BlockDragDrop.Zone.WRAP:
		var wrapping: ExpressionUI = source as ExpressionUI
		if wrapping == null or wrapping.first_empty_slot() == null:
			return false
		if get_parent() is SlotUI and not (get_parent() as SlotUI).rejection_reason(wrapping.get_model()).is_empty():
			return false
		_set_interaction_state(BlockDragDrop.State.WRAPPED)
		return true
	if not (get_parent() is Container) or get_parent() is SlotUI or BlockDragDrop._owning_block(self) != null:
		return false
	_set_interaction_state(BlockDragDrop.State.HOVERED)
	return true

func _drop_data(position: Vector2, data: Variant) -> void:
	var accepted: bool = _can_drop_data(position, data)
	_set_interaction_state(BlockDragDrop.State.NORMAL)
	if not accepted:
		return
	var source: Control = BlockDragDrop.payload_source(data)
	BlockDragDrop.commit_drag(source)
	var zone: BlockDragDrop.Zone = BlockDragDrop.classify_zone(position.x, size.x)
	if zone == BlockDragDrop.Zone.WRAP:
		_apply_wrap(source, data)
	else:
		_apply_sibling_insert(source, zone == BlockDragDrop.Zone.RIGHT, data)

func _sibling_container() -> Node:
	return get_parent() if get_parent() is Container else null

func _apply_sibling_insert(source: Control, after: bool, data: Dictionary) -> void:
	var old_parent: Node = source.get_parent()
	old_parent.remove_child(source)
	get_parent().add_child(source)
	var index: int = get_index() + (1 if after else 0)
	get_parent().move_child(source, index)
	BlockDragDrop.repair_after_removal(old_parent)
	reorder_requested.emit(BlockDragDrop.Action.INSERT_AFTER if after else BlockDragDrop.Action.INSERT_BEFORE, index, data)

func _apply_wrap(source: Control, data: Dictionary) -> void:
	var wrapping: ExpressionUI = source as ExpressionUI
	var slot: Container = wrapping.first_empty_slot()
	SlotUI.clear_from(slot)
	var destination: Node = get_parent()
	var old_parent: Node = source.get_parent()
	old_parent.remove_child(source)
	var index: int = get_index()
	destination.remove_child(self)
	destination.add_child(source)
	destination.move_child(source, index)
	slot.add_child(self)
	BlockDragDrop.repair_after_removal(old_parent)
	reorder_requested.emit(BlockDragDrop.Action.WRAP_INTO, index, data)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_set_interaction_state(BlockDragDrop.State.NORMAL)
		if _drag_source_active:
			_drag_source_active = false
			BlockDragDrop.end_drag(self)
