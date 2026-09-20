class_name BlockStyleSpec
extends RefCounted
## 表达式积木 StyleBoxFlat 的配置规范（阶段二强制项）。
##
## 规范内容：
## - Content Margin：Top / Bottom 必须为 0（消除垂直挤压）；Left / Right 必须为 8。
## - Border Width：Left / Right 必须为 2；Top / Bottom 必须为 0。
## - 底色透明度：20%~40%（由 BlockPalette.background_alpha 的 @export_range 保证）。
##
## 重要区分：下面的常量是「规范本身」，只用于校验与生成默认资源；
## 真正参与渲染的几何值一律来自 Art/Themes/ 下的 .theme / .tres 资源。
## 也就是说逻辑代码里没有任何决定外观的数字 —— 这里只有判定标准的数字。
##
## 用法：在测试或工具里
##     var problems: PackedStringArray = BlockStyleSpec.validate(stylebox)
## 空数组即合规；否则每条描述一处偏差。

const CONTENT_MARGIN_TOP: float = 0.0
const CONTENT_MARGIN_BOTTOM: float = 0.0
const CONTENT_MARGIN_LEFT: float = 8.0
const CONTENT_MARGIN_RIGHT: float = 8.0

const BORDER_WIDTH_TOP: int = 0
const BORDER_WIDTH_BOTTOM: int = 0
const BORDER_WIDTH_LEFT: int = 2
const BORDER_WIDTH_RIGHT: int = 2

## 浮点比较容差。Color 是 float32：.tres 里的 0.4 读回来是 0.40000000596，
## 不留容差会把正好卡在区间边界的合规资源误判为越界。
const ALPHA_TOLERANCE: float = 0.001


## 校验一个 StyleBoxFlat 是否符合规范，返回所有偏差描述。
static func validate(stylebox: StyleBoxFlat) -> PackedStringArray:
	if stylebox == null:
		return PackedStringArray(["StyleBoxFlat 为 null，无法校验。"])

	var problems: PackedStringArray = []
	_expect_float(problems, "content_margin_top", stylebox.content_margin_top, CONTENT_MARGIN_TOP)
	_expect_float(problems, "content_margin_bottom", stylebox.content_margin_bottom, CONTENT_MARGIN_BOTTOM)
	_expect_float(problems, "content_margin_left", stylebox.content_margin_left, CONTENT_MARGIN_LEFT)
	_expect_float(problems, "content_margin_right", stylebox.content_margin_right, CONTENT_MARGIN_RIGHT)
	_expect_int(problems, "border_width_top", stylebox.border_width_top, BORDER_WIDTH_TOP)
	_expect_int(problems, "border_width_bottom", stylebox.border_width_bottom, BORDER_WIDTH_BOTTOM)
	_expect_int(problems, "border_width_left", stylebox.border_width_left, BORDER_WIDTH_LEFT)
	_expect_int(problems, "border_width_right", stylebox.border_width_right, BORDER_WIDTH_RIGHT)
	_expect_alpha(problems, stylebox)
	return problems


## 底色透明度必须落在 20%~40%（区间常量来自 BlockPalette，只写一次）。
##
## 必须带容差：Color 内部是 float32，写进 .tres 的 0.4 读回来是 0.40000000596，
## 直接跟 0.4 比会被判成越界。
static func _expect_alpha(problems: PackedStringArray, stylebox: StyleBoxFlat) -> void:
	var alpha: float = stylebox.bg_color.a
	if alpha < BlockPalette.BG_ALPHA_MIN - ALPHA_TOLERANCE or alpha > BlockPalette.BG_ALPHA_MAX + ALPHA_TOLERANCE:
		problems.append("bg_color.a 应在 %.2f~%.2f 之间，实际 %.2f。" % [
			BlockPalette.BG_ALPHA_MIN, BlockPalette.BG_ALPHA_MAX, alpha,
		])


static func is_compliant(stylebox: StyleBoxFlat) -> bool:
	return validate(stylebox).is_empty()


## 规范的一句话摘要，便于日志与文档引用。
static func describe() -> String:
	return "content_margin T/B=%s L/R=%s；border_width T/B=%s L/R=%s；bg alpha %s%%~%s%%" % [
		CONTENT_MARGIN_TOP, CONTENT_MARGIN_LEFT,
		BORDER_WIDTH_TOP, BORDER_WIDTH_LEFT,
		BlockPalette.BG_ALPHA_MIN * 100.0, BlockPalette.BG_ALPHA_MAX * 100.0,
	]


static func _expect_float(problems: PackedStringArray, property: String, actual: float, expected: float) -> void:
	if not is_equal_approx(actual, expected):
		problems.append("%s 应为 %s，实际 %s。" % [property, expected, actual])


static func _expect_int(problems: PackedStringArray, property: String, actual: int, expected: int) -> void:
	if actual != expected:
		problems.append("%s 应为 %d，实际 %d。" % [property, expected, actual])
