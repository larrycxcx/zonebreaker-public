extends SceneTree
## `tools/map_paint.py preview` 用的截图脚本：按某一关的素材包加载一个场景，每屏截一张。
##     godot --path . --script res://tools/map_shot.gd -- 场景 关卡资源 输出目录 名字
## 敌人定住、玩家不动，只看地形和摆设；入口脚本比 autoload 先编译，所以单例用 get_node 拿。
## 横向关从左往右一屏一张；**纵向关**（摄像机 `only_up`）从下往上一屏一张——画面只往上卷，得从底下开始。

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
	# 纵向关的 limit_bottom 会跟着往上收（只往上卷），所以先记下整关多高
	var bottom := float(rig.limit_bottom)
	var screens := ceili((bottom if vertical else rig.limit_right) / (360.0 if vertical else 640.0))
	for i in screens:
		if vertical:
			# 领头的人在画面中线往下 64（`look_ahead`），所以人摆在这一屏中间再往下 64
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
