class_name CharacterAttack
extends Node3D
## 可攻击能力组件：挂在任意 [Character] 下面即可让角色会打人。
##
## [br][b]为什么是组件[/b]：同 [CharacterMovement]——能力用组件拼装，任意组合都能存在，
## 详见 [CharacterTraits]。
##
## [br][b]伤害由受击方结算[/b]（与本工程的 [Hitbox] 同一条约定）：本组件只做
## 「够不够得着」的判定与转交，真正扣血由 [method Character.take_hit] 执行，
## 于是无敌帧、倒地保护等规则只有一份实现。
##
## [br][b]距离口径[/b]：与视野一样只看水平面（XZ），不受身高差影响——
## 站在坡上 / 模型高矮不一都不会误判。
##
## can_attack / attack require the live Character.is_enemy relation; no line of sight
## requirement. contains / is_in_range / characters_in_range remain pure geometry.
## Direct Character.take_hit and Hitbox damage retain their existing policy.

## 命中时广播。[param landed] 为 false 表示够得着但没打进去（对方倒地 / 无敌帧）。
signal attacked(target: Character, landed: bool)

## 直接引用一块可复用的范围资源（.tres）。留空则用下面几个便捷参数现装一块。
## [br]想在多个组件 / 角色之间共享同一块范围时，把它指向 .tres 即可。
@export var range_geometry: CharacterRange
## Opt-in actual hurtbox XZ intersection; unsupported shapes fail closed.
@export var intersect_target_volume: bool = false
@export var yaw_offset_degrees: float = 0.0

## 用哪种形状（[member range_geometry] 为空时生效）。默认全向圆 = 旧行为，手感不变。
@export var range_shape: CharacterRange.Shape = CharacterRange.Shape.CIRCLE

## 圆 / 扇形的半径（米）。
@export var attack_range: float = 2.0:
	set(value):
		attack_range = maxf(value, 0.0)

## 扇形张角（度）。360 = 全向；默认 120° 是"正前方"的锥形。
@export var fov_degrees: float = 120.0:
	set(value):
		fov_degrees = clampf(value, 0.0, 360.0)

## 矩形范围在局部 XZ 上的尺寸（米，range_shape = BOX 时生效）。
@export var box_size: Vector2 = Vector2(2.0, 2.0)

## 区域中心相对角色原点的偏移（局部空间）：例如 (0, 0, -1) 表示整块范围向前挪 1 米。
@export var offset: Vector3 = Vector3.ZERO

## 每次攻击的 HP 伤害。
@export var damage: int = 10:
	set(value):
		damage = maxi(value, 0)

## 每次攻击的 sanity 伤害。
@export var sanity_damage: int = 0:
	set(value):
		sanity_damage = maxi(value, 0)

## Cooldown uses monotonic real seconds, like Character invulnerability.
@export var cooldown_seconds: float = 0.5:
	set(value):
		cooldown_seconds = maxf(value, 0.0)
var _ready_at_msec: int = 0
var _character: Character = null

func cooldown_remaining() -> float:
	return maxf(0.0, float(_ready_at_msec - Time.get_ticks_msec()) / 1000.0)

func is_ready() -> bool:
	return is_inside_tree() and _valid_character(_character) and not _character.is_downed and cooldown_remaining() <= 0.0

func can_attack(target: Character) -> bool:
	return is_ready() and is_instance_valid(target) and _character.is_enemy(target) and is_in_range(target) and (not target.is_downed or target.damageable_when_downed)

func _valid_character(value: Character) -> bool:
	return is_instance_valid(value) and value.is_inside_tree() and not value.is_queued_for_deletion()

## 按便捷参数现装的范围（range_geometry 为空时使用）。
var _local_range: CharacterRange = null


func _ready() -> void:
	_character = _resolve_character()
	if _character == null:
		push_warning("CharacterAttack: 没挂在 Character 下，攻击不会生效。")

# ------------------------------------------------------------------ 攻击

## 攻击 [param target]。返回 [b]true[/b] 表示这一下真的打进去了
## （在范围内，且对方没有处于无敌帧 / 倒地免伤状态）。
## 打不到自己：把自己当目标一律返回 false。
func attack(target: Character) -> bool:
	if not can_attack(target):
		return false
	# Consume before take_hit/signals to prevent reentrant attacks, including rejected hits.
	_ready_at_msec = Time.get_ticks_msec() + int(ceil(cooldown_seconds * 1000.0))
	# 受击方结算：伤害数值由本组件提供，规则（无敌帧 / 倒地）由对方决定
	var landed: bool = (target as Character).take_hit(damage, sanity_damage, _character)
	attacked.emit(target, landed)
	return landed

## 只是够得着吗（不结算伤害）。UI 画攻击范围提示、AI 选目标都用它。
## [br]语义 = 「目标在不在攻击范围这块几何区域里」，不是数值比较。
func is_in_range(target: Character) -> bool:
	if not _valid_character(_character) or not _valid_character(target) or target == _character:
		return false
	if intersect_target_volume:
		return geometry().intersects_collision_shape(target.hurtbox_shape, range_owner_transform())
	return contains_point(target.global_position)


## 世界坐标的点落在攻击范围内吗。几何判定全部委托给 [CharacterRange]，本组件不再自己算。
func contains_point(world_point: Vector3) -> bool:
	if _character == null:
		return false
	return geometry().contains_point(world_point, range_owner_transform())

## Shared by gameplay and renderer; component-local transforms do not move the range.
func range_owner_transform() -> Transform3D:
	return _character.global_transform if is_instance_valid(_character) else Transform3D.IDENTITY


## 当前生效的范围：优先用挂上来的 [member range_geometry]，否则按本组件的便捷参数现装一块
## （现装的那块缓存在组件里，改参数会立刻同步过去）。
func geometry() -> CharacterRange:
	if range_geometry != null:
		return range_geometry
	if _local_range == null:
		_local_range = CharacterRange.new()
	_local_range.shape = range_shape
	_local_range.radius = attack_range
	_local_range.fov_degrees = fov_degrees
	_local_range.box_size = box_size
	_local_range.offset = offset
	_local_range.yaw_offset_degrees = yaw_offset_degrees
	return _local_range


## Pure geometry alias for IN and renderers; ignores cooldown and downed state.
func contains(target: Character) -> bool:
	return is_in_range(target)


## 一行描述当前范围（几何与描述都在 [CharacterRange] 里，这里只转发）。
func describe_range() -> String:
	return geometry().describe()

## 攻击范围内最近的敌人并结算，返回被打的那个（范围内没人返回 null）。
func attack_nearest() -> Character:
	var nearest: Character = _nearest_in_range()
	if nearest != null:
		attack(nearest)
	return nearest

## 攻击范围内的所有角色（按距离升序）。
func characters_in_range() -> Array[Character]:
	var result: Array[Character] = []
	if _character == null or not is_inside_tree():
		return result
	for node: Node in get_tree().get_nodes_in_group(Character.GROUP_CHARACTER):
		var other: Character = node as Character
		if other != null and is_in_range(other):
			result.append(other)
	result.sort_custom(
		func(a: Character, b: Character) -> bool: return distance_to(a) < distance_to(b)
	)
	return result

## 与目标的水平（XZ）距离。
func distance_to(target: Character) -> float:
	if _character == null or target == null:
		return INF
	var from: Vector3 = _character.global_position
	var to: Vector3 = target.global_position
	return Vector2(to.x - from.x, to.z - from.z).length()

## 本组件服务的角色（可能为 null：没挂在 Character 下时）。
func get_character() -> Character:
	return _character

# ------------------------------------------------------------------ 内部

func _nearest_in_range() -> Character:
	var candidates: Array[Character] = characters_in_range()
	for candidate: Character in candidates:
		if _character.is_enemy(candidate):
			return candidate
	return null


## 沿父链找角色（角色自己身上可能还隔着别的节点）。
func _resolve_character() -> Character:
	var node: Node = get_parent()
	while node != null:
		var found: Character = node as Character
		if found != null:
			return found
		node = node.get_parent()
	return null
