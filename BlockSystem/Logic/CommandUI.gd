class_name CommandUI
extends PanelContainer
## 单行指令积木的挂载脚本（AST_Command 的视图）。
##
## 与 ExpressionUI / StatementUI 遵守同一套「积木 UI 协议」：
##     set_palette(palette: BlockPalette) -> void
##     bind_model(model: AST_Node) -> void
## 同步引擎（Logic/BlockSyncEngine.gd）只认这两个方法，不认具体类，
## 所以新增一种积木不需要改引擎。
##
## 本脚本同样不生成任何节点：节点树由 Prefabs/CommandBlockUI.tscn 提供。
## 硬约束：不得出现任何颜色或尺寸字面量。

## 调色板资源（Art 侧提供）。
@export var palette: BlockPalette

## 指令名标签（如 move_forward）。
@export var opcode_label: Label

## 实参标签（如 3, fast, true）。
@export var args_label: Label

## 只读数据源。
var _model: AST_Command = null

## 本次拖拽是否由本节点发起（拖拽被取消时用来恢复隐藏的源节点）。
var _drag_source_active: bool = false


func _ready() -> void:
	apply_palette()


## 注入数据并刷新视图。
func bind_model(model: AST_Node) -> void:
	_model = model as AST_Command
	if _model == null:
		return
	if opcode_label != null:
		opcode_label.text = _model.opcode
	if args_label != null:
		args_label.text = format_args(_model.args)
	apply_palette()


## 运行时替换调色板后立即重新着色。
func set_palette(new_palette: BlockPalette) -> void:
	palette = new_palette
	apply_palette()


## 只读当前模型（同步引擎编译 UI 时要取回原子数据）。
func get_model() -> AST_Command:
	return _model


## 把实参拼成可读文本（纯展示，不参与编译）。
func format_args(args: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for value: Variant in args:
		parts.append(str(value))
	return ", ".join(parts)


## 用调色板着色：几何取自 Theme，只覆盖 bg_color。
func apply_palette() -> void:
	if palette == null:
		push_error("CommandUI (%s): 未挂载 BlockPalette，颜色无法注入。" % name)
		return
	# 必须显式传 theme type：单参调用不会查 theme_type_variation（README §7.1）
	var base: StyleBox = get_theme_stylebox(&"panel", get_theme_type_variation())
	if not base is StyleBoxFlat:
		push_error("CommandUI (%s): theme type '%s' 没有 StyleBoxFlat('panel')。" % [name, get_theme_type_variation()])
		return
	var styled: StyleBoxFlat = (base as StyleBoxFlat).duplicate() as StyleBoxFlat
	styled.bg_color = palette.get_background_color(AST_BlockSchema.CATEGORY_COMMAND)
	add_theme_stylebox_override(&"panel", styled)
	var problems: PackedStringArray = BlockStyleSpec.validate(styled)
	if not problems.is_empty():
		push_warning("CommandUI (%s): StyleBoxFlat 不符合规范 -> %s" % [name, ", ".join(problems)])


# ------------------------------------------------------------------ 拖放

## 拖拽数据生成：载荷就是 AST 数据本身。
func _get_drag_data(_at_position: Vector2) -> Variant:
	if _model == null:
		return null
	if BlockDragDrop.begin_drag(self) == null:
		return null
	_drag_source_active = true
	return BlockDragDrop.make_payload(_model, self)


## 指令块自己不做垂直吸附，而是把落点**转发给外层语句体**，
## 由语句体统一计算插入位。这样嵌套拖拽不依赖「引擎是否会把拖放事件回溯到父节点」。
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var statement: StatementUI = enclosing_statement()
	if statement == null:
		return false
	if not BlockDragDrop.can_drop_into(BlockDragDrop.payload_source(data), self):
		return false
	return statement.can_drop_block(data)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var statement: StatementUI = enclosing_statement()
	if statement != null:
		statement.drop_block(data)


func _notification(what: int) -> void:
	if what != NOTIFICATION_DRAG_END:
		return
	if _drag_source_active:
		_drag_source_active = false
		BlockDragDrop.end_drag(self)


## 外层语句体（指令块总是挂在某个语句体里）。
func enclosing_statement() -> StatementUI:
	var node: Node = get_parent()
	while node != null:
		if node is StatementUI:
			return node
		node = node.get_parent()
	return null
