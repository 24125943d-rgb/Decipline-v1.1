extends "res://tests/test_character_decipline.gd"

var actor: Character
var victim: Character
var host: CharacterCombatHost
var movement: CharacterMovement
var vision: CharacterVision
var component: Node
var lab: Node

func before_each() -> void:
	var scene: PackedScene = load("res://scenes/character.tscn")
	_scenes.append(scene)
	actor = scene.instantiate()
	victim = scene.instantiate()
	_spawned.append(actor)
	_spawned.append(victim)
	add_child(actor)
	add_child(victim)
	actor.stance = 1
	victim.stance = -1
	victim.position = Vector3(0, 0.9, -1.5)
	actor.position.y = 0.9
	actor.add_child(CharacterAttack.new())
	movement = CharacterMovement.new()
	actor.add_child(movement)
	vision = CharacterVision.new()
	vision.update_interval = 0.0
	actor.add_child(vision)
	host = CharacterCombatHost.new()
	host.chase_timeout_seconds = 0.5
	actor.add_child(host)
	component = DeciplineScript.new()
	actor.add_child(component)
	lab = load(LAB_SCRIPT_PATH).new()
	lab.build_on_ready = false
	lab.content_path = ^"Content"
	var content: VBoxContainer = VBoxContainer.new()
	content.name = "Content"
	lab.add_child(content)
	add_child(lab)
	_spawned.append(lab)
	component.link(component.get_path_to(lab))
	component.max_iterations = 1

func _frames(count: int = 4) -> void:
	for index: int in count:
		await get_tree().physics_frame

func _program() -> void:
	await lab.build(ASTManager.from_dictionary(CombatAIMock.get_character_program_ast()))
	await _frames()

func test_real_damage_and_bounded_physics_chase() -> Variant:
	await _program()
	var original: Script = actor.get_script()
	var hp: int = victim.hp
	if not component.start():
		return str(component.last_problems)
	await _frames(5)
	if victim.hp >= hp or component.state != "finished" or actor.get_script() != original:
		return "Strict linked real Attack failed or changed Character script"
	victim.position.z = -7
	await _frames()
	host.chase_frames = 3
	var before: Vector3 = actor.position
	if not component.start():
		return "Chase start rejected"
	await _frames(12)
	if actor.position.distance_to(before) <= 0.001 or movement.is_moving() or component.state != "finished":
		return "Bounded Chase did not physically move then stop"
	host.chase_frames = 0
	component.start()
	await _frames(3)
	component.stop()
	var stopped: Vector3 = actor.position
	await _frames(4)
	if movement.is_moving() or actor.position.distance_to(stopped) > 0.001 or component.state != "stopped":
		return "Executor stop left physical movement"
	print("Real strict BlockLab execution: damage=", hp - victim.hp, "; chase displacement=", before.distance_to(stopped))
	return null

func test_visibility_and_missing_binding_and_invalid_start() -> Variant:
	victim.position.z = -6
	var friend: Character = _scenes[0].instantiate()
	_spawned.append(friend)
	add_child(friend)
	friend.stance = 1
	friend.position = Vector3(1, 0.9, -1)
	var wall: StaticBody3D = StaticBody3D.new()
	wall.collision_layer = Character.LAYER_OBSTACLE
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(4, 3, 0.4)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	wall.position = Vector3(0, 1.5, -3)
	_spawned.append(wall)
	await _program()
	if host.program_visible_closest != null or host.program_visible_exists:
		return "Friend or occluded enemy selected"
	if not component.start():
		return "No-target program rejected"
	await _frames(3)
	if host.attack_commands != 0 or host.chase_commands != 0:
		return "No-target program issued commands"
	wall.free()
	await _frames()
	if host.program_visible_closest != victim:
		return "Unoccluded enemy not selected"
	vision.free()
	host.require_vision = false
	if component.start() or component.state != "error" or host.program_visible_closest != null:
		return "Missing Vision bypassed strict contract"
	vision = CharacterVision.new()
	actor.add_child(vision)
	host.vision = vision
	for invalid: Dictionary in [{"type":"command", "opcode":"free", "args":[null]}, {"type":"command", "opcode":"Attack", "args":[true]}]:
		await lab.build(ASTManager.from_dictionary(invalid))
		if component.start() or component.last_problems.is_empty():
			return "Invalid tool/type started"
	return null

func test_lab_release_unlink_and_component_exit_cancel_chase() -> Variant:
	victim.position.z = -7
	await _program()
	for mode: int in 3:
		if not component.start():
			return "Lifecycle start rejected"
		await _frames(3)
		if not movement.is_moving():
			return "Lifecycle did not enter real chase"
		match mode:
			0: component.unlink()
			1: actor.remove_child(component)
			2: lab.free()
		await _frames(3)
		if movement.is_moving() or component.state != "stopped" or component.get("_runner") != null:
			return "Cancellation failed mode " + str(mode)
		if mode == 1:
			actor.add_child(component)
		if mode < 2:
			component.link(component.get_path_to(lab))
	return null
