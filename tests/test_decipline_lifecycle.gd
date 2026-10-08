extends Node
## Same-process regression: real UI/compile graph, then both character prefabs.
## Never instantiate or execute the generated program.
## Evidence (Godot 4.7.2 ed1daf0bf): run_tests: functional case PASS,
## process verdict FAIL: 16 resources still in use at exit.
## Reproduced outside test runner using existing probe:
## Godot --headless --verbose --path . --script res://tests/diagnose_decipline_exit.gd -- res://tests/test_decipline_lifecycle.gd test_compile_then_prefabs_and_release_target
## Probe: Test result <null>; 30 leaked ObjectDB instances, all listed as
## GDScript/GDScriptNativeClass (no live Node/PackedScene/model instances listed).
## Remaining resource paths under res://BlockSystem/:
## Core/{AST_Node,AST_Expression,AST_Statement,AST_Command,AST_BlockSchema,AST_TypeInference}.gd
## Art/Palettes/BlockPalette.gd
## Logic/{StatementFrame,SlotUI,ExpressionUI,BlockStyleSpec,CommandUI,BlockDragDrop,StatementUI,BlockSyncEngine,ASTCompiler}.gd
## Suspect, NOT proven: ASTCompiler owns inner ExecutionHighlighter script,
## whose highlight() references ASTCompiler.find_block_by_id (line 523),
## which references BlockSyncEngine/UI scripts. This is a script dependency
## cycle candidate, not evidence of a live highlighter (none was instantiated).
## Normal queued node destruction plus frame drains does not resolve exit leak.
## Prefabs are instantiated/freed off-tree, deliberately avoiding character AI.
const DeciplineScript: GDScript = preload("res://scripts/character_decipline.gd")
var _spawned: Array[Node] = []
var _scenes: Array[PackedScene] = []

func after_each() -> void:
	for node: Node in _spawned:
		if is_instance_valid(node):
			node.free()
	_spawned.clear()
	_scenes.clear()

func test_compile_then_prefabs_and_release_target() -> Variant:
	var holder: Node = Node.new()
	_spawned.append(holder)
	add_child(holder)
	var lab_script: GDScript = load("res://scripts/block_lab.gd") as GDScript
	var lab: Node = lab_script.new() as Node
	lab.name = "Lab"
	lab.set("build_on_ready", false)
	lab.set("content_path", ^"Content")
	var content: VBoxContainer = VBoxContainer.new()
	content.name = "Content"
	lab.add_child(content)
	holder.add_child(lab)
	var component: Node = DeciplineScript.new() as Node
	holder.add_child(component)
	if not component.call("link", ^"../Lab"):
		return "Real lab link failed"
	var manager: GDScript = load("res://BlockSystem/Core/ASTManager.gd") as GDScript
	var ast: RefCounted = manager.call("from_dictionary", {"type": "command", "opcode": "do_not_execute", "args": []}) as RefCounted
	var ui: Control = await lab.call("build", ast) as Control
	if ui == null or component.call("get_linked_ast") == null:
		return "Real UI build/sync failed"
	var report: Dictionary = component.call("validate")
	if not report.get("ok", false) or report.get("status") != "valid":
		return "Compile-only validation failed: " + str(report)
	# Keep the built lab alive while loading inherited PackedScenes in this process.
	for path: String in ["res://scenes/character.tscn", "res://scenes/attribute_character.tscn"]:
		var scene: PackedScene = load(path) as PackedScene
		_scenes.append(scene)
		var character: Node = scene.instantiate()
		_spawned.append(character)
		var count: int = 0
		for child: Node in character.get_children():
			if is_instance_of(child, DeciplineScript):
				count += 1
				if not (child.get("block_lab_path") as NodePath).is_empty():
					return "Prefab unexpectedly linked: " + path
				var skipped: Dictionary = child.call("validate")
				if skipped.get("status") != "skipped":
					return "Unlinked prefab validation not skipped: " + path
		character.free()
		if count != 1:
			return "Expected one inherited component: " + path
	_scenes.clear()
	lab.call("clear")
	if component.call("get_linked_ast") != null:
		return "Clear retained AST"
	lab.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(lab) or is_instance_valid(ui):
		return "Queued lab/UI destruction did not complete"
	if component.call("get_linked_block_lab") != null or component.call("get_linked_ast") != null:
		return "Freed target returned a stale object"
	report = component.call("validate")
	if report.get("status") != "skipped":
		return "Freed target validation not skipped"
	component.call("unlink")
	component.call("unlink")
	if not (component.get("block_lab_path") as NodePath).is_empty():
		return "Idempotent unlink failed"
	ast = null
	manager = null
	lab_script = null
	holder.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(holder) or is_instance_valid(component):
		return "Holder/component destruction did not complete"
	print("Lifecycle evidence: UI build + compile + both prefabs + deferred target/holder release completed; no generated program executed.")
	return null
