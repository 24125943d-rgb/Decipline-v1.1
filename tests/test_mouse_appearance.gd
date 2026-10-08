extends Node
## 角色外观（小鼠模型占位）的单元测试。
##
## 运行器约定：extends Node，方法名以 test_ 开头，返回 null = 通过、字符串 = 失败原因。
##
## 覆盖：[member Character.appearance_model] 默认已换成小鼠模型、占位球体被隐藏（节点保留）、
## 模型尺寸与原来的 1 m 占位球体一致、脚底落在角色局部 y = -0.9（游戏里正好站在地面上）、
## 并且模型朝向已对齐角色的正前方（-Z），受击判定仍然自动居中到模型包围盒中心。

const AttributeScene: PackedScene = preload("res://scenes/attribute_character.tscn")
## 原占位球体：直径 1.0 m。
const SPHERE_DIAMETER: float = 1.0
## 角色身高 1.8 m（胶囊体居中于原点）→ 脚底在局部 y = -0.9。
const FEET_LOCAL_Y: float = -0.9

var _failures: PackedStringArray = PackedStringArray()
var _spawned: Array[Node] = []


func before_each() -> void:
	_failures.clear()


func after_each() -> void:
	for node: Node in _spawned:
		if is_instance_valid(node):
			node.free()
	_spawned.clear()

# ------------------------------------------------------------------ 用例
func test_mouse_model_replaces_the_placeholder() -> Variant:
	var c: AttributeCharacter = _spawn()
	_check(c.appearance_model != null, "默认外观挂上了模型")
	_check(c.model_instance != null, "模型已经实例化进 Appearance/ModelRoot")
	if c.model_instance != null:
		_check(c.model_instance is Node3D, "模型根节点是 Node3D")
	var placeholder: Node3D = c.get_node_or_null(^"Appearance/ModelRoot/PlaceholderSphere") as Node3D
	_check(placeholder != null, "占位球体节点还在（只是隐藏，便于随时还原）")
	if placeholder != null:
		_check(not placeholder.visible, "占位球体已隐藏")
	return _verdict("test_mouse_model_replaces_the_placeholder")


func test_mouse_size_matches_placeholder_sphere() -> Variant:
	var c: AttributeCharacter = _spawn()
	var box: AABB = _appearance_aabb(c)
	_check(box.size != Vector3.ZERO, "外观有实际网格（包围盒非空）")
	var longest: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
	_check(
		absf(longest - SPHERE_DIAMETER) < 0.01,
		"最长边与球体直径一致（%.4f vs %.4f）" % [longest, SPHERE_DIAMETER]
	)
	_check(
		absf(box.position.y - FEET_LOCAL_Y) < 0.01,
		"脚底落在局部 y = %.2f（实际 %.4f）" % [FEET_LOCAL_Y, box.position.y]
	)
	var center: Vector3 = box.get_center()
	_check(
		absf(center.x) < 0.01 and absf(center.z) < 0.01,
		"模型位于角色中轴上（XZ 居中，实际 %s）" % center
	)
	return _verdict("test_mouse_size_matches_placeholder_sphere")


func test_mouse_faces_character_forward() -> Variant:
	var c: AttributeCharacter = _spawn()
	var box: AABB = _appearance_aabb(c)
	# 模型原始朝向是 +X（头部最高处的耳尖质心落在 -X 侧），包装场景把它绕 Y 轴转 90°，
	# 使脸对齐角色的正前方 -Z，因此躯干最长的一轴应该落在 Z 上。
	_check(
		box.size.z > box.size.x,
		"最长轴已转到 Z（朝向 -Z）：x = %.4f, z = %.4f" % [box.size.x, box.size.z]
	)
	return _verdict("test_mouse_faces_character_forward")


func test_hurtbox_recenters_on_the_mouse() -> Variant:
	var c: AttributeCharacter = _spawn()
	var box: AABB = _appearance_aabb(c)
	var expected: Vector3 = c.global_transform * box.get_center()
	var offset: Vector3 = c.hurtbox.global_position - expected
	_check(offset.length() < 0.002, "受击判定自动居中到模型包围盒中心（偏移 %s）" % offset)
	return _verdict("test_hurtbox_recenters_on_the_mouse")

# ------------------------------------------------------------------ 工具
## 外观（含所有可见子网格）在 ModelRoot 局部空间里的包围盒。与 Character._visual_aabb 同口径。
func _appearance_aabb(c: Character) -> AABB:
	var result: AABB = AABB()
	var source: Node3D = c.get_node_or_null(^"Appearance/ModelRoot") as Node3D
	if source == null:
		return result
	var found: bool = false
	var to_source: Transform3D = source.global_transform.affine_inverse()
	for node: Node in source.find_children("*", "VisualInstance3D", true, false):
		var visual: VisualInstance3D = node as VisualInstance3D
		if visual == null or not visual.is_visible_in_tree():
			continue
		var local_box: AABB = (to_source * visual.global_transform) * visual.get_aabb()
		result = local_box if not found else result.merge(local_box)
		found = true
	return result


func _spawn() -> AttributeCharacter:
	var character: AttributeCharacter = AttributeScene.instantiate() as AttributeCharacter
	add_child(character)
	_spawned.append(character)
	return character


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)


func _verdict(test_name: String) -> Variant:
	if _failures.is_empty():
		print("PASS  ", test_name)
		return null
	var message: String = ""
	for failure: String in _failures:
		message += "\n   - " + failure
	print("FAIL  ", test_name, message)
	return message
