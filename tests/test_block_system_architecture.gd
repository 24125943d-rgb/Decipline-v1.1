extends Node
## BlockSystem 架构约束测试 —— README §4「五条硬性解耦规则」的可执行版本。
##
## 运行器约定：extends Node，方法名以 test_ 开头，返回 null = 通过、字符串 = 失败原因。
##
## README §4 的自检目前只能靠手工跑 rg，容易漏；这里把它固化成回归测试：
##   规则 1 沙盒封闭：BlockSystem/ 内不得出现指向沙盒外部的 res:// 路径
##   规则 2 Core 无引擎依赖：只继承 RefCounted 或本层数据类，不碰 Node / SceneTree
##   规则 3 Logic 无美术字面量：不得出现数值形式的颜色字面量
##   规则 4 Art 无行为逻辑：Art/ 下唯一的脚本是数据类 BlockPalette.gd
##   规则 5（收紧版）分层只许向上：Core 只依赖 Core、Art 只依赖 Art
## 另含 README §7.2 的场景文件陷阱：@export 节点引用必须在节点头写 node_paths。
##
## 扫描一律先去注释（_code_lines）：README 的说明文字与被注释掉的示例不该算违规。

const ROOT: String = "res://BlockSystem"
const CORE_DIR: String = ROOT + "/Core"
const LOGIC_DIR: String = ROOT + "/Logic"
const ART_DIR: String = ROOT + "/Art"
const PREFAB_DIR: String = ROOT + "/Prefabs"

## 只允许数据类脚本出现在 Art/（README §2「Art 无逻辑」的唯一例外）。
const ART_ALLOWED_SCRIPT: String = ART_DIR + "/Palettes/BlockPalette.gd"

## Node 家族：Core 层一旦出现即为违规。
const ENGINE_NODES: PackedStringArray = [
	"Node", "Node2D", "Node3D", "Control", "CanvasItem", "Container", "SceneTree", "MainLoop", "Object",
]

var _failures: PackedStringArray = PackedStringArray()


func before_each() -> void:
	_failures.clear()

# ------------------------------------------------------------------ 规则 1：沙盒封闭
func test_rule1_sandbox_is_closed() -> Variant:
	var offenders: PackedStringArray = PackedStringArray()
	# 1a) .gd 里的 res:// 引用（只看代码，注释里的举例不算）
	for path: String in _files_under(ROOT, ".gd"):
		for hit: String in _res_paths_in(_code_text(path)):
			if not hit.begins_with(ROOT):
				offenders.append("%s 引用了沙盒外路径：%s" % [path.get_file(), hit])
	# 1b) 场景 / 资源里的 ext_resource 路径（真引用，不存在注释问题）
	for suffix: String in [".tscn", ".tres"]:
		for path: String in _files_under(ROOT, suffix):
			for hit: String in _res_paths_in(_read(path)):
				if not hit.begins_with(ROOT):
					offenders.append("%s 的 ext_resource 越界：%s" % [path.get_file(), hit])
	var scanned: int = (
		_files_under(ROOT, ".gd").size()
		+ _files_under(ROOT, ".tscn").size()
		+ _files_under(ROOT, ".tres").size()
	)
	_check(scanned >= 25, "扫描到的沙盒文件太少（%d），_files_under 可能失效导致本用例空跑" % scanned)
	_check(offenders.is_empty(), "沙盒封闭被破坏：\n     " + "\n     ".join(offenders))
	return _verdict("test_rule1_sandbox_is_closed")

# ------------------------------------------------------------------ 规则 2：Core 无引擎依赖
func test_rule2_core_has_no_engine_dependency() -> Variant:
	var problems: PackedStringArray = PackedStringArray()
	var local_classes: PackedStringArray = _class_names_in(CORE_DIR)
	for path: String in _files_under(CORE_DIR, ".gd"):
		var text: String = _code_text(path)
		var base: String = _extends_of(text)
		if base.is_empty():
			problems.append("%s 缺少 extends" % path.get_file())
		elif base != "RefCounted" and not local_classes.has(base):
			problems.append("%s 应继承 RefCounted 或本层数据类，实际 %s" % [path.get_file(), base])
		for needle: String in ["get_tree(", "is_inside_tree(", "add_child(", "Node.new(", "SceneTree"]:
			if text.contains(needle):
				problems.append("%s 出现引擎场景依赖：%s" % [path.get_file(), needle])
	_check(
		_files_under(CORE_DIR, ".gd").size() >= 7,
		"Core 层扫描到的脚本太少（%d），本用例可能空跑" % _files_under(CORE_DIR, ".gd").size()
	)
	_check(problems.is_empty(), "Core 层有引擎依赖：\n     " + "\n     ".join(problems))
	return _verdict("test_rule2_core_has_no_engine_dependency")

# ------------------------------------------------------------------ 规则 3：Logic 无美术字面量
func test_rule3_logic_has_no_art_literals() -> Variant:
	# 数值形式的 Color(...) 是写死的颜色；Color.WHITE / Color.TRANSPARENT 这类命名常量是允许的
	# （README §2：Logic 只做「合并」，不「决定」外观）。
	var pattern: RegEx = RegEx.new()
	pattern.compile("Color\\(\\s*[0-9]")
	var problems: PackedStringArray = PackedStringArray()
	for path: String in _files_under(LOGIC_DIR, ".gd"):
		var text: String = _code_text(path)
		if pattern.search(text) != null:
			problems.append("%s 里出现数值颜色字面量" % path.get_file())
		for needle: String in ["res://BlockSystem/Art/Icons", "add_theme_font_size_override", "font_size ="]:
			if text.contains(needle):
				problems.append("%s 里写死了美术值：%s" % [path.get_file(), needle])
	_check(
		_files_under(LOGIC_DIR, ".gd").size() >= 6,
		"Logic 层扫描到的脚本太少（%d），本用例可能空跑" % _files_under(LOGIC_DIR, ".gd").size()
	)
	_check(problems.is_empty(), "Logic 层写死了美术值：\n     " + "\n     ".join(problems))
	return _verdict("test_rule3_logic_has_no_art_literals")

# ------------------------------------------------------------------ 规则 4：Art 无逻辑
func test_rule4_art_has_only_the_palette_data_class() -> Variant:
	var scripts: PackedStringArray = PackedStringArray()
	for path: String in _files_under(ART_DIR, ".gd"):
		scripts.append(path)
	_check(
		scripts == PackedStringArray([ART_ALLOWED_SCRIPT]),
		"Art/ 下只允许数据类 BlockPalette.gd，实际有：%s" % str(scripts)
	)

	var foreign: PackedStringArray = PackedStringArray()
	for suffix: String in [".tscn", ".tres"]:
		for path: String in _files_under(ART_DIR, suffix):
			var text: String = _read(path)
			var from: int = 0
			while true:
				var at: int = text.find("[ext_resource type=\"Script\"", from)
				if at < 0:
					break
				var line_end: int = text.find("\n", at)
				var line: String = text.substr(at, (line_end if line_end > 0 else text.length()) - at)
				if not line.contains("BlockPalette.gd"):
					foreign.append("%s：%s" % [path.get_file(), line])
				from = at + 10
	_check(foreign.is_empty(), "Art/ 资源挂了行为脚本：\n     " + "\n     ".join(foreign))
	return _verdict("test_rule4_art_has_only_the_palette_data_class")

# ------------------------------------------------------------------ 规则 5：分层只许向上
func test_rule5_core_depends_only_on_core() -> Variant:
	var offenders: PackedStringArray = PackedStringArray()
	var forbidden_paths: PackedStringArray = [LOGIC_DIR, ART_DIR, PREFAB_DIR]
	var forbidden_names: PackedStringArray = _class_names_in(LOGIC_DIR) + _class_names_in(ART_DIR)
	for path: String in _files_under(CORE_DIR, ".gd"):
		var text: String = _code_text(path)
		for needle: String in forbidden_paths:
			if text.contains(needle):
				offenders.append("%s 引用了上层路径 %s" % [path.get_file(), needle])
		for needle: String in forbidden_names:
			if _mentions_word(text, needle):
				offenders.append("%s 引用了上层类 %s" % [path.get_file(), needle])
	_check(
		forbidden_names.size() >= 8,
		"上层类名清单只解析出 %d 个，扫描失效会让本用例空跑" % forbidden_names.size()
	)
	_check(offenders.is_empty(), "Core 反向依赖了上层：\n     " + "\n     ".join(offenders))
	return _verdict("test_rule5_core_depends_only_on_core")


func test_rule5_art_depends_only_on_art() -> Variant:
	var offenders: PackedStringArray = PackedStringArray()
	var forbidden_paths: PackedStringArray = [CORE_DIR, LOGIC_DIR, PREFAB_DIR]
	var forbidden_names: PackedStringArray = _class_names_in(CORE_DIR) + _class_names_in(LOGIC_DIR)
	for path: String in _files_under(ART_DIR, ".gd"):
		var text: String = _code_text(path)
		for needle: String in forbidden_paths:
			if text.contains(needle):
				offenders.append("%s 引用了他层路径 %s" % [path.get_file(), needle])
		for needle: String in forbidden_names:
			if _mentions_word(text, needle):
				offenders.append("%s 引用了他层类 %s" % [path.get_file(), needle])
	_check(
		forbidden_names.size() >= 10,
		"他层类名清单只解析出 %d 个，扫描失效会让本用例空跑" % forbidden_names.size()
	)
	_check(offenders.is_empty(), "Art 反向依赖了别的层：\n     " + "\n     ".join(offenders))
	return _verdict("test_rule5_art_depends_only_on_art")

# ------------------------------------------------------------------ §7.2 场景文件陷阱
func test_prefabs_declare_node_paths_for_exported_node_refs() -> Variant:
	var problems: PackedStringArray = PackedStringArray()
	for path: String in _files_under(PREFAB_DIR, ".tscn"):
		var lines: PackedStringArray = _read(path).split("\n")
		var declared: PackedStringArray = PackedStringArray()
		for raw: String in lines:
			var line: String = raw.strip_edges()
			if line.begins_with("[node "):
				declared = _packed_strings_in(line, "node_paths=")
				continue
			if not line.contains("= NodePath("):
				continue
			var property: String = line.split("=")[0].strip_edges()
			# 节点头里的 node_paths=… 是唯一能让这些属性在加载后非空的方式（README §7.2）
			if not declared.has(property):
				problems.append("%s：属性 %s 是 NodePath，但节点头没写 node_paths" % [
					path.get_file(), property,
				])
	_check(
		_files_under(PREFAB_DIR, ".tscn").size() >= 4,
		"Prefabs 只扫到 %d 个场景，本用例可能空跑" % _files_under(PREFAB_DIR, ".tscn").size()
	)
	_check(problems.is_empty(), "存在加载后恒为 null 的节点引用：\n     " + "\n     ".join(problems))
	return _verdict("test_prefabs_declare_node_paths_for_exported_node_refs")

# ------------------------------------------------------------------ 工具：文件扫描
## 递归收集目录下指定后缀的文件（res:// 路径）。DirAccess 默认不列隐藏文件，.gitkeep 天然被跳过。
func _files_under(dir_path: String, suffix: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var directory: DirAccess = DirAccess.open(dir_path)
	if directory == null:
		return result
	for entry: String in directory.get_files():
		var full: String = dir_path.path_join(entry)
		if entry.ends_with(suffix):
			result.append(full)
	for entry: String in directory.get_directories():
		result.append_array(_files_under(dir_path.path_join(entry), suffix))
	return result


func _read(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


## 去掉整行注释与行尾注释后的代码文本（README 的说明文字不该被判违规）。
func _code_text(path: String) -> String:
	var kept: PackedStringArray = PackedStringArray()
	for raw: String in _read(path).split("\n"):
		var line: String = raw
		var comment: int = line.find("#")
		if comment >= 0:
			line = line.substr(0, comment)
		var trimmed: String = line.strip_edges()
		if not trimmed.is_empty():
			kept.append(trimmed)
	return "\n".join(kept)


## 文本里所有 res:// 开头的路径片段。
func _res_paths_in(text: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var from: int = 0
	while true:
		var at: int = text.find("res://", from)
		if at < 0:
			break
		var stop: int = at
		while stop < text.length() and _is_path_char(text[stop]):
			stop += 1
		result.append(text.substr(at, stop - at))
		from = at + 6
	return result


func _is_path_char(character: String) -> bool:
	if character == "\"" or character == "'" or character == ")" or character == "," or character == "\n":
		return false
	return not character.strip_edges().is_empty()


## 文件里 "extends X" 的基类名（无则空串）。
func _extends_of(text: String) -> String:
	for raw: String in text.split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("extends "):
			return line.substr(8).split(" ")[0].split("(")[0].strip_edges()
	return ""


## 目录内所有 class_name 声明。
func _class_names_in(dir_path: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for path: String in _files_under(dir_path, ".gd"):
		for raw: String in _code_text(path).split("\n"):
			var line: String = raw.strip_edges()
			if line.begins_with("class_name "):
				result.append(line.substr(11).split(" ")[0].strip_edges())
	return result


## 是否以「独立单词」形式出现了某个标识符（避免 BlockPalette2 命中 BlockPalette）。
func _mentions_word(text: String, word: String) -> bool:
	if word.is_empty():
		return false
	var from: int = 0
	while true:
		var at: int = text.find(word, from)
		if at < 0:
			return false
		var before_ok: bool = at == 0 or not _is_word_char(text[at - 1])
		var after: int = at + word.length()
		var after_ok: bool = after >= text.length() or not _is_word_char(text[after])
		if before_ok and after_ok:
			return true
		from = at + 1
	return false


func _is_word_char(character: String) -> bool:
	return character.is_valid_identifier() or character == "_"


## 形如 node_paths=PackedStringArray("a", "b") 里的字符串列表。
func _packed_strings_in(line: String, key: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var at: int = line.find(key)
	if at < 0:
		return result
	for raw: String in line.substr(at).split(","):
		var quote: int = raw.find("\"")
		if quote < 0:
			continue
		var end: int = raw.find("\"", quote + 1)
		if end > quote:
			result.append(raw.substr(quote + 1, end - quote - 1))
	return result


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)


func _verdict(test_name: String) -> Variant:
	if _failures.is_empty():
		print("PASS  ", test_name)
		return null
	var message: String = ""
	for failure: String in _failures:
		message += "\n   - " + failure
	print("FAIL  ", test_name, message)
	return message
