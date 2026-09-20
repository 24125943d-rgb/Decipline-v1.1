extends VBoxContainer
## 开发期演示场景：用 BlockSyncEngine 把一棵 AST 渲染成积木，再把它编译回 AST。
##
## 下划线前缀 = 开发 / 演示工具，与 _bootstrap_structure.gd 同类，
## 不属于 Core / Logic / Art / Prefabs 任何一层，也不参与运行时逻辑。
##
## 用途：手动验证「AST -> UI -> AST」整条链路（正式画布见后续阶段）。

## 引擎实例（必须在场景树里，才能 await process_frame）。
var _engine: BlockSyncEngine = null

## 构建出来的根积木。
var _block_ui: Control = null


func _ready() -> void:
	_engine = BlockSyncEngine.new()
	add_child(_engine)

	var program: AST_Node = ASTManager.from_dictionary(_demo_program())
	print("=== 源 AST ===")
	print(ASTManager.serialize_ast_to_json(program))

	_block_ui = await _engine.build_ui_from_ast(program)
	if _block_ui == null:
		push_error("演示场景：构建失败。")
		return
	add_child(_block_ui)

	# 反向：把当前 UI 编译回 AST，证明双向通路成立
	var rebuilt: AST_Node = _engine.build_ast_from_ui(_block_ui)
	print("=== 由 UI 重建的 AST ===")
	print(ASTManager.serialize_ast_to_json(rebuilt))
	print("=== 双向一致: ", rebuilt != null and rebuilt.to_dictionary() == program.to_dictionary(), " ===")


## 演示程序：if (score > 3) { move_forward 3 fast; turn_left 90; repeat { say hello } }
func _demo_program() -> Dictionary:
	return {
		"type": "statement",
		"condition": _binary(">", _literal("score"), _literal(3)),
		"body": [
			{"type": "command", "opcode": "move_forward", "args": [3, "fast"]},
			{"type": "command", "opcode": "turn_left", "args": [90]},
			{
				"type": "statement",
				"condition": null,
				"body": [{"type": "command", "opcode": "say", "args": ["hello"]}],
			},
		],
	}


func _literal(value: Variant) -> Dictionary:
	return {"type": "expression", "operator": "", "left": null, "right": null, "value": value}


func _binary(operator: String, left: Dictionary, right: Dictionary) -> Dictionary:
	return {"type": "expression", "operator": operator, "left": left, "right": right, "value": null}
