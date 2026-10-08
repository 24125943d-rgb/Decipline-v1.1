extends Node
var actor: Character
var victim: Character
var host: CharacterCombatHost
var attack: CharacterAttack
var movement: CharacterMovement
var result: int = -1

func before_each() -> void:
	actor = Character.new()
	victim = Character.new()
	# Explicit opponents keep command tests independent of neutral defaults.
	actor.stance = 1
	victim.stance = -1
	attack = CharacterAttack.new()
	movement = CharacterMovement.new()
	host = CharacterCombatHost.new()
	host.require_vision = false
	actor.add_child(attack)
	actor.add_child(movement)
	actor.add_child(host)
	add_child(actor)
	add_child(victim)
	victim.position = Vector3(0, 0, -4)
	host.enemies = [victim]
	result = -1

func after_each() -> void:
	if is_instance_valid(actor):
		actor.free()
	if is_instance_valid(victim):
		victim.free()

func _run() -> void:
	result = await host.chase(victim)

func _frames(count: int) -> void:
	for frame: int in count:
		await get_tree().physics_frame

func test_cooldown_and_geometry() -> Variant:
	victim.position.z = -1
	attack.cooldown_seconds = 0.05
	if not attack.attack(victim) or attack.attack(victim) or not attack.contains(victim) or attack.can_attack(victim):
		return "Cooldown must not change geometry"
	while attack.cooldown_remaining() > 0.0:
		await get_tree().physics_frame
	return null if attack.attack(victim) else "Cooldown did not expire"

func test_downed_and_detached() -> Variant:
	victim.position.z = -1
	actor.hp = 0
	if attack.attack(victim) or not attack.contains(victim):
		return "Downed attacker or geometry incorrect"
	actor.revive()
	victim.hp = 0
	if attack.attack(victim):
		return "Protected downed target accepted"
	victim.damageable_when_downed = true
	if not attack.attack(victim):
		return "Explicit downed damage policy ignored"
	remove_child(victim)
	return null if not attack.contains(victim) else "Detached target accepted"

func test_continuous_and_moving_target() -> Variant:
	_run()
	await _frames(5)
	victim.position = Vector3(3, 0, -3)
	await get_tree().create_timer(2.0).timeout
	return null if result == host.ChaseResult.IN_RANGE and attack.contains(victim) and not movement.is_moving() else "Did not follow moving target to range"

func test_in_range_no_movement() -> Variant:
	victim.position.z = -1
	var outcome: int = await host.chase(victim)
	return null if outcome == host.ChaseResult.IN_RANGE and actor.position == Vector3.ZERO else "In-range chase moved"

func test_blocked_and_timeout() -> Variant:
	movement.speed = 0
	host.blocked_timeout_seconds = 0.05
	if await host.chase(victim) != host.ChaseResult.BLOCKED:
		return "Expected blocked"
	host.blocked_timeout_seconds = 1.0
	host.chase_timeout_seconds = 0.05
	return null if await host.chase(victim) == host.ChaseResult.TIMEOUT else "Expected timeout"

func test_deleted_target() -> Variant:
	_run()
	await _frames(3)
	victim.free()
	await _frames(3)
	return null if result == host.ChaseResult.TARGET_LOST and not movement.is_moving() else "Deleted target not handled"

func test_cancel_and_new_command_ownership() -> Variant:
	_run()
	await _frames(3)
	host.cancel()
	_run()
	await _frames(3)
	if not movement.is_moving() or host.chase_result != host.ChaseResult.RUNNING:
		return "Old coroutine stopped new command"
	host.attack(victim)
	await _frames(3)
	return null if not movement.is_moving() and result == host.ChaseResult.CANCELLED else "Attack failed to cancel chase"

func test_lost_vision() -> Variant:
	var vision: CharacterVision = CharacterVision.new()
	actor.add_child(vision)
	vision.set_physics_process(false)
	host.vision = vision
	host.require_vision = true
	vision.visible_characters = [victim]
	_run()
	await _frames(3)
	vision.visible_characters.clear()
	await _frames(3)
	return null if result == host.ChaseResult.VISION_LOST else "Vision loss did not end chase"

func test_downed_during_chase() -> Variant:
	_run()
	await _frames(3)
	actor.hp = 0
	await _frames(3)
	return null if result == host.ChaseResult.CANNOT_ACT and not movement.is_moving() else "Downed actor still pursuing"

func test_exit_tree_stops() -> Variant:
	_run()
	await _frames(3)
	actor.remove_child(host)
	await _frames(3)
	var stopped: bool = not movement.is_moving() and result == host.ChaseResult.CANCELLED
	host.free()
	return null if stopped else "Tree exit left movement running"

func test_attack_global_facing() -> Variant:
	var pivot: Node3D = Node3D.new()
	add_child(pivot)
	remove_child(actor)
	pivot.add_child(actor)
	pivot.rotation.y = 1.2
	victim.global_position = actor.global_position + Vector3(1, 0, 0)
	attack.range_shape = CharacterRange.Shape.SECTOR
	attack.fov_degrees = 30
	var landed: bool = host.attack(victim)
	pivot.remove_child(actor)
	add_child(actor)
	pivot.free()
	return null if landed else "Attack did not face target in world space"

func test_real_ast_stop() -> Variant:
	var compiler: ASTCompiler = ASTCompiler.new()
	var script: GDScript = ASTCompiler.compile(compiler.generate_gdscript(ASTManager.from_dictionary(CombatAIMock.get_combat_ai_ast())))
	var runner: RefCounted = script.new()
	runner.set("target", host)
	runner.call("execute")
	await _frames(3)
	runner.call("stop")
	await _frames(3)
	return null if host.chase_result == host.ChaseResult.CANCELLED and not movement.is_moving() else "AST stop failed"
