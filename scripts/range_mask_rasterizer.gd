class_name RangeMaskRasterizer
extends RefCounted
## 把水平面上的一个多边形光栅化成 [Decal] 用的遮罩贴图（alpha = 覆盖强度）。
##
## [br]视野范围和攻击范围共用这一份实现：扫描线填充 + 边缘羽化 + 从顶点往外径向渐隐。
## 两边的"几何"各自不同（视野扇形要做遮挡射线、攻击范围不做），但"把顶点画成贴花"这件事
## 只应该有一份代码，所以抽成静态工具。

## 光栅化一张 [param size_in]×[param size_in] 的 RGBA8 遮罩。
## [br][param points] 是本节点局部 XZ 平面上的多边形顶点（第 0 个是顶点 / 发射点）。
## [br][param box] 是贴花盒子在世界里的边长（米），决定 像素↔米 的比例。
## [br][param radius] 用于径向渐隐的参考半径。
## [br]多边形少于 3 个点时返回全透明图（不报错，调用方照常更新贴图）。
static func rasterize(
	points: PackedVector2Array,
	box: float,
	size_in: int,
	radius: float,
	feather: float,
	radial_falloff: float,
	flip_x: bool = false,
	flip_z: bool = false
) -> Image:
	var size: int = clampi(size_in, 32, 512)
	var data: PackedByteArray = PackedByteArray()
	data.resize(size * size * 4)  # 全 0 = 透明
	if points.size() < 3 or box <= 0.0:
		return Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data)

	var half: float = box * 0.5
	var to_pixel: float = float(size) / box
	var signed_x: float = -1.0 if flip_x else 1.0
	var signed_y: float = -1.0 if flip_z else 1.0

	var polygon: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in points:
		polygon.append(
			Vector2((point.x * signed_x + half) * to_pixel, (point.y * signed_y + half) * to_pixel)
		)
	var apex: Vector2 = polygon[0]
	var radius_px: float = maxf(radius * to_pixel, 0.001)
	var edge_feather: float = maxf(feather, 0.0)

	for row in size:
		var scan_y: float = float(row) + 0.5
		var crossings: PackedFloat32Array = PackedFloat32Array()
		for i in polygon.size():
			var a: Vector2 = polygon[i]
			var b: Vector2 = polygon[(i + 1) % polygon.size()]
			if (a.y <= scan_y) == (b.y <= scan_y):
				continue
			crossings.append(a.x + (scan_y - a.y) / (b.y - a.y) * (b.x - a.x))
		if crossings.size() < 2:
			continue
		crossings.sort()
		var pair: int = 0
		while pair + 1 < crossings.size():
			var x_left: float = maxf(crossings[pair], 0.0)
			var x_right: float = minf(crossings[pair + 1], float(size))
			pair += 2
			if x_right <= x_left:
				continue
			var start: int = int(floor(x_left))
			var end: int = int(ceil(x_right))
			for column in range(start, end):
				if column < 0 or column >= size:
					continue
				var x_center: float = float(column) + 0.5
				if x_center < x_left or x_center > x_right:
					continue
				var alpha: float = edge_alpha(x_center, x_left, x_right, edge_feather)
				if radial_falloff > 0.0:
					var dx: float = x_center - apex.x
					var dy: float = scan_y - apex.y
					var normalized: float = clampf(sqrt(dx * dx + dy * dy) / radius_px, 0.0, 1.0)
					alpha *= 1.0 - radial_falloff * normalized * normalized
				if alpha <= 0.003:
					continue
				var index: int = (row * size + column) * 4
				data[index] = 255
				data[index + 1] = 255
				data[index + 2] = 255
				data[index + 3] = int(clampf(alpha, 0.0, 1.0) * 255.0)
	return Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data)


## 边缘羽化权重：越靠多边形边界越小，羽化宽度为 0 时恒为 1。
static func edge_alpha(x: float, x_left: float, x_right: float, feather: float) -> float:
	if feather <= 0.0:
		return 1.0
	var from_left: float = clampf((x - x_left) / feather, 0.0, 1.0)
	var from_right: float = clampf((x_right - x) / feather, 0.0, 1.0)
	return minf(from_left, from_right)


## 某个像素中心在图里的 alpha（0 = 透明）。给测试和调试用，不参与渲染。
static func alpha_at(image: Image, x: int, y: int) -> float:
	if image == null or x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		return 0.0
	return image.get_pixel(x, y).a
