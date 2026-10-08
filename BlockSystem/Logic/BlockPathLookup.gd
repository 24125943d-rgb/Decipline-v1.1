extends RefCounted
## Shared structural-path lookup. Must not depend on ASTCompiler: its inner
## ExecutionHighlighter otherwise retains its owning script at engine shutdown.

static func find_block_by_id(ui_root: Control, block_uuid: String) -> Control:
	if ui_root == null or block_uuid.is_empty():
		return null
	var segments: PackedStringArray = block_uuid.split(".")
	if segments.is_empty() or segments[0] != "root":
		return null
	var current: Control = BlockSyncEngine.as_block(ui_root)
	if current == null:
		current = _first_block(ui_root)
	var index: int = 1
	while index < segments.size() and current != null:
		var role: String = segments[index]
		var slot_property: StringName = BlockSyncEngine.ROLE_SLOTS.get(StringName(role), &"")
		if slot_property.is_empty():
			return null
		var slot: Node = current.get(slot_property) as Node
		if slot == null:
			return null
		index += 1
		if role == String(AST_BlockSchema.ROLE_BODY) or role == String(AST_BlockSchema.ROLE_ARG):
			if index >= segments.size():
				return null
			current = _block_at(slot, segments[index].to_int())
			index += 1
		else:
			current = _first_block(slot)
	return current

static func _first_block(parent: Node) -> Control:
	for child: Node in parent.get_children():
		var block: Control = BlockSyncEngine.as_block(child)
		if block != null:
			return block
	return null

static func _block_at(parent: Node, wanted: int) -> Control:
	var seen: int = 0
	for child: Node in parent.get_children():
		var block: Control = BlockSyncEngine.as_block(child)
		if block == null:
			continue
		if seen == wanted:
			return block
		seen += 1
	return null
