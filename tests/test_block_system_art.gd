extends Node
## BlockSystem Art 层资源合规测试。
##
## 运行器约定：extends Node，方法名以 test_ 开头，返回 null = 通过、字符串 = 失败原因。
##
## 覆盖 README §2「Art 只被 Logic 读取」与 §7 的引擎实测结论：
##   · 所有 StyleBoxFlat 都要满足 BlockStyleSpec 规范（几何 + 底色透明度区间）
##   · 浮点比较必须带容差（§7.8：Color 是 float32，0.4 读回来是 0.40000000596）
##   · 主题必须注册各状态变体，且变体的样式几何同样合规
##   · §7.1：get_theme_stylebox 单参调用不查 type variation —— 这条引擎行为是整个
##     模块「显式传 type」写法的前提，一旦引擎改了行为，这里会先响
##   · §7.3：拖拽快照透明度取自主题项，而不是代码里的颜色兜底

const THEME_PATH: String = "res://BlockSystem/Art/Themes/block_theme.tres"
const PALETTE_PATH: String = BlockSyncEngine.DEFAULT_PALETTE
const THEMES_DIR: String = "res://BlockSystem/Art/Themes"

var _failures: PackedStringArray = PackedStringArray()
var _spawned: Array[Node] = []


func before_each() -> void:
	_failures.clear()


func after_each() -> void:
	for node: Node in _spawned:
		if is_instance_valid(node):
			node.free()
	_spawned.clear()

# ------------------------------------------------------------------ StyleBox 合规
func test_every_flat_stylebox_in_art_meets_the_spec() -> Variant:
	var checked: int = 0
	var problems: PackedStringArray = PackedStringArray()
	var directory: DirAccess = DirAccess.open(THEMES_DIR)
	if directory == null:
		_check(false, "打不开主题目录 %s" % THEMES_DIR)
		return _verdict("test_every_flat_stylebox_in_art_meets_the_spec")
	for entry: String in directory.get_files():
		if not entry.ends_with(".tres"):
			continue
		var resource: Resource = load(THEMES_DIR.path_join(entry))
		# 变体样式里有 StyleBoxEmpty（已填槽位不画底），它不是 StyleBoxFlat，跳过
		if not (resource is StyleBoxFlat):
			continue
		checked += 1
		for problem: String in BlockStyleSpec.validate(resource as StyleBoxFlat):
			problems.append("%s：%s" % [entry, problem])
	_check(checked >= 4, "只校验到 %d 个 StyleBoxFlat，可能空跑" % checked)
	_check(problems.is_empty(), "有 StyleBoxFlat 不符合规范：\n     " + "\n     ".join(problems))
	return _verdict("test_every_flat_stylebox_in_art_meets_the_spec")


func test_style_spec_rejects_bad_geometry() -> Variant:
	var bad: StyleBoxFlat = StyleBoxFlat.new()
	bad.content_margin_top = 5.0
	bad.content_margin_left = 0.0
	bad.border_width_left = 0
	bad.bg_color = Color(0.2, 0.2, 0.2, 0.9)
	var problems: PackedStringArray = BlockStyleSpec.validate(bad)
	_check(not problems.is_empty(), "违规样式必须报出问题")
	var joined: String = " ".join(problems)
	_check(joined.contains("content_margin_top"), "报出 content_margin_top")
	_check(joined.contains("content_margin_left"), "报出 content_margin_left")
	_check(joined.contains("border_width_left"), "报出 border_width_left")
	_check(joined.contains("bg_color.a"), "报出底色透明度越界")
	_check(not BlockStyleSpec.is_compliant(bad), "is_compliant 为 false")
	_check(BlockStyleSpec.validate(null).size() == 1, "传 null 返回一条说明而不是崩溃")
	return _verdict("test_style_spec_rejects_bad_geometry")


func test_style_spec_alpha_tolerance() -> Variant:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.content_margin_top = 0.0
	box.content_margin_bottom = 0.0
	box.content_margin_left = 8.0
	box.content_margin_right = 8.0
	box.border_width_top = 0
	box.border_width_bottom = 0
	box.border_width_left = 2
	box.border_width_right = 2
	# §7.8：正好卡在边界上的值必须放行（float32 存不下 0.4）
	box.bg_color = Color(0.2, 0.2, 0.2, BlockPalette.BG_ALPHA_MAX)
	_check(BlockStyleSpec.is_compliant(box), "正好等于上边界视为合规")
	box.bg_color = Color(0.2, 0.2, 0.2, BlockPalette.BG_ALPHA_MAX + BlockStyleSpec.ALPHA_TOLERANCE * 0.5)
	_check(BlockStyleSpec.is_compliant(box), "误差在容差内视为合规")
	box.bg_color = Color(0.2, 0.2, 0.2, BlockPalette.BG_ALPHA_MAX + 0.01)
	_check(not BlockStyleSpec.is_compliant(box), "超出容差判为越界")
	box.bg_color = Color(0.2, 0.2, 0.2, BlockPalette.BG_ALPHA_MIN - 0.01)
	_check(not BlockStyleSpec.is_compliant(box), "低于下边界判为越界")
	return _verdict("test_style_spec_alpha_tolerance")


func test_spec_describes_itself() -> Variant:
	var text: String = BlockStyleSpec.describe()
	_check(text.contains("8"), "摘要里带上左内边距")
	_check(text.contains("20") and text.contains("40"), "摘要里带上透明度区间（20%~40%）")
	return _verdict("test_spec_describes_itself")

# ------------------------------------------------------------------ 调色板
func test_palette_default_is_fully_configured() -> Variant:
	var palette: BlockPalette = load(PALETTE_PATH) as BlockPalette
	_check(palette != null, "默认调色板能加载")
	if palette == null:
		return _verdict("test_palette_default_is_fully_configured")
	_check(palette.validate().is_empty(), "自检无问题：%s" % str(palette.validate()))
	var colors: Array[Color] = []
	for property: String in BlockPalette.COLOR_PROPERTIES:
		colors.append(palette.get(property))
	for i: int in colors.size():
		_check(colors[i].get_luminance() > 0.0, "%s 不是未配置的默认黑" % BlockPalette.COLOR_PROPERTIES[i])
		for j: int in range(i + 1, colors.size()):
			_check(
				colors[i] != colors[j],
				"%s 与 %s 不应同色" % [BlockPalette.COLOR_PROPERTIES[i], BlockPalette.COLOR_PROPERTIES[j]]
			)
	_check(
		palette.background_alpha >= BlockPalette.BG_ALPHA_MIN
			and palette.background_alpha <= BlockPalette.BG_ALPHA_MAX,
		"背景透明度在规范区间内"
	)
	return _verdict("test_palette_default_is_fully_configured")


func test_palette_lookup_and_background_color() -> Variant:
	var palette: BlockPalette = load(PALETTE_PATH) as BlockPalette
	if palette == null:
		_check(false, "默认调色板能加载")
		return _verdict("test_palette_lookup_and_background_color")
	var pairs: Dictionary = {
		BlockPalette.CATEGORY_VARIABLE: "variable_color",
		BlockPalette.CATEGORY_MATH: "math_color",
		BlockPalette.CATEGORY_LOGIC: "logic_color",
		BlockPalette.CATEGORY_COMMAND: "command_color",
		BlockPalette.CATEGORY_STATEMENT: "statement_color",
	}
	for category: StringName in pairs:
		var property: String = pairs[category]
		_check_eq(palette.get_color_for_category(category), palette.get(property), "类别 %s 取色" % category)
		var background: Color = palette.get_background_color(category)
		# §7.8：Color 是 float32，0.3 读回来是 0.30000001192，必须带容差比较
		_check(
			is_equal_approx(background.a, palette.background_alpha),
			"类别 %s 的底色用规范透明度（期望 %f，实际 %f）" % [
				category, palette.background_alpha, background.a,
			]
		)
		_check_eq(background.to_html(false), (palette.get(property) as Color).to_html(false), "底色只改透明度，不动 RGB")
	return _verdict("test_palette_lookup_and_background_color")

# ------------------------------------------------------------------ 主题
func test_theme_registers_required_variations() -> Variant:
	var theme: Theme = load(THEME_PATH) as Theme
	_check(theme != null, "主题能加载")
	if theme == null:
		return _verdict("test_theme_registers_required_variations")
	var panel_variations: PackedStringArray = [
		"ExpressionBlock", "ExpressionBlock_Hovered", "ExpressionBlock_Wrapped", "CommandBlock",
		"SlotPlaceholder", "SlotFilled", "SlotRejected",
	]
	for variation: String in panel_variations:
		_check(theme.has_stylebox(&"panel", StringName(variation)), "变体 %s 定义了 panel 样式" % variation)
		_check_eq(
			theme.get_type_variation_base(StringName(variation)), &"PanelContainer",
			"变体 %s 的基类是 PanelContainer" % variation
		)
	_check_eq(
		theme.get_type_variation_base(&"StatementBlock_Hovered"), &"VBoxContainer",
		"语句落点变体的基类是 VBoxContainer"
	)
	_check(
		theme.has_constant(&"separation", &"StatementBlock_Hovered"),
		"语句落点变体靠加大 separation 提示落点"
	)
	_check(
		theme.has_color(BlockDragDrop.PREVIEW_MODULATE, BlockDragDrop.PREVIEW_THEME_TYPE),
		"拖拽快照透明度是主题项（不是代码里的颜色）"
	)
	return _verdict("test_theme_registers_required_variations")


func test_theme_styleboxes_match_the_spec() -> Variant:
	var theme: Theme = load(THEME_PATH) as Theme
	if theme == null:
		_check(false, "主题能加载")
		return _verdict("test_theme_styleboxes_match_the_spec")
	var checked: int = 0
	var problems: PackedStringArray = PackedStringArray()
	for variation: String in [
		"ExpressionBlock", "ExpressionBlock_Hovered", "ExpressionBlock_Wrapped", "CommandBlock",
		"SlotPlaceholder", "SlotRejected",
	]:
		var box: StyleBox = theme.get_stylebox(&"panel", StringName(variation))
		if not (box is StyleBoxFlat):
			_check(false, "变体 %s 的 panel 不是 StyleBoxFlat" % variation)
			continue
		checked += 1
		for problem: String in BlockStyleSpec.validate(box as StyleBoxFlat):
			problems.append("%s：%s" % [variation, problem])
	_check(checked >= 5, "只校验到 %d 个变体样式，可能空跑" % checked)
	_check(problems.is_empty(), "主题里的样式不符合规范：\n     " + "\n     ".join(problems))
	return _verdict("test_theme_styleboxes_match_the_spec")


## 版本行为哨兵：README §7.1 记录「单参 get_theme_stylebox 不会查 type variation」。
## 本用例实测 Godot 4.7.2 的真实行为：**变体会被解析**，两种取法拿到同一份样式 —— 与 §7.1 的
## 旧结论不符（该结论可能来自更早的 4.x）。保留这条用例是为了钉住行为：若引擎回退到旧行为，
## 这里会先响。模块里一律显式传 type 的写法在两种行为下都安全，所以无需改动它。
func test_variation_lookup_resolves_the_same_stylebox_either_way() -> Variant:
	var theme: Theme = load(THEME_PATH) as Theme
	if theme == null:
		_check(false, "主题能加载")
		return _verdict("test_variation_lookup_resolves_the_same_stylebox_either_way")
	var panel: PanelContainer = PanelContainer.new()
	panel.theme = theme
	panel.set_theme_type_variation(&"ExpressionBlock")
	add_child(panel)
	_spawned.append(panel)
	var one_arg: StyleBox = panel.get_theme_stylebox(&"panel")
	var with_type: StyleBox = panel.get_theme_stylebox(&"panel", &"ExpressionBlock")
	_check(one_arg != null and with_type != null, "两种取法都拿得到样式")
	_check_eq(one_arg, with_type, "4.7.2 实测：单参取法也会解析变体")
	_check_eq(
		panel.get_theme_type_variation(), &"ExpressionBlock",
		"节点的变体名确实是 ExpressionBlock（否则上面的结论无意义）"
	)
	if with_type is StyleBoxFlat:
		_check_eq(
			(with_type as StyleBoxFlat).content_margin_left, BlockStyleSpec.CONTENT_MARGIN_LEFT,
			"拿到的是美术配的几何"
		)
	return _verdict("test_variation_lookup_resolves_the_same_stylebox_either_way")


func test_slot_variations_used_by_the_prefab_exist_in_the_theme() -> Variant:
	var theme: Theme = load(THEME_PATH) as Theme
	var scene: PackedScene = load(SlotUI.TEMPLATE) as PackedScene
	_check(scene != null, "插槽模板能加载")
	if scene == null or theme == null:
		return _verdict("test_slot_variations_used_by_the_prefab_exist_in_the_theme")
	var slot: SlotUI = scene.instantiate() as SlotUI
	_check(slot != null, "模板根节点是 SlotUI")
	if slot == null:
		return _verdict("test_slot_variations_used_by_the_prefab_exist_in_the_theme")
	# 脚本侧的变体名与 Art 侧的注册名必须对上：任一侧改名都要同步，否则视觉静默失效
	for variation: StringName in [slot.empty_variation, slot.filled_variation, slot.rejected_variation]:
		_check(theme.has_stylebox(&"panel", variation), "主题里注册了插槽变体 %s" % variation)
	slot.free()
	return _verdict("test_slot_variations_used_by_the_prefab_exist_in_the_theme")


func test_preview_modulate_comes_from_the_theme() -> Variant:
	# §7.3：拖拽快照透明度取自主题项 BlockDrag/preview_modulate，
	# 代码里只保留 Color.WHITE 作为条目缺席时的兜底（不写死颜色字面量）
	var theme: Theme = load(THEME_PATH) as Theme
	var slot: SlotUI = SlotUI.create(AST_BlockSchema.ROLE_LEFT)
	_check(slot != null, "能造出插槽")
	if slot == null or theme == null:
		return _verdict("test_preview_modulate_comes_from_the_theme")
	add_child(slot)
	_spawned.append(slot)
	var resolved: Color = BlockDragDrop.resolve_preview_modulate(slot)
	_check_eq(
		resolved, theme.get_color(BlockDragDrop.PREVIEW_MODULATE, BlockDragDrop.PREVIEW_THEME_TYPE),
		"透明度与主题项一致"
	)
	_check(resolved != Color.WHITE, "不是代码里的白色兜底")
	_check(resolved.a < 1.0, "快照是半透明的")
	return _verdict("test_preview_modulate_comes_from_the_theme")

# ------------------------------------------------------------------ 工具
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
