class_name CharacterVision
extends Node3D
## 角色视野：向角色正前方展开的扇形可见范围 + 遮挡判定。
##
## 把它挂在角色（[Character]）下面就行（约定子节点名 `Vision`，也可以直接用
## `res://scenes/vision.tscn`）。扇形顶点是本节点，朝向取角色的正前方（-Z，
## 模型朝向不同时用 [member yaw_offset_degrees] 校正）。
##
## [br][b]扇形[/b]：广角 [member fov_degrees]、半径 [member view_radius]，运行时随时可改，
## 改完下一个物理帧就生效（想立刻重算用 [method request_update]）。
## [br][b]无视高度[/b]：扇形、半径、遮挡路径全部在水平面（XZ）上计算——目标站在高处或
## 低处一样能被看见，只有障碍物能挡住路径。
## [br][b]遮挡[/b]：从角色脚底往上、按 [member los_probe_heights] 的比例射出若干条水平射线，
## 只要有一条是通的就算看得见。所以比角色高（[member Character.height]）的实心障碍物会把
## 全部射线挡死，而矮箱子 / 台阶挡不住（最上面那条射线能越过去）。只有
## [member occluder_mask] 里的层算障碍物，[member transparent_group] 里的物体永不遮挡。
## [br][b]判定[/b]：目标的受击判定（[member Character.hurtbox]）在水平面上按
## [member samples_per_axis] 采样成网格，只要[b]任意一个采样点[/b]既在扇形内又没被遮挡，
## 该角色就算对当前角色可视，记进 [member visible_characters]。

## 有角色进入视野。
signal target_entered_view(target: Character)
## 有角色离开视野（走出扇形 / 被挡住 / 被销毁）。
signal target_exited_view(target: Character)
## 每次重算完广播一次，参数是新的可见角色列表。
signal view_updated(visible_targets: Array)

# ------------------------------------------------------------------ 视野
@export_group("视野 / Field of View")
## 水平广角（全角，度）。360 = 整圈。
@export_range(1.0, 360.0, 1.0, "suffix:deg") var fov_degrees: float = 90.0:
	set(value):
		fov_degrees = clampf(value, 1.0, 360.0)
		request_update()

## 视线半径（米）。
@export_range(0.1, 500.0, 0.1, "suffix:m") var view_radius: float = 12.0:
	set(value):
		view_radius = maxf(value, 0.1)
		request_update()

## 朝向偏移（度）：模型 / 视野不朝 -Z 时用它校正。
@export_range(-180.0, 180.0, 1.0, "suffix:deg") var yaw_offset_degrees: float = 0.0

## 重算间隔（秒）。0 = 每个物理帧都算。
@export_range(0.0, 5.0, 0.01, "suffix:s") var update_interval: float = 0.1

## 关掉后立刻清空可见列表并停止重算。
@export var enabled: bool = true

# ------------------------------------------------------------------ 遮挡
@export_group("遮挡 / Occlusion")
## 是否做遮挡判定（关掉就是纯扇形检测，穿透一切）。
@export var use_occlusion: bool = true
## 哪些物理层算“不透明障碍物”（默认第 4 层，见 [constant Character.LAYER_OBSTACLE]）。
@export_flags_3d_physics var occluder_mask: int = Character.LAYER_OBSTACLE
## 这个组里的物体永远不遮挡视线（玻璃、草丛、栏杆…）。
@export var transparent_group: StringName = &"vision_transparent"
## 视线探针高度，单位是 [member Character.height] 的比例（0 = 脚底，1 = 头顶）。
## 默认最高一条略高于头顶：所以只有[b]严格高过角色[/b]的障碍物才挡得住，和角色一样高
## 或更矮的挡不住。
@export var los_probe_heights: PackedFloat32Array = PackedFloat32Array([0.25, 0.6, 1.02])

# ------------------------------------------------------------------ 目标
@export_group("目标 / Targets")
## 候选角色所在的组，默认就是 [constant Character.GROUP_CHARACTER]。
@export var candidate_group: StringName = Character.GROUP_CHARACTER
## 受击判定的水平采样密度：2 = 四角，3 = 九宫格。
@export_range(1, 9, 1) var samples_per_axis: int = 3
## 收紧判定：只有受击判定中心可见才算（默认只要有一部分可见就算，即“部分可见即可视”）。
@export var require_center_visible: bool = false
## 忽略已经倒地的角色。
@export var ignore_downed: bool = false

# ------------------------------------------------------------------ 调试
@export_group("调试 / Debug")
## 画出扇形和到每个目标的判定线（绿 = 可见，红 = 被挡住）。只在开发时打开。
@export var debug_draw: bool = false
@export var debug_color: Color = Color(0.35, 1.0, 0.5, 1.0)
@export var debug_blocked_color: Color = Color(1.0, 0.35, 0.35, 1.0)

# ------------------------------------------------------------------ 状态
## 当前对“当前角色”可视的角色（受击判定有一部分或全部落在无遮挡的扇形内）。
var visible_characters: Array[Character] = []
## 视野所属的角色：向上查找自动接上，找不到就是 null（此时探针退回用本节点的高度）。
var owner_character: Character = null

var _elapsed: float = 0.0
var _debug_mesh: MeshInstance3D = null
var _last_candidates: Array[Character] = []
var _last_hit_points: Dictionary = {}
var _last_centers: Dictionary = {}

# ------------------------------------------------------------------ 生命周期
func _ready() -> void:
	owner_character = _find_owner_character()
	_setup_debug_draw()
	# 第一个物理帧就出结果（物理空间只能在物理帧里查）
	_elapsed = maxf(update_interval, 0.0)


func _physics_process(delta: float) -> void:
	if not enabled:
		if not visible_characters.is_empty():
			var empty: Array[Character] = []
			_apply_visible(empty)
		return
	if update_interval <= 0.0:
		_update_view()
		return
	_elapsed += delta
	if _elapsed < update_interval:
		return
	_elapsed = 0.0
	_update_view()

# ------------------------------------------------------------------ 公开 API
## 让下一次物理帧立刻重算（改完参数想马上生效时用；物理空间只能在物理帧里查，
## 所以这里不做同步重算）。
func request_update() -> void:
	if is_inside_tree() and enabled:
		_elapsed = update_interval


## 目标当前是否对当前角色可视。
func can_see(target: Character) -> bool:
	return target != null and visible_characters.has(target)


## 某个世界坐标点是否落在扇形里（只看水平距离和角度，忽略高度）。
func is_in_sector(point: Vector3) -> bool:
	var delta: Vector3 = point - global_position
	var flat: Vector3 = Vector3(delta.x, 0.0, delta.z)
	if flat.length() > view_radius:
		return false
	if fov_degrees >= 359.999:
		return true
	if flat.length_squared() < 0.000001:
		return true
	return rad_to_deg(_horizontal_forward().angle_to(flat.normalized())) <= fov_degrees * 0.5


## 扇形中心方向（世界空间，已含 [member yaw_offset_degrees]）。
## 想让视野跟着摄像机 / 头骨走，覆盖这个函数即可。
func get_forward() -> Vector3:
	var direction: Vector3 = -global_transform.basis.z
	if not is_zero_approx(yaw_offset_degrees):
		direction = direction.rotated(Vector3.UP, deg_to_rad(yaw_offset_degrees))
	if direction.length_squared() < 0.000001:
		return Vector3.FORWARD
	return direction.normalized()


## 视线探针的世界高度列表（脚底往上按比例算）。
func get_probe_heights() -> PackedFloat32Array:
	var heights: PackedFloat32Array = PackedFloat32Array()
	if owner_character != null and is_instance_valid(owner_character):
		var feet_y: float = owner_character.get_feet_position().y
		var character_height: float = maxf(owner_character.height, 0.05)
		for fraction: float in los_probe_heights:
			heights.append(feet_y + fraction * character_height)
	elif los_probe_heights.is_empty():
		heights.append(global_position.y)
	else:
		# 没有角色可参考，就退回用本节点的高度
		heights.append(global_position.y)
	return heights

# ------------------------------------------------------------------ 内部：主循环
func _update_view() -> void:
	if not is_inside_tree():
		return
	var candidates: Array[Character] = _collect_candidates()
	_last_candidates = candidates
	_last_hit_points.clear()
	_last_centers.clear()

	var current: Array[Character] = []
	for candidate: Character in candidates:
		var box: AABB = _hurtbox_world_aabb(candidate)
		_last_centers[candidate] = box.get_center()
		if _is_target_visible(candidate, box):
			current.append(candidate)

	_apply_visible(current)
	if debug_draw:
		_refresh_debug_draw()


func _apply_visible(current: Array[Character]) -> void:
	var previous: Array[Character] = []
	for target: Character in visible_characters:
		if is_instance_valid(target):
			previous.append(target)

	visible_characters = current

	for target: Character in current:
		if not previous.has(target):
			target_entered_view.emit(target)
	for target: Character in previous:
		if not current.has(target):
			target_exited_view.emit(target)
	view_updated.emit(current)


func _collect_candidates() -> Array[Character]:
	var result: Array[Character] = []
	for node: Node in get_tree().get_nodes_in_group(candidate_group):
		var candidate: Character = node as Character
		if candidate == null or candidate == owner_character:
			continue
		if candidate.hurtbox == null:
			continue
		if ignore_downed and candidate.is_downed:
			continue
		result.append(candidate)
	return result


func _is_target_visible(target: Character, box: AABB) -> bool:
	if require_center_visible:
		var center: Vector3 = box.get_center()
		return _point_visible(target, center)

	for point: Vector3 in _sample_points(box):
		if _point_visible(target, point):
			_last_hit_points[target] = point
			return true
	return false


func _point_visible(target: Character, point: Vector3) -> bool:
	if not is_in_sector(point):
		return false
	if not use_occlusion:
		return true
	return _has_line_of_sight(target, point)

# ------------------------------------------------------------------ 内部：遮挡
## 只要有一条探针没被挡住，就算看得见。
func _has_line_of_sight(target: Character, point: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return true

	var exclude: Array[RID] = _los_exclusions(target)
	var heights: PackedFloat32Array = get_probe_heights()

	for height: float in heights:
		# 水平射线：两端同高，所以高度不参与判定，只用来决定“够不够高”
		var from: Vector3 = Vector3(global_position.x, height, global_position.z)
		var goal: Vector3 = Vector3(point.x, height, point.z)
		if from.distance_squared_to(goal) < 0.000001:
			return true
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			from, goal, occluder_mask, exclude
		)
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			return true
		if _is_transparent(hit.get("collider")):
			return true
	return false


func _los_exclusions(target: Character) -> Array[RID]:
	var exclude: Array[RID] = []
	if owner_character != null and is_instance_valid(owner_character):
		exclude.append(owner_character.get_rid())
	if target != null and is_instance_valid(target):
		exclude.append(target.get_rid())
	return exclude


func _is_transparent(collider: Variant) -> bool:
	var node: Node = collider as Node
	if node == null:
		return false
	if transparent_group != StringName() and node.is_in_group(transparent_group):
		return true
	if node.has_meta(&"vision_transparent"):
		return bool(node.get_meta(&"vision_transparent"))
	return false

# ------------------------------------------------------------------ 内部：几何
func _horizontal_forward() -> Vector3:
	var forward: Vector3 = get_forward()
	var flat: Vector3 = Vector3(forward.x, 0.0, forward.z)
	if flat.length_squared() < 0.000001:
		return Vector3.FORWARD
	return flat.normalized()


## 目标受击判定的世界包围盒；取不到形状时退化成受击判定原点上的一个点。
func _hurtbox_world_aabb(target: Character) -> AABB:
	var hurtbox: Area3D = target.hurtbox
	if hurtbox == null:
		return AABB()
	var box: AABB = AABB()
	var found: bool = false
	for child: Node in hurtbox.get_children():
		if not (child is CollisionShape3D):
			continue
		var shape_node: CollisionShape3D = child as CollisionShape3D
		var local_box: AABB = _shape_local_aabb(shape_node.shape)
		if local_box.size == Vector3.ZERO:
			continue
		var world_box: AABB = _transform_aabb(local_box, shape_node.global_transform)
		box = world_box if not found else box.merge(world_box)
		found = true
	if not found:
		box = AABB(hurtbox.global_position, Vector3.ZERO)
	return box


## 在水平面上采样：高度不参与判定，所以只取 AABB 中心高度上的一张网格。
func _sample_points(box: AABB) -> PackedVector3Array:
	var points: PackedVector3Array = PackedVector3Array()
	var count: int = clampi(samples_per_axis, 1, 9)
	var y: float = box.get_center().y
	for ix in count:
		for iz in count:
			var fx: float = 0.5 if count == 1 else float(ix) / float(count - 1)
			var fz: float = 0.5 if count == 1 else float(iz) / float(count - 1)
			points.append(
				Vector3(lerpf(box.position.x, box.end.x, fx), y, lerpf(box.position.z, box.end.z, fz))
			)
	return points


static func _shape_local_aabb(shape: Shape3D) -> AABB:
	if shape == null:
		return AABB()
	if shape is BoxShape3D:
		var box_size: Vector3 = (shape as BoxShape3D).size
		return AABB(-box_size * 0.5, box_size)
	if shape is SphereShape3D:
		var radius: float = (shape as SphereShape3D).radius
		var diameter: Vector3 = Vector3(radius, radius, radius) * 2.0
		return AABB(-diameter * 0.5, diameter)
	if shape is CapsuleShape3D:
		var capsule: CapsuleShape3D = shape as CapsuleShape3D
		return AABB(
			Vector3(-capsule.radius, -capsule.height * 0.5, -capsule.radius),
			Vector3(capsule.radius * 2.0, capsule.height, capsule.radius * 2.0)
		)
	if shape is CylinderShape3D:
		var cylinder: CylinderShape3D = shape as CylinderShape3D
		return AABB(
			Vector3(-cylinder.radius, -cylinder.height * 0.5, -cylinder.radius),
			Vector3(cylinder.radius * 2.0, cylinder.height, cylinder.radius * 2.0)
		)
	if shape is ConvexPolygonShape3D:
		var poly_points: PackedVector3Array = (shape as ConvexPolygonShape3D).points
		if poly_points.is_empty():
			return AABB()
		var min_point: Vector3 = poly_points[0]
		var max_point: Vector3 = poly_points[0]
		for point: Vector3 in poly_points:
			min_point = min_point.min(point)
			max_point = max_point.max(point)
		return AABB(min_point, max_point - min_point)
	return AABB()


static func _transform_aabb(box: AABB, xform: Transform3D) -> AABB:
	var min_point: Vector3 = xform * box.position
	var max_point: Vector3 = min_point
	for i in 8:
		var corner: Vector3 = box.position + Vector3(
			box.size.x if (i & 1) != 0 else 0.0,
			box.size.y if (i & 2) != 0 else 0.0,
			box.size.z if (i & 4) != 0 else 0.0
		)
		var world_corner: Vector3 = xform * corner
		min_point = min_point.min(world_corner)
		max_point = max_point.max(world_corner)
	return AABB(min_point, max_point - min_point)


func _find_owner_character() -> Character:
	var node: Node = get_parent()
	while node != null:
		var character: Character = node as Character
		if character != null:
			return character
		node = node.get_parent()
	return null

# ------------------------------------------------------------------ 调试绘制
func _setup_debug_draw() -> void:
	if not debug_draw:
		return
	if _debug_mesh != null:
		_debug_mesh.queue_free()
	_debug_mesh = MeshInstance3D.new()
	_debug_mesh.name = "VisionDebug"
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	_debug_mesh.material_override = material
	_debug_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_debug_mesh.mesh = ImmediateMesh.new()
	add_child(_debug_mesh)
	_refresh_debug_draw()


func _refresh_debug_draw() -> void:
	if _debug_mesh == null:
		return
	var mesh: ImmediateMesh = _debug_mesh.mesh as ImmediateMesh
	if mesh == null:
		return
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	var origin: Vector3 = global_position
	var forward: Vector3 = _horizontal_forward()
	var half_angle: float = deg_to_rad(fov_degrees * 0.5)
	var segments: int = maxi(int(fov_degrees / 10.0), 3)

	# 扇形（画在本节点所在的水平面上）
	var previous: Vector3 = origin
	for i in segments + 1:
		var angle: float = -half_angle + (2.0 * half_angle) * (float(i) / float(segments))
		var point: Vector3 = origin + forward.rotated(Vector3.UP, angle) * view_radius
		if i == 0 or i == segments:
			_add_debug_line(mesh, origin, point, debug_color)
		if i > 0:
			_add_debug_line(mesh, previous, point, debug_color)
		previous = point

	# 每个候选目标一条判定线：绿 = 看得见，红 = 看不见
	for target: Character in _last_candidates:
		var endpoint: Vector3 = _last_hit_points.get(target, _last_centers.get(target, origin))
		var color: Color = debug_color if visible_characters.has(target) else debug_blocked_color
		_add_debug_line(mesh, origin, endpoint, color)

	mesh.surface_end()


func _add_debug_line(mesh: ImmediateMesh, from: Vector3, to: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(to_local(from))
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(to_local(to))
