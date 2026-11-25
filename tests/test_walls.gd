extends GameTest
## Vertical walls: no taller than the jump height (can be jumped over), they block the way, block bullets, block enemy sight, and patrollers turn around at them.
## These cases need the walls kept, so they all use reset_scene(…, true).

const GROUND_Y := 320.0


func walls() -> Array[Platform]:
	var found: Array[Platform] = []
	for wall in main.get_node("Level/Walls").get_children():
		found.append(wall as Platform)
	return found


func wall(wall_name: String) -> Platform:
	return main.get_node("Level/Walls/" + wall_name) as Platform


## Measure how high the player can lift their feet with one full jump on flat ground.
func measure_jump_height() -> float:
	await reset_scene()
	await frames(20)
	var ground := player.global_position.y
	var top := ground
	Input.action_press("jump")
	for i in 60:
		await tree.physics_frame
		top = minf(top, player.global_position.y)
	Input.action_release("jump")
	return ground - top


func test_level_has_vertical_walls() -> void:
	await reset_scene(false, true)
	var all := walls()
	check("the level has 2 walls", all.size() == 2, str(all.size()))
	for w in all:
		check("%s is solid, not a one-way platform" % w.name, not w.one_way)
		check("%s is taller than it is wide" % w.name, w.size.y > w.size.x, str(w.size))
		check("%s stands on the ground" % w.name, is_equal_approx(w.position.y + w.size.y, GROUND_Y), "bottom at %.1f" % (w.position.y + w.size.y))


func test_walls_are_lower_than_the_jump() -> void:
	var jump_height := await measure_jump_height()
	await reset_scene(false, true)
	for w in walls():
		# Leave at least 6px of margin, so a normal jump gets over without pushing the limit.
		check("%s (%dpx) is at least 6px lower than the %.0fpx jump" % [w.name, int(w.size.y), jump_height], w.size.y <= jump_height - 6.0)


func test_player_can_jump_over_every_wall() -> void:
	# The two walls in the stage, plus a temporary 72px wall (the old Wall3, close to the highest allowed).
	for wall_name in ["Wall1", "Wall2", "TallWall"]:
		await reset_scene(false, true)
		var w := add_wall(1080, 72, wall_name) if wall_name == "TallWall" else wall(wall_name)
		# Run right from 80px left of the wall, take off 44px from it and hold jump.
		# Platform1 is above the left of Wall1, so go over it from right to left instead, to avoid landing on the platform.
		var from_left: bool = wall_name != "Wall1"
		var direction := 1 if from_left else -1
		var face_x := w.position.x if from_left else w.position.x + w.size.x
		player.global_position = Vector2(face_x - 80.0 * direction, 304)
		player.velocity = Vector2.ZERO
		await frames(5)
		Input.action_press("move_right" if from_left else "move_left")
		var jumped := false
		for i in 120:
			await tree.physics_frame
			if not jumped and absf(player.global_position.x - face_x) < 44.0:
				Input.action_press("jump")
				jumped = true
		release_all_input()
		var crossed: bool = player.global_position.x > w.position.x + w.size.x if from_left else player.global_position.x < w.position.x
		check("player jumps over %s (%dpx)" % [wall_name, int(w.size.y)], crossed, "ended at x=%.1f" % player.global_position.x)


func test_walls_block_walking() -> void:
	await reset_scene(false, true)
	var w := wall("Wall2")
	player.global_position = Vector2(w.position.x - 60.0, 304)
	player.velocity = Vector2.ZERO
	Input.action_press("move_right")
	await frames(90)
	check("walking into a wall stops the player", player.global_position.x < w.position.x, "x=%.1f" % player.global_position.x)
	Input.action_press("sprint")
	await frames(60)
	check("sprinting into it does not get through either", player.global_position.x < w.position.x, "x=%.1f" % player.global_position.x)


func test_walls_stop_player_bullets() -> void:
	await reset_scene(false, true)
	var w := wall("Wall2")
	player.global_position = Vector2(w.position.x - 80.0, 304)
	player.velocity = Vector2.ZERO
	player.facing = 1
	player._visual.scale.x = 1
	await frames(3)
	player.current_slot().cooldown_left = 0.0
	player._shoot(Vector2.RIGHT)
	var passed := false
	for i in 30:
		await tree.physics_frame
		for b in bullets(4):
			passed = passed or b.global_position.x > w.position.x + w.size.x
	check("player bullets never get past the wall", not passed)
	check("the bullet is destroyed at the wall", bullets(4).is_empty(), str(bullets(4).size()))


func test_walls_stop_enemy_bullets() -> void:
	await reset_scene(false, true)
	var w := wall("Wall2")
	# Spawn an enemy bullet flying left right next to the wall's right side, with the player standing left of the wall.
	player.global_position = Vector2(w.position.x - 60.0, 304)
	var bullet: Bullet = load("res://scenes/enemy_bullet.tscn").instantiate()
	bullet.direction = Vector2.LEFT
	main.add_child(bullet)
	bullet.global_position = Vector2(w.position.x + w.size.x + 40.0, 306)
	await frames(40)
	check("enemy bullets are destroyed by the wall", not is_instance_valid(bullet))
	check("the player behind the wall is not hit", player.health == player.max_health, str(player.health))


func test_turret_cannot_see_through_a_wall() -> void:
	await reset_scene(true, true)
	keep_only_enemies(["Turret1"])
	var turret: EnemyTurret = main.get_node("Enemies/Turret1")
	var w := add_wall(1080, 72) # 72px tall, in front of the turret (x=1160)
	var shots := [0]
	turret.shot_fired.connect(func(): shots[0] += 1)
	# The player stands left of the wall, within the turret's range (400px).
	player.global_position = Vector2(w.position.x - 80.0, 304)
	player.velocity = Vector2.ZERO
	for i in 120:
		player._invincible_timer = 1000.0
		await tree.physics_frame
	check("turret holds fire at a player hidden behind the wall", shots[0] == 0, str(shots[0]))
	check("find_target reports nothing", turret.find_target() == null)

	Input.action_press("crouch")
	await frames(60)
	check("turret does not go prone for a player it cannot see", not turret.is_prone)
	Input.action_release("crouch")

	# Control group: with the wall removed, the same spot gets shot at once.
	w.free()
	await frames(2)
	for i in 30:
		player._invincible_timer = 1000.0
		await tree.physics_frame
	check("without the wall the turret fires at the same spot", shots[0] > 0, str(shots[0]))


func test_walker_cannot_see_through_a_wall() -> void:
	await reset_scene(true, true)
	keep_only_enemies(["WalkerC"])
	var walker: EnemyWalker = main.get_node("Enemies/WalkerC")
	var w := wall("Wall2")
	# C's range is 400px. It stands right of the wall facing left, the player left of the wall.
	walker.global_position = Vector2(w.position.x + w.size.x + 80.0, 306)
	walker.move_speed = 0.0
	walker.facing = -1
	walker._apply_facing()
	player.global_position = Vector2(w.position.x - 80.0, 304)
	player.velocity = Vector2.ZERO
	var shots := [0]
	walker.shot_fired.connect(func(): shots[0] += 1)
	Input.action_press("crouch")
	for i in 120:
		player._invincible_timer = 1000.0
		await tree.physics_frame
	check("walker holds fire at a player behind the wall", shots[0] == 0, str(shots[0]))
	check("walker does not go prone for a player it cannot see", not walker.is_prone)


func test_line_of_sight_passes_one_way_platforms() -> void:
	await reset_scene(true, false)
	keep_only_enemies(["Turret1"])
	var turret: EnemyTurret = main.get_node("Enemies/Turret1")
	# Only the ray itself is tested: stop the turret's physics so that when moved under the crawl tunnel it does not overlap the ceiling and get pushed away.
	turret.set_physics_process(false)
	# From the turret's muzzle look at a point right above Platform1 (one-way, x 160..256, y 256..272): the sight line has to pass through the platform.
	turret.global_position = Vector2(208, 304)
	await frames(3)
	check("one-way platforms do not block line of sight", turret.has_line_of_sight(Vector2(208, 220)))
	# Look the same way above CrawlBlock (solid, x 296..352, y 120..148): it gets blocked.
	turret.global_position = Vector2(648, 304)
	await frames(3)
	check("solid blocks do block line of sight", not turret.has_line_of_sight(Vector2(648, 220)))


func test_walker_turns_around_at_a_wall() -> void:
	await reset_scene(true, true)
	keep_only_enemies(["WalkerA"])
	var walker: EnemyWalker = main.get_node("Enemies/WalkerA")
	var w := wall("Wall1")
	walker.global_position = Vector2(w.position.x + w.size.x + 60.0, 306)
	walker.facing = -1
	walker._apply_facing()
	# Patrollers stop walking once they start fighting, so the player has to be sent away (far off and out of view)
	player.global_position = Vector2(1200, 304)
	player.velocity = Vector2.ZERO
	await frames(2)
	snap_camera()
	var crossed := false
	var turned := false
	for i in 200:
		await tree.physics_frame
		crossed = crossed or walker.global_position.x < w.position.x
		turned = turned or walker.facing == 1
	check("walker turns around at the wall", turned)
	check("walker never walks through the wall", not crossed, "x=%.1f" % walker.global_position.x)
