class_name CharacterTraits
extends RefCounted
## 角色能力（trait）登记表 —— 本工程里「多重继承」的实际形态。
##
## [br][b]为什么不能直接多继承[/b]：GDScript 只支持单继承，一个类不能同时是
## [AttributeCharacter] 和 [MovableCharacter]。如果改用继承链（角色 → 可移动 → 可攻击 →
## 有属性），组合顺序就被写死了，多一种能力就要再排一条链，很快爆炸。
##
## [br][b]本工程的做法[/b]（视野组件从第一天就是这么定的）：
## [br]1. [b]能力 = 组件[/b]：[CharacterVision] / [CharacterMovement] / [CharacterAttack]
##   都是挂在角色下的 Node3D 子节点，各自只管自己那一件事；
## [br]2. [b]类只负责默认装配[/b]：[MovableCharacter] 天生带移动组件、[AttackCharacter] 天生带
##   攻击组件、[AttributeCharacter] 带六项属性——它们只是「预设组合」，不是能力的唯一来源；
## [br]3. [b]任意组合[/b]：给任何 [Character]（包括 [AttributeCharacter]）调
##   [method add_trait]，组件按需实例化。于是「有属性 + 会走 + 会打」可以同时存在于
##   一个角色身上，调用方用 [method movement_of] / [method attack_of] / [method vision_of]
##   统一取用，完全不必知道对方是哪个子类。
##
## [br][codeblock]
## var hero: AttributeCharacter = ATTRIBUTE_SCENE.instantiate()
## CharacterTraits.add_trait(hero, CharacterTraits.TRAIT_MOVEMENT)
## CharacterTraits.add_trait(hero, CharacterTraits.TRAIT_ATTACK)
## CharacterTraits.movement_of(hero).move(Vector3.RIGHT)
## CharacterTraits.attack_of(hero).attack(enemy)
## print(hero.strength)                      # 属性照旧可用
## [/codeblock]

## 视野能力（组件：[CharacterVision]，节点名固定为 Vision）。
const TRAIT_VISION: StringName = &"vision"
## 可移动能力（组件：[CharacterMovement]）。
const TRAIT_MOVEMENT: StringName = &"movement"
## 可攻击能力（组件：[CharacterAttack]）。
const TRAIT_ATTACK: StringName = &"attack"

## 能力 → 组件节点名（固定名字，组件靠它被找到）。
const TRAIT_NODE_NAMES: Dictionary = {
	&"vision": &"Vision",
	&"movement": &"Movement",
	&"attack": &"Attack",
}

## 能力 → 组件场景。加一种能力只要在这两张扁平表里各加一行 + 写好组件，
## 不用碰任何现有类（数据驱动的装配表）。
## [br]（保持扁平结构是有意的：GDScript 对 const 容器里的嵌套结构与常量键限制较多。）
const TRAIT_SCENES: Dictionary = {
	&"vision": "res://scenes/vision.tscn",
	&"movement": "res://scenes/character_movement.tscn",
	&"attack": "res://scenes/character_attack.tscn",
}

# ------------------------------------------------------------------ 装配

## 让角色拥有某种能力：已经有组件就原样返回，没有就实例化组件场景挂上去。
## 返回组件节点（能力名字不对 / 角色为 null 时返回 null）。
## [br]重复调用是安全的（幂等）。
static func add_trait(character: Character, trait_name: StringName) -> Node:
	if character == null or not TRAIT_SCENES.has(trait_name):
		return null
	var existing: Node = get_trait(character, trait_name)
	if existing != null:
		return existing
	var scene: PackedScene = load(String(TRAIT_SCENES[trait_name])) as PackedScene
	if scene == null:
		push_warning(
			"CharacterTraits: 能力 '%s' 的组件场景加载失败：%s" % [trait_name, TRAIT_SCENES[trait_name]]
		)
		return null
	var component: Node = scene.instantiate()
	component.name = String(TRAIT_NODE_NAMES.get(trait_name, &"Trait"))
	character.add_child(component)
	return component


## 摘掉某种能力（组件被移除并释放）。返回是否真的摘掉了。
static func remove_trait(character: Character, trait_name: StringName) -> bool:
	var component: Node = get_trait(character, trait_name)
	if component == null:
		return false
	character.remove_child(component)
	component.queue_free()
	return true


## 有没有这种能力。
static func has_trait(character: Character, trait_name: StringName) -> bool:
	return get_trait(character, trait_name) != null


## 取出能力组件（没有返回 null）。
static func get_trait(character: Character, trait_name: StringName) -> Node:
	if character == null or not TRAIT_NODE_NAMES.has(trait_name):
		return null
	return character.get_node_or_null(NodePath(String(TRAIT_NODE_NAMES[trait_name])))


## 角色当前拥有的全部能力名（按 [constant TRAIT_SCENES] 的顺序）。
static func active_traits(character: Character) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for trait_name: StringName in TRAIT_SCENES:
		if has_trait(character, trait_name):
			result.append(String(trait_name))
	return result

# ------------------------------------------------------------------ 类型化取用

## 视野组件（没有则返回 null）。
static func vision_of(character: Character) -> CharacterVision:
	return get_trait(character, TRAIT_VISION) as CharacterVision


## 移动组件（没有则返回 null）。
static func movement_of(character: Character) -> CharacterMovement:
	return get_trait(character, TRAIT_MOVEMENT) as CharacterMovement


## 攻击组件（没有则返回 null）。
static func attack_of(character: Character) -> CharacterAttack:
	return get_trait(character, TRAIT_ATTACK) as CharacterAttack
