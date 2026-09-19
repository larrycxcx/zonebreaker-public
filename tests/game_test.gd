class_name GameTest
extends RefCounted
## 行为测试基类。子类里每个 `test_` 开头的方法就是一条用例，由 `run_tests.gd` 自动发现并执行。
##
## 这些测试是「跑起来看结果」的集成测试：真的实例化主场景、真的模拟按键、真的等物理帧，
## 所以能抓到纯语法检查抓不到的问题（碰撞层配错、射线打不到、状态机卡死等）。
## 为此会直接读写被测对象的私有成员（`_fire_timer` 之类），这是有意为之，
## 比为测试在游戏代码里开一堆公开接口更划算。

## 项目里应该定义的全部输入动作，test_input_actions_exist 逐个检查。
const ACTIONS := ["move_left", "move_right", "jump", "crouch", "sprint", "aim_up", "aim_down", "shoot"]

## 由 runner 注入。SceneTree 脚本里 `await tree.physics_frame` 才能推进物理。
var tree: SceneTree
var main: Node
var player: Player
var results: Array[Dictionary] = []
## 这条用例里 GameEvents 报告过的事件名，按先后顺序。reset_scene() 时清空。
var events: Array[StringName] = []


func check(label: String, ok: bool, detail := "") -> void:
	results.append({"label": label, "ok": ok, "detail": detail})


func frames(count: int) -> void:
	for i in count:
		await tree.physics_frame


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
func reset_scene(keep_enemies := false, keep_walls := false) -> void:
	release_all_input()
	free_scene()
	# 素材包是全局状态：换过包的用例如果中途出错没换回来，会影响后面所有用例，所以每次都恢复默认包。
	Skins.use(Skins.default_skin())
	events.clear()
	if not GameEvents.event_happened.is_connected(_record_event):
		GameEvents.event_happened.connect(_record_event)
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	player = main.get_node("Player")
	if not keep_enemies:
		for enemy in main.get_node("Enemies").get_children():
			enemy.free()
	if not keep_walls:
		for wall in main.get_node("Level/Walls").get_children():
			wall.free()
	await frames(2)


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
	if GameEvents.event_happened.is_connected(_record_event):
		GameEvents.event_happened.disconnect(_record_event)
	if main != null and is_instance_valid(main):
		main.free()
	main = null
	player = null


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
