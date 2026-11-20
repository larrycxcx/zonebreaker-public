extends GameTest
## 第二关的两种机关：液压机（`HydraulicPress`）和闸门（`BlastGate`）。2026-10 用户要求加的，
## 素材里一直有、我们没用上。都只伤玩家，都得躲着穿过去。
##
## 规则按贴图每一帧量出来的表算（锤头压到哪、门开多大），外观只画那一帧——
## 所以最后一条用例拿默认皮肤和素材包各跑一遍，比判定是不是一模一样。

const GROUND_Y := 320.0
const STAND_Y := 304.0
const PACK := "res://skins/industrial/industrial_skin.tres"
const LEVEL_2 := "res://scenes/level_2.tscn"


func place(scene: String, x: float) -> Node2D:
	var trap := (load(scene) as PackedScene).instantiate() as Node2D
	main.add_child(trap)
	trap.global_position = Vector2(x, GROUND_Y - 64.0)
	return trap


## 推进到机关的某一帧（最多 n 帧物理帧）。
func until_frame(trap: Node, wanted: Array, n := 300) -> bool:
	for i in n:
		if wanted.has(trap.get("frame")):
			return true
		await tree.physics_frame
	return wanted.has(trap.get("frame"))


# ---------------------------------------------------------------- 液压机

func test_a_raised_press_leaves_room_to_walk_under() -> void:
	await reset_scene()
	var press := place("res://scenes/trap_press.tscn", 400) as HydraulicPress
	check("setup: it starts raised", press.frame == 0)
	check("there is room for a standing player under it", press.clearance() >= 32.0,
		"%.0f" % press.clearance())
	player.global_position = Vector2(416, STAND_Y)
	var full := player.health
	await frames(30)
	check("standing under it while it rests is safe", player.health == full, "%d -> %d" % [full, player.health])


func test_a_slamming_press_hits_standing_and_lying_alike() -> void:
	for crouch: bool in [false, true]:
		await reset_scene()
		var press := place("res://scenes/trap_press.tscn", 400) as HydraulicPress
		player.global_position = Vector2(416, STAND_Y)
		if crouch:
			Input.action_press("crouch")
		await frames(4)
		var full := player.health
		var slammed := await until_frame(press, [2, 3, 4])
		await frames(2)
		release_all_input()
		check("setup: it slammed down", slammed)
		check("it hits a %s player" % ("lying" if crouch else "standing"), player.health < full,
			"%d -> %d" % [full, player.health])


func test_a_press_blocks_nothing() -> void:
	# 碰不得，但不是墙：没有碰撞体，人和子弹都不会被它挡住（挡住的是天花板，那是关卡的事）
	var press := (load("res://scenes/trap_press.tscn") as PackedScene).instantiate()
	var bodies := press.find_children("*", "CollisionObject2D", true, false)
	check("no collision bodies", bodies.is_empty() and not press is CollisionObject2D, str(bodies))
	press.free()


# ---------------------------------------------------------------- 闸门

func test_a_shut_gate_is_a_wall() -> void:
	await reset_scene()
	var gate := place("res://scenes/trap_gate.tscn", 400) as BlastGate
	check("setup: it starts shut", gate.is_shut())
	player.global_position = Vector2(340, STAND_Y)
	Input.action_press("move_right")
	await frames(40)
	release_all_input()
	check("you cannot walk through it", player.global_position.x < 400.0, str(player.global_position.x))


func test_a_shut_gate_stops_bullets() -> void:
	await reset_scene()
	var gate := place("res://scenes/trap_gate.tscn", 400) as BlastGate
	player.global_position = Vector2(340, STAND_Y)
	await frames(3)
	player._shoot(Vector2.RIGHT)
	await frames(20)
	var past := bullets(4).filter(func(b: Node2D) -> bool: return b.global_position.x > 432.0)
	check("setup: the gate is shut", gate.is_shut())
	check("no bullet gets through", past.is_empty(), str(past.size()))


func test_an_open_gate_lets_you_through() -> void:
	await reset_scene()
	var gate := place("res://scenes/trap_gate.tscn", 400) as BlastGate
	var opened := await until_frame(gate, [4])
	check("setup: it opens", opened)
	player.global_position = Vector2(370, STAND_Y)
	Input.action_press("move_right")
	await frames(30)
	release_all_input()
	check("you walk right through", player.global_position.x > 440.0, str(player.global_position.x))


func test_a_closing_gate_bites_and_throws_you_out() -> void:
	await reset_scene()
	var gate := place("res://scenes/trap_gate.tscn", 400) as BlastGate
	await until_frame(gate, [4])
	player.global_position = Vector2(412, STAND_Y)
	player.velocity = Vector2.ZERO
	var full := player.health
	var closed := await until_frame(gate, [7], 200)
	await frames(10)
	check("setup: it closed on you", closed)
	check("it hurts", player.health < full, "%d -> %d" % [full, player.health])
	check("and you are not left stuck inside", not gate.column().intersects(player.hit_box()),
		"%s vs %s" % [player.hit_box(), gate.column()])


func test_a_gate_never_shuts_on_someone_who_cannot_move() -> void:
	# 关门那一下的击退一般就把人推出去了；但倒地的人（双人）不吃击退、被定住的也动不了——
	# 合死那一刻还在门里的要直接挪出去，否则人就嵌在实心的门里了。
	# 只靠击退的话上一条用例照样绿（故障注入时发现的），所以这条把人定住单独测
	await reset_scene()
	var gate := place("res://scenes/trap_gate.tscn", 400) as BlastGate
	await until_frame(gate, [4])
	player.global_position = Vector2(412, STAND_Y)
	player.velocity = Vector2.ZERO
	player.set_physics_process(false)
	var closed := await until_frame(gate, [7], 200)
	await frames(2)
	check("setup: it closed", closed)
	check("you were moved out of the door", not gate.column().intersects(player.hit_box()),
		"%s vs %s" % [player.hit_box(), gate.column()])


# ---------------------------------------------------------------- 第二关里的摆法

func open_level_2(skin: SkinPack = null) -> void:
	await reset_scene(true, true, skin, 1, LEVEL_2)


func traps_of(kind: Variant) -> Array:
	return main.get_node("Traps").get_children().filter(func(n: Node) -> bool: return is_instance_of(n, kind))


func solids_of_level() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for node in main.get_node("Level").get_children():
		var slab := node as Platform
		if slab != null and not slab.one_way:
			out.append(Rect2(slab.position, slab.size))
	return out


func test_stage_2_has_presses_and_a_gate() -> void:
	# 第二关是分层的格子地图：液压机挂在各层楼板的天花板下，闸门是厂房二楼的出口
	await open_level_2()
	var presses := traps_of(HydraulicPress)
	var gates := traps_of(BlastGate)
	check("presses in a row", presses.size() >= 3, str(presses.size()))
	check("and a gate", gates.size() >= 1, str(gates.size()))
	var phases := {}
	var solids := solids_of_level()
	for press: HydraulicPress in presses:
		phases[press.phase] = true
		var on_floor := false
		for rect in solids:
			if absf(rect.position.y - (press.global_position.y + 64.0)) < 0.5 					and rect.position.x <= press.global_position.x + 16.0 and press.global_position.x + 16.0 <= rect.end.x:
				on_floor = true
		check("%s sits on a floor" % press.name, on_floor, str(press.global_position))
	check("the presses are out of step with each other", phases.size() == presses.size(), str(phases.keys()))


func test_you_cannot_jump_over_a_gate_or_round_a_press() -> void:
	# 门和压机都只有 64 高、一跳有 87——头顶要有实心的盖着，留下的缝最多一个人高（32）：
	# 那截缝在压机的杆子旁边、半空里，人站不进去
	await open_level_2()
	var solids := solids_of_level()
	for trap: Node2D in traps_of(HydraulicPress) + traps_of(BlastGate):
		var x := trap.global_position.x + 16.0
		var lowest := -INF
		for rect in solids:
			if rect.position.x <= x and x <= rect.end.x and rect.end.y <= trap.global_position.y + 0.5:
				lowest = maxf(lowest, rect.end.y)
		check("%s has a solid roof close over it" % trap.name, trap.global_position.y - lowest <= 32.0,
			"%.0f open above" % (trap.global_position.y - lowest))


func test_no_enemy_waits_inside_a_trap() -> void:
	await open_level_2()
	for trap: Node2D in traps_of(HydraulicPress) + traps_of(BlastGate):
		for enemy in enemies():
			var e := enemy as Enemy
			if e.global_position.y < 0.0:
				continue
			# 只看同一层的：楼上楼下的隔着楼板，撞不上
			if absf(e.global_position.y - (trap.global_position.y + 48.0)) > 48.0:
				continue
			check("%s is clear of %s" % [e.name, trap.name],
				absf(e.global_position.x - (trap.global_position.x + 16.0)) > 40.0, str(e.global_position))


func test_the_pack_draws_the_traps_and_the_rules_do_not_change() -> void:
	var rects := []
	for skin: SkinPack in [null, load(PACK) as SkinPack]:
		await reset_scene(false, false, skin)
		var press := place("res://scenes/trap_press.tscn", 400) as HydraulicPress
		var gate := place("res://scenes/trap_gate.tscn", 480) as BlastGate
		await until_frame(press, [3])
		rects.append([press.danger_rects(), gate.is_shut()])
		if skin != null:
			check("the press wears the pack's art", press.get_node("Visual") is TrapSpriteAppearance)
			check("so does the gate", gate.get_node("Visual") is TrapSpriteAppearance)
		else:
			check("the default skin draws blocks", press.get_node("Visual") is TrapBlocks)
	check("same danger zones in both skins", rects[0] == rects[1], str(rects))


# ---------------------------------------------------------------- 油桶、可打爆的箱子、传送带
# 2026-10 用户要的三样：「红色的桶当汽油桶放在敌人旁边，打一枪就炸（手雷那种爆炸）」、
# 「传送带」、「可打爆的箱子」。

const BARREL := "res://scenes/trap_barrel.tscn"
const CRATE := "res://scenes/trap_crate.tscn"


func barrel_at(x: float) -> ExplosiveBarrel:
	var barrel := (load(BARREL) as PackedScene).instantiate() as ExplosiveBarrel
	main.add_child(barrel)
	barrel.global_position = Vector2(x, GROUND_Y - ExplosiveBarrel.SIZE.y / 2.0)
	return barrel


func crate_at(x: float, bottom := GROUND_Y) -> BreakableCrate:
	var crate := (load(CRATE) as PackedScene).instantiate() as BreakableCrate
	main.add_child(crate)
	crate.global_position = Vector2(x, bottom - BreakableCrate.SIZE.y)
	return crate


## 一个站着不动、不还手的炮台（60 血，挨得住一桶），摆在 x 上。
func dummy_at(x: float) -> Enemy:
	await reset_scene(true)
	keep_only_enemies(["Turret1"])
	var turret := main.get_node("Enemies/Turret1") as Enemy
	turret.global_position = Vector2(x, STAND_Y)
	turret.set_physics_process(false)
	return turret


## 玩家站在 x 上朝右开一枪，等子弹飞一会儿。
func shoot_right_from(x: float, wait := 40) -> void:
	player.global_position = Vector2(x, STAND_Y)
	await frames(2)
	player._shoot(Vector2.RIGHT)
	await frames(wait)


func test_a_shot_barrel_blows_up_the_enemy_next_to_it() -> void:
	var turret := await dummy_at(360)
	var barrel := barrel_at(330)
	var full := turret.health
	await shoot_right_from(160)
	check("one bullet sets it off", not is_instance_valid(barrel) or barrel.exploded)
	check("the enemy next to it gets hurt far more than one bullet would", full - turret.health > SHOT * 2,
		"%d -> %d" % [full, turret.health])
	check("it went off as an explosion (the grenade's picture)", events.has(&"explosion"))
	check("and the barrel is gone", not is_instance_valid(barrel))


func test_the_blast_is_credited_to_the_shooter() -> void:
	var turret := await dummy_at(360)
	turret.health = 5
	barrel_at(330)
	var xp := player.progress.xp
	var money := player.progress.money
	await shoot_right_from(160)
	check("the enemy died", not is_instance_valid(turret) or turret.health <= 0)
	check("and the reward goes to the player who fired", player.progress.xp > xp or player.progress.money > money,
		"xp %d -> %d" % [xp, player.progress.xp])


func test_a_barrel_hurts_the_player_too() -> void:
	await reset_scene()
	var barrel := barrel_at(200)
	player.global_position = Vector2(180, STAND_Y)
	await frames(2)
	var full := player.health
	barrel.take_damage(SHOT, Vector2.INF, player)
	await frames(4)
	check("standing next to it when it goes hurts", player.health < full, "%d -> %d" % [full, player.health])


func test_from_far_enough_the_player_is_safe() -> void:
	await reset_scene()
	var barrel := barrel_at(300)
	player.global_position = Vector2(160, STAND_Y)
	await frames(2)
	var full := player.health
	barrel.take_damage(SHOT, Vector2.INF, player)
	await frames(4)
	check("140 px away is outside the blast", player.health == full, "%d -> %d" % [full, player.health])


func test_barrels_go_off_in_a_chain() -> void:
	await reset_scene()
	var first := barrel_at(300)
	var second := barrel_at(340)
	var third := barrel_at(380)
	var far := barrel_at(560)
	player.global_position = Vector2(100, STAND_Y)
	await frames(2)   # 刚加进来的桶要等物理那边登记上，爆炸才查得到它们
	first.take_damage(SHOT, Vector2.INF, player)
	await frames(6)
	check("the one next to it goes too", not is_instance_valid(second))
	check("and the next one along", not is_instance_valid(third))
	check("but not one far away", is_instance_valid(far) and not far.exploded)


func test_a_barrel_does_not_block_the_way() -> void:
	await reset_scene()
	var barrel := barrel_at(260)
	player.global_position = Vector2(200, STAND_Y)
	Input.action_press("move_right")
	await frames(40)
	release_all_input()
	check("the player walks past it", player.global_position.x > 300, "%.0f" % player.global_position.x)
	check("without setting it off", is_instance_valid(barrel) and not barrel.exploded)


func test_enemy_bullets_fly_through_a_barrel() -> void:
	# 敌人不会自己把身边的桶打爆：它们的子弹不找 enemy 层
	var shot := (load("res://scenes/enemy_bullet.tscn") as PackedScene).instantiate() as Area2D
	check("enemy bullets ignore the barrel's layer", shot.collision_mask & ExplosiveBarrel.ENEMY_LAYER == 0,
		str(shot.collision_mask))
	shot.free()


func test_a_crate_blocks_until_it_is_shot_apart() -> void:
	await reset_scene()
	var crate := crate_at(300)
	player.global_position = Vector2(240, STAND_Y)
	Input.action_press("move_right")
	await frames(40)
	release_all_input()
	check("a whole crate stops the player", player.global_position.x < 300, "%.0f" % player.global_position.x)
	for i in crate.toughness - 1:
		crate.take_damage(SHOT, Vector2.INF, player)
	await frames(2)
	check("one hit short it still stands", is_instance_valid(crate) and not crate.broken)
	crate.take_damage(SHOT, Vector2.INF, player)
	await frames(4)
	check("the last hit breaks it", crate.broken)
	Input.action_press("move_right")
	await frames(40)
	release_all_input()
	check("and then the way is open", player.global_position.x > 340, "%.0f" % player.global_position.x)


func test_real_bullets_break_a_crate() -> void:
	await reset_scene()
	var crate := crate_at(300)
	var needed := crate.toughness
	for i in needed - 1:
		await shoot_right_from(200, 12)
	check("%d shots leave it standing" % (needed - 1), is_instance_valid(crate) and not crate.broken)
	await shoot_right_from(200, 12)
	check("the %dth breaks it" % needed, not is_instance_valid(crate) or crate.broken)


func test_a_crate_is_cover() -> void:
	var turret := await dummy_at(380)
	crate_at(320)
	var full := turret.health
	await shoot_right_from(200)
	check("a bullet into the crate does not reach the enemy behind", turret.health == full,
		"%d -> %d" % [full, turret.health])


func test_a_conveyor_carries_whoever_stands_on_it() -> void:
	for speed: float in [70.0, -70.0]:
		await reset_scene()
		var belt: Platform = load("res://scenes/platform.tscn").instantiate()
		belt.size = Vector2(400, 16)
		belt.conveyor = speed
		belt.position = Vector2(200, 240)
		main.get_node("Level").add_child(belt)
		player.global_position = Vector2(400, 224)
		await frames(20)
		var x0 := player.global_position.x
		await frames(60)
		var moved := player.global_position.x - x0
		check("a belt at %+.0f carries an idle player that way" % speed, signf(moved) == signf(speed)
			and absf(moved) > 40.0, "%.1f" % moved)


# ---------------------------------------------------------------- 第五关（实验室）：地刺、毒气罐

const SPIKES := "res://scenes/trap_spikes.tscn"
const CAPSULE := "res://scenes/trap_capsule.tscn"


## 地刺摆在地面上（帧底边 = 地面 + 底座嵌进去的 4 行），玩家站在它正上方。
func spikes_at(x: float) -> SpikeTrap:
	var trap := (load(SPIKES) as PackedScene).instantiate() as SpikeTrap
	main.add_child(trap)
	trap.global_position = Vector2(x, GROUND_Y + 4.0 - SpikeTrap.SIZE.y)
	return trap


func capsule_at(x: float, bottom := GROUND_Y) -> BreakableCrate:
	var capsule := (load(CAPSULE) as PackedScene).instantiate() as BreakableCrate
	main.add_child(capsule)
	capsule.global_position = Vector2(x, bottom - capsule.size.y)
	return capsule


func test_resting_spikes_show_but_are_safe_to_stand_on() -> void:
	await reset_scene()
	var trap := spikes_at(400)
	check("setup: it starts at rest", trap.frame == SpikeTrap.REST and not trap.is_armed())
	# 平时露出一小截：远远就看得见这儿有地刺（用户定的：默认就要看得到，不另加警示）
	check("at rest the tips stick out of the floor where you can see them", trap.height() >= 4.0,
		"%.0f px" % trap.height())
	player.global_position = Vector2(416, STAND_Y)
	var full := player.health
	await frames(30)
	check("standing on resting spikes is safe", player.health == full, "%d -> %d" % [full, player.health])
	check("the base is flush with the floor (nothing to trip on)", player.global_position.y > STAND_Y - 1.0,
		"%.1f" % player.global_position.y)


func test_spikes_warn_before_they_strike() -> void:
	await reset_scene()
	var trap := spikes_at(400)
	# 预警是「先缩回去」：全缩进地面那一步就排在「弹出」前面，而且留够反应时间
	var warn := SpikeTrap.ORDER.find(SpikeTrap.WARN)
	var strike := SpikeTrap.ORDER.find(2)
	check("the spikes duck right before they strike", strike == warn + 1, "%d -> %d" % [warn, strike])
	check("and stay down long enough to react to", trap.durations[warn] >= 0.3, str(trap.durations[warn]))
	check("ducking really hides them (lower than at rest)",
		SpikeTrap.TIPS[SpikeTrap.WARN] > SpikeTrap.TIPS[SpikeTrap.REST],
		"%d vs %d" % [SpikeTrap.TIPS[SpikeTrap.WARN], SpikeTrap.TIPS[SpikeTrap.REST]])
	check("the warning itself does not hurt",
		SpikeTrap.SURFACE - SpikeTrap.TIPS[SpikeTrap.WARN] < SpikeTrap.HARMFUL)


func test_extended_spikes_hurt_whoever_stands_on_them() -> void:
	await reset_scene()
	var trap := spikes_at(400)
	player.global_position = Vector2(416, STAND_Y)
	await frames(2)
	var full := player.health
	var struck := await until_frame(trap, [2, 3])
	await frames(2)
	check("setup: the spikes came up", struck)
	check("they hurt a player standing on them", player.health < full, "%d -> %d" % [full, player.health])


func test_the_resting_stub_does_not_hurt() -> void:
	await reset_scene()
	var trap := spikes_at(400)
	trap.set_physics_process(false)
	trap.frame = SpikeTrap.REST
	check("the stub showing at rest is harmless (it only marks the trap)", not trap.is_armed(),
		"%.0f px" % trap.height())
	trap.frame = 3
	check("while full height is not", trap.is_armed(), "%.0f px" % trap.height())
	check("and full height reaches the feet of someone standing on the floor",
		trap.danger_rect().intersects(Rect2(408, GROUND_Y - 32.0, 24, 32)), str(trap.danger_rect()))


func test_spikes_block_nothing() -> void:
	await reset_scene()
	var trap := spikes_at(300)
	trap.set_physics_process(false)
	trap.frame = 3
	player.global_position = Vector2(240, STAND_Y)
	player.grant_invincibility(5.0)
	Input.action_press("move_right")
	await frames(40)
	release_all_input()
	check("you can walk straight through (they hurt, they don't wall you off)", player.global_position.x > 340,
		"%.0f" % player.global_position.x)
	check("nothing in it collides", trap.find_children("*", "CollisionObject2D", true, false).is_empty())


func test_a_capsule_blocks_until_it_is_shattered() -> void:
	await reset_scene()
	var capsule := capsule_at(300)
	player.global_position = Vector2(240, STAND_Y)
	Input.action_press("move_right")
	await frames(40)
	release_all_input()
	check("a whole capsule stops the player", player.global_position.x < 300, "%.0f" % player.global_position.x)
	for i in capsule.toughness - 1:
		capsule.take_damage(SHOT, Vector2.INF, player)
	await frames(2)
	check("one hit short it still stands", not capsule.broken)
	capsule.take_damage(SHOT, Vector2.INF, player)
	# 等过箱子那种「散架动画走完就删掉」的时间（0.5 秒）再看：碎片得还在
	await frames(60)
	check("the shards stay on the floor (the node is kept)", is_instance_valid(capsule))
	check("the last hit shattered it", is_instance_valid(capsule) and capsule.broken)
	Input.action_press("move_right")
	await frames(40)
	release_all_input()
	check("then you walk over the shards", player.global_position.x > 340, "%.0f" % player.global_position.x)


func test_one_capsule_can_be_jumped_but_two_cannot() -> void:
	# 单个 48 高，一跳翻得过去（不打也行，跳过去）；两个摞起来 96，比一跳高——非打不可
	await reset_scene()
	var capsule := capsule_at(300)
	check("setup: a capsule is 48 tall", is_equal_approx(capsule.size.y, 48.0), str(capsule.size))
	player.global_position = Vector2(220, STAND_Y)
	Input.action_press("move_right")
	Input.action_press("jump")
	await frames(70)
	release_all_input()
	check("one capsule is jumped over", player.global_position.x > 340, "%.0f" % player.global_position.x)
	await reset_scene()
	capsule_at(300)
	capsule_at(300, GROUND_Y - 48.0)
	player.global_position = Vector2(220, STAND_Y)
	Input.action_press("move_right")
	Input.action_press("jump")
	await frames(70)
	release_all_input()
	check("two stacked are not", player.global_position.x < 300, "%.0f" % player.global_position.x)
