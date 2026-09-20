extends CanvasLayer
## 摄影机操作按钮：键盘 [b]Q / E / R[/b] 的屏幕平替。
##
## [br]· 左下角「视角左旋」＝ Q，右下角「视角右旋」＝ E：按住持续旋转，速度用 [Camera3D] 上的
##   [member yaw_speed_degrees]，和键盘完全一致
## [br]· 方向按[b]"画面内容往哪滑"[/b]来定：左旋 = 画面往左滑，右旋 = 画面往右滑
##   （和左键拖动"抓住场景拖"的手感一致）
## [br]· 右上角「视野复原」＝ R：点一下回到开机记录的初始机位
##
## [br][b]两个旋转键同时按住时：先输入覆盖后输入[/b]——先按下的那个说了算，后按的不生效，
## 直到先按下的松开（此时如果后按的还按着，它就接上）。
##
## [br]按钮只是往 [Camera3D] 塞旋转意图（[method set_turn_input]），自身不碰任何相机数值。

@export_group("接线 / Wiring")
## 要控制的摄影机。
@export var camera_path: NodePath = ^"../Camera3D"
@export var rotate_left_path: NodePath = ^"RotateLeft"
@export var rotate_right_path: NodePath = ^"RotateRight"
@export var restore_path: NodePath = ^"Restore"

var _camera: Camera3D = null
var _left: Button = null
var _right: Button = null
var _restore: Button = null
## 当前按住的方向钮，[b]按“先按下的排在前面”[/b]的顺序存放：-1 左旋 / +1 右旋。
var _held: Array[float] = []

# ------------------------------------------------------------------ 生命周期
func _ready() -> void:
	_camera = get_node_or_null(camera_path) as Camera3D
	if _camera == null:
		push_warning("CameraUIButtons: 找不到摄影机（%s），按钮不会生效。" % camera_path)

	_left = get_node_or_null(rotate_left_path) as Button
	_right = get_node_or_null(rotate_right_path) as Button
	_restore = get_node_or_null(restore_path) as Button
	if _left == null or _right == null:
		push_warning("CameraUIButtons: 缺少旋转按钮，按钮不会生效。")

	if _left != null:
		_left.button_down.connect(func() -> void: press_direction(-1.0))
		_left.button_up.connect(func() -> void: release_direction(-1.0))
	if _right != null:
		_right.button_down.connect(func() -> void: press_direction(1.0))
		_right.button_up.connect(func() -> void: release_direction(1.0))
	if _restore != null:
		_restore.pressed.connect(_on_restore_pressed)


func _exit_tree() -> void:
	# 界面被销毁时别把旋转卡住
	_held.clear()
	_apply_turn()

# ------------------------------------------------------------------ 公开 API
## 按下一个旋转方向（-1 左旋 / +1 右旋）。重复按下同一个方向不会有副作用。
func press_direction(direction: float) -> void:
	if _held.has(direction):
		return
	_held.append(direction)  # 后按的排到后面，于是先按下的天然优先
	_apply_turn()


## 松开一个旋转方向。
func release_direction(direction: float) -> void:
	if not _held.has(direction):
		return
	_held.erase(direction)
	_apply_turn()


## 当前真正生效的旋转方向（-1 / +1 / 0）。
func get_active_direction() -> float:
	return 0.0 if _held.is_empty() else float(_held[0])

# ------------------------------------------------------------------ 内部
func _apply_turn() -> void:
	if _camera == null:
		return
	_camera.call("set_turn_input", get_active_direction())


func _on_restore_pressed() -> void:
	if _camera != null:
		_camera.call("restore_initial")
