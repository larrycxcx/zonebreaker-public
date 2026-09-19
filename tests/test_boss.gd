extends GameTest
## Boss：关卡里的其它敌人都是普通敌人（直接继承 Enemy），Boss 继承 Boss。
## 规则：进入屏幕才出场（之前待机不行动）；出场时报告 boss_appear、右上角显示头像和血条；
## 终极武器定住 Boss、清掉它的子弹、对它造成 ultimate_damage 点伤害，但不会直接消灭它。
## 具体攻击方式每个 Boss 不同，这里只测通用规则（占位 Boss 的站桩连发除外）。

const ENEMY_BULLET_SCENE := "res://scenes/enemy_bullet.tscn"

var boss: Boss


## 只留 Boss（x=616），玩家在关卡最左边，Boss 在屏幕外。
func start(extra := []) -> void:
	await reset_scene(true)
	keep_only_enemies(["Boss"] + extra)
	boss = main.get_node("Enemies/Boss")
	await frames(5)


## 把玩家放到 x，等摄像机跟过去。
func go_to(x: float) -> void:
	player.global_position = Vector2(x, 152)
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
	for enemy in main.get_node("Enemies").get_children():
		if enemy is Boss:
			bosses.append(enemy.name)
		else:
			check("%s is a normal enemy" % enemy.name, enemy is Enemy)
	check("the level has one boss", bosses == [&"Boss"], str(bosses))
	var b: Boss = main.get_node("Enemies/Boss")
	check("boss has a portrait", b.portrait != null)
	check("boss is much tougher than normal enemies", b.max_health >= 30)
	check("one ultimate does not kill it", b.ultimate_damage < b.max_health)


func test_dormant_until_on_screen() -> void:
	await start()
	# 把射程放大到整个关卡：如果它在屏幕外也在行动，就一定会开火
	boss.detect_range = 1000.0
	await go_to(300) # 屏幕 = x 140..460，Boss 在 616
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
	await go_to(560)
	check("on screen: appeared", boss.has_appeared)
	check("boss_appear reported once", count(&"boss_appear") == 1)
	check("appear sound played", played.has(&"boss_appear"))
	Sfx.sound_played.disconnect(on_played)
	check("HUD bar shown", bar().visible)
	check("HUD bar in the top-right corner", bar().position.x > 200 and bar().position.y < 20)
	var portrait: TextureRect = main.get_node("HUD/BossBar/Portrait")
	check("HUD shows the boss portrait", portrait.texture == boss.portrait)
	check("health bar full", is_equal_approx(fill_ratio(), 1.0))
	# 离开再回来不会再出场一次
	await go_to(40)
	await go_to(560)
	check("appears only once", count(&"boss_appear") == 1)
	check("bar stays up while the boss lives", bar().visible)


func test_attacks_after_appearing() -> void:
	await start()
	await go_to(460) # 屏幕内、射程 200 内
	var fired := false
	for i in 150:
		await frames(1)
		if not bullets(16).is_empty():
			fired = true
			break
	check("placeholder boss fires at the player", fired)


func test_health_bar_follows_damage() -> void:
	await start()
	await go_to(560)
	boss.take_damage(10)
	check("bar shrinks with damage", is_equal_approx(fill_ratio(), 30.0 / 40.0), str(fill_ratio()))
	boss.take_damage(100)
	await frames(2)
	check("boss dies", not is_instance_valid(boss))
	check("bar hidden after the boss dies", not bar().visible)


func test_ultimate_freezes_clears_and_damages() -> void:
	await start(["Turret1"])
	await go_to(460)
	var turret: Enemy = main.get_node("Enemies/Turret1")
	for x in [480.0, 600.0]:
		var bullet: Bullet = load(ENEMY_BULLET_SCENE).instantiate()
		bullet.launch(Vector2.LEFT)
		main.add_child(bullet)
		bullet.global_position = Vector2(x, 120)
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
	check("boss takes ultimate_damage", is_instance_valid(boss) and boss.health == hp - boss.ultimate_damage)
	check("HUD bar updated", is_equal_approx(fill_ratio(), float(hp - boss.ultimate_damage) / boss.max_health))
	check("normal enemy on screen is still destroyed", not is_instance_valid(turret))


func test_ultimate_can_finish_a_weak_boss() -> void:
	await start()
	await go_to(460)
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
