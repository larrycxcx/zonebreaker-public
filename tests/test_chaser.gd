extends GameTest
## Enemy D (charger): does not shoot or go prone, patrols at normal speed, and when it sees the player within 240px charges at 150 (slower than the player's walk),
## hurts by contact, jumps walls and platforms, walls block its sight, and it gives up after losing the player.

const GROUND_ENEMY_Y := 306.0


## Keep only D, standing on the ground at x facing facing; the player waits far away (out of range) first.
func _setup_chaser(x: float, facing: int, keep_walls := false) -> EnemyChaser:
	await reset_scene(true, keep_walls)
	keep_only_enemies(["ChaserD"])
	var d: EnemyChaser = main.get_node("Enemies/ChaserD")
	player.global_position = Vector2(x - 600.0 if x > 640.0 else x + 600.0, 304)
	player.velocity = Vector2.ZERO
	d.global_position = Vector2(x, GROUND_ENEMY_Y)
	d.velocity = Vector2.ZERO
	d.facing = facing
	d._apply_facing()
	snap_camera()
	await frames(10)
	return d


## While chasing, at the end of every frame D should face the spot it is chasing (the picture is drawn after this).
## Looking only at "did it catch up in the end" is not enough: if it also turned around at ledges / walls by the patrol rules while chasing,
## it would turn back the next frame and catch up anyway, but on screen it would come charging with its back to the player.
## Exception: with the player right below and it walking toward the platform edge to go down (_drop_direction != 0), that direction decides the facing.
func _facing_wrong_way(d: EnemyChaser) -> bool:
	var offset_x := d._last_seen.x - d.global_position.x
	return d.is_chasing and d._drop_direction == 0 and absf(offset_x) > 4.0 and d.facing != signi(offset_x)


func _put_player(x: float, y := 304.0) -> void:
	player.global_position = Vector2(x, y)
	player.velocity = Vector2.ZERO
	snap_camera()


func test_d_is_configured() -> void:
	await reset_scene(true)
	var d: EnemyChaser = main.get_node("Enemies/ChaserD")
	var turret: Enemy = main.get_node("Enemies/Turret1")
	var walker: EnemyWalker = main.get_node("Enemies/WalkerA")
	check("D has as much health as the turret", d.max_health == turret.max_health and d.max_health == 6 * SHOT, "%d vs %d" % [d.max_health, turret.max_health])
	check("D has no gun", d.bullet_scene == null and d.get_node_or_null("Muzzle") == null)
	check("D never goes prone", not d.can_go_prone)
	check("D patrols at the normal enemy speed", d.move_speed == walker.move_speed, "%.1f vs %.1f" % [d.move_speed, walker.move_speed])
	check("D charges at 150", d.charge_speed == 150.0, "%.1f" % d.charge_speed)
	check("D charges slower than the player walks", d.charge_speed < player.move_speed, "%.1f vs %.1f" % [d.charge_speed, player.move_speed])
	check("D notices the player within 240px", d.detect_range == 240.0)
	check("D jumps like the player", d.jump_velocity == player.jump_velocity)


func test_d_patrols_at_normal_speed() -> void:
	var d := await _setup_chaser(500.0, 1)
	await frames(20)
	check("D patrols while the player is far away", not d.is_chasing)
	check("patrol speed is the normal enemy speed", is_equal_approx(absf(d.velocity.x), d.move_speed), "%.1f" % absf(d.velocity.x))


func test_d_charges_when_it_sees_the_player() -> void:
	var d := await _setup_chaser(500.0, -1)
	_put_player(300.0)
	await frames(5)
	check("D starts chasing", d.is_chasing)
	check("D charges at 150", is_equal_approx(d.velocity.x, -150.0), "%.1f" % d.velocity.x)


func test_d_turns_around_for_a_player_behind_it() -> void:
	# D goes by straight-line distance, front or back: it turns and charges even with the player behind it (patrollers only look straight ahead).
	var d := await _setup_chaser(500.0, 1)
	_put_player(300.0)
	await frames(5)
	check("D turns toward a player behind it", d.facing == -1 and d.velocity.x < 0.0, "facing %d, vx %.1f" % [d.facing, d.velocity.x])


func test_d_ignores_a_player_it_cannot_see() -> void:
	# Beyond 240px and not on screen itself: it cannot spot the player and patrols as usual
	var d := await _setup_chaser(1000.0, 1)
	_put_player(240.0)
	await frames(30)
	check("off screen and beyond 240px: D keeps patrolling", not d.is_chasing and d.facing == 1)
	check("still at patrol speed", is_equal_approx(absf(d.velocity.x), d.move_speed), "%.1f" % absf(d.velocity.x))


func test_d_sees_the_player_whenever_it_is_on_screen() -> void:
	# When the player can see it, it has to see the player: on screen it charges even from 260px away (beyond 240)
	var d := await _setup_chaser(500.0, 1)
	_put_player(240.0)
	await frames(5)
	check("on screen at 260px: D charges", d.is_chasing and d.velocity.x < 0.0, "chasing %s, vx %.1f" % [d.is_chasing, d.velocity.x])


func test_d_never_shoots_or_lies_down() -> void:
	var d := await _setup_chaser(500.0, -1)
	_put_player(360.0)
	Input.action_press("crouch")
	var ever_prone := false
	var enemy_bullets := 0
	for i in 150:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		ever_prone = ever_prone or d.is_prone
		enemy_bullets += bullets(16).size()
	check("D never fires", enemy_bullets == 0, str(enemy_bullets))
	check("D never lies down", not ever_prone)


func test_d_hurts_by_touching_the_player() -> void:
	var d := await _setup_chaser(500.0, -1)
	_put_player(380.0)
	var hurt_at := -1
	for i in 120:
		await tree.physics_frame
		if player.health < player.max_health:
			hurt_at = i
			break
	check("D reaches the player and hurts it by contact", hurt_at >= 0, "hurt after %d frames" % hurt_at)
	check("no bullets were involved", bullets(16).is_empty())


func test_walls_block_d_vision() -> void:
	# Wall2: x 800..816, 56 tall. D right of the wall, the player left of it, 140px apart (within 240).
	var d := await _setup_chaser(900.0, 1, true)
	_put_player(760.0)
	var ever_chased := false
	var crossed := false
	for i in 120:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		ever_chased = ever_chased or d.is_chasing
		crossed = crossed or d.global_position.x < 816.0
	check("D does not notice a player hidden behind a wall", not ever_chased)
	check("so it never comes over the wall", not crossed, "x=%.1f" % d.global_position.x)


func test_d_follows_the_player_over_a_wall() -> void:
	# D sees the player first (no wall between), then the player escapes over Wall2: D has to chase to where it last saw them and jump the wall after them.
	var d := await _setup_chaser(1040.0, -1, true)
	_put_player(880.0)
	await frames(5)
	check("D spots the player first", d.is_chasing)
	Input.action_press("move_left")
	var jumped := false
	var crossed_at := -1
	var wrong_way_frames := 0
	for i in 300:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		wrong_way_frames += 1 if _facing_wrong_way(d) else 0
		if not jumped and player.global_position.x < 860.0:
			Input.action_press("jump")
			jumped = true
		if d.global_position.x < 800.0:
			crossed_at = i
			break
	check("D jumps over the wall after the player", crossed_at >= 0, "D at x=%.1f" % d.global_position.x)
	check("D faces where it is heading the whole time", wrong_way_frames == 0, "%d frames facing away" % wrong_way_frames)


func test_d_jumps_up_onto_a_platform() -> void:
	# The player stands on Platform1 (one-way, x 160..256, top y=256), D on the ground below.
	var d := await _setup_chaser(380.0, -1)
	_put_player(208.0, 240.0)
	var landed := false
	for i in 240:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		if d.is_on_floor() and absf(d.global_position.y - 240.0) < 1.5:
			landed = true
			break
	check("D jumps up and lands on the player's platform", landed, "D at %s" % d.global_position)


func test_d_charges_off_its_platform() -> void:
	# The real placement in the level: D on Platform6 (x 1000..1096, top y=184), the player walking on the ground below.
	await reset_scene(true, true)
	keep_only_enemies(["ChaserD"])
	var d: EnemyChaser = main.get_node("Enemies/ChaserD")
	_put_player(920.0)
	var reached_ground := false
	var wrong_way_frames := 0
	for i in 240:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		wrong_way_frames += 1 if _facing_wrong_way(d) else 0
		if d.is_on_floor() and d.global_position.y > 300.0:
			reached_ground = true
			break
	check("D drops off its platform to chase the player", reached_ground, "D at %s" % d.global_position)
	check("D lands near the player instead of overshooting", absf(d.global_position.x - player.global_position.x) < 100.0, "D at x=%.1f, player at x=%.1f" % [d.global_position.x, player.global_position.x])
	check("D does not turn away at the platform edge", wrong_way_frames == 0, "%d frames facing away" % wrong_way_frames)


func test_d_gives_up_after_losing_the_player() -> void:
	var d := await _setup_chaser(500.0, -1)
	_put_player(360.0)
	await frames(5)
	check("D is chasing", d.is_chasing)
	_put_player(1120.0) # Suddenly run more than 240px away
	var gave_up_at := -1
	for i in 240:
		await tree.physics_frame
		if not d.is_chasing:
			gave_up_at = i
			break
	check("D gives up within its 2s memory", gave_up_at >= 0 and gave_up_at <= 125, "after %d frames" % gave_up_at)
	await frames(10)
	check("and goes back to patrol speed", is_equal_approx(absf(d.velocity.x), d.move_speed), "%.1f" % absf(d.velocity.x))


func test_d_gets_down_when_the_player_is_right_below() -> void:
	# D stands in the middle of Platform1 (one-way, x 160..256, top y=256), with the player on the ground right below it.
	# One-way platforms do not block sight, so D can always see the player; it has to walk off the platform itself, not wait above their head.
	await reset_scene(true)
	keep_only_enemies(["ChaserD"])
	var d: EnemyChaser = main.get_node("Enemies/ChaserD")
	d.global_position = Vector2(208, 240)
	d.velocity = Vector2.ZERO
	_put_player(208.0)
	var reached_ground_at := -1
	var hurt := false
	for i in 180:
		await tree.physics_frame
		if reached_ground_at < 0 and d.is_on_floor() and d.global_position.y > 300.0:
			reached_ground_at = i
		# Do not break out the moment it touches the player: D runs into the player while falling, before it has landed,
		# and breaking early would mean the assertion "it really came down by itself" never sees the landing frame.
		hurt = hurt or player.health < player.max_health
	check("D walks off the platform to get to the player below", reached_ground_at >= 0, "D at %s" % d.global_position)
	check("and then reaches the player", hurt)
	check("it lands close to the player", absf(d.global_position.x - 208.0) < 60.0, "x=%.1f" % d.global_position.x)


func test_one_way_platform_sides_do_not_make_d_jump() -> void:
	# D stands on top of Wall2 (x 800..816, top y=264), and right ahead is the side of Platform5 (one-way, x 840..936, y 248..264),
	# exactly at the height of its forward check ray. One-way platforms can be passed through sideways, so D should walk straight through after the player instead of jumping as if it were a wall.
	await reset_scene(true, true)
	keep_only_enemies(["ChaserD"])
	var d: EnemyChaser = main.get_node("Enemies/ChaserD")
	d.global_position = Vector2(808, 250)
	d.velocity = Vector2.ZERO
	d.facing = 1
	d._apply_facing()
	_put_player(960.0)
	var ever_rose := false
	for i in 90:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		ever_rose = ever_rose or d.velocity.y < 0.0
		if d.is_on_floor() and d.global_position.y > 300.0:
			break
	check("D does not jump at the side of a one-way platform", not ever_rose)
	check("D gets down to the player", d.global_position.y > 300.0, "D at %s" % d.global_position)


## While D charges the player runs the other way; compare their distance one second apart.
func _gap_after_running_away(sprint: bool) -> Array:
	var d := await _setup_chaser(760.0, 1)
	_put_player(840.0)
	await frames(5)
	var chasing := d.is_chasing
	Input.action_press("move_right")
	if sprint:
		Input.action_press("sprint")
	await frames(20) # Let both speed up to a steady speed first
	var gap_before := player.global_position.x - d.global_position.x
	await frames(60)
	var gap_after := player.global_position.x - d.global_position.x
	release_all_input()
	return [chasing, gap_before, gap_after]


func test_walking_away_keeps_ahead_of_d() -> void:
	var r := await _gap_after_running_away(false)
	check("D was chasing", r[0])
	check("walking away, D does not close the gap", r[2] >= r[1], "%.1f -> %.1f" % [r[1], r[2]])


func test_sprinting_away_outruns_d() -> void:
	var r := await _gap_after_running_away(true)
	check("D was chasing", r[0])
	# Running at 270 against a charge of 150 opens about 120px in a second.
	check("sprinting away opens a clear gap", r[2] - r[1] > 80.0, "%.1f -> %.1f" % [r[1], r[2]])


# ---------------------------------------------------------------- Bouncing back after a bump

func test_d_bounces_off_instead_of_sitting_on_the_player() -> void:
	# Without the bounce it would stay glued to the player and hit again as soon as the invincibility frames ran out — a player pinned in a corner could only stand and take it.
	# **Do not place it at x 592..704**: that is under the crawl passage with 30px of clearance, and a 32px-tall enemy gets stuck in there
	var d := await _setup_chaser(500.0, -1)
	_put_player(400.0)
	var health_before := player.health
	for i in 120:
		await tree.physics_frame
		if player.health < health_before:
			break
	check("setup: D got to the player", player.health < health_before, str(player.health))
	check("and got shoved back", d.is_bouncing())
	var gap_at_hit := absf(d.global_position.x - player.global_position.x)
	# The player stands still (stopping after the knockback of the hit); see how far it backs off
	player.velocity = Vector2.ZERO
	var widest := gap_at_hit
	for i in int(d.bounce_time * 60.0) + 6:
		await tree.physics_frame
		player.velocity.x = 0.0
		widest = maxf(widest, absf(d.global_position.x - player.global_position.x))
	check("it really backs off", widest - gap_at_hit > 30.0, "%.1f -> %.1f" % [gap_at_hit, widest])
	check("but it is still facing the player", d.facing == signi(player.global_position.x - d.global_position.x),
		"%d vs %d" % [d.facing, signi(player.global_position.x - d.global_position.x)])
	check("and comes back for more", d.is_chasing and not d.is_bouncing())


func test_d_does_not_drain_the_player_while_bouncing() -> void:
	# Hit, back off, again: one bump should cost one hit of health, not keep draining it while glued on.
	var d := await _setup_chaser(500.0, -1)
	_put_player(400.0)
	var start := player.health
	for i in 120:
		await tree.physics_frame
		if player.health < start:
			break
	check("setup: the first hit landed", player.health == start - GameTest.HIT, str(player.health))
	var after_hit := player.health
	for i in 20:
		await tree.physics_frame
	check("no second hit while it is backing off", player.health == after_hit, str(player.health))
	check("setup: it was still backing off", d.is_bouncing() or absf(d.global_position.x - player.global_position.x) > 20.0,
		"%.1f" % absf(d.global_position.x - player.global_position.x))
