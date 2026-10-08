class_name TestRangeIntegration
extends Node
const CHARACTER: PackedScene = preload("res://scenes/character.tscn")
var world: Node3D

func before_each() -> void:
	world = Node3D.new()
	add_child(world)

func after_each() -> void:
	world.free()

func _character(at: Vector3) -> Character:
	var result: Character = CHARACTER.instantiate() as Character
	world.add_child(result)
	result.global_position = at
	return result

func test_box_yaw_and_offset() -> Variant:
	var geometry: CharacterRange = CharacterRange.new()
	geometry.shape = CharacterRange.Shape.BOX
	geometry.box_size = Vector2(4, 1)
	geometry.yaw_offset_degrees = 90
	geometry.offset = Vector3(5, 0, 2)
	if not geometry.contains_point(Vector3(5, 100, 3.5), Transform3D.IDENTITY):
		return "Rotated box must include its long axis, ignoring height"
	if geometry.contains_point(Vector3(6, 0, 2), Transform3D.IDENTITY):
		return "Rotated box must exclude short-axis exterior"
	return null

func test_actual_capsule_and_unsupported_shapes() -> Variant:
	var geometry: CharacterRange = CharacterRange.new()
	geometry.radius = 1
	var shape: CollisionShape3D = CollisionShape3D.new()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 2
	shape.shape = capsule
	world.add_child(shape)
	shape.position = Vector3(1.3, 50, 0)
	if geometry.contains(shape, Transform3D.IDENTITY) or not geometry.intersects_collision_shape(shape, Transform3D.IDENTITY):
		return "Capsule projection should intersect while origin is outside"
	shape.rotation.x = 0.3
	if geometry.supports_collision_shape(shape, Transform3D.IDENTITY):
		return "Tilted capsules must be explicitly unsupported"
	shape.rotation = Vector3.ZERO
	shape.scale = Vector3(2, 1, 1)
	if geometry.intersects_collision_shape(shape, Transform3D.IDENTITY):
		return "Nonuniform scale must fail closed"
	shape.scale = Vector3.ONE
	shape.shape = BoxShape3D.new()
	if geometry.supports_collision_shape(shape, Transform3D.IDENTITY):
		return "Box target projection is not supported"
	shape.shape = SphereShape3D.new()
	shape.disabled = true
	if geometry.intersects_collision_shape(shape, Transform3D.IDENTITY):
		return "Disabled shapes must not intersect"
	return null

func test_sector_disk_edges_and_reflex() -> Variant:
	var geometry: CharacterRange = CharacterRange.new()
	geometry.shape = CharacterRange.Shape.SECTOR
	geometry.radius = 2
	geometry.fov_degrees = 90
	var edge: Vector2 = Vector2.UP.rotated(PI / 4) * 1.5
	var exterior: Vector2 = edge + Vector2(0.08, 0.08)
	if not geometry.intersects_disk(Vector3(exterior.x, 0, exterior.y), 0.12, Transform3D.IDENTITY):
		return "Disk must intersect radial sector edge"
	if geometry.intersects_disk(Vector3(0, 0, 1), 0.2, Transform3D.IDENTITY):
		return "Disk behind sector must not intersect"
	geometry.fov_degrees = 270
	if not geometry.intersects_disk(Vector3(1, 0, 0), 0, Transform3D.IDENTITY):
		return "Reflex sector side should be included"
	if geometry.intersects_disk(Vector3(0, 0, 1), 0.1, Transform3D.IDENTITY):
		return "Reflex sector missing wedge should remain empty"
	return null

func test_renderer_tiny_offset_edges_and_decal() -> Variant:
	var owner_character: Character = _character(Vector3(3, 0, 4))
	owner_character.rotation.y = 0.7
	var attack: CharacterAttack = CharacterAttack.new()
	owner_character.add_child(attack)
	attack.position = Vector3(10, 0, 10)
	attack.range_shape = CharacterRange.Shape.SECTOR
	attack.attack_range = 0.005
	attack.fov_degrees = 3
	attack.yaw_offset_degrees = 37
	attack.offset = Vector3(2, 0, -1)
	var area: AttackAreaRenderer = AttackAreaRenderer.new()
	owner_character.add_child(area)
	area.position = Vector3(-4, 0, 3)
	area.rebuild_now()
	var expected: Vector3 = owner_character.global_transform * attack.offset
	var apex: Vector3 = area.get_apex_world()
	if Vector2(apex.x - expected.x, apex.z - expected.z).length() > 0.00001:
		return "Renderer must use character transform, not component transform"
	var boundary: PackedVector2Array = attack.geometry().boundary_points(64)
	if boundary.size() < 3 or absf(boundary[1].length() - 0.005) > 0.000001:
		return "Tiny sector boundary must not disappear"
	var expected_edge: Vector2 = Vector2.UP.rotated(deg_to_rad(35.5)) * 0.005
	if boundary[1].distance_to(expected_edge) > 0.000001:
		return "Sector endpoint must be exact"
	var decal: Decal = area.get_node("AttackAreaDecal") as Decal
	if decal.size.x > 0.02 or decal.texture_albedo == null:
		return "Tiny offset decal must use boundary bounds"
	area.decal_enabled = false
	if decal.visible:
		return "Disabling decal must immediately hide it"
	return null

func test_attack_volume_is_opt_in() -> Variant:
	var attacker: Character = _character(Vector3.ZERO)
	var victim: Character = _character(Vector3(1.3, 0, 0))
	var attack: CharacterAttack = CharacterAttack.new()
	attacker.add_child(attack)
	attack.attack_range = 1
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = 0.4
	victim.hurtbox_shape.shape = sphere
	victim.hurtbox.global_position = victim.global_position
	if attack.contains(victim):
		return "Default remains origin containment"
	attack.intersect_target_volume = true
	if not attack.contains(victim):
		return "Opt-in uses actual hurtbox"
	return null

func test_real_ast_attack_and_bounded_chase() -> Variant:
	var attacker: Character = _character(Vector3.ZERO)
	var victim: Character = _character(Vector3(0, 0, -1.5))
	attacker.stance = 1
	victim.stance = -1
	var attack: CharacterAttack = CharacterAttack.new()
	attacker.add_child(attack)
	var movement: CharacterMovement = CharacterMovement.new()
	attacker.add_child(movement)
	var host: CharacterCombatHost = CharacterCombatHost.new()
	host.require_vision = false
	host.enemies = [victim]
	host.chase_frames = 3
	attacker.add_child(host)
	var compiler: ASTCompiler = ASTCompiler.new()
	compiler.max_iterations = 1
	var hp_before: int = victim.hp
	await compiler.compile_and_run(ASTManager.from_dictionary(CombatAIMock.get_combat_ai_ast()), host, Callable())
	if host.attack_commands != 1 or victim.hp >= hp_before:
		return "Real compiled IN must call CharacterAttack and damage target"
	victim.global_position = Vector3(0, 0, -10)
	var before: Vector3 = attacker.global_position
	await compiler.compile_and_run(ASTManager.from_dictionary(CombatAIMock.get_combat_ai_ast()), host, Callable())
	if host.chase_commands != 1 or movement.is_moving():
		return "Chase must return after bounded physics pulse and stop"
	if attacker.global_position.distance_to(before) <= 0.001:
		return "Chase must move the real CharacterBody through movement component"
	return null
