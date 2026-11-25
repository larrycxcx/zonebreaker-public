extends GameTest
## Progression: Progress (level, XP, money, skill points, gear, saves), how the four stats (life, attack, defence, fire rate) act on the player,
## kill rewards, and everything kept after dying and restarting.
##
## The most important one: **a level 1 player with no gear feels exactly as before the rework** (120 health dies in 3 hits, one bullet does SHOT, cooldowns unchanged),
## so the old tests can keep guarding the feel, and levels and gear are added on top of that.


const SAVE_FOR_TEST := "user://test_progress.json"


## Teardown: turn saving off, restore the path, delete the file the test used.
func drop_test_save() -> void:
	Progress.persist = false
	Progress.save_path = Progress.DEFAULT_SAVE
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_FOR_TEST))


## Player 1's progress. In co-op each player has one (`Progress.of(index)`); this suite tests player 1.
func me() -> PlayerProgress:
	return Progress.of(0)


## Simulate "die and restart the stage": rebuild the whole stage but leave Progress alone (reset_scene would wipe it to a new game).
func restart_level() -> void:
	free_scene()
	main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	player = main.get_node("Player")
	for enemy in enemies():
		enemy.free()
	await frames(2)


## Have the player fire once to the right and return that bullet.
func fire_one() -> Bullet:
	player.global_position = Vector2(200, 200)
	player.facing = 1
	player._shoot(Vector2.RIGHT)
	var shots := bullets(4)
	return shots[-1] if not shots.is_empty() else null


# ---------------------------------------------------------------- Level 1 = the old feel

# ---------------------------------------------------------------- The numbers planned for 23 stages
#
# These pin down "the set of numbers chosen for 23 stages". They look like tests of constants, but that is exactly what needs guarding:
# the curve, the caps and the points per level were worked out together; change any one alone and the whole progression falls apart.

func test_the_level_curve_is_a_power_not_an_exponential() -> void:
	# It used to be `100 × 1.5^(L-1)`, needing 740,000 XP for one level at level 23 — a curve for a game of ten-odd levels.
	# With a power curve each doubling of level is only about three times dearer, so 23 stages can be finished.
	var balance := Progress.balance
	var ten := balance.xp_to_next(10)
	var twenty := balance.xp_to_next(20)
	check("setup: it does get more expensive", twenty > ten, "%d vs %d" % [ten, twenty])
	check("but not exponentially so", float(twenty) / ten < 4.0,
		"level 20 costs %.1f times level 10" % (float(twenty) / ten))


func test_one_run_through_the_game_is_worth_about_one_level_per_stage() -> void:
	# The plan: a first playthrough of 23 stages ends around level 23, and 23 → 30 takes grinding.
	# If the total XP does not add up, either the number of stages changed or the curve moved — the two have to be worked out together.
	var balance := Progress.balance
	var total := 0
	for level in range(1, 23):
		total += balance.xp_to_next(level)
	check("getting to 23 costs six figures of xp", total > 100000 and total < 200000,
		"{:,}".format(total) if false else str(total))


func test_how_far_you_got_is_saved_too() -> void:
	# Saving only the character and not the progress would mean starting from stage 1 every time — once strong, the first few stages are just boring
	var me := Progress.of(0)
	me.reached = 7
	var copy := PlayerProgress.new(Progress.balance)
	copy.from_dict(me.to_dict())
	check("the save remembers how far you got", copy.reached == 7, str(copy.reached))
	# Old saves do not have this field: loaded, it means "only stage 1 unlocked", without crashing or becoming 0
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
	# All four need caps, or gear bonuses mean nothing however big — defence could stack to 400 (damage divided by 5)
	for stat: StringName in Balance.STATS:
		check("%s is capped" % stat, Progress.balance.cap.has(stat), str(Progress.balance.cap))


func test_points_are_refused_once_a_stat_is_maxed() -> void:
	# Still accepting points at the cap would take the point and add to allocated while stat() stays clamped — the player cannot see they are throwing it away
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
	# 2 points per level: 63 points in hand at max level 30, and maxing all four stats takes 88 — you have to choose
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


# ---------------------------------------------------------------- Kill rewards, levelling up

func test_kills_pay_xp_and_money() -> void:
	await reset_scene(true)
	keep_only_enemies(["WalkerA", "Turret1"])
	var walker: Enemy = main.get_node("Enemies/WalkerA")
	var turret: Enemy = main.get_node("Enemies/Turret1")
	var xp := walker.xp_reward + turret.xp_reward
	var money := walker.money_reward + turret.money_reward
	var tougher := turret.xp_reward > walker.xp_reward and turret.money_reward > walker.money_reward
	walker.take_damage(walker.health)
	turret.hit_by_ultimate() # Kills by the ultimate count too
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


# ---------------------------------------------------------------- The four stats

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
	# Attack 10 → 15: damage × 1.5
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


# ---------------------------------------------------------------- Shop, gear

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
	await restart_level() # Weapons are equipped at spawn
	check("the player spawns with it", player.weapons[0] == heavy)
	var shot := fire_one()
	check("its power doubles the damage", shot != null and shot.damage == 2 * SHOT, str(shot.damage) if shot != null else "no shot")
	check("its bonus slows the fire rate", is_equal_approx(player.current_slot().cooldown_left, 0.3 * 100.0 / 80.0),
		str(player.current_slot().cooldown_left))
	check("the grenade slot is untouched", player.weapons[1].resource_path == "res://weapons/grenade.tres")


# ---------------------------------------------------------------- Everything kept after dying, saves

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


# ---------------------------------------------------------------- Character roster

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
	# **Set the play time yourself**: timing starts as soon as the stage loads (`main.gd` calls `tick_playtime()` every frame),
	# and on a slow run those few frames can add up to over a second; this case asks about "just created, not played yet" and should not depend on machine speed.
	was.played_seconds = 0.0
	Progress.take_seat(1, mine)
	check("moving them over empties the old seat", Progress.of(1) == mine and Progress.of(0) != mine)
	check("and the first seat gets somebody else", Progress.of(0) != null and Progress.of(0) != mine)
	# The one pushed out **has not played a single minute** and does not take up a row in the roster (that is pressing NEW in the menu and changing your mind)
	check("the empty character who was there is dropped", not Progress.roster.has(was))


func test_a_character_you_actually_played_is_never_dropped() -> void:
	await reset_scene(false, false, null, 2)
	var theirs := Progress.of(1)
	theirs.played_seconds = 30.0    # Really played (over `UNPLAYED_GRACE`)
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
	# Two old formats: the co-op version had two entries in players, the even older one had a single progress spread over the top level.
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
		"%d characters, Lv%d" % [Progress.roster.size(), Progress.of(0).level])
	check("and playing solo does not invent a second one", Progress.roster.size() == 1, str(Progress.roster.size()))
	drop_test_save()


## Auto-generated names **must not repeat**. Names are capped at 10 characters, and `_free_name` used to "append a number, then truncate" —
## `PLAYER 1` + ` 10` truncated back to `PLAYER 1 1`, and from 11 on every one truncated to one of the strings already taken,
## so after counting through 99 it handed back the duplicate as it was. The player's save thus piled up six identical `PLAYER 1`s:
## the save list was a page of the same name, and seats looked up by name picked the wrong person (actually hit in 2026-09).
func test_auto_names_stay_unique_past_the_length_limit() -> void:
	await reset_scene()
	var names: Array[String] = []
	var too_long: Array[String] = []
	# A dozen or so already reaches two-digit suffixes, which is exactly where it used to fall apart
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


## A save that already has duplicate names (left behind by the bug above) has to be fixed on load,
## or the list would be full of identical rows and seats would pick the wrong person.
func test_a_save_full_of_duplicates_heals_itself() -> void:
	await reset_scene()
	var doubles := []
	for i in 4:
		doubles.append({"name": "PLAYER 1", "level": i + 1})
	var file := FileAccess.open(SAVE_FOR_TEST, FileAccess.WRITE)
	# The one seated is the 3rd (level 3). **Looking up by name cannot find them** — all four are called PLAYER 1,
	# looking up by name only gets the first one, and the player loading the save would end up as another character.
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


## The save records seats as **roster indices**, not names: names are changed by the player, and after a rename the same person has to sit back down.
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
	# Indices are stored, not names: with duplicate names (a save like the previous case) looking up by name picks the wrong person
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
	var armor := load("res://weapons/grenade.tres") as Equipment # Any piece of gear that has a resource path
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
	# Speed governs sprinting too: stamina cost × 100 / speed. Speed 150 = only 2/3 of the stamina for the same run
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


func test_a_save_from_before_the_rename_is_carried_over() -> void:
	# In 2026-11 the project was renamed from FirstGame to ZONE BREAKER, and `user://` moved to another directory. If the old directory has a save and the new one does not, copy it over;
	# if the new one already has one, leave it alone (an old save must not overwrite new progress). All done in a temporary directory, never touching the real save.
	var root := ProjectSettings.globalize_path("user://rename_test")
	var target := root.path_join("ZONE BREAKER/save.json")
	DirAccess.make_dir_recursive_absolute(root.path_join("FirstGame"))
	var old := FileAccess.open(root.path_join("FirstGame/save.json"), FileAccess.WRITE)
	old.store_string("{\"old\": true}")
	old.close()
	check("the old save is copied over", Progress.adopt_old_save(target, root))
	check("with the same contents", FileAccess.get_file_as_string(target) == "{\"old\": true}")
	check("and the old one stays where it was", FileAccess.file_exists(root.path_join("FirstGame/save.json")))
	var fresh := FileAccess.open(target, FileAccess.WRITE)
	fresh.store_string("{\"new\": true}")
	fresh.close()
	check("a save already in the new place is left alone", not Progress.adopt_old_save(target, root)
		and FileAccess.get_file_as_string(target) == "{\"new\": true}")
	for path in [target, root.path_join("FirstGame/save.json")]:
		DirAccess.remove_absolute(path)
	for dir in [root.path_join("ZONE BREAKER"), root.path_join("FirstGame"), root]:
		DirAccess.remove_absolute(dir)
