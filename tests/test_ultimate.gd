extends GameTest
## The ultimate: K / pad Y fires it instantly, 4 times per life.
## Firing clears all enemy bullets and freezes the whole scene for 2 seconds (neither player nor enemies can move), with the player invincible until 0.5 seconds after it ends;
## when the freeze ends it destroys every enemy that was on screen at the moment it fired (regardless of health), and those off screen are unaffected.

const ENEMY_BULLET_SCENE := "res://scenes/enemy_bullet.tscn"


## The player stands at x=200 (camera at the far left of the stage, screen = x 0..320).
## Only keep the two turrets (12 health, the toughest): Turret2 moved on screen, Turret1 left off screen at x=1160.
func start() -> void:
	await reset_scene(true)
	keep_only_enemies(["Turret1", "Turret2"])
	player.global_position = Vector2(200, 304)
	player.velocity = Vector2.ZERO
	await frames(10)


func use_ultimate() -> void:
	Input.action_press("ultimate")
	await frames(2)
	Input.action_release("ultimate")


## Wait for the freeze to end and return how many physics frames it lasted (-1 if it has not ended after limit frames).
func wait_for_unpause(limit := 600) -> int:
	for i in limit:
		if not tree.paused:
			return i
		await tree.physics_frame
	return -1


func count(event: StringName) -> int:
	return events.filter(func(e): return e == event).size()


func test_config_and_bindings() -> void:
	await start()
	check("player has an ultimate weapon", player.ultimate_weapon != null)
	check("2 uses per life", player.ultimate_weapon.max_ammo == 2 and player.ultimate_ammo() == 2)
	check("ultimate: K", keyboard_keys("ultimate").has(KEY_K))
	check("ultimate: gamepad Y", InputMap.action_get_events("ultimate").any(
		func(e): return e is InputEventJoypadButton and e.button_index == JOY_BUTTON_Y))
	check("not part of the weapon switch cycle", not player.weapons.has(player.ultimate_weapon))
	var row: HBoxContainer = main.get_node("HUD/UltimateRow")
	check("HUD shows 2 ultimate pips", row.get_child_count() == 2)


func test_freeze_clears_bullets_and_kills_on_screen_enemies() -> void:
	await start()
	var near: Enemy = main.get_node("Enemies/Turret2")
	var far: Enemy = main.get_node("Enemies/Turret1")
	near.global_position = Vector2(400, 304)
	await frames(5)
	# Put a few enemy bullets on screen and off screen, plus one player bullet
	for x in [120.0, 500.0, 1000.0]:
		var bullet: Bullet = load(ENEMY_BULLET_SCENE).instantiate()
		bullet.launch(Vector2.LEFT)
		main.add_child(bullet)
		bullet.global_position = Vector2(x, 100)
	player._shoot(Vector2.RIGHT)
	await frames(1)
	check("setup: enemy bullets on and off screen", bullets(16).size() >= 3, "%d" % bullets(16).size())
	var weapon_before := player.current_weapon
	var near_pos := near.global_position
	await use_ultimate()
	check("tree is paused", tree.paused)
	check("ultimate_start reported", count(&"ultimate_start") == 1)
	check("one use spent", player.ultimate_ammo() == 1)
	var pips: Array = main.get_node("HUD/UltimateRow").get_children()
	check("HUD: one pip dimmed", pips[0].color != pips[1].color)
	await frames(1)
	check("every enemy bullet is gone (on and off screen)", bullets(16).is_empty(), "%d left" % bullets(16).size())
	check("player bullets are kept", bullets(4).size() >= 1)
	check("current weapon unchanged", player.current_weapon == weapon_before)

	# During the freeze: keys do nothing, nobody moves, enemies do not fire
	var player_pos := player.global_position
	Input.action_press("move_right")
	Input.action_press("shoot")
	await frames(60)
	check("player frozen even while pressing move", player.global_position == player_pos)
	check("enemy frozen", near.global_position == near_pos)
	check("nobody fires during the freeze", bullets(16).is_empty())
	check("enemies still alive during the freeze", is_instance_valid(near) and near.health == near.max_health)
	Input.action_release("move_right")
	Input.action_release("shoot")

	var took: int = await wait_for_unpause()
	# About 62 frames waited already; in total it should be around 2 seconds (120 frames)
	check("freeze lasts about 2 seconds", took > 40 and took < 80, "%d more frames" % took)
	await frames(2)
	check("on-screen enemy destroyed regardless of health", not is_instance_valid(near))
	check("off-screen enemy untouched", is_instance_valid(far) and far.health == far.max_health)
	check("ultimate_blast reported", count(&"ultimate_blast") == 1)
	check("enemy_death reported", count(&"enemy_death") == 1)
	# After it ends the player can act normally
	var x0 := player.global_position.x
	Input.action_press("move_right")
	await frames(10)
	Input.action_release("move_right")
	check("player moves again after the freeze", player.global_position.x > x0 + 10)


func test_flyer_on_screen_is_hit_too() -> void:
	await reset_scene(true)
	keep_only_enemies(["FlyerE", "Turret1"])
	player.global_position = Vector2(200, 304)
	await frames(10)
	var flyer: Enemy = main.get_node("Enemies/FlyerE")
	await use_ultimate()
	await wait_for_unpause()
	await frames(2)
	check("flyer overhead on screen destroyed", not is_instance_valid(flyer))


func test_invincible_during_and_just_after() -> void:
	await start()
	var hp := player.health
	await use_ultimate()
	await frames(10)
	player.take_damage(HIT)
	check("no damage during the freeze", player.health == hp)
	await wait_for_unpause()
	await frames(10) # About 0.17 seconds after it ends
	player.take_damage(HIT)
	check("still invincible right after the freeze", player.health == hp)
	check("shield does not blink the player", player.get_node("Visual").visible)
	await frames(30) # 0.5 seconds have passed
	player.take_damage(HIT)
	check("can be hurt again afterwards", player.health == hp - HIT)


func test_limited_uses() -> void:
	await start()
	for i in 2:
		await use_ultimate()
		await wait_for_unpause()
		await frames(2)
	check("two uses spent", player.ultimate_ammo() == 0)
	check("two activations", count(&"ultimate_start") == 2)
	await use_ultimate()
	await frames(2)
	check("third press does nothing", not tree.paused and count(&"ultimate_start") == 2)
	var pips: Array = main.get_node("HUD/UltimateRow").get_children()
	check("HUD: both pips dimmed", pips[0].color == pips[1].color and pips[0].color != player.ultimate_weapon.hud_color)
	# Reloading the stage after death: a new life, the uses refilled
	await start()
	check("refilled on a new life", player.ultimate_ammo() == 2)


func test_usable_lying_down_and_in_air() -> void:
	await start()
	Input.action_press("crouch")
	Input.action_press("move_right")
	await frames(10)
	check("setup: crawling", player.is_crouching)
	await use_ultimate()
	check("works while crawling", tree.paused)
	await wait_for_unpause()
	release_all_input()
	await frames(20)
	Input.action_press("jump")
	await frames(8)
	check("setup: airborne", not player.is_on_floor())
	await use_ultimate()
	check("works in the air", tree.paused)
	var y := player.global_position.y
	await frames(30)
	check("frozen in mid-air", player.global_position.y == y)
	await wait_for_unpause()


func test_sounds_play_during_the_freeze() -> void:
	await start()
	var played := []
	var on_played := func(event: StringName, _stream: AudioStream) -> void: played.append(event)
	Sfx.sound_played.connect(on_played)
	await use_ultimate()
	await frames(2)
	check("start sound plays while paused", played.has(&"ultimate_start"))
	check("Sfx keeps running during pause", Sfx.can_process())
	await wait_for_unpause()
	await frames(2)
	Sfx.sound_played.disconnect(on_played)
	check("blast sound plays", played.has(&"ultimate_blast"))


func test_every_enemy_hit_goes_up_in_a_blast() -> void:
	# At the end of the freeze, a blast goes off on each enemy hit on screen (only the picture, drawn by Fx), and none off screen
	await reset_scene(true)
	keep_only_enemies(["WalkerA", "FlyerE", "Turret1"])
	player.global_position = Vector2(200, 304)
	await frames(10)
	# Note the nodes newly added to the effects layer and read their positions at the end of this frame (Fx adds them to the scene first, then positions them)
	var added: Array[Node2D] = []
	var fx: Node = main.get_node("Fx")
	var on_added := func(node: Node) -> void:
		if node is Node2D:
			added.append(node as Node2D)
	fx.child_entered_tree.connect(on_added)
	await use_ultimate()
	# During the freeze the whole tree is paused: the positions noted now are where the enemies are at the moment of the blast
	var on_screen: Array[Vector2] = []
	var off_screen: Array[Vector2] = []
	for enemy: Enemy in enemies():
		if enemy.is_on_screen():
			on_screen.append(enemy.body_center())
		else:
			off_screen.append(enemy.body_center())
	check("setup: some enemies on screen and some off", on_screen.size() >= 2 and off_screen.size() >= 1,
		"%d / %d" % [on_screen.size(), off_screen.size()])
	await wait_for_unpause()
	await frames(1)
	fx.child_entered_tree.disconnect(on_added)
	var blasts: Array[Vector2] = []
	for node in added:
		if is_instance_valid(node) and node.get(&"radius") != null:
			blasts.append(node.global_position)
	for at in on_screen:
		check("a blast on the enemy at %s" % at, blasts.any(func(b: Vector2) -> bool: return b.distance_to(at) < 2.0), str(blasts))
	for at in off_screen:
		check("no blast on the off-screen enemy at %s" % at, not blasts.any(func(b: Vector2) -> bool: return b.distance_to(at) < 2.0))
	var sized := fx.get_children().filter(func(c: Node) -> bool: return c.get(&"radius") != null)
	check("the blasts are grenade-sized", not sized.is_empty() and sized.all(func(c: Node) -> bool: return is_equal_approx(c.get(&"radius"), 56.0)),
		str(sized.map(func(c: Node) -> Variant: return c.get(&"radius"))))
