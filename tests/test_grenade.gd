extends GameTest
## Grenades and weapon switching: Shift / pad X switches between [rifle, grenade], J / RT fires the current weapon.
## Grenade rules: hitting an enemy directly explodes at once; hitting the ground / a wall bounces once, and the next touch explodes; it explodes after 1.5 seconds at most;
## damage is highest at the centre / on a direct hit, decreasing toward the edge, zero outside; it does not hurt its thrower; walls block the blast; it passes up through one-way platforms and lands on them; unlimited supply.

const GRENADE_SCENE := "res://scenes/grenade.tscn"


func start(x := 200.0) -> void:
	await reset_scene()
	player.global_position = Vector2(x, 304)
	player.velocity = Vector2.ZERO
	await frames(10)


func grenades() -> Array:
	return main.get_children().filter(func(c): return c is Grenade)


## Switch to the grenade, throw one in the current aim direction and return it.
func throw_one() -> Grenade:
	if player.current_weapon != 1:
		player.switch_weapon()
	player.current_slot().cooldown_left = 0.0
	# One grenade per press, looking at "just pressed"; simulated with action_press it only becomes true on the next physics frame,
	# so hold it for two frames — pressed for one frame and released, the key is already up when the check comes round and nothing is thrown.
	Input.action_press("shoot")
	await frames(2)
	Input.action_release("shoot")
	var found := grenades()
	return found[-1] if not found.is_empty() else null


## Put a grenade straight down somewhere (without the throw), for setting up exact geometry.
func spawn_grenade(pos: Vector2, velocity := Vector2.ZERO, gravity := -1.0) -> Grenade:
	var grenade: Grenade = load(GRENADE_SCENE).instantiate()
	grenade.launch(Vector2.DOWN)
	grenade.velocity = velocity
	if gravity >= 0.0:
		grenade.gravity = gravity
	main.add_child(grenade)
	grenade.global_position = pos
	return grenade


## Record where this grenade exploded (and whether it bounced).
func track(grenade: Grenade) -> Dictionary:
	var info := {"exploded_at": null, "bounces": 0}
	var on_event := func(event: StringName, source: Node) -> void:
		if source != grenade:
			return
		if event == &"explosion":
			info["exploded_at"] = grenade.global_position
		elif event == &"grenade_bounce":
			info["bounces"] += 1
	GameEvents.event_happened.connect(on_event)
	info["disconnect"] = func() -> void: GameEvents.event_happened.disconnect(on_event)
	return info


## Put a patroller on the ground at x, standing still with raised health, for measuring damage.
func dummy(walker_name: String, x: float, health := 100) -> EnemyWalker:
	var w: EnemyWalker = main.get_node("Enemies/" + walker_name)
	w.global_position = Vector2(x, 306)
	w.move_speed = 0.0
	w.max_health = health
	w.health = health
	w.set_physics_process(false)
	return w


# ---------------------------------------------------------------- Weapons and switching

func test_weapons_and_bindings() -> void:
	await start()
	check("the player carries [rifle, grenade]", player.weapons.size() == 2 and player.weapons[0].resource_path == "res://weapons/rifle.tres" and player.weapons[1].resource_path == "res://weapons/grenade.tres")
	var g: Weapon = player.weapons[1]
	check("grenades are unlimited", g.max_ammo == -1)
	check("one grenade per press, 0.5s apart", not g.automatic and g.cooldown == 0.5)
	check("throwing reports grenade_throw", g.fire_event == &"grenade_throw")
	check("switch weapon: Shift", keyboard_keys("switch_weapon") == [KEY_SHIFT], str(keyboard_keys("switch_weapon")))
	check("K only fires the ultimate, not switch", InputMap.get_actions().filter(func(a): return keyboard_keys(a).has(KEY_K)) == [&"ultimate"])


func test_shift_switches_weapons() -> void:
	await start()
	var icon: ColorRect = main.get_node("HUD/WeaponIcon")
	check("starts with the rifle", player.current_weapon == 0 and icon.color == player.weapons[0].hud_color)
	Input.action_press("switch_weapon")
	await frames(2)
	Input.action_release("switch_weapon")
	check("Shift switches to the grenade", player.current_weapon == 1)
	check("the HUD shows the grenade", icon.color == player.weapons[1].hud_color)
	check("with a click", events.has(&"weapon_switch"))
	Input.action_press("switch_weapon")
	await frames(2)
	Input.action_release("switch_weapon")
	check("and back to the rifle", player.current_weapon == 0 and icon.color == player.weapons[0].hud_color)
	check("holding Shift switches only once", events.count(&"weapon_switch") == 2, str(events.count(&"weapon_switch")))


func test_each_weapon_keeps_its_own_cooldown() -> void:
	await start()
	await throw_one()
	var grenade_cooldown := player.current_slot().cooldown_left
	player.switch_weapon() # Back to the rifle
	check("the rifle is ready right away", player.current_slot().is_ready())
	player.switch_weapon() # And back to the grenade again
	check("the grenade is still cooling down", not player.current_slot().is_ready() and player.current_slot().cooldown_left <= grenade_cooldown, "%.2f" % player.current_slot().cooldown_left)
	# Wait 0.6 seconds holding the rifle: the grenade set aside cools down too and can be thrown on switching back.
	player.switch_weapon()
	await frames(36)
	player.switch_weapon()
	check("a weapon cools down while holstered", player.current_slot().is_ready(), "%.2f" % player.current_slot().cooldown_left)


func test_grenades_are_unlimited_but_one_per_press() -> void:
	await start()
	player.switch_weapon()
	var thrown := 0
	for i in 6:
		player.current_slot().cooldown_left = 0.0
		var before := events.count(&"grenade_throw")
		Input.action_press("shoot")
		await frames(1)
		Input.action_release("shoot")
		await frames(1)
		thrown += events.count(&"grenade_throw") - before
	check("six presses throw six grenades", thrown == 6, str(thrown))
	var before_hold := events.count(&"grenade_throw")
	player.current_slot().cooldown_left = 0.0
	Input.action_press("shoot")
	await frames(60)
	Input.action_release("shoot")
	check("holding the button throws only one", events.count(&"grenade_throw") - before_hold == 1, str(events.count(&"grenade_throw") - before_hold))


# ---------------------------------------------------------------- Flight and how it explodes

func test_forward_throw_arcs_bounces_once_then_explodes() -> void:
	await start()
	var grenade := await throw_one()
	check("a grenade is thrown", grenade != null)
	if grenade == null:
		return
	var info := track(grenade)
	var start_y := grenade.global_position.y
	var highest := start_y
	var first_landing_x := -1.0
	for i in 120:
		await tree.physics_frame
		if not is_instance_valid(grenade):
			break
		highest = minf(highest, grenade.global_position.y)
		if first_landing_x < 0.0 and info["bounces"] == 1:
			first_landing_x = grenade.global_position.x
	info["disconnect"].call()
	check("it rises first (an arc)", start_y - highest > 40.0, "rose %.1f px" % (start_y - highest))
	check("it lands 100-260px ahead", first_landing_x > 300.0 and first_landing_x < 460.0, "x=%.1f" % first_landing_x)
	check("bounces exactly once", info["bounces"] == 1, str(info["bounces"]))
	check("then explodes on the ground", info["exploded_at"] != null and info["exploded_at"].y > 300.0, str(info["exploded_at"]))


func test_direct_hit_explodes_at_once() -> void:
	await reset_scene(true)
	keep_only_enemies(["WalkerA"])
	var walker := dummy("WalkerA", 400, 2)
	var grenade := spawn_grenade(Vector2(400, 240), Vector2(0, 240))
	var info := track(grenade)
	var deaths := []
	walker.died.connect(func(): deaths.append(true))
	for i in 40:
		await tree.physics_frame
		if info["exploded_at"] != null:
			break
	info["disconnect"].call()
	check("dropping onto an enemy explodes on contact", info["exploded_at"] != null and info["exploded_at"].y < 300.0, str(info["exploded_at"]))
	check("without bouncing first", info["bounces"] == 0, str(info["bounces"]))
	check("a direct hit does full damage (kills a 2-health walker)", deaths.size() == 1)


func test_fuse_forces_the_explosion() -> void:
	await start()
	# A grenade hanging still in the air (no gravity, touching nothing): it still explodes once 1.5 seconds are up.
	var grenade := spawn_grenade(Vector2(400, 240), Vector2.ZERO, 0.0)
	var info := track(grenade)
	var frame := 0
	while info["exploded_at"] == null and frame < 150:
		await tree.physics_frame
		frame += 1
	info["disconnect"].call()
	check("a grenade that never lands explodes after 1.5s", info["exploded_at"] != null and frame >= 88 and frame <= 92, "frame %d" % frame)


# ---------------------------------------------------------------- Damage

func test_damage_falls_off_with_distance() -> void:
	await reset_scene(true)
	keep_only_enemies(["WalkerA", "WalkerB", "WalkerC", "ChaserD"])
	var at_centre := dummy("WalkerA", 600)
	var half_way := dummy("WalkerB", 600 + 28)
	var near_edge := dummy("WalkerC", 600 - 52)
	var d: EnemyChaser = main.get_node("Enemies/ChaserD")
	d.global_position = Vector2(600 + 90, 306)
	d.set_physics_process(false)
	var d_health := d.health
	await frames(2)
	var grenade := spawn_grenade(Vector2(600, 306), Vector2.ZERO, 0.0)
	await frames(1)
	grenade.explode()
	await frames(1)
	check("at the centre: full damage (3 shots)", at_centre.health == 100 - 3 * SHOT, str(100 - at_centre.health))
	check("half way out: 2 shots", half_way.health == 100 - 2 * SHOT, str(100 - half_way.health))
	# Linear falloff then rounding: near the edge it works out to a little more than one shot
	check("near the edge: about 1 shot", 100 - near_edge.health >= SHOT and 100 - near_edge.health < SHOT * 3 / 2, str(100 - near_edge.health))
	check("outside the blast: nothing", d.health == d_health, str(d_health - d.health))


func test_walls_block_the_blast() -> void:
	await reset_scene(true, true)
	keep_only_enemies(["WalkerA", "WalkerB"])
	# Wall2: x 800..408, 56 tall. The explosion is left of the wall, the two patrollers equally far from it (40px), one on this side of the wall, one behind it.
	var same_side := dummy("WalkerA", 750)
	var behind_wall := dummy("WalkerB", 830)
	await frames(2)
	var grenade := spawn_grenade(Vector2(790, 306), Vector2.ZERO, 0.0)
	await frames(1)
	grenade.explode()
	await frames(1)
	check("the enemy on the same side is hurt", same_side.health < 100, str(same_side.health))
	check("the enemy behind the wall is not", behind_wall.health == 100, str(behind_wall.health))


func test_walls_bounce_grenades() -> void:
	await reset_scene(false, true)
	# Throwing right from against the left side of Wall2: the grenade bounces back off the wall instead of passing through.
	player.global_position = Vector2(770, 304)
	player.velocity = Vector2.ZERO
	await frames(10)
	var grenade := await throw_one()
	var info := track(grenade)
	var crossed := false
	for i in 120:
		await tree.physics_frame
		if not is_instance_valid(grenade):
			break
		crossed = crossed or grenade.global_position.x > 816.0
	info["disconnect"].call()
	check("the grenade never gets through the wall", not crossed)
	check("it bounced off something", info["bounces"] >= 1, str(info["bounces"]))


func test_grenades_never_hurt_the_player() -> void:
	await start()
	var grenade := spawn_grenade(player.global_position, Vector2.ZERO, 0.0)
	await frames(1)
	grenade.explode()
	await frames(2)
	check("an explosion right on the player does no harm", player.health == player.max_health, str(player.health))


func test_the_blast_reaches_a_prone_enemy() -> void:
	await reset_scene(true)
	keep_only_enemies(["WalkerC"])
	var c := dummy("WalkerC", 600)
	c.set_prone(true)
	await frames(2)
	var grenade := spawn_grenade(Vector2(630, 300), Vector2.ZERO, 0.0)
	await frames(1)
	grenade.explode()
	await frames(1)
	check("a prone enemy nearby is hurt", c.health < 100, str(c.health))


# ---------------------------------------------------------------- In action

func test_lob_over_a_wall_onto_the_turret() -> void:
	# Put up a 72px wall (x 1080..548) in front of Turret1 (x=1160). The player throws forward from left of the wall, and the grenade clears the wall and hits the turret.
	await reset_scene(true)
	keep_only_enemies(["Turret1"])
	# BossPlatform (x 992..552, y=248) would catch the lobbed grenade; this case only cares about the wall, so move it out of the way first.
	main.get_node("Level/BossPlatform").free()
	add_wall(1080, 72)
	var turret: EnemyTurret = main.get_node("Enemies/Turret1")
	player.global_position = Vector2(940, 304)
	player.velocity = Vector2.ZERO
	player.facing = 1
	player._visual.scale.x = 1
	await frames(10)
	var grenade := await throw_one()
	var crossed := false
	for i in 90:
		player._invincible_timer = 1000.0
		await tree.physics_frame
		if is_instance_valid(grenade) and grenade.global_position.x > 1096.0:
			crossed = true
	check("the grenade clears the wall", crossed)
	check("and hits the turret behind it (6 shots -> 3)", turret.health == 3 * SHOT, str(turret.health))


func test_one_way_platforms_up_through_down_onto() -> void:
	# Standing right under Platform1 (one-way, x 160..128, top y=256), throw straight up: it flies up through the platform, falls back onto it and explodes on top.
	await start(208)
	Input.action_press("aim_up")
	await frames(2)
	var grenade := await throw_one()
	var info := track(grenade)
	var went_above := false
	for i in 120:
		await tree.physics_frame
		if not is_instance_valid(grenade):
			break
		went_above = went_above or grenade.global_position.y < 240.0
	info["disconnect"].call()
	check("it flies up through the platform", went_above)
	check("and lands on top of it", info["exploded_at"] != null and info["exploded_at"].y < 260.0, str(info["exploded_at"]))
