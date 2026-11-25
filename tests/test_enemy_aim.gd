extends GameTest
## Enemy diagonal fire: when the player is diagonally above / below (45.0°~135.0° from level, within range in a straight line), B, C and the turret
## stop walking (patrollers) or turn (turret), aim for 0.3 seconds and fire at 45°; A does not. They go back to normal once the player is level again or gone.

const DIAGONAL := 0.7071


## Keep only one enemy, put at pos facing left (patrollers patrol as usual unless still = true).
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
	# Park the player outside every range first: otherwise enemies start firing level bursts during setup, muddling the observation of diagonal shots.
	player.global_position = Vector2(1240.0 if pos.x < 640.0 else 40.0, 304)
	await frames(5)
	return enemy


## Watch for some frames: record each bullet's direction and the frame it was fired on, plus how far the enemy walked horizontally.
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


## Which way the gun barrel (placeholder art) really points: the barrel is laid out "facing right" and mirrored as a whole when facing left, so local +x points at the body.
func gun_direction(e: Enemy) -> Vector2:
	var gun := turning_gun(e)
	return (Vector2.RIGHT if e.facing > 0 else Vector2.LEFT).rotated(gun.rotation)


func _all_toward(shots: Array, expected: Vector2) -> bool:
	return not shots.is_empty() and shots.all(func(s): return s["direction"].is_equal_approx(expected))


# ---------------------------------------------------------------- Configuration and checks

func test_which_enemies_aim_diagonally() -> void:
	await reset_scene(true)
	for n in ["WalkerB", "WalkerC", "Turret1", "Turret2"]:
		check("%s aims diagonally" % n, (main.get_node("Enemies/" + n) as Enemy).can_aim_diagonally)
	for n in ["WalkerA", "ChaserD", "FlyerE"]:
		check("%s does not" % n, not (main.get_node("Enemies/" + n) as Enemy).can_aim_diagonally)
	var turret: Enemy = main.get_node("Enemies/Turret1")
	check("aim time is 0.3s", turret.diagonal_aim_time == 0.3)


func test_aim_sectors() -> void:
	# Pure geometry: only look at aim_for()'s verdict for different positions (turret range 400, A range 220).
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


# ---------------------------------------------------------------- Patrollers

## The player stands on Platform1 (one-way, x 160..128, top y=256), the patroller on the ground below to the right, exactly 90°.
func _player_on_platform1() -> void:
	player.global_position = Vector2(208, 240)
	player.velocity = Vector2.ZERO


func test_b_stops_and_fires_diagonally_up() -> void:
	var b := await _place("WalkerB", Vector2(274, 304))
	_player_on_platform1()
	var w := await _watch(b, 120)
	# On the frame it spots the player it has already taken a step (aiming is checked after moving), then it stands still.
	check("B stops walking to aim", w["moved"] < 2.0 and is_zero_approx(b.velocity.x), "moved %.1f" % w["moved"])
	check("B aims diagonally up", b.aim == Enemy.Aim.DIAGONAL_UP, str(b.aim))
	check("B fires diagonally up-left", _all_toward(w["shots"], Vector2(-DIAGONAL, -DIAGONAL)), str(w["shots"].map(func(s): return s["direction"])))
	check("B still fires in bursts", w["shots"].size() >= 2, str(w["shots"].size()))
	check("the gun points up-left", gun_direction(b).is_equal_approx(Vector2(-DIAGONAL, -DIAGONAL)), str(gun_direction(b)))


func test_a_burst_keeps_its_direction() -> void:
	# Halfway through a level burst the player jumps onto a platform diagonally above: the remaining shots stay level, and diagonal shots only start after the aiming time.
	seed(6)
	var b := await _place("WalkerB", Vector2(274, 304), true)
	player.global_position = Vector2(160, 304) # Straight ahead at the same height
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
	for i in 12: # The remaining 1~2 shots of the burst finish during this time, before the aiming time is up
		player._invincible_timer = 1000.0
		await tree.physics_frame
	b.shot_fired.disconnect(record)
	check("the rest of the burst stays level", shots.size() >= 2 and shots.all(func(d): return d.is_equal_approx(Vector2.LEFT)), str(shots))


func test_diagonal_fire_waits_for_the_aim_time() -> void:
	var b := await _place("WalkerB", Vector2(274, 304))
	_player_on_platform1()
	var w := await _watch(b, 120)
	var first: int = w["shots"][0]["frame"] if not w["shots"].is_empty() else -1
	# 0.3 seconds = 18 frames; a frame or two of check delay is allowed.
	check("the first diagonal shot comes after ~0.3s of aiming", first >= 17 and first <= 24, "frame %d" % first)


func test_diagonal_shots_hit_the_player() -> void:
	var b := await _place("WalkerB", Vector2(274, 304))
	_player_on_platform1()
	await _watch(b, 180, false)
	check("a player standing diagonally above gets hit", player.health < player.max_health, str(player.health))


func test_a_does_not_fire_diagonally() -> void:
	var a := await _place("WalkerA", Vector2(274, 304))
	_player_on_platform1()
	var w := await _watch(a, 120)
	check("A keeps walking", w["moved"] > 20.0, "moved %.1f" % w["moved"])
	check("A holds fire", w["shots"].is_empty(), str(w["shots"].size()))


func test_walker_resumes_patrol_after_the_player_leaves() -> void:
	var b := await _place("WalkerB", Vector2(274, 304))
	_player_on_platform1()
	await _watch(b, 80)
	check("B is aiming", b.is_aiming_diagonally())
	player.global_position = Vector2(1240, 304)
	var w := await _watch(b, 120)
	check("B goes back to level aim", not b.is_aiming_diagonally())
	check("and walks on at patrol speed", w["moved"] > 20.0, "moved %.1f" % w["moved"])
	check("the gun is level again", is_equal_approx(turning_gun(b).rotation, 0.0))


func test_walker_does_not_aim_diagonally_behind_it() -> void:
	# Patrollers only fire straight ahead: with the player diagonally behind, it patrols as usual.
	var b := await _place("WalkerB", Vector2(142, 304)) # Facing left
	_player_on_platform1() # The player is above to its right, i.e. behind it
	var w := await _watch(b, 80)
	check("no diagonal aim at a player behind", w["shots"].is_empty() and not b.is_aiming_diagonally())


func test_c_fires_down_at_a_prone_player() -> void:
	# C stands on Platform6 (x 1000..548, top y=184), the player prone on the ground below to the left. Bullets always travel at 90°:
	# from the muzzle at (1028, 176), reaching the height of a prone body (y≈316) takes 140px to the left, so the player is placed at x=888.
	# (Placed exactly at 90°, x=914, it would miss: that line passes at the height of a standing body, skimming over the prone player.)
	var c := await _place("WalkerC", Vector2(1048, 168), true)
	player.global_position = Vector2(888, 304)
	player.velocity = Vector2.ZERO
	Input.action_press("crouch")
	# First watch invincible for 1.5 seconds: being hit knocks the player into the air and they stand up automatically, and C stands up with them — the last frame alone would miss that it lay down midway, so watch every frame.
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
	# Then turn invincibility off and wait for the next shot (C fires every 4.4 seconds, plus about 0.7 seconds of flight): coming diagonally from above, prone does not dodge it.
	player._invincible_timer = 0.0
	for i in 180:
		await tree.physics_frame
		if player.health < player.max_health:
			break
	check("lying down does not dodge shots from above", player.health < player.max_health, str(player.health))


# ---------------------------------------------------------------- Turret

func test_turret_fires_diagonally_up() -> void:
	# The turret on the ground, the player on Platform5 (x 840..468, top y=248), up and to its left at 90°.
	var turret := await _place("Turret1", Vector2(1000, 304))
	player.global_position = Vector2(926, 232)
	player.velocity = Vector2.ZERO
	var w := await _watch(turret, 180, false)
	check("the turret aims diagonally up", turret.aim == Enemy.Aim.DIAGONAL_UP, str(turret.aim))
	check("it fires up-left", _all_toward(w["shots"], Vector2(-DIAGONAL, -DIAGONAL)), str(w["shots"].map(func(s): return s["direction"])))
	check("the player on the platform gets hit", player.health < player.max_health, str(player.health))
	check("the barrel points up-left", gun_direction(turret).is_equal_approx(Vector2(-DIAGONAL, -DIAGONAL)), str(gun_direction(turret)))


func test_turret_turns_for_a_diagonal_target_behind_it() -> void:
	var turret := await _place("Turret1", Vector2(840, 304))
	# The player up and to its right (it was facing left): the turret turns around.
	player.global_position = Vector2(926, 232)
	player.velocity = Vector2.ZERO
	var w := await _watch(turret, 120)
	check("the turret turns to face the player", turret.facing == 1)
	check("and fires up-right", _all_toward(w["shots"], Vector2(DIAGONAL, -DIAGONAL)), str(w["shots"].map(func(s): return s["direction"])))
