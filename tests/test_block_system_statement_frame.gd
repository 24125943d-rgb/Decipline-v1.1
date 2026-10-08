extends Node
## 语句外框（StatementFrame）测试：真 C / E / 梳型的凹多边形。
##
## 最关键的是 test_mouth_is_hollow_and_the_spine_is_solid：用 Geometry2D.is_point_in_polygon
## 证明「凹口里是空的、竖脊和关键字带是实的、右侧开口是通的」——
## 上一版用圆角矩形 + shadow_offset 的做法在这里必然失败（那时它就是一个实心框）。

const FRAME_SCRIPT: GDScript = preload("res://BlockSystem/Logic/StatementFrame.gd")
const IF_SCENE: PackedScene = preload("res://BlockSystem/Prefabs/IfBlockUI.tscn")

var _spawned: Array[Node] = []
var _frame: StatementFrame = null
var _mouths: Array[Node] = []


func before_each() -> void:
	_spawned.clear()
	_frame = null
	_mouths.clear()


func after_each() -> void:
	for node: Node in _spawned:
		if is_instance_valid(node):
			node.free()
	_spawned.clear()


## 搭一个外框：mouth_count 条凹口 → mouth_count 个语句体行 + (mouth_count + 1) 个关键字行。
func _build(mouth_count: int) -> void:
	_frame = FRAME_SCRIPT.new() as StatementFrame
	_frame.wall_thickness = 8.0
	_frame.corner_radius = 6.0
	_frame.corner_segments = 5
	_frame.size = Vector2(240.0, 0.0)
	add_child(_frame)
	_spawned.append(_frame)

	var column: VBoxContainer = VBoxContainer.new()
	_frame.add_child(column)
	for i in range(mouth_count + 1):
		var row: Label = Label.new()
		row.custom_minimum_size = Vector2(0.0, 30.0)
		row.text = "row"
		column.add_child(row)
		if i < mouth_count:
			var body: VBoxContainer = VBoxContainer.new()
			body.custom_minimum_size = Vector2(0.0, 40.0)
			column.add_child(body)
			var filler: Control = Control.new()
			filler.custom_minimum_size = Vector2(0.0, 16.0)
			body.add_child(filler)
			_mouths.append(body)
	_frame.set_mouth_nodes(_mouths)
	await get_tree().process_frame
	await get_tree().process_frame


# ---------------------------------------------------------------- 角数 = 4N + 4
func test_c_shape_has_eight_corners() -> Variant:
	await _build(1)
	if _frame.corner_count() != 8:
		return "1 条凹口应是 C 型 8 角，实际 %d" % _frame.corner_count()
	return null


func test_e_shape_has_twelve_corners() -> Variant:
	await _build(2)
	if _frame.corner_count() != 12:
		return "2 条凹口应是 E 型 12 角，实际 %d" % _frame.corner_count()
	return null


func test_comb_shape_has_sixteen_corners() -> Variant:
	await _build(3)
	if _frame.corner_count() != 16:
		return "3 条凹口应是梳型 16 角，实际 %d" % _frame.corner_count()
	return null


func test_no_mouth_is_a_closed_ring() -> Variant:
	await _build(0)
	if _frame.corner_count() != 4:
		return "没有凹口时应是矩形 4 角，实际 %d" % _frame.corner_count()
	var polygon: PackedVector2Array = _frame.build_polygon()
	if not Geometry2D.is_point_in_polygon(_frame.size * 0.5, polygon):
		return "矩形内部应被填满"
	return null


# ---------------------------------------------------------------- 形状是不是真的凹的
func test_mouth_is_hollow_and_the_spine_is_solid() -> Variant:
	await _build(1)
	var polygon: PackedVector2Array = _frame.build_polygon()
	var origin: Vector2 = _frame.get_global_rect().position
	var mouth_center: Vector2 = _mouths[0].get_global_rect().get_center() - origin
	if Geometry2D.is_point_in_polygon(mouth_center, polygon):
		return "凹口正中不该被填上：那说明画成了实心框（上一版的错就是这个）"
	if Geometry2D.is_point_in_polygon(Vector2(_frame.size.x - 4.0, mouth_center.y), polygon):
		return "凹口右侧应该是敞开的（C 的开口）"
	if not Geometry2D.is_point_in_polygon(Vector2(_frame.wall_thickness * 0.5, _frame.size.y * 0.5), polygon):
		return "左侧竖脊应是实心的"
	if not Geometry2D.is_point_in_polygon(Vector2(_frame.size.x * 0.5, 4.0), polygon):
		return "顶部关键字带应是实心的"
	return null


func test_second_mouth_keeps_a_divider_band() -> Variant:
	await _build(2)
	var polygon: PackedVector2Array = _frame.build_polygon()
	var origin: Vector2 = _frame.get_global_rect().position
	var first_center: Vector2 = _mouths[0].get_global_rect().get_center() - origin
	var second_center: Vector2 = _mouths[1].get_global_rect().get_center() - origin
	if Geometry2D.is_point_in_polygon(Vector2(_frame.size.x - 4.0, first_center.y), polygon):
		return "第一条凹口右侧应敞开"
	if Geometry2D.is_point_in_polygon(Vector2(_frame.size.x - 4.0, second_center.y), polygon):
		return "第二条凹口右侧应敞开"
	var divider_y: float = (first_center.y + second_center.y) * 0.5
	if not Geometry2D.is_point_in_polygon(Vector2(_frame.wall_thickness * 0.5, divider_y), polygon):
		return "两条凹口之间的隔断（else 那一带）应是实心的"
	return null


# ---------------------------------------------------------------- 圆角
func test_rounded_corners_expand_into_arcs() -> Variant:
	await _build(1)
	var expected: int = 8 * _frame.corner_segments
	if _frame.build_polygon().size() != expected:
		return "圆角后顶点数应是 角数×细分 = %d，实际 %d" % [expected, _frame.build_polygon().size()]
	_frame.corner_radius = 0.0
	if _frame.build_polygon().size() != 8:
		return "半径为 0 时应回到 8 个尖角，实际 %d" % _frame.build_polygon().size()
	return null


# ---------------------------------------------------------------- 真预制体端到端
func test_if_else_prefab_gets_two_mouths() -> Variant:
	# 直接手搭一条 IF/ELSE（不依赖 mock 的字段命名）：条件非空 + else 分支非空
	var branch: AST_Statement = AST_Statement.new()
	branch.condition = AST_Variable.new()
	branch.else_body.append(AST_Command.new())
	var ui: Node = IF_SCENE.instantiate()
	ui.size = Vector2(260.0, 0.0)
	add_child(ui)
	_spawned.append(ui)
	ui.call("bind_statement", branch)
	await get_tree().process_frame
	await get_tree().process_frame
	var frame: StatementFrame = ui.get("frame") as StatementFrame
	if frame == null:
		return "预制体上的 frame 没接上（node_paths / 属性名对不上？）"
	if frame.corner_count() != 12:
		return "带 else 的 if 应是 E 型 12 角，实际 %d" % frame.corner_count()
	if frame.get_fill_color().a <= 0.0:
		return "外框底色应该已经被调色板刷过（alpha > 0）"
	return null
