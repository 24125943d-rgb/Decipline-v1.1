@tool
extends EditorScript
## 阶段零 · 结构引导脚本（EditorScript）
##
## 用途：在 res://BlockSystem/ 下幂等地重建标准沙盒解耦目录树，
## 并为每个叶子目录补上 .gitkeep，保证 Git 子模块能跟踪空目录。
## 已存在的目录与文件不会被覆盖。
##
## 运行方式（任选其一）：
##   1. 在脚本编辑器中打开本文件 → 菜单 File > Run（快捷键 Ctrl+Shift+X）
##   2. 在 FileSystem 面板右键本文件 → Run
##
## 本脚本是开发期工具，不属于 Core / Logic / Art / Prefabs 任何一层，不参与运行时逻辑。

const MODULE_ROOT: String = "res://BlockSystem"

## 叶子目录（相对 MODULE_ROOT），与 README 的结构规范一一对应，请勿随意增删。
const LAYOUT: PackedStringArray = [
	"Core",
	"Logic",
	"Art/Themes",
	"Art/Palettes",
	"Art/Icons",
	"Prefabs",
]

const GITKEEP_CONTENT: String = "# 占位文件：让 Git 跟踪该空目录，请勿删除。\n"

## 结构树说明，用于打印到输出面板。
const LAYOUT_DESCRIPTION: Dictionary = {
	"Core": "纯数据层：AST 节点与解析器",
	"Logic": "交互层：拖拽、吸附、撤销重做",
	"Art/Themes": "美术专区：.theme 与 StyleBox",
	"Art/Palettes": "美术专区：.tres 配色资源",
	"Art/Icons": "美术专区：图标资源",
	"Prefabs": "组装层：代码块模板场景 (.tscn)",
}


func _run() -> void:
	print("=== BlockSystem 结构引导开始 ===")
	_ensure_directory(MODULE_ROOT)
	for relative_path: String in LAYOUT:
		_ensure_directory(MODULE_ROOT.path_join(relative_path))

	# 让新建目录立刻出现在 FileSystem 面板中。
	EditorInterface.get_resource_filesystem().scan()

	_print_layout()
	print("=== BlockSystem 结构引导完成 ===")


## 创建目录（含中间层级）并补齐 .gitkeep；已存在时跳过。
func _ensure_directory(path: String) -> void:
	if DirAccess.dir_exists_absolute(path):
		print("  [已存在] %s/" % path)
	else:
		var error: Error = DirAccess.make_dir_recursive_absolute(path)
		if error != OK:
			push_error("BlockSystem: 目录创建失败 %s（错误码 %d）" % [path, error])
			return
		print("  [新建]   %s/" % path)
	_ensure_gitkeep(path)


## 写入隐藏占位文件，使 Git 能跟踪空目录；已存在时不覆盖。
func _ensure_gitkeep(directory: String) -> void:
	var keep_path: String = directory.path_join(".gitkeep")
	if FileAccess.file_exists(keep_path):
		return
	var file: FileAccess = FileAccess.open(keep_path, FileAccess.WRITE)
	if file == null:
		push_warning("BlockSystem: 无法写入 %s（错误码 %d）" % [keep_path, FileAccess.get_open_error()])
		return
	file.store_string(GITKEEP_CONTENT)
	file.close()


func _print_layout() -> void:
	print("")
	print("res://BlockSystem/")
	print("├── Core/          纯数据层：AST 节点与解析器")
	print("├── Logic/         交互层：拖拽、吸附、撤销重做")
	print("├── Art/           美术专区")
	print("│   ├── Themes/    .theme 与 StyleBox")
	print("│   ├── Palettes/  .tres 配色资源")
	print("│   └── Icons/     图标资源")
	print("└── Prefabs/       组装层：代码块模板场景 (.tscn)")
	print("")
