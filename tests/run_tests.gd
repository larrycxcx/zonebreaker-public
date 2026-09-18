extends SceneTree
## 测试入口。用法（$godot 见 CLAUDE.md）：
##
##   & $godot --headless --path . --script res://tests/run_tests.gd
##   & $godot --headless --path . --script res://tests/run_tests.gd -- crouch
##
## 加 `-- <名字>` 只跑指定的一组，不加就全跑。全部通过退出码为 0，有失败为 1。

const SUITES := {
	"player": "res://tests/test_player.gd",
	"enemies": "res://tests/test_enemies.gd",
	"crouch": "res://tests/test_crouch.gd",
}


func _initialize() -> void:
	_run()


func _run() -> void:
	var wanted := OS.get_cmdline_user_args()
	var total := 0
	var failed := 0
	var failed_labels: Array[String] = []

	for suite_name in SUITES:
		if wanted.size() > 0 and not wanted.has(suite_name):
			continue
		print("\n=== ", suite_name, " ===")
		var suite: GameTest = load(SUITES[suite_name]).new()
		suite.tree = self

		for method in suite.get_method_list():
			var test_name: String = method.name
			if not test_name.begins_with("test_"):
				continue
			print("  ", test_name)
			suite.results.clear()
			await suite.call(test_name)
			# 每条用例跑完就把场景释放掉，用例之间互不影响，退出时也不会报资源泄漏。
			suite.free_scene()
			await physics_frame

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

	print("\n", "-".repeat(50))
	if failed == 0:
		print("all %d checks passed" % total)
	else:
		print("%d of %d checks FAILED:" % [failed, total])
		for label in failed_labels:
			print("  - ", label)
	quit(1 if failed > 0 else 0)
