extends GameTest
## 成长系统：Progress（等级、经验、金钱、技能点、装备、存档）、四个属性（生命、攻击、防御、射速）怎么作用到玩家身上、
## 杀敌奖励、死了重开全部保留。
##
## 最要紧的一条：**1 级、没装备的玩家和改造前手感一模一样**（120 血挨 3 下死、子弹一发 SHOT、冷却原样），
## 这样老测试才能继续守着手感，升级和装备都是在这之上加。


const SAVE_FOR_TEST := "user://test_progress.json"


## 收尾：关掉存档、把路径还原、删掉测试用的那个文件。
func drop_test_save() -> void:
	Progress.persist = false
	Progress.save_path = Progress.DEFAULT_SAVE
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_FOR_TEST))


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

# ---------------------------------------------------------------- 23 关的数值规划
#
# 这几条把「为 23 关定下来的那套数字」钉住。它们看着像在测常量，但那正是要守的东西：
# 曲线、上限、每级给几点是一起算出来的，谁单独动一个，整条成长线就塌了。

func test_the_level_curve_is_a_power_not_an_exponential() -> void:
	# 原来是 `100 × 1.5^(L-1)`，到 23 级升一级要 74 万经验——那是给十来级的游戏用的曲线。
	# 次方曲线每翻一倍等级只贵三倍左右，23 关才跑得完。
	var balance := Progress.balance
	var ten := balance.xp_to_next(10)
	var twenty := balance.xp_to_next(20)
	check("setup: it does get more expensive", twenty > ten, "%d vs %d" % [ten, twenty])
	check("but not exponentially so", float(twenty) / ten < 4.0,
		"level 20 costs %.1f times level 10" % (float(twenty) / ten))


func test_one_run_through_the_game_is_worth_about_one_level_per_stage() -> void:
	# 规划：一周目 23 关打完大约 23 级，23 → 30 要靠刷。
	# 累计经验对不上的话，要么关数变了、要么曲线动了——两边得一起算。
	var balance := Progress.balance
	var total := 0
	for level in range(1, 23):
		total += balance.xp_to_next(level)
	check("getting to 23 costs six figures of xp", total > 100000 and total < 200000,
		"{:,}".format(total) if false else str(total))


func test_how_far_you_got_is_saved_too() -> void:
	# 只存角色不存进度的话，每次都得从第一关重来——练强了之后前几关就只剩无聊
	var me := Progress.of(0)
	me.reached = 7
	var copy := PlayerProgress.new(Progress.balance)
	copy.from_dict(me.to_dict())
	check("the save remembers how far you got", copy.reached == 7, str(copy.reached))
	# 老存档没有这一项：读进来就是「只解锁了第一关」，不能崩也不能变成 0
	var old_save := me.to_dict()
	old_save.erase("reached")
	var fresh := PlayerProgress.new(Progress.balance)
	fresh.from_dict(old_save)
	check("a save from before this feature still opens", fresh.reached == 1, str(fresh.reached))


func test_levelling_stops_at_the_cap() -> void:
	var me := Progress.of(0)
	me.level = me.balance.max_level
	me.xp = 0
	var points := me.points
	me.add_xp(999999)
	check("the cap holds", me.level == me.balance.max_level, str(me.level))
	check("and hands out no more points", me.points == points, str(me.points))
	check("the bar reads as maxed", me.is_max_level())


func test_every_stat_has_a_ceiling() -> void:
	# 四个都要有上限，否则装备加成做多少都没意义——防御能堆到 400（伤害除以 5）
	for stat: StringName in Balance.STATS:
		check("%s is capped" % stat, Progress.balance.cap.has(stat), str(Progress.balance.cap))


func test_points_are_refused_once_a_stat_is_maxed() -> void:
	# 到顶了还收的话，点数扣了、allocated 加了，stat() 却夹在上限不动——玩家看不出自己在白扔
	var me := Progress.of(0)
	me.points = 999
	var stat := Balance.SPEED
	while not me.is_capped(stat) and me.spend_point(stat):
		pass
	check("setup: it really reached the ceiling", me.is_capped(stat), str(me.stat(stat)))
	var points := me.points
	var spent: int = me.allocated.get(stat, 0)
	check("no more points go in", not me.spend_point(stat))
	check("and none were quietly eaten", me.points == points and me.allocated.get(stat, 0) == spent,
		"%d / %d" % [me.points, me.allocated.get(stat, 0)])


func test_points_come_two_at_a_time() -> void:
	# 每级 2 点：30 级满级手上 63 点，点满四个属性要 88 点 —— 必须取舍
	check("two per level", Progress.balance.points_per_level == 2,
		str(Progress.balance.points_per_level))
	var need := 0
	for stat: StringName in Balance.STATS:
		var per: float = Progress.balance.per_point.get(stat, 1.0)
		need += ceili((Progress.balance.cap[stat] - Progress.balance.base.get(stat, 0.0)) / per)
	var have := Progress.balance.starting_points 		+ (Progress.balance.max_level - 1) * Progress.balance.points_per_level
	check("a maxed character cannot max everything", have < need, "%d points vs %d needed" % [have, need])


func test_a_new_game_feels_like_before() -> void:
	await reset_scene()
	check("level 1, no xp, no money", me().level == 1 and me().xp == 0 and me().money == 0)
	check("with a few points to spend right away", me().points == Progress.balance.starting_points, str(me().points))
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
	var boss: Enemy = main.get_node("Enemies/BossMissile")
	for enemy: Enemy in enemies():
		check("%s pays xp and money" % enemy.name, enemy.xp_reward > 0 and enemy.money_reward > 0)
		if enemy != boss:
			check("the boss pays more than %s" % enemy.name, boss.xp_reward > enemy.xp_reward and boss.money_reward > enemy.money_reward)


func test_levelling_up_gives_skill_points() -> void:
	await reset_scene()
	var levels := []
	me().leveled_up.connect(func(level: int) -> void: levels.append(level))
	var start_points := me().points
	var first := Progress.balance.xp_to_next(1)
	me().add_xp(first - 1)
	check("one short of the next level: still level 1", me().level == 1 and me().points == start_points)
	me().add_xp(1)
	check("reaching it: level 2", me().level == 2 and me().xp == 0, "Lv %d, %d xp" % [me().level, me().xp])
	check("with skill points to spend", me().points == start_points + Progress.balance.points_per_level, str(me().points))
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
	armor.slot = Equipment.Slot.BODY
	armor.price = 50
	armor.bonuses = {Balance.LIFE: 40.0, Balance.DEFENSE: 10.0}
	armor.resist = {&"burn": 0.5}
	check("can't buy without the money", not me().buy(armor) and me().money == 0)
	me().add_money(80)
	check("buying takes the money", me().buy(armor) and me().money == 30, str(me().money))
	check("and does not double-buy", not me().buy(armor) and me().money == 30)
	check("bought is not worn yet", me().gear(Equipment.Slot.BODY) == null and player.max_health == 3 * HIT)
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


# ---------------------------------------------------------------- 角色名册

func test_every_seat_sits_on_a_character_from_the_roster() -> void:
	await reset_scene(false, false, null, 2)
	check("both seats are taken", Progress.of(0) != null and Progress.of(1) != null)
	check("by two different characters", Progress.of(0) != Progress.of(1))
	check("both of them are in the roster",
		Progress.roster.has(Progress.of(0)) and Progress.roster.has(Progress.of(1)), str(Progress.roster.size()))
	check("and they are told apart by name",
		Progress.of(0).character_name != Progress.of(1).character_name,
		"%s / %s" % [Progress.of(0).character_name, Progress.of(1).character_name])


func test_names_are_cleaned_up_and_have_to_be_unique() -> void:
	await reset_scene()
	check("lower case becomes upper", PlayerProgress.sanitize_name("ryu") == "RYU")
	check("anything but letters digits and space is dropped",
		PlayerProgress.sanitize_name("r!y#u 9") == "RYU 9", PlayerProgress.sanitize_name("r!y#u 9"))
	check("and it is cut to the limit",
		PlayerProgress.sanitize_name("ABCDEFGHIJKLMNOP").length() == PlayerProgress.NAME_LIMIT)
	var made := Progress.create("RYU")
	check("a new character joins the roster", made != null and Progress.roster.has(made))
	check("and starts at level one with points to spend",
		made.level == 1 and made.points == Progress.balance.starting_points, str(made.points))
	check("the same name is refused", Progress.create("RYU") == null)
	check("even spelled differently", Progress.create("ryu") == null)
	check("a free name is fine", Progress.create("NOVA") != null)


func test_a_character_can_only_sit_in_one_seat() -> void:
	await reset_scene(false, false, null, 2)
	var mine := Progress.create("RYU")
	Progress.take_seat(0, mine)
	check("the first seat takes them", Progress.of(0) == mine and Progress.seat_of(mine) == 0)
	var was := Progress.of(1)
	# **时长要自己定**：关卡一加载就开始记时（`main.gd` 每帧 `tick_playtime()`），
	# 跑得慢的时候这几帧能记上一秒多，这条用例问的是「刚建好还没玩」，不该看机器快慢。
	was.played_seconds = 0.0
	Progress.take_seat(1, mine)
	check("moving them over empties the old seat", Progress.of(1) == mine and Progress.of(0) != mine)
	check("and the first seat gets somebody else", Progress.of(0) != null and Progress.of(0) != mine)
	# 被挤走的那个**一分钟都没玩过**，不留在名册里占一行（菜单里按 NEW 又改主意就是这条）
	check("the empty character who was there is dropped", not Progress.roster.has(was))


func test_a_character_you_actually_played_is_never_dropped() -> void:
	await reset_scene(false, false, null, 2)
	var theirs := Progress.of(1)
	theirs.played_seconds = 30.0    # 真玩过的（超过 `UNPLAYED_GRACE`）
	var mine := Progress.create("RYU")
	Progress.take_seat(1, mine)
	check("somebody who has played stays in the roster", Progress.roster.has(theirs))
	check("even though they lost their seat", Progress.seat_of(theirs) < 0)
	var spent := Progress.of(0)
	spent.spend_point(&"life")
	var other := Progress.create("KEN")
	Progress.take_seat(0, other)
	check("and so does somebody who spent a point", Progress.roster.has(spent))


func test_deleting_a_character_frees_their_seat() -> void:
	await reset_scene(false, false, null, 2)
	var mine := Progress.create("RYU")
	Progress.take_seat(0, mine)
	Progress.remove(mine)
	check("they are gone from the roster", not Progress.roster.has(mine))
	check("the seat is filled by somebody else", Progress.of(0) != null and Progress.of(0) != mine)
	check("and that somebody is in the roster too", Progress.roster.has(Progress.of(0)))


func test_playtime_only_adds_up_for_who_is_playing() -> void:
	await reset_scene(false, false, null, 2)
	var bench := Progress.create("BENCHED")
	var before := [Progress.of(0).played_seconds, Progress.of(1).played_seconds, bench.played_seconds]
	Progress.tick_playtime(2.5)
	check("both seats count the time",
		Progress.of(0).played_seconds - before[0] == 2.5 and Progress.of(1).played_seconds - before[1] == 2.5,
		"%.1f / %.1f" % [Progress.of(0).played_seconds, Progress.of(1).played_seconds])
	check("nobody else does", bench.played_seconds == before[2], str(bench.played_seconds))


func test_the_roster_round_trips() -> void:
	await reset_scene(false, false, null, 2)
	Progress.save_path = SAVE_FOR_TEST
	Progress.persist = true
	var mine := Progress.create("RYU", &"cyborg")
	mine.add_xp(Progress.balance.xp_to_next(1) + 5)
	mine.add_money(77)
	mine.played_seconds = 1234.0
	Progress.take_seat(0, mine)
	Progress.save_game()
	var names := Progress.roster.map(func(p: PlayerProgress) -> String: return p.character_name)
	names.sort()
	Progress.new_game()
	check("setup: a new game forgets the roster", not Progress.roster.any(func(p: PlayerProgress) -> bool: return p.character_name == "RYU"))
	Progress.load_game()
	var back := Progress.roster.map(func(p: PlayerProgress) -> String: return p.character_name)
	back.sort()
	check("the whole roster comes back", back == names, "%s vs %s" % [back, names])
	var loaded: PlayerProgress = Progress.of(0)
	check("sitting in the seat it was left in", loaded.character_name == "RYU", loaded.character_name)
	check("with its level, money, look and playtime",
		loaded.level == 2 and loaded.money == 77 and loaded.look == &"cyborg" and loaded.played_seconds == 1234.0,
		"Lv%d $%d %s %.0fs" % [loaded.level, loaded.money, loaded.look, loaded.played_seconds])
	check("and a save time to show in the list", not loaded.saved_at.is_empty(), loaded.saved_at)
	drop_test_save()


func test_saves_from_before_the_roster_still_load() -> void:
	# 两种老格式：双人那版是 players 里两份，更早那版是一份进度摊在最外层。
	await reset_scene(false, false, null, 2)
	var file := FileAccess.open(SAVE_FOR_TEST, FileAccess.WRITE)
	file.store_string(JSON.stringify({"players": [{"level": 3, "money": 99}, {"level": 5, "money": 12}]}))
	file.close()
	Progress.save_path = SAVE_FOR_TEST
	Progress.load_game()
	check("the two seats become two characters", Progress.roster.size() == 2, str(Progress.roster.size()))
	check("with their progress kept", Progress.of(0).level == 3 and Progress.of(1).level == 5,
		"Lv%d / Lv%d" % [Progress.of(0).level, Progress.of(1).level])
	check("and names to show in the list",
		not Progress.of(0).character_name.is_empty() and Progress.of(0).character_name != Progress.of(1).character_name,
		"%s / %s" % [Progress.of(0).character_name, Progress.of(1).character_name])
	Progress.new_game()
	file = FileAccess.open(SAVE_FOR_TEST, FileAccess.WRITE)
	file.store_string(JSON.stringify({"level": 4, "money": 40}))
	file.close()
	Progress.load_game()
	check("the oldest format becomes one character", Progress.roster.size() == 1 and Progress.of(0).level == 4,
		"%d 个，Lv%d" % [Progress.roster.size(), Progress.of(0).level])
	check("and playing solo does not invent a second one", Progress.roster.size() == 1, str(Progress.roster.size()))
	drop_test_save()


## 自动起的名字**不许重**。名字上限 10 个字符，`_free_name` 原先是「拼上数字再截断」——
## `PLAYER 1` + ` 10` 截回 `PLAYER 1 1`，从 11 往后每一个都截成已经占着的那几串，
## 数完 99 个就把重复的那个原样交了出去。玩家的存档里因此攒出六个一模一样的 `PLAYER 1`：
## 存档列表整页同名，座位按名字找回来也会认错人（2026-09 实际踩到）。
func test_auto_names_stay_unique_past_the_length_limit() -> void:
	await reset_scene()
	var names: Array[String] = []
	var too_long: Array[String] = []
	# 十几个就会走到两位数的后缀，那正是原先塌掉的地方
	for i in 20:
		var made := Progress.fresh(0)
		names.append(made.character_name)
		if made.character_name.length() > PlayerProgress.NAME_LIMIT:
			too_long.append(made.character_name)
	var seen := {}
	for character_name in names:
		seen[character_name] = true
	check("twenty auto-named characters get twenty different names",
		seen.size() == names.size(), str(names))
	check("and every one of them fits the name limit", too_long.is_empty(), str(too_long))


## 存档里已经攒着同名的（上面那个 bug 留下的），读进来要当场改掉，
## 不然列表上全是一模一样的行、座位也认错人。
func test_a_save_full_of_duplicates_heals_itself() -> void:
	await reset_scene()
	var doubles := []
	for i in 4:
		doubles.append({"name": "PLAYER 1", "level": i + 1})
	var file := FileAccess.open(SAVE_FOR_TEST, FileAccess.WRITE)
	# 坐着的是第 3 个（等级 3）。**按名字是找不回他的**——四个人都叫 PLAYER 1，
	# 按名字找只会拿到第一个，玩家读档进来就是另一个角色了。
	file.store_string(JSON.stringify({"characters": doubles, "seats": [2, -1]}))
	file.close()
	Progress.save_path = SAVE_FOR_TEST
	Progress.load_game()
	check("all four are still there", Progress.roster.size() == 4, str(Progress.roster.size()))
	var seen := {}
	for profile in Progress.roster:
		seen[profile.character_name] = true
	check("but no two of them share a name now", seen.size() == 4, str(seen.keys()))
	check("and their progress is untouched", Progress.roster[2].level == 3,
		str(Progress.roster[2].level))
	check("the seat came back to the right one of them", Progress.of(0).level == 3,
		"Lv%d" % Progress.of(0).level)
	drop_test_save()


## 座位在存档里记的是**名册下标**，不是名字：名字是玩家改的，改完还得坐回原来那个人。
func test_a_seat_survives_its_character_being_renamed() -> void:
	await reset_scene()
	Progress.save_path = SAVE_FOR_TEST
	Progress.persist = true
	var first := Progress.create("ALPHA")
	var second := Progress.create("BETA")
	Progress.take_seat(0, second)
	second.character_name = "OMEGA"
	Progress.save_game()
	Progress.new_game()
	Progress.load_game()
	check("both characters came back", Progress.roster.size() == 2, str(Progress.roster.size()))
	check("and the renamed one is still in the seat", Progress.of(0).character_name == "OMEGA",
		Progress.of(0).character_name)
	# 存的是下标不是名字：名字重了（上一条用例那种存档）按名字就会认错人
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_FOR_TEST))
	var seats: Array = (saved as Dictionary).get("seats", [])
	check("and the file records the seat by roster index",
		not seats.is_empty() and (seats[0] is float or seats[0] is int), str(seats))
	drop_test_save()


func test_there_is_a_slot_for_every_piece_of_gear() -> void:
	check("eight slots", Equipment.Slot.size() == 8, str(Equipment.Slot.size()))
	check("weapons come first", Equipment.Slot.GUN == 0 and Equipment.Slot.GRENADE == 1)
	for slot: int in Equipment.Slot.values():
		check("slot %d has a name for the UI" % slot, Equipment.SLOT_NAMES.has(slot))


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
