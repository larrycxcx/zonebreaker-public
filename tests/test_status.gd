extends GameTest
## The structure of status effects (StatusEffect data + StatusEffects timing): damage over time, duration, refresh without stacking, resistance (gear / the enemy's own),
## slowing, paralysis (cannot move or fire), damage over time not triggering invincibility or knockback, weapons with a status applying it on hit, and kills by damage over time still giving rewards.
## The game has no concrete statuses yet (poison, burning, paralysis come later), so these use ones made by the test.



## Player 1's progress. In co-op each player has one (`Progress.of(index)`); this suite tests player 1.
func me() -> PlayerProgress:
	return Progress.of(0)


func dot(id: StringName, damage: int, seconds := 1.0, interval := 0.25) -> StatusEffect:
	var effect := StatusEffect.new()
	effect.id = id
	effect.duration = seconds
	effect.tick_interval = interval
	effect.tick_damage = damage
	return effect


func paralysis(seconds := 1.0) -> StatusEffect:
	var effect := StatusEffect.new()
	effect.id = &"paralysis"
	effect.duration = seconds
	effect.can_act = false
	effect.move_scale = 0.0
	return effect


# ---------------------------------------------------------------- The timing itself

func test_damage_ticks_for_the_duration_then_stops() -> void:
	var s := StatusEffects.new()
	var hits := []
	s.on_damage = func(amount: int) -> void: hits.append(amount)
	check("it takes hold", s.apply(dot(&"poison", 3, 1.0, 0.25)))
	for i in 60:
		s.tick(1.0 / 60.0)
	check("ticks every 0.25s for 1s: 4 ticks", hits == [3, 3, 3, 3], str(hits))
	check("then wears off", not s.has(&"poison"))
	for i in 60:
		s.tick(1.0 / 60.0)
	check("and stays off", hits.size() == 4)


func test_catching_it_again_refreshes_instead_of_stacking() -> void:
	var s := StatusEffects.new()
	var hits := []
	s.on_damage = func(amount: int) -> void: hits.append(amount)
	s.apply(dot(&"burn", 5, 1.0, 0.5))
	for i in 30:
		s.tick(1.0 / 60.0)
	s.apply(dot(&"burn", 5, 1.0, 0.5))
	check("refreshed to the full duration", is_equal_approx(s.time_left(&"burn"), 1.0), "%.2f" % s.time_left(&"burn"))
	check("still one burn, not two", hits.size() <= 1, str(hits))


func test_resistance_shortens_and_immunity_blocks() -> void:
	var s := StatusEffects.new()
	check("half resistance: half the time", s.apply(dot(&"poison", 1, 2.0), 0.5) and is_equal_approx(s.time_left(&"poison"), 1.0),
		"%.2f" % s.time_left(&"poison"))
	check("full resistance: immune", not s.apply(dot(&"burn", 1, 2.0), 1.0) and not s.has(&"burn"))


# ---------------------------------------------------------------- On the player

func test_the_player_takes_poison_without_iframes_or_knockback() -> void:
	await reset_scene()
	await frames(5)
	player.apply_status(dot(&"poison", 5, 1.0, 0.25))
	var velocity_before := player.velocity.x
	await frames(65)
	check("poison drains health over time", player.health == player.max_health - 4 * 5, str(player.health))
	check("without making the player invincible", not player.is_invincible())
	check("or knocking them back", absf(player.velocity.x - velocity_before) < 1.0, str(player.velocity.x))
	player.take_damage(HIT)
	check("a real hit still lands right after", player.health == player.max_health - 20 - HIT, str(player.health))


func test_gear_resists_statuses_on_the_player() -> void:
	await reset_scene()
	var charm := Equipment.new()
	charm.slot = Equipment.Slot.TRINKET
	charm.resist = {&"poison": 1.0}
	me().owned.append(charm)
	me().equip(charm)
	player.apply_status(dot(&"poison", 5))
	check("an immunity charm keeps poison off", not player.statuses.has(&"poison"))
	player.apply_status(dot(&"burn", 5))
	check("but not other statuses", player.statuses.has(&"burn"))


func test_paralysis_stops_moving_and_shooting() -> void:
	await reset_scene()
	player.global_position = Vector2(300, 304)
	await frames(5)
	player.apply_status(paralysis(0.5))
	var x := player.global_position.x
	Input.action_press("move_right")
	Input.action_press("shoot")
	await frames(20)
	check("paralysed: can't walk", absf(player.global_position.x - x) < 1.0, str(player.global_position.x - x))
	check("paralysed: can't shoot", bullets(4).is_empty())
	await frames(30)
	check("then it wears off and the player moves again", player.global_position.x - x > 10.0, str(player.global_position.x - x))
	release_all_input()


func test_slows_stack_with_crouching() -> void:
	await reset_scene()
	var slow := StatusEffect.new()
	slow.id = &"slow"
	slow.duration = 5.0
	slow.move_scale = 0.5
	player.apply_status(slow)
	check("a slow halves walking speed", is_equal_approx(player._speed_scale(), 0.5), str(player._speed_scale()))
	player.is_crouching = true
	check("and multiplies with crawling", is_equal_approx(player._speed_scale(), player.crouch_speed_scale * 0.5), str(player._speed_scale()))
	player.is_crouching = false


# ---------------------------------------------------------------- Weapons with a status, on enemies

func test_a_weapon_with_a_status_puts_it_on_what_it_hits() -> void:
	await reset_scene(true)
	keep_only_enemies(["Turret1"])
	var turret: Enemy = main.get_node("Enemies/Turret1")
	turret.set_physics_process(false)
	var burning := (load("res://weapons/rifle.tres") as Weapon).duplicate() as Weapon
	burning.status = dot(&"burn", 2, 1.0, 0.25)
	player.equip_weapon(0, burning)
	player.global_position = turret.global_position + Vector2(-120, 0)
	player.facing = 1
	await frames(2)
	player._shoot(Vector2.RIGHT)
	var burned := false
	for i in 40:
		await frames(1)
		if turret.statuses.has(&"burn"):
			burned = true
			break
	check("the bullet sets the enemy on fire", burned)
	var health := turret.health
	await frames(20)
	check("and it keeps burning", turret.health < health, "%d -> %d" % [health, turret.health])


func test_enemies_can_resist_and_burning_to_death_pays() -> void:
	await reset_scene(true)
	keep_only_enemies(["WalkerA"])
	var walker: Enemy = main.get_node("Enemies/WalkerA")
	walker.set_physics_process(false)
	walker.resist = {&"poison": 1.0}
	walker.apply_status(dot(&"poison", 50))
	check("an enemy immune to poison shrugs it off", not walker.statuses.has(&"poison"))
	var reward := walker.xp_reward
	walker.apply_status(dot(&"burn", walker.health, 1.0, 0.1))
	for i in 20:
		await frames(1)
		if not is_instance_valid(walker):
			break
	check("burning to death kills it", not is_instance_valid(walker))
	check("and still pays", me().xp == reward, "%d vs %d" % [me().xp, reward])


# ---------------------------------------------------------------- The first real status: poison (the gas clouds of stage 5)

const POISON := "res://status/poison.tres"
const CLOUD := "res://scenes/poison_cloud.tscn"


func cloud_at(x: float, y: float) -> PoisonCloud:
	var cloud := (load(CLOUD) as PackedScene).instantiate() as PoisonCloud
	main.add_child(cloud)
	cloud.global_position = Vector2(x, y)
	return cloud


func test_poison_is_a_real_status() -> void:
	var poison := load(POISON) as StatusEffect
	check("it is called poison", poison.id == &"poison", str(poison.id))
	check("it hurts over time", poison.tick_damage > 0 and poison.tick_interval > 0.0)
	check("and wears off by itself", poison.duration > 0.0 and poison.duration < 10.0, str(poison.duration))
	check("it does not slow you or stop you (that would be another status)",
		poison.move_scale == 1.0 and poison.can_act)


func test_standing_in_a_cloud_poisons_you_and_it_lingers_after() -> void:
	await reset_scene()
	player.global_position = Vector2(400, 304)
	await frames(2)
	var full := player.health
	var cloud := cloud_at(400, 300)
	await frames(10)
	check("standing in it poisons you", player.statuses.has(&"poison"))
	player.global_position = Vector2(560, 304)
	await frames(2)
	check("setup: you walked out of it", not cloud.touches(player.hit_box()))
	await frames(40)
	check("out of the cloud the poison keeps working", player.health < full, "%d -> %d" % [full, player.health])
	await frames(200)
	check("and then it wears off", not player.statuses.has(&"poison"))
	var after := player.health
	await frames(60)
	check("after that no more damage", player.health == after, "%d -> %d" % [after, player.health])


func test_staying_in_the_cloud_does_not_stack() -> void:
	# Staying inside keeps refreshing the duration, but the damage per tick is the same — two seconds lose as much health as "poisoned once for two seconds"
	await reset_scene()
	var poison := load(POISON) as StatusEffect
	player.global_position = Vector2(400, 304)
	await frames(2)
	var cloud := cloud_at(400, 300)
	cloud.lifetime = 30.0
	var full := player.health
	await frames(120)
	var lost := full - player.health
	var expected := int(2.0 / poison.tick_interval) * poison.tick_damage
	check("two seconds in the cloud cost about two seconds of poison", absi(lost - expected) <= poison.tick_damage,
		"%d lost, expected about %d" % [lost, expected])


func test_a_cloud_fades_away_on_its_own() -> void:
	await reset_scene()
	var cloud := cloud_at(400, 200)
	var life := cloud.lifetime
	await frames(int(life * 60.0) + 10)
	check("after its lifetime it is gone", not is_instance_valid(cloud))


func test_a_cloud_only_poisons_players() -> void:
	await reset_scene(true)
	keep_only_enemies(["Turret1"])
	var turret := main.get_node("Enemies/Turret1") as Enemy
	turret.set_physics_process(false)
	var full := turret.health
	var cloud := cloud_at(turret.global_position.x, turret.global_position.y)
	cloud.lifetime = 30.0
	await frames(90)
	check("an enemy standing in it is untouched", turret.health == full and not turret.statuses.has(&"poison"),
		"%d -> %d" % [full, turret.health])


func test_gear_can_make_you_immune_to_poison() -> void:
	await reset_scene()
	var mask := Equipment.new()
	mask.slot = Equipment.Slot.HEAD
	mask.resist = {&"poison": 1.0}
	me().owned.append(mask)
	me().equip(mask)
	player.global_position = Vector2(400, 304)
	await frames(2)
	var full := player.health
	cloud_at(400, 300)
	await frames(60)
	check("full poison resistance: the cloud does nothing", player.health == full and not player.statuses.has(&"poison"),
		"%d -> %d" % [full, player.health])


func test_a_poisoned_player_turns_green_and_stays_green_through_a_hit() -> void:
	await reset_scene()
	var look := player.get_node("Visual") as Appearance
	check("setup: no tint to start with", look.status_tint() == Color.WHITE)
	player.apply_status(load(POISON) as StatusEffect)
	await frames(2)
	check("poisoned: the player is tinted", look.status_tint() != Color.WHITE and look.modulate.g > look.modulate.r,
		str(look.modulate))
	look.flash_hit()
	await frames(20)
	check("a hit flash fades back to the tint, not to white", look.modulate.is_equal_approx(
		Color(look.status_tint().r, look.status_tint().g, look.status_tint().b, look.modulate.a)), str(look.modulate))
	player.statuses.clear()
	await frames(2)
	check("cured: back to normal colours", look.status_tint() == Color.WHITE and look.modulate.r > 0.99,
		str(look.modulate))


func test_the_hud_says_poison_while_it_lasts() -> void:
	await reset_scene()
	var hud: Node = main.get_node("HUD")
	var line: Label = hud.call("status_label")
	check("setup: the status line is empty", line.text == "")
	player.apply_status(load(POISON) as StatusEffect)
	await frames(2)
	check("poisoned: the HUD says so", line.text == "POISON", line.text)
	check("in green", line.get_theme_color("font_color") == UiKit.GREEN)
	player.statuses.clear()
	await frames(2)
	check("cured: the line is empty again", line.text == "", line.text)
