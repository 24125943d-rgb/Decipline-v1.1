extends SceneTree
## Manual load-only exit probe. No generated program is instantiated or executed.
func _initialize() -> void:
	call_deferred("_probe")

func _probe() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if not args.is_empty() else "res://scripts/character_decipline.gd"
	var resource: Resource = load(path)
	print("Loaded only: ", resource.resource_path)
	if args.size() > 1:
		var test: Node = resource.new()
		root.add_child(test)
		var result: Variant = await test.call(args[1])
		print("Test result: ", result)
		test.after_each()
		test.free()
	resource = null
	await process_frame
	quit()
