class_name MovableCharacter
extends Character
## 可移动角色：天生装上 [CharacterMovement] 组件的 [Character] 预设。
##
## [br][b]它只是一个「预设组合」，不是移动能力的唯一来源[/b]：[CharacterTraits] 可以给
## 任何别的角色（包括 [AttributeCharacter]）装上移动组件，所以「有属性 + 会走 + 会打」
## 不需要再新开一个类——GDScript 是单继承，排不出那种菱形，能力一律用组件拼。
##
## [br][codeblock]
## var unit := MOVABLE_SCENE.instantiate() as MovableCharacter
## unit.speed = 4.0
## unit.move(Vector3.RIGHT)          # 持续向右
## unit.step(3.0)                    # 或者一次性前进 3 米
## unit.stop()
## [/codeblock]

@export_group("移动 / Movement")
## 移动速度（米/秒）。写入后会同步到 [CharacterMovement] 组件，组件才是运行时的权威值。
@export var speed: float:
	get:
		return _movement.speed if _movement != null else _speed
	set(value):
		_speed = maxf(value, 0.0)
		if _movement != null:
			_movement.speed = _speed

var _speed: float = 3.0
var _movement: CharacterMovement = null


func _ready() -> void:
	super()
	_movement = CharacterTraits.add_trait(
		self, CharacterTraits.TRAIT_MOVEMENT
	) as CharacterMovement
	if _movement == null:
		push_warning("MovableCharacter: 移动组件没装上，移动不会生效。")
		return
	_movement.speed = _speed  # 把 Inspector 里配的值灌进组件

# ------------------------------------------------------------------ 移动 API（转发给组件）

## 开始朝 [param direction] 持续移动（零向量等价于 [method stop]）。
func move(direction: Vector3) -> void:
	if _movement != null:
		_movement.move(direction)


## 停下。
func stop() -> void:
	if _movement != null:
		_movement.stop()


## 一次性走 [param distance] 米（负数后退），走完才返回实际位移。
## [param direction] 留空时按角色正前方（-Z）。
## 可 await：[code]var walked := await unit.walk(3.0)[/code]。
func walk(distance: float, direction: Vector3 = Vector3.ZERO) -> float:
	if _movement == null:
		return 0.0
	return await _movement.walk(distance, direction)


## 正在移动吗。
func is_moving() -> bool:
	return _movement != null and _movement.is_moving()


## 当前移动方向（零向量表示不动）。
func get_direction() -> Vector3:
	return Vector3.ZERO if _movement == null else _movement.get_direction()


## 移动组件（没装上时为 null）。
func get_movement() -> CharacterMovement:
	return _movement
