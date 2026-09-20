extends VisionTrial
## 试用场景的交互：[b]鼠标左键点击角色 → 获取并显示该角色当前的视野[/b]。
##
## 它是场景抽象类 [VisionTrial] 的派生：角色 / 障碍物列表、相机初始机位都由基类管理，
## 这里只加"点击切换视野 + HUD 读数"这一层交互。
##
## [br]· 点到角色的[b]身体[/b]或它的[b]受击判定[/b]（Area3D）都算命中；点到地面 / 障碍物则不改当前选择。
## [br]· 选取发生在[b]按下[/b]的瞬间，所以按下后继续拖动（摄影机的左键平移）不会改变选择结果。
## [br]· 切换时只把被选中角色的 [VisionAreaRenderer] 打开，其它角色的关掉，
##   于是画面里始终只有一份"当前视野"（射线多边形 + 贴花 + 目标连线）。
## [br]· 左上角 HUD 实时显示：当前角色的视野参数，以及它此刻看得见谁。
##
## [br][b]前置[/b]：角色要挂 [CharacterVision]（判定）和 [VisionAreaRenderer]（可视化）；
## 本脚本只负责"切换在看谁"，不参与判定。

@export_group("接线 / Wiring")
## 用来做屏幕射线投射的相机：沿用基类的 [member VisionTrial.camera_path]。
## 点击射线要打中哪些层：默认角色身体 + 受击判定。
@export_flags_3d_physics var click_mask: int = Character.LAYER_CHARACTER | Character.LAYER_HURTBOX
## 开局默认选中的角色（留空则不选，等玩家点）。
@export var initial_selection: NodePath = ^"CharacterA"
## 屏幕射线的最大长度。
@export var click_range: float = 500.0

@export_group("HUD")
## 是否显示左上角的视野读数。
@export var show_hud: bool = true
@export_range(0.02, 2.0, 0.01) var hud_refresh_interval: float = 0.15

## 当前正在查看其视野的角色。
var selected: Character = null

var _camera: Camera3D = null
var _label: Label = null
var _elapsed: float = 0.0
## 场景里所有"可被查看"的角色（挂了 VisionArea 的）。
var _candidates: Array[Character] = []

# ------------------------------------------------------------------ 生命周期
func _ready() -> void:
	super()  # 先让 VisionTrial 收好角色 / 障碍物列表和相机初始机位
	_camera = get_node_or_null(camera_path) as Camera3D
	if _camera == null:
		push_warning("VisionTrialSelector: 找不到 Camera3D，点击选取不可用。")
	_collect_candidates()
	if show_hud:
		_build_hud()
	select_character(get_node_or_null(initial_selection) as Character)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		select_at_screen(mouse.position)


func _physics_process(delta: float) -> void:
	if _label == null:
		return
	_elapsed += delta
	if _elapsed < hud_refresh_interval:
		return
	_elapsed = 0.0
	_update_hud()

# ------------------------------------------------------------------ 公开 API
## 用屏幕坐标选取角色（鼠标位置，或者自己造一个 Vector2 都行）。
## 命中角色返回它；打到别的东西 / 空处返回 null。
func select_at_screen(screen_position: Vector2) -> Character:
	if _camera == null:
		return null
	var space: PhysicsDirectSpaceState3D = _camera.get_world_3d().direct_space_state
	if space == null:
		return null
	var from: Vector3 = _camera.project_ray_origin(screen_position)
	var to: Vector3 = from + _camera.project_ray_normal(screen_position) * click_range
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, click_mask)
	query.collide_with_areas = true  # 受击判定是 Area3D，点在球体边缘也能选中
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return null
	var character: Character = character_of(hit.get("collider"))
	if character == null:
		return null
	select_character(character)
	return character


## 把"当前视野"切换到某个角色。
func select_character(character: Character) -> void:
	if character == null:
		return
	selected = character
	for candidate: Character in _candidates:
		var area: Node = candidate.get_node_or_null(^"VisionArea")
		if area != null:
			area.set("enabled", candidate == character)
	_update_hud()
	print(_describe(character))


## 从射线命中的对象反查角色：可能是角色本体，也可能是它的受击判定。
func character_of(collider: Variant) -> Character:
	var node: Node = collider as Node
	if node == null:
		return null
	var direct: Character = node as Character
	if direct != null:
		return direct
	return node.get_parent() as Character


## 某个角色此刻看得见谁（名字列表）。
func visible_names(character: Character) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	if character == null:
		return names
	var vision: CharacterVision = character.get_node_or_null(^"Vision") as CharacterVision
	if vision == null:
		return names
	for target: Character in vision.visible_characters:
		names.append(String(target.name))
	return names

# ------------------------------------------------------------------ 内部
## 可被查看的角色 = 基类收进来的角色里，挂了 [VisionAreaRenderer] 的那些。
func _collect_candidates() -> void:
	_candidates.clear()
	for character: Character in characters:
		if character.get_node_or_null(^"VisionArea") != null:
			_candidates.append(character)


func _describe(character: Character) -> String:
	var vision: CharacterVision = character.get_node_or_null(^"Vision") as CharacterVision
	if vision == null:
		return "%s：没有挂视野组件" % character.name
	var names: PackedStringArray = visible_names(character)
	return "当前视野：%s（%.0f° / %.1f m）→ 看得见 %d 个角色：%s" % [
		character.name,
		vision.fov_degrees,
		vision.view_radius,
		names.size(),
		"（无）" if names.is_empty() else ", ".join(names),
	]


func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	_label = Label.new()
	_label.name = "VisionReadout"
	_label.position = Vector2(18, 14)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 别把点击吃掉
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(0.92, 1.0, 0.92))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_label)
	_update_hud()


func _update_hud() -> void:
	if _label == null:
		return
	if selected == null:
		_label.text = "左键点击一个角色，查看它当前的视野"
		return
	_label.text = "%s\n左键点击其它角色可切换视野" % _describe(selected)
