class_name AttackAreaRenderer
extends Node3D
## 用[b]多边形网格 + 贴花（Decal）[/b]可视化 [CharacterAttack] 的攻击范围。
##
## 挂在角色下面、和 `Attack` 同级即可（自动向上找同一棵树里的 [CharacterAttack]，
## 也可以用 [member attack_path] 显式指定）。
##
## [br][b]与 [VisionAreaRenderer] 的分工[/b]：视野必须投射线做遮挡，攻击范围[b]不做[/b]
## No occlusion. Uses CharacterRange.boundary_points: exact rectangle corners and
## sector endpoints, tessellated circular arcs. No coarse search and no minimum radius cutoff.
## Uses CharacterAttack.range_owner_transform, NOT the Attack component transform.
## Upright owner/renderer transforms are supported; pitch/roll are not a terrain projection.
## Boundary points are stored separately from the fan center (index zero).
## [br][b]目标连线[/b]：[member draw_target_lines] 会朝场景里每个角色画一条线，
## 绿 = 在当前范围内，红 = 在范围外（用的就是 [method CharacterAttack.contains]）。
##
## [br][b]注意[/b]：这是调试/表现组件，重算按 [member update_interval] 节流；
## 改完参数想立刻刷新用 [method request_update] 或 [method rebuild_now]。

@export_group("接线 / Wiring")
## 留空则自动向上找同一棵树里的 [CharacterAttack]。
@export var attack_path: NodePath
## 关掉就完全不重算，并把多边形 / 连线 / 贴花一起隐藏。
@export var enabled: bool = true:
	set(value):
		enabled = value
		_apply_visibility()
		if value:
			request_update()
## 重算间隔（秒）。0 = 每个物理帧都重算。
@export_range(0.0, 2.0, 0.01) var update_interval: float = 0.08

@export_group("多边形 / Polygon")
## 圆周上的采样方向数，越多边界越平滑。
@export_range(8, 512, 1) var ray_count: int = 64
## 多边形贴在角色脚底所在的地面上（否则贴在组件自身的高度上）。
@export var snap_to_ground: bool = true
## 多边形离地面的高度偏移，避免和地板 z-fighting。
@export var ground_offset: float = 0.03
@export var draw_fill: bool = true
@export var fill_color: Color = Color(1.0, 0.45, 0.35, 0.16)
@export var draw_border: bool = true
@export var border_color: Color = Color(1.0, 0.5, 0.4, 0.85)
## 边框是否穿透遮挡显示（方便一眼看出范围完全不受墙影响）。
@export var border_through_walls: bool = true

@export_group("贴花 / Decal")
@export var decal_enabled: bool = true:
	set(value):
		decal_enabled = value
		_apply_visibility()
## 贴花盒子的高度（米），盒底贴地、向上这么高。
@export var decal_box_height: float = 6.0
## 盒子相对范围直径的放大系数（留点余量给渐隐）。
@export_range(1.0, 2.0, 0.01) var decal_size_padding: float = 1.12
## 贴花遮罩纹理的分辨率。
@export_range(32, 512, 1) var decal_mask_size: int = 128
@export var decal_color: Color = Color(1.0, 0.55, 0.45, 1.0)
## 贴花对底色的替换程度（0 = 只发光不改底色）。
@export_range(0.0, 1.0, 0.01) var decal_albedo_mix: float = 0.35
@export_range(0.0, 8.0, 0.05) var decal_emission_energy: float = 0.7
## 从范围顶点往外渐隐的强度（0 = 均匀铺满）。
@export_range(0.0, 1.0, 0.01) var decal_radial_falloff: float = 0.6
## 多边形边缘的羽化像素数。
@export_range(0.0, 8.0, 0.1) var decal_edge_feather: float = 1.5
## 贴花纹理坐标方向（不同引擎 / 需求下如果发现镜像，翻一下这两个开关即可）。
@export var decal_flip_x: bool = false
@export var decal_flip_z: bool = false

@export_group("目标连线 / Target Lines")
@export var draw_target_lines: bool = true
## 目标在范围内的连线颜色。
@export var inside_line_color: Color = Color(1.0, 0.4, 0.35, 1.0)
## 目标在范围外的连线颜色。
@export var outside_line_color: Color = Color(0.55, 0.55, 0.6, 1.0)

# ------------------------------------------------------------------ 内部状态
var _attack: CharacterAttack = null
var _area_mesh: MeshInstance3D = null
var _line_mesh: MeshInstance3D = null
var _decal: Decal = null
var _mask_texture: ImageTexture = null
var _fill_material: StandardMaterial3D = null
var _border_material: StandardMaterial3D = null
var _line_material: StandardMaterial3D = null
## 最近一次的多边形顶点（本节点局部空间的 XZ，第 0 个是范围顶点）。
var _points: PackedVector2Array = PackedVector2Array()
## 范围顶点（世界空间，已含 CharacterRange.offset）。
var _origin_world: Vector3 = Vector3.ZERO
var _elapsed: float = 0.0

# ------------------------------------------------------------------ 生命周期
func _ready() -> void:
	_attack = _resolve_attack()
	if _attack == null:
		push_warning("AttackAreaRenderer: no CharacterAttack found; the attack area visual will not be generated.")
		enabled = false
		return
	_build_nodes()
	_apply_materials()
	_elapsed = maxf(update_interval, 0.0)  # 第一个物理帧就出结果


func _physics_process(delta: float) -> void:
	if not enabled or _attack == null:
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
## 让下一次物理帧立刻重算。
func request_update() -> void:
	if enabled and _attack != null:
		_elapsed = update_interval


## 立即重算一次（不等节流）：改完参数 / 移动完角色想马上看到结果时用。
func rebuild_now() -> void:
	if _attack == null:
		return
	_rebuild()


## 最近一次算出的多边形顶点数（含范围顶点；圆 / 扇正常是 ray_count + 1）。
func get_point_count() -> int:
	return _points.size()


## 范围顶点（世界空间，已含 range 的 offset）。
func get_apex_world() -> Vector3:
	return _point_world(_points[0]) if not _points.is_empty() else global_position


## 某个水平方向上多边形大概能延伸多远（世界米数）：取方向最接近的那个多边形顶点。
## [br]没被范围形状排除时应该接近 [member CharacterRange.radius]
## （与视野不同，[b]不会因为障碍物而缩短[/b]——范围本就不做遮挡）。
func get_reach(world_direction: Vector3) -> float:
	if _points.size() < 2:
		return 0.0
	var flat: Vector3 = Vector3(world_direction.x, 0.0, world_direction.z)
	if flat.length_squared() < 0.000001:
		return 0.0
	return _reach_along(flat.normalized())


## 场景里当前落在范围内 / 范围外的角色（连线用的就是攻击组件自己的判定）。
func characters_in_range() -> Array[Character]:
	var found: Array[Character] = []
	if _attack == null:
		return found
	for node: Node in _tree_nodes_in_group(Character.GROUP_CHARACTER):
		var target: Character = node as Character
		if target != null and _attack.contains(target):
			found.append(target)
	return found

# ------------------------------------------------------------------ 主流程
func _rebuild() -> void:
	_build_polygon()
	_update_area_mesh()
	_update_target_lines()
	if decal_enabled:
		_update_decal()


## 一颗射线都不投：沿圆周方向对 range.contains_point() 粗扫 + 二分求边界。
func _build_polygon() -> void:
	_points = PackedVector2Array()
	var geometry: CharacterRange = _current_geometry()
	if geometry == null:
		return
	var owner_transform: Transform3D = _attack.range_owner_transform()
	_origin_world = owner_transform * geometry.offset
	_points.append(_to_plane(_origin_world))
	for point: Vector2 in geometry.boundary_points(ray_count):
		_points.append(_to_plane(owner_transform * (geometry.offset + Vector3(point.x, 0.0, point.y))))


## 沿一个水平方向能走多远还在范围内（粗扫定位区间 + 二分收敛）。
func _reach_along(direction: Vector3) -> float:
	var geometry: CharacterRange = _current_geometry()
	if geometry == null:
		return 0.0
	var local: Vector3 = _attack.range_owner_transform().basis.inverse() * direction
	var flat: Vector2 = Vector2(local.x, local.z).rotated(-deg_to_rad(geometry.yaw_offset_degrees))
	if flat.length() == 0.0:
		return 0.0
	if geometry.shape == CharacterRange.Shape.BOX:
		var x_limit: float = INF if flat.x == 0.0 else geometry.box_size.x * 0.5 / absf(flat.x)
		var z_limit: float = INF if flat.y == 0.0 else geometry.box_size.y * 0.5 / absf(flat.y)
		return minf(x_limit, z_limit)
	if geometry.shape == CharacterRange.Shape.SECTOR and absf(rad_to_deg(flat.angle_to(Vector2.UP))) > geometry.fov_degrees * 0.5 + 0.00001:
		return 0.0
	return geometry.radius / flat.length()


func _is_inside(world_point: Vector3) -> bool:
	var geometry: CharacterRange = _current_geometry()
	return geometry != null and geometry.contains_point(world_point, _attack.global_transform)


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
			vertices.append(apex)
			vertices.append(Vector3(_points[i].x, plane_y, _points[i].y))
			vertices.append(Vector3(_points[next_index].x, plane_y, _points[next_index].y))
			for _v in 3:
				normals.append(Vector3.UP)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays(vertices, normals))
		mesh.surface_set_material(surface_count, _fill_material)
		surface_count += 1

	if draw_border:
		vertices.clear()
		normals.clear()
		for i: int in range(1, _points.size()):
			vertices.append(Vector3(_points[i].x, plane_y, _points[i].y))
			normals.append(Vector3.UP)
		vertices.append(Vector3(_points[1].x, plane_y, _points[1].y))
		normals.append(Vector3.UP)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, _arrays(vertices, normals))
		mesh.surface_set_material(surface_count, _border_material)


func _update_target_lines() -> void:
	if _line_mesh == null:
		return
	var mesh: ArrayMesh = _line_mesh.mesh as ArrayMesh
	if mesh == null:
		return
	mesh.clear_surfaces()
	if not draw_target_lines or _attack == null:
		return

	var plane_y: float = _plane_local_y()
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var apex: Vector3 = Vector3(_points[0].x, plane_y, _points[0].y) if not _points.is_empty() else Vector3.ZERO

	var drew_any: bool = false
	for node: Node in _tree_nodes_in_group(Character.GROUP_CHARACTER):
		var target: Character = node as Character
		if target == null or target == _attack.get_character() or target.hurtbox == null:
			continue
		var local_world: Vector3 = to_local(target.hurtbox.global_position)
		var color: Color = inside_line_color if _attack.contains(target) else outside_line_color
		vertices.append(apex)
		vertices.append(Vector3(local_world.x, plane_y, local_world.z))
		for _v in 2:
			normals.append(Vector3.UP)
			colors.append(color)
		drew_any = true

	if not drew_any:
		return
	var arrays: Array = _arrays(vertices, normals)
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	mesh.surface_set_material(0, _line_material)


func _update_decal() -> void:
	if _decal == null or _attack == null:
		return
	var geometry: CharacterRange = _current_geometry()
	if geometry == null:
		return
	if _points.size() < 3:
		return
	var minimum: Vector2 = _points[1]
	var maximum: Vector2 = minimum
	for i: int in range(1, _points.size()):
		minimum = minimum.min(_points[i])
		maximum = maximum.max(_points[i])
	var center: Vector2 = (minimum + maximum) * 0.5
	var span: Vector2 = maximum - minimum
	var box: float = maxf(maxf(span.x, span.y) * decal_size_padding, 0.001)
	var radius: float = box * 0.5
	_decal.position = Vector3(center.x, _floor_local_y() + decal_box_height * 0.5, center.y)
	_decal.size = Vector3(box, maxf(decal_box_height, 0.001), box)
	var polygon: PackedVector2Array = PackedVector2Array()
	for i: int in range(1, _points.size()):
		polygon.append(_points[i] - center)
	var image: Image = RangeMaskRasterizer.rasterize(
		polygon,
		box,
		decal_mask_size,
		radius,
		decal_edge_feather,
		decal_radial_falloff,
		decal_flip_x,
		decal_flip_z
	)
	if _mask_texture == null:
		_mask_texture = ImageTexture.create_from_image(image)
		_decal.texture_albedo = _mask_texture
		_decal.texture_emission = _mask_texture
	else:
		_mask_texture.update(image)

# ------------------------------------------------------------------ 内部工具
static func _arrays(vertices: PackedVector3Array, normals: PackedVector3Array) -> Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	return arrays


func _current_geometry() -> CharacterRange:
	if _attack == null or not is_instance_valid(_attack):
		return null
	return _attack.geometry()


func _tree_nodes_in_group(group: StringName) -> Array[Node]:
	var found: Array[Node] = []
	var tree: SceneTree = get_tree()
	if tree == null:
		return found
	found.assign(tree.get_nodes_in_group(group))
	return found


## 世界点 → 本节点局部 XZ（Y 丢掉，多边形和贴花都在水平面上用）。
func _to_plane(world_point: Vector3) -> Vector2:
	var local: Vector3 = to_local(world_point)
	return Vector2(local.x, local.z)


## 参考地面（角色脚底，或组件自身高度）的世界 Y。
func _ground_world_y() -> float:
	if not snap_to_ground or _attack == null:
		return _attack.global_position.y if _attack != null else global_position.y
	var character: Character = _attack.get_character()
	if character != null and is_instance_valid(character):
		return character.get_feet_position().y
	return _attack.global_position.y


## 地面所在的本地 Y（贴花盒子的下沿）。
func _floor_local_y() -> float:
	return to_local(Vector3(global_position.x, _ground_world_y(), global_position.z)).y


## 多边形所在的本地 Y（地面再抬 ground_offset）。
func _plane_local_y() -> float:
	var world_y: float = _ground_world_y() + ground_offset
	return to_local(Vector3(global_position.x, world_y, global_position.z)).y


func _point_world(point: Vector2) -> Vector3:
	return to_global(Vector3(point.x, _plane_local_y(), point.y))


func _resolve_attack() -> CharacterAttack:
	if not attack_path.is_empty():
		return get_node_or_null(attack_path) as CharacterAttack
	var node: Node = self
	while node != null:
		for child: Node in node.get_children():
			if child is CharacterAttack:
				return child as CharacterAttack
		node = node.get_parent()
	return null


func _build_nodes() -> void:
	_area_mesh = MeshInstance3D.new()
	_area_mesh.name = "AttackAreaPolygon"
	_area_mesh.mesh = ArrayMesh.new()
	_area_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_area_mesh)

	_line_mesh = MeshInstance3D.new()
	_line_mesh.name = "AttackTargetLines"
	_line_mesh.mesh = ArrayMesh.new()
	_line_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_line_mesh)

	_decal = Decal.new()
	_decal.name = "AttackAreaDecal"
	_decal.modulate = decal_color
	_decal.albedo_mix = decal_albedo_mix
	_decal.emission_energy = decal_emission_energy
	add_child(_decal)

	_apply_visibility()


## 让子节点的可见性跟随 [member enabled]。
func _apply_visibility() -> void:
	for node: Node in [_area_mesh, _line_mesh, _decal]:
		var visual: VisualInstance3D = node as VisualInstance3D
		if visual != null:
			visual.visible = enabled and (visual != _decal or decal_enabled)


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
