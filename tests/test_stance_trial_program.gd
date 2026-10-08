extends Node
var _scene: PackedScene = null
var _trial: Node = null
var _runner_ids: Array[int] = []

func after_each() -> void:
	if is_instance_valid(_trial):
		_trial.free()
	_trial = null
	_scene = null
	_runner_ids.clear()

func _spawn(automatic: bool) -> Node:
	_scene = load("res://scenes/stance_trial.tscn") as PackedScene
	_trial = _scene.instantiate()
	var bootstrap: Node = _trial.get_node("AIBootstrap")
	bootstrap.set("autostart", automatic)
	for letter: String in ["A", "B", "C", "D", "E", "F", "G"]:
		var component: CharacterDecipline = _trial.get_node("Character" + letter + "/Decipline") as CharacterDecipline
		component.state_changed.connect(_record_runner.bind(component))
	add_child(_trial)
	return bootstrap

func _record_runner(value: String, component: CharacterDecipline) -> void:
	if value == "running":
		var runner: RefCounted = component.get("_runner") as RefCounted
		if runner != null:
			_runner_ids.append(runner.get_instance_id())

func test_disabled_autostart_has_no_execution_side_effects() -> Variant:
	var bootstrap: Node = _spawn(false)
	for frame: int in 5:
		await get_tree().process_frame
	if bootstrap.get("state") != "idle" or not _runner_ids.is_empty():
		return "Disabled autostart executed AI"
	return _check_unprogrammed_enemies()

func _check_unprogrammed_enemies() -> Variant:
	var ally: Character = _trial.get_node("CharacterA") as Character
	for letter: String in ["D", "E", "F", "G"]:
		var actor: Character = _trial.get_node("Character" + letter) as Character
		var component: CharacterDecipline = actor.get_node("Decipline") as CharacterDecipline
		if not component.block_lab_path.is_empty() or component.get_linked_block_lab() != null or component.get_linked_ast() != null:
			return "Enemy still has a program link: " + letter
		if component.is_running() or component.state != "idle" or component.get("_runner") != null:
			return "Enemy has execution state or runner: " + letter
		if actor.get_script() != load("res://scripts/attribute_character.gd") or actor.stance != -1 or not ally.is_enemy(actor):
			return "Enemy script or hostility changed: " + letter
		for component_name: String in ["Vision", "Movement", "Attack", "Hurtbox"]:
			if not actor.has_node(component_name):
				return "Enemy lost capability: " + letter + "/" + component_name
	return null

func test_strict_assembly_and_actual_three_starts() -> Variant:
	var bootstrap: Node = _spawn(false)
	bootstrap.call("prepare_and_start")
	for frame: int in 600:
		if bootstrap.get("state") in ["started", "failed"]:
			break
		await get_tree().process_frame
	if bootstrap.get("state") != "started":
		return "Bounded startup failed: " + str(bootstrap.get("diagnostics"))
	if _runner_ids.size() != 3 or bootstrap.get("vision_ready").size() != 3:
		return "Did not observe three real running transitions after fresh Vision updates"
	if bootstrap.get("started_characters") != PackedStringArray(["CharacterA", "CharacterB", "CharacterC"]):
		return "Started characters were not exactly A/B/C"
	var enemy_problem: Variant = _check_unprogrammed_enemies()
	if enemy_problem != null:
		return enemy_problem
	var host_ids: Array[int] = []
	var command_count: int = 0
	for letter: String in ["A", "B", "C"]:
		var actor: Character = _trial.get_node("Character" + letter) as Character
		var component: CharacterDecipline = actor.get_node("Decipline") as CharacterDecipline
		var host: CharacterCombatHost = actor.get_node("CombatHost") as CharacterCombatHost
		var count: int = 0
		for child: Node in actor.get_children():
			if child is CharacterDecipline:
				count += 1
		if count != 1 or actor.get_script() != load("res://scripts/attribute_character.gd"):
			return "Duplicate Decipline or replaced character script: " + letter
		if component.get_linked_block_lab() != _trial.get_node("BlockLab" if letter == "B" else "ContactBlockLab") or not component.validate_for_character().ok:
			return "Strict link/validation failed: " + letter
		var contract: CharacterProgramContract = CharacterProgramContract.new()
		var source: String = contract.generate_strict(component.get_linked_ast() as AST_Node, host)
		var condition: String = "attack_range" if letter == "B" else 'target.call("attach",'
		if host.chase_stop_policy != (CharacterCombatHost.ChaseStopPolicy.ATTACK_RANGE if letter == "B" else CharacterCombatHost.ChaseStopPolicy.CONTACT):
			return "Wrong chase policy: " + letter
		for expected: String in ["program_visible_exists", "program_visible_closest", condition, "program_attack", "program_chase"]:
			if not source.contains(expected):
				return "Missing strict source mapping: " + expected
		if host_ids.has(host.get_instance_id()) or host.character != actor:
			return "Shared or incorrect host"
		host_ids.append(host.get_instance_id())
		command_count += host.attack_commands + host.chase_commands
		if actor.stance != (1 if letter in ["A", "B", "C"] else -1):
			return "Changed stance"
	for index: int in _runner_ids.size():
		if _runner_ids.count(_runner_ids[index]) != 1:
			return "Shared runner"
	if command_count == 0:
		return "Started but no actual decisions observed"
	print("Stance trial verified: three strict links, D/E/F/G unlinked and idle, unique runners/hosts, actual commands=", command_count)
	return null
