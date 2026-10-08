extends Node
## VisionTrial（试用场景抽象类）的单元测试。
##
## 覆盖：两个列表的自动收集、相机初始机位参数、任意两角色之间的可见性查询。
## 约定同测试运行器：方法名以 test_ 开头，返回 null = 通过、字符串 = 失败原因。

const TrialScene: PackedScene = preload("res://scenes/vision_trial.tscn")
const BareCharacterScene: PackedScene = preload("res://scenes/character.tscn")

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
func test_contents_are_collected() -> Variant:
	var trial: VisionTrial = _make_trial()
	_check_eq(
		_names(trial.characters),
		PackedStringArray([
			"CharacterA", "CharacterB", "CharacterC", "CharacterD",
			"CharacterE", "CharacterF", "CharacterG",
		]),
		"角色列表：自动收集并按名字排序"
	)
	_check_eq(
		_names(trial.obstacles),
		PackedStringArray(["BackWall", "Crate", "Obstacle", "Pillar"]),
		"障碍物列表：4 个落在障碍层上的物理体"
	)
	_check(not _names(trial.obstacles).has("Floor"), "地板（第 1 层）不算障碍物")
	_check_eq(trial.get_characters_with_vision().size(), 7, "7 个角色都挂了视野")
	print("  ", trial.describe())
	return _verdict("test_contents_are_collected")


func test_camera_initial_transform_parameter() -> Variant:
	var trial: VisionTrial = _make_trial()
	var camera: Camera3D = trial.get_camera()
	_check(camera != null, "找得到相机")
	if camera == null:
		return _verdict("test_camera_initial_transform_parameter")
	_check(
		trial.camera_initial_transform.is_equal_approx(camera.global_transform),
		"默认参数就是场景里手摆的那台机位"
	)
	_check(not trial.use_camera_initial_transform, "默认不覆盖场景机位（所以现有效果不变）")

	var moved: Transform3D = camera.global_transform
	moved.origin += Vector3(0.0, 3.0, 0.0)
	trial.set_camera_initial_transform(moved)
	_check(camera.global_transform.is_equal_approx(moved), "换初始机位后相机立刻过去")

	camera.global_transform = Transform3D(Basis(), Vector3(0.0, 40.0, 0.0))
	trial.restore_camera()
	_check(camera.global_transform.is_equal_approx(moved), "restore_camera() 回到新的初始机位")
	return _verdict("test_camera_initial_transform_parameter")


func test_can_see_between_characters() -> Variant:
	var trial: VisionTrial = _make_trial()
	await _settle()
	var a: Character = _character(trial, "CharacterA")
	var b: Character = _character(trial, "CharacterB")
	var c: Character = _character(trial, "CharacterC")
	var f: Character = _character(trial, "CharacterF")

	_check(trial.can_see(a, c), "A 看得见 C")
	_check(not trial.can_see(a, b), "A 看不见 B（被墙挡住）")
	_check(not trial.can_see(a, a), "自己看不见自己")
	_check(not trial.can_see(null, c), "观察者为 null → false")
	_check(not trial.can_see(a, null), "目标为 null → false")
	_check(trial.can_see(f, a), "F 看得见 A")
	_check(not trial.can_see(a, f), "但 A 看不见 F：视线是有方向的")
	return _verdict("test_can_see_between_characters")


func test_observers_and_map() -> Variant:
	var trial: VisionTrial = _make_trial()
	await _settle()
	var c: Character = _character(trial, "CharacterC")

	var observers: Array[Character] = trial.get_observers_of(c)
	var observer_names: PackedStringArray = _names(observers)
	print("  谁看得见 C：", observer_names)
	_check(observer_names.has("CharacterA"), "A 看得见 C")
	_check(observer_names.has("CharacterE"), "E 看得见 C")
	_check(observer_names.has("CharacterG"), "G 看得见 C")
	_check(observer_names.has("CharacterF"), "F 的视野半径扩大到 30 后看得见 C")
	_check(not observer_names.has("CharacterC"), "C 自己不在名单里")
	_check_eq(observers.size(), 4, "恰好 4 个观察者（A、E、F、G）")

	var map: Dictionary = trial.get_visibility_map()
	_check_eq(map.size(), 7, "可见性地图覆盖 7 个角色")
	_check_eq(_names(map[_character(trial, "CharacterA")]), PackedStringArray(["CharacterC", "CharacterG"]), "A 的视野半径扩大到 25 后恰好看得见 C、G")

	var bare: Character = BareCharacterScene.instantiate() as Character
	trial.add_child(bare)
	_spawned.append(bare)
	_check(not trial.can_see(bare, c), "没挂视野组件的角色 → false（不会崩）")
	return _verdict("test_observers_and_map")

# ------------------------------------------------------------------ 工具
func _make_trial() -> VisionTrial:
	var trial: VisionTrial = TrialScene.instantiate() as VisionTrial
	add_child(trial)
	_spawned.append(trial)
	return trial


func _character(trial: VisionTrial, character_name: String) -> Character:
	return trial.get_node_or_null(NodePath(character_name)) as Character


func _names(list: Variant) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	if list == null:
		return result
	for item: Variant in list:
		result.append(String((item as Node).name))
	return result


func _settle(frames: int = 5) -> void:
	for i in frames:
		await get_tree().physics_frame


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
