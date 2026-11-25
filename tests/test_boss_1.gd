extends GameTest
## Boss A (the four-legged missile mech): big, jumps, never goes prone; does not chase, fires fans from its missile pod (only on the ground, but also while walking),
## hurts on contact; dodges grenades that "have landed" and bounce along the floor, not grenades in the air; one ultimate takes 1/4 of its health.

const GRENADE_SCENE := "res://scenes/grenade.tscn"
const NORMAL_ENEMIES := [
	"res://scenes/enemy_1_a.tscn", "res://scenes/enemy_1_b.tscn", "res://scenes/enemy_1_c.tscn",
	"res://scenes/enemy_1_g.tscn", "res://scenes/enemy_1_e.tscn", "res://scenes/enemy_1_d.tscn",
]

var boss: BossMissile


## Keep only Boss A (spawn x=1200), with the player at player_x. The player's health is set very high so being killed by the boss does not spoil the case.
func start(player_x := 940.0) -> void:
	await reset_scene(true)
	keep_only_enemies(["BossMissile"])
	boss = main.get_node("Enemies/BossMissile")
	player.health = 999
	player.global_position = Vector2(player_x, 304)
	player.velocity = Vector2.ZERO
	await frames(5)
	# With the player standing far left the boss's centre may sit right on the screen edge without having appeared; make it appear directly here, the entrance rule is tested by test_boss.gd.
	boss.appear()


## Keep the boss still: no moving, jumping or shooting (to rule out other actions when testing grenade dodging).
func hold_still() -> void:
	boss.roam_speed = 0.0
	boss._jump_timer = 999.0
	boss.jump_interval_min = 999.0
	boss.jump_interval_max = 999.0
	boss.fire_interval = 999.0
	boss._fire_timer = 999.0
	boss._burst_left = 0


## Remove the platform in the boss area (for cases that only test grenades and do not care about terrain).
func clear_high_ground() -> void:
	main.get_node("Level/BossPlatform").free()


## Put the boss at x and the player distance to its left (the boss walks around, and the grenade cases need a fixed distance).
## At 1200: 220~320px to the left of that is an empty stretch without platforms, so the arc never lands on a platform halfway.
func park_boss_and_player(distance: float, x := 1200.0) -> void:
	boss.global_position = Vector2(x, 296)
	boss.velocity = Vector2.ZERO
	player.global_position = Vector2(x - distance, 304)
	player.velocity = Vector2.ZERO
	await frames(5)


func shape_size(body: Node) -> Vector2:
	return ((body.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D).size


## Put a still grenade at pos (with its own physics off, just "a grenade lying there").
func place_grenade(pos: Vector2, landed: bool) -> Grenade:
	var grenade: Grenade = load(GRENADE_SCENE).instantiate()
	grenade.landed = landed
	main.add_child(grenade)
	grenade.global_position = pos
	grenade.set_physics_process(false)
	return grenade


func test_config() -> void:
	await start()
	check("Boss A is a boss", boss is Boss)
	var size := shape_size(boss)
	for path in NORMAL_ENEMIES:
		var enemy: Node = load(path).instantiate()
		var other := shape_size(enemy)
		check("bigger than %s" % path.get_file(), size.x > other.x and size.y > other.y, "%s vs %s" % [size, other])
		enemy.free()
	check("never lies down", not boss.can_go_prone)
	check("ultimate deals 1/4 of max health", boss.ultimate_damage() * 4 == boss.max_health, "%d / %d" % [boss.ultimate_damage(), boss.max_health])
	check("appears when on screen", boss.has_appeared)


func test_ultimate_takes_a_quarter() -> void:
	await start()
	for i in 3:
		boss.hit_by_ultimate()
	check("three ultimates leave a quarter", boss.health == boss.max_health / 4, str(boss.health))
	boss.hit_by_ultimate()
	await frames(1)
	check("the fourth one finishes it", not is_instance_valid(boss))


func test_roams_near_home_without_chasing() -> void:
	await start(940)
	var home := boss.global_position.x
	var far := 0.0
	var moved := false
	var airborne := false
	var top := boss.global_position.y
	for i in 480:
		await frames(1)
		far = maxf(far, absf(boss.global_position.x - home))
		moved = moved or absf(boss.velocity.x) > 0.0
		airborne = airborne or not boss.is_on_floor()
		top = minf(top, boss.global_position.y)
	check("walks around", moved)
	check("stays near home, does not chase the player", far <= boss.roam_range + 16.0, "%.1f px from home" % far)
	check("jumps", airborne)
	check("jumps high", 296.0 - top > 60.0, "%.1f px" % (296.0 - top))


## Pin the player at x for some frames (the boss bumps and shoots it; without pinning it would be pushed away), returning their final horizontal distance.
func pin_player_at(x: float, frame_count := 120) -> float:
	for i in frame_count:
		player.global_position = Vector2(x, 304)
		player.velocity = Vector2.ZERO
		player._invincible_timer = 1000.0
		await frames(1)
	return absf(boss.global_position.x - x)


func test_backs_off_when_the_player_gets_close() -> void:
	# In your face it backs off while firing. Frame by frame: as long as the player is within close_range it must not walk toward the player
	#(looking only at the final distance is not enough; random wandering also walks away).
	await start()
	var spot := boss.global_position.x - 40.0
	var toward := 0
	var close_frames := 0
	for i in 120:
		player.global_position = Vector2(spot, 304)
		player.velocity = Vector2.ZERO
		player._invincible_timer = 1000.0
		await frames(1)
		var offset := spot - boss.global_position.x
		if absf(offset) < boss.close_range and boss.is_on_floor():
			close_frames += 1
			if signf(boss.velocity.x) == signf(offset):
				toward += 1
	check("setup: the player did get close", close_frames > 10, str(close_frames))
	# Allow a frame or two of transition: the player was moved in front of it instantly, and on that frame it still carries last frame's velocity
	check("never walks into a player in its face", toward <= 2, "%d of %d frames" % [toward, close_frames])
	check("ends up out of arm's reach", absf(boss.global_position.x - spot) > boss.close_range - 20.0,
		"%.1f px apart" % absf(boss.global_position.x - spot))
	check("back-off is slower than the player walks", boss.back_off_speed < player.move_speed, "%.0f vs %.0f" % [boss.back_off_speed, player.move_speed])


func test_steps_closer_when_the_player_is_far() -> void:
	# Far away (but within range) it closes in to find a firing spot
	await start()
	var spot := boss._home.x - 400.0
	var before := absf(boss.global_position.x - spot)
	await pin_player_at(spot, 360)
	# For the last 120 frames it stays at fighting distance: random wandering would drift back far away
	var worst := 0.0
	var gap := 0.0
	for i in 60:
		player.global_position = Vector2(spot, 304)
		player.velocity = Vector2.ZERO
		player._invincible_timer = 1000.0
		await frames(1)
		gap = absf(boss.global_position.x - spot)
		worst = maxf(worst, gap)
	check("closes in on a distant player", gap < before - 60.0, "%.1f -> %.1f" % [before, gap])
	check("and keeps that range instead of drifting back", worst <= boss.far_range + 60.0, "worst %.1f" % worst)
	check("stops around its preferred range", gap > boss.close_range, "%.1f" % gap)
	check("never leaves its ground to chase", boss.global_position.x >= boss._home.x - boss.roam_range - 16.0, str(boss.global_position.x))


func test_cornered_at_the_edge_of_its_ground() -> void:
	# Pushed to the edge of its ground it stops backing off (better to be in your face than to leave).
	# The level's right wall is just outside the edge of its ground and would stop it on its own, so the ground is narrowed temporarily here to test the edge itself.
	await start()
	boss.roam_range = 80.0
	var edge := boss._home.x + boss.roam_range
	# With the player closing in from the left it can only back off to the right, where the edge of its ground is
	boss.global_position = Vector2(edge - 20.0, 296)
	await pin_player_at(edge - 90.0, 360)
	check("holds the edge of its ground", boss.global_position.x <= edge + 16.0,
		"%.1f, edge at %.1f" % [boss.global_position.x, edge])
	check("and stays cornered there instead of fleeing past it", boss.global_position.x > edge - 60.0,
		"%.1f, edge at %.1f" % [boss.global_position.x, edge])


func test_ground_is_wider_than_before() -> void:
	await start()
	check("the boss ground covers most of the boss area", boss.roam_range >= 140.0, str(boss.roam_range))
	# The player is far out of range: it wanders on its own and should use a much wider area than the old range (±64), without crossing the edge
	player.global_position = Vector2(boss._home.x - 600.0, 304)
	player.velocity = Vector2.ZERO
	var reach := 0.0
	for i in 600:
		await frames(1)
		reach = maxf(reach, absf(boss.global_position.x - boss._home.x))
	check("wanders across more than the old 64px range", reach > 80.0, "%.1f px from home" % reach)
	check("but never a step beyond its ground", reach <= boss.roam_range + 16.0, "%.1f px from home" % reach)


func test_never_lies_down() -> void:
	await start(960)
	Input.action_press("crouch")
	var prone := false
	for i in 120:
		await frames(1)
		prone = prone or boss.is_prone or shape_size(boss).y != 48.0
	Input.action_release("crouch")
	check("setup: player lying down", true)
	check("boss never lies down", not prone)


func test_contact_hurts_the_player() -> void:
	await start(940)
	hold_still()
	player.health = 3
	player.global_position = Vector2(boss.global_position.x - 28, 304)
	await frames(5)
	check("touching the boss hurts", player.health < 3)


func test_dodges_a_grenade_on_the_ground() -> void:
	for side in [-1, 1]:
		await start(940)
		hold_still()
		var x0 := boss.global_position.x
		place_grenade(Vector2(x0 + side * 60, 312), true)
		var jumped := false
		for i in 20:
			await frames(1)
			jumped = jumped or not boss.is_on_floor()
		var moved := boss.global_position.x - x0
		check("grenade on the %s: moves away" % ("left" if side < 0 else "right"), signf(moved) == -side and absf(moved) > 20.0, "%.1f" % moved)
		check("grenade on the %s: jumps" % ("left" if side < 0 else "right"), jumped)


func test_ignores_a_grenade_in_the_air() -> void:
	await start(940)
	hold_still()
	var x0 := boss.global_position.x
	place_grenade(Vector2(x0 - 60, 220), false)
	var jumped := false
	for i in 20:
		await frames(1)
		jumped = jumped or not boss.is_on_floor()
	check("does not move", absf(boss.global_position.x - x0) < 0.5)
	check("does not jump", not jumped)


func test_grenade_lands_and_is_dodged() -> void:
	# Really throw one: it lands in front of the boss and bounces toward it; the boss dodges and loses no health
	await start()
	clear_high_ground() # This one only tests dodging grenades; do not let the arc hit a platform
	hold_still()
	await park_boss_and_player(320.0) # A grenade thrown on flat ground travels about 220px, landing in front of the boss
	player.facing = 1
	player.switch_weapon()
	Input.action_press("shoot")
	await frames(2)
	Input.action_release("shoot")
	var grenade: Grenade = main.get_children().filter(func(c): return c is Grenade)[0]
	var landed := false
	var dodged := false
	for i in 120:
		await frames(1)
		if not is_instance_valid(grenade):
			break
		landed = landed or grenade.landed
		dodged = dodged or boss.is_dodging
	check("grenade landed before reaching the boss", landed)
	check("boss dodged", dodged)
	check("boss took no damage", boss.health == boss.max_health, "%d / %d" % [boss.health, boss.max_health])


func test_grenade_in_the_air_hits_directly() -> void:
	# Throw from closer: still in the air it hits the boss; the boss does not dodge and takes full damage
	await start()
	clear_high_ground()
	hold_still()
	await park_boss_and_player(220.0)
	player.facing = 1
	player.switch_weapon()
	Input.action_press("shoot")
	await frames(2)
	Input.action_release("shoot")
	var grenade: Grenade = main.get_children().filter(func(c): return c is Grenade)[0]
	var dodged := false
	var landed := false
	for i in 120:
		await frames(1)
		if not is_instance_valid(grenade):
			break
		landed = landed or grenade.landed
		dodged = dodged or boss.is_dodging or not boss.is_on_floor()
	check("setup: grenade never landed", not landed)
	check("boss did not dodge", not dodged)
	check("direct hit damage (3 shots)", boss.health == boss.max_health - 3 * SHOT, "%d / %d" % [boss.health, boss.max_health])


func test_a_wall_bounce_is_not_landing() -> void:
	# A grenade bouncing back off a wall is still an "in the air" grenade, and the boss does not dodge; only hitting the ground / a platform top counts as landing
	await start()
	var grenade: Grenade = load(GRENADE_SCENE).instantiate()
	grenade.launch(Vector2.RIGHT)
	grenade.velocity = Vector2(400, 0)
	grenade.gravity = 0.0
	main.add_child(grenade)
	grenade.global_position = Vector2(1240, 200)
	var bounced := false
	for i in 20:
		await frames(1)
		if grenade.velocity.x < 0.0:
			bounced = true
			break
	check("setup: bounced off the right wall", bounced)
	check("a wall bounce does not count as landing", not grenade.landed)
	grenade.queue_free()


func test_the_boss_platform_is_plain_terrain() -> void:
	# The boss used to jump onto this platform to fire down when the player lay prone; the fan reaches prone players anyway, so that went and the platform is ordinary terrain
	await start()
	var p: Platform = main.get_node("Level/BossPlatform")
	check("the boss area still has its platform", p != null and p.one_way)
	check("the player can jump onto it", 320.0 - p.global_position.y < 92.0, "%.0fpx high" % (320.0 - p.global_position.y))
	check("the boss no longer has a high-ground behaviour", not ("high_ground" in boss))


# ---------------------------------------------------------------- Missile fan

## Keep the boss standing, not jumping (firing as usual), with the player at player_x.
func stand_and_face(player_x: float) -> void:
	boss.roam_speed = 0.0
	boss.back_off_speed = 0.0
	boss._jump_timer = 999.0
	boss.jump_interval_min = 999.0
	boss.jump_interval_max = 999.0
	player.global_position = Vector2(player_x, 304)
	player.velocity = Vector2.ZERO
	await frames(10)


## Wait for the next fan and return the bullets of that round (the batch that left on the same frame).
func next_volley(limit := 200) -> Array:
	boss._fire_timer = minf(boss._fire_timer, 0.05)
	for i in limit:
		player._invincible_timer = 1000.0
		var before := bullets(16).size()
		await frames(1)
		var now := bullets(16)
		if now.size() > before:
			return now.slice(before)
	return []


func test_a_volley_is_a_fan() -> void:
	await start()
	await stand_and_face(boss.global_position.x - 200.0)
	var volley := await next_volley()
	check("one volley fires fan_count missiles at once", volley.size() == boss.fan_count, "%d / %d" % [volley.size(), boss.fan_count])
	if volley.size() != boss.fan_count:
		return
	var angles: Array[float] = []
	for b: Bullet in volley:
		angles.append(rad_to_deg(Vector2(-b.direction.x, b.direction.y).angle()))
	angles.sort()
	var even := true
	for i in angles.size() - 1:
		even = even and absf(angles[i + 1] - angles[i] - boss.fan_spread) < 0.5
	check("the missiles are fan_spread degrees apart", even, str(angles))
	var muzzle := boss._muzzle_position()
	var all_from_pod := true
	var detail := []
	for b: Bullet in volley:
		# Having flown a short way since leaving: its flight line must pass through the pod mouth, and not far from it
		var off := b.global_position - muzzle
		var miss := absf(off.cross(b.direction))
		detail.append("%.2f/%.1f" % [miss, off.length()])
		all_from_pod = all_from_pod and miss < 0.5 and off.length() < 20.0
	check("all of them leave from the missile pod", all_from_pod, "offset / distance %s" % [detail])
	check("the missiles are the boss's own", volley.all(func(b: Bullet) -> bool: return b.skin_key == &"boss_bullet"))
	check("and the ultimate can clear them", volley.all(func(b: Bullet) -> bool: return b.is_in_group(&"enemy_bullets")))


func test_the_fan_is_centred_on_the_player() -> void:
	# The middle missile aims at the player's body centre (standing or prone alike; prone the centre is lower and the fan follows it down)
	for case in [[-220.0, false], [-140.0, false], [-220.0, true]]:
		await start()
		await stand_and_face(boss.global_position.x + case[0])
		if case[1]:
			Input.action_press("crouch")
			await frames(10)
		var volley := await next_volley()
		release_all_input()
		var want := (player.body_center() - boss._muzzle_position()).normalized()
		check("fan centre aims at the player %.0fpx away%s" % [absf(case[0]), " (prone)" if case[1] else ""],
			boss.fan_center.angle_to(want) < deg_to_rad(1.0), "%s vs %s" % [boss.fan_center, want])
		# The whole fan spreads symmetrically around the centre: checking only "one missile points at the centre" would still pass if the whole fan leaned to one side
		var offsets: Array[float] = []
		for bullet: Bullet in volley:
			offsets.append(boss.fan_center.angle_to(bullet.direction))
		var mean := 0.0
		for o in offsets:
			mean += o / maxf(offsets.size(), 1.0)
		check("and the fan spreads evenly on both sides of it", volley.size() == boss.fan_count and absf(mean) < deg_to_rad(0.5),
			"mean offset %.1f°" % rad_to_deg(mean))


func test_the_fan_only_points_forward() -> void:
	# The pod faces forward: with the player almost straight above, the fan centre lifts to fan_max_angle at most, never firing straight up or behind
	await start()
	boss.fire_fan(player) # Fire a round first so the facing is settled
	var up_close := Node2D.new()
	main.add_child(up_close)
	up_close.global_position = boss._muzzle_position() + Vector2(boss.facing * 10.0, -200.0)
	boss.fire_fan(up_close)
	var pitch := rad_to_deg(atan2(-boss.fan_center.y, absf(boss.fan_center.x)))
	check("the fan centre never tilts past fan_max_angle", pitch <= boss.fan_max_angle + 0.1, "%.1f°" % pitch)
	check("and still points forward", signf(boss.fan_center.x) == boss.facing, str(boss.fan_center))
	up_close.free()


func test_turns_to_face_the_player_before_firing() -> void:
	await start()
	for side in [-1.0, 1.0]:
		await stand_and_face(boss.global_position.x + side * 180.0)
		var volley := await next_volley()
		check("player on the %s: faces that way" % ("left" if side < 0 else "right"), boss.facing == int(side), str(boss.facing))
		check("player on the %s: the whole fan flies that way" % ("left" if side < 0 else "right"),
			not volley.is_empty() and volley.all(func(b: Bullet) -> bool: return signf(b.direction.x) == side))


func test_gaps_open_up_with_distance() -> void:
	# The fan can be dodged: at fighting distance, the gap between neighbouring missiles is wider than a standing player, so standing in a gap dodges it
	await start()
	var distance := boss.close_range * 2.0
	var gap := 2.0 * distance * tan(deg_to_rad(boss.fan_spread / 2.0))
	check("at %.0fpx the missiles are %.0fpx apart, room for a standing player" % [distance, gap], gap > Player.STAND_HEIGHT + 8.0)


func test_lying_down_does_not_dodge_the_fan() -> void:
	# Lying prone used to dodge the boss's level shots; the fan aims at the body centre, so prone still gets hit
	await start()
	await stand_and_face(boss.global_position.x - 200.0)
	Input.action_press("crouch")
	await frames(10)
	player.health = 3
	var hit := false
	for i in 240:
		await frames(1)
		if player.health < 3:
			hit = true
			break
	release_all_input()
	check("a prone player still gets hit", hit)


func test_fires_only_on_the_ground_and_while_walking() -> void:
	await start(900)
	var shots := []
	boss.shot_fired.connect(func() -> void: shots.append({"air": not boss.is_on_floor(), "vx": boss.velocity.x}))
	# In the air: the cooldown resets on take-off, and not a single shot before landing
	for i in 120:
		await frames(1)
		if boss.is_on_floor():
			break
	boss.velocity.y = boss.jump_velocity
	await frames(2)
	shots.clear()
	boss._fire_timer = 0.0
	var landed := false
	for i in 120:
		player._invincible_timer = 1000.0
		await frames(1)
		if boss.is_on_floor():
			landed = true
			break
		check("no missiles while airborne", shots.is_empty(), str(shots))
		if not shots.is_empty():
			break
	check("setup: it did land again", landed)
	# On the ground: it keeps firing while walking
	for i in 480:
		player._invincible_timer = 1000.0
		await frames(1)
		if shots.any(func(s): return not s["air"] and s["vx"] != 0.0):
			break
	check("fires while walking", shots.any(func(s): return s["vx"] != 0.0), str(shots.slice(0, 5)))
