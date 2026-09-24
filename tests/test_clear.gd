extends GameTest
## 打完一关：Boss 倒下 → 结算页 → 进度往前推 → 下一关 / 回主菜单。
##
## 以前关卡只有一个出口——全灭。打死 Boss 什么都不会发生，你可以继续往右走到墙边站着。
## 23 关要接得上，就得有「打完了」这件事，而且存档里得记住打到哪儿了，
## 否则每次都从第一关重来——练强了之后前几关就只剩无聊。

const LEVEL_1 := "res://levels/level_1.tres"


func screen() -> ClearScreen:
	return main.get_node("ClearScreen")


## 摆好一关（默认是正式第一关，因为**测试关不在关卡清单里**，没有进度可推），
## 只留 Boss，把玩家放到它跟前。
func face_the_boss(players := 1) -> Boss:
	var level := load(LEVEL_1) as LevelInfo
	await reset_scene(true, true, null, players, level.scene_path, level)
	keep_only_enemies(["BossArenaBossA1"])
	var boss: Boss = main.get_node("Enemies/BossArenaBossA1")
	player.global_position = boss.global_position + Vector2(-160, -16)
	player.health = 9999
	if player2 != null:
		player2.global_position = boss.global_position + Vector2(-200, -16)
		player2.health = 9999
	snap_camera()
	await frames(4)
	return boss


## 打死 Boss 并等结算页弹出来。
func finish_the_stage(boss: Boss) -> void:
	main.clear_delay = 0.05
	boss.take_damage(boss.max_health, Vector2.INF, player)
	for i in 60:
		await tree.physics_frame
		if screen().is_open():
			return


func test_killing_the_boss_finishes_the_stage() -> void:
	var boss := await face_the_boss()
	check("setup: the stage is running", not screen().is_open() and not tree.paused)
	await finish_the_stage(boss)
	check("the results come up", screen().is_open())
	check("and the stage is frozen while you read them", tree.paused)
	tree.paused = false


func test_finishing_unlocks_the_next_stage() -> void:
	var boss := await face_the_boss()
	check("setup: only the first stage is open", player.progress.reached == 1,
		str(player.progress.reached))
	await finish_the_stage(boss)
	# 打完第 1 关 = 解锁到第 2 关。**进度只往上推、不往下夹**，
	# 所以就算清单里眼下只有一关，数字照样是 2（卸载了关卡 DLC 也不该抹掉存档里的进度）
	check("beating it moves you on", player.progress.reached == 2, str(player.progress.reached))
	tree.paused = false


func test_the_results_show_what_the_stage_paid() -> void:
	var boss := await face_the_boss()
	var money := player.progress.money
	await finish_the_stage(boss)
	var results: Array = main._results()
	check("one panel per player", results.size() == 1, str(results.size()))
	check("it is this character", results[0]["name"] == player.progress.character_name,
		str(results[0]))
	check("and it counts what the boss paid", results[0]["money"] == player.progress.money - money,
		"%d vs %d" % [results[0]["money"], player.progress.money - money])
	check("which is more than nothing", results[0]["money"] > 0, str(results[0]["money"]))
	tree.paused = false


func test_the_xp_line_survives_a_level_up() -> void:
	# 升级时经验会清零重算，直接相减会得出负数——跨过的那几档要补回来
	var boss := await face_the_boss()
	var me := player.progress
	me.xp = me.balance.xp_to_next(me.level) - 1      # 差一点就升级
	main._remember_start()
	await finish_the_stage(boss)
	var results: Array = main._results()
	check("setup: it really levelled up", results[0]["levels_gained"] >= 1,
		str(results[0]["levels_gained"]))
	check("the xp earned is still a sensible number", results[0]["xp"] > 0, str(results[0]["xp"]))
	tree.paused = false


func test_both_players_get_a_panel() -> void:
	# 经验和金钱是各算各的（谁打死的记谁头上），所以两个人的成绩都要摆出来
	var boss := await face_the_boss(2)
	await finish_the_stage(boss)
	var results: Array = main._results()
	check("two panels", results.size() == 2, str(results.size()))
	check("with each character's own name",
		results[0]["name"] != results[1]["name"], str(results))
	tree.paused = false


func test_finishing_pulls_the_team_mate_along() -> void:
	# 双人**取两个人里最高的**：老手带新人时朋友也跟着解锁，不用卡着重打十几关
	var boss := await face_the_boss(2)
	player.progress.reached = 7
	player2.progress.reached = 1
	main._unlock_next()
	check("the veteran keeps their progress", player.progress.reached >= 7,
		str(player.progress.reached))
	check("and the newcomer is pulled up to it",
		player2.progress.reached == player.progress.reached,
		"%d vs %d" % [player2.progress.reached, player.progress.reached])
	tree.paused = false


func test_the_pause_button_cannot_steal_the_results() -> void:
	var boss := await face_the_boss()
	await finish_the_stage(boss)
	check("setup: the results are up", screen().is_open())
	await tap(&"pause")
	var pause: PauseMenu = main.get_node("PauseMenu")
	check("pausing does nothing while you read them", not pause.is_open())
	tree.paused = false


func test_dying_after_the_boss_does_not_double_up() -> void:
	# Boss 倒下的同一刻最后一个玩家也死了，两页一起弹出来就乱了
	var boss := await face_the_boss()
	await finish_the_stage(boss)
	player.take_damage(9999)
	await frames(30)
	var death: DeathScreen = main.get_node("DeathScreen")
	check("only the results are showing", screen().is_open() and not death.is_open())
	tree.paused = false
