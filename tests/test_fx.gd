extends GameTest
## The effects layer (`Fx`): listens to the event bus and spawns short-lived placeholder effects where shots, hits and wall impacts happen.
## Effects are display only — no collision, no effect on any check, and they must go away by themselves.

func fx() -> Fx:
	return main.get_node("Fx")


func effects() -> Array:
	return fx().get_children()


## Wait for an effect to appear and return it; null on timeout.
func wait_for_effect(limit := 120) -> Node2D:
	for i in limit:
		await frames(1)
		if not effects().is_empty():
			return effects()[0]
	return null


func test_level_has_an_fx_layer() -> void:
	await reset_scene()
	check("the level has an Fx node", fx() != null)
	check("muzzle flash assigned", fx().muzzle_flash_scene != null)
	check("hit spark assigned", fx().hit_spark_scene != null)
	check("impact spark assigned", fx().impact_spark_scene != null)
	check("starts empty", effects().is_empty())
	# Effects are display only: no colliders anywhere in the tree, or they would block bullets and people
	# The loop variable needs a type: untyped it is a Variant, := below cannot infer a type and the whole script fails to compile (a pitfall noted in CLAUDE.md)
	for scene: PackedScene in [fx().muzzle_flash_scene, fx().hit_spark_scene, fx().impact_spark_scene]:
		var effect := scene.instantiate()
		check("%s is purely visual (no collision anywhere)" % scene.resource_path.get_file(), not has_collision(effect))
		effect.free()


## Does this tree contain any colliders?
func has_collision(node: Node) -> bool:
	if node is CollisionObject2D:
		return true
	return node.get_children().any(func(child): return has_collision(child))


func test_every_enemy_shoot_event_makes_a_flash() -> void:
	# If a new enemy is added and its shoot_event is not registered in Fx.SHOOT_EVENTS, its shots get no muzzle flash
	await reset_scene(true)
	for enemy in enemies():
		if enemy.bullet_scene == null:
			continue # Enemies that do not shoot (D, F)
		check("%s's shoot event (%s) is listed in Fx" % [enemy.name, enemy.shoot_event],
			Fx.SHOOT_EVENTS.has(enemy.shoot_event), str(Fx.SHOOT_EVENTS))


func test_muzzle_flash_when_the_player_fires() -> void:
	await reset_scene()
	player.global_position = Vector2(400, 304)
	player.velocity = Vector2.ZERO
	await frames(10)
	Input.action_press("shoot")
	var flash := await wait_for_effect()
	Input.action_release("shoot")
	check("firing makes a muzzle flash", flash != null)
	if flash == null:
		return
	check("at the muzzle", flash.global_position.distance_to(player.last_muzzle_position) < 1.0,
		"%s vs %s" % [flash.global_position, player.last_muzzle_position])
	check("turned along the shot", is_equal_approx(flash.rotation, player.last_shot_direction.angle()),
		"%.2f vs %.2f" % [flash.rotation, player.last_shot_direction.angle()])


func test_flash_follows_the_aim() -> void:
	await reset_scene()
	player.global_position = Vector2(400, 304)
	player.velocity = Vector2.ZERO
	await frames(10)
	Input.action_press("aim_up")
	await frames(2)
	Input.action_press("shoot")
	var flash := await wait_for_effect()
	release_all_input()
	check("aiming up: flash points up", flash != null and is_equal_approx(flash.rotation, Vector2.UP.angle()),
		"%.2f" % (flash.rotation if flash != null else 0.0))


func test_impact_spark_where_a_bullet_hits_a_wall() -> void:
	await reset_scene(false, true)
	var wall := add_wall(600, 60)
	player.global_position = Vector2(520, 304)
	player.velocity = Vector2.ZERO
	player.facing = 1
	await frames(10)
	player._shoot(Vector2.RIGHT)
	var hit: Node2D = null
	for i in 40:
		await frames(1)
		# The muzzle flash is at the player, the hit sparks at the wall: pick the latter by x
		for effect in effects():
			if effect.global_position.x > wall.position.x - 12.0:
				hit = effect
				break
		if hit != null:
			break
	check("a bullet hitting a wall makes a spark", hit != null)
	if hit != null:
		check("the spark is at the wall", absf(hit.global_position.x - wall.position.x) < 12.0,
			"%.1f vs wall at %.1f" % [hit.global_position.x, wall.position.x])


func test_hit_spark_on_the_enemy_that_was_shot() -> void:
	await reset_scene(true)
	keep_only_enemies(["WalkerC"])
	var c: Enemy = main.get_node("Enemies/WalkerC")
	c.move_speed = 0.0
	c.max_health = 100
	c.health = 100
	c.global_position = Vector2(600, 304)
	player.global_position = Vector2(480, 304)
	player.velocity = Vector2.ZERO
	player.facing = 1
	await frames(10)
	for effect in effects():
		effect.free() # Clear the flashes from setup
	player._shoot(Vector2.RIGHT)
	var spark: Node2D = null
	for i in 60:
		await frames(1)
		for effect in effects():
			if effect.global_position.distance_to(c.global_position) < 20.0:
				spark = effect
				break
		if spark != null:
			break
	check("hitting an enemy makes a spark on it", spark != null, "enemy at %s" % c.global_position)
	check("the enemy really took the hit", c.health < 100, str(c.health))


func test_effects_clean_themselves_up() -> void:
	await reset_scene()
	player.global_position = Vector2(400, 304)
	player.velocity = Vector2.ZERO
	await frames(10)
	Input.action_press("shoot")
	# A flash lives only 0.06 seconds (about 4 frames) and the gun fires every 0.15 seconds, so look while firing, not by counting afterwards
	var seen := false
	for i in 30:
		await frames(1)
		seen = seen or not effects().is_empty()
	Input.action_release("shoot")
	check("setup: effects were spawned", seen)
	for i in 90:
		await frames(1)
		if effects().is_empty():
			break
	check("they all disappear on their own", effects().is_empty(), "%d left" % effects().size())


func test_effects_do_not_touch_gameplay() -> void:
	# The effects layer is only a listener: take it out and gameplay (bullets, damage) is exactly the same
	await reset_scene(true)
	keep_only_enemies(["WalkerC"])
	var c: Enemy = main.get_node("Enemies/WalkerC")
	c.move_speed = 0.0
	c.global_position = Vector2(600, 304)
	fx().queue_free()
	await frames(2)
	player.global_position = Vector2(480, 304)
	player.velocity = Vector2.ZERO
	player.facing = 1
	await frames(10)
	var before := c.health
	player._shoot(Vector2.RIGHT)
	for i in 40:
		await frames(1)
		if not is_instance_valid(c) or c.health < before:
			break
	check("without the Fx layer the shot still hits", not is_instance_valid(c) or c.health < before,
		str(c.health) if is_instance_valid(c) else "dead")
