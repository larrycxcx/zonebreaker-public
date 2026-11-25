extends GameTest
## Enemy behaviour, damage checks, player health and invincibility frames. This suite needs the enemies, so every case uses `reset_scene(true)`.


func test_level_setup() -> void:
	await reset_scene(true)
	check("9 enemies in the level (8 normal + 1 boss)", enemies().size() == 9, str(main.get_node("Enemies").get_child_count()))
	check("player starts at full health: three hits", player.health == 3 * HIT and player.max_health == 3 * HIT, str(player.health))
	check("hud health bar starts full", (main.get_node("HUD/HealthBar/Fill") as ColorRect).size.x == (main.get_node("HUD/HealthBar") as ColorRect).size.x)


func test_enemies_stand_where_placed() -> void:
	await reset_scene(true)
	await frames(40)
	var walker1: EnemyWalker = main.get_node("Enemies/WalkerA")
	var walker2: EnemyWalker = main.get_node("Enemies/WalkerB")
	var turret: EnemyTurret = main.get_node("Enemies/Turret1")
	check("ground walker stands on the ground", walker1.is_on_floor() and absf(walker1.global_position.y - 306.0) < 4.0, str(walker1.global_position))
	check("platform walker stands on its platform", walker2.is_on_floor() and absf(walker2.global_position.y - 178.0) < 4.0, str(walker2.global_position))
	check("turret stands on the ground", turret.is_on_floor(), str(turret.global_position))


## A patroller **stops walking once a fight starts**, so cases testing the patrol itself have to send the player away first:
## far away and off screen, so it has nobody to fire back at.
func _send_player_away() -> void:
	player.global_position = Vector2(1200, 304)
	player.velocity = Vector2.ZERO
	await frames(2)
	snap_camera()


func test_walker_patrols() -> void:
	await reset_scene(true)
	keep_only_enemies(["WalkerA"])
	await _send_player_away()
	await frames(40)
	var walker: EnemyWalker = main.get_node("Enemies/WalkerA")
	var start_x := walker.global_position.x
	await frames(60)
	check("walker moves along the ground", absf(walker.global_position.x - start_x) > 20.0, "%.1f -> %.1f" % [start_x, walker.global_position.x])


func test_a_walker_stands_and_fights_instead_of_walking_on() -> void:
	# Once engaged it stands and fires; only when the player leaves its sight does it resume patrolling.
	await reset_scene(true)
	keep_only_enemies(["WalkerA"])
	var walker: EnemyWalker = main.get_node("Enemies/WalkerA")
	await _send_player_away()
	await frames(30)
	var roaming := walker.global_position.x
	await frames(40)
	check("setup: it really is patrolling", absf(walker.global_position.x - roaming) > 20.0,
		"%.1f -> %.1f" % [roaming, walker.global_position.x])
	# Get right in front of it
	player.global_position = Vector2(walker.global_position.x + 160.0 * walker.facing, 304)
	player.velocity = Vector2.ZERO
	player.health = 999
	await frames(2)
	snap_camera()
	await frames(20)
	var engaged := walker.global_position.x
	await frames(60)
	check("it stops where it is", absf(walker.global_position.x - engaged) < 1.0,
		"%.1f -> %.1f" % [engaged, walker.global_position.x])
	check("and keeps shooting", bullets(16).size() > 0, str(bullets(16).size()))
	await _send_player_away()
	await frames(20)
	var freed := walker.global_position.x
	await frames(60)
	check("once the player is gone it walks on again", absf(walker.global_position.x - freed) > 20.0,
		"%.1f -> %.1f" % [freed, walker.global_position.x])


func test_walker_turns_at_ledges() -> void:
	await reset_scene(true)
	await frames(40)
	# Platform4: x 640..384. The patroller must turn around at the edge, not walk off.
	var walker: EnemyWalker = main.get_node("Enemies/WalkerB")
	var fell := false
	for i in 300:
		await tree.physics_frame
		if walker.global_position.y > 200.0:
			fell = true
			break
	check("walker never walks off its platform", not fell, str(walker.global_position))
	check("walker stays within the platform", walker.global_position.x > 636.0 and walker.global_position.x < 772.0, str(walker.global_position.x))


func test_walker_turns_at_the_crawl_block() -> void:
	await reset_scene(true)
	# The crawl passage (x 592..704, 30px of clearance) is lower than a patroller (32px tall); it has to turn around instead of getting stuck pushing against it.
	var walker: EnemyWalker = main.get_node("Enemies/WalkerA")
	walker.global_position = Vector2(540, 304)
	walker.facing = 1
	walker._apply_facing()
	var turned := false
	for i in 200:
		await tree.physics_frame
		if walker.facing == -1:
			turned = true
			break
	check("walker turns around instead of getting stuck", turned, str(walker.global_position))


func test_bullets_kill_the_walker() -> void:
	await reset_scene(true)
	keep_only_enemies(["WalkerA"])
	await frames(30)
	var walker: EnemyWalker = main.get_node("Enemies/WalkerA")
	check("walker takes two shots", walker.max_health == 2 * SHOT and walker.health == 2 * SHOT)

	walker.take_damage(SHOT)
	check("one shot does not kill a walker", is_instance_valid(walker) and walker.health == SHOT, str(walker.health))
	await frames(2)

	# GDScript lambdas capture local variables by value, so a reference type like an array collects the signals.
	var death_signals := []
	walker.died.connect(func(): death_signals.append(true))

	player.global_position = walker.global_position + Vector2(-80, 0)
	player.velocity = Vector2.ZERO
	player.facing = 1
	player._visual.scale.x = 1
	await frames(2)
	player.current_slot().cooldown_left = 0.0
	player._shoot(Vector2(player.facing, 0))
	for i in 30:
		await tree.physics_frame
		if not is_instance_valid(walker):
			break
	check("the next bullet kills it", death_signals.size() == 1 and not is_instance_valid(walker), str(death_signals))


func test_collision_masks_keep_sides_apart() -> void:
	await reset_scene(true)
	var player_bullet: Bullet = load("res://scenes/bullet.tscn").instantiate()
	var enemy_bullet: Bullet = load("res://scenes/enemy_bullet.tscn").instantiate()
	check("player bullets ignore the player", (player_bullet.collision_mask & 2) == 0)
	check("player bullets hit enemies", (player_bullet.collision_mask & 8) != 0)
	check("enemy bullets ignore enemies", (enemy_bullet.collision_mask & 8) == 0)
	check("enemy bullets hit the player", (enemy_bullet.collision_mask & 2) != 0)
	player_bullet.free()
	enemy_bullet.free()


func test_turret_only_fires_in_range() -> void:
	await reset_scene(true)
	keep_only_enemies(["Turret1"])
	await frames(30)
	var turret: EnemyTurret = main.get_node("Enemies/Turret1")

	player.global_position = Vector2(64, 304) # Away from the turret
	var seen_while_far := 0
	for i in 90:
		await tree.physics_frame
		seen_while_far += bullets(16).size()
	check("turret holds fire while the player is far away", seen_while_far == 0, str(seen_while_far))

	player.global_position = turret.global_position + Vector2(-200, 0)
	player.velocity = Vector2.ZERO
	var directions := {}
	for i in 120:
		await tree.physics_frame
		for bullet in bullets(16):
			directions[bullet.direction] = true
	check("turret fires once the player is in range", directions.size() > 0, str(directions.keys()))
	check("turret bullets fly toward the player", directions.keys() == [Vector2.LEFT], str(directions.keys()))
	check("turret bullets hurt the player", player.health < player.max_health, str(player.health))
	check("turret faces the player", turret.facing == -1, str(turret.facing))


func test_turret_flips_to_face_the_player() -> void:
	await reset_scene(true)
	keep_only_enemies(["Turret1"])
	await frames(30)
	var turret: EnemyTurret = main.get_node("Enemies/Turret1")
	player.global_position = turret.global_position + Vector2(90, 0)
	player.velocity = Vector2.ZERO
	await frames(10)
	check("turret turns to the other side", turret.facing == 1, str(turret.facing))


func test_walker_shoots_at_the_player() -> void:
	await reset_scene(true)
	keep_only_enemies(["WalkerA"])
	var walker: EnemyWalker = main.get_node("Enemies/WalkerA")
	await frames(20)

	# Stand right in front of the patroller at the same height, within range.
	walker.global_position = Vector2(400, 304)
	walker.facing = -1
	walker._apply_facing()
	player.global_position = Vector2(280, 304)
	player.velocity = Vector2.ZERO

	var directions := {}
	for i in 160:
		await tree.physics_frame
		for bullet in bullets(16):
			directions[bullet.direction] = true
	check("walker fires at the player", directions.size() > 0, str(directions.keys()))
	check("walker bullets fly toward the player", directions.keys() == [Vector2.LEFT], str(directions.keys()))
	check("walker bullets hurt the player", player.health < player.max_health, str(player.health))


func test_walker_does_not_shoot_backwards() -> void:
	await reset_scene(true)
	keep_only_enemies(["WalkerA"])
	var walker: EnemyWalker = main.get_node("Enemies/WalkerA")
	await frames(20)

	# The player behind it: a patroller must not turn back to aim; turning is decided by the patrol alone.
	walker.global_position = Vector2(400, 304)
	walker.facing = -1
	walker._apply_facing()
	player.global_position = Vector2(520, 304)
	player.velocity = Vector2.ZERO

	var shots := 0
	for i in 100:
		await tree.physics_frame
		# Keep it walking left, so it does not turn around midway and bring the player in front of it.
		walker.facing = -1
		shots += bullets(16).size()
	check("walker holds fire when the player is behind it", shots == 0, str(shots))
	check("walker keeps facing away", walker.facing == -1 and player.health == player.max_health, str(player.health))


func test_walker_and_turret_level_shots_hit_standing_and_miss_prone() -> void:
	await reset_scene(true)
	keep_only_enemies(["WalkerA", "Turret1"])
	var walker: EnemyWalker = main.get_node("Enemies/WalkerA")
	var turret: EnemyTurret = main.get_node("Enemies/Turret1")
	await frames(30)

	# Two kinds of enemy standing on the same ground: world positions only have to agree to a sub-pixel — the patroller is moving, and CharacterBody2D's safe margin (0.08 by default)
	# makes it hover about 0.07px above the ground, while the stationary turret sits flush.
	var body_gap := absf(walker.global_position.y - turret.global_position.y)
	check("both rest on the ground within a sub-pixel", body_gap < 0.5, "%.3f px" % body_gap)

	# Their muzzle heights need not be the same (the patroller holds its gun at the chest, the turret's barrel is 4px lower per the art),
	# but the level shots fired standing must all fall in the same band: hitting a standing player, flying over a prone one.
	# Looking at the markers is not enough; it has to look at bullets really fired.
	walker.facing = -1
	turret.facing = -1
	walker.try_shoot(1998.0, player)
	turret.try_shoot(1998.0, player)
	await frames(1)
	var shots := bullets(16)
	check("both actually fired", shots.size() == 2, str(shots.size()))
	var ground := turret.global_position.y + 16.0
	for shot: Node2D in shots:
		var half := ((shot.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D).size.y / 2.0
		var bottom := ground - (shot.global_position.y + half)
		var top := ground - (shot.global_position.y - half)
		check("a level shot passes over a prone player (bottom %.1f px above ground)" % bottom, bottom > Player.CROUCH_HEIGHT)
		check("a level shot still hits a standing player (top %.1f px above ground)" % top, top < Player.STAND_HEIGHT)


func test_enemy_bullets_do_not_hurt_other_enemies() -> void:
	await reset_scene(true)
	keep_only_enemies(["WalkerA", "WalkerB"])
	var shooter: EnemyWalker = main.get_node("Enemies/WalkerA")
	var victim: EnemyWalker = main.get_node("Enemies/WalkerB")
	await frames(20)

	# Put another patroller right in front of the muzzle and move the player far away so it does not interfere.
	player.global_position = Vector2(1200, 304)
	shooter.global_position = Vector2(480, 304)
	shooter.facing = -1
	shooter._apply_facing()
	victim.global_position = Vector2(400, 304)
	victim.facing = -1
	victim._apply_facing()
	victim.move_speed = 0.0
	shooter.move_speed = 0.0
	await frames(2)

	var victim_health := victim.health
	var deaths := []
	victim.died.connect(func(): deaths.append(true))
	shooter.try_shoot(1998.0, player)
	await frames(2)
	check("a bullet is in the air", bullets(16).size() == 1, str(bullets(16).size()))

	# Frames for the bullet to pass the ally: 80px / (300px/s / 60) = 16 frames, with plenty of margin.
	await frames(40)
	check("the other enemy takes no damage", victim.health == victim_health and deaths.is_empty(), str(victim.health))
	check("it is still alive", is_instance_valid(victim) and not victim.is_queued_for_deletion())


## Set up an enemy: standing at pos facing left, patrollers no longer walking.
func _place_enemy(enemy: Enemy, pos: Vector2) -> void:
	enemy.global_position = pos
	enemy.facing = -1
	enemy._visual.scale.x = -1
	if enemy is EnemyWalker:
		(enemy as EnemyWalker)._apply_facing()


## Put C at x=1000 standing still facing left (not patrolling), with the player 140px in front of it.
func _setup_c_facing_player() -> EnemyWalker:
	await reset_scene(true)
	keep_only_enemies(["WalkerC"])
	var c: EnemyWalker = main.get_node("Enemies/WalkerC")
	await frames(10)
	_place_enemy(c, Vector2(1000, 304))
	c.move_speed = 0.0
	player.global_position = Vector2(860, 304)
	player.velocity = Vector2.ZERO
	await frames(10)
	return c


func test_c_goes_prone_when_the_player_does() -> void:
	var c := await _setup_c_facing_player()
	check("C stands while the player stands", not c.is_prone)

	Input.action_press("crouch")
	await frames(15) # 0.25 seconds, still within the 0.4-second reaction time
	check("C waits a moment before going prone", not c.is_prone)
	await frames(15)
	check("C goes prone after the reaction time", c.is_prone)
	var shape_height := (c._shape.shape as RectangleShape2D).size.y
	check("prone C is as low as a prone player", shape_height == Enemy.PRONE_HEIGHT, str(shape_height))
	check("prone C keeps its feet on the ground", c.is_on_floor(), str(c.global_position))
	# The muzzle is computed from the collision shape centre, so lowering the shape when prone brings it down to the floor by itself (no longer relying on the placeholder being squashed)
	var prone_muzzle := c.level_muzzle_position().y
	check("prone muzzle drops to skim the ground", prone_muzzle > 312.0 and prone_muzzle < 318.0, "y=%.1f" % prone_muzzle)

	Input.action_release("crouch")
	await frames(2)
	check("C stands up as soon as the player does", not c.is_prone and (c._shape.shape as RectangleShape2D).size.y == 32.0)


func test_turret_never_lies_down() -> void:
	await reset_scene(true)
	keep_only_enemies(["Turret1"])
	var turret: EnemyTurret = main.get_node("Enemies/Turret1")
	await frames(10)
	_place_enemy(turret, Vector2(1000, 304))
	player.global_position = Vector2(860, 304)
	player.velocity = Vector2.ZERO
	check("turrets cannot go prone", not turret.can_go_prone)
	var shots := [0]
	turret.shot_fired.connect(func(): shots[0] += 1)
	Input.action_press("crouch")
	var ever_prone := false
	for i in 150:
		await tree.physics_frame
		ever_prone = ever_prone or turret.is_prone
	check("a turret stays upright when the player lies down", not ever_prone)
	# So lying prone at the same height dodges the turret completely: its level shots fired standing fly over the prone player.
	check("the turret keeps firing", shots[0] >= 2, str(shots[0]))
	check("and every shot flies over the prone player", player.health == player.max_health, str(player.health))


func test_prone_enemy_hits_a_prone_player() -> void:
	var c := await _setup_c_facing_player()
	Input.action_press("crouch")
	# The first shot is fired before C goes prone and flies overhead; then C lies down and the next shot comes along the floor.
	for i in 180:
		await tree.physics_frame
		if player.health < player.max_health:
			break
	check("lying down no longer dodges a prone enemy", player.health < player.max_health, str(player.health))
	check("the hit came while both were prone", player.is_crouching and c.is_prone)


func test_type_c_stops_and_lies_down_to_shoot() -> void:
	await reset_scene(true)
	keep_only_enemies(["WalkerC"])
	var walker: EnemyWalker = main.get_node("Enemies/WalkerC")
	await frames(10)
	_place_enemy(walker, Vector2(500, 304))
	player.global_position = Vector2(360, 304) # In front of the patroller (to the left)
	player.velocity = Vector2.ZERO
	Input.action_press("crouch")
	await frames(40)
	check("walker lies down when the player ahead does", walker.is_prone)
	var x_prone := walker.global_position.x
	await frames(30)
	check("walker stays put while prone", absf(walker.global_position.x - x_prone) < 0.5, "%.2f -> %.2f" % [x_prone, walker.global_position.x])

	Input.action_release("crouch")
	await frames(30)
	check("walker gets up when the player does", not walker.is_prone)
	# It stood up, but the player is still right in front of it, so it **stands and keeps firing** instead of patrolling on
	var x_up := walker.global_position.x
	await frames(30)
	check("but it holds its ground while the player is still in front",
		absf(walker.global_position.x - x_up) < 0.5, "%.2f -> %.2f" % [x_up, walker.global_position.x])
	await _send_player_away()
	await frames(20)
	var x_free := walker.global_position.x
	await frames(60)
	check("walker resumes its patrol once the player is gone",
		absf(walker.global_position.x - x_free) > 10.0, "%.2f -> %.2f" % [x_free, walker.global_position.x])


func test_type_c_ignores_a_prone_player_behind_it() -> void:
	await reset_scene(true)
	keep_only_enemies(["WalkerC"])
	var walker: EnemyWalker = main.get_node("Enemies/WalkerC")
	await frames(10)
	_place_enemy(walker, Vector2(400, 304))
	player.global_position = Vector2(500, 304) # Behind it (to the right)
	player.velocity = Vector2.ZERO
	Input.action_press("crouch")
	var ever_prone := false
	for i in 40:
		await tree.physics_frame
		ever_prone = ever_prone or walker.is_prone
		walker.facing = -1 # Do not let it turn around midway and bring the player in front
	check("walker does not lie down for a player behind it", not ever_prone)


func test_standing_shots_fly_over_a_prone_enemy() -> void:
	var c := await _setup_c_facing_player()
	# Enemies do not lie down on their own while the player stands, so make it lie down directly and freeze the AI, testing only the height relationship.
	c.set_prone(true)
	c.set_physics_process(false)
	player.global_position = Vector2(880, 304)
	player.velocity = Vector2.ZERO
	player.facing = 1
	player._visual.scale.x = 1
	await frames(3)
	player.current_slot().cooldown_left = 0.0
	player._shoot(Vector2.RIGHT)
	await frames(40)
	check("a standing shot flies over a prone enemy", c.health == c.max_health, str(c.health))

	# Control group: the same shot hits once the enemy stands up, proving it was dodged by height and not that nothing was fired.
	# (The player cannot fire while prone, so the control group has the enemy stand up instead.)
	c.set_prone(false)
	await frames(3)
	player.current_slot().cooldown_left = 0.0
	player._shoot(Vector2.RIGHT)
	await frames(40)
	check("the same shot hits it once it stands up", not is_instance_valid(c) or c.health < c.max_health, str(c.health) if is_instance_valid(c) else "dead")


func test_player_invincibility_frames() -> void:
	# This one only cares about the player and the HUD; clear the enemies so nobody takes a sudden shot midway.
	await reset_scene()
	await frames(30)
	var health_events := []
	player.health_changed.connect(func(health, _max_health): health_events.append(health))

	player.take_damage(HIT, player.global_position + Vector2(40, 0))
	check("player loses one hit", player.health == 2 * HIT, str(player.health))
	check("health_changed fires", health_events == [2 * HIT], str(health_events))
	check("knockback pushes away from the source", player.velocity.x < 0.0 and player.velocity.y < 0.0, str(player.velocity))
	var bar := main.get_node("HUD/HealthBar") as ColorRect
	check("hud bar drops by a third", absf((bar.get_node("Fill") as ColorRect).size.x - bar.size.x * 2.0 / 3.0) <= 1.0,
		str((bar.get_node("Fill") as ColorRect).size.x))

	player.take_damage(HIT, player.global_position)
	check("further damage is blocked while invincible", player.health == 2 * HIT, str(player.health))

	await frames(70) # 1 second of invincibility = 60 frames
	check("blinking stops afterwards", is_equal_approx(player._visual.modulate.a, 1.0), str(player._visual.modulate.a))
	player.take_damage(HIT, player.global_position)
	check("damage lands again once invincibility ends", player.health == HIT, str(player.health))


func test_touching_an_enemy_hurts() -> void:
	await reset_scene(true)
	keep_only_enemies(["WalkerA"])
	await frames(30)
	var walker: EnemyWalker = main.get_node("Enemies/WalkerA")
	player.global_position = walker.global_position
	player.velocity = Vector2.ZERO
	await frames(4)
	check("standing on an enemy costs one hit", player.health == 2 * HIT, str(player.health))


func test_player_death() -> void:
	await reset_scene()
	await frames(30)
	var death_signals := []
	player.died.connect(func(): death_signals.append(true))

	for i in 3:
		player._invincible_timer = 0.0
		player.take_damage(HIT, player.global_position + Vector2(40, 0))
		await frames(2)
	check("player dies at zero health", death_signals.size() == 1 and player.health == 0, str(player.health))
	# The "GAME OVER" and "retry / main menu" screen belongs to `DeathScreen`; its tests are in test_menus.gd

	var x_before := player.global_position.x
	Input.action_press("move_right")
	await frames(30)
	Input.action_release("move_right")
	check("a dead player ignores movement input", absf(player.global_position.x - x_before) < 24.0, str(player.global_position.x - x_before))

	Input.action_press("shoot")
	await frames(20)
	Input.action_release("shoot")
	check("a dead player cannot shoot", bullets(4).size() == 0, str(bullets(4).size()))


# ---------------------------------------------------------------- Vision parity: enemies the player can see must see the player

## The player hugs the left of the stage (the camera rests on the left limit, view = x 0..640), the enemy is at x facing left, with its cooldown reset.
func _face_off(enemy_name: String, x: float) -> Enemy:
	await reset_scene(true)
	keep_only_enemies([enemy_name])
	var enemy: Enemy = main.get_node("Enemies/" + enemy_name)
	player.global_position = Vector2(100, 304)
	player.velocity = Vector2.ZERO
	player.health = 999
	var y := 88.0 if enemy is EnemyFlyer else 304.0
	if enemy is EnemyFlyer:
		(enemy as EnemyFlyer).set_anchor(Vector2(x, y))
		(enemy as EnemyFlyer).is_following = false
		(enemy as EnemyFlyer).move_speed = 0.0
	else:
		enemy.global_position = Vector2(x, y)
		enemy.velocity = Vector2.ZERO
	enemy.facing = -1
	enemy._apply_visual_facing()
	if enemy is EnemyWalker:
		(enemy as EnemyWalker).move_speed = 0.0
	enemy._fire_timer = 0.0
	enemy._burst_left = 0
	if enemy is EnemyGrenadier:
		(enemy as EnemyGrenadier)._throw_timer = 0.0
	if enemy is EnemyChaser:
		(enemy as EnemyChaser)._memory_left = 0.0
		(enemy as EnemyChaser).is_chasing = false
	for grenade in tree.get_nodes_in_group(Grenade.GROUP):
		grenade.free()
	for shot in bullets(16):
		shot.free()
	snap_camera()
	return enemy


## Did this enemy react to the player within frame_count frames (firing, throwing, charging, following)?
func _reacts(enemy: Enemy, frame_count := 90) -> bool:
	var fired := [false]
	enemy.shot_fired.connect(func() -> void: fired[0] = true)
	for i in frame_count:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		if not is_instance_valid(enemy):
			return false
		if fired[0] or not tree.get_nodes_in_group(Grenade.GROUP).is_empty():
			return true
		if enemy is EnemyChaser and (enemy as EnemyChaser).is_chasing:
			return true
		if enemy is EnemyFlyer and (enemy as EnemyFlyer).is_following:
			return true
	return false


func test_every_enemy_on_screen_reacts_to_the_player() -> void:
	# 480px: further than the detection range of A/B (220), C and the turret (400), D (240) and F (300), but still on screen —
	# the player used to be able to kill them from the screen before they reacted
	for enemy_name in ["WalkerA", "WalkerB", "WalkerC", "Turret1", "ChaserD", "FlyerE", "WalkerF"]:
		var enemy := await _face_off(enemy_name, 580.0)
		check("setup: %s is on screen, beyond its detect range" % enemy_name,
			enemy.is_partly_on_screen() and 480.0 > enemy.detect_range, str(enemy.detect_range))
		check("%s reacts to a player it is on screen with" % enemy_name, await _reacts(enemy))


func test_enemies_off_screen_and_out_of_range_stay_unaware() -> void:
	# Control: off screen and beyond the detection range they still cannot spot you (or they would start firing from across the whole stage)
	for enemy_name in ["WalkerA", "WalkerB", "WalkerC", "Turret1", "ChaserD", "FlyerE", "WalkerF"]:
		var enemy := await _face_off(enemy_name, 1000.0)
		check("setup: %s is off screen and out of range" % enemy_name, not enemy.is_partly_on_screen() and 900.0 > enemy.detect_range)
		check("%s does not react" % enemy_name, not await _reacts(enemy, 60))
