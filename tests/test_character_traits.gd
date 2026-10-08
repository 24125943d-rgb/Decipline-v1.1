extends Node
## 角色能力（trait）测试：可移动 / 可攻击组件，以及「多重继承」的实际效果。
##
## 运行器约定：extends Node，方法名以 test_ 开头，返回 null = 通过、字符串 = 失败原因。
##
## GDScript 不支持多继承，所以「有属性 + 会走 + 会打」是用组件拼出来的（见 CharacterTraits）。
## 本文件重点验证：
##   · 两个预设子类天生带对应组件，参数转发正确
##   · add_trait 幂等、可摘除
##   · 【核心】AttributeCharacter 装上移动 + 攻击后，三种能力同时可用
##   · 移动真的发生位移（逐物理帧）、walk() 走完指定距离、撞墙会停下
##   · 攻击只在范围内生效、不会打自己、够得着但打不进去（倒地）时如实返回 false

const CHARACTER_SCENE: PackedScene = preload("res://scenes/character.tscn")
const MOVABLE_SCENE: PackedScene = preload("res://scenes/movable_character.tscn")
const ATTACK_SCENE: PackedScene = preload("res://scenes/attack_character.tscn")
const ATTRIBUTE_SCENE: PackedScene = preload("res://scenes/attribute_character.tscn")

var _failures: PackedStringArray = PackedStringArray()
var _spawned: Array[Node] = []


func before_each() -> void:
	_failures.clear()


func after_each() -> void:
	for node: Node in _spawned:
		if is_instance_valid(node):
			node.free()
	_spawned.clear()

# ------------------------------------------------------------------ 装配与查询
func test_plain_character_has_no_traits() -> Variant:
	var c: Character = _spawn_character()
	_check_eq(CharacterTraits.active_traits(c), PackedStringArray(), "普通角色什么能力都没有")
	_check(not CharacterTraits.has_trait(c, CharacterTraits.TRAIT_MOVEMENT), "没有移动能力")
	_check(CharacterTraits.movement_of(c) == null, "取不到移动组件")
	_check(CharacterTraits.get_trait(c, &"nope") == null, "未知能力名返回 null")
	_check(CharacterTraits.get_trait(null, CharacterTraits.TRAIT_ATTACK) == null, "null 角色返回 null")
	return _verdict("test_plain_character_has_no_traits")


func test_movable_character_ships_with_movement() -> Variant:
	var unit: MovableCharacter = MOVABLE_SCENE.instantiate() as MovableCharacter
	add_child(unit)
	_spawned.append(unit)
	_check(unit is Character, "可移动角色仍然是 Character")
	_check_eq(
		CharacterTraits.active_traits(unit), PackedStringArray(["movement"]),
		"天生带移动能力"
	)
	var movement: CharacterMovement = unit.get_movement()
	_check(movement != null, "组件挂上了")
	if movement == null:
		return _verdict("test_movable_character_ships_with_movement")
	_check_eq(movement.get_character(), unit, "组件认得自己的角色")
	# 参数转发：改角色上的值要落到组件里
	unit.speed = 7.5
	_check_eq(movement.speed, 7.5, "速度转发到组件")
	_check_eq(unit.speed, 7.5, "读回来也是同一个值")
	unit.speed = -3.0
	_check_eq(unit.speed, 0.0, "速度不允许为负")
	return _verdict("test_movable_character_ships_with_movement")


func test_attack_character_ships_with_attack() -> Variant:
	var unit: AttackCharacter = ATTACK_SCENE.instantiate() as AttackCharacter
	add_child(unit)
	_spawned.append(unit)
	_check_eq(
		CharacterTraits.active_traits(unit), PackedStringArray(["attack"]), "天生带攻击能力"
	)
	var attack: CharacterAttack = unit.get_attack()
	_check(attack != null, "组件挂上了")
	if attack == null:
		return _verdict("test_attack_character_ships_with_attack")
	unit.attack_range = 4.5
	unit.damage = 12
	unit.sanity_damage = 3
	_check_eq(attack.attack_range, 4.5, "攻击距离转发到组件")
	_check_eq(attack.damage, 12, "伤害转发到组件")
	_check_eq(attack.sanity_damage, 3, "sanity 伤害转发到组件")
	unit.attack_range = -1.0
	_check_eq(unit.attack_range, 0.0, "攻击距离不允许为负")
	return _verdict("test_attack_character_ships_with_attack")


func test_add_trait_is_idempotent() -> Variant:
	var c: Character = _spawn_character()
	var before: int = c.get_child_count()
	var first: Node = CharacterTraits.add_trait(c, CharacterTraits.TRAIT_MOVEMENT)
	var second: Node = CharacterTraits.add_trait(c, CharacterTraits.TRAIT_MOVEMENT)
	_check(first != null, "装上了移动组件")
	_check_eq(first, second, "重复装配返回同一个组件")
	_check_eq(c.get_child_count(), before + 1, "只多挂了一个组件")
	_check(CharacterTraits.remove_trait(c, CharacterTraits.TRAIT_MOVEMENT), "能摘掉能力")
	_check(not CharacterTraits.has_trait(c, CharacterTraits.TRAIT_MOVEMENT), "摘掉后查不到了")
	_check(not CharacterTraits.remove_trait(c, CharacterTraits.TRAIT_MOVEMENT), "重复摘除返回 false")
	return _verdict("test_add_trait_is_idempotent")


## 【核心用例】GDScript 单继承 → 用组件拼出「有属性 + 会走 + 会打」
func test_attribute_character_can_gain_every_trait() -> Variant:
	var hero: AttributeCharacter = _spawn_attribute(Vector3(0, 0.9, 0))
	var victim: AttackCharacter = _spawn_attack(Vector3(1.0, 0.9, 0))
	hero.stance = 1
	victim.stance = -1
	CharacterTraits.add_trait(hero, CharacterTraits.TRAIT_MOVEMENT)
	CharacterTraits.add_trait(hero, CharacterTraits.TRAIT_ATTACK)
	CharacterTraits.add_trait(hero, CharacterTraits.TRAIT_VISION)
	_check_eq(
		CharacterTraits.active_traits(hero),
		PackedStringArray(["vision", "movement", "attack"]),
		"一个角色同时拥有三种能力"
	)
	# 1) 属性照旧
	hero.strength = 14
	_check_eq(hero.get_attribute(AttributeCharacter.ATTR_STR), 14, "六项属性仍然可用")
	# 2) 会打
	var attack: CharacterAttack = CharacterTraits.attack_of(hero)
	_check(attack.can_attack(victim), "攻击组件认得范围内的目标")
	var before_hp: int = victim.hp
	_check(attack.attack(victim), "攻击打进去了")
	_check_eq(victim.hp, before_hp - attack.damage, "受击方扣血（伤害由受击方结算）")
	# 3) 会走
	var movement: CharacterMovement = CharacterTraits.movement_of(hero)
	_check(movement != null, "移动组件也在")
	if movement != null:
		movement.move(Vector3.BACK)
		_check(movement.is_moving(), "开始移动")
		_check_eq(hero.velocity, Vector3(0, 0, movement.speed), "速度按方向 × 速度设置")
		movement.stop()
		_check_eq(hero.velocity, Vector3.ZERO, "停下后速度清零")
	# 4) 视野也在（同一个角色，三套组件互不干扰）
	_check(CharacterTraits.vision_of(hero) != null, "视野组件也在")
	return _verdict("test_attribute_character_can_gain_every_trait")

# ------------------------------------------------------------------ 移动
func test_move_normalizes_direction() -> Variant:
	var unit: MovableCharacter = _spawn_movable(Vector3.ZERO)
	var movement: CharacterMovement = unit.get_movement()
	_check(movement != null, "有移动组件")
	if movement == null:
		return _verdict("test_move_normalizes_direction")
	movement.move(Vector3(10.0, 0.0, 0.0))
	_check_eq(movement.get_direction(), Vector3.RIGHT, "方向被归一化成单位向量")
	_check(movement.is_moving(), "正在移动")
	movement.move(Vector3.ZERO)
	_check(not movement.is_moving(), "零向量等于停下")
	_check_eq(unit.get_direction(), Vector3.ZERO, "子类转发查询也对")
	return _verdict("test_move_normalizes_direction")


func test_move_actually_displaces_over_physics_frames() -> Variant:
	var unit: MovableCharacter = _spawn_movable(Vector3.ZERO)
	unit.speed = 3.0
	var start: Vector3 = unit.global_position
	unit.move(Vector3.RIGHT)
	var frames: int = 10
	for _i: int in frames:
		await get_tree().physics_frame
	unit.stop()
	var travelled: float = start.distance_to(unit.global_position)
	var delta: float = unit.get_physics_process_delta_time()
	var expected: float = unit.speed * float(frames) * delta
	_check(travelled > 0.0, "确实动起来了（%.4f 米）" % travelled)
	_check(
		travelled > expected * 0.7 and travelled < expected * 1.3,
		"位移符合 速度 × 帧数 × 物理帧长（实际 %.4f，期望约 %.4f）" % [travelled, expected]
	)
	_check(
		unit.global_position.y == 0.0, "只走水平方向，y 不变（本组件不做重力）"
	)
	return _verdict("test_move_actually_displaces_over_physics_frames")


func test_walk_travels_the_requested_distance_forward() -> Variant:
	var unit: MovableCharacter = _spawn_movable(Vector3.ZERO)
	unit.speed = 5.0
	var walked: float = await unit.walk(2.0)
	_check(
		absf(walked - 2.0) < 0.2,
		"走完 2 米（实际 %.3f）" % walked
	)
	_check(
		absf(unit.global_position.z + 2.0) < 0.2,
		"默认朝正前方 -Z（z = %.3f）" % unit.global_position.z
	)
	_check(not unit.is_moving(), "走完自动停下")
	return _verdict("test_walk_travels_the_requested_distance_forward")


func test_walk_supports_direction_and_backwards() -> Variant:
	var unit: MovableCharacter = _spawn_movable(Vector3.ZERO)
	await unit.walk(-1.0)
	_check(unit.global_position.z > 0.5, "负距离 = 后退（z = %.3f）" % unit.global_position.z)
	await unit.walk(1.5, Vector3.RIGHT)
	_check(unit.global_position.x > 1.0, "可以指定方向走（x = %.3f）" % unit.global_position.x)
	return _verdict("test_walk_supports_direction_and_backwards")


func test_walk_stops_at_an_obstacle() -> Variant:
	var unit: MovableCharacter = _spawn_movable(Vector3(0, 0.9, 0))
	var wall: StaticBody3D = StaticBody3D.new()
	wall.collision_layer = Character.LAYER_CHARACTER  # 与角色的 collision_mask 对上才算实心
	wall.collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(4.0, 4.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	_spawned.append(wall)
	wall.global_position = Vector3(0, 0.9, -3.0)  # 正前方 3 米
	await get_tree().physics_frame
	var travelled: float = await unit.walk(10.0)
	_check(travelled < 5.0, "被墙挡下，没走满 10 米（实际 %.2f）" % travelled)
	_check(travelled > 1.0, "但确实往前走了（实际 %.2f）" % travelled)
	_check(unit.global_position.z > -3.0, "停在墙前（z = %.2f）" % unit.global_position.z)
	return _verdict("test_walk_stops_at_an_obstacle")

# ------------------------------------------------------------------ 攻击
func test_attack_lands_only_within_range() -> Variant:
	var attacker: AttackCharacter = _spawn_attack(Vector3.ZERO)
	attacker.attack_range = 2.0
	attacker.damage = 15
	attacker.sanity_damage = 5
	var near: Character = _spawn_character(Vector3(1.0, 0.0, 0.0))
	var far: Character = _spawn_character(Vector3(9.0, 0.0, 0.0))
	attacker.stance = 1
	near.stance = -1
	far.stance = -1
	_check(attacker.can_attack(near), "1 米内够得着")
	_check(not attacker.can_attack(far), "9 米外够不着")
	var near_hp: int = near.hp
	var near_sanity: int = near.sanity
	var far_hp: int = far.hp
	_check(attacker.attack(near), "近处这一下打进去了")
	_check_eq(near.hp, near_hp - 15, "扣了 15 点 HP")
	_check_eq(near.sanity, near_sanity - 5, "扣了 5 点 sanity（与 HP 一起由受击方结算）")
	_check(not attacker.attack(far), "远处那一下没打进去")
	_check_eq(far.hp, far_hp, "远处目标毫发无损")
	return _verdict("test_attack_lands_only_within_range")


func test_attack_never_hits_self() -> Variant:
	var attacker: AttackCharacter = _spawn_attack(Vector3.ZERO)
	_check(not attacker.can_attack(attacker), "自己不算目标")
	_check(not attacker.attack(attacker), "打自己不会生效")
	_check_eq(attacker.hp, attacker.max_hp, "自己没掉血")
	_check(not attacker.can_attack(null), "null 目标返回 false")
	return _verdict("test_attack_never_hits_self")


func test_attack_nearest_picks_the_closest() -> Variant:
	var attacker: AttackCharacter = _spawn_attack(Vector3.ZERO)
	attacker.attack_range = 10.0
	attacker.damage = 7
	var mid: Character = _spawn_character(Vector3(4.0, 0.0, 0.0))
	var near: Character = _spawn_character(Vector3(2.0, 0.0, 0.0))
	var close: Character = _spawn_character(Vector3(1.0, 0.0, 0.0))
	attacker.stance = 1
	mid.stance = -1
	near.stance = -1
	close.stance = -1
	var in_range: Array[Character] = attacker.characters_in_range()
	_check_eq(in_range.size(), 3, "范围内三个目标")
	if in_range.size() == 3:
		_check_eq(in_range[0], close, "按距离升序，最近的在最前")
	var hit: Character = attacker.attack_nearest()
	_check_eq(hit, close, "打到的是最近的那个")
	if hit != null:
		_check_eq(hit.hp, hit.max_hp - 7, "最近的目标掉了血")
	_check_eq(near.hp, near.max_hp, "其它目标没被波及")
	_check_eq(mid.hp, mid.max_hp, "其它目标没被波及")
	return _verdict("test_attack_nearest_picks_the_closest")


func test_attack_reports_not_landed_for_a_downed_target() -> Variant:
	var attacker: AttackCharacter = _spawn_attack(Vector3.ZERO)
	attacker.damage = 999
	var victim: Character = _spawn_character(Vector3(1.0, 0.0, 0.0))
	attacker.stance = 1
	victim.stance = -1
	var landings: Array = []
	attacker.get_attack().attacked.connect(
		func(_target: Character, landed: bool) -> void: landings.append(landed)
	)
	_check(attacker.attack(victim), "第一下打进去了")
	_check(victim.is_downed, "目标被打倒")
	# Readiness rejects protected downed targets before dispatch; geometry stays true.
	attacker.get_attack().cooldown_seconds = 0.0
	_check(attacker.get_attack().contains(victim), "Downed target remains geometrically in range")
	_check(not attacker.get_attack().can_attack(victim), "Protected downed target is not attack-ready")
	_check(not attacker.attack(victim), "倒地目标这一下不生效")
	_check_eq(landings, [true], "Rejected commands do not emit hit-dispatch signals")
	return _verdict("test_attack_reports_not_landed_for_a_downed_target")


func test_attack_range_uses_horizontal_distance() -> Variant:
	var attacker: AttackCharacter = _spawn_attack(Vector3.ZERO)
	attacker.attack_range = 2.0
	# 正上方 3 米：水平距离为 0，所以够得着（与视野一样忽略高度差）
	var above: Character = _spawn_character(Vector3(0.0, 3.0, 0.0))
	attacker.stance = 1
	above.stance = -1
	_check(attacker.can_attack(above), "只看水平距离，不受高度差影响")
	_check_eq(attacker.get_attack().distance_to(above), 0.0, "水平距离为 0")
	return _verdict("test_attack_range_uses_horizontal_distance")

# ------------------------------------------------------------------ 工具
func _spawn_character(at: Vector3 = Vector3.ZERO) -> Character:
	var c: Character = CHARACTER_SCENE.instantiate() as Character
	add_child(c)
	_spawned.append(c)
	c.global_position = at
	return c


func _spawn_movable(at: Vector3 = Vector3.ZERO) -> MovableCharacter:
	var c: MovableCharacter = MOVABLE_SCENE.instantiate() as MovableCharacter
	add_child(c)
	_spawned.append(c)
	c.global_position = at
	return c


func _spawn_attack(at: Vector3 = Vector3.ZERO) -> AttackCharacter:
	var c: AttackCharacter = ATTACK_SCENE.instantiate() as AttackCharacter
	add_child(c)
	_spawned.append(c)
	c.global_position = at
	return c


func _spawn_attribute(at: Vector3 = Vector3.ZERO) -> AttributeCharacter:
	var c: AttributeCharacter = ATTRIBUTE_SCENE.instantiate() as AttributeCharacter
	add_child(c)
	_spawned.append(c)
	c.global_position = at
	return c


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)


func _check_eq(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s（期望 %s，实际 %s）" % [label, expected, actual])


func _verdict(test_name: String) -> Variant:
	if _failures.is_empty():
		print("PASS  ", test_name)
		return null
	var message: String = ""
	for failure: String in _failures:
		message += "\n   - " + failure
	print("FAIL  ", test_name, message)
	return message
