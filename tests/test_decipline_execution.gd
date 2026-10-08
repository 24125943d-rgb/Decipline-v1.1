extends "res://tests/test_character_decipline.gd"

func test_strict_execution_snapshot_stop_and_host_exit() -> Variant:
	var holder: Node = Node.new()
	_spawned.append(holder)
	add_child(holder)
	var character: Node = load("res://scripts/character.gd").new()
	holder.add_child(character)
	for path: String in ["character_attack", "character_movement", "character_vision"]:
		character.add_child(load("res://scripts/" + path + ".gd").new())
	var component: Node = DeciplineScript.new()
	character.add_child(component)
	var original: Script = character.get_script()
	var lab: Node = load(LAB_SCRIPT_PATH).new()
	lab.name = "Lab"
	lab.build_on_ready = false
	lab.content_path = ^"Content"
	var content: VBoxContainer = VBoxContainer.new()
	content.name = "Content"
	lab.add_child(content)
	holder.add_child(lab)
	component.link(component.get_path_to(lab))
	if component.is_running() or component.state != "idle":
		return "Must default to idle."
	if component.start() or component.state != "error":
		return "Empty program accepted."
	var manager: GDScript = load("res://BlockSystem/Core/ASTManager.gd")
	await lab.build(manager.from_dictionary({"type":"statement", "loop":true, "body":[{"type":"command", "opcode":"Chase", "args":[null]}, {"type":"command", "opcode":"Attack", "args":[null]}]}))
	component.max_iterations = 2
	if not component.start() or component.start():
		return "Start or double-start policy failed."
	var host: Node = character.get_node("CombatHost")
	lab.clear()
	for index: int in 5:
		await get_tree().process_frame
	if component.state != "finished" or host.chase_commands != 2:
		return "Bounded snapshot did not finish."
	if character.get_script() != original:
		return "Character script was replaced."
	await lab.build(manager.from_dictionary({"type":"statement", "loop":true, "body":[]}))
	component.max_iterations = 0
	component.start()
	component.stop()
	component.start()
	await get_tree().process_frame
	if not component.is_running():
		return "Old coroutine overwrote restart."
	host.free()
	await get_tree().process_frame
	if component.state != "stopped" or component.get("_runner") != null:
		return "Host release did not stop and release runner."
	return null
