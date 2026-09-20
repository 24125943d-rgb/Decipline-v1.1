class_name TemporaryModifierTable
extends RefCounted
## 临时修正表：管理游戏里所有【数值变更型】非永久修正（buff / debuff）的独立库。
##
## 它不是角色的属性——[AttributeCharacter] 完全不知道这张表的存在；由游戏代码（技能、道具、
## 事件、AI）来这里取修正，再施加到角色身上。
##
## [br][b]唯一合法来源[/b]：游戏里所有非永久修正都应该由 [method instantiate] /
## [method instantiate_for] 产出，不要手动 new [AttributeModifier]。
##
## [br][b]主键 / 候选键[/b]：每个元素有一个整数主键（[member TemporaryModifier.primary_key]）
## 和一个字符串候选键（[member TemporaryModifier.name]），两个都能查，且各自唯一。
##
## [br][b]数据从哪来[/b]：[constant DEFAULT_DIRECTORY] 目录里的 .tres（一个文件一个元素），
## 第一次用到这张表时会自动装一次（[method ensure_loaded]）；也可以 [method register] 代码构造的
## 元素，或 [method load_directory] 换目录。
##
## [codeblock]
## TemporaryModifierTable.instantiate_for(enemy, "虚弱")                       # 按候选键
## TemporaryModifierTable.instantiate_for(enemy, 2, {ATTR_STR: -5})            # 镣铐：按主键 + 参数
## TemporaryModifierTable.find_by_polarity(TemporaryModifier.Polarity.NEGATIVE)
## [/codeblock]

## 默认的数据目录：里面每个 .tres 是一个 [TemporaryModifier] 元素。
const DEFAULT_DIRECTORY: String = "res://data/temporary_modifiers"

## 主键 → 元素。
static var _by_key: Dictionary = {}
## 候选键（名称）→ 元素。
static var _by_name: Dictionary = {}
## 默认目录是不是已经装过了（保证只自动装一次）。
static var _defaults_loaded: bool = false

# ------------------------------------------------------------------ 注册 / 注销
## 把一个元素登记进表。[b]成功返回空字符串[/b]，失败返回原因（不写日志，调用方自己决定要不要记）。
static func register(entry: TemporaryModifier) -> String:
	if entry == null:
		return "元素为空"
	if entry.name.is_empty():
		return "缺少候选键（名称）"
	if entry.primary_key < 0:
		return "主键必须是 >= 0 的整数（当前 %d）" % entry.primary_key
	if not TemporaryModifier.is_allowed_kind(entry.kind):
		return "'%s' 是局外永久改动（直接写变量本体），不属于临时修正表" % entry.name
	if entry.is_temporary() and not entry.is_expiry_valid():
		return (
			"临时修正 '%s' 必须挂一个非空的结束判定脚本（继承 ModifierExpiry，不能是基类本身）"
			% entry.name
		)
	if entry.kind == AttributeModifier.Kind.IN_RUN_PERMANENT and entry.expiry != null:
		return "局内永久修正 '%s' 不该挂结束判定脚本（它一直生效到局结束）" % entry.name
	var existing: TemporaryModifier = find_by_key(entry.primary_key)
	if existing != null:
		return "主键 %d 已被 '%s' 占用" % [entry.primary_key, existing.name]
	if _by_name.has(entry.name):
		return "候选键 '%s' 已被占用" % entry.name
	_by_key[entry.primary_key] = entry
	_by_name[entry.name] = entry
	return ""


## 批量登记，返回成功条数（失败的会被跳过）。
static func register_all(entries: Array) -> int:
	var registered: int = 0
	for entry: Variant in entries:
		if register(entry as TemporaryModifier).is_empty():
			registered += 1
	return registered


## 按主键或候选键注销，返回是否真的注销了。
static func unregister(key_or_name: Variant) -> bool:
	var entry: TemporaryModifier = find(key_or_name)
	if entry == null:
		return false
	_by_key.erase(entry.primary_key)
	_by_name.erase(entry.name)
	return true


## 清空整张表（不影响“默认目录已装过”的标记）。
static func clear() -> void:
	_by_key.clear()
	_by_name.clear()

# ------------------------------------------------------------------ 查询
## 表里有多少元素。
static func size() -> int:
	return _by_key.size()


## 按主键或候选键查元素。[param key_or_name] 传 int 或 String / StringName。
static func find(key_or_name: Variant) -> TemporaryModifier:
	if key_or_name is int or key_or_name is float:
		return find_by_key(int(key_or_name))
	if key_or_name is String or key_or_name is StringName:
		return find_by_name(String(key_or_name))
	return null


## 按主键（[member TemporaryModifier.primary_key]）查。
static func find_by_key(primary_key: int) -> TemporaryModifier:
	return _by_key.get(primary_key) as TemporaryModifier


## 按候选键（[member TemporaryModifier.name]）查。
static func find_by_name(name: String) -> TemporaryModifier:
	return _by_name.get(name) as TemporaryModifier


## 表里有没有这个主键 / 候选键。
static func has(key_or_name: Variant) -> bool:
	return find(key_or_name) != null


## 全部元素，按主键排序。
static func all_entries() -> Array[TemporaryModifier]:
	var result: Array[TemporaryModifier] = []
	var sorted_keys: Array = _by_key.keys()
	sorted_keys.sort()
	for key: Variant in sorted_keys:
		result.append(_by_key[key] as TemporaryModifier)
	return result


## 全部主键，升序。
static func keys() -> Array[int]:
	var result: Array[int] = []
	var sorted_keys: Array = _by_key.keys()
	sorted_keys.sort()
	for key: Variant in sorted_keys:
		result.append(int(key))
	return result


## 全部候选键，按主键顺序。
static func names() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for entry: TemporaryModifier in all_entries():
		result.append(entry.name)
	return result


## 按正面 / 负面筛（挑诅咒、挑祝福常用）。
static func find_by_polarity(polarity: TemporaryModifier.Polarity) -> Array[TemporaryModifier]:
	return _filter(func(entry: TemporaryModifier) -> bool: return entry.polarity == polarity)


## 按种类筛。
static func find_by_kind(kind: AttributeModifier.Kind) -> Array[TemporaryModifier]:
	return _filter(func(entry: TemporaryModifier) -> bool: return entry.kind == kind)


# ------------------------------------------------------------------ 实例化（唯一合法来源）
## 按主键或候选键实例化一个修正。[param parameters] 只在非固定值修正上生效
## （属性序号 → 值），固定值修正会忽略它。找不到元素返回 null。
static func instantiate(key_or_name: Variant, parameters: Dictionary = {}) -> AttributeModifier:
	ensure_loaded()
	var entry: TemporaryModifier = find(key_or_name)
	if entry == null:
		push_error("临时修正表：找不到 %s，无法实例化。" % str(key_or_name))
		return null
	return entry.instantiate(parameters)


## 实例化并直接施加到角色身上，返回真正生效的那一份（想手动移除就留着它）。
static func instantiate_for(
	character: AttributeCharacter, key_or_name: Variant, parameters: Dictionary = {}
) -> AttributeModifier:
	if character == null:
		push_error("临时修正表：instantiate_for 需要一个 AttributeCharacter。")
		return null
	var modifier: AttributeModifier = instantiate(key_or_name, parameters)
	if modifier == null:
		return null
	return character.apply_modifier(modifier)

# ------------------------------------------------------------------ 数据装载
## 装载一个目录里的全部 .tres 元素，返回成功条数。
static func load_directory(path: String = DEFAULT_DIRECTORY) -> int:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return 0
	var files: PackedStringArray = directory.get_files()
	files.sort()
	var registered: int = 0
	for file: String in files:
		if not file.ends_with(".tres"):
			continue
		var full_path: String = path.path_join(file)
		var resource: Resource = load(full_path)
		var entry: TemporaryModifier = resource as TemporaryModifier
		if entry == null:
			push_warning("临时修正表：%s 不是 TemporaryModifier，已跳过。" % full_path)
			continue
		var error: String = register(entry)
		if error.is_empty():
			registered += 1
		else:
			push_warning("临时修正表：%s 登记失败 —— %s" % [full_path, error])
	return registered


## 保证默认目录只被自动装一次；重复调用不会有额外效果。返回本次装进来的条数。
static func ensure_loaded(path: String = DEFAULT_DIRECTORY) -> int:
	if _defaults_loaded:
		return 0
	_defaults_loaded = true
	return load_directory(path)

# ------------------------------------------------------------------ 内部
static func _filter(predicate: Callable) -> Array[TemporaryModifier]:
	var result: Array[TemporaryModifier] = []
	for entry: TemporaryModifier in all_entries():
		if predicate.call(entry):
			result.append(entry)
	return result
