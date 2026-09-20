extends Node
## Character 基类的单元测试。
##
## 运行器约定：脚本 extend Node，测试方法以 test_ 开头；
## 返回 null 表示通过，返回字符串表示失败原因。

const CharacterScene: PackedScene = preload("res://scenes/character.tscn")

var _failures: PackedStringArray = PackedStringArray()
# lambda 按值捕获局部变量，所以信号计数必须放在成员变量上。
var _downed_events: int = 0
var _revived_events: int = 0
var _hp_events: int = 0
var _hits: int = 0

func before_each() -> void:
	_failures.clear()
	_downed_events = 0
	_revived_events = 0
	_hp_events = 0
	_hits = 0

# ------------------------------------------------------------------ 用例
func test_defaults() -> Variant:
	var c: Character = _spawn()
	_check_eq(c.max_hp, 100, "默认 max_hp")
	_check_eq(c.hp, 100, "默认 hp")
	_check_eq(c.max_sanity, 100, "默认 max_sanity")
	_check_eq(c.sanity, 100, "默认 sanity")
	_check_eq(c.state, Character.State.NORMAL, "默认状态")
	_check(not c.is_downed, "默认未倒地")
	_check(not c.is_confused, "默认未混乱")
	_check(c.is_alive(), "默认存活")
	_check(c.is_in_group(Character.GROUP_CHARACTER), "加入 character 组")
	_check_eq(c.get_state_name(), "NORMAL", "状态名")
	var placeholder: MeshInstance3D = c.get_node_or_null(^"Appearance/ModelRoot/PlaceholderSphere")
	_check(placeholder != null and placeholder.visible, "默认显示占位球体")
	c.free()
	return _verdict("test_defaults")


func test_hp_floor_and_downed_flag() -> Variant:
	var c: Character = _spawn()
	c.downed.connect(func() -> void: _downed_events += 1)
	c.revived.connect(func() -> void: _revived_events += 1)
	c.hp_changed.connect(func(_current: int, _maximum: int) -> void: _hp_events += 1)

	c.take_damage(30)
	_check_eq(c.hp, 70, "扣 30")
	_check_eq(_downed_events, 0, "未倒地时不发 downed")
	_check(c.is_normal(), "只掉血仍是正常状态")

	c.take_damage(9999)
	_check_eq(c.hp, 0, "HP 不会低于 0")
	_check(c.is_downed, "HP 归零 → 倒地 flag = true")
	_check_eq(c.state, Character.State.DOWNED, "HP 归零 → 状态 DOWNED")
	_check(c.is_in_group(Character.GROUP_DOWNED), "倒地角色进入 downed 组")
	_check_eq(_downed_events, 1, "downed 信号发一次")
	_check(_hp_events >= 2, "hp_changed 信号有发")

	c.hp = -50
	_check_eq(c.hp, 0, "直接写 -50 仍被夹到 0")
	c.hp = 9999
	_check_eq(c.hp, c.max_hp, "直接写超上限仍被夹住")
	_check_eq(_revived_events, 1, "回血到 > 0 发 revived")
	_check(not c.is_in_group(Character.GROUP_DOWNED), "回血后离开 downed 组")

	c.heal(50)
	_check_eq(c.hp, c.max_hp, "heal 不超过 max_hp")
	c.max_hp = 40
	_check_eq(c.hp, 40, "调低上限后当前值跟着夹住")
	c.free()
	return _verdict("test_hp_floor_and_downed_flag")


func test_downed_blocks_damage_and_revive() -> Variant:
	var c: Character = _spawn()
	c.revived.connect(func() -> void: _revived_events += 1)

	c.take_damage(100)
	_check(not c.take_hit(50, 0, null), "倒地时 take_hit 返回 false")
	_check_eq(c.hp, 0, "倒地时不吃伤害")

	c.damageable_when_downed = true
	_check(c.take_hit(1, 0, null), "允许倒地追击后 take_hit 生效")
	_check_eq(c.hp, 0, "倒地追击也不会让 HP 变负")
	c.damageable_when_downed = false

	c.revive()
	_check_eq(c.hp, c.max_hp, "revive 回满")
	_check(not c.is_downed, "扶起后清除倒地 flag")
	_check(not c.is_in_group(Character.GROUP_DOWNED), "扶起后离开 downed 组")
	_check_eq(c.state, Character.State.NORMAL, "扶起后回到正常")
	_check_eq(_revived_events, 1, "revived 信号")

	c.take_damage(100)
	c.revive_hp = 25
	c.revive()
	_check_eq(c.hp, 25, "revive_hp 生效")
	c.free()
	return _verdict("test_downed_blocks_damage_and_revive")


func test_sanity_floor_and_confusion() -> Variant:
	var c: Character = _spawn()
	var states: Array[int] = []
	c.state_changed.connect(func(_previous: int, current: int) -> void: states.append(current))

	c.take_sanity_damage(30)
	_check_eq(c.sanity, 70, "扣 sanity 30")
	c.take_sanity_damage(9999)
	_check_eq(c.sanity, 0, "sanity 不会低于 0")
	_check(c.is_confused, "sanity 归零 → 混乱")
	_check(not c.is_downed, "sanity 归零不算倒地")
	_check(c.is_alive(), "混乱仍然存活")
	_check_eq(c.state, Character.State.CONFUSED, "状态 CONFUSED")
	_check(states.has(Character.State.CONFUSED), "state_changed 报告 CONFUSED")
	_check(not c.is_in_group(Character.GROUP_DOWNED), "混乱不进 downed 组")

	c.sanity = -10
	_check_eq(c.sanity, 0, "直接写负数仍被夹到 0")
	c.restore_sanity(9999)
	_check_eq(c.sanity, c.max_sanity, "restore_sanity 不超过上限")
	_check_eq(c.state, Character.State.NORMAL, "sanity 恢复 → 正常")
	c.free()
	return _verdict("test_sanity_floor_and_confusion")


func test_downed_overrides_confusion() -> Variant:
	var c: Character = _spawn()
	c.take_sanity_damage(100)
	_check(c.is_confused and not c.is_downed, "先进入混乱")

	c.take_damage(100)
	_check_eq(c.state, Character.State.DOWNED, "混乱 + HP 归零 → 倒地")
	_check(not c.is_confused, "倒地时不再算混乱")

	c.revive()
	_check_eq(c.state, Character.State.CONFUSED, "扶起但 sanity 仍为 0 → 回到混乱")
	c.restore_sanity(100)
	_check_eq(c.state, Character.State.NORMAL, "sanity 回满 → 正常")
	c.free()
	return _verdict("test_downed_overrides_confusion")


func test_hurtbox_is_centered_and_replaceable() -> Variant:
	var c: Character = _spawn()
	_check(c.hurtbox != null, "存在 Hurtbox")
	_check(c.hurtbox is Area3D, "Hurtbox 是 Area3D")
	_check(c.hurtbox_shape != null, "Hurtbox 里有一个 CollisionShape3D")
	_check(c.hurtbox_shape.shape is SphereShape3D, "占位形状是球体")
	if c.hurtbox_shape.shape is SphereShape3D:
		var sphere: SphereShape3D = c.hurtbox_shape.shape as SphereShape3D
		_check_eq(snappedf(sphere.radius, 0.001), 0.5, "球体半径")
	_check_eq(c.hurtbox.collision_layer, Character.LAYER_HURTBOX, "在受击层")
	_check_eq(c.hurtbox.collision_mask, Character.LAYER_HITBOX, "扫描攻击层")
	_check(c.hurtbox.monitorable, "可被攻击判定检测到")

	# 占位球体半径 0.5、位于原点 → 受击判定中心应落在角色原点
	var offset: Vector3 = c.hurtbox.global_position - c.global_position
	_check(offset.length() < 0.001, "受击判定位于外观中心（偏移 %s）" % offset)

	# 外观整体抬高后，重新居中应该跟过去
	c.appearance.position = Vector3(0, 1.5, 0)
	c.recenter_hurtbox()
	var moved: float = snappedf(c.hurtbox.global_position.y - c.global_position.y, 0.001)
	_check_eq(moved, 1.5, "外观偏移后重新居中")

	# 形状可以随便换（可替换性）
	c.hurtbox_shape.shape = CapsuleShape3D.new()
	c.recenter_hurtbox()
	_check(c.hurtbox_shape.shape is CapsuleShape3D, "受击形状可以换成胶囊")
	c.free()
	return _verdict("test_hurtbox_is_centered_and_replaceable")


func test_hit_filters_and_invulnerability() -> Variant:
	var c: Character = _spawn()

	var attack: Hitbox = Hitbox.new()
	attack.damage = 20
	attack.sanity_damage = 4
	add_child(attack)
	_check(attack.is_in_group(Character.GROUP_HITBOX), "Hitbox 自动加入 hitbox 组")

	var received: Array = []
	c.hit_received.connect(
		func(damage: int, sanity_damage: int, _source: Node) -> void: received.append([damage, sanity_damage])
	)

	c._on_hurtbox_area_entered(attack)
	_check_eq(c.hp, 80, "命中扣 HP")
	_check_eq(c.sanity, 96, "命中扣 sanity")
	_check_eq(received.size(), 1, "hit_received 信号")
	if received.size() == 1:
		_check_eq(received[0][0], 20, "信号里的 HP 伤害")
		_check_eq(received[0][1], 4, "信号里的 sanity 伤害")

	var decoy: Area3D = Area3D.new()
	add_child(decoy)
	c._on_hurtbox_area_entered(decoy)
	_check_eq(c.hp, 80, "不在 hitbox 组里的 Area3D 不结算")

	var mute: Hitbox = Hitbox.new()
	mute.damage = 0
	mute.sanity_damage = 0
	add_child(mute)
	c._on_hurtbox_area_entered(mute)
	_check_eq(c.hp, 80, "damage / sanity_damage 都为 0 时不结算")

	c.invulnerability_time = 0.5
	_check(c.take_hit(5, 0, null), "无敌帧外第一下命中")
	_check(not c.take_hit(5, 0, null), "无敌帧内第二下不生效")
	_check_eq(c.hp, 75, "无敌帧吞掉的那下不结算")

	attack.free()
	decoy.free()
	mute.free()
	c.free()
	return _verdict("test_hit_filters_and_invulnerability")


func test_appearance_model_swap_and_animation() -> Variant:
	var c: Character = _spawn()
	var placeholder: MeshInstance3D = c.get_node_or_null(^"Appearance/ModelRoot/PlaceholderSphere")
	_check(placeholder != null and placeholder.visible, "替换前显示占位球体")

	var fake_model: PackedScene = _make_fake_model()
	_check(fake_model.can_instantiate(), "假模型打包成功")

	c.set_appearance_model(fake_model)
	_check(c.model_instance != null, "模型已实例化")
	_check(c.model_instance.get_parent() == c.model_root, "模型挂在 ModelRoot 下")
	_check(not placeholder.visible, "占位球体被隐藏")
	_check(c.animation_player != null, "找到模型自带的 AnimationPlayer")
	_check_eq(c.get_anim_names().size(), 1, "读到模型自带的动画数量")
	_check(c.has_anim(&"idle"), "能找到 idle 动画")
	_check(c.play_anim(&"idle"), "能播放 idle 动画")
	_check(not c.has_anim(&"not_exists"), "不存在的动画返回 false")

	# 假模型网格中心在 y = 2（模拟 Blender 模型轴心在脚底）→ 受击判定要跟着抬上去
	var centered: float = snappedf(c.hurtbox.global_position.y - c.global_position.y, 0.001)
	_check_eq(centered, 2.0, "受击判定对齐到模型包围盒中心")

	# 按外观尺寸缩放形状（换一份独立资源，避免动到共享的子资源）
	c.hurtbox_shape.shape = SphereShape3D.new()
	c.fit_hurtbox_to_appearance = true
	c.recenter_hurtbox()
	var radius: float = snappedf((c.hurtbox_shape.shape as SphereShape3D).radius, 0.001)
	_check_eq(radius, 1.0, "形状按外观尺寸缩放")

	c.free()
	return _verdict("test_appearance_model_swap_and_animation")


func test_physics_overlap_delivers_hit() -> Variant:
	var victim: Character = _spawn()

	var attacker: Hitbox = Hitbox.new()
	attacker.damage = 25
	attacker.sanity_damage = 5
	var collision: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = 0.5
	collision.shape = sphere
	attacker.add_child(collision)
	add_child(attacker)
	attacker.hit.connect(func(_hurtbox: Area3D) -> void: _hits += 1)

	# 直接压在受击判定正中心，靠真实物理重叠触发
	attacker.global_position = victim.hurtbox.global_position
	for i: int in 4:
		await get_tree().physics_frame

	_check_eq(victim.hp, 75, "一次重叠扣 25 HP（没有被重复结算）")
	_check_eq(victim.sanity, 95, "一次重叠扣 5 sanity")
	_check_eq(_hits, 1, "Hitbox 的 hit 信号发了一次")

	attacker.free()
	victim.free()
	return _verdict("test_physics_overlap_delivers_hit")

# ------------------------------------------------------------------ 工具
func _spawn() -> Character:
	var character: Character = CharacterScene.instantiate() as Character
	add_child(character)
	return character


func _make_fake_model() -> PackedScene:
	var model_root_node: Node3D = Node3D.new()
	model_root_node.name = "FakeModel"

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "Body"
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(2, 2, 2)
	mesh_instance.mesh = box
	mesh_instance.position = Vector3(0, 2, 0)
	model_root_node.add_child(mesh_instance)
	mesh_instance.owner = model_root_node  # owner 必须在入树之后设置

	var player: AnimationPlayer = AnimationPlayer.new()
	player.name = "AnimationPlayer"
	var library: AnimationLibrary = AnimationLibrary.new()
	var animation: Animation = Animation.new()
	animation.length = 1.0
	library.add_animation("idle", animation)
	player.add_animation_library("", library)
	model_root_node.add_child(player)
	player.owner = model_root_node

	var packed: PackedScene = PackedScene.new()
	packed.pack(model_root_node)
	model_root_node.free()
	return packed


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
