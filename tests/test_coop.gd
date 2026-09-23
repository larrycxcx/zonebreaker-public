extends GameTest
## 双人（第一步：输入分开、敌人认两个玩家）。
##
## 守的东西：双人时才生成 2 号；两套输入互不干扰；方向键双人时归 2 号、切回单人还给 1 号；
## 每个 2 号动作都有键盘和 2 号手柄的绑定；敌人打**最近的、打得着的**那个（最近的躲墙后就打另一个），
## 死掉的玩家不再被当目标；终极武器让两个人一起无敌。

const P1_ACTIONS := ["move_left", "move_right", "jump", "crouch", "sprint", "shoot", "switch_weapon", "ultimate", "aim_down", "aim_up"]


func arrows_of(action: StringName) -> Array:
	return InputMap.action_get_events(action).filter(func(event: InputEvent) -> bool:
		return event is InputEventKey and Session.SHARED_KEYS.has((event as InputEventKey).physical_keycode))


func pads_of(action: StringName) -> Array:
	return InputMap.action_get_events(action).filter(func(event: InputEvent) -> bool:
		return event is InputEventJoypadButton or event is InputEventJoypadMotion)


# ---------------------------------------------------------------- 谁在场

func test_the_second_player_only_shows_up_in_two_player() -> void:
	await reset_scene()
	check("one player by default", player2 == null and tree.get_nodes_in_group(&"player").size() == 1)
	await reset_scene(false, false, null, 2)
	check("two players in co-op", player2 != null and tree.get_nodes_in_group(&"player").size() == 2)
	check("they are numbered", player.player_index == 0 and player2.player_index == 1)
	check("and start side by side", absf(player2.global_position.x - player.global_position.x) < 64.0
		and absf(player2.global_position.y - player.global_position.y) < 1.0, str(player2.global_position - player.global_position))


# ---------------------------------------------------------------- 输入分开

func test_every_action_has_a_second_player_copy() -> void:
	for action in P1_ACTIONS:
		var second := StringName("p2_" + action)
		check("%s has a second-player action" % action, InputMap.has_action(second))
		if not InputMap.has_action(second):
			continue
		var keys := InputMap.action_get_events(second).filter(func(event: InputEvent) -> bool: return event is InputEventKey)
		check("%s: keyboard and gamepad" % second, not keys.is_empty() and not pads_of(second).is_empty())
		check("%s: on the second gamepad" % second, pads_of(second).all(func(event: InputEvent) -> bool: return event.device == 1))
		check("%s: on the first gamepad" % action, pads_of(action).all(func(event: InputEvent) -> bool: return event.device == 0))


func test_the_arrow_keys_move_to_the_second_player_in_co_op() -> void:
	Session.set_player_count(1)
	var solo := arrows_of(&"move_left").size()
	check("solo: the first player keeps the arrow keys", solo > 0, str(solo))
	Session.set_player_count(2)
	check("co-op: the first player gives them up", arrows_of(&"move_left").is_empty())
	check("and the second player has them", not arrows_of(&"p2_move_left").is_empty())
	Session.set_player_count(1)
	check("back to solo: they come back", arrows_of(&"move_left").size() == solo, str(arrows_of(&"move_left").size()))


func test_each_player_answers_only_to_its_own_keys() -> void:
	await reset_scene(false, false, null, 2)
	player.global_position = Vector2(200, 304)
	player2.global_position = Vector2(300, 304)
	await frames(2)
	var start := [player.global_position.x, player2.global_position.x]
	Input.action_press("p2_move_right")
	await frames(20)
	release_all_input()
	check("the second player's key moves only the second player",
		player2.global_position.x - start[1] > 10.0 and absf(player.global_position.x - start[0]) < 1.0,
		"P1 %.1f, P2 %.1f" % [player.global_position.x - start[0], player2.global_position.x - start[1]])
	# 上一段松手后 2 号还有惯性，会再滑一小段：停稳了再看下一段
	player.velocity = Vector2.ZERO
	player2.velocity = Vector2.ZERO
	await frames(2)
	start = [player.global_position.x, player2.global_position.x]
	Input.action_press("move_right")
	await frames(20)
	release_all_input()
	check("and the first player's key moves only the first player",
		player.global_position.x - start[0] > 10.0 and absf(player2.global_position.x - start[1]) < 1.0,
		"P1 %.1f, P2 %.1f" % [player.global_position.x - start[0], player2.global_position.x - start[1]])


func test_the_second_player_shoots_with_its_own_key() -> void:
	await reset_scene(false, false, null, 2)
	player.global_position = Vector2(200, 304)
	player2.global_position = Vector2(300, 304)
	await frames(2)
	Input.action_press("p2_shoot")
	await frames(3)
	release_all_input()
	var shots := bullets(4)
	check("the second player fires", not shots.is_empty())
	if not shots.is_empty():
		check("from the second player, not the first",
			shots.all(func(shot: Bullet) -> bool: return absf(shot.global_position.x - player2.global_position.x) < 60.0), str(shots.size()))


# ---------------------------------------------------------------- 共用摄像机

func test_the_camera_belongs_to_the_level_not_to_a_player() -> void:
	await reset_scene()
	check("the level owns the camera", camera_rig() != null and camera_rig() is CameraRig)
	check("and no player carries one", player.get_node_or_null("Camera2D") == null)


func test_solo_keeps_the_camera_on_the_one_player() -> void:
	# 单人时中点就是这个玩家本人，画面和摄像机还挂在玩家身上那会儿一模一样。
	await reset_scene()
	player.global_position = Vector2(400, 304)
	await frames(3)
	check("the camera sits on the player", absf(camera_rig().global_position.x - player.global_position.x) < 0.5,
		"%.1f vs %.1f" % [camera_rig().global_position.x, player.global_position.x])
	# 对照：单人永远夹不到人，走到哪都不会被镜头推着走
	var spot := player.global_position
	await frames(5)
	check("and never pushes them around", absf(player.global_position.x - spot.x) < 0.5, str(player.global_position - spot))


func test_co_op_follows_the_middle_of_the_two() -> void:
	await reset_scene(false, false, null, 2)
	player.global_position = Vector2(300, 304)
	player2.global_position = Vector2(500, 304)
	await frames(3)
	check("the camera sits between them",
		absf(camera_rig().global_position.x - 400.0) < 1.0, "%.1f" % camera_rig().global_position.x)


func test_neither_player_can_be_pushed_off_screen() -> void:
	# 魂斗罗的规矩：镜头跟中点，谁落在画面外就被拖回来。分头走只能走到画面两边为止。
	await reset_scene(false, false, null, 2)
	player.global_position = Vector2(200, 304)
	player2.global_position = Vector2(1100, 304)
	await frames(3)
	var view := camera_rig().view_rect()
	check("setup: they are further apart than one screen", view.size.x < 900.0, "画面宽 %.0f" % view.size.x)
	for who in [player, player2]:
		check("%s is back inside the view" % who.name, view.grow(-1.0).has_point(who.global_position),
			"x=%.1f，画面 %.1f..%.1f" % [who.global_position.x, view.position.x, view.end.x])
	check("and they really did get dragged together",
		absf(player2.global_position.x - player.global_position.x) < 900.0,
		"%.1f" % absf(player2.global_position.x - player.global_position.x))


func test_a_dead_player_neither_drags_the_camera_nor_gets_dragged() -> void:
	await reset_scene(false, false, null, 2)
	player.global_position = Vector2(300, 304)
	player2.global_position = Vector2(700, 304)
	await frames(3)
	check("setup: the camera is between them", absf(camera_rig().global_position.x - 500.0) < 1.0,
		"%.1f" % camera_rig().global_position.x)
	player2.take_damage(player2.health)
	await frames(3)
	check("once one dies the camera follows the living one",
		absf(camera_rig().global_position.x - player.global_position.x) < 1.0,
		"%.1f vs %.1f" % [camera_rig().global_position.x, player.global_position.x])


# ---------------------------------------------------------------- 2 号玩家长什么样

func test_the_two_players_wear_different_characters() -> void:
	# 同屏两个人得看得出谁是谁：两个座位默认拿两套不同的外观。
	var skin := load(CYBERPUNK) as SkinPack
	await reset_scene(false, false, skin, 2)
	var one: Node = player.get_node("Visual")
	var two: Node = player2.get_node("Visual")
	check("both are wearing the pack's sprites", one is SpriteAppearance and two is SpriteAppearance)
	check("but not the same character", one.get(&"art_dir") != two.get(&"art_dir"),
		"%s / %s" % [one.get(&"art_dir"), two.get(&"art_dir")])
	check("each wears what their own character says", String(one.get(&"art_dir")).ends_with(String(player.progress.look))
		and String(two.get(&"art_dir")).ends_with(String(player2.progress.look)),
		"%s / %s" % [player.progress.look, player2.progress.look])


func test_the_look_comes_from_the_character_not_the_seat() -> void:
	# 外观是角色自己的属性：1 号玩家照样可以是 Punk。
	var skin := load(CYBERPUNK) as SkinPack
	await reset_scene(false, false, skin, 1)
	check("setup: the first seat starts on the default look", player.progress.look == &"biker", str(player.progress.look))
	# 换个外观再重开这一关（进度不重置，就像菜单里选完角色进关一样）
	Progress.of(0).look = &"cyborg"
	free_scene()
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	player = main.get_node("Player")
	for enemy in enemies():
		enemy.free()
	await frames(2)
	check("the first player wears what their character picked",
		String(player.get_node("Visual").get(&"art_dir")).ends_with("cyborg"),
		str(player.get_node("Visual").get(&"art_dir")))


func test_a_different_character_changes_nothing_about_the_rules() -> void:
	# 换外观不能换规则：两个人的判定框、出膛点、跳跃高度必须一模一样。
	var skin := load(CYBERPUNK) as SkinPack
	await reset_scene(false, false, skin, 2)
	player.global_position = Vector2(200, 304)
	player2.global_position = Vector2(300, 304)
	await frames(10)
	var box_one: RectangleShape2D = (player.get_node("CollisionShape2D") as CollisionShape2D).shape
	var box_two: RectangleShape2D = (player2.get_node("CollisionShape2D") as CollisionShape2D).shape
	check("same collision box", box_one.size == box_two.size, "%s vs %s" % [box_one.size, box_two.size])
	for aim in [Vector2.RIGHT, Vector2.UP, Vector2(1, -1).normalized(), Vector2(1, 1).normalized(), Vector2.DOWN]:
		var one := player._muzzle_position(aim) - player.global_position
		var two := player2._muzzle_position(aim) - player2.global_position
		check("same muzzle aiming %s" % aim, one == two, "%s vs %s" % [one, two])


# ---------------------------------------------------------------- 濒死与营救

## 把两个人放到互相够不着的地方，免得刚倒地就被顺手救起来。
func stand_apart() -> void:
	player.global_position = Vector2(200, 304)
	player2.global_position = Vector2(560, 304)
	player.velocity = Vector2.ZERO
	player2.velocity = Vector2.ZERO
	snap_camera()
	await frames(3)


func test_solo_death_is_still_just_death() -> void:
	# 一个人玩没人来救，倒地只会变成站着等死，所以单人根本不进这个状态。
	await reset_scene()
	player.take_damage(player.max_health)
	await frames(2)
	check("no downed state on your own", not player.is_downed())
	check("the player is simply dead", not player.is_alive() and player.health == 0)


func test_emptying_the_bar_in_co_op_puts_you_down_instead() -> void:
	await reset_scene(false, false, null, 2)
	await stand_apart()
	var fell := []
	player2.downed.connect(func() -> void: fell.append(true))
	player2.take_damage(player2.max_health)
	await frames(2)
	check("the second player goes down", player2.is_downed() and fell.size() == 1, str(fell))
	check("not dead yet", is_instance_valid(player2) and player2.health == 0)
	check("but out of play", not player2.is_alive())
	check("with a countdown running", player2.down_time_left() > 0.0 and player2.down_time_left() <= player2.down_time,
		"%.1f" % player2.down_time_left())


func test_a_downed_player_cannot_be_shot_or_moved() -> void:
	await reset_scene(false, false, null, 2)
	await stand_apart()
	player2.take_damage(player2.max_health)
	# 先让倒计时走掉半秒，这样「被打了一下又回到满格」一眼就看得出来
	await frames(30)
	var left := player2.down_time_left()
	var spot := player2.global_position
	player2.take_damage(HIT)
	Input.action_press("p2_move_right")
	Input.action_press("p2_shoot")
	await frames(10)
	release_all_input()
	check("a stray shot takes nothing off", player2.health == 0, str(player2.health))
	check("and does not put the countdown back to the top",
		player2.down_time_left() < left and player2.down_time_left() < player2.down_time - 0.4,
		"满格 %.1f，挨打前 %.2f，挨打后 %.2f" % [player2.down_time, left, player2.down_time_left()])
	check("and they cannot walk away", absf(player2.global_position.x - spot.x) < 2.0,
		str(player2.global_position - spot))
	check("nor fire", bullets(4).is_empty(), str(bullets(4).size()))


func test_enemies_leave_a_downed_player_alone() -> void:
	await reset_scene(true, false, null, 2)
	keep_only_enemies(["ChaserD"])
	var d: EnemyChaser = main.get_node("Enemies/ChaserD")
	d.global_position = Vector2(600, 306)
	d.velocity = Vector2.ZERO
	player.global_position = Vector2(300, 304)
	player2.global_position = Vector2(700, 304)
	snap_camera()
	await frames(5)
	check("setup: it is going for the nearer (second) player", d.velocity.x > 0.0, "vx %.1f" % d.velocity.x)
	player2.take_damage(player2.max_health)
	await frames(5)
	check("once they are down it turns to the one still standing", d.velocity.x < 0.0, "vx %.1f" % d.velocity.x)


func test_a_team_mate_who_walks_over_picks_you_up() -> void:
	await reset_scene(false, false, null, 2)
	await stand_apart()
	player2.take_damage(player2.max_health)
	await frames(2)
	check("setup: down", player2.is_downed())
	player.global_position = player2.global_position + Vector2(16, 0)
	await frames(3)
	check("standing next to them brings them back", not player2.is_downed() and player2.is_alive())
	check("with half a bar", player2.health == int(player2.max_health * player2.revive_health_ratio),
		"%d / %d" % [player2.health, player2.max_health])
	check("and a moment of safety", player2.is_invincible())


func test_nobody_comes_and_the_countdown_runs_out() -> void:
	await reset_scene(false, false, null, 2)
	await stand_apart()
	player2.down_time = 0.3 # 别让用例等十秒
	player2.take_damage(player2.max_health)
	await frames(2)
	check("setup: down, not dead", player2.is_downed())
	for i in 60:
		await tree.physics_frame
		if not player2.is_downed():
			break
	check("the countdown finishes the job", not player2.is_downed() and player2.health == 0)
	check("and now they are really dead", not player2.is_alive() and events.has(&"player_death"))


func test_the_level_only_restarts_once_both_are_out() -> void:
	await reset_scene(false, false, null, 2)
	await stand_apart()
	player.down_time = 0.2
	player2.down_time = 0.2
	player.take_damage(player.max_health)
	# 等久一点：1 号的倒计时走完、真死了，连 game_over 该响的那半秒也过了
	await frames(90)
	check("setup: the first player really is dead", not player.is_alive() and not player.is_downed(),
		"alive %s, downed %s" % [player.is_alive(), player.is_downed()])
	check("but the team mate is still standing, so the level goes on", not events.has(&"game_over"), str(events))
	player2.take_damage(player2.max_health)
	await frames(5)
	check("the second one is only down, still no game over", player2.is_downed() and not events.has(&"game_over"), str(events))
	for i in 120:
		await tree.physics_frame
		if events.has(&"game_over"):
			break
	check("only once nobody is left", events.has(&"game_over"), str(events))


# ---------------------------------------------------------------- 左右两套 HUD

const CYBERPUNK := "res://skins/cyberpunk/cyberpunk_skin.tres"


func huds() -> Array:
	return main.get_children().filter(func(node: Node) -> bool: return node is CanvasLayer and node.has_method("look"))


func bar_of(hud_name: String) -> ColorRect:
	return main.get_node("%s/HealthBar" % hud_name) as ColorRect


func test_two_players_get_two_huds() -> void:
	await reset_scene()
	check("solo has one HUD", huds().size() == 1, str(huds().size()))
	await reset_scene(false, false, null, 2)
	check("co-op has two", huds().size() == 2, str(huds().size()))
	check("one for each player",
		main.get_node("HUD").player_index == 0 and main.get_node("HUD2").player_index == 1)


func test_the_two_huds_sit_on_opposite_sides() -> void:
	await reset_scene(false, false, null, 2)
	var left := bar_of("HUD")
	var right := bar_of("HUD2")
	check("the first player's bar is on the left half", left.position.x + left.size.x < 320.0,
		"%.0f..%.0f" % [left.position.x, left.position.x + left.size.x])
	check("the second player's is on the right half", right.position.x > 320.0,
		"%.0f..%.0f" % [right.position.x, right.position.x + right.size.x])
	check("and they are the same size", is_equal_approx(left.size.x, right.size.x), "%.0f vs %.0f" % [left.size.x, right.size.x])


func test_the_skinned_hud_is_mirrored_too() -> void:
	# 素材包的 HUD 外观是另一棵树，镜像要一起做，否则右边那套画面还留在左边
	var skin := load(CYBERPUNK) as SkinPack
	await reset_scene(false, false, skin, 2)
	check("setup: the pack really brought a HUD look", main.get_node("HUD").look() != null)
	var left: Control = main.get_node("HUD").look()
	var right: Control = main.get_node("HUD2").look()
	check("the second player's art moved to the right", right.position.x > left.position.x + 200.0,
		"%.0f vs %.0f" % [left.position.x, right.position.x])
	# 它画出来的东西也跟着走了：武器槽是外观里的节点，位置按外观根节点算
	var slot_left: Control = left.get_node("WeaponSlot")
	var slot_right: Control = right.get_node("WeaponSlot")
	check("so does what it draws", slot_right.global_position.x > slot_left.global_position.x + 200.0,
		"%.0f vs %.0f" % [slot_left.global_position.x, slot_right.global_position.x])


func test_each_hud_shows_its_own_player() -> void:
	await reset_scene(false, false, null, 2)
	var fill_one: ColorRect = main.get_node("HUD/HealthBar/Fill")
	var fill_two: ColorRect = main.get_node("HUD2/HealthBar/Fill")
	var before := [fill_one.size.x, fill_two.size.x]
	check("setup: both bars start full", before[0] == before[1] and before[0] > 0.0, str(before))
	player2.take_damage(HIT)
	await frames(2)
	check("hurting the second player shortens only their bar",
		fill_two.size.x < before[1] and fill_one.size.x == before[0],
		"P1 %.0f->%.0f, P2 %.0f->%.0f" % [before[0], fill_one.size.x, before[1], fill_two.size.x])


func test_each_hud_shows_its_own_progress() -> void:
	await reset_scene(false, false, null, 2)
	Progress.of(1).add_money(42)
	await frames(2)
	var one: Label = main.get_node("HUD/ProgressLabel")
	var two: Label = main.get_node("HUD2/ProgressLabel")
	check("the second player's purse shows on their own HUD", two.text.contains("CASH 42"), two.text)
	check("and not on the first player's", not one.text.contains("CASH 42"), one.text)


func test_the_shared_parts_show_up_once() -> void:
	await reset_scene(true, false, null, 2)
	keep_only_enemies(["BossA"])
	(main.get_node("Enemies/BossA") as Boss).appear()
	await frames(2)
	check("the boss bar is on the first player's HUD", (main.get_node("HUD/BossBar") as Control).visible)
	check("and never on the second's", not (main.get_node("HUD2/BossBar") as Control).visible)
	# 两个人都倒下、倒计时也走完（双人时血空了是倒地，不是直接死）
	player.down_time = 0.05
	player2.down_time = 0.05
	player.take_damage(player.max_health)
	player2.take_damage(player2.max_health)
	for i in 60:
		await tree.physics_frame
		if not player.is_alive() and not player.is_downed() and not player2.is_downed():
			break
	check("setup: both are really dead", not player.is_downed() and not player2.is_downed()
		and player.health == 0 and player2.health == 0)
	check("the death message shows once", (main.get_node("HUD/Message") as Label).visible
		and not (main.get_node("HUD2/Message") as Label).visible)


# ---------------------------------------------------------------- 各存各的成长进度

const SAVE_FOR_TEST := "user://test_coop_progress.json"


func drop_test_save() -> void:
	Progress.persist = false
	Progress.save_path = Progress.DEFAULT_SAVE
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_FOR_TEST))


func test_each_player_has_their_own_progress() -> void:
	await reset_scene(false, false, null, 2)
	check("two separate profiles", Progress.of(0) != Progress.of(1))
	check("each player holds their own", player.progress == Progress.of(0) and player2.progress == Progress.of(1))
	Progress.of(0).add_xp(Progress.balance.xp_to_next(1))
	Progress.of(0).add_money(50)
	await frames(2)
	check("levelling one does not level the other",
		Progress.of(0).level == 2 and Progress.of(1).level == 1,
		"P1 Lv%d, P2 Lv%d" % [Progress.of(0).level, Progress.of(1).level])
	check("and the money stays apart", Progress.of(0).money == 50 and Progress.of(1).money == 0,
		"P1 $%d, P2 $%d" % [Progress.of(0).money, Progress.of(1).money])


func test_a_stat_point_only_reaches_its_own_player() -> void:
	await reset_scene(false, false, null, 2)
	var before := [player.max_health, player2.max_health]
	check("setup: both start the same", before[0] == before[1], str(before))
	Progress.of(1).points = 1
	Progress.of(1).spend_point(Balance.LIFE)
	await frames(2)
	check("the second player gets tougher", player2.max_health > before[1],
		"%d -> %d" % [before[1], player2.max_health])
	check("the first player is untouched", player.max_health == before[0],
		"%d -> %d" % [before[0], player.max_health])


func test_the_kill_pays_whoever_made_it() -> void:
	await reset_scene(true, false, null, 2)
	keep_only_enemies(["WalkerA"])
	var walker: Enemy = main.get_node("Enemies/WalkerA")
	walker.global_position = Vector2(500, 304)
	walker._fire_timer = 999.0
	player.global_position = Vector2(300, 304)
	player2.global_position = Vector2(400, 304)
	await frames(2)
	var before := [Progress.of(0).xp, Progress.of(1).xp]
	Input.action_press("p2_shoot")
	for i in 120:
		await tree.physics_frame
		if not is_instance_valid(walker):
			break
	release_all_input()
	check("the second player shot it dead", not is_instance_valid(walker))
	check("so the second player is paid", Progress.of(1).xp > before[1],
		"%d -> %d" % [before[1], Progress.of(1).xp])
	check("and the first player, who never fired, is not", Progress.of(0).xp == before[0],
		"%d -> %d" % [before[0], Progress.of(0).xp])


func test_the_save_holds_both_players() -> void:
	await reset_scene(false, false, null, 2)
	Progress.save_path = SAVE_FOR_TEST
	Progress.persist = true
	Progress.of(0).add_money(30)
	Progress.of(1).add_money(70)
	Progress.new_game()
	check("setup: a new game forgets it all", Progress.of(0).money == 0 and Progress.of(1).money == 0)
	Progress.load_game()
	check("both purses come back", Progress.of(0).money == 30 and Progress.of(1).money == 70,
		"P1 $%d, P2 $%d" % [Progress.of(0).money, Progress.of(1).money])
	drop_test_save()


func test_a_save_from_before_co_op_still_loads() -> void:
	# 双人之前的存档是一份进度直接摊在最外层，没有 players 这一项。读到那种就当成 1 号的。
	await reset_scene(false, false, null, 2)
	var file := FileAccess.open(SAVE_FOR_TEST, FileAccess.WRITE)
	file.store_string(JSON.stringify({"level": 3, "xp": 4, "money": 99, "points": 2}))
	file.close()
	Progress.save_path = SAVE_FOR_TEST
	Progress.load_game()
	check("the old save becomes the first player", Progress.of(0).level == 3 and Progress.of(0).money == 99,
		"Lv%d $%d" % [Progress.of(0).level, Progress.of(0).money])
	check("and the second player starts fresh", Progress.of(1).level == 1 and Progress.of(1).money == 0,
		"Lv%d $%d" % [Progress.of(1).level, Progress.of(1).money])
	drop_test_save()


# ---------------------------------------------------------------- 敌人认两个玩家

func test_an_enemy_goes_for_the_nearest_player_it_can_see() -> void:
	await reset_scene(true, false, null, 2)
	keep_only_enemies(["ChaserD"])
	var d: EnemyChaser = main.get_node("Enemies/ChaserD")
	d.global_position = Vector2(600, 306)
	d.velocity = Vector2.ZERO
	player.global_position = Vector2(300, 304)   # 远
	player2.global_position = Vector2(700, 304)  # 近
	snap_camera()
	await frames(5)
	check("it charges the nearer player", d.is_chasing and d.velocity.x > 0.0, "vx %.1f" % d.velocity.x)
	# 近的那个躲到墙后：改打看得见的那个（不是简单挑最近的）
	add_wall(660, 60)
	await frames(5)
	check("with the nearer one behind a wall, it goes for the other", d.velocity.x < 0.0, "vx %.1f" % d.velocity.x)


func test_a_dead_player_is_no_longer_a_target() -> void:
	await reset_scene(true, false, null, 2)
	keep_only_enemies(["ChaserD"])
	var d: EnemyChaser = main.get_node("Enemies/ChaserD")
	d.global_position = Vector2(600, 306)
	d.velocity = Vector2.ZERO
	player.global_position = Vector2(300, 304)
	player2.global_position = Vector2(700, 304)
	snap_camera()
	await frames(5)
	check("setup: chasing the nearer (second) player", d.velocity.x > 0.0, "vx %.1f" % d.velocity.x)
	player2.take_damage(player2.health)
	await frames(5)
	check("once it dies, the enemy turns to the living one", d.velocity.x < 0.0, "vx %.1f" % d.velocity.x)


func test_the_ultimate_protects_both_players() -> void:
	await reset_scene(false, false, null, 2)
	player.global_position = Vector2(200, 304)
	player2.global_position = Vector2(240, 304)
	await frames(2)
	Input.action_press("ultimate")
	await frames(2)
	release_all_input()
	check("both players are invincible during the freeze", player.is_invincible() and player2.is_invincible())
	for i in 300:
		if not tree.paused:
			break
		await tree.physics_frame
	tree.paused = false
