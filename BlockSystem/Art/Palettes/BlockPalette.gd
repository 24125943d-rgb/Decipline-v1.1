class_name BlockPalette
extends Resource
## 数据驱动的积木调色板 —— 纯美术数据（Art/Palettes）。
##
## 目的：把「哪一类积木用什么颜色」从逻辑代码里彻底剥离，
## 交给美术在编辑器中配置 res://BlockSystem/Art/Palettes/*.tres。
##
## 职责边界（与 Theme 严格分工，互不越界）：
## - 本类只提供「颜色 + 底色透明度」。
## - 几何（padding / border / 圆角 / 字号）一律由 Art/Themes/ 里的
##   StyleBoxFlat 与 Theme 决定，本类不持有任何尺寸。
## - 本类不含行为逻辑，只有取值与自检。
##
## 因此逻辑层（Logic/）取色时只允许调用 get_color_for_category()，
## 代码中不允许出现任何颜色字面量。

## 类别键：逻辑层用这些常量取色，避免字符串拼写错误。
const CATEGORY_VARIABLE: StringName = &"variable"
const CATEGORY_MATH: StringName = &"math"
const CATEGORY_LOGIC: StringName = &"logic"
const CATEGORY_COMMAND: StringName = &"command"
const CATEGORY_STATEMENT: StringName = &"statement"

## 底色透明度的规范区间（20%~40%）。这是「美术规范」本身，
## 下面用 @export_range 变成编辑器里的硬约束，只写一次，不重复。
const BG_ALPHA_MIN: float = 0.2
const BG_ALPHA_MAX: float = 0.4
const BG_ALPHA_STEP: float = 0.01

## 变量积木颜色（如 "score"、"lives"）。
@export_color_no_alpha var variable_color: Color

## 数学积木颜色（如 + - * /）。
@export_color_no_alpha var math_color: Color

## 逻辑积木颜色（如 > == and not）。
@export_color_no_alpha var logic_color: Color

## 单行指令积木颜色（对应 AST_Command）。
@export_color_no_alpha var command_color: Color

## 控制流积木颜色（对应 AST_Statement）。
@export_color_no_alpha var statement_color: Color

## 积木底色透明度。@export_range 在编辑器中即为硬约束，
## 取区间中点作为默认值，保证默认状态本身就落在规范内。
@export_range(BG_ALPHA_MIN, BG_ALPHA_MAX, BG_ALPHA_STEP, "suffix:%") var background_alpha: float = (BG_ALPHA_MIN + BG_ALPHA_MAX) * 0.5


## 按类别取色。未知类别 push_error 并返回透明哨兵（非美术配色）。
func get_color_for_category(p_category: StringName) -> Color:
	match p_category:
		CATEGORY_VARIABLE:
			return variable_color
		CATEGORY_MATH:
			return math_color
		CATEGORY_LOGIC:
			return logic_color
		CATEGORY_COMMAND:
			return command_color
		CATEGORY_STATEMENT:
			return statement_color
		_:
			push_error("BlockPalette: 未知积木类别 '%s'。" % p_category)
			return Color.TRANSPARENT


## 叠加规范透明度后的积木底色，直接可赋给 StyleBoxFlat.bg_color。
func get_background_color(p_category: StringName) -> Color:
	var tint: Color = get_color_for_category(p_category)
	tint.a = background_alpha
	return tint


## 资源自检：返回问题描述列表，空数组表示已正确配置。
## 供美术在编辑器里核对 .tres 是否漏配。
func validate() -> PackedStringArray:
	var problems: PackedStringArray = []
	for property: String in COLOR_PROPERTIES:
		var value: Color = get(property)
		if value.r == 0.0 and value.g == 0.0 and value.b == 0.0:
			problems.append("%s 仍是未配置的默认黑，请在 .tres 里设置。" % property)
	if background_alpha < BG_ALPHA_MIN or background_alpha > BG_ALPHA_MAX:
		problems.append("background_alpha=%.3f 超出规范区间 %.0f%%~%.0f%%。" % [
			background_alpha, BG_ALPHA_MIN * 100.0, BG_ALPHA_MAX * 100.0,
		])
	return problems


## 需要美术配置的颜色属性名（自检用）。
const COLOR_PROPERTIES: PackedStringArray = [
	"variable_color",
	"math_color",
	"logic_color",
	"command_color",
	"statement_color",
]
