extends GameTest
## 手雷与武器切换：Shift / 手柄 X 在 [步枪, 手雷] 之间切换，J / RT 用当前武器开火。
## 手雷规则：直接砸中敌人立刻爆炸；撞到地面/墙弹一下，再碰到就爆炸；最长 1.5 秒保底爆炸；
## 伤害中心/直接命中最高、往边缘递减、范围外为零；不伤自己；墙挡爆炸；单向平台上穿下落；不限数量。

const GRENADE_SCENE := "res://scenes/grenade.tscn"


func start(x := 200.0) -> void:
	await reset_scene()
	player.global_position = Vector2(x, 304)
	player.velocity = Vector2.ZERO
	await frames(10)


func grenades() -> Array:
	return main.get_children().filter(func(c): return c is Grenade)


## 切到手雷，朝当前瞄准方向扔一颗，返回它。
func throw_one() -> Grenade:
	if player.current_weapon != 1:
		player.switch_weapon()
	player.current_slot().cooldown_left = 0.0
	# 手雷每按一次扔一颗，看的是「刚按下」；用 action_press 模拟时它在下一个物理帧才成立，
	# 所以要按住两帧——只按一帧就松开，轮到判定时键已经松了，什么也扔不出去。
	Input.action_press("shoot")
	await frames(2)
	Input.action_release("shoot")
	var found := grenades()
	return found[-1] if not found.is_empty() else null


## 直接在某处放一颗手雷（不经过扔的动作），用来精确摆几何关系。
func spawn_grenade(pos: Vector2, velocity := Vector2.ZERO, gravity := -1.0) -> Grenade:
	var grenade: Grenade = load(GRENADE_SCENE).instantiate()
	grenade.launch(Vector2.DOWN)
	grenade.velocity = velocity
	if gravity >= 0.0:
		grenade.gravity = gravity
	main.add_child(grenade)
	grenade.global_position = pos
	return grenade


## 记下这颗手雷爆炸的位置（和是否弹过）。
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


## 把一个巡逻兵摆在地面 x 处、站定不动、血量调高，用来量伤害。
func dummy(walker_name: String, x: float, health := 100) -> EnemyWalker:
	var w: EnemyWalker = main.get_node("Enemies/" + walker_name)
	w.global_position = Vector2(x, 306)
	w.move_speed = 0.0
	w.max_health = health
	w.health = health
	w.set_physics_process(false)
	return w


# ---------------------------------------------------------------- 武器与切换

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
	player.switch_weapon() # 回到步枪
	check("the rifle is ready right away", player.current_slot().is_ready())
	player.switch_weapon() # 再切回手雷
	check("the grenade is still cooling down", not player.current_slot().is_ready() and player.current_slot().cooldown_left <= grenade_cooldown, "%.2f" % player.current_slot().cooldown_left)
	# 拿着步枪等 0.6 秒：放在一边的手雷也在冷却，切回来就能扔。
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


# ---------------------------------------------------------------- 飞行与爆炸方式

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
	# 悬空不动的手雷（没有重力、不碰任何东西）：1.5 秒到了也要炸。
	var grenade := spawn_grenade(Vector2(400, 240), Vector2.ZERO, 0.0)
	var info := track(grenade)
	var frame := 0
	while info["exploded_at"] == null and frame < 150:
		await tree.physics_frame
		frame += 1
	info["disconnect"].call()
	check("a grenade that never lands explodes after 1.5s", info["exploded_at"] != null and frame >= 88 and frame <= 92, "frame %d" % frame)


# ---------------------------------------------------------------- 伤害

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
	# 线性衰减后取整：边缘附近那一点算出来是一发多一点
	check("near the edge: about 1 shot", 100 - near_edge.health >= SHOT and 100 - near_edge.health < SHOT * 3 / 2, str(100 - near_edge.health))
	check("outside the blast: nothing", d.health == d_health, str(d_health - d.health))


func test_walls_block_the_blast() -> void:
	await reset_scene(true, true)
	keep_only_enemies(["WalkerA", "WalkerB"])
	# Wall2：x 800..408，高 56。爆炸在墙左边，两个巡逻兵离爆炸一样远（40px），一个在墙这边、一个在墙后面。
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
	# 贴着 Wall2 左边往右扔：手雷撞墙弹回来，不会穿过去。
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


# ---------------------------------------------------------------- 实战

func test_lob_over_a_wall_onto_the_turret() -> void:
	# 在 Turret1（x=1160）前面搭一堵 72px 高的墙（x 1080..548）。玩家在墙左边往前扔，手雷越过墙砸到炮台。
	await reset_scene(true)
	keep_only_enemies(["Turret1"])
	# BossPlatform（x 992..552，y=248）会接住抛过去的手雷，这条用例只关心墙，先挪开它。
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
	# 站在 Platform1（单向，x 160..128，顶面 y=256）正下方往正上方扔：穿过平台飞上去，落回来时落在平台上面炸。
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
