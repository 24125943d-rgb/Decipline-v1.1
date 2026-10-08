class_name AttackCharacter
extends Character
## 可攻击角色：天生装上 [CharacterAttack] 组件的 [Character] 预设。
##
## [br][b]它同样只是「预设组合」[/b]：想让 [AttributeCharacter] 也会打人，用
## [method CharacterTraits.add_trait] 给它装攻击组件即可，不必新开子类。
##
## [br][b]伤害由受击方结算[/b]（与 [Hitbox] 同一约定）：本类只提供
## [member attack_range] / [member damage] 与 [method attack]，无敌帧、倒地保护
## 这些规则由 [method Character.take_hit] 那边统一实现。
##
## [br][codeblock]
## var enemy := ATTACK_SCENE.instantiate() as AttackCharacter
## enemy.attack_range = 2.5
## enemy.damage = 12
## if enemy.can_attack(hero):
##     enemy.attack(hero)
## enemy.attack_nearest()            # 或者打范围内最近的
## [/codeblock]

@export_group("攻击 / Attack")
## 攻击距离（米，水平面 XZ 距离，不受身高差影响）。
@export var attack_range: float:
	get:
		return _attack.attack_range if _attack != null else _range
	set(value):
		_range = maxf(value, 0.0)
		if _attack != null:
			_attack.attack_range = _range

## 每次攻击的 HP 伤害。
@export var damage: int:
	get:
		return _attack.damage if _attack != null else _damage
	set(value):
		_damage = maxi(value, 0)
		if _attack != null:
			_attack.damage = _damage

## 每次攻击的 sanity 伤害。
@export var sanity_damage: int:
	get:
		return _attack.sanity_damage if _attack != null else _sanity_damage
	set(value):
		_sanity_damage = maxi(value, 0)
		if _attack != null:
			_attack.sanity_damage = _sanity_damage

var _range: float = 2.0
var _damage: int = 10
var _sanity_damage: int = 0
var _attack: CharacterAttack = null


func _ready() -> void:
	super()
	_attack = CharacterTraits.add_trait(self, CharacterTraits.TRAIT_ATTACK) as CharacterAttack
	if _attack == null:
		push_warning("AttackCharacter: 攻击组件没装上，攻击不会生效。")
		return
	_attack.attack_range = _range
	_attack.damage = _damage
	_attack.sanity_damage = _sanity_damage

# ------------------------------------------------------------------ 攻击 API（转发给组件）

## 攻击 [param target]，返回这一下是否真的打进去了。
func attack(target: Character) -> bool:
	return false if _attack == null else _attack.attack(target)


## 够得着吗（不结算伤害）。
func can_attack(target: Character) -> bool:
	return false if _attack == null else _attack.can_attack(target)


## 打范围内最近的，返回被打的那个（没人返回 null）。
func attack_nearest() -> Character:
	return null if _attack == null else _attack.attack_nearest()


## 攻击范围内的所有角色（按距离升序）。
func characters_in_range() -> Array[Character]:
	var result: Array[Character] = []
	if _attack != null:
		result = _attack.characters_in_range()
	return result


## 攻击组件（没装上时为 null）。
func get_attack() -> CharacterAttack:
	return _attack
