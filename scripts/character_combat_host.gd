class_name CharacterCombatHost
extends Node
## Real AST host: IN compiles to attack_range.contains(closest_enemy).
## Nonempty enemies is an explicit candidate whitelist, never a hostility override.
## Empty enemies discovers the Character group (it no longer means no candidates).
## Stance is checked live on every query/command and each chase physics iteration;
## a relation change ends chase as TARGET_LOST and stops movement.
## Optional vision filters candidates without changing the vision snapshot.
## Attach under Character with Attack and Movement siblings. Does not auto-run AI.
## Chase is continuous by default, bounded by timeout; straight-line, not pathfinding.
@export var enemies: Array[Character] = []
@export var require_vision: bool = true
## 0 = continuous straight-line chase (not pathfinding); >0 = legacy pulse.
@export_range(0, 60, 1) var chase_frames: int = 0
@export var chase_timeout_seconds: float = 10.0
@export var blocked_timeout_seconds: float = 0.5
@export var turn_before_attack: bool = true
enum ChaseStopPolicy { ATTACK_RANGE, CONTACT }
## CONTACT uses solid geometry + safe_margin, never hurtboxes or attack radius.
@export var chase_stop_policy: ChaseStopPolicy = ChaseStopPolicy.ATTACK_RANGE
enum ChaseResult { IDLE, RUNNING, IN_RANGE, PULSE_COMPLETE, CANCELLED, TIMEOUT, BLOCKED, TARGET_LOST, VISION_LOST, CANNOT_ACT, UNAVAILABLE, CONTACT }
signal chase_finished(command_id: int, result: ChaseResult)
var command_generation: int = 0
var chase_result: ChaseResult = ChaseResult.IDLE
var character: Character = null
var movement: CharacterMovement = null
var vision: CharacterVision = null
var attack_range: CharacterAttack = null
var attack_commands: int = 0
var chase_commands: int = 0
var enemies_visible: bool:
	get:
		return closest_enemy != null
var closest_enemy: Character:
	get:
		var nearest: Character = null
		var distance: float = INF
		if not is_instance_valid(attack_range):
			return null
		for enemy: Character in _candidates():
			if not is_instance_valid(enemy) or not _valid_target(enemy):
				continue
			if not _visible(enemy):
				continue
			var candidate_distance: float = attack_range.distance_to(enemy)
			if candidate_distance < distance:
				distance = candidate_distance
				nearest = enemy
		return nearest

## Strict program reads never use the legacy require_vision bypass.
var program_visible: Array[Character]:
	get:
		var result: Array[Character] = []
		if not is_instance_valid(character) or not is_instance_valid(vision) or not vision.enabled:
			return result
		for enemy: Character in _candidates():
			if _valid_target(enemy) and vision.can_see(enemy):
				result.append(enemy)
		return result
var program_visible_closest: Character:
	get:
		var nearest: Character = null
		var best: float = INF
		for enemy: Character in program_visible:
			var delta: Vector3 = enemy.global_position - character.global_position
			var distance: float = Vector2(delta.x, delta.z).length_squared()
			if distance < best:
				best = distance
				nearest = enemy
		return nearest
var program_visible_exists: bool:
	get:
		return program_visible_closest != null

func validate_program_bindings(needs: PackedStringArray) -> PackedStringArray:
	var errors: PackedStringArray = []
	for capability: String in needs:
		var component: Node = null
		match capability:
			"Character": component = character
			"Attack": component = attack_range
			"Movement": component = movement
			"Vision": component = vision
		if not is_instance_valid(component) or not component.is_inside_tree() or component.is_queued_for_deletion():
			errors.append("root: Missing live %s binding." % capability)
	return errors

## Pure two-object solid contact; no enemy/vision policy is applied.
func attach(lhs: Variant, rhs: Variant) -> bool:
	if not lhs is Character or not rhs is Character:
		return false
	return preload("res://scripts/character_contact.gd").attach(lhs, rhs)

func program_attack(target: Character) -> bool:
	if not validate_program_bindings(["Character", "Attack", "Vision"]).is_empty():
		return false
	if not vision.enabled or not vision.can_see(target):
		return false
	return attack(target)

func program_chase(target: Character) -> ChaseResult:
	if not validate_program_bindings(["Character", "Attack", "Movement", "Vision"]).is_empty():
		return ChaseResult.UNAVAILABLE
	# Keep the strict vision policy for every physics iteration without changing legacy settings.
	return await chase(target, true)

func _ready() -> void:
	character = get_parent() as Character
	if character == null:
		push_warning("CharacterCombatHost requires a Character parent.")
		return
	for child: Node in character.get_children():
		if child is CharacterAttack:
			attack_range = child as CharacterAttack
		elif child is CharacterMovement:
			movement = child as CharacterMovement
		elif child is CharacterVision:
			vision = child as CharacterVision

func _candidates() -> Array[Character]:
	if not enemies.is_empty():
		return enemies
	var result: Array[Character] = []
	if is_inside_tree():
		for node: Node in get_tree().get_nodes_in_group(Character.GROUP_CHARACTER):
			if node is Character:
				result.append(node as Character)
	return result

func _valid_target(target: Character) -> bool:
	return (
		is_instance_valid(character) and is_instance_valid(target)
		and character.is_enemy(target) and target.is_inside_tree()
		and not target.is_queued_for_deletion()
		and (enemies.has(target) if not enemies.is_empty() else target.is_in_group(Character.GROUP_CHARACTER))
		and (not target.is_downed or target.damageable_when_downed)
	)

func _can_act() -> bool:
	return is_inside_tree() and not is_queued_for_deletion() and is_instance_valid(character) and character.is_inside_tree() and not character.is_queued_for_deletion() and not character.is_downed

## Uses the latest vision snapshot, including its configured update latency.
func _visible(target: Character) -> bool:
	return not require_vision or (is_instance_valid(vision) and vision.enabled and vision.can_see(target))

func _face(target: Character) -> void:
	var direction: Vector3 = target.global_position - character.global_position
	direction.y = 0.0
	if direction.length_squared() > 0.000001:
		character.global_rotation = Vector3(0.0, atan2(-direction.x, -direction.z), 0.0)

## Explicit optional AST cancellation protocol.
func cancel_ast_execution() -> void:
	cancel()

func cancel() -> void:
	var previous_id: int = command_generation
	var was_running: bool = chase_result == ChaseResult.RUNNING
	command_generation += 1
	if is_instance_valid(movement):
		movement.stop()
	if was_running:
		chase_result = ChaseResult.CANCELLED
		chase_finished.emit(previous_id, chase_result)

func _exit_tree() -> void:
	cancel()

func attack(target: Character) -> bool:
	attack_commands += 1
	cancel()
	if not _can_act() or not _valid_target(target) or not _visible(target) or not is_instance_valid(attack_range):
		return false
	if turn_before_attack:
		_face(target)
	return attack_range.attack(target)

func _finish(token: int, result: ChaseResult) -> ChaseResult:
	if token != command_generation:
		return ChaseResult.CANCELLED
	if is_instance_valid(movement):
		movement.stop()
	chase_result = result
	chase_finished.emit(token, result)
	return result

func chase(target: Character, strict_vision: bool = false) -> ChaseResult:
	chase_commands += 1
	cancel()
	var token: int = command_generation
	chase_result = ChaseResult.RUNNING
	var started: int = Time.get_ticks_msec()
	var last_progress: int = started
	var timeout_ms: int = int(maxf(0.05, chase_timeout_seconds) * 1000.0)
	var blocked_ms: int = int(maxf(0.05, blocked_timeout_seconds) * 1000.0)
	var steps: int = 0
	var observed_step: int = movement.completed_steps if is_instance_valid(movement) else 0
	var previous: Vector3 = character.global_position if _can_act() else Vector3.ZERO
	while token == command_generation:
		if not _can_act():
			return _finish(token, ChaseResult.CANNOT_ACT)
		if not is_instance_valid(movement) or not movement.is_inside_tree() or not is_instance_valid(attack_range) or not attack_range.is_inside_tree():
			return _finish(token, ChaseResult.UNAVAILABLE)
		if not is_instance_valid(target) or not _valid_target(target):
			return _finish(token, ChaseResult.TARGET_LOST)
		if (strict_vision and (not is_instance_valid(vision) or not vision.enabled or not vision.can_see(target))) or not _visible(target):
			return _finish(token, ChaseResult.VISION_LOST)
		_face(target)
		# Check contact before timeout/blocked: a stopped body may have reached its goal.
		if chase_stop_policy == ChaseStopPolicy.CONTACT:
			if CharacterContact.attach(character, target):
				return _finish(token, ChaseResult.CONTACT)
		elif attack_range.is_in_range(target):
			return _finish(token, ChaseResult.IN_RANGE)
		var now: int = Time.get_ticks_msec()
		if now - started >= timeout_ms:
			return _finish(token, ChaseResult.TIMEOUT)
		# physics_frame precedes movement processing. Only sample completed steps.
		if movement.completed_steps != observed_step:
			steps += movement.completed_steps - observed_step
			observed_step = movement.completed_steps
			if previous.distance_to(character.global_position) > 0.00001:
				last_progress = now
			previous = character.global_position
			if chase_frames > 0 and steps >= clampi(chase_frames, 1, 60):
				return _finish(token, ChaseResult.PULSE_COMPLETE)
		if now - last_progress >= blocked_ms:
			return _finish(token, ChaseResult.BLOCKED)
		var direction: Vector3 = target.global_position - character.global_position
		direction.y = 0.0
		movement.move(direction)
		await get_tree().physics_frame
	return ChaseResult.CANCELLED
