extends GameTest
## 第四关的 Boss「骷髅头」（`scripts/boss_skull.gd`）和它召唤的小骷髅（`scripts/skull_minion.gd`）。
##
## 用测试关跑：清掉关卡自带的浮台（不然「激光射到哪」「换一层」量的是关卡原有的东西），
## 把 Boss 摆在右侧、最低的位置正好让激光对准站在地上的人（和第四关里一样的摆法：地面 320 → 288）。

const PACK := "res://skins/basement/basement_skin.tres"
const GROUND_Y := 320.0
const STAND_Y := 304.0
const BOSS_AT := Vector2(544, 288)


func open_arena(skin: SkinPack = null) -> void:
	await reset_scene(false, false, skin)
	for node in main.get_node("Level").get_children():
		var slab := node as Platform
		if slab != null and slab.one_way:
			slab.free()


func spawn_boss() -> BossSkull:
	var boss := (load("res://scenes/boss_4.tscn") as PackedScene).instantiate() as BossSkull
	main.get_node("Enemies").add_child(boss)
	boss.global_position = BOSS_AT
	boss._home = BOSS_AT
	boss._lanes = [BOSS_AT.x, BOSS_AT.x + boss.lane_offset]
	return boss


func add_ledge(x: float, top: float, wide := 160.0) -> Platform:
	var ledge: Platform = load("res://scenes/platform.tscn").instantiate()
	ledge.one_way = true
	ledge.position = Vector2(x, top)
	ledge.size = Vector2(wide, 16)
	main.get_node("Level").add_child(ledge)
	return ledge


## 等它进入某个状态（最多 n 帧）。
func wait_for(boss: BossSkull, state: Callable, n := 300) -> bool:
	for i in n:
		if state.call():
			return true
		await tree.physics_frame
	return state.call()


# ---------------------------------------------------------------- 身份

func test_it_is_a_floating_boss() -> void:
	var boss := (load("res://scenes/boss_4.tscn") as PackedScene).instantiate() as BossSkull
	check("it is a boss", boss is Boss)
	check("it floats", boss.motion_mode == CharacterBody2D.MOTION_MODE_FLOATING)
	check("and does not fall before it appears", is_zero_approx(boss.gravity))
	check("it brings minions to summon", boss.minion_scene != null)
	boss.free()


func test_the_pack_has_its_art() -> void:
	var pack := load(PACK) as SkinPack
	for key: StringName in [&"4_boss", &"4_minion"]:
		check("%s is in the pack" % key, pack.appearances.has(key))
	for clip: String in ["idle", "charge", "beam", "summon", "sneer", "hurt", "death"]:
		check("the boss has %s" % clip,
			ResourceLoader.exists("res://skins/basement/enemies/4_boss/%s_r.png" % clip))
	for clip: String in ["idle", "walk", "hurt", "death"]:
		check("the minion has %s" % clip,
			ResourceLoader.exists("res://skins/basement/enemies/4_minion/%s_r.png" % clip))
	check("and a beam to tile", ResourceLoader.exists("res://skins/basement/enemies/4_boss/beam_thick.png"))


# ---------------------------------------------------------------- 激光

func test_it_lines_up_charges_then_fires() -> void:
	await open_arena()
	var boss := spawn_boss()
	player.global_position = Vector2(300, STAND_Y)
	snap_camera()
	var full := player.health
	var charged := await wait_for(boss, func() -> bool: return boss.is_charging())
	check("it starts charging", charged)
	check("lined up on the player's body", absf(boss.beam_height() - player.body_center().y) <= 1.0,
		"%.1f vs %.1f" % [boss.beam_height(), player.body_center().y])
	# **量蓄力持续了多久**，不是只看进没进过：蓄力为 0 时状态也会闪一帧「蓄力中」
	var held := 0
	while boss.is_charging() and held < 120:
		await tree.physics_frame
		held += 1
		if boss.is_charging():
			check("nothing hurts while it charges — that is the warning", player.health == full,
				"%d -> %d at frame %d" % [full, player.health, held])
	check("the warning lasts long enough to react to", held >= 30, "%d frames" % held)
	var fired := await wait_for(boss, func() -> bool: return boss.is_firing(), 30)
	check("then it fires", fired)
	await frames(3)
	check("and the beam hits", player.health < full, "%d -> %d" % [full, player.health])


func test_the_beam_runs_to_the_wall_through_ledges() -> void:
	await open_arena()
	var boss := spawn_boss()
	add_ledge(200, boss.global_position.y + BossSkull.BEAM_ORIGIN.y - 8.0, 120)
	player.global_position = Vector2(300, STAND_Y)
	snap_camera()
	await wait_for(boss, func() -> bool: return boss.is_firing())
	var wall := main.get_node("Level/WallLeft") as Platform
	var wall_face := wall.position.x + wall.size.x
	check("it fires across the whole level, to the far wall", absf(boss.beam_end().x - wall_face) < 2.0,
		"ends at %.0f, wall at %.0f" % [boss.beam_end().x, wall_face])


func test_another_floor_is_safe() -> void:
	# 躲法是换一层：激光锁定之后跳上一层（60 高）就打不到
	await open_arena()
	var boss := spawn_boss()
	var ledge := add_ledge(240, GROUND_Y - 60.0, 160)
	player.global_position = Vector2(300, STAND_Y)
	snap_camera()
	await wait_for(boss, func() -> bool: return boss.is_charging())
	player.global_position = Vector2(300, ledge.position.y - 16.0)
	var full := player.health
	await wait_for(boss, func() -> bool: return boss.is_firing(), 60)
	await frames(int(boss.beam_time * 60.0))
	check("one floor up, the beam passes under you", player.health == full, "%d -> %d" % [full, player.health])


func test_lying_down_under_it_also_works() -> void:
	# 激光对着站着的人的身体中心、6px 粗；趴下的人顶在它下面
	await open_arena()
	var boss := spawn_boss()
	player.global_position = Vector2(300, STAND_Y)
	snap_camera()
	await wait_for(boss, func() -> bool: return boss.is_charging())
	Input.action_press("crouch")
	await frames(4)
	var full := player.health
	await wait_for(boss, func() -> bool: return boss.is_firing(), 60)
	await frames(int(boss.beam_time * 60.0))
	release_all_input()
	check("setup: the player really lay down", player.hit_box().size.y < 20.0, str(player.hit_box()))
	check("and the beam went over", player.health == full, "%d -> %d" % [full, player.health])


# ---------------------------------------------------------------- 召唤、换边

func test_every_third_attack_is_a_summon() -> void:
	await open_arena()
	var boss := spawn_boss()
	player.global_position = Vector2(300, STAND_Y)
	snap_camera()
	boss._attacks = boss.summon_every - 1
	boss._left = 0.0
	await frames(60)
	check("it summoned", boss.minions().size() == boss.summon_count, str(boss.minions().size()))
	for minion in boss.minions():
		check("a minion is a skull minion", minion is SkullMinion)


func test_never_more_minions_than_the_cap() -> void:
	await open_arena()
	var boss := spawn_boss()
	player.global_position = Vector2(300, STAND_Y)
	snap_camera()
	for i in 3:
		boss._summon()
	check("capped", boss.minions().size() <= boss.minion_cap, str(boss.minions().size()))


func test_minions_float_at_you_and_die_in_two_shots() -> void:
	await open_arena()
	var minion := (load("res://scenes/enemy_4_minion.tscn") as PackedScene).instantiate() as SkullMinion
	main.get_node("Enemies").add_child(minion)
	minion.global_position = Vector2(500, 200)
	player.global_position = Vector2(300, STAND_Y)
	snap_camera()
	var start := minion.global_position.distance_to(player.body_center())
	await frames(60)
	check("it drifts towards the player", minion.global_position.distance_to(player.body_center()) < start - 30.0)
	minion.take_damage(GameTest.SHOT)
	check("one shot is not enough", is_instance_valid(minion) and minion.health > 0)
	minion.take_damage(GameTest.SHOT)
	check("two are", not is_instance_valid(minion) or minion.health <= 0)


func test_killing_a_minion_while_the_boss_lives_is_fine() -> void:
	# 2026-10 试玩崩过：打死一只小骷髅以后，Boss 每帧清理名单时把已经释放的对象传给了
	# 带类型的 lambda 参数，每帧报 SCRIPT ERROR（编辑器里就停在调试器上）。
	# 原来的用例只测过「Boss 死了小骷髅跟着碎」，从没在 Boss 还活着的时候打死过一只。
	await open_arena()
	var boss := spawn_boss()
	player.global_position = Vector2(300, STAND_Y)
	snap_camera()
	await frames(2)
	boss._summon()
	var minions := boss.minions().duplicate()
	check("setup: there are minions", minions.size() >= 2, str(minions.size()))
	# **直接 free()，不走 take_damage**：真打的时候是玩家的子弹把它打死的，子弹在 Boss 之后处理，
	# 小骷髅在那一帧末尾就被释放了——Boss 下一帧清理名单时拿到的是一个已经释放的对象。
	# 在两帧之间 take_damage 的话它只是「待删」，Boss 先看到待删就去掉了，重现不出来（第一版就这么绿了）。
	(minions[0] as Enemy).free()
	await frames(30)
	check("the boss lets go of the dead one", boss.minions().size() == minions.size() - 1,
		str(boss.minions().size()))
	check("and keeps fighting", is_instance_valid(boss) and boss.health > 0)


func test_it_switches_sides_every_other_attack() -> void:
	await open_arena()
	var boss := spawn_boss()
	player.global_position = Vector2(300, STAND_Y)
	snap_camera()
	boss._attacks = 1
	boss._left = 0.0
	var swapped := await wait_for(boss, func() -> bool: return boss.is_swapping(), 30)
	check("it heads for the other side", swapped)
	await wait_for(boss, func() -> bool: return not boss.is_swapping(), 240)
	check("and gets there", absf(boss.global_position.x - (BOSS_AT.x + boss.lane_offset)) < 2.0,
		str(boss.global_position.x))
	check("still facing into the shaft", boss.facing == 1)


# ---------------------------------------------------------------- 第二阶段

func test_it_turns_nasty_below_half_and_says_so_once() -> void:
	await open_arena()
	var boss := spawn_boss()
	player.global_position = Vector2(300, STAND_Y)
	snap_camera()
	await frames(2)
	boss.take_damage(boss.max_health / 2 + 1)
	check("enraged", boss.is_enraged())
	boss.take_damage(5)
	var said := events.count(&"boss_enrage")
	check("and it said so exactly once", said == 1, str(said))


func test_enraged_it_fires_twice_a_round() -> void:
	await open_arena()
	var boss := spawn_boss()
	player.global_position = Vector2(300, STAND_Y)
	snap_camera()
	await frames(2)
	boss.take_damage(boss.max_health / 2 + 1)
	player.set_physics_process(false)
	var beams := 0
	var was_firing := false
	for i in 400:
		await tree.physics_frame
		player.health = player.max_health
		if boss.is_firing() and not was_firing:
			beams += 1
		was_firing = boss.is_firing()
		if boss._move == BossSkull.Move.REST and beams > 0:
			break
	check("two beams in one round", beams == 2, str(beams))


# ---------------------------------------------------------------- 死了

func test_its_minions_go_with_it_and_pay_nothing() -> void:
	await open_arena()
	var boss := spawn_boss()
	player.global_position = Vector2(300, STAND_Y)
	snap_camera()
	await frames(2)
	boss._summon()
	var minions := boss.minions().duplicate()
	check("setup: there are minions", not minions.is_empty())
	# 比金钱、不比经验：Boss 那 400 多经验会让 1 级的角色升级，升级把经验清零重算，差值就不是奖励了
	var money := player.progress.money
	var pay := boss.money_reward
	boss.die()
	await frames(2)
	# 不给循环变量标类型：它们多半已经被释放了，给已释放的对象赋一个带类型的变量会报错
	for minion in minions:
		check("a minion went with it", not is_instance_valid(minion) or minion.is_queued_for_deletion())
	check("and only the boss paid", player.progress.money - money == pay,
		"%d vs %d" % [player.progress.money - money, pay])


# ---------------------------------------------------------------- 换皮肤

func test_the_pack_draws_the_beam_and_changes_no_rules() -> void:
	var heights := []
	for skin: SkinPack in [null, load(PACK) as SkinPack]:
		await open_arena(skin)
		var boss := spawn_boss()
		player.global_position = Vector2(300, STAND_Y)
		snap_camera()
		await wait_for(boss, func() -> bool: return boss.is_firing())
		heights.append([boss.beam_height(), boss.beam_end().x])
		if skin != null:
			var visual := boss.get_node("Visual")
			check("the pack's look is on", visual is BossSkullAppearance, str(visual))
			if visual is BossSkullAppearance:
				check("and it is drawing the beam", (visual as BossSkullAppearance)._beam_state == 2)
				check("in the firing pose", (visual as BossSkullAppearance).clip() == &"beam",
					str((visual as BossSkullAppearance).clip()))
	check("the same beam in both skins", heights[0] == heights[1], str(heights))
