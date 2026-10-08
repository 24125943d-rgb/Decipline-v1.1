extends Node

const DeciplineScript = preload("res://scripts/character_decipline.gd")
const LAB_SCRIPT_PATH: String = "res://scripts/block_lab.gd"
var _spawned: Array[Node] = []
# Keep PackedScene ownership until all instances are freed, including inherited scenes.
var _scenes: Array[PackedScene] = []

func after_each() -> void:
	for node in _spawned:
		if is_instance_valid(node):
			node.free()
	_spawned.clear()
	_scenes.clear()

func test_link_sync_compile_unlink() -> Variant:
	var holder := Node.new()
	_spawned.append(holder)
	add_child(holder)
	var lab: Node = load(LAB_SCRIPT_PATH).new()
	lab.name = "Lab"
	lab.build_on_ready = false
	lab.content_path = ^"Content"
	var content := VBoxContainer.new()
	content.name = "Content"
	lab.add_child(content)
	holder.add_child(lab)
	var component := DeciplineScript.new()
	holder.add_child(component)
	if component.validate().status != "skipped":
		return "Unlinked component must skip silently"
	if component.link(^"../Content"):
		return "Invalid target accepted"
	if not component.link(^"../Lab"):
		return "Real BlockLab link failed"
	if component.validate().status != "empty":
		return "Unbuilt lab must report empty"
	var manager_script: GDScript = load("res://BlockSystem/Core/ASTManager.gd") as GDScript
	var ast: RefCounted = manager_script.call("from_dictionary", {"type": "command", "opcode": "do_not_execute", "args": []}) as RefCounted
	await lab.build(ast)
	if component.get_linked_ast() == null:
		return "UI -> AST failed"
	if not component.validate().ok:
		return "Compile-only validation failed"
	lab.clear()
	if component.get_linked_ast() != null:
		return "Stale AST after clear"
	component.unlink()
	if component.get_linked_block_lab() != null or component.validate().status != "skipped":
		return "Unlink failed"
	return null

func _prefab_check_moved_to_isolated_suite() -> Variant:
	for path in ["res://scenes/character.tscn", "res://scenes/attribute_character.tscn"]:
		var scene: PackedScene = load(path) as PackedScene
		_scenes.append(scene)
		var character: Node = scene.instantiate()
		_spawned.append(character)
		var count: int = 0
		for child in character.get_children():
			if child is DeciplineScript:
				count += 1
				if not child.block_lab_path.is_empty():
					return "Prefab unexpectedly linked: " + path
		if count != 1:
			return "Expected one inherited Decipline: " + path
	return null
