class_name CharacterDecipline
extends Node
## Explicit snapshot execution through an independent runner; never replaces Character scripts.
signal state_changed(state: String)
signal execution_error(problems: PackedStringArray)
signal completed(status: String)

@export var combat_host_path: NodePath = NodePath("")
@export var max_iterations: int = 0
var state: String = "idle"
var last_problems: PackedStringArray = []
var _runner: RefCounted = null
var _host: Node = null
var _lab: Node = null
var _generation: int = 0

func is_running() -> bool:
	return state == "running"

func _set_state(value: String) -> void:
	state = value
	state_changed.emit(value)

func _resolve_host() -> Node:
	var host_script: GDScript = load("res://scripts/character_combat_host.gd") as GDScript
	var character_script: GDScript = load("res://scripts/character.gd") as GDScript
	var character: Node = get_parent()
	if not is_instance_of(character, character_script):
		return null
	if not combat_host_path.is_empty():
		var explicit: Node = get_node_or_null(combat_host_path)
		return explicit if is_instance_of(explicit, host_script) and explicit.get_parent() == character else null
	for child: Node in character.get_children():
		if is_instance_of(child, host_script):
			return child
	var created: Node = host_script.new() as Node
	created.name = "CombatHost"
	character.add_child(created)
	return created

func _prepare() -> Dictionary:
	if not is_inside_tree() or get_linked_block_lab() == null:
		return {"ok": false, "status": "invalid", "problems": PackedStringArray(["A live linked BlockLab is required."])}
	var ast: RefCounted = get_linked_ast()
	if ast == null:
		return {"ok": false, "status": "empty", "problems": PackedStringArray(["BlockLab has no available AST."])}
	var host: Node = _resolve_host()
	if not is_instance_valid(host) or not host.is_inside_tree() or host.is_queued_for_deletion():
		return {"ok": false, "status": "invalid", "problems": PackedStringArray(["A live CombatHost on this Character is required."])}
	var contract: RefCounted = load("res://scripts/character_program_contract.gd").new() as RefCounted
	var source: String = contract.call("generate_strict", ast, host)
	var problems: PackedStringArray = contract.get("problems").duplicate()
	var script: GDScript = null
	if not source.is_empty():
		script = load("res://BlockSystem/Logic/ASTCompiler.gd").call("compile", source) as GDScript
		if script == null:
			problems.append("Generated program compilation failed.")
	return {"ok": script != null, "status": "valid" if script != null else "invalid", "problems": problems, "script": script, "host": host}

func validate_for_character() -> Dictionary:
	var report: Dictionary = _prepare()
	report.erase("script")
	report.erase("host")
	return report

## Returns acceptance immediately, not the eventual command result. Double start is rejected.
func start() -> bool:
	if is_running():
		return false
	var report: Dictionary = _prepare()
	last_problems = report.problems
	if not report.ok:
		_set_state("error")
		execution_error.emit(last_problems)
		completed.emit("error")
		return false
	_generation += 1
	_host = report.host
	_runner = report.script.new() as RefCounted
	_runner.set("target", _host)
	_runner.set("max_iterations", max_iterations)
	_lab = get_linked_block_lab()
	_lab.tree_exiting.connect(_host_exiting, CONNECT_ONE_SHOT)
	_host.tree_exiting.connect(_host_exiting, CONNECT_ONE_SHOT)
	_set_state("running")
	_execute(_runner, _generation)
	return true

func _execute(runner: RefCounted, token: int) -> void:
	await runner.call("execute")
	if token != _generation:
		return
	_release()
	_set_state("finished")
	completed.emit("finished")

func _release() -> void:
	if is_instance_valid(_lab) and _lab.tree_exiting.is_connected(_host_exiting):
		_lab.tree_exiting.disconnect(_host_exiting)
	_lab = null
	if is_instance_valid(_host) and _host.tree_exiting.is_connected(_host_exiting):
		_host.tree_exiting.disconnect(_host_exiting)
	_runner = null
	_host = null

func stop() -> void:
	if not is_running():
		return
	_generation += 1
	if _runner != null:
		_runner.call("stop")
		_runner.set("target", null)
	_release()
	_set_state("stopped")
	completed.emit("stopped")

func _host_exiting() -> void:
	stop()

func _exit_tree() -> void:
	stop()

# Resolve the lab type only when a link is inspected; unlinked character prefabs
# must not own the complete BlockSystem UI/compiler script dependency graph.
const BLOCK_LAB_SCRIPT_PATH: String = "res://scripts/block_lab.gd"
## 相对于此组件的 BlockLab 实例路径。空路径代表无关联，保持静默。
@export var block_lab_path: NodePath = NodePath(""):
	set(value):
		if block_lab_path != value:
			stop()
		block_lab_path = value

## 链接已有路径；失败时保留旧链接。
func link(path: NodePath) -> bool:
	if path.is_empty():
		return false
	var lab: Node = get_node_or_null(path)
	if not is_instance_of(lab, load(BLOCK_LAB_SCRIPT_PATH)):
		return false
	if block_lab_path != path:
		stop()
	block_lab_path = path
	return true

func unlink() -> void:
	stop()
	block_lab_path = NodePath("")

func get_linked_block_lab() -> Node:
	if block_lab_path.is_empty():
		return null
	var lab: Node = get_node_or_null(block_lab_path)
	return lab if is_instance_of(lab, load(BLOCK_LAB_SCRIPT_PATH)) else null

## 每次读取重新同步 UI -> AST，不缓存旧程序。
func get_linked_ast() -> RefCounted:
	var lab: Node = get_linked_block_lab()
	if lab == null:
		return null
	return lab.call("get_program_ast") as RefCounted

## 仅验证转译和 GDScript 编译；不保证运行时目标的方法/属性存在。
## 无链接时返回 skipped，无日志。报告不持有脚本或执行器。
func validate() -> Dictionary:
	if get_linked_block_lab() == null:
		return {"ok": false, "status": "skipped", "problems": PackedStringArray()}
	var ast: RefCounted = get_linked_ast()
	if ast == null:
		return {"ok": false, "status": "empty", "problems": PackedStringArray(["BlockLab has no available AST"])}
	# Keep the entire compiler graph outside the unlinked prefab's static dependencies.
	var compiler_script: GDScript = load("res://BlockSystem/Logic/ASTCompiler.gd") as GDScript
	var compiler: RefCounted = compiler_script.new() as RefCounted
	var source: String = str(compiler.call("generate_gdscript", ast))
	var problems: PackedStringArray = compiler.get("problems")
	problems = problems.duplicate()
	if not problems.is_empty():
		return {"ok": false, "status": "invalid", "problems": problems}
	if compiler_script.call("compile", source) == null:
		problems.append("Generated GDScript compilation failed")
	return {"ok": problems.is_empty(), "status": "valid" if problems.is_empty() else "invalid", "problems": problems}
