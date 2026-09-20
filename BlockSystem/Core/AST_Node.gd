class_name AST_Node
extends RefCounted
## AST 节点基类 —— 纯数据层（Core）。
##
## 架构约束（见 res://BlockSystem/README.md 第 4 节）：
## - 只继承 RefCounted，不触碰 Node / SceneTree，可在 headless 环境脱离场景独立测试。
## - 序列化契约：每个节点序列化后必定带 `type` 字段，反序列化时由 ASTManager
##   依据该字段派发到具体子类。
##
## 实现说明：GDScript 不允许子类覆写父类常量（会报 "member already exists in
## parent class"），因此 type 是实例字段，由各子类在自己的 _init() 中写入，
## 而不是多态常量。

## type 字段的合法取值之一（与子类一一对应）。
const TYPE_NODE: String = "node"

## 节点种类标识，参与序列化。由具体子类在 _init() 中写入。
var type: String = TYPE_NODE


## 导出为可被 JSON.stringify 处理的普通 Dictionary。
## 子类覆写本方法时必须保留 "type" 字段。
func to_dictionary() -> Dictionary:
	return {"type": type}


## 供 Godot 调试器与 print() 使用的简短描述。
func _to_string() -> String:
	return "<%s>" % type
