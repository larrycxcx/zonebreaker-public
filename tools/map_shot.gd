extends SceneTree
## The screenshot script used by `tools/map_paint.py preview`: loads a scene with a given stage's art pack and takes one screenshot per screen.
## godot --path . --script res://tools/map_shot.gd -- scene stage_resource output_dir name
## Enemies are frozen and the player does not move, only terrain and props matter; the entry script compiles before the autoloads, so singletons are fetched with get_node.
## Horizontal stages take one per screen from left to right; **vertical stages** (camera `only_up`) one per screen from the bottom up — the view only scrolls up, so it has to start at the bottom.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var info: Resource = load(args[1])
	root.get_node("/root/Skins").use(info.skin)
	var level: Node = (load(args[0]) as PackedScene).instantiate()
	root.add_child(level)
	var player: Node2D = level.get_node("Player")
	player.set_physics_process(false)
	await process_frame
	level.get_node("Enemies").process_mode = Node.PROCESS_MODE_DISABLED
	var rig := level.get_node("Camera2D") as Camera2D
	var vertical: bool = rig.get("only_up")
	# A vertical stage's limit_bottom closes in upward (it only scrolls up), so note the whole stage's height first
	var bottom := float(rig.limit_bottom)
	var screens := ceili((bottom if vertical else rig.limit_right) / (360.0 if vertical else 640.0))
	for i in screens:
		if vertical:
			# The leader sits 64 below the middle of the view (`look_ahead`), so the player is placed in the middle of this screen plus 64 down
			player.global_position = Vector2(320, bottom - i * 360 - 180 + 64)
		else:
			player.global_position = Vector2(i * 640 + 320, 200)
		for f in 4:
			rig.call("_physics_process", 0.0)
			rig.force_update_scroll()
			await process_frame
		var shot := root.get_texture().get_image()
		shot.save_png("%s/%s_%02d.png" % [args[2], args[3], i + 1])
	quit()
