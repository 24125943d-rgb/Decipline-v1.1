extends Camera3D
## 试用场景的摄影机控制器：[b]环绕式（Orbit）摄像机[/b]。
##
## [br][b]按键[/b]
## [br]· [b]Q / E[/b]：绕 Y 轴旋转摄影机（偏航），按住连续转。
##   方向按"画面内容往哪滑"来定：Q = 画面内容往左滑，E = 画面内容往右滑
## [br]· [b]W / A / S / D[/b]：在 XZ 平面上平移[b]枢轴点[/b]（相对当前朝向：W = 画面往里）
## [br]· [b]鼠标拖动[/b]：按住[b]左键 / 右键[/b]拖动 = 直接平移枢轴点（水平方向，不用按 WASD）。
##   左键与"点击角色查看视野"共用：按下先选取，之后移动即平移
## [br]· [b]鼠标滚轮[/b]：以 Y 轴为极轴缩放半径（= 摄影机到枢轴点的距离）
## [br]· [b]R[/b]：一键还原到开局记录的初始机位
##
## [br][b]模型[/b]：摄影机始终"看向"一个位于地面上的枢轴点——
## 枢轴点固定在环境地面平面 [code]y = 0[/code] 上（只被 WASD 在 XZ 上移动，Y 永远是 0），
## 摄影机位置 = 枢轴点 + R(偏航, 俯仰) · (0, 0, 半径)。
## [br]初始枢轴点取[b]镜头正前方与地面 y = 0 的交点[/b]（本场景里约为 (1.6, 0, 0.7)），
## 这样开机第一帧的姿态和你在编辑器里手摆的完全一致，不会跳一下；
## 代价是初始枢轴点不是严格的 (0,0,0)——想强制对准世界原点，把
## [method _record_initial_state] 里那句交点计算换成 [code]Vector3.ZERO[/code] 即可。
##
## [br]俯仰角不提供按键控制：始终保持初始俯仰，只有 Q/E 的偏航和滚轮的半径会变。

@export_group("速度 / Speeds")
## Q / E 的旋转速度（度/秒）。
@export var yaw_speed_degrees: float = 90.0
## WASD 的平移速度（米/秒）。
@export var move_speed: float = 10.0
## 滚轮每一格的缩放倍率。
@export_range(1.01, 2.0, 0.01) var zoom_factor: float = 1.12

@export_group("范围 / Limits")
## 极坐标半径的最小值（米）。
@export var min_distance: float = 3.0
## 极坐标半径的最大值（米）。
@export var max_distance: float = 150.0
## 俯仰角下限（度，越小越接近水平）。
@export_range(1.0, 60.0, 0.5) var min_pitch_degrees: float = 5.0
## 俯仰角上限（度，越大越接近俯视）。
@export_range(30.0, 89.0, 0.5) var max_pitch_degrees: float = 89.0

## 拖动平移可以绑定的鼠标键。
enum PanButton {
	LEFT = MOUSE_BUTTON_LEFT,
	RIGHT = MOUSE_BUTTON_RIGHT,
	MIDDLE = MOUSE_BUTTON_MIDDLE,
}

@export_group("鼠标拖动 / Mouse Drag")
## 拖动平移可以绑定的鼠标键，默认[b]左键 + 右键[/b]（中键也随时可以加回来）。
## 左键同时承担"点击角色查看视野"：按下的瞬间先完成选取，接着移动就变成拖动平移，
## 两者互不干扰——选取只认按下，平移只认移动。
@export var pan_mouse_buttons: Array[PanButton] = [PanButton.LEFT, PanButton.RIGHT]
## 拖动灵敏度倍率（1.0 = 抓住枢轴点所在平面，指针与世界 1:1）。
@export_range(0.1, 5.0, 0.05) var drag_sensitivity: float = 1.0
## 拖动时把光标换成"抓取"样式。
@export var change_cursor_on_drag: bool = true

## 还原成功时打印一行，方便确认。
@export var print_on_restore: bool = true

# ------------------------------------------------------------------ 状态
## 枢轴点（永远在 y = 0 地面上）。
var _pivot: Vector3 = Vector3.ZERO
## 偏航（绕 Y 轴，弧度）。
var _yaw: float = 0.0
## 俯仰（[b]向下为正[/b]，弧度；0 = 水平，≈90° = 正俯视）。
var _pitch: float = 0.0
## 极坐标半径 = 摄影机到枢轴点的距离（米）。
var _distance: float = 1.0

var _initial_pivot: Vector3 = Vector3.ZERO
var _initial_yaw: float = 0.0
var _initial_pitch: float = 0.0
var _initial_distance: float = 1.0

## 是否正在用鼠标拖动平移。
var _dragging: bool = false
## 外部（屏幕按钮等）塞进来的旋转意图：-1 右旋 / +1 左旋 / 0 = 交给键盘。
var _external_turn: float = 0.0

# ------------------------------------------------------------------ 生命周期
func _ready() -> void:
	_record_initial_state()
	_apply()


func _process(delta: float) -> void:
	# 屏幕按钮（[method set_turn_input]）优先；没有被按住时回落到键盘 Q / E
	var turn: float = _external_turn
	if is_zero_approx(turn):
		if Input.is_physical_key_pressed(KEY_Q):
			turn -= 1.0
		if Input.is_physical_key_pressed(KEY_E):
			turn += 1.0
	if not is_zero_approx(turn):
		_yaw += deg_to_rad(yaw_speed_degrees) * turn * delta
		_apply()

	var move: Vector3 = _planar_move_input()
	if move != Vector3.ZERO:
		var next: Vector3 = _pivot + move * move_speed * delta
		_pivot = Vector3(next.x, 0.0, next.z)
		_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _dragging:
			drag_pan_by((event as InputEventMouseMotion).relative)
	elif event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event as InputEventMouseButton
		if pan_mouse_buttons.has(mouse.button_index as PanButton):
			_set_dragging(mouse.pressed)
			return
		if not mouse.pressed:
			return
		if mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(1.0 / zoom_factor)
		elif mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(zoom_factor)
	elif event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and key.physical_keycode == KEY_R:
			restore_initial()

# ------------------------------------------------------------------ 公开 API
## 外部输入（屏幕上的「视角左旋 / 右旋」按钮等）塞旋转意图：
## [code]+1[/code] = 偏航增大（画面内容往右滑）、[code]-1[/code] = 偏航减小（画面内容往左滑）、
## [code]0[/code] = 交回键盘 Q / E。按住期间按 [member yaw_speed_degrees] 的速度连续旋转，
## 和按键盘完全一致。
func set_turn_input(direction: float) -> void:
	_external_turn = clampf(direction, -1.0, 1.0)


## 滚轮缩放：把极坐标半径乘以 [param factor]（>1 拉远，<1 拉近）。
func zoom_by(factor: float) -> void:
	_distance = clampf(_distance * factor, min_distance, max_distance)
	_apply()


## 鼠标拖动平移：按屏幕位移 [param relative]（像素）把枢轴点沿地面挪动。
## 尺度取自"枢轴点所在深度的画面比例"，所以在哪个缩放级别下手感都一致；
## 竖直方向额外除以俯仰的正弦（俯视角把地面压扁了，同样的地面距离占的像素更少）。
func drag_pan_by(relative: Vector2) -> void:
	if relative == Vector2.ZERO:
		return
	var viewport_height: float = float(get_viewport().get_visible_rect().size.y)
	if viewport_height <= 1.0:
		viewport_height = 1080.0
	var meters_per_pixel: float = 2.0 * _distance * tan(deg_to_rad(fov) * 0.5) / viewport_height
	meters_per_pixel *= drag_sensitivity
	var right: Vector3 = Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var forward: Vector3 = Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var vertical_scale: float = meters_per_pixel / maxf(sin(_pitch), 0.3)
	var offset: Vector3 = right * (-relative.x * meters_per_pixel) + forward * (relative.y * vertical_scale)
	_pivot = Vector3(_pivot.x + offset.x, 0.0, _pivot.z + offset.z)
	_apply()


## 还原到开局记录的初始机位（枢轴点 / 偏航 / 俯仰 / 半径一起还原）。
func restore_initial() -> void:
	_pivot = _initial_pivot
	_yaw = _initial_yaw
	_pitch = _initial_pitch
	_distance = _initial_distance
	_apply()
	if print_on_restore:
		print("Camera restored to its initial view: ", get_state())


## 当前机位，方便脚本 / 调试读取：
## [code]{pivot, yaw_degrees, pitch_degrees, distance, position}[/code]。
func get_state() -> Dictionary:
	return {
		"pivot": _pivot,
		"yaw_degrees": rad_to_deg(_yaw),
		"pitch_degrees": rad_to_deg(_pitch),
		"distance": _distance,
		"position": global_transform.origin,
	}

# ------------------------------------------------------------------ 内部
## 把当前机位记为新的"初始机位"（R 键 / 「视野复原」按钮的回到点）。
## 场景类（[VisionTrial]）设置完初始机位后会调这个，让复原点跟着更新。
func capture_initial_state() -> void:
	_record_initial_state()
	_apply()


## 从当前 transform 反解出初始机位（场景里手摆的机位就是纯 偏航 + 俯仰，没有 roll）。
func _record_initial_state() -> void:
	var current_basis: Basis = global_transform.basis
	var forward: Vector3 = -current_basis.z
	var flat: Vector3 = Vector3(forward.x, 0.0, forward.z)
	if flat.length_squared() < 0.000001:
		flat = Vector3(0.0, 0.0, -1.0)
	flat = flat.normalized()
	_initial_yaw = atan2(-flat.x, -flat.z)
	_initial_pitch = -asin(clampf(forward.y, -1.0, 1.0))

	# 枢轴点 = 视线与地面 y = 0 的交点
	var eye: Vector3 = global_transform.origin
	var pivot: Vector3 = Vector3(eye.x, 0.0, eye.z)
	if absf(forward.y) > 0.0001:
		var hit_distance: float = -eye.y / forward.y
		if hit_distance > 0.0:
			pivot = eye + forward * hit_distance
	pivot.y = 0.0

	_initial_pivot = pivot
	_initial_distance = maxf(eye.distance_to(pivot), 0.001)

	_pivot = _initial_pivot
	_yaw = _initial_yaw
	_pitch = _initial_pitch
	_distance = _initial_distance


## 拖动状态切换（顺手换成"抓取"光标）。
func _set_dragging(value: bool) -> void:
	if _dragging == value:
		return
	_dragging = value
	if change_cursor_on_drag:
		Input.set_default_cursor_shape(Input.CURSOR_DRAG if value else Input.CURSOR_ARROW)


## 把（枢轴点, 偏航, 俯仰, 半径）写回摄影机的 transform。
func _apply() -> void:
	_pitch = clampf(_pitch, deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))
	var view_basis: Basis = Basis.from_euler(Vector3(-_pitch, _yaw, 0.0))
	global_transform = Transform3D(view_basis, _pivot + view_basis * Vector3(0.0, 0.0, _distance))


## WASD → XZ 平面上的方向（相对当前偏航；W 是画面往里）。
func _planar_move_input() -> Vector3:
	var input: Vector2 = Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		input.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		input.y += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		input.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		input.x += 1.0
	if input == Vector2.ZERO:
		return Vector3.ZERO
	input = input.normalized()
	var forward: Vector3 = Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var right: Vector3 = Vector3(cos(_yaw), 0.0, -sin(_yaw))
	return (forward * -input.y + right * input.x).normalized()
