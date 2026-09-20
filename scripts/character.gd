class_name Character
extends CharacterBody3D
## 角色基类：3D 外观 + 受击判定 + HP / SAN 状态机。
##
## [br][b]外观[/b]：`Appearance/ModelRoot` 是模型挂点。把从 Blender 导出的 `.glb` /
## `.gltf` 场景拖进 [member appearance_model]，占位球体会被自动替换；模型自带的
## [AnimationPlayer] 会被自动接管，用 [method play_anim] 播放动画。
## [br][b]受击判定[/b]：`Hurtbox`（[Area3D]）默认是位于外观中心的球体，初始化时自动
## 对齐到外观包围盒的中心。换成胶囊 / 骨骼挂点 / 复合形状都不用改脚本，只要保持
## 节点名是 `Hurtbox`（或改 [member hurtbox_path]）——伤害由受击方结算。
## [br][b]属性[/b]：[member hp] / [member sanity] 的写入永远被夹在 0 ~ 上限之间，
## 不可能变成负数。
## [br][b]状态[/b]：HP 归零 → 倒地（[member is_downed]，全局可读的 flag，同时加入
## `"downed"` 组）；未倒地且 sanity 归零 → 混乱（[member is_confused]）。
## 倒地优先级高于混乱，且倒地期间默认不再吃伤害（见 [member damageable_when_downed]）。

# ------------------------------------------------------------------ 信号
## HP 变化（只在该值真的变了时发出）。
signal hp_changed(current: int, maximum: int)
## sanity 变化（只在该值真的变了时发出）。
signal sanity_changed(current: int, maximum: int)
## 状态切换：正常 / 混乱 / 倒地。
signal state_changed(previous: State, current: State)
## 进入倒地。
signal downed
## 从倒地恢复（被扶起 / 回血）。
signal revived
## 攻击真正生效时发出（被无敌帧或倒地状态挡掉的攻击不会发）。
signal hit_received(damage: int, sanity_damage: int, source: Node)

# ------------------------------------------------------------------ 枚举 / 常量
enum State {
	NORMAL, ## HP > 0 且 sanity > 0
	CONFUSED, ## 未倒地，但 sanity == 0
	DOWNED, ## HP == 0（优先于混乱）
}

## 所有角色的组，方便 `get_tree().get_nodes_in_group(&"character")`。
const GROUP_CHARACTER: StringName = &"character"
## 倒地的角色自动加入这个组，方便全局查询“现在谁倒着”。
const GROUP_DOWNED: StringName = &"downed"
## 攻击判定框的组名。Hurtbox 只会处理这个组里的 Area3D。
const GROUP_HITBOX: StringName = &"hitbox"

const LAYER_CHARACTER: int = 1 << 0 ## 角色身体（物理碰撞）
const LAYER_HURTBOX: int = 1 << 1 ## 受击判定
const LAYER_HITBOX: int = 1 << 2 ## 攻击判定
const LAYER_OBSTACLE: int = 1 << 3 ## 会挡住视野的不透明障碍物（墙、箱子…）

# ------------------------------------------------------------------ 导出属性
@export_group("属性 / Stats")
## HP 上限。
@export var max_hp: int = 100:
	set(value):
		max_hp = maxi(value, 1)
		_apply_hp(_hp)

## 当前 HP，最小值 0。归零即倒地。
@export var hp: int:
	get:
		return _hp
	set(value):
		_apply_hp(value)

## sanity 上限。
@export var max_sanity: int = 100:
	set(value):
		max_sanity = maxi(value, 1)
		_apply_sanity(_sanity)

## 当前 sanity，最小值 0。归零（且未倒地）即混乱。
@export var sanity: int:
	get:
		return _sanity
	set(value):
		_apply_sanity(value)

@export_group("倒地 / 复活")
## 倒地后是否仍会被打（倒地追击用）。
@export var damageable_when_downed: bool = false
## [method revive] 不传参时恢复的 HP；<= 0 表示回满。
@export var revive_hp: int = -1
## 受击后的无敌时间（秒），0 表示没有无敌帧。
@export var invulnerability_time: float = 0.0

@export_group("身体 / Body")
## 角色当前高度（米）：脚底到头顶。蹲下 / 变身时改这个值，身体碰撞体会跟着变，
## 视野的遮挡高度判定也用它（见 [CharacterVision]）。
@export var height: float = 1.8:
	set(value):
		height = maxf(value, 0.05)
		_apply_body_height()

@export_group("外观 / Appearance")
## 从 Blender 导出的 .glb / .gltf（导入后是一个 PackedScene）。留空则显示占位球体。
@export var appearance_model: PackedScene
## 可选：显式指定用哪个 AnimationPlayer。留空则优先用模型自带的，其次用场景里的。
@export var animation_player_path: NodePath

@export_group("受击判定 / Hurtbox")
## 受击判定节点路径。
@export var hurtbox_path: NodePath = ^"Hurtbox"
## 初始化时把受击判定移到外观包围盒中心（换成别的模型后不会跑偏）。
@export var recenter_hurtbox_on_appearance: bool = true
## 同时按外观尺寸缩放形状。注意：改的是形状资源本体，多个角色共用同一个场景文件时
## 需要把该形状设为 Local To Scene。
@export var fit_hurtbox_to_appearance: bool = false

# ------------------------------------------------------------------ 状态（只读）
## 全局 flag：HP 归零即 true。
var is_downed: bool = false
## 派生状态：未倒地 且 sanity == 0。
var is_confused: bool = false
## 当前状态（由 [member hp] / [member sanity] 推导，不要直接写）。
var state: State = State.NORMAL

# ------------------------------------------------------------------ 节点引用
@onready var appearance: Node3D = get_node_or_null(^"Appearance") as Node3D
@onready var model_root: Node3D = get_node_or_null(^"Appearance/ModelRoot") as Node3D
@onready var _placeholder: MeshInstance3D = get_node_or_null(
	^"Appearance/ModelRoot/PlaceholderSphere"
) as MeshInstance3D

## 受击判定（[Area3D]），可替换成任意形状。
var hurtbox: Area3D = null
## 受击判定里的碰撞形状，用于 [member fit_hurtbox_to_appearance]。
var hurtbox_shape: CollisionShape3D = null
## 身体碰撞体（胶囊），会跟着 [member height] 变。
var body_shape: CollisionShape3D = null
## 当前挂载的外观模型实例（从 [member appearance_model] 实例化而来）。
var model_instance: Node3D = null
## 实际使用的动画播放器（模型自带的，或场景里的）。
var animation_player: AnimationPlayer = null

# ------------------------------------------------------------------ 内部
var _hp: int = 100
var _sanity: int = 100
var _was_downed: bool = false
var _body_shape_is_local: bool = false
var _invulnerable_until_msec: int = 0

# ------------------------------------------------------------------ 生命周期
func _ready() -> void:
	add_to_group(GROUP_CHARACTER)
	_setup_body()
	_setup_appearance()
	_setup_hurtbox()
	_setup_animation_player()

	# 夹取属性。清空“上一次”状态，让信号和钩子在 _ready 之后重放一次，
	# 这样一开始就倒地 / 混乱的角色也能正确通知订阅者。
	_was_downed = false
	state = State.NORMAL
	_apply_hp(_hp)
	_apply_sanity(_sanity)
	_sync_down_group()
	hp_changed.emit(_hp, max_hp)
	sanity_changed.emit(_sanity, max_sanity)
	_on_character_ready()

# ------------------------------------------------------------------ 受击 API
## 统一受击入口（Hurtbox 命中和外部直接调用都走这里）。
## 返回 true 表示这次攻击真的生效了（没被无敌帧或倒地状态吃掉）。
func take_hit(damage: int, sanity_damage: int = 0, source: Node = null) -> bool:
	if is_downed and not damageable_when_downed:
		return false
	var now: int = Time.get_ticks_msec()
	if now < _invulnerable_until_msec:
		return false
	if invulnerability_time > 0.0:
		_invulnerable_until_msec = now + int(round(invulnerability_time * 1000.0))

	var hp_damage: int = maxi(damage, 0)
	var san_damage: int = maxi(sanity_damage, 0)
	take_damage(hp_damage)
	take_sanity_damage(san_damage)
	hit_received.emit(hp_damage, san_damage, source)
	return true

## 扣 HP。负数视为 0。
func take_damage(amount: int) -> void:
	_apply_hp(_hp - maxi(amount, 0))

## 回 HP，不会超过 [member max_hp]。
func heal(amount: int) -> void:
	_apply_hp(_hp + maxi(amount, 0))

## 扣 sanity。负数视为 0。
func take_sanity_damage(amount: int) -> void:
	_apply_sanity(_sanity - maxi(amount, 0))

## 回 sanity，不会超过 [member max_sanity]。
func restore_sanity(amount: int) -> void:
	_apply_sanity(_sanity + maxi(amount, 0))

## 扶起：HP 回到 > 0，倒地 flag 自动清除。sanity 不变。
## [param hp_amount] <= 0 时使用 [member revive_hp]（再 <= 0 则回满）。
func revive(hp_amount: int = 0) -> void:
	var target: int = hp_amount
	if target <= 0:
		target = revive_hp if revive_hp > 0 else max_hp
	_apply_hp(target)

# ------------------------------------------------------------------ 查询
func is_alive() -> bool:
	return not is_downed


## 头顶的世界坐标。约定角色原点在身体中心，所以头顶 = 原点 + 高度 / 2。
func get_head_position() -> Vector3:
	return global_position + Vector3.UP * height * 0.5


## 脚底的世界坐标。
func get_feet_position() -> Vector3:
	return global_position - Vector3.UP * height * 0.5


func is_normal() -> bool:
	return state == State.NORMAL


## "NORMAL" / "CONFUSED" / "DOWNED"，方便打日志。
func get_state_name() -> String:
	return String(State.keys()[state])

# ------------------------------------------------------------------ 外观 / 动画
## 运行时换模型（换装、换伙伴等）。
func set_appearance_model(model: PackedScene) -> void:
	appearance_model = model
	if not is_node_ready():
		return
	_setup_appearance()
	_setup_animation_player()
	if recenter_hurtbox_on_appearance:
		recenter_hurtbox()


## 播放模型自带（或场景里）的动画，成功返回 true。
func play_anim(animation: StringName, blend_time: float = -1.0) -> bool:
	if animation_player == null or not animation_player.has_animation(animation):
		return false
	animation_player.play(animation, blend_time)
	return true


func has_anim(animation: StringName) -> bool:
	return animation_player != null and animation_player.has_animation(animation)


## 播放器里所有可用的动画名，方便接状态机。
func get_anim_names() -> PackedStringArray:
	if animation_player == null:
		return PackedStringArray()
	return animation_player.get_animation_list()


# ------------------------------------------------------------------ 受击判定
## 把受击判定移到外观（模型包围盒）的中心。换模型后可以手动再调一次。
func recenter_hurtbox() -> void:
	if hurtbox == null:
		return
	var source: Node3D = model_root if model_root != null else appearance
	if source == null:
		return
	var box: AABB = _visual_aabb(source)
	var has_visual: bool = box.size != Vector3.ZERO
	var center: Vector3 = box.get_center() if has_visual else Vector3.ZERO
	hurtbox.global_position = source.global_transform * center
	if fit_hurtbox_to_appearance and has_visual:
		_fit_shape_to_size(box.size)

# ------------------------------------------------------------------ 子类钩子
## 进入某个状态时调用（[_ready] 之后才会触发）。
func _on_state_entered(_new_state: State) -> void:
	pass


## 进入倒地时调用。
func _on_downed() -> void:
	pass


## 从倒地恢复时调用。
func _on_revived() -> void:
	pass


## [_ready] 末尾调用，此时外观、受击判定、属性都已经就绪。
func _on_character_ready() -> void:
	pass

# ------------------------------------------------------------------ 内部实现
func _apply_hp(value: int) -> void:
	var clamped: int = clampi(value, 0, max_hp)
	var changed: bool = clamped != _hp
	_hp = clamped
	if changed and is_node_ready():
		hp_changed.emit(_hp, max_hp)
	_refresh_state()


func _apply_sanity(value: int) -> void:
	var clamped: int = clampi(value, 0, max_sanity)
	var changed: bool = clamped != _sanity
	_sanity = clamped
	if changed and is_node_ready():
		sanity_changed.emit(_sanity, max_sanity)
	_refresh_state()


## 由 HP / sanity 推导状态与 flag：倒地 = HP 为 0；混乱 = 未倒地 且 sanity 为 0。
func _refresh_state() -> void:
	var downed_now: bool = _hp <= 0
	var confused_now: bool = (not downed_now) and _sanity <= 0

	is_downed = downed_now
	is_confused = confused_now

	var new_state: State = State.NORMAL
	if downed_now:
		new_state = State.DOWNED
	elif confused_now:
		new_state = State.CONFUSED

	var previous: State = state
	if new_state != previous:
		state = new_state
		if is_node_ready():
			state_changed.emit(previous, new_state)
			_on_state_entered(new_state)

	if is_downed != _was_downed:
		_was_downed = is_downed
		_mark_downed(is_downed)


func _mark_downed(value: bool) -> void:
	if is_inside_tree():
		_sync_down_group()
	if not is_node_ready():
		return
	if value:
		downed.emit()
		_on_downed()
	else:
		revived.emit()
		_on_revived()


func _sync_down_group() -> void:
	if is_downed:
		if not is_in_group(GROUP_DOWNED):
			add_to_group(GROUP_DOWNED)
	elif is_in_group(GROUP_DOWNED):
		remove_from_group(GROUP_DOWNED)


func _setup_body() -> void:
	body_shape = get_node_or_null(^"BodyCollision") as CollisionShape3D
	if body_shape != null and body_shape.shape is CapsuleShape3D:
		# 先复制一份形状资源：改高度时不会波及共用同一份子资源的其它角色
		body_shape.shape = body_shape.shape.duplicate()
		_body_shape_is_local = true
	_apply_body_height()


func _apply_body_height() -> void:
	if body_shape == null or not (body_shape.shape is CapsuleShape3D):
		return
	if not _body_shape_is_local:
		body_shape.shape = (body_shape.shape as Shape3D).duplicate()
		_body_shape_is_local = true
	var capsule: CapsuleShape3D = body_shape.shape as CapsuleShape3D
	capsule.height = maxf(height, capsule.radius * 2.0 + 0.01)


func _setup_appearance() -> void:
	if model_root == null:
		push_warning("Character: 场景里缺少 Appearance/ModelRoot 节点，无法挂载外观模型。")
		return

	# 清掉上一次挂进去的模型（占位球体保留，只是隐藏）
	for child: Node in model_root.get_children():
		if child == _placeholder:
			continue
		child.queue_free()
	model_instance = null

	if appearance_model != null:
		var instance: Node = appearance_model.instantiate()
		if instance is Node3D:
			model_instance = instance as Node3D
			model_root.add_child(model_instance)
		else:
			push_warning("Character: appearance_model 的根节点不是 Node3D，已忽略。")
			instance.free()

	if _placeholder != null:
		_placeholder.visible = model_instance == null


func _setup_hurtbox() -> void:
	hurtbox = get_node_or_null(hurtbox_path) as Area3D
	if hurtbox == null:
		push_warning("Character: 找不到受击判定节点 '%s'。" % hurtbox_path)
		return

	hurtbox_shape = null
	for child: Node in hurtbox.get_children():
		if child is CollisionShape3D:
			hurtbox_shape = child as CollisionShape3D
			break

	if not hurtbox.area_entered.is_connected(_on_hurtbox_area_entered):
		hurtbox.area_entered.connect(_on_hurtbox_area_entered)

	if recenter_hurtbox_on_appearance:
		recenter_hurtbox()


func _setup_animation_player() -> void:
	var found: AnimationPlayer = null
	if not animation_player_path.is_empty():
		found = get_node_or_null(animation_player_path) as AnimationPlayer
	if found == null and model_instance != null:
		for node: Node in model_instance.find_children("*", "AnimationPlayer", true, false):
			found = node as AnimationPlayer
			if found != null:
				break
	if found == null:
		found = get_node_or_null(^"AnimationPlayer") as AnimationPlayer
	animation_player = found


## 外观（含所有子网格）在 source 局部空间里的包围盒。
func _visual_aabb(source: Node3D) -> AABB:
	var result: AABB = AABB()
	var found: bool = false
	var to_source_space: Transform3D = source.global_transform.affine_inverse()
	for node: Node in source.find_children("*", "VisualInstance3D", true, false):
		var visual: VisualInstance3D = node as VisualInstance3D
		if visual == null or not visual.is_visible_in_tree():
			continue
		var local_box: AABB = (to_source_space * visual.global_transform) * visual.get_aabb()
		result = local_box if not found else result.merge(local_box)
		found = true
	return result


func _fit_shape_to_size(box_size: Vector3) -> void:
	if hurtbox_shape == null or hurtbox_shape.shape == null:
		return
	var shape: Shape3D = hurtbox_shape.shape
	if shape is SphereShape3D:
		var sphere: SphereShape3D = shape as SphereShape3D
		sphere.radius = maxf(box_size.x, maxf(box_size.y, box_size.z)) * 0.5
	elif shape is CapsuleShape3D:
		var capsule: CapsuleShape3D = shape as CapsuleShape3D
		capsule.radius = maxf(box_size.x, box_size.z) * 0.5
		capsule.height = maxf(box_size.y, capsule.radius * 2.0 + 0.01)
	elif shape is BoxShape3D:
		(shape as BoxShape3D).size = box_size


func _on_hurtbox_area_entered(area: Area3D) -> void:
	if area == null or not area.is_in_group(GROUP_HITBOX):
		return
	var damage: int = _read_int(area, &"damage")
	var sanity_damage: int = _read_int(area, &"sanity_damage")
	if damage == 0 and sanity_damage == 0:
		return
	take_hit(damage, sanity_damage, area)


func _read_int(source: Object, property: StringName) -> int:
	var raw: Variant = source.get(property)
	if raw is int or raw is float:
		return int(raw)
	return 0
