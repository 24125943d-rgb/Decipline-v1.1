extends Node
var actor: Character
var target: Character
var host: CharacterCombatHost
var wall: StaticBody3D

func before_each() -> void:
	actor = Character.new()
	target = Character.new()
	actor.stance = 1
	target.stance = -1
	for body: Character in [actor, target]:
		var collider: CollisionShape3D = CollisionShape3D.new()
		var capsule: CapsuleShape3D = CapsuleShape3D.new()
		capsule.radius = 0.5
		capsule.height = 2.0
		collider.shape = capsule
		body.add_child(collider)
	var attack: CharacterAttack = CharacterAttack.new()
	attack.attack_range = 4.0
	actor.add_child(attack)
	actor.add_child(CharacterMovement.new())
	host = CharacterCombatHost.new()
	host.require_vision = false
	host.chase_timeout_seconds = 2.0
	host.blocked_timeout_seconds = 0.15
	actor.add_child(host)
	add_child(actor)
	add_child(target)
	target.position.z = -2.0
	host.enemies = [target]

func after_each() -> void:
	actor.free()
	target.free()
	if is_instance_valid(wall):
		wall.free()

func test_contact_moves_inside_attack_range_to_solid_margin() -> Variant:
	host.chase_stop_policy = CharacterCombatHost.ChaseStopPolicy.CONTACT
	if not host.attack_range.contains(target) or CharacterContact.attach(actor, target):
		return "Invalid starting geometry"
	var result: int = await host.chase(target)
	if result != CharacterCombatHost.ChaseResult.CONTACT or not CharacterContact.attach(actor, target):
		return "Did not reach physical contact: result=%s distance=%s" % [result, actor.position.distance_to(target.position)]
	if actor.position.z > -0.9 or actor.position.distance_to(target.position) < 0.999 or host.movement.is_moving():
		return "No approach, penetration, or movement left running"
	return null

func test_default_range_does_not_move() -> Variant:
	var result: int = await host.chase(target)
	return null if result == CharacterCombatHost.ChaseResult.IN_RANGE and actor.position == Vector3.ZERO else "Default range policy changed"

func test_contact_still_blocked_by_wall() -> Variant:
	wall = StaticBody3D.new()
	var collider: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(10, 4, 0.2)
	collider.shape = box
	wall.add_child(collider)
	wall.position.z = -0.8
	add_child(wall)
	host.chase_stop_policy = CharacterCombatHost.ChaseStopPolicy.CONTACT
	var result: int = await host.chase(target)
	return null if result == CharacterCombatHost.ChaseResult.BLOCKED and not CharacterContact.attach(actor, target) and actor.position.z > -0.31 else "Wall bypassed or falsely attached"
