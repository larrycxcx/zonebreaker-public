class_name GameTest
extends RefCounted
## 行为测试基类。子类里每个 `test_` 开头的方法就是一条用例，由 `run_tests.gd` 自动发现并执行。
##
## 这些测试是「跑起来看结果」的集成测试：真的实例化主场景、真的模拟按键、真的等物理帧，
## 所以能抓到纯语法检查抓不到的问题（碰撞层配错、射线打不到、状态机卡死等）。
## 为此会直接读写被测对象的私有成员（`_primary.cooldown_left` 之类），这是有意为之，
## 比为测试在游戏代码里开一堆公开接口更划算。

## 项目里应该定义的全部输入动作，test_input_actions_exist 逐个检查。
const ACTIONS := ["move_left", "move_right", "jump", "crouch", "sprint", "aim_up", "aim_down", "shoot", "switch_weapon", "ultimate"]

## 数值是 RPG 式的（玩家 120 血、敌人 20 血起），测试按「几下」来写：
## 敌人打 1 级玩家一下扣 HIT（挨 3 下死），玩家一发子弹打敌人扣 SHOT（巡逻兵挨 2 发死）。
const HIT := 40
const SHOT := 10

## 由 runner 注入。SceneTree 脚本里 `await tree.physics_frame` 才能推进物理。
var tree: SceneTree
var main: Node
var player: Player
## 双人时的 2 号玩家（reset_scene 传 players = 2 才有），单人时是 null。
var player2: Player
var results: Array[Dictionary] = []
## 这条用例里 GameEvents 报告过的事件名，按先后顺序。reset_scene() 时清空。
var events: Array[StringName] = []


func check(label: String, ok: bool, detail := "") -> void:
	results.append({"label": label, "ok": ok, "detail": detail})


func frames(count: int) -> void:
	for i in count:
		await tree.physics_frame


## 按一下就松（「每按一次触发一次」的动作：跳跃、切武器、菜单里的上下和确认）。
## **要按住至少两帧**：`Input.action_press()` 模拟的按下要到**下一个物理帧**才算 just_pressed，
## 只按一帧就松，轮到判定时键已经松了，什么也不会发生。
func tap(action: StringName) -> void:
	Input.action_press(action)
	await frames(2)
	Input.action_release(action)
	await frames(1)


## 松开所有游戏动作（跳过引擎自带的 ui_*）。
## 直接遍历 InputMap 而不是用 ACTIONS 列表：新加了动作却忘了登记的话，
## 某条用例按下的键就会一直按着带进后面的用例（向上瞄准刚踩过这个坑）。
func release_all_input() -> void:
	for action in InputMap.get_actions():
		if not String(action).begins_with("ui_"):
			Input.action_release(action)


## 重新加载一份主场景。
## 默认清掉所有敌人：巡逻兵走遍了整块地面，测纯操作时如果不清场，
## 玩家一传送过去就会吃接触伤害被击飞，后面一连串断言都会莫名其妙地失败。
## 默认也移除 Level/Walls 下的竖墙：墙会挡路、挡子弹、挡视线，而大部分用例测的是和墙无关的机制，
## 不该因为关卡里掩体摆放的调整而失败。测墙本身的用例传 keep_walls = true。
## `skin` 传了就用它加载这一关（角色在 _ready 里按当前包装外观，所以必须在加载之前定好）；
## 不传就恢复默认包。
## `scene` 默认是**测试关**（`main.tscn`，1280 宽、地面一整条）；正式关卡传它自己的路径。
func reset_scene(keep_enemies := false, keep_walls := false, skin: SkinPack = null, players := 1,
		scene := "res://scenes/main.tscn") -> void:
	release_all_input()
	free_scene()
	# 终极武器会暂停整棵树：用例中途出错、没等到恢复，也不能把暂停带进下一条用例。
	tree.paused = false
	# 素材包是全局状态：换过包的用例如果中途出错没换回来，会影响后面所有用例，所以每次都恢复默认包。
	Skins.use(skin if skin != null else Skins.default_skin())
	# 成长进度也是全局状态：每条用例都从新开一局开始（1 级、初始武器），并且不读写玩家的真实存档
	Progress.persist = false
	Progress.new_game()
	# 几个人玩也是全局状态（Session），每条用例都设一遍，默认单人
	Session.set_player_count(players)
	events.clear()
	if not GameEvents.event_happened.is_connected(_record_event):
		GameEvents.event_happened.connect(_record_event)
	main = load(scene).instantiate()
	tree.root.add_child(main)
	player = main.get_node("Player")
	player2 = main.get_node_or_null("Player2")
	if not keep_enemies:
		for enemy in main.get_node("Enemies").get_children():
			enemy.free()
	if not keep_walls:
		for wall in main.get_node("Level/Walls").get_children():
			wall.free()
	await frames(2)


## 在关卡里临时搭一堵实心竖墙（和关卡里的竖墙同样的做法：platform.tscn，16px 宽，立在地面上），返回它。
## 测「墙」这个机制本身时用它，不依赖关卡里墙摆在哪、有没有（Wall3 就是为了试 Boss 难度拆掉的）。
func add_wall(x: float, height: float, wall_name := "TestWall") -> Platform:
	var w: Platform = load("res://scenes/platform.tscn").instantiate()
	w.name = wall_name
	w.position = Vector2(x, 320.0 - height)
	w.size = Vector2(8, height)
	main.get_node("Level/Walls").add_child(w)
	return w


## 瞬移玩家之后让摄像机立刻跟上。摄像机每帧是在物理更新**之后**才跟的，瞬移那一帧敌人看到的还是上一帧的画面范围——
## 敌人「在屏幕里就看得见玩家」，这一帧就可能误把玩家看见（D 还会带着 2 秒记忆追过来）。
func snap_camera() -> void:
	var camera := camera_rig()
	if camera != null:
		camera._physics_process(0.0)
		camera.force_update_scroll()


## 关卡共用的摄像机（跟两个玩家的中点，不再挂在玩家身上）。
func camera_rig() -> CameraRig:
	return main.get_node_or_null("Camera2D") as CameraRig


## 关卡里的敌人（只要真正的敌人）。敌人的子弹和手雷也挂在 Enemies 下（敌人死了它们照样飞完），
## 而敌人在屏幕里就会开火，所以一加载关卡 Enemies 下就可能有子弹——遍历敌人要用这个，别直接 get_children()。
func enemies() -> Array:
	return main.get_node("Enemies").get_children().filter(func(node: Node) -> bool: return node is Enemy)


## 只留下指定名字的敌人，其它全部移除。
## 敌人现在都会射击，测某一个敌人时必须清掉其它的，否则别人的子弹会污染结果。
func keep_only_enemies(names: Array) -> void:
	for enemy in main.get_node("Enemies").get_children():
		if not names.has(String(enemy.name)):
			enemy.free()


func _record_event(event: StringName, _source: Node) -> void:
	events.append(event)


func free_scene() -> void:
	release_all_input()
	tree.paused = false
	if GameEvents.event_happened.is_connected(_record_event):
		GameEvents.event_happened.disconnect(_record_event)
	if main != null and is_instance_valid(main):
		main.free()
	main = null
	player = null


## 角色外观里叫这个名字的方块（枪、枪管之类）。外观都挂在 `Visual` 上的 Appearance 里。
func art(actor: Node, art_name: String) -> CanvasItem:
	return actor.get_node("Visual").get_node_or_null(NodePath(art_name)) as CanvasItem


## 敌人身上那根会跟着瞄准转的枪管（外观层的 turning_gun 指定）。
func turning_gun(enemy: Enemy) -> Control:
	var appearance: Appearance = enemy.get_node("Visual")
	return appearance.get_node_or_null(appearance.turning_gun) as Control


## 某个动作绑定的键盘按键（physical_keycode），忽略手柄绑定。
func keyboard_keys(action: StringName) -> Array:
	var keys := []
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			keys.append((event as InputEventKey).physical_keycode)
	return keys


## 按碰撞层收集场上还活着的子弹（4 = 玩家子弹，16 = 敌人子弹）。
## 子弹命中后立刻消失，所以判断「有没有开火」要逐帧采样，不能事后再数。
func bullets(layer: int, node: Node = null) -> Array:
	var found := []
	for child in (node if node != null else main).get_children():
		if child is Bullet and (child as Bullet).collision_layer == layer:
			found.append(child)
		found.append_array(bullets(layer, child))
	return found
