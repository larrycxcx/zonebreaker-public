extends GameTest
## Pits: fall out of the stage and you die.
##
## The stage ground is at y=320 and the bottom of the view at 360; `Main.fall_y` (400) is another 40px further down before it counts as falling out —
## running along the ground never trips it, and dropping into a pit kills at once. The test level's (`main.tscn`) ground is one unbroken strip with no pits,
## so these cases always put the player straight at pit-bottom height to test the rule itself.

## At the bottom of a pit (below the stage's fall line).
func below_the_level() -> float:
	return (main.fall_y as float) + 40.0


func test_falling_into_a_pit_costs_a_third_of_your_health() -> void:
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(5)
	var full := player.health
	check("setup: at full health on the ground", full == player.max_health)
	player.global_position = Vector2(400, below_the_level())
	await frames(3)
	var lost := full - player.health
	check("it costs about a third", absf(lost - player.max_health / 3.0) <= 1.0,
		"lost %d of %d" % [lost, player.max_health])
	check("but you are still in the game", player.is_alive() and not player.is_downed())


func test_a_fall_puts_you_back_where_you_last_stood() -> void:
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(5)
	Input.action_press("move_right")
	await frames(30)
	release_all_input()
	await frames(5)
	var stood := player.global_position
	check("setup: it walked somewhere", stood.x > 240.0, str(stood))
	player.global_position = Vector2(stood.x + 400.0, below_the_level())
	await frames(3)
	check("it is back on solid ground", player.global_position.distance_to(stood) < 24.0,
		"%s vs %s" % [player.global_position, stood])
	check("standing still, not still falling", absf(player.velocity.y) < 200.0, str(player.velocity))
	check("with a moment of safety", player.is_invincible())


func test_enough_falls_still_finish_you_off() -> void:
	# Losing the last health goes down the usual death path (alone you die, in co-op you go down)
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(5)
	for i in 6:
		player._shield_timer = 0.0
		player.global_position = Vector2(200, below_the_level())
		await frames(3)
		if not player.is_alive():
			break
	check("the pit gets you in the end", not player.is_alive() and player.health == 0,
		str(player.health))


func test_a_pit_does_not_care_about_the_invincible_frames() -> void:
	# The invincibility right after a hit should not let you float in the pit
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(5)
	var full := player.health
	player.take_damage(HIT, player.global_position + Vector2(40, 0))
	await frames(2)
	check("setup: invincible right now", player.is_invincible())
	player.global_position = Vector2(200, below_the_level())
	await frames(3)
	check("the pit takes its cut anyway", player.health < full - HIT, str(player.health))


func test_the_last_fall_puts_you_down_not_out_when_a_mate_is_around() -> void:
	# Losing the last bit of health in a pit: **alone you die, in co-op you go down** — and since downed players in a pit get brought back too,
	# they land on the last spot they stood on firmly and a partner can still walk over and revive them. Not "cannot be saved so just dead".
	await reset_scene(false, false, null, 2)
	player.global_position = Vector2(200, 304)
	player2.global_position = Vector2(700, 304)
	await frames(5)
	var stood := player2.global_position
	player2.health = maxi(1, ceili(player2.max_health * player2.fall_damage_ratio))
	player2._shield_timer = 0.0
	player2.global_position = Vector2(stood.x + 200.0, below_the_level())
	for i in 20:
		await tree.physics_frame
		if player2.is_downed():
			break
	check("the last third puts them down", player2.is_downed() and not player2.is_alive(),
		"down=%s health=%d" % [player2.is_downed(), player2.health])
	await frames(4)
	check("and they are fished out of the pit", player2.global_position.y < main.fall_y,
		str(player2.global_position))
	check("back where they last stood", player2.global_position.distance_to(stood) < 24.0,
		"%s vs %s" % [player2.global_position, stood])
	# A partner walking over can still revive them
	player.global_position = player2.global_position + Vector2(16, 0)
	await frames(4)
	check("so the mate can still pick them up", player2.is_alive() and not player2.is_downed())


func test_alone_in_a_pit_there_is_no_getting_up() -> void:
	# Alone nobody can revive you, so losing the last bit of health means death
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(5)
	player.health = maxi(1, ceili(player.max_health * player.fall_damage_ratio))
	player._shield_timer = 0.0
	player.global_position = Vector2(400, below_the_level())
	await frames(4)
	check("it is a real death, not a knockdown", not player.is_alive() and not player.is_downed(),
		"health=%d" % player.health)


func test_in_co_op_a_downed_player_is_fished_out_too() -> void:
	# A downed player has no health left to lose, but left at the bottom of a pit a partner could never reach them, so they are brought back too
	await reset_scene(false, false, null, 2)
	player.global_position = Vector2(200, 304)
	player2.global_position = Vector2(600, 304)
	await frames(5)
	player2.take_damage(player2.max_health)
	await frames(2)
	check("setup: down, not dead", player2.is_downed())
	player2.global_position = Vector2(600, below_the_level())
	await frames(3)
	check("it is back on the ground", player2.global_position.y < main.fall_y,
		str(player2.global_position))
	check("and still down, waiting for help", player2.is_downed())


func test_an_enemy_that_falls_in_is_cleaned_up() -> void:
	# Luring the D chasing you to the edge of a pit and pushing it in is a tool the player should have; falling in counts as its death
	await reset_scene(true)
	keep_only_enemies(["ChaserD"])
	var d: Enemy = main.get_node("Enemies/ChaserD")
	var deaths := []
	d.died.connect(func() -> void: deaths.append(true))
	d.global_position = Vector2(300, below_the_level())
	await frames(4)
	check("it dies when it drops out", deaths.size() == 1, str(deaths.size()))
	check("and does not die twice", not is_instance_valid(d) or d.is_queued_for_deletion())
