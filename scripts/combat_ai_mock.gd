class_name CombatAIMock
extends RefCounted
## 第一个实战业务逻辑的 AST 样例：AI 战斗决策（纯 Dictionary 手写，不经过 UI 画布）。
##
## [codeblock]
## WHILE SEE Enemies
##     IF Enemy.closest IN Attack-range
##         ATTACK Enemy.closest
##     ELSE
##         CHASE Enemy.closest
## [/codeblock]
##
## [br][b]变量与条件约定[/b]
## [br]· "SEE Enemies"     → 变量节点 [code]{"type": "variable", "name": "enemies_visible"}[/code]
## [br]· "IN Attack-range" → [code]in[/code] 表达式：[code]closest_enemy IN attack_range[/code]
##   （左是对象积木，右是带 [code]contains()[/code] 的范围对象）
## [br]· ATTACK / CHASE    → [AST_Command]，args 里带目标参数 [code]"closest_enemy"[/code]
##   （宿主按名字解析目标，例如实现 [code]attack(who: String)[/code]）
## [br]· WHILE 用 [code]"loop": true[/code] + 非空 condition 表达；
##   每个 statement / command 都带 [code]uuid[/code]，供 [ASTCompiler] 注入探针。
##
## [br]整棵树的形状与字段名都在 [method get_combat_ai_ast] 里，可以直接喂给
## [code]ASTManager.from_dictionary()[/code] → [code]ASTCompiler.generate_gdscript()[/code]。

## 探针 uuid：一眼能看出对应哪块积木。
const UUID_WHILE: String = "uuid_while_1"
const UUID_IF: String = "uuid_if_1"
const UUID_ATTACK: String = "uuid_attack_1"
const UUID_CHASE: String = "uuid_chase_1"


## 手写这棵语法树。返回纯 Dictionary，可 JSON 序列化。
static func get_combat_ai_ast() -> Dictionary:
	return {
		"type": "statement",
		"uuid": UUID_WHILE,
		"loop": true,
		"condition": _variable("enemies_visible"),
		"body": [
			{
				"type": "statement",
				"uuid": UUID_IF,
				"condition": _in_range(
					_variable("closest_enemy"), _variable("attack_range")
				),
				"body": [_command(UUID_ATTACK, "attack")],
				"else_body": [_command(UUID_CHASE, "chase")],
			},
		],
	}


## Dedicated strict Character example; legacy generic mock remains unchanged.
static func get_character_program_ast() -> Dictionary:
	return {
		"type": "statement", "loop": true,
		"condition": _variable("Enemy.visible.exists"),
		"body": [{
			"type": "statement",
			"condition": _in_range(_variable("Enemy.visible.closest"), _variable("Attack-range")),
			"body": [{"type": "command", "opcode": "Attack", "args": [_variable("Enemy.visible.closest")]}],
			"else_body": [{"type": "command", "opcode": "Chase", "args": [_variable("Enemy.visible.closest")]}]
		}]
	}

## Opt-in contact program; legacy/B and bootstrap remain unchanged.
static func get_character_attach_program_ast() -> Dictionary:
	var program: Dictionary = get_character_program_ast()
	program.body[0].condition = {
		"type": "expression", "operator": "attach",
		"left": _variable("Self"), "right": _variable("Enemy.visible.closest"), "value": null
	}
	return program

## 变量引用节点。
static func _variable(variable_name: String) -> Dictionary:
	return {"type": "variable", "name": variable_name}


## 「左 IN 右」：左 = 对象（哪个敌人），右 = 范围对象（宿主提供，带 contains()）。
static func _in_range(left: Dictionary, right: Dictionary) -> Dictionary:
	return {
		"type": "expression",
		"operator": "in",
		"left": left,
		"right": right,
		"value": null,
	}


## 指令节点：目标是[b]对象参数[/b]（一个变量积木），会嵌进指令的参数槽里显示，
## 而不是拼进指令自己的文本。
static func _command(uuid: String, opcode: String) -> Dictionary:
	return {
		"type": "command",
		"uuid": uuid,
		"opcode": opcode,
		"args": [_variable("closest_enemy")],
	}
