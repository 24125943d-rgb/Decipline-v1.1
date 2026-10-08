extends Node
## AttackAreaRenderer 与 RangeMaskRasterizer 的测试。
##
## 核心要验三件事：
## 1. 多边形来自 range.contains_point()（换 shape 不用改渲染器）：圆 / 扇 / 矩形都能描对；
## 2. 攻击范围[b]不做遮挡[/b]——场景里加一堵墙，reach 不变（这条是"正交关注点"的回归闸门）；
## 3. 光栅化是视野和攻击范围共用的那一份（空多边形透明、中间有值、往外渐隐）。

const CHARACTER_SCENE: PackedScene = preload("res://scenes/character.tscn")
const ATTACK_SCENE: PackedScene = preload("res://scenes/character_attack.tscn")
const AREA_SCENE: PackedScene = preload("res://scripts/attack_area_renderer.tscn")

var world: Node3D = null
var host: Character = null
var attack: CharacterAttack = null
var area: AttackAreaRenderer = null
var blocker: StaticBody3D = null


func before_each() -> void:
	world = Node3D.new()
	add_child(world)

	host = CHARACTER_SCENE.instantiate() as Character
	host.name = "Host"
	world.add_child(host)

	var attack_node: Node = ATTACK_SCENE.instantiate()
	attack_node.name = "Attack"
	host.add_child(attack_node)
	attack = attack_node as CharacterAttack

	var area_node: Node = AREA_SCENE.instantiate()
	area_node.name = "AttackArea"
	host.add_child(area_node)
	area = area_node as AttackAreaRenderer

	attack.attack_range = 3.0
	attack.range_shape = CharacterRange.Shape.CIRCLE
	attack.range_geometry = null


func after_each() -> void:
	if world != null and is_instance_valid(world):
		world.queue_free()
	world = null
	host = null
	attack = null
	area = null
	blocker = null


func _spawn_character(name_text: String, at: Vector3) -> Character:
	var other: Character = CHARACTER_SCENE.instantiate() as Character
	other.name = name_text
	other.position = at
	world.add_child(other)
	return other


func _spawn_blocker(at: Vector3) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Blocker"
	body.position = at
	body.collision_layer = Character.LAYER_OBSTACLE
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(2.0, 2.0, 2.0)
	shape.shape = box
	body.add_child(shape)
	world.add_child(body)
	return body


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ---------------------------------------------------------------- 几何：圆
func test_circle_polygon_matches_the_radius() -> Variant:
	area.rebuild_now()
	if area.get_point_count() != area.ray_count + 1:
		return "圆应给每个方向都落点：期望 %d 个点，实际 %d" % [area.ray_count + 1, area.get_point_count()]
	for direction: Vector3 in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		var reach: float = area.get_reach(direction)
		if absf(reach - 3.0) > 0.2:
			return "方向 %s 的 reach 应接近 3.0，实际 %.3f" % [direction, reach]
	return null


func test_radius_change_is_picked_up() -> Variant:
	attack.attack_range = 1.25
	area.rebuild_now()
	var reach: float = area.get_reach(Vector3.FORWARD)
	if absf(reach - 1.25) > 0.15:
		return "改完 attack_range 后 reach 应为 1.25，实际 %.3f" % reach
	return null


# ---------------------------------------------------------------- 几何：扇
func test_sector_keeps_only_the_cone() -> Variant:
	attack.range_shape = CharacterRange.Shape.SECTOR
	attack.fov_degrees = 90.0
	attack.attack_range = 3.0
	area.rebuild_now()
	var forward_reach: float = area.get_reach(Vector3.FORWARD)
	if absf(forward_reach - 3.0) > 0.25:
		return "扇形正前方的 reach 应接近 3.0，实际 %.3f" % forward_reach
	if area.get_point_count() > 25:
		return "90° 扇形不该有 %d 个点（整圆才是 %d）" % [area.get_point_count(), area.ray_count + 1]
	if area.get_point_count() < 8:
		return "90° 扇形点太少：%d 个（锥内的方向都该落点）" % area.get_point_count()
	return null


func test_sector_rotation_follows_the_character() -> Variant:
	host.rotation_degrees = Vector3(0.0, -90.0, 0.0)
	attack.range_shape = CharacterRange.Shape.SECTOR
	attack.fov_degrees = 60.0
	attack.attack_range = 3.0
	area.rebuild_now()
	# Godot Y=-90 turns -Z toward +X, not -X. Old nearest-vertex reach
	# incorrectly returned a radius even for directions outside the sector.
	var forward: Vector3 = -host.global_transform.basis.z
	var forward_reach: float = area.get_reach(forward)
	if absf(forward_reach - 3.0) > 0.3:
		return "Rotated forward reach must be 3, got %.3f" % forward_reach
	if area.get_reach(-forward) != 0.0:
		return "Opposite direction must be outside the sector"
	return null


# ---------------------------------------------------------------- 几何：矩形
func test_box_shape_reaches_along_its_axes() -> Variant:
	attack.range_shape = CharacterRange.Shape.BOX
	attack.box_size = Vector2(4.0, 2.0)
	area.rebuild_now()
	var along_width: float = maxf(area.get_reach(Vector3.LEFT), area.get_reach(Vector3.RIGHT))
	if absf(along_width - 2.0) > 0.3:
		return "矩形横向应到 2.0（4/2），实际 %.3f" % along_width
	var along_depth: float = area.get_reach(Vector3.FORWARD)
	if absf(along_depth - 1.0) > 0.3:
		return "矩形纵深应到 1.0（2/2），实际 %.3f" % along_depth
	return null


# ---------------------------------------------------------------- 偏移
func test_offset_moves_the_apex() -> Variant:
	attack.attack_range = 2.0
	attack.offset = Vector3(1.5, 0.0, 0.0)
	area.rebuild_now()
	var apex: Vector3 = area.get_apex_world()
	var expected: Vector3 = attack.global_position + Vector3(1.5, 0.0, 0.0)
	if _flat_distance(apex, expected) > 0.05:
		return "顶点应落在 offset 处：期望 %s，实际 %s" % [expected, apex]
	return null


# ---------------------------------------------------------------- 与遮挡解耦（关键回归闸门）
func test_obstacle_does_not_shrink_the_range() -> Variant:
	area.rebuild_now()
	var before: float = area.get_reach(Vector3.FORWARD)
	blocker = _spawn_blocker(Vector3(0.0, 0.0, -1.0))
	area.rebuild_now()
	var after: float = area.get_reach(Vector3.FORWARD)
	if absf(after - before) > 0.001:
		return "攻击范围不做遮挡：加墙前 %.3f，加墙后 %.3f（不该变）" % [before, after]
	if absf(after - 3.0) > 0.2:
		return "加墙后 reach 仍应接近 3.0，实际 %.3f" % after
	return null


# ---------------------------------------------------------------- 角色判定 / 连线
func test_characters_in_range_uses_the_attack_rule() -> Variant:
	var near: Character = _spawn_character("Near", Vector3(0.0, 0.0, -1.5))
	var far: Character = _spawn_character("Far", Vector3(0.0, 0.0, -6.0))
	area.rebuild_now()
	var found: Array[Character] = area.characters_in_range()
	if not found.has(near):
		return "距离 1.5 的角色应在范围内，实际找到 %d 个" % found.size()
	if found.has(far):
		return "距离 6.0 的角色不该在范围内"
	if found.has(host):
		return "自己不该算进范围内"
	return null


func test_target_lines_are_drawn() -> Variant:
	var near: Character = _spawn_character("Near", Vector3(0.0, 0.0, -1.5))
	area.draw_target_lines = true
	area.rebuild_now()
	var line_mesh: MeshInstance3D = area.get_node_or_null("AttackTargetLines") as MeshInstance3D
	if line_mesh == null:
		return "连线节点没建出来"
	var array_mesh: ArrayMesh = line_mesh.mesh as ArrayMesh
	if array_mesh == null or array_mesh.get_surface_count() < 1:
		return "有目标时应该画出连线（near=%s）" % near.name
	area.draw_target_lines = false
	area.rebuild_now()
	if array_mesh.get_surface_count() != 0:
		return "关掉 draw_target_lines 后不该还有连线"
	return null


# ---------------------------------------------------------------- 网格 / 显隐 / 贴花
func test_mesh_has_fill_and_border_surfaces() -> Variant:
	area.rebuild_now()
	var area_mesh: MeshInstance3D = area.get_node_or_null("AttackAreaPolygon") as MeshInstance3D
	if area_mesh == null:
		return "多边形节点没建出来"
	var array_mesh: ArrayMesh = area_mesh.mesh as ArrayMesh
	if array_mesh.get_surface_count() != 2:
		return "填充 + 边框应有 2 个 surface，实际 %d" % array_mesh.get_surface_count()
	area.draw_border = false
	area.rebuild_now()
	if array_mesh.get_surface_count() != 1:
		return "关掉边框后应只剩填充的 1 个 surface，实际 %d" % array_mesh.get_surface_count()
	return null


func test_disabled_hides_every_visual() -> Variant:
	area.rebuild_now()
	area.enabled = false
	for node_name: String in ["AttackAreaPolygon", "AttackTargetLines", "AttackAreaDecal"]:
		var visual: VisualInstance3D = area.get_node_or_null(node_name) as VisualInstance3D
		if visual == null:
			return "%s 没建出来" % node_name
		if visual.visible:
			return "enabled = false 后 %s 应该隐藏" % node_name
	area.enabled = true
	var polygon: VisualInstance3D = area.get_node("AttackAreaPolygon") as VisualInstance3D
	if not polygon.visible:
		return "enabled = true 后应重新显示"
	return null


func test_decal_mask_follows_the_polygon() -> Variant:
	area.rebuild_now()
	var decal: Decal = area.get_node_or_null("AttackAreaDecal") as Decal
	if decal == null:
		return "贴花节点没建出来"
	if decal.texture_albedo == null or decal.size.x <= 0.0:
		return "贴花应有遮罩纹理和正的盒子尺寸"
	area.decal_enabled = false
	area.rebuild_now()
	return null


# ---------------------------------------------------------------- 共享光栅化器
func test_rasterizer_empty_polygon_is_transparent() -> Variant:
	var image: Image = RangeMaskRasterizer.rasterize(
		PackedVector2Array(), 4.0, 32, 2.0, 1.0, 0.5
	)
	for y in range(0, 32, 7):
		for x in range(0, 32, 7):
			if RangeMaskRasterizer.alpha_at(image, x, y) > 0.0:
				return "空多边形应得到全透明图，( %d , %d ) 上却有值" % [x, y]
	return null


func test_rasterizer_fills_inside_and_fades_outwards() -> Variant:
	# box = 4 米、32 像素 → 每米 8 像素；这块多边形离顶点 0.5~2 米，都在半径 2 米内
	var patch: PackedVector2Array = PackedVector2Array([
		Vector2(0.5, 0.5), Vector2(2.0, 0.5), Vector2(2.0, 2.0), Vector2(0.5, 2.0)
	])
	var hard: Image = RangeMaskRasterizer.rasterize(patch, 4.0, 32, 2.0, 0.0, 0.0)
	var inside: float = RangeMaskRasterizer.alpha_at(hard, 22, 22)
	if inside < 0.99:
		return "硬边填充的内部应完全不透明，实际 %.3f" % inside
	if RangeMaskRasterizer.alpha_at(hard, 2, 2) > 0.0:
		return "多边形外应透明"
	var faded: Image = RangeMaskRasterizer.rasterize(patch, 4.0, 32, 2.0, 0.0, 0.9)
	var near_apex: float = RangeMaskRasterizer.alpha_at(faded, 21, 21)
	var far_away: float = RangeMaskRasterizer.alpha_at(faded, 30, 30)
	if not (near_apex > far_away + 0.2):
		return "开了径向渐隐后靠顶点应明显比远处实：近 %.3f，远 %.3f" % [near_apex, far_away]
	if RangeMaskRasterizer.alpha_at(faded, 2, 2) > 0.0:
		return "渐隐不该把覆盖范围扩到多边形外"
	return null


func test_rasterizer_edge_alpha_helper() -> Variant:
	if RangeMaskRasterizer.edge_alpha(5.0, 0.0, 10.0, 0.0) != 1.0:
		return "羽化宽度为 0 时应恒为 1"
	if RangeMaskRasterizer.edge_alpha(0.0, 0.0, 10.0, 2.0) > 0.001:
		return "正好落在左边界上时应为 0"
	if absf(RangeMaskRasterizer.edge_alpha(1.0, 0.0, 10.0, 2.0) - 0.5) > 0.001:
		return "距边界半个羽化宽度时应为 0.5"
	if absf(RangeMaskRasterizer.edge_alpha(5.0, 0.0, 10.0, 2.0) - 1.0) > 0.001:
		return "离边界足够远时应为 1"
	return null
