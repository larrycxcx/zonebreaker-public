extends GameTest
## Clearing a stage: the boss falls → results screen → progress moves on → next stage / back to the main menu.
##
## Stages used to have only one way out — everyone dying. Killing the boss did nothing, and you could keep walking right until you stood at the wall.
## For 23 stages to connect there has to be "cleared", and the save has to remember how far you got,
## otherwise you start from stage 1 every time — and once you are strong the first stages are just boring.

const LEVEL_1 := "res://levels/level_1.tres"


func screen() -> ClearScreen:
	return main.get_node("ClearScreen")


## Set up a stage (the first real stage by default, because **the test level is not in the stage list** and has no progress to move on),
## keep only the boss and put the player in front of it.
func face_the_boss(players := 1) -> Boss:
	var level := load(LEVEL_1) as LevelInfo
	await reset_scene(true, true, null, players, level.scene_path, level)
	keep_only_enemies(["1-Boss-1"])
	var boss: Boss = main.get_node("Enemies/1-Boss-1")
	player.global_position = boss.global_position + Vector2(-160, -16)
	player.health = 9999
	if player2 != null:
		player2.global_position = boss.global_position + Vector2(-200, -16)
		player2.health = 9999
	snap_camera()
	await frames(4)
	return boss


## Kill the boss and wait for the results screen to pop up.
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
	# Clearing stage 1 = unlocking up to stage 2. **Progress only moves up, never gets clamped down**,
	# so even if the list has only one stage right now, the number is still 2 (uninstalling a stage DLC should not wipe progress in the save either)
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
	# A level-up resets XP and recounts it, so plain subtraction gives a negative number — the thresholds crossed have to be added back
	var boss := await face_the_boss()
	var me := player.progress
	me.xp = me.balance.xp_to_next(me.level) - 1      # Just short of a level-up
	main._remember_start()
	await finish_the_stage(boss)
	var results: Array = main._results()
	check("setup: it really levelled up", results[0]["levels_gained"] >= 1,
		str(results[0]["levels_gained"]))
	check("the xp earned is still a sensible number", results[0]["xp"] > 0, str(results[0]["xp"]))
	tree.paused = false


func test_both_players_get_a_panel() -> void:
	# XP and money are counted separately (each kill is credited to whoever made it), so both players' results have to be shown
	var boss := await face_the_boss(2)
	await finish_the_stage(boss)
	var results: Array = main._results()
	check("two panels", results.size() == 2, str(results.size()))
	check("with each character's own name",
		results[0]["name"] != results[1]["name"], str(results))
	tree.paused = false


func test_finishing_pulls_the_team_mate_along() -> void:
	# In co-op **take the higher of the two**: when a veteran plays with a newcomer the friend unlocks along with them, without replaying a dozen stages
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
	# The last player dying at the same moment the boss falls would pop up both screens at once, which would be a mess
	var boss := await face_the_boss()
	await finish_the_stage(boss)
	player.take_damage(9999)
	await frames(30)
	var death: DeathScreen = main.get_node("DeathScreen")
	check("only the results are showing", screen().is_open() and not death.is_open())
	tree.paused = false
