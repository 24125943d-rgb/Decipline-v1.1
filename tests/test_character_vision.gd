extends Node
## CharacterVision（角色视野）的单元测试。
##
## 约定同测试运行器：extends Node，方法名以 test_ 开头，返回 null = 通过、字符串 = 失败原因。
## 视野的遮挡判定依赖物理空间，所以每个用例都要等几个物理帧。

const CharacterScene: PackedScene = preload("res://scenes/character.tscn")
const Vision = preload("res://scripts/character_vision.gd")

# 所有角色都站在地面上（脚底 y = 0），原点在身体中心
const FEET_Y: float = 0.9

var _failures: PackedStringArray = PackedStringArray()
var _spawned: Array[Node] = []

func before_each() -> void:
	_failures.clear()


func after_each() -> void:
	# 用例里造的角色必须全部清掉：视野是按全局 character 组扫描的，
	# 漏掉一个就会污染后面的用例。
	for node: Node in _spawned:
		if is_instance_valid(node):
			node.free()
	_spawned.clear()

# ------------------------------------------------------------------ 用例
func test_sector_math() -> Variant:
	var observer: Character = _make_character(Vector3(0, FEET_Y, 0))
	var vision: Vision = _make_vision(observer)
	vision.view_radius = 10.0  # 下面按 10 米半径验证

	_check(vision.is_in_sector(Vector3(0, FEET_Y, -5)), "正前方在扇形内")
	_check(not vision.is_in_sector(Vector3(0, FEET_Y, 5)), "正后方不在扇形内")
	_check(vision.is_in_sector(Vector3(4, FEET_Y, -4.8)), "偏 40° 在扇形内")
	_check(not vision.is_in_sector(Vector3(5, FEET_Y, -4)), "偏 51° 超出 90° 广角")
	_check(not vision.is_in_sector(Vector3(0, FEET_Y, -10.5)), "超出半径不在扇形内")
	_check(vision.is_in_sector(Vector3(0, 50, -3)), "正上方 50 米仍在扇形内（无视高度）")
	_check(vision.is_in_sector(Vector3(0, -50, -3)), "正下方 50 米也仍在扇形内")

	vision.fov_degrees = 360.0
	_check(vision.is_in_sector(Vector3(0, FEET_Y, 5)), "360° 时背后也算")
	vision.fov_degrees = 90.0

	vision.yaw_offset_degrees = 180.0
	_check(vision.is_in_sector(Vector3(0, FEET_Y, 5)), "yaw 偏移 180° 后背后在扇形内")
	_check(not vision.is_in_sector(Vector3(0, FEET_Y, -5)), "yaw 偏移 180° 后正前方不在扇形内")

	observer.free()
	return _verdict("test_sector_math")


func test_sees_clear_target() -> Variant:
	var observer: Character = _make_character(Vector3(0, FEET_Y, 0))
	var vision: Vision = _make_vision(observer)
	var front: Character = _make_character(Vector3(0, FEET_Y, -6))
	var behind: Character = _make_character(Vector3(0, FEET_Y, 8))

	var entered: Array = []
	var exited: Array = []
	vision.target_entered_view.connect(func(target: Character) -> void: entered.append(target))
	vision.target_exited_view.connect(func(target: Character) -> void: exited.append(target))
	await _settle()

	_check(vision.can_see(front), "正前方的角色可视")
	_check(not vision.can_see(behind), "背后的角色不可视")
	_check_eq(vision.visible_characters.size(), 1, "可见列表里只有正前方那个")
	_check(entered.has(front), "target_entered_view 信号")

	front.global_position = Vector3(0, FEET_Y, 8)
	await _settle()
	_check(not vision.can_see(front), "走到背后后不可视")
	_check(exited.has(front), "target_exited_view 信号")

	front.global_position = Vector3(0, FEET_Y, -6)
	await _settle()
	_check(vision.can_see(front), "走回正面后重新可视")
	_check_eq(vision.visible_characters.size(), 1, "可见列表没有重复")

	observer.free()
	return _verdict("test_sees_clear_target")


func test_wall_blocks_crate_does_not() -> Variant:
	var observer: Character = _make_character(Vector3(0, FEET_Y, 0))
	var vision: Vision = _make_vision(observer)
	var target: Character = _make_character(Vector3(0, FEET_Y, -6))

	var wall: StaticBody3D = _make_obstacle(Vector3(0, 1.5, -3), Vector3(4, 3, 0.4))
	await _settle()
	_check(not vision.can_see(target), "3 米高的墙挡住 1.8 米的角色")

	vision.use_occlusion = false
	await _settle()
	_check(vision.can_see(target), "关掉遮挡判定后能看穿墙")
	vision.use_occlusion = true
	wall.free()

	var crate: StaticBody3D = _make_obstacle(Vector3(0, 0.3, -3), Vector3(4, 0.6, 0.4))
	await _settle()
	_check(vision.can_see(target), "0.6 米的矮箱子挡不住（从上面看过去）")
	crate.free()

	# 障碍物不在遮挡层上就不算遮挡
	var other_layer: StaticBody3D = _make_obstacle(
		Vector3(0, 1.5, -3), Vector3(4, 3, 0.4), Character.LAYER_CHARACTER
	)
	await _settle()
	_check(vision.can_see(target), "不在 occluder_mask 里的物体不算遮挡")
	other_layer.free()

	observer.free()
	return _verdict("test_wall_blocks_crate_does_not")


func test_occlusion_follows_character_height() -> Variant:
	var observer: Character = _make_character(Vector3(0, FEET_Y, 0), 1.8)
	var vision: Vision = _make_vision(observer)
	var target: Character = _make_character(Vector3(0, FEET_Y, -6))
	var wall: StaticBody3D = _make_obstacle(Vector3(0, 0.65, -3), Vector3(4, 1.3, 0.4))
	await _settle()

	_check(vision.can_see(target), "1.3 米的墙矮于 1.8 米的角色 → 不遮挡")

	# 蹲到 1.2 米：同一个障碍物就挡得住了
	observer.height = 1.2
	observer.global_position = Vector3(0, 0.6, 0)
	await _settle()
	_check(not vision.can_see(target), "角色蹲到 1.2 米后，1.3 米的墙挡住视线")

	# 和角色一样高不算“超过”
	observer.height = 1.3
	observer.global_position = Vector3(0, 0.65, 0)
	await _settle()
	_check(vision.can_see(target), "和角色一样高（1.3 = 1.3）不算超过，不遮挡")

	# 站直回 1.8 米又能看见了
	observer.height = 1.8
	observer.global_position = Vector3(0, FEET_Y, 0)
	await _settle()
	_check(vision.can_see(target), "站回 1.8 米后又看得见")

	wall.free()
	observer.free()
	return _verdict("test_occlusion_follows_character_height")


func test_height_does_not_limit_range() -> Variant:
	var observer: Character = _make_character(Vector3(0, FEET_Y, 0))
	var vision: Vision = _make_vision(observer)
	var flyer: Character = _make_character(Vector3(0, 20, -6))
	var buried: Character = _make_character(Vector3(0, -40, -6))
	await _settle()

	_check(vision.can_see(flyer), "20 米高空的目标可视（生效范围无视高度）")
	_check(vision.can_see(buried), "地下 40 米的目标也可视")
	_check_eq(vision.visible_characters.size(), 2, "两个都在可见列表里")

	observer.free()
	return _verdict("test_height_does_not_limit_range")


func test_partial_occlusion_counts_as_visible() -> Variant:
	var observer: Character = _make_character(Vector3(0, FEET_Y, 0))
	var vision: Vision = _make_vision(observer)
	var target: Character = _make_character(Vector3(0, FEET_Y, -6))
	# 细柱子只遮住受击判定（半径 0.5 的球）中间一条缝
	var post: StaticBody3D = _make_obstacle(Vector3(0, 1.5, -3), Vector3(0.2, 3, 0.2))
	await _settle()

	_check(vision.can_see(target), "只挡住中间一条缝 → 仍有部分可见即算可视")

	vision.require_center_visible = true
	await _settle()
	_check(not vision.can_see(target), "收紧成“中心必须可见”后不可视")
	vision.require_center_visible = false

	vision.samples_per_axis = 1
	await _settle()
	_check(not vision.can_see(target), "只采中心一个点时不可视")
	vision.samples_per_axis = 3
	await _settle()
	_check(vision.can_see(target), "恢复九宫格采样后又可视")

	post.free()
	observer.free()
	return _verdict("test_partial_occlusion_counts_as_visible")


func test_transparent_group_does_not_block() -> Variant:
	var observer: Character = _make_character(Vector3(0, FEET_Y, 0))
	var vision: Vision = _make_vision(observer)
	var target: Character = _make_character(Vector3(0, FEET_Y, -6))
	var glass: StaticBody3D = _make_obstacle(
		Vector3(0, 1.5, -3), Vector3(4, 3, 0.4), Character.LAYER_OBSTACLE, &"vision_transparent"
	)
	await _settle()
	_check(vision.can_see(target), "vision_transparent 组里的物体不遮挡视线")

	glass.remove_from_group(&"vision_transparent")
	await _settle()
	_check(not vision.can_see(target), "移出该组后恢复遮挡")

	glass.free()
	observer.free()
	return _verdict("test_transparent_group_does_not_block")


func test_radius_and_fov_are_live() -> Variant:
	var observer: Character = _make_character(Vector3(0, FEET_Y, 0))
	var vision: Vision = _make_vision(observer)
	var straight: Character = _make_character(Vector3(0, FEET_Y, -6))
	var diagonal: Character = _make_character(Vector3(3.5, FEET_Y, -4))
	await _settle()

	_check(vision.can_see(straight), "6 米外正前方可视")
	_check(vision.can_see(diagonal), "偏 41° 的目标在 90° 广角内")

	vision.view_radius = 3.0
	await _settle()
	_check(not vision.can_see(straight), "半径缩到 3 米后 6 米外的目标不可视")
	vision.view_radius = 12.0
	await _settle()
	_check(vision.can_see(straight), "半径恢复后又可视")

	vision.fov_degrees = 10.0
	await _settle()
	_check(vision.can_see(straight), "广角缩到 10° 后正前方（0°）仍可视")
	_check(not vision.can_see(diagonal), "广角缩到 10° 后 41° 的目标不可视")

	observer.free()
	return _verdict("test_radius_and_fov_are_live")


func test_ignore_downed() -> Variant:
	var observer: Character = _make_character(Vector3(0, FEET_Y, 0))
	var vision: Vision = _make_vision(observer)
	var target: Character = _make_character(Vector3(0, FEET_Y, -6))
	await _settle()
	_check(vision.can_see(target), "正常状态下可视")

	target.take_damage(999)
	await _settle()
	_check(vision.can_see(target), "默认倒地角色仍算可视")

	vision.ignore_downed = true
	await _settle()
	_check(not vision.can_see(target), "开启 ignore_downed 后看不见倒地角色")
	_check_eq(vision.visible_characters.size(), 0, "可见列表被清空")

	observer.free()
	return _verdict("test_ignore_downed")


func test_body_height_syncs_collision() -> Variant:
	var observer: Character = _make_character(Vector3(0, FEET_Y, 0), 1.8)
	_check_eq(snappedf((observer.body_shape.shape as CapsuleShape3D).height, 0.001), 1.8, "初始胶囊高度")
	_check_eq(snappedf(observer.get_head_position().y - observer.get_feet_position().y, 0.001), 1.8, "头顶到脚底 = height")

	observer.height = 1.0
	_check_eq(snappedf((observer.body_shape.shape as CapsuleShape3D).height, 0.001), 1.0, "改 height 后身体碰撞体跟着变")
	_check_eq(snappedf(observer.get_head_position().y - observer.get_feet_position().y, 0.001), 1.0, "头顶到脚底跟着变")

	# 形状资源是每个角色各自复制的，互不干扰
	var other: Character = _make_character(Vector3(6, FEET_Y, 0), 1.8)
	_check_eq(snappedf((other.body_shape.shape as CapsuleShape3D).height, 0.001), 1.8, "另一个角色不受影响")
	_check(observer.body_shape.shape != other.body_shape.shape, "两个角色用的是各自的形状资源")

	observer.free()
	return _verdict("test_body_height_syncs_collision")


func test_vision_without_character() -> Variant:
	var holder: Node3D = Node3D.new()
	add_child(holder)
	holder.global_position = Vector3(0, FEET_Y, 0)
	var vision: Vision = Vision.new()
	vision.update_interval = 0.0
	holder.add_child(vision)
	_spawned.append(holder)
	_spawned.append(vision)
	var target: Character = _make_character(Vector3(0, FEET_Y, -6))
	await _settle()

	_check(vision.owner_character == null, "找不到所属角色")
	_check(vision.can_see(target), "没有角色时依然能用（探针退回本节点的高度）")

	holder.free()
	return _verdict("test_vision_without_character")

# ------------------------------------------------------------------ 工具
func _settle(frames: int = 4) -> void:
	for i in frames:
		await get_tree().physics_frame


func _make_character(at: Vector3, height: float = 1.8) -> Character:
	var character: Character = CharacterScene.instantiate() as Character
	add_child(character)
	character.global_position = at
	character.height = height
	_spawned.append(character)
	return character


func _make_vision(observer: Character) -> Vision:
	var vision: Vision = Vision.new()
	observer.add_child(vision)
	vision.update_interval = 0.0  # 每个物理帧都重算，测试里好等
	_spawned.append(vision)
	return vision


func _make_obstacle(
	center: Vector3, size: Vector3, layer: int = Character.LAYER_OBSTACLE, group: StringName = &""
) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var collision: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	add_child(body)
	body.global_position = center
	if group != StringName():
		body.add_to_group(group)
	_spawned.append(body)
	return body


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
