extends GameTest
## 敌人斜射：B、C、炮台在玩家位于斜上/斜下方向（偏离水平 45.0°~135.0°、直线距离在射程内）时，
## 巡逻兵停下、炮台转向，瞄准 0.3 秒后朝 45° 开火；A 不会。玩家回到水平方向或离开后恢复原样。

const DIAGONAL := 0.7071


## 只留一个敌人，放到 pos 朝左（巡逻兵会照常巡逻，除非 still = true）。
func _place(enemy_name: String, pos: Vector2, still := false) -> Enemy:
	await reset_scene(true)
	keep_only_enemies([enemy_name])
	var enemy: Enemy = main.get_node("Enemies/" + enemy_name)
	enemy.global_position = pos
	enemy.facing = -1
	enemy._visual.scale.x = -1
	if enemy is EnemyWalker:
		(enemy as EnemyWalker)._apply_facing()
		if still:
			(enemy as EnemyWalker).move_speed = 0.0
	# 先把玩家停在所有射程之外：否则准备阶段敌人就开始水平连发，会搅乱后面对斜射的观察。
	player.global_position = Vector2(1240.0 if pos.x < 640.0 else 40.0, 304)
	await frames(5)
	return enemy


## 观察若干帧：记录每颗子弹的方向和它是第几帧射出的，以及敌人横向走了多远。
func _watch(enemy: Enemy, frame_count: int, invincible := true) -> Dictionary:
	var shots := []
	var frame := [0]
	var record := func() -> void: shots.append({"frame": frame[0], "direction": enemy.last_shot_direction})
	enemy.shot_fired.connect(record)
	var x0 := enemy.global_position.x
	var stood_still := true
	for i in frame_count:
		if invincible:
			player._invincible_timer = 1000.0
		await tree.physics_frame
		frame[0] += 1
		if is_instance_valid(enemy) and absf(enemy.velocity.x) > 0.1:
			stood_still = false
	if is_instance_valid(enemy):
		enemy.shot_fired.disconnect(record)
	return {"shots": shots, "moved": absf(enemy.global_position.x - x0) if is_instance_valid(enemy) else 0.0, "stood_still": stood_still}


## 枪管（占位美术）实际指着哪个方向：枪管按「朝右」摆，朝左时整块镜像过去，所以本地 +x 指向身体。
func gun_direction(e: Enemy) -> Vector2:
	var gun := turning_gun(e)
	return (Vector2.RIGHT if e.facing > 0 else Vector2.LEFT).rotated(gun.rotation)


func _all_toward(shots: Array, expected: Vector2) -> bool:
	return not shots.is_empty() and shots.all(func(s): return s["direction"].is_equal_approx(expected))


# ---------------------------------------------------------------- 配置与判定

func test_which_enemies_aim_diagonally() -> void:
	await reset_scene(true)
	for n in ["WalkerB", "WalkerC", "Turret1", "Turret2"]:
		check("%s aims diagonally" % n, (main.get_node("Enemies/" + n) as Enemy).can_aim_diagonally)
	for n in ["WalkerA", "ChaserD", "FlyerE"]:
		check("%s does not" % n, not (main.get_node("Enemies/" + n) as Enemy).can_aim_diagonally)
	var turret: Enemy = main.get_node("Enemies/Turret1")
	check("aim time is 0.3s", turret.diagonal_aim_time == 0.3)


func test_aim_sectors() -> void:
	# 纯几何：只看 aim_for() 对不同方位的判定（炮台射程 400，A 射程 220）。
	await reset_scene(true)
	var turret: Enemy = main.get_node("Enemies/Turret1")
	var walker_a: Enemy = main.get_node("Enemies/WalkerA")
	turret.set_physics_process(false)
	walker_a.set_physics_process(false)
	var dummy := Node2D.new()
	main.add_child(dummy)
	var cases := [
		[Vector2(-120, 0), Enemy.Aim.LEVEL, "same height"],
		[Vector2(-120, -30), Enemy.Aim.LEVEL, "15px higher (within the 20px tolerance)"],
		[Vector2(-120, -70), Enemy.Aim.DIAGONAL_UP, "30 degrees up"],
		[Vector2(-240, 240), Enemy.Aim.DIAGONAL_DOWN, "90 degrees down"],
		[Vector2(100, -160), Enemy.Aim.DIAGONAL_UP, "58 degrees up, other side"],
		[Vector2(-40, -120), -1, "72 degrees up (too steep)"],
		[Vector2(-300, -80), -1, "15 degrees but 40px up (neither level nor diagonal)"],
		[Vector2(-300, -300), -1, "45 degrees but 212px away (out of range)"],
	]
	for c in cases:
		dummy.global_position = turret.global_position + c[0]
		var got := turret.aim_for(dummy)
		check("turret, %s: %s" % [c[2], "none" if c[1] < 0 else Enemy.Aim.keys()[c[1]]], got == c[1], str(got))
	dummy.global_position = walker_a.global_position + Vector2(-120, -70)
	check("A never aims diagonally", walker_a.aim_for(dummy) == -1)
	dummy.free()


# ---------------------------------------------------------------- 巡逻兵

## 玩家站在 Platform1（单向，x 160..128，顶面 y=256）上，巡逻兵在右下方地面上，正好 90°。
func _player_on_platform1() -> void:
	player.global_position = Vector2(208, 240)
	player.velocity = Vector2.ZERO


func test_b_stops_and_fires_diagonally_up() -> void:
	var b := await _place("WalkerB", Vector2(274, 306))
	_player_on_platform1()
	var w := await _watch(b, 120)
	# 发现玩家的那一帧已经先走了一步（瞄准在移动之后判定），之后就站定。
	check("B stops walking to aim", w["moved"] < 2.0 and is_zero_approx(b.velocity.x), "moved %.1f" % w["moved"])
	check("B aims diagonally up", b.aim == Enemy.Aim.DIAGONAL_UP, str(b.aim))
	check("B fires diagonally up-left", _all_toward(w["shots"], Vector2(-DIAGONAL, -DIAGONAL)), str(w["shots"].map(func(s): return s["direction"])))
	check("B still fires in bursts", w["shots"].size() >= 2, str(w["shots"].size()))
	check("the gun points up-left", gun_direction(b).is_equal_approx(Vector2(-DIAGONAL, -DIAGONAL)), str(gun_direction(b)))


func test_a_burst_keeps_its_direction() -> void:
	# 水平连发打到一半玩家跳上斜上方的平台：剩下的子弹还是水平的，斜射要等瞄准时间过了才开始。
	seed(6)
	var b := await _place("WalkerB", Vector2(274, 306), true)
	player.global_position = Vector2(160, 304) # 正前方同一高度
	var shots := []
	var record := func() -> void: shots.append(b.last_shot_direction)
	b.shot_fired.connect(record)
	for i in 10:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		if not shots.is_empty():
			break
	check("a level burst started", shots.size() == 1 and shots[0].is_equal_approx(Vector2.LEFT), str(shots))
	_player_on_platform1()
	for i in 12: # 连发剩下的 1~2 颗在这段时间里打完，瞄准时间还没到
		player._invincible_timer = 1000.0
		await tree.physics_frame
	b.shot_fired.disconnect(record)
	check("the rest of the burst stays level", shots.size() >= 2 and shots.all(func(d): return d.is_equal_approx(Vector2.LEFT)), str(shots))


func test_diagonal_fire_waits_for_the_aim_time() -> void:
	var b := await _place("WalkerB", Vector2(274, 306))
	_player_on_platform1()
	var w := await _watch(b, 120)
	var first: int = w["shots"][0]["frame"] if not w["shots"].is_empty() else -1
	# 0.3 秒 = 18 帧；允许一两帧的判定延迟。
	check("the first diagonal shot comes after ~0.3s of aiming", first >= 17 and first <= 24, "frame %d" % first)


func test_diagonal_shots_hit_the_player() -> void:
	var b := await _place("WalkerB", Vector2(274, 306))
	_player_on_platform1()
	await _watch(b, 180, false)
	check("a player standing diagonally above gets hit", player.health < player.max_health, str(player.health))


func test_a_does_not_fire_diagonally() -> void:
	var a := await _place("WalkerA", Vector2(274, 306))
	_player_on_platform1()
	var w := await _watch(a, 120)
	check("A keeps walking", w["moved"] > 20.0, "moved %.1f" % w["moved"])
	check("A holds fire", w["shots"].is_empty(), str(w["shots"].size()))


func test_walker_resumes_patrol_after_the_player_leaves() -> void:
	var b := await _place("WalkerB", Vector2(274, 306))
	_player_on_platform1()
	await _watch(b, 80)
	check("B is aiming", b.is_aiming_diagonally())
	player.global_position = Vector2(1240, 304)
	var w := await _watch(b, 120)
	check("B goes back to level aim", not b.is_aiming_diagonally())
	check("and walks on at patrol speed", w["moved"] > 20.0, "moved %.1f" % w["moved"])
	check("the gun is level again", is_equal_approx(turning_gun(b).rotation, 0.0))


func test_walker_does_not_aim_diagonally_behind_it() -> void:
	# 巡逻兵只打正前方：玩家在斜后方时照常巡逻。
	var b := await _place("WalkerB", Vector2(142, 306)) # 朝左
	_player_on_platform1() # 玩家在它右上方，也就是身后
	var w := await _watch(b, 80)
	check("no diagonal aim at a player behind", w["shots"].is_empty() and not b.is_aiming_diagonally())


func test_c_fires_down_at_a_prone_player() -> void:
	# C 站在 Platform6（x 1000..548，顶面 y=184）上，玩家趴在左下方地面。子弹固定走 90°：
	# 出膛点 (1028, 176)，要到趴下身体的高度（y≈316）得往左 140px，所以玩家放在 x=888。
	# （放在正好 90° 的 x=914 反而打不中：那条线经过的是站立身体的高度，从趴着的玩家头顶掠过。）
	var c := await _place("WalkerC", Vector2(1048, 170), true)
	player.global_position = Vector2(888, 304)
	player.velocity = Vector2.ZERO
	Input.action_press("crouch")
	# 先无敌观察 1.5 秒：中弹会被击退到空中、自动站起来，C 也就跟着站起来——只看最后一帧会漏掉它中途趴下过，所以逐帧看。
	var shots := []
	var record := func() -> void: shots.append(c.last_shot_direction)
	c.shot_fired.connect(record)
	var ever_prone := false
	for i in 90:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		ever_prone = ever_prone or c.is_prone
	c.shot_fired.disconnect(record)
	check("C aims diagonally down", c.aim == Enemy.Aim.DIAGONAL_DOWN, str(c.aim))
	check("C fires down-left", not shots.is_empty() and shots.all(func(d): return d.is_equal_approx(Vector2(-DIAGONAL, DIAGONAL))), str(shots))
	check("C never lies down while firing down (it only lies down level with the player)", not ever_prone and not c.is_prone)
	# 再关掉无敌等下一发（C 每 4.4 秒一发，子弹飞过去还要约 0.7 秒）：从上面斜着打下来，趴着也躲不掉。
	player._invincible_timer = 0.0
	for i in 180:
		await tree.physics_frame
		if player.health < player.max_health:
			break
	check("lying down does not dodge shots from above", player.health < player.max_health, str(player.health))


# ---------------------------------------------------------------- 炮台

func test_turret_fires_diagonally_up() -> void:
	# 炮台在地面，玩家站在 Platform5（x 840..468，顶面 y=248）上，在它左上方 90°。
	var turret := await _place("Turret1", Vector2(1000, 306))
	player.global_position = Vector2(926, 232)
	player.velocity = Vector2.ZERO
	var w := await _watch(turret, 180, false)
	check("the turret aims diagonally up", turret.aim == Enemy.Aim.DIAGONAL_UP, str(turret.aim))
	check("it fires up-left", _all_toward(w["shots"], Vector2(-DIAGONAL, -DIAGONAL)), str(w["shots"].map(func(s): return s["direction"])))
	check("the player on the platform gets hit", player.health < player.max_health, str(player.health))
	check("the barrel points up-left", gun_direction(turret).is_equal_approx(Vector2(-DIAGONAL, -DIAGONAL)), str(gun_direction(turret)))


func test_turret_turns_for_a_diagonal_target_behind_it() -> void:
	var turret := await _place("Turret1", Vector2(840, 306))
	# 玩家在它右上方（它原本朝左）：炮台会转身。
	player.global_position = Vector2(926, 232)
	player.velocity = Vector2.ZERO
	var w := await _watch(turret, 120)
	check("the turret turns to face the player", turret.facing == 1)
	check("and fires up-right", _all_toward(w["shots"], Vector2(DIAGONAL, -DIAGONAL)), str(w["shots"].map(func(s): return s["direction"])))
