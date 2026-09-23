extends GameTest
## 成长系统：Progress（等级、经验、金钱、技能点、装备、存档）、四个属性（生命、攻击、防御、射速）怎么作用到玩家身上、
## 杀敌奖励、死了重开全部保留。
##
## 最要紧的一条：**1 级、没装备的玩家和改造前手感一模一样**（120 血挨 3 下死、子弹一发 SHOT、冷却原样），
## 这样老测试才能继续守着手感，升级和装备都是在这之上加。


const SAVE_FOR_TEST := "user://test_progress.json"


## 1 号玩家那一份成长进度。双人时每人一份（`Progress.of(index)`），这一组测的是 1 号。
func me() -> PlayerProgress:
	return Progress.of(0)


## 模拟「死了重开本关」：关卡整个重建，但不动 Progress（reset_scene 会把它清成新开一局）。
func restart_level() -> void:
	free_scene()
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	player = main.get_node("Player")
	for enemy in enemies():
		enemy.free()
	await frames(2)


## 让玩家朝右开一枪，返回那颗子弹。
func fire_one() -> Bullet:
	player.global_position = Vector2(200, 200)
	player.facing = 1
	player._shoot(Vector2.RIGHT)
	var shots := bullets(4)
	return shots[-1] if not shots.is_empty() else null


# ---------------------------------------------------------------- 1 级 = 原来的手感

func test_a_new_game_feels_like_before() -> void:
	await reset_scene()
	check("level 1, no xp, no money, no points", me().level == 1 and me().xp == 0 and me().money == 0 and me().points == 0)
	check("carrying the rifle and the grenade", player.weapons[0].resource_path == "res://weapons/rifle.tres"
		and player.weapons[1].resource_path == "res://weapons/grenade.tres")
	check("three hits to die", player.max_health == 3 * HIT, str(player.max_health))
	var shot := fire_one()
	check("a bullet does one shot of damage", shot != null and shot.damage == SHOT, str(shot.damage) if shot != null else "no shot")
	check("the rifle cools down as before", is_equal_approx(player.current_slot().cooldown_left, player.weapons[0].cooldown),
		str(player.current_slot().cooldown_left))
	player.take_damage(HIT)
	check("a hit takes a full hit (no defense)", player.health == 2 * HIT, str(player.health))


# ---------------------------------------------------------------- 杀敌奖励、升级

func test_kills_pay_xp_and_money() -> void:
	await reset_scene(true)
	keep_only_enemies(["WalkerA", "Turret1"])
	var walker: Enemy = main.get_node("Enemies/WalkerA")
	var turret: Enemy = main.get_node("Enemies/Turret1")
	var xp := walker.xp_reward + turret.xp_reward
	var money := walker.money_reward + turret.money_reward
	var tougher := turret.xp_reward > walker.xp_reward and turret.money_reward > walker.money_reward
	walker.take_damage(walker.health)
	turret.hit_by_ultimate() # 终极武器消灭的也算
	await frames(1)
	check("xp from both kills", me().xp == xp, "%d vs %d" % [me().xp, xp])
	check("money from both kills", me().money == money, "%d vs %d" % [me().money, money])
	check("a tougher enemy pays more", tougher)


func test_every_enemy_pays_and_the_boss_pays_most() -> void:
	await reset_scene(true)
	var boss: Enemy = main.get_node("Enemies/BossA")
	for enemy: Enemy in enemies():
		check("%s pays xp and money" % enemy.name, enemy.xp_reward > 0 and enemy.money_reward > 0)
		if enemy != boss:
			check("the boss pays more than %s" % enemy.name, boss.xp_reward > enemy.xp_reward and boss.money_reward > enemy.money_reward)


func test_levelling_up_gives_skill_points() -> void:
	await reset_scene()
	var levels := []
	me().leveled_up.connect(func(level: int) -> void: levels.append(level))
	var first := Progress.balance.xp_to_next(1)
	me().add_xp(first - 1)
	check("one short of the next level: still level 1", me().level == 1 and me().points == 0)
	me().add_xp(1)
	check("reaching it: level 2", me().level == 2 and me().xp == 0, "Lv %d, %d xp" % [me().level, me().xp])
	check("with skill points to spend", me().points == Progress.balance.points_per_level, str(me().points))
	check("each level asks for more xp", Progress.balance.xp_to_next(2) > first)
	me().add_xp(Progress.balance.xp_to_next(2) + Progress.balance.xp_to_next(3))
	check("a big pile of xp can climb several levels", me().level == 4 and levels == [2, 3, 4], str(levels))


# ---------------------------------------------------------------- 四个属性

func test_life_raises_max_health_and_heals_the_gain() -> void:
	await reset_scene()
	player.take_damage(HIT)
	var before := player.health
	me().points = 2
	me().spend_point(Balance.LIFE)
	var gain := int(Progress.balance.per_point[Balance.LIFE])
	check("max health goes up", player.max_health == 3 * HIT + gain, str(player.max_health))
	check("and the gain is healed on the spot", player.health == before + gain, "%d -> %d" % [before, player.health])
	check("points are spent", me().points == 1)
	check("a bad stat name spends nothing", not me().spend_point(&"luck") and me().points == 1)


func test_attack_raises_damage() -> void:
	await reset_scene()
	me().points = 5
	for i in 5:
		me().spend_point(Balance.ATTACK)
	var shot := fire_one()
	# 攻击 10 → 15：伤害 × 1.5
	check("+5 attack: 50% more damage", shot != null and shot.damage == roundi(SHOT * 1.5), str(shot.damage) if shot != null else "no shot")
	player.switch_weapon()
	player.current_slot().cooldown_left = 0.0
	player._shoot(Vector2.RIGHT)
	var grenade: Grenade = null
	for g in tree.get_nodes_in_group(Grenade.GROUP):
		grenade = g
	check("grenades hit harder too", grenade != null and grenade.max_damage == roundi(3 * SHOT * 1.5) and grenade.min_damage == roundi(SHOT * 1.5),
		"%d..%d" % [grenade.max_damage, grenade.min_damage] if grenade != null else "no grenade")


func test_defense_softens_hits_but_never_to_zero() -> void:
	await reset_scene()
	me().points = 20
	for i in 20:
		me().spend_point(Balance.DEFENSE)
	var defense := me().stat(Balance.DEFENSE)
	player.take_damage(HIT)
	var expected := Balance.damage_taken(HIT, defense)
	check("defense %d: a hit takes %d instead of %d" % [defense, expected, HIT], player.health == player.max_health - expected and expected < HIT,
		str(player.max_health - player.health))
	check("even huge defense lets 1 through", Balance.damage_taken(HIT, 1e6) == 1)
	check("zero damage stays zero", Balance.damage_taken(0, 0.0) == 0)


func test_speed_shortens_cooldowns_up_to_a_cap() -> void:
	await reset_scene()
	me().points = 10
	for i in 10:
		me().spend_point(Balance.SPEED)
	var rate := me().stat(Balance.SPEED)
	fire_one()
	check("speed %d%%: the rifle cools down faster" % rate,
		is_equal_approx(player.current_slot().cooldown_left, player.weapons[0].cooldown * 100.0 / rate), str(player.current_slot().cooldown_left))
	me().points = 1000
	for i in 1000:
		me().spend_point(Balance.SPEED)
	check("but only up to the cap", me().stat(Balance.SPEED) == Progress.balance.cap[Balance.SPEED],
		str(me().stat(Balance.SPEED)))
	check("the ultimate is not sped up", player._ultimate.cooldown_scale == 1.0)


# ---------------------------------------------------------------- 商店、装备

func test_buying_and_wearing_gear() -> void:
	await reset_scene()
	var armor := Equipment.new()
	armor.slot = Equipment.Slot.ARMOR
	armor.price = 50
	armor.bonuses = {Balance.LIFE: 40.0, Balance.DEFENSE: 10.0}
	armor.resist = {&"burn": 0.5}
	check("can't buy without the money", not me().buy(armor) and me().money == 0)
	me().add_money(80)
	check("buying takes the money", me().buy(armor) and me().money == 30, str(me().money))
	check("and does not double-buy", not me().buy(armor) and me().money == 30)
	check("bought is not worn yet", me().gear(Equipment.Slot.ARMOR) == null and player.max_health == 3 * HIT)
	me().equip(armor)
	check("wearing it adds its bonuses", player.max_health == 3 * HIT + 40 and me().stat(Balance.DEFENSE) == 10.0,
		"%d / %s" % [player.max_health, me().stat(Balance.DEFENSE)])
	check("and its resistances", is_equal_approx(me().resistance(&"burn"), 0.5) and me().resistance(&"poison") == 0.0)


func test_a_stronger_gun_changes_what_you_fire() -> void:
	await reset_scene()
	var heavy := (load("res://weapons/rifle.tres") as Weapon).duplicate() as Weapon
	heavy.power = 2.0
	heavy.cooldown = 0.3
	heavy.bonuses = {Balance.SPEED: -20.0}
	me().owned.append(heavy)
	me().equip(heavy)
	check("the gun slot holds it", me().gear(Equipment.Slot.GUN) == heavy)
	await restart_level() # 武器在出生时装上
	check("the player spawns with it", player.weapons[0] == heavy)
	var shot := fire_one()
	check("its power doubles the damage", shot != null and shot.damage == 2 * SHOT, str(shot.damage) if shot != null else "no shot")
	check("its bonus slows the fire rate", is_equal_approx(player.current_slot().cooldown_left, 0.3 * 100.0 / 80.0),
		str(player.current_slot().cooldown_left))
	check("the grenade slot is untouched", player.weapons[1].resource_path == "res://weapons/grenade.tres")


# ---------------------------------------------------------------- 死了全部保留、存档

func test_dying_keeps_everything() -> void:
	await reset_scene()
	me().add_xp(Progress.balance.xp_to_next(1) + 7)
	me().add_money(123)
	me().spend_point(Balance.LIFE)
	var snapshot := [me().level, me().xp, me().money, me().points]
	player.take_damage(player.health)
	await frames(2)
	await restart_level()
	check("level, xp, money and points survive a death", [me().level, me().xp, me().money, me().points] == snapshot,
		"%s vs %s" % [[me().level, me().xp, me().money, me().points], snapshot])
	check("the new player spawns with the raised life, at full health",
		player.max_health == 3 * HIT + int(Progress.balance.per_point[Balance.LIFE]) and player.health == player.max_health, str(player.max_health))


func test_the_save_round_trips() -> void:
	await reset_scene()
	Progress.save_path = SAVE_FOR_TEST
	Progress.persist = true
	var armor := load("res://weapons/grenade.tres") as Equipment # 随便一件有资源路径的装备
	me().add_xp(Progress.balance.xp_to_next(1) + 5)
	me().add_money(77)
	me().spend_point(Balance.ATTACK)
	me().spend_point(Balance.ATTACK)
	var snapshot := [me().level, me().xp, me().money, me().points, me().allocated.duplicate()]
	Progress.new_game()
	check("setup: a new game forgets it all", me().level == 1 and me().money == 0)
	Progress.load_game()
	check("loading the save brings it all back",
		[me().level, me().xp, me().money, me().points, me().allocated] == snapshot,
		"%s vs %s" % [[me().level, me().xp, me().money, me().points, me().allocated], snapshot])
	check("including what is worn", me().gear(Equipment.Slot.GRENADE) == armor and me().gear(Equipment.Slot.GUN) != null)
	Progress.persist = false
	Progress.save_path = Progress.DEFAULT_SAVE
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_FOR_TEST))


func test_a_broken_save_starts_fresh() -> void:
	await reset_scene()
	var file := FileAccess.open(SAVE_FOR_TEST, FileAccess.WRITE)
	file.store_string("{not json")
	file.close()
	Progress.save_path = SAVE_FOR_TEST
	Progress.load_game()
	check("a broken save is ignored", me().level == 1 and me().gear(Equipment.Slot.GUN) != null)
	Progress.save_path = Progress.DEFAULT_SAVE
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_FOR_TEST))


func test_speed_makes_sprints_last_longer() -> void:
	# 速度同时管冲刺：体力消耗 × 100 / 速度。速度 150 = 同样跑一段只耗 2/3 的体力
	var drains := []
	for points in [0, 10]:
		await reset_scene()
		me().points = points
		for i in points:
			me().spend_point(Balance.SPEED)
		player.global_position = Vector2(100, 304)
		await frames(2)
		var before := player.stamina
		Input.action_press("move_right")
		Input.action_press("sprint")
		await frames(30)
		release_all_input()
		drains.append(before - player.stamina)
	check("setup: the sprint really used stamina", drains[0] > 5.0, str(drains))
	check("speed 150: two thirds of the stamina for the same sprint", absf(drains[1] - drains[0] * 2.0 / 3.0) < 0.5, str(drains))
