extends Node

var actor: Character
var target: Character
var near: Character
var host: CharacterCombatHost
var attack: CharacterAttack
var movement: CharacterMovement
var chase_outcome: int = -1

func before_each() -> void:
	actor = Character.new()
	target = Character.new()
	near = Character.new()
	attack = CharacterAttack.new()
	movement = CharacterMovement.new()
	host = CharacterCombatHost.new()
	host.require_vision = false
	actor.add_child(attack)
	actor.add_child(movement)
	actor.add_child(host)
	add_child(actor)
	add_child(target)
	add_child(near)
	target.position = Vector3(0, 0, -1.5)
	near.position = Vector3(0, 0, -1)
	attack.cooldown_seconds = 0
	chase_outcome = -1

func after_each() -> void:
	for node: Variant in [actor, target, near]:
		if is_instance_valid(node):
			node.free()

func test_all_nine_relations_and_self() -> Variant:
	for a: int in [-1, 0, 1]:
		actor.stance = a
		if actor.is_enemy(actor) or actor.is_friendly(actor) or actor.is_neutral(actor):
			return "All relation queries must exclude self"
		if actor.is_enemy(null) or actor.is_friendly(null) or actor.is_neutral(null):
			return "All relation queries must exclude null"
		for b: int in [-1, 0, 1]:
			target.stance = b
			var product: int = a * b
			if actor.is_enemy(target) != (product == -1) or target.is_enemy(actor) != (product == -1):
				return "Incorrect symmetric enemy relation for %d, %d" % [a, b]
			if actor.is_friendly(target) != (product == 1) or target.is_friendly(actor) != (product == 1):
				return "Incorrect symmetric friendly relation for %d, %d" % [a, b]
			if actor.is_neutral(target) != (product == 0) or target.is_neutral(actor) != (product == 0):
				return "Incorrect symmetric neutral relation for %d, %d" % [a, b]
	return null

func test_default_zero_is_neutral_and_not_attackable() -> Variant:
	if actor.stance != 0 or target.stance != 0 or not actor.is_neutral(target):
		return "Default characters must be neutral"
	if actor.is_enemy(target) or actor.is_friendly(target) or host.enemies_visible:
		return "Default zero stance must not create enemies or friends"
	if attack.can_attack(target) or attack.attack(target) or host.attack(target) or attack.attack_nearest() != null:
		return "Default neutral target must not be attacked"
	if target.hp != 100 or not attack.contains(target) or not attack.characters_in_range().has(target):
		return "Neutrality must preserve health and geometry"
	return null if await host.chase(target) == host.ChaseResult.TARGET_LOST else "Neutral chase accepted"

func test_live_neutral_transition_and_restored_hostility() -> Variant:
	actor.stance = 1
	target.stance = -1
	host.enemies = [target]
	if host.closest_enemy != target or not attack.can_attack(target):
		return "Initial enemy must be attackable"
	target.stance = 0
	if host.enemies_visible or attack.can_attack(target) or attack.attack(target) or host.attack(target):
		return "Neutral transition must immediately reject attacks"
	if not attack.contains(target) or not actor.is_neutral(target):
		return "Neutral transition must preserve IN geometry"
	target.stance = -1
	if host.closest_enemy != target or not attack.attack(target):
		return "Restored hostility must immediately allow attacks"
	actor.stance = 0
	return null if not host.enemies_visible and actor.is_neutral(target) else "Actor neutral transition was not applied"

func test_null_and_freed() -> Variant:
	if actor.is_enemy(null):
		return "Null must not be an enemy"
	target.free()
	# Godot rejects a freed object at a typed Character argument boundary before
	# entering is_enemy. Callers holding stale references must validate first.
	var enemy: bool = is_instance_valid(target) and actor.is_enemy(target)
	return null if not enemy else "Freed target accepted"

func test_integer_assignments_saturate_and_subclass_inherits() -> Variant:
	var child: AttributeCharacter = AttributeCharacter.new()
	var valid: bool = child.stance == 0
	for value: int in [-100, -2, -1, 0, 1, 2, 100]:
		actor.stance = value
		child.stance = value
		valid = valid and actor.stance == clampi(value, -1, 1) and child.stance == actor.stance
	child.free()
	return null if valid else "Stance must be a clamped base property inherited by subclasses"

func test_live_closest_whitelist_and_group_fallback() -> Variant:
	actor.stance = 1
	near.stance = 1
	target.stance = -1
	if host.closest_enemy != target:
		return "Group search selected a nearer non-enemy"
	host.enemies = [near]
	if host.enemies_visible:
		return "Whitelist must not override stance or search outside itself"
	host.enemies = [near, target]
	near.stance = -1
	if host.closest_enemy != near:
		return "Target stance change was not applied immediately"
	actor.stance = -1
	if host.enemies_visible:
		return "Actor stance change was not applied immediately"
	near.stance = 1
	return null if host.closest_enemy == near else "New hostility was not discovered"

func test_attack_geometry_nearest_and_live_rejection() -> Variant:
	actor.stance = 1
	near.stance = 1
	target.stance = -1
	if not attack.contains(near) or not attack.is_in_range(near) or not attack.characters_in_range().has(near):
		return "Friendship must not change geometry or IN"
	if attack.can_attack(near) or attack.attack(near) or host.attack(near):
		return "Non-enemy attack accepted"
	if attack.attack_nearest() != target or near.hp != 100 or target.hp != 90:
		return "Nearest selection must skip nearer non-enemies"
	target.stance = 1
	if attack.can_attack(target) or host.attack(target) or attack.attack_nearest() != null:
		return "Attack did not recheck changed relation"
	return null if attack.contains(target) else "Changed relation polluted geometry"

func _chase() -> void:
	chase_outcome = await host.chase(target)

func _frames() -> void:
	for frame: int in 3:
		await get_tree().physics_frame

func test_chase_stops_on_target_stance_change() -> Variant:
	actor.stance = -1
	target.stance = 1
	target.position.z = -20
	host.enemies = [target]
	_chase()
	await _frames()
	if not movement.is_moving():
		return "Chase did not start"
	target.stance = 0
	await _frames()
	return null if chase_outcome == host.ChaseResult.TARGET_LOST and not movement.is_moving() and actor.velocity == Vector3.ZERO else "Changed relation left chase moving"

func test_chase_stops_on_actor_stance_change_and_rejects_friend() -> Variant:
	actor.stance = -1
	target.stance = 1
	target.position.z = -20
	_chase()
	await _frames()
	actor.stance = 1
	await _frames()
	if chase_outcome != host.ChaseResult.TARGET_LOST or movement.is_moving():
		return "Actor stance change did not stop chase"
	return null if await host.chase(target) == host.ChaseResult.TARGET_LOST else "Friendly chase accepted"

func test_vision_snapshot_keeps_non_enemies() -> Variant:
	var vision: CharacterVision = CharacterVision.new()
	actor.add_child(vision)
	vision.set_physics_process(false)
	vision.visible_characters = [near, target]
	host.vision = vision
	host.require_vision = true
	actor.stance = 1
	near.stance = 1
	target.stance = -1
	if host.closest_enemy != target or not vision.can_see(near):
		return "Host hostility filtering must not remove visible friends"
	target.stance = 1
	return null if not host.enemies_visible and vision.can_see(target) else "Stance filtering changed vision snapshot"
