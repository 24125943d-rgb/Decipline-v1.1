class_name CharacterMovement
extends Node3D
## 可移动能力组件：挂在任意 [Character] 下面即可让角色会走路。
##
## [br][b]为什么是组件而不是子类[/b]：GDScript 只支持单继承，而「可移动 + 可攻击 + 有属性」
## 这种组合用继承树表达不了（要么组合爆炸，要么被迫排一条固定顺序的链）。
## 本工程从视野组件开始就定了口径：[b]能力 = 组件[/b]，类只负责默认装配，见 [CharacterTraits]。
##
## [br][b]两种移动语义[/b]（都按「速度 = 米/秒」解释 [member speed]）：
## [br]· [method move]：设置[b]移动意图[/b]，之后每个物理帧朝该方向持续走，直到
##   [method stop] 或换方向。适合摇杆 / 键盘这种逐帧驱动。
## [br]· [method step]：一次性走一段固定距离（走完就停），适合积木指令「前进 3」。
##
## [br]前进方向沿用本工程的约定：角色节点的 [b]-Z[/b]（与 [CharacterVision] 一致）。
##
## [br][b]不做的事[/b]：不处理重力、跳跃、地面吸附（本工程的角色是浮在地面平面上的），
## 也不负责转身——转身是另一个关注点，需要时再单独加组件。

## 移动速度（米/秒）。
@export var speed: float = 3.0:
	set(value):
		speed = maxf(value, 0.0)

## 移动意图（世界空间方向，长度为 1；零向量表示不动）。
var _direction: Vector3 = Vector3.ZERO

## Number of completed move_and_slide steps (for post-physics consumers).
var completed_steps: int = 0
var _character: Character = null


func _ready() -> void:
	_character = _resolve_character()
	if _character == null:
		push_warning("CharacterMovement: 没挂在 Character 下，移动不会生效。")
	set_physics_process(false)  # 没在移动时不占物理帧

# ------------------------------------------------------------------ 移动

## 开始朝 [param direction] 持续移动（方向会自动归一化；零向量等价于 [method stop]）。
func move(direction: Vector3) -> void:
	if direction.is_zero_approx():
		stop()
		return
	_direction = direction.normalized()
	_apply()

## 停下（清掉移动意图与本帧速度）。
func stop() -> void:
	_direction = Vector3.ZERO
	_apply()

## 一次性走 [param distance] 米（负数表示后退），走完才返回[b]实际[/b]位移
## ——撞到东西会提前停下，所以可能小于请求值。
## [br]它是可 await 的协程：内部逐物理帧推进（复用 [method move] 的持续移动），
## 因此既不用 [code]move_and_collide[/code]（那要求物理帧上下文），
## 又能直接给积木指令用：[code]await target.walk(3.0)[/code]。
## [param direction] 留空时按角色正前方（-Z）。
func walk(distance: float, direction: Vector3 = Vector3.ZERO) -> float:
	if _character == null or is_zero_approx(distance) or not is_inside_tree():
		return 0.0
	var heading: Vector3 = direction.normalized() if not direction.is_zero_approx() else get_forward()
	var before: Vector3 = _character.global_position
	move(heading * signf(distance))
	var remaining: float = absf(distance)
	var guard: int = 0
	while remaining > 0.0 and is_instance_valid(_character):
		var step_from: Vector3 = _character.global_position
		await get_tree().physics_frame
		var moved: float = step_from.distance_to(_character.global_position)
		if moved <= 0.0001:
			break  # 被挡住了，别在这儿空转
		remaining -= moved
		guard += 1
		if guard > 100000:
			break
	stop()
	return before.distance_to(_character.global_position)

# ------------------------------------------------------------------ 查询

## 正在移动吗（有移动意图且组件可用）。
func is_moving() -> bool:
	return _character != null and not _direction.is_zero_approx()

## 当前移动方向（零向量表示不动）。
func get_direction() -> Vector3:
	return _direction

## 角色正前方：约定为节点的 -Z（与视野组件同口径）。
func get_forward() -> Vector3:
	if _character == null:
		return Vector3.FORWARD
	return -_character.global_transform.basis.z

## 本组件服务的角色（可能为 null：没挂在 Character 下时）。
func get_character() -> Character:
	return _character

# ------------------------------------------------------------------ 内部

func _physics_process(_delta: float) -> void:
	if _character == null:
		return
	_character.velocity = _direction * speed
	_character.move_and_slide()
	completed_steps += 1


## 把意图落到「要不要跑物理帧」和「速度是否清零」上。
func _apply() -> void:
	if _character == null:
		return
	if _direction.is_zero_approx():
		_character.velocity = Vector3.ZERO
		set_physics_process(false)
	else:
		# 立刻反映意图：move() 之后马上查询状态就是对的；
		# 真正的位移仍由 _physics_process 每帧推进（那里会重算，改 speed 立即生效）
		_character.velocity = _direction * speed
		set_physics_process(true)


## 沿父链找角色（角色自己身上可能还隔着别的节点）。
func _resolve_character() -> Character:
	var node: Node = get_parent()
	while node != null:
		var found: Character = node as Character
		if found != null:
			return found
		node = node.get_parent()
	return null
