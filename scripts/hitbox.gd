class_name Hitbox
extends Area3D
## 攻击判定框（[Character] 的 `Hurtbox` 的对手方）。
##
## 约定：[b]伤害由受击方结算[/b]。Hitbox 只负责携带伤害数据并广播 [signal hit]，
## 不会自己扣血——这样一次攻击不会既被 Hitbox 又被 Hurtbox 重复结算。
## 把 [Character] 的 Hurtbox 放到 [constant Character.LAYER_HURTBOX]，本节点 mask 勾上
## 同一层，两者重叠时受击方会收到伤害。
##
## 招式开关：平时 `monitoring = false`，挥到判定帧时打开；配合 [member one_shot]
## 可以做到“一次挥击只命中一次”。

## 命中时广播，可以用来放特效 / 音效。
signal hit(hurtbox: Area3D)

## HP 伤害。
@export var damage: int = 10:
	set(value):
		damage = maxi(value, 0)

## sanity 伤害。
@export var sanity_damage: int = 0:
	set(value):
		sanity_damage = maxi(value, 0)

## 命中一次后自动关闭判定（单次挥击）。
@export var one_shot: bool = false

## 攻击判定所在的碰撞层，默认 [constant Character.LAYER_HITBOX]。
@export var attack_layer: int = Character.LAYER_HITBOX
## 攻击判定要扫描的层，默认 [constant Character.LAYER_HURTBOX]（角色的受击层）。
@export var target_mask: int = Character.LAYER_HURTBOX

func _ready() -> void:
	add_to_group(Character.GROUP_HITBOX)
	# 代码 new 出来的 Hitbox 也要落在正确的层上，不能只靠场景文件里的设置
	collision_layer = attack_layer
	collision_mask = target_mask
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)


func _on_area_entered(area: Area3D) -> void:
	if area == null:
		return
	var victim: Character = area.get_parent() as Character
	if victim == null:
		return
	hit.emit(area)
	if one_shot:
		monitoring = false
