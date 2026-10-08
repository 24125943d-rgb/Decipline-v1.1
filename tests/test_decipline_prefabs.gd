extends Node
## Isolate prefab loading from the compiler/UI dependency graph in the test process.
func test_prefabs_inherit_single_unlinked_component() -> Variant:
	for path: String in ["res://scenes/character.tscn", "res://scenes/attribute_character.tscn"]:
		var scene: PackedScene = load(path) as PackedScene
		var character: Node = scene.instantiate()
		var count: int = 0
		var linked: bool = false
		for child: Node in character.get_children():
			if child is CharacterDecipline:
				count += 1
				linked = linked or not child.block_lab_path.is_empty()
		character.free()
		if count != 1 or linked:
			return "Expected one unlinked Decipline: " + path
	return null
