class_name GameTest
extends RefCounted
## 行为测试基类。子类里每个 `test_` 开头的方法就是一条用例，由 `run_tests.gd` 自动发现并执行。
##
## 这些测试是「跑起来看结果」的集成测试：真的实例化主场景、真的模拟按键、真的等物理帧，
## 所以能抓到纯语法检查抓不到的问题（碰撞层配错、射线打不到、状态机卡死等）。
## 为此会直接读写被测对象的私有成员（`_fire_timer` 之类），这是有意为之，
## 比为测试在游戏代码里开一堆公开接口更划算。

const ACTIONS := ["move_left", "move_right", "jump", "crouch", "shoot"]

## 由 runner 注入。SceneTree 脚本里 `await tree.physics_frame` 才能推进物理。
var tree: SceneTree
var main: Node
var player: Player
var results: Array[Dictionary] = []


func check(label: String, ok: bool, detail := "") -> void:
	results.append({"label": label, "ok": ok, "detail": detail})


func frames(count: int) -> void:
	for i in count:
		await tree.physics_frame


func release_all_input() -> void:
	for action in ACTIONS:
		Input.action_release(action)


## 重新加载一份主场景。
## 默认清掉所有敌人：巡逻兵走遍了整块地面，测纯操作时如果不清场，
## 玩家一传送过去就会吃接触伤害被击飞，后面一连串断言都会莫名其妙地失败。
func reset_scene(keep_enemies := false) -> void:
	release_all_input()
	free_scene()
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	player = main.get_node("Player")
	if not keep_enemies:
		for enemy in main.get_node("Enemies").get_children():
			enemy.free()
	await frames(2)


## 只留下指定名字的敌人，其它全部移除。
## 敌人现在都会射击，测某一个敌人时必须清掉其它的，否则别人的子弹会污染结果。
func keep_only_enemies(names: Array) -> void:
	for enemy in main.get_node("Enemies").get_children():
		if not names.has(String(enemy.name)):
			enemy.free()


func free_scene() -> void:
	release_all_input()
	if main != null and is_instance_valid(main):
		main.free()
	main = null
	player = null


## 按碰撞层收集场上还活着的子弹（4 = 玩家子弹，16 = 敌人子弹）。
## 子弹命中后立刻消失，所以判断「有没有开火」要逐帧采样，不能事后再数。
func bullets(layer: int, node: Node = null) -> Array:
	var found := []
	for child in (node if node != null else main).get_children():
		if child is Bullet and (child as Bullet).collision_layer == layer:
			found.append(child)
		found.append_array(bullets(layer, child))
	return found
