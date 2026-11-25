extends GameTest
## Bosses: every other enemy in a level is a regular enemy (extending Enemy directly); bosses extend Boss.
## Rules: it only appears once it enters the screen (idle until then); on appearing it reports boss_appear and the portrait and health bar show at the top right;
## the ultimate freezes the boss, clears its bullets and deals ultimate_damage() to it, but never destroys it outright.
## Each boss's attacks differ; only the shared rules are tested here (Boss A's own rules are in test_boss_a.gd).

const ENEMY_BULLET_SCENE := "res://scenes/enemy_bullet.tscn"

var boss: Boss


## Keep only Boss A (x=1200), with the player at the far left of the stage and the boss off screen.
func start(extra := []) -> void:
	await reset_scene(true)
	keep_only_enemies(["BossMissile"] + extra)
	boss = main.get_node("Enemies/BossMissile")
	await frames(5)


## Put the player at x and wait for the camera to follow.
func go_to(x: float) -> void:
	player.global_position = Vector2(x, 304)
	player.velocity = Vector2.ZERO
	await frames(5)


func count(event: StringName) -> int:
	return events.filter(func(e): return e == event).size()


func bar() -> Control:
	return main.get_node("HUD/BossBar")


func fill_ratio() -> float:
	var health: ColorRect = main.get_node("HUD/BossBar/Health")
	var fill: ColorRect = main.get_node("HUD/BossBar/Health/Fill")
	return fill.size.x / health.size.x


## Does the health bar show this much health (the bar width is rounded to whole pixels, one pixel of difference allowed)?
func bar_shows(health: int) -> bool:
	var width: float = main.get_node("HUD/BossBar/Health").size.x
	return absf(fill_ratio() - float(health) / boss.max_health) <= 1.0 / width


func use_ultimate() -> void:
	Input.action_press("ultimate")
	await frames(2)
	Input.action_release("ultimate")


func wait_for_unpause() -> void:
	for i in 300:
		if not tree.paused:
			return
		await tree.physics_frame


func test_classification() -> void:
	await reset_scene(true)
	var bosses := []
	for enemy in enemies():
		if enemy is Boss:
			bosses.append(enemy.name)
		else:
			check("%s is a normal enemy" % enemy.name, enemy is Enemy)
	check("the level has one boss", bosses == [&"BossMissile"], str(bosses))
	var b: Boss = main.get_node("Enemies/BossMissile")
	check("boss has a portrait", b.portrait != null)
	check("boss is much tougher than normal enemies", b.max_health >= 30)
	check("one ultimate does not kill it", b.ultimate_damage() < b.max_health)


func test_dormant_until_on_screen() -> void:
	await start()
	# Enlarge the range to the whole stage: if it acts while off screen, it is bound to fire
	boss.detect_range = 2000.0
	await go_to(600) # Screen = x 280..460, boss at 1200
	await frames(120)
	check("off screen: not appeared", not boss.has_appeared)
	check("off screen: no appear event", count(&"boss_appear") == 0)
	check("off screen: HUD bar hidden", not bar().visible)
	check("off screen: dormant, does not fire even with the player in range", bullets(16).is_empty())


func test_appears_once_with_hud_and_sound() -> void:
	await start()
	var played := []
	var on_played := func(event: StringName, _stream: AudioStream) -> void: played.append(event)
	Sfx.sound_played.connect(on_played)
	await go_to(1120)
	check("on screen: appeared", boss.has_appeared)
	check("boss_appear reported once", count(&"boss_appear") == 1)
	check("appear sound played", played.has(&"boss_appear"))
	Sfx.sound_played.disconnect(on_played)
	check("HUD bar shown", bar().visible)
	# The bar is at the top centre: in co-op each side of the screen has a player HUD, and the boss goes in the middle
	var middle: float = bar().position.x + bar().size.x / 2.0
	check("HUD bar across the top middle", absf(middle - 320.0) < 24.0 and bar().position.y < 40,
		"centre %.0f, y %.0f" % [middle, bar().position.y])
	var portrait: TextureRect = main.get_node("HUD/BossBar/Portrait")
	check("HUD shows the boss portrait", portrait.texture == boss.portrait)
	check("health bar full", is_equal_approx(fill_ratio(), 1.0))
	# Leaving and coming back does not make it appear again
	await go_to(80)
	await go_to(1120)
	check("appears only once", count(&"boss_appear") == 1)
	check("bar stays up while the boss lives", bar().visible)


func test_attacks_after_appearing() -> void:
	await start()
	await go_to(920) # On screen, in range
	var fired := false
	for i in 150:
		await frames(1)
		if not bullets(16).is_empty():
			fired = true
			break
	check("boss fires at the player", fired)


func test_health_bar_follows_damage() -> void:
	await start()
	await go_to(1120)
	boss.take_damage(10 * SHOT)
	check("bar shrinks with damage", bar_shows(boss.max_health - 10 * SHOT), str(fill_ratio()))
	boss.take_damage(boss.max_health)
	await frames(2)
	check("boss dies", not is_instance_valid(boss))
	check("bar hidden after the boss dies", not bar().visible)


func test_ultimate_freezes_clears_and_damages() -> void:
	await start(["Turret1"])
	await go_to(920)
	var turret: Enemy = main.get_node("Enemies/Turret1")
	for x in [960.0, 1200.0]:
		var bullet: Bullet = load(ENEMY_BULLET_SCENE).instantiate()
		bullet.launch(Vector2.LEFT)
		main.add_child(bullet)
		bullet.global_position = Vector2(x, 240)
	await frames(1)
	var hp := boss.health
	await use_ultimate()
	check("tree paused", tree.paused)
	await frames(1)
	check("boss bullets cleared", bullets(16).is_empty())
	var fire_timer := boss._fire_timer
	await frames(60)
	check("boss frozen: its fire timer does not run", boss._fire_timer == fire_timer)
	check("nobody fires during the freeze", bullets(16).is_empty())
	check("boss not hurt yet during the freeze", boss.health == hp)
	await wait_for_unpause()
	await frames(2)
	check("boss survives the ultimate", is_instance_valid(boss))
	check("boss takes ultimate_damage", is_instance_valid(boss) and boss.health == hp - boss.ultimate_damage())
	check("HUD bar updated", bar_shows(hp - boss.ultimate_damage()), str(fill_ratio()))
	check("normal enemy on screen is still destroyed", not is_instance_valid(turret))


func test_ultimate_can_finish_a_weak_boss() -> void:
	await start()
	await go_to(920)
	boss.take_damage(boss.max_health - 5)
	await use_ultimate()
	await wait_for_unpause()
	await frames(2)
	check("ultimate damage finishes a boss with little health left", not is_instance_valid(boss))
	check("bar hidden", not bar().visible)


func test_ultimate_misses_an_off_screen_boss() -> void:
	await start()
	await use_ultimate()
	await wait_for_unpause()
	await frames(2)
	check("off-screen boss untouched", boss.health == boss.max_health)


## The range of world coordinates the camera can see now.
func view() -> Rect2:
	var viewport := main.get_viewport()
	return viewport.get_canvas_transform().affine_inverse() * viewport.get_visible_rect()


func test_appears_as_soon_as_any_part_shows() -> void:
	# A boss is wide: half of it is already visible and hittable while its centre is still off screen, and it should appear then rather than letting the player shoot a boss that does not fight back
	await start()
	await go_to(600)
	var half := ((boss.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D).size.x / 2.0
	var edge := view().end.x
	boss.global_position = Vector2(edge + half + 4.0, 296)
	boss.velocity = Vector2.ZERO
	await frames(3)
	check("setup: fully off screen", not boss.is_partly_on_screen())
	check("fully off screen: still dormant", not boss.has_appeared)
	boss.global_position = Vector2(edge + half - 12.0, 296)
	await frames(3)
	check("setup: its centre is still off screen", not boss.is_on_screen())
	check("12px of it showing: it appears", boss.has_appeared)
	check("and the HUD bar is up", bar().visible)


func test_a_dormant_boss_wakes_when_hit() -> void:
	await start()
	await go_to(600)
	check("setup: dormant", not boss.has_appeared)
	boss.take_damage(1)
	await frames(1)
	check("getting hit wakes it up", boss.has_appeared)
	check("the hit still counts", boss.health == boss.max_health - 1, str(boss.health))
	check("and the HUD shows the right health", bar().visible and bar_shows(boss.max_health - 1))
	check("it only appeared once", count(&"boss_appear") == 1)


func test_its_sight_covers_the_screen() -> void:
	# It can reach a player anywhere on screen as soon as it appears: its range is at least one screen wide
	await start()
	check("sight reaches across the screen", boss.detect_range >= view().size.x, "%.0f vs %.0f" % [boss.detect_range, view().size.x])
