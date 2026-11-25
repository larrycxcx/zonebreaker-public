extends GameTest
## The pause menu and the skill screen.
##
## What it guards: both players can pause, the stage really stops while paused, the ultimate's two-second freeze cannot have its pause stolen,
## one press on the skill screen really adds one point, in co-op each column follows its own player, stats on the player change after spending points, and back steps out level by level.

const STATS := 4


func menu() -> PauseMenu:
	return main.get_node("PauseMenu")


func skills() -> SkillsScreen:
	for child in menu().get_child(0).get_children():
		if child is SkillsScreen:
			return child
	return null


## Press once with the keys of a given player.
func tap_as(player_index: int, action: StringName) -> void:
	await tap(action if player_index == 0 else StringName("p%d_%s" % [player_index + 1, action]))


# ---------------------------------------------------------------- Pause

func test_pausing_stops_the_level() -> void:
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(2)
	check("setup: running", not tree.paused and not menu().is_open())
	await tap(&"pause")
	check("the menu is up", menu().is_open())
	check("and the level is frozen", tree.paused)
	var spot := player.global_position
	Input.action_press("move_right")
	await frames(10)
	release_all_input()
	check("the player cannot move while paused", player.global_position == spot,
		str(player.global_position - spot))
	await tap(&"cancel")
	check("backing out closes it", not menu().is_open() and not tree.paused)


func test_a_closed_menu_does_not_listen() -> void:
	# A pitfall we hit: hiding the menu only checked `visible` (a node's own switch, still true when a parent is hidden),
	# so it kept taking keys while not paused — pressing "down down A" in the game picked QUIT and the whole process exited.
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(2)
	check("setup: the menu is closed", not menu().is_open())
	var list: MenuList = menu().menu_list()
	check("setup: its cursor is on the first item", list.index == 0, str(list.index))
	# Press only "down" once first: if the cursor moved now, pressing "down A" would pick QUIT and close the process,
	# leaving the test no chance to even report an error, so the assertion stops at this step and goes no further.
	await tap(&"aim_down")
	check("moving the stick while playing does not move a hidden cursor", list.index == 0, str(list.index))
	await tap(&"jump")
	check("and confirming does not open anything", not menu().is_open() and not tree.paused)


func test_reopening_puts_the_gold_box_back_on_resume() -> void:
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(2)
	await tap(&"pause")
	var list: MenuList = menu().menu_list()
	await tap(&"aim_down")
	check("setup: the cursor moved off RESUME", list.index == PauseMenu.SKILLS, str(list.index))
	await tap(&"cancel")
	await tap(&"pause")
	check("it reopens on RESUME", list.index == PauseMenu.RESUME, str(list.index))
	# The cursor box was moved by direct assignment (not the key-press path); the box has to follow, or it would stay on SKILLS
	check("and the gold box is on RESUME too",
		list._cursor.position.is_equal_approx(list.highlight_box(PauseMenu.RESUME).position),
		"%s vs %s" % [list._cursor.position, list.highlight_box(PauseMenu.RESUME).position])
	await tap(&"cancel")


func test_either_player_can_pause() -> void:
	await reset_scene(false, false, null, 2)
	# `pause` is one action bound to the Start button of both pads, so it does not matter who presses
	var pads := InputMap.action_get_events(&"pause").filter(func(e: InputEvent) -> bool:
		return e is InputEventJoypadButton)
	var devices := pads.map(func(e: InputEvent) -> int: return e.device)
	check("both gamepads can pause", devices.has(0) and devices.has(1), str(devices))
	check("and the keyboard too", InputMap.action_get_events(&"pause").any(func(e: InputEvent) -> bool:
		return e is InputEventKey))


func test_the_ultimate_freeze_keeps_the_pause_button_out() -> void:
	# The ultimate also freezes things with tree.paused; fighting over it the two would undo each other
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(2)
	await tap(&"ultimate")
	check("setup: the ultimate froze the level", tree.paused and not menu().is_open())
	await tap(&"pause")
	check("pausing is refused while it lasts", not menu().is_open())
	for i in 300:
		if not tree.paused:
			break
		await tree.physics_frame
	check("and the freeze ended on its own", not tree.paused)
	await tap(&"pause")
	check("now it opens", menu().is_open())
	await tap(&"cancel")


# ---------------------------------------------------------------- Death choice

func death() -> DeathScreen:
	return main.get_node("DeathScreen")


## Kill the player and wait for that screen to pop up. **Shorten the two delays first** (0.5 + 0.7 seconds by default), so each case does not wait 72 frames.
func die_and_wait() -> void:
	main.game_over_delay = 0.05
	main.respawn_delay = 0.1
	player.take_damage(player.max_health)
	for i in 60:
		await tree.physics_frame
		if death().is_open():
			return


func test_dying_offers_a_choice_instead_of_just_reloading() -> void:
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(2)
	check("setup: alive and running", player.is_alive() and not death().is_open())
	await die_and_wait()
	check("the choice comes up", death().is_open())
	# "GAME OVER" is written on this layer, not the HUD: the darkening layer is here, and written on the HUD it would be darkened into an unreadable grey
	check("and it says what happened", death()._title.visible and death()._title.text == "GAME OVER",
		death()._title.text)
	check("with retry and main menu on it", death().menu_list()._items == DeathScreen.ITEMS,
		str(death().menu_list()._items))
	check("and the level is frozen while you pick", tree.paused)
	check("starting on retry", death().menu_list().index == DeathScreen.RETRY)
	await tap(&"cancel")
	check("there is no backing out of being dead", death().is_open() and tree.paused)
	await tap(&"jump")


func test_retry_lets_the_level_run_again() -> void:
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(2)
	await die_and_wait()
	check("setup: the choice is up", death().is_open())
	var picked := []
	death().chosen.connect(func(index: int) -> void: picked.append(index))
	await tap(&"jump")
	check("retry was taken", picked == [DeathScreen.RETRY], str(picked))
	check("the page is gone", not death().is_open())
	check("and the level runs again", not tree.paused)


func test_the_death_screen_keeps_the_pause_button_out() -> void:
	# Both change `tree.paused`, and fighting over it they would undo each other (the same reason as the ultimate freeze)
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(2)
	await die_and_wait()
	check("setup: the choice is up", death().is_open())
	await tap(&"pause")
	check("pausing does nothing while you are choosing", not menu().is_open())
	check("and the choice is still up", death().is_open() and tree.paused)
	await tap(&"jump")


func test_main_menu_leaves_the_level() -> void:
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(2)
	await die_and_wait()
	check("setup: the choice is up", death().is_open())
	await tap(&"aim_down")
	check("setup: on main menu", death().menu_list().index == DeathScreen.MAIN_MENU)
	await tap(&"jump")
	await frames(3)
	check("the level is left for the menu", tree.current_scene is MainMenu, str(tree.current_scene))
	check("and nothing is left frozen", not tree.paused)
	# **Clean up**: with the menu still in the tree, the next case pressing A would have it taken as a "menu confirm" (see the pitfalls in CLAUDE.md)
	tree.unload_current_scene()
	await frames(2)


# ---------------------------------------------------------------- HUD

func hud() -> CanvasLayer:
	return main.get_node("HUD")


func test_the_hud_writes_in_the_pixel_font() -> void:
	if needs_art(): return
	await reset_scene()
	await frames(2)
	var label: Label = hud().get_node("ProgressLabel")
	var font := label.get_theme_font("font")
	# Body text uses the small font (10px); the big 14px one is kept for titles, and both are only ever scaled by integers
	check("the level / cash line uses the pack's small font",
		font != null and font.resource_path == UiKit.FONT_SMALL,
		"" if font == null else font.resource_path)
	check("in gold, not white", label.get_theme_color("font_color") == UiKit.GOLD,
		str(label.get_theme_color("font_color")))
	# HUD text sits right on top of the level, and against a bright sky the strokes blur together, so it needs a dark shadow behind it.
	# **Look at the colour, not just the offset**: in Label's built-in theme the offset is already 1, and the shadow colour is fully transparent by default.
	var shade := label.get_theme_color("font_shadow_color")
	check("with a shadow behind it that is dark and solid",
		shade.get_luminance() < 0.2 and shade.a > 0.5, str(shade))
	check("and offset off the glyph", label.get_theme_constant("shadow_offset_x") > 0
		and label.get_theme_constant("shadow_offset_y") > 0,
		"%d,%d" % [label.get_theme_constant("shadow_offset_x"), label.get_theme_constant("shadow_offset_y")])


func test_the_progress_line_leaves_room_for_the_other_player() -> void:
	# In co-op there is one on each side, and squeezed into one line (LV / XP / CASH / PTS) it is up to 414px wide, colliding in the middle of the screen
	await reset_scene()
	await frames(2)
	# Level 20 is the realistic ceiling of this game (XP ×1.5 per level, beyond that the numbers reach seven digits, see the note in hud.gd)
	var me := player.progress
	me.level = 20
	me.xp = me.balance.xp_to_next(20) - 1
	me.money = 999999
	me.points = 99
	me.progress_changed.emit()
	await frames(1)
	var label: Label = hud().get_node("ProgressLabel")
	var lines := label.text.split("
")
	check("it is written on two lines", lines.size() == 2, label.text)
	var widest := 0.0
	for line in lines:
		widest = maxf(widest, label.get_theme_font("font").get_string_size(
			line, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.TEXT_SIZE).x)
	var half := 640.0 / 2.0 - 12.0
	check("even at the biggest numbers it stays in its half", widest <= half,
		"%.0f > %.0f" % [widest, half])


# ---------------------------------------------------------------- Spending points

func test_spending_a_point_raises_the_stat_and_the_player() -> void:
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(2)
	var before := player.max_health
	var points := player.progress.points
	check("setup: there are points to spend", points > 0, str(points))
	await tap(&"pause")
	await tap(&"aim_down")        # RESUME -> SKILLS
	await tap(&"jump")            # Into the skill screen
	check("the skills screen is up", skills() != null)
	await tap(&"jump")            # The first item is LIFE, add a point
	check("one point is gone", player.progress.points == points - 1, str(player.progress.points))
	check("life went up", player.progress.stat(Balance.LIFE) > before, str(player.progress.stat(Balance.LIFE)))
	check("and the player got tougher right away", player.max_health > before,
		"%d -> %d" % [before, player.max_health])
	await tap(&"cancel")
	check("back to the pause menu", skills() == null and menu().is_open())
	await tap(&"cancel")
	check("and back to the game", not menu().is_open() and not tree.paused)


func test_the_cursor_picks_which_stat_gets_the_point() -> void:
	await reset_scene()
	await frames(2)
	await tap(&"pause")
	await tap(&"aim_down")
	await tap(&"jump")
	await tap(&"aim_down")        # LIFE -> ATTACK
	await tap(&"jump")
	check("attack took the point", player.progress.allocated.get(Balance.ATTACK, 0) == 1,
		str(player.progress.allocated))
	check("and life did not", player.progress.allocated.get(Balance.LIFE, 0) == 0, str(player.progress.allocated))


func test_the_skills_screen_also_counts_points_not_stat_points() -> void:
	# The same rule as character setup: the gold column shows points put in, not how much the stat grew (a point of life adds 10).
	await reset_scene()
	await frames(2)
	await tap(&"pause")
	await tap(&"aim_down")
	await tap(&"jump")
	var rows: Array = skills()._columns[0]["rows"]
	check("setup: nothing spent yet", rows[0]["bonus"].text == "", rows[0]["bonus"].text)
	await tap(&"jump")            # The first item is LIFE
	check("one point in life reads as +1", rows[0]["bonus"].text == "+1", rows[0]["bonus"].text)
	check("and the value beside it is the real one",
		rows[0]["value"].text == str(roundi(player.progress.stat(Balance.LIFE))), rows[0]["value"].text)
	await tap(&"cancel")
	await tap(&"cancel")


func test_running_out_of_points_stops_the_spending() -> void:
	await reset_scene()
	await frames(2)
	player.progress.points = 1
	await tap(&"pause")
	await tap(&"aim_down")
	await tap(&"jump")
	await tap(&"jump")
	check("setup: the last point is spent", player.progress.points == 0)
	var allocated: int = player.progress.allocated.get(Balance.LIFE, 0)
	await tap(&"jump")
	check("pressing again does nothing", player.progress.allocated.get(Balance.LIFE, 0) == allocated,
		str(player.progress.allocated))


func test_in_co_op_each_player_spends_their_own_points() -> void:
	await reset_scene(false, false, null, 2)
	await frames(2)
	await tap(&"pause")
	await tap(&"aim_down")
	await tap(&"jump")
	check("the screen shows a column for each player", skills() != null)
	var before := [player.progress.points, player2.progress.points]
	await tap_as(1, &"aim_down")   # Player 2 moves the cursor to ATTACK
	await tap_as(1, &"jump")
	check("the second player spent one", player2.progress.points == before[1] - 1, str(player2.progress.points))
	check("on their own attack", player2.progress.allocated.get(Balance.ATTACK, 0) == 1,
		str(player2.progress.allocated))
	check("the first player's points are untouched", player.progress.points == before[0], str(player.progress.points))
	check("and so are their stats", player.progress.allocated.is_empty(), str(player.progress.allocated))
	# The skill screen only closes once both players press back
	await tap_as(0, &"cancel")
	check("one player backing out is not enough", skills() != null)
	await tap_as(1, &"cancel")
	check("both of them is", skills() == null and menu().is_open())
	await tap(&"cancel")
