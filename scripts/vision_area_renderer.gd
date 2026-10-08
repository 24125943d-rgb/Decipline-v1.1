class_name VisionAreaRenderer
extends Node3D
## 用[b]射线检测生成动态多边形[/b] + [b]贴花（Decal）投影[/b]来可视化 [CharacterVision] 的视野覆盖范围。
##
## 挂在角色下面、和 `Vision` 同级即可（会自动向上找同一棵树里的 [CharacterVision]，
## 也可以用 [member vision_path] 显式指定）。
##
## [br][b]动态多边形[/b]：在视野的广角里均分 [member ray_count] 根射线，每根射线用与判定规则
## 一致的[b]多层探针[/b]（[method CharacterVision.get_probe_heights]）取“最远可达距离”，
## 被墙挡住的方向自然缩短——所以多边形是实时被障碍物[b]镂空[/b]的，和可见性判定同源。
## [br][b]贴花[/b]：同一组点被光栅化进一张 ImageTexture 交给 [Decal] 投到地面 / 物体上，
## 因此贴花同样是镂空的，不会穿墙（[member decal_radial_falloff] 负责从视野顶点往外渐隐）。
## [br][b]目标连线[/b]：[member draw_target_lines] 会朝每个候选角色画一条线，
## 绿 = 对当前角色可视，红 = 不可视（用视野组件已经算好的结果，不重复判定）。
##
## [br][b]注意[/b]：物理空间只能在物理帧里查询，所以重算走 [method _physics_process]
## 并按 [member update_interval] 节流；改完参数想立刻生效用 [method request_update]。

@export_group("接线 / Wiring")
## 留空则自动向上找同一棵树里的 [CharacterVision]。
@export var vision_path: NodePath
## 关掉就完全不重算，并把多边形 / 连线 / 贴花一起隐藏
## （试用场景用它来只显示“当前选中角色”的视野）。
@export var enabled: bool = true:
	set(value):
		enabled = value
		_apply_visibility()
		if value:
			request_update()
## 重算间隔（秒）。0 = 每个物理帧都重算。
@export_range(0.0, 2.0, 0.01) var update_interval: float = 0.08

@export_group("动态多边形 / Polygon")
## 扇形里的射线数量，越多边界越平滑。
@export_range(8, 512, 1) var ray_count: int = 64
## 多边形贴在角色脚底所在的地面上（否则贴在视野节点自身的高度上）。
@export var snap_to_ground: bool = true
## 多边形离地面的高度偏移，避免和地板 z-fighting。
@export var ground_offset: float = 0.03
@export var draw_fill: bool = true
@export var fill_color: Color = Color(0.4, 0.95, 0.55, 0.16)
@export var draw_border: bool = true
@export var border_color: Color = Color(0.45, 1.0, 0.6, 0.85)
## 边框是否穿透遮挡显示（方便一眼看出边界被墙切断）。
@export var border_through_walls: bool = true

@export_group("贴花 / Decal")
@export var decal_enabled: bool = true
## 贴花盒子的高度（米），盒底贴地、向上这么高。
@export var decal_box_height: float = 6.0
## 盒子相对视野直径的放大系数（留点余量给渐隐）。
@export_range(1.0, 2.0, 0.01) var decal_size_padding: float = 1.12
## 贴花遮罩纹理的分辨率。
@export_range(32, 512, 1) var decal_mask_size: int = 128
@export var decal_color: Color = Color(0.5, 1.0, 0.6, 1.0)
## 贴花对底色的替换程度（0 = 只发光不改底色）。
@export_range(0.0, 1.0, 0.01) var decal_albedo_mix: float = 0.35
@export_range(0.0, 8.0, 0.05) var decal_emission_energy: float = 0.7
## 从视野顶点往外渐隐的强度（0 = 均匀铺满）。
@export_range(0.0, 1.0, 0.01) var decal_radial_falloff: float = 0.6
## 多边形边缘的羽化像素数。
@export_range(0.0, 8.0, 0.1) var decal_edge_feather: float = 1.5
## 贴花纹理坐标方向（不同引擎 / 需求下如果发现镜像，翻一下这两个开关即可）。
@export var decal_flip_x: bool = false
@export var decal_flip_z: bool = false

@export_group("目标连线 / Target Lines")
@export var draw_target_lines: bool = true
@export var visible_line_color: Color = Color(0.35, 1.0, 0.5, 1.0)
@export var blocked_line_color: Color = Color(1.0, 0.35, 0.35, 1.0)

# ------------------------------------------------------------------ 内部状态
var _vision: CharacterVision = null
var _area_mesh: MeshInstance3D = null
var _line_mesh: MeshInstance3D = null
var _decal: Decal = null
var _mask_texture: ImageTexture = null
var _fill_material: StandardMaterial3D = null
var _border_material: StandardMaterial3D = null
var _line_material: StandardMaterial3D = null
## 最近一次的多边形顶点（本节点局部空间的 XZ，第 0 个是视野顶点投影）。
var _points: PackedVector2Array = PackedVector2Array()
var _elapsed: float = 0.0

# ------------------------------------------------------------------ 生命周期
func _ready() -> void:
	_vision = _resolve_vision()
	if _vision == null:
		push_warning("VisionAreaRenderer: no CharacterVision found; the vision area visual will not be generated.")
		enabled = false
		return
	_build_nodes()
	_apply_materials()
	_elapsed = maxf(update_interval, 0.0)  # 第一个物理帧就出结果


func _physics_process(delta: float) -> void:
	if not enabled or _vision == null:
		return
	if update_interval <= 0.0:
		_rebuild()
		return
	_elapsed += delta
	if _elapsed < update_interval:
		return
	_elapsed = 0.0
	_rebuild()

# ------------------------------------------------------------------ 公开 API
## 让下一次物理帧立刻重算（改完参数 / 移动完角色想马上刷新时用）。
func request_update() -> void:
	if enabled and _vision != null:
		_elapsed = update_interval


## 最近一次算出的多边形顶点数（含视野顶点，正常是 ray_count + 1）。
func get_point_count() -> int:
	return _points.size()


## 某个水平方向上多边形大概能延伸多远（世界米数）：取方向最接近的那个多边形顶点，
## 用来验证“这个方向被墙切断了”这件事（没被挡时应该接近 view_radius）。
func get_reach(world_direction: Vector3) -> float:
	if _points.size() < 2:
		return 0.0
	var flat: Vector3 = Vector3(world_direction.x, 0.0, world_direction.z)
	if flat.length_squared() < 0.000001:
		return 0.0
	flat = flat.normalized()
	var apex_world: Vector3 = _point_world(_points[0])
	var best_alignment: float = -2.0
	var best_distance: float = 0.0
	for i in range(1, _points.size()):
		var delta: Vector3 = _point_world(_points[i]) - apex_world
		var distance: float = delta.length()
		if distance < 0.0001:
			continue
		var alignment: float = flat.dot(delta / distance)
		if alignment > best_alignment:
			best_alignment = alignment
			best_distance = distance
	return best_distance

# ------------------------------------------------------------------ 主流程
func _rebuild() -> void:
	_cast_polygon()
	_update_area_mesh()
	_update_target_lines()
	if decal_enabled:
		_update_decal()


## 射线检测：每根射线取“所有探针里能到达的最远距离”。
func _cast_polygon() -> void:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return

	var origin: Vector3 = _vision.global_position
	var forward: Vector3 = _vision.get_forward()
	var flat_forward: Vector3 = Vector3(forward.x, 0.0, forward.z)
	if flat_forward.length_squared() < 0.000001:
		flat_forward = Vector3.FORWARD
	flat_forward = flat_forward.normalized()

	var heights: PackedFloat32Array = _vision.get_probe_heights()
	if heights.is_empty():
		heights.append(origin.y)
	var exclude: Array[RID] = []
	if _vision.owner_character != null and is_instance_valid(_vision.owner_character):
		exclude.append(_vision.owner_character.get_rid())

	var half_angle: float = deg_to_rad(_vision.fov_degrees * 0.5)
	var full_circle: bool = _vision.fov_degrees >= 359.999
	var radius: float = _vision.view_radius

	_points = PackedVector2Array()
	var apex: Vector2 = _to_plane(origin)
	_points.append(apex)

	var count: int = maxi(ray_count, 8)
	for i in count:
		var t: float = float(i) / float(count)
		var angle: float = TAU * t if full_circle else -half_angle + 2.0 * half_angle * t
		var direction: Vector3 = flat_forward.rotated(Vector3.UP, angle)
		var reach: float = 0.0
		for height: float in heights:
			var from: Vector3 = Vector3(origin.x, height, origin.z)
			var to: Vector3 = from + direction * radius
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
				from, to, _vision.occluder_mask, exclude
			)
			var hit: Dictionary = space.intersect_ray(query)
			var reached: float = radius
			if not hit.is_empty():
				reached = from.distance_to(hit.get("position", to))
			reach = maxf(reach, reached)
		_points.append(_to_plane(origin + direction * reach))


func _update_area_mesh() -> void:
	if _area_mesh == null:
		return
	var mesh: ArrayMesh = _area_mesh.mesh as ArrayMesh
	if mesh == null:
		return
	mesh.clear_surfaces()
	if _points.size() < 3:
		return

	var plane_y: float = _plane_local_y()
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var apex: Vector3 = Vector3(_points[0].x, plane_y, _points[0].y)

	var surface_count: int = 0
	if draw_fill:
		vertices.clear()
		normals.clear()
		for i in range(1, _points.size()):
			var next_index: int = 1 if i + 1 >= _points.size() else i + 1
			var current: Vector3 = Vector3(_points[i].x, plane_y, _points[i].y)
			var next: Vector3 = Vector3(_points[next_index].x, plane_y, _points[next_index].y)
			vertices.append(apex)
			vertices.append(current)
			vertices.append(next)
			for _v in 3:
				normals.append(Vector3.UP)
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(surface_count, _fill_material)
		surface_count += 1

	if draw_border:
		vertices.clear()
		normals.clear()
		vertices.append(apex)
		normals.append(Vector3.UP)
		for i in range(1, _points.size()):
			vertices.append(Vector3(_points[i].x, plane_y, _points[i].y))
			normals.append(Vector3.UP)
		vertices.append(apex)
		normals.append(Vector3.UP)
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arrays)
		mesh.surface_set_material(surface_count, _border_material)


func _update_target_lines() -> void:
	if _line_mesh == null:
		return
	var mesh: ArrayMesh = _line_mesh.mesh as ArrayMesh
	if mesh == null:
		return
	mesh.clear_surfaces()
	if not draw_target_lines:
		return

	var plane_y: float = _plane_local_y()
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var apex: Vector3 = Vector3(_points[0].x, plane_y, _points[0].y) if _points.size() > 0 else Vector3.ZERO

	var drew_any: bool = false
	for node: Node in get_tree().get_nodes_in_group(_vision.candidate_group):
		var target: Character = node as Character
		if target == null or target == _vision.owner_character or target.hurtbox == null:
			continue
		var world: Vector3 = target.hurtbox.global_position
		var local: Vector3 = Vector3(to_local(world).x, plane_y, to_local(world).z)
		var color: Color = (
			visible_line_color if _vision.can_see(target) else blocked_line_color
		)
		vertices.append(apex)
		vertices.append(local)
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		colors.append(color)
		colors.append(color)
		drew_any = true

	if not drew_any:
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	mesh.surface_set_material(0, _line_material)


## 把多边形光栅化成贴花遮罩（扫描线填充 + 边缘羽化 + 径向渐隐）。
func _update_decal() -> void:
	if _decal == null:
		return
	var radius: float = _vision.view_radius
	var box: float = maxf(radius * 2.0 * decal_size_padding, 0.1)
	var floor_local: float = _floor_local_y()
	_decal.position = Vector3(0.0, floor_local + decal_box_height * 0.5, 0.0)
	_decal.size = Vector3(box, decal_box_height, box)

	var image: Image = _rasterize_mask(box)
	if _mask_texture == null:
		_mask_texture = ImageTexture.create_from_image(image)
		_decal.texture_albedo = _mask_texture
		_decal.texture_emission = _mask_texture
	else:
		_mask_texture.update(image)


func _rasterize_mask(box: float) -> Image:
	# 扫描线填充 / 羽化 / 径向渐隐的实现在 RangeMaskRasterizer（和攻击范围共用一份）。
	return RangeMaskRasterizer.rasterize(
		_points,
		box,
		decal_mask_size,
		_vision.view_radius,
		decal_edge_feather,
		decal_radial_falloff,
		decal_flip_x,
		decal_flip_z
	)


# ------------------------------------------------------------------ 内部工具
static func _edge_alpha(x: float, x_left: float, x_right: float, feather: float) -> float:
	if feather <= 0.0:
		return 1.0
	var from_left: float = clampf((x - x_left) / feather, 0.0, 1.0)
	var from_right: float = clampf((x_right - x) / feather, 0.0, 1.0)
	return minf(from_left, from_right)


## 世界点 → 本节点局部 XZ（Y 丢掉，多边形和贴花都在水平面上用）。
func _to_plane(world_point: Vector3) -> Vector2:
	var local: Vector3 = to_local(world_point)
	return Vector2(local.x, local.z)


## 参考地面（角色脚底，或视野节点自身高度）的世界 Y。
func _ground_world_y() -> float:
	if not snap_to_ground:
		return _vision.global_position.y
	var character: Character = _vision.owner_character
	if character != null and is_instance_valid(character):
		return character.get_feet_position().y
	return _vision.global_position.y


## 地面所在的本地 Y（贴花盒子的下沿）。
func _floor_local_y() -> float:
	return to_local(Vector3(global_position.x, _ground_world_y(), global_position.z)).y


## 多边形所在的本地 Y（地面再抬 ground_offset，避开地板 z-fighting）。
func _plane_local_y() -> float:
	var world_y: float = _ground_world_y() + ground_offset
	return to_local(Vector3(global_position.x, world_y, global_position.z)).y


func _point_world(point: Vector2) -> Vector3:
	return to_global(Vector3(point.x, _plane_local_y(), point.y))


func _resolve_vision() -> CharacterVision:
	if not vision_path.is_empty():
		return get_node_or_null(vision_path) as CharacterVision
	var node: Node = self
	while node != null:
		for child: Node in node.get_children():
			if child is CharacterVision:
				return child as CharacterVision
		node = node.get_parent()
	return null


func _build_nodes() -> void:
	_area_mesh = MeshInstance3D.new()
	_area_mesh.name = "VisionAreaPolygon"
	_area_mesh.mesh = ArrayMesh.new()
	_area_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_area_mesh)

	_line_mesh = MeshInstance3D.new()
	_line_mesh.name = "VisionTargetLines"
	_line_mesh.mesh = ArrayMesh.new()
	_line_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_line_mesh)

	_decal = Decal.new()
	_decal.name = "VisionAreaDecal"
	_decal.modulate = decal_color
	_decal.albedo_mix = decal_albedo_mix
	_decal.emission_energy = decal_emission_energy
	add_child(_decal)

	_apply_visibility()


## 让子节点的可见性跟随 [member enabled]。
func _apply_visibility() -> void:
	if _area_mesh != null:
		_area_mesh.visible = enabled
	if _line_mesh != null:
		_line_mesh.visible = enabled
	if _decal != null:
		_decal.visible = enabled


func _apply_materials() -> void:
	_fill_material = StandardMaterial3D.new()
	_fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fill_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fill_material.albedo_color = fill_color
	_fill_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED

	_border_material = StandardMaterial3D.new()
	_border_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_border_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_border_material.albedo_color = border_color
	_border_material.no_depth_test = border_through_walls
	_border_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED

	_line_material = StandardMaterial3D.new()
	_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_line_material.vertex_color_use_as_albedo = true
	_line_material.no_depth_test = true
	_line_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
