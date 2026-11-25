extends SceneTree
## Test entry point. Usage ($godot: see CLAUDE.md):
##
##   & $godot --headless --path . --script res://tests/run_tests.gd
##   & $godot --headless --path . --script res://tests/run_tests.gd -- crouch
##
## Add `-- <name>` (player / enemies / enemy_types / enemy_aim / chaser / flyer / crouch / sprint / walls / gamepad / aiming / weapons / grenade / audio) to run only that suite; without it everything runs. Exit code 0 when everything passes, 1 on failures.

const SUITES := {
	"player": "res://tests/test_player.gd",
	"enemies": "res://tests/test_enemies.gd",
	"enemy_types": "res://tests/test_enemy_types.gd",
	"enemy_aim": "res://tests/test_enemy_aim.gd",
	"chaser": "res://tests/test_chaser.gd",
	"enemy_f": "res://tests/test_enemy_f.gd",
	"flyer": "res://tests/test_flyer.gd",
	"crouch": "res://tests/test_crouch.gd",
	"ladders": "res://tests/test_ladders.gd",
	"map_demo": "res://tests/test_map_demo.gd",
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
	"lab": "res://tests/test_lab.gd",
	"lab_enemies": "res://tests/test_lab_enemies.gd",
	"lab_bosses": "res://tests/test_lab_bosses.gd",
	"level_5": "res://tests/test_level_5.gd",
	"boss_4": "res://tests/test_boss_4.gd",
	"menus": "res://tests/test_menus.gd",
	"main_menu": "res://tests/test_main_menu.gd",
	"progression": "res://tests/test_progression.gd",
	"coop": "res://tests/test_coop.gd",
	"pits": "res://tests/test_pits.gd",
	"vertical": "res://tests/test_vertical.gd",
	"level_1": "res://tests/test_level_1.gd",
	"level_2": "res://tests/test_level_2.gd",
	"traps": "res://tests/test_traps.gd",
	"level_3": "res://tests/test_level_3.gd",
	"level_4": "res://tests/test_level_4.gd",
	"catalog": "res://tests/test_catalog.gd",
	"clear": "res://tests/test_clear.gd",
	"shop": "res://tests/test_shop.gd",
	"status": "res://tests/test_status.gd",
	"audio": "res://tests/test_audio.gd",
}


## The longest one case may run. It guards against a case waiting for a signal that never comes,
## where the runner's await would wait forever; when the watchdog fires it reports which case is stuck and exits with a failure.
const TEST_TIMEOUT_SEC := 60.0


## Collect the SCRIPT ERRORs during a case.
## In Godot, a runtime error in the middle of a coroutine aborts that case, but the runner's await returns as usual,
## and the case has recorded no assertions — without catching them, failing cases would be counted as "passed".
## The Logger may be called from another thread, hence the lock.
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
	# This entry script is compiled earlier than the autoload singletons (GameEvents, Skins, Sfx), when their names do not exist yet.
	# So it must not statically reference any type that drags in game scripts (e.g. `var suite: GameTest` —
	# that would compile GameTest → Player → player.gd at once, where GameEvents is "identifier not found", and the whole run would use a broken player),
	# and it waits one frame first, loading the suites once the singletons are registered.
	await process_frame
	var wanted := OS.get_cmdline_user_args()
	var total := 0
	var failed := 0
	var failed_labels: Array[String] = []
	# When the art is missing (public build) the cases testing the art skip themselves (`GameTest.needs_art()`); this only counts them
	var skipped := 0

	for suite_name in SUITES:
		if wanted.size() > 0 and not wanted.has(suite_name):
			continue
		print("\n=== ", suite_name, " ===")
		# If a test script itself has a syntax error, load fails: record one failure and carry on with the other suites, instead of the whole runner crashing or hanging.
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
			suite.skipped = false
			_script_errors.take() # Drop errors that may come from the previous case's teardown; only count this case's own
			_arm_watchdog("%s / %s" % [suite_name, test_name])
			await suite.call(test_name)
			# Free the scene after every case, so cases do not affect each other and nothing leaks on exit.
			suite.free_scene()
			await physics_frame
			for error in _script_errors.take():
				suite.check("no script error (%s)" % error, false)
			if suite.skipped:
				skipped += 1
				print("    SKIP  needs the third-party art (not in this build)")

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

	_test_serial += 1 # Disarm the last case's watchdog
	print("\n", "-".repeat(50))
	if skipped > 0:
		print("%d tests skipped: they check the third-party art, which this build leaves out" % skipped)
	if failed == 0:
		print("all %d checks passed" % total)
	else:
		print("%d of %d checks FAILED:" % [failed, total])
		for label in failed_labels:
			print("  - ", label)
	OS.remove_logger(_script_errors)
	quit(1 if failed > 0 else 0)
