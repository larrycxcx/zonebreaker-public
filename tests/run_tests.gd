extends SceneTree
## 测试入口。用法（$godot 见 CLAUDE.md）：
##
##   & $godot --headless --path . --script res://tests/run_tests.gd
##   & $godot --headless --path . --script res://tests/run_tests.gd -- crouch
##
## 加 `-- <名字>`（player / enemies / enemy_types / enemy_aim / chaser / flyer / crouch / sprint / walls / gamepad / aiming / weapons / grenade / audio）只跑指定的一组，不加就全跑。全部通过退出码为 0，有失败为 1。

const SUITES := {
	"player": "res://tests/test_player.gd",
	"enemies": "res://tests/test_enemies.gd",
	"enemy_types": "res://tests/test_enemy_types.gd",
	"enemy_aim": "res://tests/test_enemy_aim.gd",
	"chaser": "res://tests/test_chaser.gd",
	"enemy_f": "res://tests/test_enemy_f.gd",
	"flyer": "res://tests/test_flyer.gd",
	"crouch": "res://tests/test_crouch.gd",
	"drop": "res://tests/test_drop.gd",
	"sprint": "res://tests/test_sprint.gd",
	"walls": "res://tests/test_walls.gd",
	"gamepad": "res://tests/test_gamepad.gd",
	"aiming": "res://tests/test_aiming.gd",
	"weapons": "res://tests/test_weapons.gd",
	"grenade": "res://tests/test_grenade.gd",
	"ultimate": "res://tests/test_ultimate.gd",
	"boss": "res://tests/test_boss.gd",
	"boss_1": "res://tests/test_boss_1.gd",
	"visuals": "res://tests/test_visuals.gd",
	"fx": "res://tests/test_fx.gd",
	"feel": "res://tests/test_feel.gd",
	"skin_visuals": "res://tests/test_skin_visuals.gd",
	"cyberpunk": "res://tests/test_cyberpunk_skin.gd",
	"cyberpunk_enemies": "res://tests/test_cyberpunk_enemies.gd",
	"cyberpunk_projectiles": "res://tests/test_cyberpunk_projectiles.gd",
	"cyberpunk_terrain": "res://tests/test_cyberpunk_terrain.gd",
	"cyberpunk_hud": "res://tests/test_cyberpunk_hud.gd",
	"cyberpunk_fx": "res://tests/test_cyberpunk_fx.gd",
	"cyberpunk_audio": "res://tests/test_cyberpunk_audio.gd",
	"industrial": "res://tests/test_industrial.gd",
	"bar_street": "res://tests/test_bar_street.gd",
	"basement": "res://tests/test_basement.gd",
	"basement_enemies": "res://tests/test_basement_enemies.gd",
	"menus": "res://tests/test_menus.gd",
	"main_menu": "res://tests/test_main_menu.gd",
	"progression": "res://tests/test_progression.gd",
	"coop": "res://tests/test_coop.gd",
	"pits": "res://tests/test_pits.gd",
	"vertical": "res://tests/test_vertical.gd",
	"level_1": "res://tests/test_level_1.gd",
	"level_2": "res://tests/test_level_2.gd",
	"level_3": "res://tests/test_level_3.gd",
	"catalog": "res://tests/test_catalog.gd",
	"clear": "res://tests/test_clear.gd",
	"shop": "res://tests/test_shop.gd",
	"status": "res://tests/test_status.gd",
	"audio": "res://tests/test_audio.gd",
}


## 单条用例最多跑多久。防的是用例在等一个永远不会来的信号，
## runner 的 await 会一直等下去；看门狗到点就报出是哪条用例卡住，并以失败退出。
const TEST_TIMEOUT_SEC := 60.0


## 收集用例运行期间的 SCRIPT ERROR。
## Godot 里协程中途出运行时错误时，那条用例直接中止，但 runner 的 await 照常返回，
## 而它一条断言都没记——不拦下来的话，出错的用例会被当成「通过」。
## Logger 可能在别的线程被调用，所以加锁。
class ScriptErrorCollector extends Logger:
	var _mutex := Mutex.new()
	var _errors: Array[String] = []

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		_mutex.lock()
		_errors.append("%s:%d %s" % [file.get_file(), line, rationale if rationale != "" else code])
		_mutex.unlock()

	func take() -> Array[String]:
		_mutex.lock()
		var taken := _errors.duplicate()
		_errors.clear()
		_mutex.unlock()
		return taken


var _test_serial := 0
var _script_errors := ScriptErrorCollector.new()


func _initialize() -> void:
	OS.add_logger(_script_errors)
	_run()


func _arm_watchdog(label: String) -> void:
	_test_serial += 1
	var serial := _test_serial
	create_timer(TEST_TIMEOUT_SEC).timeout.connect(func() -> void:
		if serial == _test_serial:
			print("\n    TIMEOUT  %s did not finish within %d s (look for a SCRIPT ERROR above)" % [label, int(TEST_TIMEOUT_SEC)])
			quit(1))


func _run() -> void:
	# 这个入口脚本比 autoload 单例（GameEvents、Skins、Sfx）更早编译，那时它们的名字还不存在。
	# 所以这里不能静态引用任何会连带加载游戏脚本的类型（比如 `var suite: GameTest`——
	# 它会立刻编译 GameTest → Player → player.gd 里的 GameEvents 报「找不到标识符」，整场测试都跑在坏掉的玩家上），
	# 并且先等一帧，单例注册好之后再去加载各组测试。
	await process_frame
	var wanted := OS.get_cmdline_user_args()
	var total := 0
	var failed := 0
	var failed_labels: Array[String] = []

	for suite_name in SUITES:
		if wanted.size() > 0 and not wanted.has(suite_name):
			continue
		print("\n=== ", suite_name, " ===")
		# 测试脚本本身有语法错误时 load 会失败：记为一条失败、继续跑别的组，而不是整个 runner 崩掉卡死。
		var script := load(SUITES[suite_name]) as GDScript
		if script == null or not script.can_instantiate():
			total += 1
			failed += 1
			failed_labels.append("%s: suite failed to load (see SCRIPT ERROR above)" % suite_name)
			print("    FAIL  could not load ", SUITES[suite_name])
			continue
		var suite = script.new()
		suite.tree = self

		for method in suite.get_method_list():
			var test_name: String = method.name
			if not test_name.begins_with("test_"):
				continue
			print("  ", test_name)
			suite.results.clear()
			_script_errors.take() # 丢掉上一条用例收尾阶段可能产生的错误，只算这条自己的
			_arm_watchdog("%s / %s" % [suite_name, test_name])
			await suite.call(test_name)
			# 每条用例跑完就把场景释放掉，用例之间互不影响，退出时也不会报资源泄漏。
			suite.free_scene()
			await physics_frame
			for error in _script_errors.take():
				suite.check("no script error (%s)" % error, false)

			for result in suite.results:
				total += 1
				var detail: String = result["detail"]
				if result["ok"]:
					print("    PASS  ", result["label"], ("  " + detail) if detail != "" else "")
				else:
					failed += 1
					var label: String = "%s / %s: %s" % [suite_name, test_name, result["label"]]
					failed_labels.append(label)
					print("    FAIL  ", result["label"], ("  " + detail) if detail != "" else "")

	_test_serial += 1 # 解除最后一条用例的看门狗
	print("\n", "-".repeat(50))
	if failed == 0:
		print("all %d checks passed" % total)
	else:
		print("%d of %d checks FAILED:" % [failed, total])
		for label in failed_labels:
			print("  - ", label)
	OS.remove_logger(_script_errors)
	quit(1 if failed > 0 else 0)
