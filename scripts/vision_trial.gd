class_name VisionTrial
extends Node3D
## 试用场景（视野沙盒）的抽象类。
##
## 把根节点挂上这个类，场景就自带三件事：
## [br]· [member characters]：场景里的角色实例列表（留空 = 自动收集本节点下所有 [Character]）
## [br]· [member obstacles]：场景里的障碍物列表（留空 = 自动收集本节点下所有[b]落在
##   [constant Character.LAYER_OBSTACLE] 层上的物理体[/b]，也就是真正会挡视线的那批）
## [br]· 摄影机的初始机位是[b]可变参数[/b]（[member camera_initial_transform]）：
##   R 键 / 「视野复原」按钮回到的就是它
##
## [br]两个列表只负责"索引 / 统计 / 让外部脚本按名字点名"，[b]视野判定仍然由各角色身上的
## [CharacterVision] 各自完成[/b]——这个类不参与判定，也不改任何角色。
##
## [br][b]用法[/b]
## [codeblock]
## var trial: VisionTrial = get_tree().current_scene
## trial.set_camera_initial_transform(new_transform)   # 换初始机位（复原点也跟着换）
## for character in trial.characters:
##     print(character.name, " 看得见 ", trial.get_visibility_map()[character])
## [/codeblock]

@export_group("摄影机 / Camera")
## 相机节点（一般就叫 Camera3D）。
@export var camera_path: NodePath = ^"Camera3D"
## 勾上才用 [member camera_initial_transform] 覆盖相机节点自身的姿态；
## 不勾 = 就用场景里手摆好的姿态（默认，和以前的行为一致）。
@export var use_camera_initial_transform: bool = false
## 摄影机的初始机位（世界空间的可变参数）。默认值就是本工程试用场景里手调好的那台：
## 偏航 72.648°、俯仰 37.648°（向下）、位置 (23.26268, 17.53285, 7.45795)。
## [br]（用欧拉角拼，是因为 GDScript 的 [Basis] 没有 9 个浮点的构造函数。）
@export var camera_initial_transform: Transform3D = Transform3D(
	Basis.from_euler(Vector3(deg_to_rad(-37.6480757), deg_to_rad(72.6483724), 0.0)),
	Vector3(23.26268, 17.532846, 7.457945)
)

@export_group("场景内容 / Contents")
## 场景里的角色实例。留空 = 自动收集本节点下所有 [Character]（按名字排序）。
@export var characters: Array[Character] = []
## 场景里的障碍物（挡视线的物理体）。留空 = 自动收集所有落在
## [constant Character.LAYER_OBSTACLE] 层上的物理体（按名字排序）。
@export var obstacles: Array[Node3D] = []

# ------------------------------------------------------------------ 生命周期
func _ready() -> void:
	if use_camera_initial_transform:
		apply_camera_initial_transform()
	refresh_contents()

# ------------------------------------------------------------------ 摄影机
## 取相机节点（找不到返回 null）。
func get_camera() -> Camera3D:
	return get_node_or_null(camera_path) as Camera3D


## 把 [member camera_initial_transform] 应用到相机上，并让相机把它记为新的"复原点"。
## （相机上如果挂的是本工程的 [code]camera_orbit_controller.gd[/code]，它会通过
## [code]capture_initial_state()[/code] 重新记录。）
func apply_camera_initial_transform() -> void:
	var camera: Camera3D = get_camera()
	if camera == null:
		push_warning("VisionTrial: 找不到相机（%s），初始机位没有应用。" % camera_path)
		return
	camera.global_transform = camera_initial_transform
	if camera.has_method(&"capture_initial_state"):
		camera.call(&"capture_initial_state")


## 运行时换初始机位：设好参数、立刻应用，并让复原点跟着更新。
## 之后按 R 键 / 点「视野复原」就会回到这个新机位。
func set_camera_initial_transform(camera_transform: Transform3D) -> void:
	camera_initial_transform = camera_transform
	use_camera_initial_transform = true
	apply_camera_initial_transform()


## 让相机回到初始机位（等价于按 R）。
func restore_camera() -> void:
	var camera: Camera3D = get_camera()
	if camera != null and camera.has_method(&"restore_initial"):
		camera.call(&"restore_initial")

# ------------------------------------------------------------------ 场景内容
## 重新收集两个列表。[param force] 为 false 时只补空的（不覆盖手动指定的内容）。
func refresh_contents(force: bool = false) -> void:
	if force or characters.is_empty():
		characters = _collect_characters()
	if force or obstacles.is_empty():
		obstacles = _collect_obstacles()


## 场景里所有挂了视野组件的角色。
func get_characters_with_vision() -> Array[Character]:
	var result: Array[Character] = []
	for character: Character in characters:
		if character.get_node_or_null(^"Vision") != null:
			result.append(character)
	return result


## 谁看得见谁：[code]{角色: [它此刻看得见的角色…]}[/code]。
func get_visibility_map() -> Dictionary:
	var result: Dictionary = {}
	for character: Character in characters:
		var vision: CharacterVision = character.get_node_or_null(^"Vision") as CharacterVision
		var visible_now: Array[Character] = []
		if vision != null:
			for target: Character in vision.visible_characters:
				visible_now.append(target)
		result[character] = visible_now
	return result


## 任意两个角色之间的查询：[param observer] 此刻看得见 [param target] 吗？
##
## [br]读的是观察者上一次算好的结果（视野按 [member CharacterVision.update_interval] 节流），
## 所以不会在查询里做射线检测；想要"刚挪完位置的最新答案"，先 [method refresh_visions]
## 再等一个物理帧。
## [br]视线是[b]有方向[/b]的：[code]can_see(a, b)[/code] 为 true 不代表 [code]can_see(b, a)[/code]
## 也为 true。观察者是自己 / 没挂 [CharacterVision] / 传 null 时，一律返回 false。
func can_see(observer: Character, target: Character) -> bool:
	if observer == null or target == null or observer == target:
		return false
	if not is_instance_valid(target):
		return false
	var vision: CharacterVision = observer.get_node_or_null(^"Vision") as CharacterVision
	if vision == null:
		return false
	return vision.can_see(target)


## 反过来问：[param target] 此刻被谁看见？返回所有看得见它的角色（按 [method characters] 的顺序）。
func get_observers_of(target: Character) -> Array[Character]:
	var result: Array[Character] = []
	if target == null or not is_instance_valid(target):
		return result
	for observer: Character in get_characters_with_vision():
		if can_see(observer, target):
			result.append(observer)
	return result


## 让场景里所有视野立刻重算一遍。
func refresh_visions() -> void:
	for character: Character in get_characters_with_vision():
		var vision: CharacterVision = character.get_node_or_null(^"Vision") as CharacterVision
		vision.request_update()


## 一行摘要，方便日志 / 调试。
func describe() -> String:
	return "角色 %d 个（%d 个带视野）／障碍物 %d 个／相机初始机位 %s" % [
		characters.size(),
		get_characters_with_vision().size(),
		obstacles.size(),
		camera_initial_transform.origin,
	]

# ------------------------------------------------------------------ 内部
func _collect_characters() -> Array[Character]:
	var result: Array[Character] = []
	for node: Node in _walk(self):
		var character: Character = node as Character
		if character != null:
			result.append(character)
	result.sort_custom(func(a: Character, b: Character) -> bool: return String(a.name) < String(b.name))
	return result


func _collect_obstacles() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for node: Node in _walk(self):
		var body: CollisionObject3D = node as CollisionObject3D
		if body != null and (body.collision_layer & Character.LAYER_OBSTACLE) != 0:
			result.append(body)
	result.sort_custom(func(a: Node3D, b: Node3D) -> bool: return String(a.name) < String(b.name))
	return result


## 深度优先遍历全部后代（不含自己），结果按遍历顺序，调用方自己排。
func _walk(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child: Node in node.get_children():
		result.append(child)
		result.append_array(_walk(child))
	return result
