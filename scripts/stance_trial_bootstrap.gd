extends Node
## Scene-local orchestration. Never replaces a Character script or auto-restarts a runner.
const PROGRAM_CHARACTERS = ["A", "B", "C"]
@export var autostart: bool = true
@export var preparation_timeout_seconds: float = 5.0
var state: String = "idle"
var diagnostics: PackedStringArray = []
var started_characters: PackedStringArray = []
var vision_ready: Dictionary = {}
var _components: Array[CharacterDecipline] = []
var _built: bool = false
var _elapsed: float = 0.0

func _ready() -> void:
	set_process(false)
	if autostart:
		prepare_and_start.call_deferred()

func prepare_and_start() -> void:
	if state != "idle":
		return
	state = "preparing"
	print("Stance trial: preparing strict BlockLab program and fresh vision snapshots.")
	for letter: String in PROGRAM_CHARACTERS:
		var lab: Node = get_node("../BlockLab" if letter == "B" else "../ContactBlockLab")
		var actor: Character = get_node("../Character" + letter) as Character
		var component: CharacterDecipline = actor.get_node("Decipline") as CharacterDecipline
		var vision: CharacterVision = actor.get_node("Vision") as CharacterVision
		if component == null or vision == null or not component.link(component.get_path_to(lab)):
			_fail("Character%s: missing component or BlockLab link failed." % letter)
			return
		_components.append(component)
		vision.view_updated.connect(_on_view_updated.bind(vision), CONNECT_ONE_SHOT)
		vision.request_update()
	set_process(true)
	_build()

func _build() -> void:
	for lab_name: String in ["BlockLab", "ContactBlockLab"]:
		var lab: Node = get_node("../" + lab_name)
		var data: Dictionary = CombatAIMock.get_character_program_ast() if lab_name == "BlockLab" else CombatAIMock.get_character_attach_program_ast()
		var ast: AST_Node = ASTManager.from_dictionary(data)
		var ui: Control = await lab.call("build", ast)
		if state != "preparing":
			return
		if ui == null:
			_fail(lab_name + " construction failed.")
			return
	_built = true

func _on_view_updated(_targets: Array, vision: CharacterVision) -> void:
	if vision.enabled and vision.owner_character != null:
		vision_ready[vision.get_parent().name] = true

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed > preparation_timeout_seconds:
		_fail("Preparation timed out: BlockLab or fresh Vision update unavailable.")
		return
	if not _built or vision_ready.size() != PROGRAM_CHARACTERS.size():
		return
	set_process(false)
	for component: CharacterDecipline in _components:
		var report: Dictionary = component.validate_for_character()
		if not report.ok:
			_fail("%s: strict validation failed: %s" % [component.get_parent().name, report.problems])
			return
	for component: CharacterDecipline in _components:
		var host: CharacterCombatHost = component.get_parent().get_node("CombatHost") as CharacterCombatHost
		host.chase_stop_policy = CharacterCombatHost.ChaseStopPolicy.ATTACK_RANGE if component.get_parent().name == "CharacterB" else CharacterCombatHost.ChaseStopPolicy.CONTACT
		if not component.start():
			_fail("%s: start rejected: %s" % [component.get_parent().name, component.last_problems])
			return
		started_characters.append(str(component.get_parent().name))
		print("Stance trial: %s started (%s)." % [component.get_parent().name, component.state])
	state = "started"
	print("Stance trial: only A/B/C independent runners started. No visible enemy means WHILE exits; no automatic restart.")

func _fail(message: String) -> void:
	state = "failed"
	diagnostics.append(message)
	set_process(false)
	for component: CharacterDecipline in _components:
		component.stop()
	push_warning("Stance trial: " + message)
