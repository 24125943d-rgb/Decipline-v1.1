class_name CharacterRange
extends Resource
## 「范围」：与角色[b]位置和朝向相关[/b]的一块几何区域，可复用、可存成 .tres 数据。
##
## [br]本类只回答一个问题：某个世界坐标的点，在不在这个区域里
## （[method contains_point] / [method contains]）。区域定义在[b]宿主局部空间[/b]，
## 所以同一份 .tres 换到不同角色、不同朝向上都成立 —— 这是"范围"与"某次具体判定"的分离。
##
## [br][b]刻意不管遮挡[/b]：几何包含与视线遮挡是两个正交的关注点，本类[b]不做任何射线检测[/b]。
## 需要「必须看得见才能打到」时，由使用方自己组合（例如 [method CharacterVision.can_see]）；
## 视野那套多层探针是视野自己的策略，不该长在 range 上。
##
## [br][b]为什么是 Resource 而不是 Node[/b]：以后 range 会很多（攻击范围 / 反应半径 /
## 交互距离 / 听觉范围 / 技能 AoE……），它们应当是数据：在编辑器里配、能共享、能被组件引用，
## 而不是每个都实例化一棵节点树。
##
## [br][codeblock]
## var reach := CharacterRange.new()
## reach.shape = CharacterRange.Shape.SECTOR
## reach.radius = 2.5
## reach.fov_degrees = 90.0
## if reach.contains(enemy, character.global_transform):
##     print("够得着（遮挡与否由你自己再判）")
## [/codeblock]

## 区域形状。新形状 = 新增一个分支 / 一个子类，调用方接口不变。
enum Shape {
	CIRCLE, ## 全向圆
	SECTOR, ## 以宿主 -Z 为正前方的扇形（与视野同一个朝向约定）
	BOX,    ## 局部 XZ 矩形：贴身横劈 / 直线突刺这类规则区
}

@export var shape: Shape = Shape.CIRCLE

## 圆 / 扇形的半径（米）。
@export var radius: float = 2.0:
	set(value):
		radius = maxf(value, 0.0)

## 扇形张角（度）。360 = 全向。
@export var fov_degrees: float = 120.0:
	set(value):
		fov_degrees = clampf(value, 0.0, 360.0)

## Forward is -Z; positive yaw turns toward +X (negative Godot Y rotation).
## This preserves the original sector convention and also applies to BOX.
## Offset is owner-local and is not rotated by yaw.
@export var yaw_offset_degrees: float = 0.0

## 矩形尺寸（局部 XZ，米）。
@export var box_size: Vector2 = Vector2(2.0, 2.0):
	set(value):
		box_size = Vector2(maxf(value.x, 0.0), maxf(value.y, 0.0))

## 区域中心相对宿主原点的偏移（局部空间，例如 (0, 0, -1) 表示整块范围向前挪 1 米）。
@export var offset: Vector3 = Vector3.ZERO


## 世界坐标的点是否落在区域内。[param owner_transform] 是宿主（角色）的世界变换。
func contains_point(world_point: Vector3, owner_transform: Transform3D) -> bool:
	var local: Vector3 = owner_transform.affine_inverse() * world_point - offset
	var flat: Vector2 = Vector2(local.x, local.z)
	match shape:
		Shape.SECTOR:
			if flat.length() > radius:
				return false
			if fov_degrees >= 360.0 or flat == Vector2.ZERO:
				return true
			# 局部空间里宿主正前方是 -Z；把 (x, z) 映射成 2D 后 -Z 就是 Vector2.UP
			# yaw_offset 等价于把"目标方向"反向旋转，效果与旋转扇形中心一致
			var aim: Vector2 = flat
			if not is_zero_approx(yaw_offset_degrees):
				aim = flat.rotated(-deg_to_rad(yaw_offset_degrees))
			return absf(rad_to_deg(aim.angle_to(Vector2.UP))) <= fov_degrees * 0.5
		Shape.BOX:
			var aim: Vector2 = flat.rotated(-deg_to_rad(yaw_offset_degrees))
			return absf(aim.x) <= box_size.x * 0.5 and absf(aim.y) <= box_size.y * 0.5
		_:
			return flat.length() <= radius


## 目标节点（任意 Node3D）是否在区域内。
func contains(node: Node3D, owner_transform: Transform3D) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	return contains_point(node.global_position, owner_transform)


## 一行描述，供 UI / 调试 / 积木提示用。
func describe() -> String:
	match shape:
		Shape.SECTOR:
			return "sector %.0f deg r=%.2f" % [fov_degrees, radius]
		Shape.BOX:
			return "box %.2f x %.2f" % [box_size.x, box_size.y]
		_:
			return "circle r=%.2f" % radius


## 复制一份（运行时想改参数又不影响共享的 .tres 时用）。
func copy() -> CharacterRange:
	return duplicate(true) as CharacterRange


## Exact horizontal disk intersection, not full 3D collision. Tangency counts.
## Requires upright uniformly scaled owner. Height and occlusion are ignored.
func intersects_disk(world_center: Vector3, world_radius: float, owner_transform: Transform3D) -> bool:
	if not _upright_uniform(owner_transform.basis) or world_radius < 0.0:
		return false
	var local: Vector3 = owner_transform.affine_inverse() * world_center - offset
	var point: Vector2 = Vector2(local.x, local.z).rotated(-deg_to_rad(yaw_offset_degrees))
	return _distance_to_region(point) <= world_radius / owner_transform.basis.x.length() + 0.000001

## Actual supported shapes: uniform SphereShape3D (any rotation), upright uniform
## CapsuleShape3D. Their XZ projections are disks of the actual shape radius.
## Disabled/null shapes, boxes/cylinders, tilted capsules, nonuniform scale/shear
## return false, deliberately without an approximate bounding-sphere fallback.
func supports_collision_shape(collision: CollisionShape3D, owner_transform: Transform3D) -> bool:
	if not is_instance_valid(collision) or collision.disabled or collision.shape == null:
		return false
	if not _upright_uniform(owner_transform.basis):
		return false
	var basis: Basis = collision.global_transform.basis
	if not basis.is_conformal() or basis.x.length() < 0.000001:
		return false
	return collision.shape is SphereShape3D or (collision.shape is CapsuleShape3D and _upright_uniform(basis))

func intersects_collision_shape(collision: CollisionShape3D, owner_transform: Transform3D) -> bool:
	if not supports_collision_shape(collision, owner_transform):
		return false
	var actual_radius: float = 0.0
	if collision.shape is SphereShape3D:
		actual_radius = (collision.shape as SphereShape3D).radius
	else:
		actual_radius = (collision.shape as CapsuleShape3D).radius
	return intersects_disk(collision.global_position, actual_radius * collision.global_transform.basis.x.length(), owner_transform)

static func _upright_uniform(basis: Basis) -> bool:
	return basis.is_conformal() and basis.x.length() > 0.000001 and absf(basis.y.normalized().dot(Vector3.UP)) > 0.999999

func _distance_to_region(point: Vector2) -> float:
	if shape == Shape.BOX:
		var excess: Vector2 = point.abs() - box_size * 0.5
		return Vector2(maxf(excess.x, 0.0), maxf(excess.y, 0.0)).length()
	if shape == Shape.CIRCLE or fov_degrees >= 360.0:
		return maxf(point.length() - radius, 0.0)
	if point == Vector2.ZERO:
		return 0.0
	var half_angle: float = deg_to_rad(fov_degrees * 0.5)
	if absf(point.angle_to(Vector2.UP)) <= half_angle + 0.0000001:
		return maxf(point.length() - radius, 0.0)
	return minf(_segment_distance(point, Vector2.UP.rotated(-half_angle) * radius), _segment_distance(point, Vector2.UP.rotated(half_angle) * radius))

static func _segment_distance(point: Vector2, end: Vector2) -> float:
	if end.length_squared() == 0.0:
		return point.length()
	return point.distance_to(end * clampf(point.dot(end) / end.length_squared(), 0.0, 1.0))

## Ordered boundary relative to offset, with yaw applied. Both sector endpoints
## are exact; arcs are tessellated, never searched. Partial sectors include apex.
func boundary_points(segments: int = 64) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	if shape == Shape.BOX:
		var half: Vector2 = box_size * 0.5
		points = PackedVector2Array([Vector2(-half.x, -half.y), Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)])
	else:
		var partial: bool = shape == Shape.SECTOR and fov_degrees < 360.0
		var sweep: float = deg_to_rad(fov_degrees) if partial else TAU
		var count: int = maxi(1, int(ceil(float(maxi(segments, 8)) * sweep / TAU)))
		if partial:
			points.append(Vector2.ZERO)
		for i: int in range(count + 1 if partial else count):
			points.append(Vector2.UP.rotated(-sweep * 0.5 + sweep * float(i) / float(count)) * radius)
	for i: int in points.size():
		points[i] = points[i].rotated(deg_to_rad(yaw_offset_degrees))
	return points
