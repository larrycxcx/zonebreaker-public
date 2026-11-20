extends GameTest
## 第五关（实验室）的两个 Boss：中段小 Boss「变异枪手」（`BossGunner`）、关底 Boss（以后加在这里）。
##
## 小 Boss 和用户定的：一间闸门封住的房间，**打死它不算通关**；招式按固定顺序轮着来——
## 蓄力激光（趴下躲）→ 边走边打的激光弹 → 枪托冲撞，贴脸插一记前踢；血过半蓄力激光变成两道（先低后高，不能一直趴着）。

const PACK := "res://skins/lab/lab_skin.tres"
const GUNNER := "res://scenes/boss_5_mid.tscn"
const GROUND_Y := 320.0
const STAND_Y := 304.0


func pack() -> SkinPack:
	return load(PACK) as SkinPack


## 只留地面（测试关的浮台、墙会挡激光、挡人）。
func open_floor(skin: SkinPack = null) -> void:
	await reset_scene(false, false, skin)
	for node in main.get_node("Level").get_children():
		var slab := node as Platform
		if slab != null and slab.one_way:
			slab.free()


func gunner_at(x: float) -> BossGunner:
	var boss := (load(GUNNER) as PackedScene).instantiate() as BossGunner
	main.get_node("Enemies").add_child(boss)
	boss.global_position = Vector2(x, GROUND_Y - 24.0)
	return boss


## 一个站好了、出场了、什么都还没开始打的小 Boss（招式由用例自己挑）。
func ready_gunner(x: float) -> BossGunner:
	var boss := gunner_at(x)
	await frames(4)
	boss.appear()
	# 在画面里的话它这几帧可能已经自己出场、打了一招：全部归位
	boss.move = BossGunner.Move.IDLE
	boss.velocity = Vector2.ZERO
	boss._left = 99.0
	boss._turn = 0
	boss._home = boss.global_position
	boss._homed = true
	return boss


func test_the_gunner_is_a_boss_that_does_not_end_the_level() -> void:
	await open_floor()
	var boss := await ready_gunner(480)
	player.global_position = Vector2(200, STAND_Y)
	check("it is a boss (health bar, ultimate only hurts it)", boss is Boss)
	check("but its death does not clear the stage", not boss.ends_level)
	check("its entrance does not switch to the boss music", boss.appear_event != &"boss_appear",
		str(boss.appear_event))
	boss.take_damage(boss.health, Vector2.INF, player)
	await frames(10)
	check("killed: no stage clear", not events.has(&"level_clear"), str(events))
	check("but it paid out", events.has(&"enemy_death"))


func test_the_hud_shows_its_bar_like_any_boss() -> void:
	await open_floor()
	gunner_at(480)
	player.global_position = Vector2(300, STAND_Y)
	snap_camera()
	await frames(10)
	check("on screen: the boss bar shows", (main.get_node("HUD/BossBar") as Control).visible)


func test_it_charges_before_the_laser() -> void:
	await open_floor()
	var boss := await ready_gunner(480)
	player.global_position = Vector2(200, STAND_Y)
	player.grant_invincibility(10.0)
	boss._start(BossGunner.Move.CHARGE)
	var charged := 0
	for i in 120:
		await tree.physics_frame
		if boss.is_charging():
			charged += 1
		if boss.is_firing():
			break
	check("it holds a visible charge first", charged >= 30, "%d frames" % charged)
	check("then fires", boss.is_firing())


func fire_beam_at(boss: BossGunner, prone: bool) -> int:
	player.global_position = Vector2(220, STAND_Y)
	if prone:
		Input.action_press("crouch")
	await frames(6)
	var full := player.health
	boss._start(BossGunner.Move.BEAM)
	await frames(int(boss.beam_time * 60.0) + 2)
	release_all_input()
	return full - player.health


func test_the_laser_hits_you_standing_and_misses_you_lying_down() -> void:
	await open_floor()
	var boss := await ready_gunner(480)
	boss.facing = -1
	var lost := await fire_beam_at(boss, false)
	check("standing in its path: hit", lost > 0, str(lost))
	await open_floor()
	boss = await ready_gunner(480)
	boss.facing = -1
	lost = await fire_beam_at(boss, true)
	check("lying flat: it passes over you", lost == 0, str(lost))


func test_the_laser_stops_at_a_wall() -> void:
	await open_floor()
	var boss := await ready_gunner(480)
	boss.facing = -1
	add_wall(300, 80)
	player.global_position = Vector2(220, STAND_Y)
	await frames(4)
	var full := player.health
	boss._start(BossGunner.Move.BEAM)
	await frames(10)
	check("the beam ends at the wall", boss.beam_end().x > 290.0, "%.0f" % boss.beam_end().x)
	await frames(int(boss.beam_time * 60.0))
	check("so someone behind the wall is safe", player.health == full, "%d -> %d" % [full, player.health])


func test_below_half_health_it_fires_low_then_high() -> void:
	await open_floor()
	var boss := await ready_gunner(480)
	boss.facing = -1
	player.global_position = Vector2(200, STAND_Y)
	await frames(2)
	boss.take_damage(boss.health - int(boss.max_health * 0.4), Vector2.INF, player)
	check("half health: it is enraged", boss.is_enraged())
	check("and it said so (once)", events.count(&"boss_enrage") == 1)
	boss._start(BossGunner.Move.BEAM)
	var heights: Array[float] = []
	var from_the_gun := true
	var airborne := false
	for i in int(boss.beam_time * 60.0) * 2 + 40:
		await tree.physics_frame
		if boss.is_firing():
			# 激光永远从枪口出去（素材里没有举高枪的姿势，高的那道靠蹦起来打）
			from_the_gun = from_the_gun and is_equal_approx(boss.beam_height() - boss.global_position.y, boss.beam_low)
			if heights.size() == 2:
				airborne = airborne or not boss.is_on_floor()
			if heights.is_empty() or absf(heights[-1] - boss.beam_height()) > 1.0:
				heights.append(boss.beam_height())
	check("every beam leaves from the gun", from_the_gun)
	check("the high one is fired from the top of a hop", airborne)
	check("two beams, the second higher", heights.size() == 2 and heights[1] < heights[0] - 15.0, str(heights))
	if heights.size() == 2:
		var floor_y := GROUND_Y
		var standing := Rect2(188, floor_y - 32.0, 24, 32)
		check("the second one clears a standing head", heights[1] + boss.beam_half < standing.position.y,
			"%.0f vs head %.0f" % [heights[1], standing.position.y])
		check("but it is low enough to catch a jump", floor_y - heights[1] < 80.0, "%.0f above the floor" %
			(floor_y - heights[1]))


func test_point_blank_it_kicks_you_away() -> void:
	await open_floor()
	var boss := await ready_gunner(400)
	boss.facing = -1
	# 40：在踢的范围里，又没贴到身上（贴上了先吃接触伤害，无敌帧会把踢那一下吞掉）
	player.global_position = Vector2(360, STAND_Y)
	await frames(2)
	var full := player.health
	boss._left = 0.0
	await frames(int(boss.kick_time * 60.0) + 20)
	check("too close: a kick lands", player.health < full, "%d -> %d" % [full, player.health])
	check("and sends you flying back", player.global_position.x < 330.0, "%.0f" % player.global_position.x)


func test_the_lunge_winds_up_then_rushes_forward() -> void:
	await open_floor()
	var boss := await ready_gunner(480)
	boss.facing = -1
	player.global_position = Vector2(330, STAND_Y)
	await frames(2)
	var full := player.health
	boss._start(BossGunner.Move.LUNGE_WINDUP)
	var start := boss.global_position.x
	await frames(int(boss.lunge_windup * 60.0) - 4)
	check("during the wind-up it stays put (time to jump aside)", absf(boss.global_position.x - start) < 1.0)
	await frames(int(boss.lunge_time * 60.0) + 10)
	check("then it rushes forward", boss.global_position.x < start - 60.0, "%.0f -> %.0f" % [start, boss.global_position.x])
	check("and the rush hits whoever is in the way", player.health < full, "%d -> %d" % [full, player.health])


func test_it_walks_and_shoots_bolts() -> void:
	await open_floor()
	var boss := await ready_gunner(500)
	boss.facing = -1
	player.global_position = Vector2(120, STAND_Y)
	player.grant_invincibility(10.0)
	snap_camera()
	boss._start(BossGunner.Move.BOLTS)
	var start := boss.global_position.x
	var shots := 0
	for i in int(boss.bolt_time * 60.0):
		await tree.physics_frame
		shots = maxi(shots, main.get_node("Enemies").get_children().filter(
			func(n: Node) -> bool: return n is Bullet).size())
	check("it fires while advancing", shots >= 2, str(shots))
	check("and it walks towards you", boss.global_position.x < start - 20.0, "%.0f -> %.0f" % [start, boss.global_position.x])


func test_the_moves_come_in_a_fixed_order() -> void:
	await open_floor()
	var boss := await ready_gunner(500)
	player.global_position = Vector2(150, STAND_Y)
	player.grant_invincibility(30.0)
	snap_camera()
	boss._left = 0.0
	var seen: Array = []
	for i in 900:
		await tree.physics_frame
		var m: int = boss.move
		if m in [BossGunner.Move.CHARGE, BossGunner.Move.BOLTS, BossGunner.Move.LUNGE_WINDUP] and (seen.is_empty() or seen[-1] != m):
			seen.append(m)
		if seen.size() >= 4:
			break
	check("charge, bolts, lunge, then charge again", seen == [BossGunner.Move.CHARGE, BossGunner.Move.BOLTS,
		BossGunner.Move.LUNGE_WINDUP, BossGunner.Move.CHARGE], str(seen))


func test_it_keeps_to_its_room() -> void:
	await open_floor()
	var boss := await ready_gunner(500)
	player.global_position = Vector2(60, STAND_Y)
	player.grant_invincibility(30.0)
	snap_camera()
	boss._left = 0.0
	var lowest := boss.global_position.x
	for i in 600:
		await tree.physics_frame
		lowest = minf(lowest, boss.global_position.x)
	check("however you lure it, it stays within its room", lowest >= 500.0 - boss.roam_range - 2.0,
		"got to %.0f" % lowest)


func test_the_gunner_runs_in_the_pack_without_errors() -> void:
	if needs_art(): return
	await open_floor(pack())
	var boss := gunner_at(480)
	player.global_position = Vector2(200, STAND_Y)
	player.grant_invincibility(30.0)
	snap_camera()
	await frames(400)
	check("seven seconds of the gunner in the pack ran clean", is_instance_valid(boss))
	check("its HUD portrait comes from the pack", boss.hud_portrait() != null
		and boss.hud_portrait().resource_path.contains("lab"), str(boss.hud_portrait()))


# --- 关底 Boss「生化舱」 ---

const POD := "res://scenes/boss_5.tscn"


## 一个出场了、飘在测试关地面上空、什么都还没开始打的生化舱。
func ready_pod(x: float) -> BossPod:
	var boss := (load(POD) as PackedScene).instantiate() as BossPod
	main.get_node("Enemies").add_child(boss)
	boss.global_position = Vector2(x, GROUND_Y - 150.0)
	await frames(2)
	boss.appear()
	await frames(2)
	boss.move = BossPod.Move.HOVER
	boss._left = 99.0
	boss._turn = 0
	return boss


func bullet_count() -> int:
	return main.get_node("Enemies").get_children().filter(func(n: Node) -> bool: return n is Bullet).size()


func test_the_pod_is_the_stage_boss() -> void:
	await open_floor()
	var boss := await ready_pod(480)
	check("it ends the stage", boss.ends_level)
	check("it flies (no gravity)", boss.motion_mode == CharacterBody2D.MOTION_MODE_FLOATING and boss.gravity == 0.0)
	check("it found the floor under it", absf(boss.floor_y() - GROUND_Y) < 1.0, "%.0f" % boss.floor_y())
	await frames(60)
	check("and hangs in the air", boss.global_position.y < GROUND_Y - 100.0, "%.0f" % boss.global_position.y)


func test_the_moves_come_in_a_fixed_order_too() -> void:
	await open_floor()
	var boss := await ready_pod(480)
	player.global_position = Vector2(200, STAND_Y)
	player.grant_invincibility(60.0)
	snap_camera()
	boss._left = 0.0
	var seen: Array = []
	for i in 1500:
		await tree.physics_frame
		var m: int = boss.move
		if m in [BossPod.Move.CHARGE, BossPod.Move.CANNON, BossPod.Move.SHELL] and (seen.is_empty() or seen[-1] != m):
			seen.append(m)
		if seen.size() >= 5:
			break
	check("sweep, cannon, shell, cannon, sweep", seen == [BossPod.Move.CHARGE, BossPod.Move.CANNON, BossPod.Move.SHELL,
		BossPod.Move.CANNON, BossPod.Move.CHARGE], str(seen))


## 让它在玩家旁边扫一次，返回玩家掉了多少血（`prone` = 一直趴着）。
func sweep_at(boss: BossPod, prone: bool) -> int:
	player.global_position = Vector2(240, STAND_Y)
	if prone:
		Input.action_press("crouch")
	await frames(6)
	var full := player.health
	boss._face(player)
	boss._start(BossPod.Move.CHARGE)
	for i in 400:
		await tree.physics_frame
		if boss.move == BossPod.Move.HOVER:
			break
	release_all_input()
	return full - player.health


func test_the_sweep_presses_down_to_chest_height() -> void:
	await open_floor()
	var boss := await ready_pod(480)
	player.global_position = Vector2(240, STAND_Y)
	player.grant_invincibility(60.0)
	boss._start(BossPod.Move.CHARGE)
	var charged := 0
	var top := INF
	var bottom := -INF
	for i in 400:
		await tree.physics_frame
		if boss.is_charging():
			charged += 1
		if boss.is_firing():
			top = minf(top, boss.beam_height())
			bottom = maxf(bottom, boss.beam_height())
		if boss.move == BossPod.Move.HOVER and bottom > -INF:
			break
	check("a visible charge first", charged >= 40, "%d frames" % charged)
	check("it fires from up high", GROUND_Y - top > 120.0, "%.0f above the floor" % (GROUND_Y - top))
	check("and presses down to a standing chest", absf(GROUND_Y - bottom - boss.chest) < 1.0, "%.0f" % (GROUND_Y - bottom))


func test_lying_flat_dodges_the_sweep_standing_does_not() -> void:
	await open_floor()
	var boss := await ready_pod(480)
	var lost := await sweep_at(boss, false)
	check("standing on the floor: the sweep gets you", lost > 0, str(lost))
	await open_floor()
	boss = await ready_pod(480)
	lost = await sweep_at(boss, true)
	check("lying flat: it passes over you", lost == 0, str(lost))


func test_the_sweep_stops_at_a_wall() -> void:
	await open_floor()
	var boss := await ready_pod(480)
	add_wall(330, 200)
	player.global_position = Vector2(240, STAND_Y)
	await frames(4)
	var full := player.health
	boss._face(player)
	boss._start(BossPod.Move.CHARGE)
	for i in 400:
		await tree.physics_frame
		if boss.is_firing():
			check("the beam ends at the wall", boss.beam_end().x > 320.0, "%.0f" % boss.beam_end().x)
			break
	for i in 300:
		await tree.physics_frame
		if boss.move == BossPod.Move.HOVER:
			break
	check("behind the wall you are safe", player.health == full, "%d -> %d" % [full, player.health])


func test_below_half_it_sweeps_back_up() -> void:
	await open_floor()
	var boss := await ready_pod(480)
	player.global_position = Vector2(240, STAND_Y)
	player.grant_invincibility(60.0)
	boss.take_damage(boss.health - int(boss.max_health * 0.4), Vector2.INF, player)
	check("half health: enraged", boss.is_enraged())
	check("said so once", events.count(&"boss_enrage") == 1)
	boss._start(BossPod.Move.CHARGE)
	var went_back := false
	var low := -INF
	for i in 500:
		await tree.physics_frame
		if boss.is_firing():
			low = maxf(low, boss.beam_height())
			if boss.move == BossPod.Move.SWEEP_BACK and boss.beam_height() < low - 40.0:
				went_back = true
		if boss.move == BossPod.Move.HOVER and low > -INF:
			break
	check("after pressing down it sweeps back up with the beam on", went_back)


func cannon_for(offset: Vector2) -> int:
	await open_floor()
	var boss := await ready_pod(400)
	player.global_position = boss.global_position + offset
	await frames(1)
	return boss.pick_cannon(player)


func test_it_picks_the_cannon_by_where_you_are() -> void:
	check("right below: the down cannon", await cannon_for(Vector2(10, 150)) == BossPod.Cannon.DOWN)
	check("below and to the side: the diagonal one", await cannon_for(Vector2(-130, 150)) == BossPod.Cannon.DIAGONAL)
	check("level or far off: the level one", await cannon_for(Vector2(-300, 10)) == BossPod.Cannon.LEVEL)


func test_the_cannon_shots_fly_where_the_cannon_points() -> void:
	await open_floor()
	var boss := await ready_pod(400)
	player.global_position = Vector2(280, STAND_Y)
	player.grant_invincibility(60.0)
	snap_camera()
	boss._start(BossPod.Move.CANNON)
	var shot := []
	boss.shot_fired.connect(func() -> void:
		shot.append([boss.cannon, boss.last_shot_direction, boss.last_muzzle_position - boss.global_position]))
	for i in 200:
		await tree.physics_frame
		if not shot.is_empty():
			break
	check("it fired", not shot.is_empty())
	if shot.is_empty():
		return
	var which: int = shot[0][0]
	var dir: Vector2 = shot[0][1]
	var at: Vector2 = shot[0][2]
	var wants := {BossPod.Cannon.DOWN: Vector2.DOWN, BossPod.Cannon.DIAGONAL: Vector2(boss.facing, 1).normalized(),
		BossPod.Cannon.LEVEL: Vector2(boss.facing, 0)}
	var want: Vector2 = wants[which]
	check("the shot goes the way that cannon points", dir.is_equal_approx(want), "%s vs %s" % [dir, want])
	var muzzle: Vector2 = BossPod.CANNON_MUZZLES[which]
	check("from that cannon's muzzle", at.is_equal_approx(Vector2(muzzle.x * boss.facing, muzzle.y)), str(at))


func test_in_its_shell_nothing_hurts_it() -> void:
	await open_floor()
	var boss := await ready_pod(480)
	player.global_position = Vector2(200, STAND_Y)
	player.grant_invincibility(60.0)
	boss._start(BossPod.Move.SHELL)
	var full := boss.health
	boss.take_damage(50, Vector2.INF, player)
	boss.hit_by_ultimate(player)
	check("shelled: shots and the ultimate do nothing", boss.health == full, "%d -> %d" % [full, boss.health])
	var before := bullet_count()
	for i in int(boss.shell_time * 60.0) + 4:
		await tree.physics_frame
	var ring := bullet_count() - before
	check("it opens with a ring of shots", ring == boss.ring_count, str(ring))
	boss.take_damage(50, Vector2.INF, player)
	check("open again: it can be hurt", boss.health == full - 50, "%d" % boss.health)


func test_the_pod_keeps_to_its_arena() -> void:
	await open_floor()
	var boss := await ready_pod(500)
	player.global_position = Vector2(40, STAND_Y)
	player.grant_invincibility(60.0)
	snap_camera()
	boss._left = 0.0
	var lowest := boss.global_position.x
	for i in 900:
		await tree.physics_frame
		lowest = minf(lowest, boss.global_position.x)
	check("it stays within its arena", lowest >= 500.0 - boss.roam_range - 0.5, "%.0f" % lowest)


func test_the_pod_runs_in_the_pack_without_errors() -> void:
	if needs_art(): return
	await open_floor(pack())
	var boss := (load(POD) as PackedScene).instantiate() as BossPod
	main.get_node("Enemies").add_child(boss)
	boss.global_position = Vector2(480, GROUND_Y - 150.0)
	player.global_position = Vector2(200, STAND_Y)
	player.grant_invincibility(60.0)
	snap_camera()
	var art := (boss._visual as Node).get(&"art_dir") as String
	var missing := {}
	for i in 900:
		await tree.physics_frame
		var shown: StringName = boss._visual.call(&"clip")
		for side in ["r", "l"]:
			var path := "%s/%s_%s.png" % [art, shown, side]
			if not ResourceLoader.exists(path):
				missing[path] = true
	check("fifteen seconds of the pod in the pack ran clean", is_instance_valid(boss))
	check("every clip it showed exists in the pack", missing.is_empty(), str(missing.keys()))
	check("its HUD portrait comes from the pack", boss.hud_portrait() != null
		and boss.hud_portrait().resource_path.contains("lab"), str(boss.hud_portrait()))
