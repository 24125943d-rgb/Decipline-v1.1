class_name StatementFrame
extends MarginContainer
## 控制流积木的外框：按[b]运行时布局[/b]现场生成一条凹多边形，所以能画真正的 C / E / 梳型。
##
## [br][b]形状规则（通用，臂数不限）[/b]：关键字行（Header、else 标签…）= 实心带；
## 语句体容器 = 凹口（透明，给子积木让位）。凹口数 N 决定形状：
## N=1 → C 型，N=2 → E 型，N=3 → 梳型…… 每条凹口贡献 4 个角（角数 = 4N + 4）。
## 因为凹口的位置是[b]子节点 rect 的函数[/b]，静态的 StyleBoxFlat 只能画矩形，做不到这件事。
##
## [br]几何值（墙厚 / 圆角半径 / 圆角细分 / 内边距）在 Prefab 上配置（Prefabs 属美术侧数据），
## 本文件的默认值只是"没配也不会崩"的兜底。[b]颜色一律由外部注入[/b]（见 [method set_colors]）——
## 本文件不得出现数值颜色字面量（BlockSystem README 规则 3）。

## 竖脊宽度取「关键行」的高度（关掉就用下面那个固定值）。
@export var spine_matches_row: bool = true
## 竖脊宽度的兜底值（spine_matches_row 关掉时用）。
@export var wall_thickness: float = 8.0
## 底边（下唇）厚度相对竖脊宽度的比例：1.0 = 与文本行同厚。
@export_range(0.0, 2.0, 0.05) var bottom_lip_ratio: float = 1.0
## 凹口最小高度相对竖脊宽度的比例（0 = 完全贴合内容）。
@export_range(0.0, 2.0, 0.05) var mouth_min_ratio: float = 0.5
## 圆角半径（像素）。0 = 硬直角。
@export var corner_radius: float = 6.0
## 每个圆角用几段近似弧线（越大越圆）。用了圆角后顶点数 = 角数 × 本值。
@export_range(1, 12, 1) var corner_segments: int = 5
## 内容与框内壁的间隙（0 = 内壁与积木严丝合缝）。
@export var content_padding: float = 0.0
## 轮廓线粗细相对墙厚的比例。
@export_range(0.0, 0.8, 0.01) var outline_ratio: float = 0.28

## 要挖成凹口的"行"节点（语句体容器）。包着它们的缩进容器会被自动并进来。
var _mouth_nodes: Array[Node] = []
var _fill_color: Color = Color.WHITE
var _outline_color: Color = Color.WHITE


func _ready() -> void:
	_apply_own_margins()
	resized.connect(queue_redraw)


func _notification(what: int) -> void:
	# 内容重排（子积木增删、尺寸变化）之后：脊宽要吃「行高」，形状也要重算。
	# 用 deferred 避免在排序过程中改边距引起递归重排。
	if what == NOTIFICATION_SORT_CHILDREN:
		call_deferred(&"_refresh_after_sort")


func _refresh_after_sort() -> void:
	_apply_own_margins()
	queue_redraw()


# ------------------------------------------------------------------ 公开 API
## 指定哪些节点算"凹口"。传语句体容器即可（body / else / …，数量不限 → 梳型）。
func set_mouth_nodes(nodes: Array[Node]) -> void:
	_mouth_nodes = nodes
	queue_redraw()


## 注入颜色（来自 Art 的调色板；本组件自己不决定颜色）。
func set_colors(fill: Color, outline: Color) -> void:
	_fill_color = fill
	_outline_color = outline
	queue_redraw()


func get_fill_color() -> Color:
	return _fill_color


## 手动要求重画（数据变了但布局没动静时用，例如 else 分支刚显示出来）。
func refresh() -> void:
	queue_redraw()


## 当前形状的角度数（不含圆角细分）：无凹口 = 4，N 个凹口 = 4N + 4。
func corner_count() -> int:
	return _corners().size()


## 现场生成的多边形（本组件局部坐标；圆角已按角数 × corner_segments 展开）。
func build_polygon() -> PackedVector2Array:
	return _rounded(_corners())


# ------------------------------------------------------------------ 形状
## 未加圆角前的"角"序列：外接矩形 + 每条凹口 4 个角。
func _corners() -> PackedVector2Array:
	var width: float = size.x
	var height: float = size.y
	if width <= 1.0 or height <= 1.0:
		return PackedVector2Array()
	var spine: float = _spine_width()
	var inner_x: float = minf(spine + content_padding, width * 0.5)
	var corners: PackedVector2Array = PackedVector2Array()
	# 最后一条凹口的底：决定底边画在哪（被父容器拉伸出来的多余高度一律不画）
	var last_bottom: float = 0.0
	corners.append(Vector2(0.0, 0.0))
	corners.append(Vector2(width, 0.0))
	for mouth: Rect2 in _mouth_rects():
		var top: float = clampf(mouth.position.y, 0.0, height)
		var bottom: float = clampf(mouth.position.y + mouth.size.y, 0.0, height)
		# 空语句体也要看得见凹口；有内容时按内容高度贴合（mouth_min_ratio 调小即可更紧）
		var minimum: float = spine * mouth_min_ratio
		if bottom - top < minimum:
			var center: float = (top + bottom) * 0.5
			top = clampf(center - minimum * 0.5, 0.0, height)
			bottom = clampf(center + minimum * 0.5, 0.0, height)
		if bottom - top <= 0.5:
			continue
		last_bottom = bottom
		corners.append(Vector2(width, top))
		corners.append(Vector2(inner_x, top))
		corners.append(Vector2(inner_x, bottom))
		corners.append(Vector2(width, bottom))
	# 底边固定厚度（脊宽 × bottom_lip_ratio）：不随被拉伸的框高乱长
	var bottom_y: float = height
	if last_bottom > 0.0:
		bottom_y = clampf(last_bottom + spine * bottom_lip_ratio, 0.0, height)
	corners.append(Vector2(width, bottom_y))
	corners.append(Vector2(0.0, bottom_y))
	return corners


## 把每个角用二次贝塞尔近似成弧线（凸角倒角、凹角内圆角都由同一条公式给出）。
func _rounded(corners: PackedVector2Array) -> PackedVector2Array:
	var count: int = corners.size()
	if count < 3:
		return PackedVector2Array()
	if corner_radius <= 0.01 or corner_segments < 2:
		return corners
	var rounded: PackedVector2Array = PackedVector2Array()
	for i in count:
		var previous: Vector2 = corners[(i - 1 + count) % count]
		var current: Vector2 = corners[i]
		var following: Vector2 = corners[(i + 1) % count]
		var to_previous: Vector2 = previous - current
		var to_following: Vector2 = following - current
		var length_previous: float = to_previous.length()
		var length_following: float = to_following.length()
		if length_previous < 0.001 or length_following < 0.001:
			rounded.append(current)
			continue
		var radius: float = minf(corner_radius, minf(length_previous, length_following) * 0.5)
		if radius <= 0.01:
			rounded.append(current)
			continue
		var arc_start: Vector2 = current + to_previous / length_previous * radius
		var arc_end: Vector2 = current + to_following / length_following * radius
		for step in corner_segments:
			var t: float = float(step) / float(corner_segments - 1)
			rounded.append(arc_start.lerp(current, t).lerp(current.lerp(arc_end, t), t))
	return rounded


## 每条凹口在本组件局部坐标里的 rect（由子节点实际 rect 推出来，所以会自动跟着布局变）。
func _mouth_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var column: Control = _content_column()
	if column == null or not column.is_visible_in_tree():
		return rects
	var origin: Vector2 = get_global_rect().position
	for node: Node in _mouth_nodes:
		var control: Control = node as Control
		if control == null or not is_instance_valid(control) or not control.is_visible_in_tree():
			continue
		var rect: Rect2 = control.get_global_rect()
		# 往上并到内容列之前的所有包装容器（缩进用的 MarginContainer 等）
		var walker: Node = control.get_parent()
		while walker != null and walker != column:
			var wrapper: Control = walker as Control
			if wrapper != null:
				rect = rect.merge(wrapper.get_global_rect())
			walker = walker.get_parent()
		if walker != column:
			continue  # 不属于本框的内容列，忽略
		rects.append(Rect2(rect.position - origin, rect.size))
	rects.sort_custom(_sorts_by_top)
	return rects


static func _sorts_by_top(a: Rect2, b: Rect2) -> bool:
	return a.position.y < b.position.y


func _content_column() -> Control:
	# _ready 阶段可能还没有内容列，别越界
	if get_child_count() == 0:
		return null
	return get_child(0) as Control


# ------------------------------------------------------------------ 绘制
func _draw() -> void:
	var polygon: PackedVector2Array = build_polygon()
	if polygon.size() < 3:
		return
	# 自己三角化再逐块填充：凹多边形（E / 梳型）直接交给引擎的 canvas 填充会报
	# "triangulation failed"，而 Geometry2D 的耳切法能稳定处理；相邻三角形共享顶点、
	# 互不重叠，所以半透明底色不会在内部叠色。
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(polygon)
	var cursor: int = 0
	while cursor + 2 < indices.size():
		draw_colored_polygon(
			PackedVector2Array([
				polygon[indices[cursor]], polygon[indices[cursor + 1]], polygon[indices[cursor + 2]]
			]),
			_fill_color
		)
		cursor += 3
	if outline_ratio > 0.0:
		var closed: PackedVector2Array = polygon.duplicate()
		closed.append(polygon[0])
		draw_polyline(closed, _outline_color, maxf(_spine_width() * outline_ratio, 1.0), true)


## 自身给内容让位：左边留竖脊，其余留内边距，底部留出下唇。
func _apply_own_margins() -> void:
	var spine: float = _spine_width()
	_set_margin(&"margin_left", spine + content_padding)
	_set_margin(&"margin_top", content_padding)
	_set_margin(&"margin_right", content_padding)
	_set_margin(&"margin_bottom", spine * bottom_lip_ratio)


## 只在值真的变了才写：避免「改边距 → 重排 → 再改边距」的死循环。
func _set_margin(name_text: StringName, value: float) -> void:
	var rounded: int = int(round(value))
	if get_theme_constant(name_text) == rounded:
		return
	add_theme_constant_override(name_text, rounded)


## 竖脊宽度：默认取第一条可见行（关键字行）的高度 —— 于是脊、底边与文本同厚。
func _spine_width() -> float:
	var base: float = wall_thickness
	if spine_matches_row:
		base = maxf(base, _row_height())
	return maxf(base, 1.0)


func _row_height() -> float:
	var column: Control = _content_column()
	if column == null:
		return 0.0
	for child: Node in column.get_children():
		var row: Control = child as Control
		if row != null and row.is_visible_in_tree():
			return row.get_rect().size.y
	return 0.0
