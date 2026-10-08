class_name CharacterContact
extends RefCounted
## Synchronous convex solid proximity, independent of physics ticks and hostility.
## Only direct body shapes, never Area3D hurtboxes. Unsupported/sheared shapes fail closed.
const DEFAULT_TOLERANCE: float = 0.0001
const MAX_TOLERANCE: float = 0.005

static func attach(a: Variant, b: Variant, tolerance: float = DEFAULT_TOLERANCE) -> bool:
	if not is_instance_valid(a) or not is_instance_valid(b) or a == b:
		return false
	if not a is CharacterBody3D or not b is CharacterBody3D:
		return false
	if not a.is_inside_tree() or not b.is_inside_tree() or a.is_queued_for_deletion() or b.is_queued_for_deletion():
		return false
	var left: Array[CollisionShape3D] = _shapes(a)
	var right: Array[CollisionShape3D] = _shapes(b)
	if left.is_empty() or right.is_empty():
		return false
	var margin: float = clampf(tolerance, 0.0, MAX_TOLERANCE) + clampf(maxf(a.safe_margin, b.safe_margin), 0.0, MAX_TOLERANCE)
	for x: CollisionShape3D in left:
		for y: CollisionShape3D in right:
			var p: Vector3 = x.global_position
			for iteration: int in 128:
				var q: Vector3 = _project(y, p)
				p = _project(x, q)
				if p.distance_to(q) <= margin:
					return true
	return false

static func _shapes(body: CharacterBody3D) -> Array[CollisionShape3D]:
	var result: Array[CollisionShape3D] = []
	for child: Node in body.get_children():
		if not child is CollisionShape3D:
			continue
		var node: CollisionShape3D = child as CollisionShape3D
		if node.disabled:
			continue
		var shape: Shape3D = node.shape
		if not (shape is CapsuleShape3D or shape is SphereShape3D or shape is BoxShape3D):
			return []
		var basis: Basis = node.global_transform.basis
		var scale: Vector3 = basis.get_scale().abs()
		if minf(scale.x, minf(scale.y, scale.z)) < 0.000001:
			return []
		var unit: Basis = Basis(basis.x.normalized(), basis.y.normalized(), basis.z.normalized())
		if absf(unit.x.dot(unit.y)) + absf(unit.x.dot(unit.z)) + absf(unit.y.dot(unit.z)) > 0.00001:
			return []
		if not shape is BoxShape3D and (absf(scale.x - scale.y) + absf(scale.x - scale.z)) > 0.00001:
			return []
		result.append(node)
	return result

static func _project(node: CollisionShape3D, point: Vector3) -> Vector3:
	var transform: Transform3D = node.global_transform
	var local: Vector3 = transform.affine_inverse() * point
	var shape: Shape3D = node.shape
	if shape is BoxShape3D:
		var half: Vector3 = (shape as BoxShape3D).size * 0.5
		return transform * local.clamp(-half, half)
	var center: Vector3 = Vector3.ZERO
	var radius: float = 0.0
	if shape is CapsuleShape3D:
		var capsule: CapsuleShape3D = shape as CapsuleShape3D
		radius = capsule.radius
		var segment: float = maxf(0.0, capsule.height * 0.5 - radius)
		center.y = clampf(local.y, -segment, segment)
	else:
		radius = (shape as SphereShape3D).radius
	var offset: Vector3 = local - center
	return transform * (center + offset.limit_length(radius))
