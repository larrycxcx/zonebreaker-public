extends GameTest
## 异常状态的结构（StatusEffect 数据 + StatusEffects 计时）：持续伤害、持续时间、刷新不叠加、抗性（装备 / 敌人自己）、
## 减速、麻痹（不能动、不能开火）、持续伤害不触发无敌也不击退、武器带状态打中就挂上、持续伤害打死敌人照样给奖励。
## 游戏里还没有具体的状态（中毒、灼烧、麻痹以后再加），这里用测试现做的。


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


# ---------------------------------------------------------------- 计时本身

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


# ---------------------------------------------------------------- 玩家身上

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
	charm.slot = Equipment.Slot.ACCESSORY
	charm.resist = {&"poison": 1.0}
	Progress.owned.append(charm)
	Progress.equip(charm)
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


# ---------------------------------------------------------------- 武器带状态、敌人身上

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
	check("and still pays", Progress.xp == reward, "%d vs %d" % [Progress.xp, reward])
