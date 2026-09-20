extends GameTest
## 终极武器：K / 手柄 Y 瞬时发动，每条命 4 次。
## 发动时清掉所有敌人子弹、整个场景定格 2 秒（玩家和敌人都不能动），玩家无敌到恢复后 0.5 秒；
## 定格结束时消灭发动那一刻屏幕内的所有敌人（不管血量），屏幕外的不受影响。

const ENEMY_BULLET_SCENE := "res://scenes/enemy_bullet.tscn"


## 玩家站在 x=200（摄像机在关卡最左，屏幕 = x 0..320）。
## 只留两个炮台（12 血，最耐打）：Turret2 挪到屏幕内，Turret1 留在 x=1160 屏幕外。
func start() -> void:
	await reset_scene(true)
	keep_only_enemies(["Turret1", "Turret2"])
	player.global_position = Vector2(200, 304)
	player.velocity = Vector2.ZERO
	await frames(10)


func use_ultimate() -> void:
	Input.action_press("ultimate")
	await frames(2)
	Input.action_release("ultimate")


## 等定格结束，返回定格持续了多少个物理帧（超过 limit 帧还没结束就返回 -1）。
func wait_for_unpause(limit := 600) -> int:
	for i in limit:
		if not tree.paused:
			return i
		await tree.physics_frame
	return -1


func count(event: StringName) -> int:
	return events.filter(func(e): return e == event).size()


func test_config_and_bindings() -> void:
	await start()
	check("player has an ultimate weapon", player.ultimate_weapon != null)
	check("2 uses per life", player.ultimate_weapon.max_ammo == 2 and player.ultimate_ammo() == 2)
	check("ultimate: K", keyboard_keys("ultimate").has(KEY_K))
	check("ultimate: gamepad Y", InputMap.action_get_events("ultimate").any(
		func(e): return e is InputEventJoypadButton and e.button_index == JOY_BUTTON_Y))
	check("not part of the weapon switch cycle", not player.weapons.has(player.ultimate_weapon))
	var row: HBoxContainer = main.get_node("HUD/UltimateRow")
	check("HUD shows 2 ultimate pips", row.get_child_count() == 2)


func test_freeze_clears_bullets_and_kills_on_screen_enemies() -> void:
	await start()
	var near: Enemy = main.get_node("Enemies/Turret2")
	var far: Enemy = main.get_node("Enemies/Turret1")
	near.global_position = Vector2(400, 306)
	await frames(5)
	# 屏幕内、屏幕外各放几颗敌人子弹，再放一颗玩家子弹
	for x in [120.0, 500.0, 1000.0]:
		var bullet: Bullet = load(ENEMY_BULLET_SCENE).instantiate()
		bullet.launch(Vector2.LEFT)
		main.add_child(bullet)
		bullet.global_position = Vector2(x, 100)
	player._shoot(Vector2.RIGHT)
	await frames(1)
	check("setup: enemy bullets on and off screen", bullets(16).size() >= 3, "%d" % bullets(16).size())
	var weapon_before := player.current_weapon
	var near_pos := near.global_position
	await use_ultimate()
	check("tree is paused", tree.paused)
	check("ultimate_start reported", count(&"ultimate_start") == 1)
	check("one use spent", player.ultimate_ammo() == 1)
	var pips: Array = main.get_node("HUD/UltimateRow").get_children()
	check("HUD: one pip dimmed", pips[0].color != pips[1].color)
	await frames(1)
	check("every enemy bullet is gone (on and off screen)", bullets(16).is_empty(), "%d left" % bullets(16).size())
	check("player bullets are kept", bullets(4).size() >= 1)
	check("current weapon unchanged", player.current_weapon == weapon_before)

	# 定格期间：按键无效、谁都不动、敌人不开火
	var player_pos := player.global_position
	Input.action_press("move_right")
	Input.action_press("shoot")
	await frames(60)
	check("player frozen even while pressing move", player.global_position == player_pos)
	check("enemy frozen", near.global_position == near_pos)
	check("nobody fires during the freeze", bullets(16).is_empty())
	check("enemies still alive during the freeze", is_instance_valid(near) and near.health == near.max_health)
	Input.action_release("move_right")
	Input.action_release("shoot")

	var took: int = await wait_for_unpause()
	# 已经等了约 62 帧，总共应该在 2 秒（120 帧）左右
	check("freeze lasts about 2 seconds", took > 40 and took < 80, "%d more frames" % took)
	await frames(2)
	check("on-screen enemy destroyed regardless of health", not is_instance_valid(near))
	check("off-screen enemy untouched", is_instance_valid(far) and far.health == far.max_health)
	check("ultimate_blast reported", count(&"ultimate_blast") == 1)
	check("enemy_death reported", count(&"enemy_death") == 1)
	# 恢复后玩家能正常行动
	var x0 := player.global_position.x
	Input.action_press("move_right")
	await frames(10)
	Input.action_release("move_right")
	check("player moves again after the freeze", player.global_position.x > x0 + 10)


func test_flyer_on_screen_is_hit_too() -> void:
	await reset_scene(true)
	keep_only_enemies(["FlyerE", "Turret1"])
	player.global_position = Vector2(200, 304)
	await frames(10)
	var flyer: Enemy = main.get_node("Enemies/FlyerE")
	await use_ultimate()
	await wait_for_unpause()
	await frames(2)
	check("flyer overhead on screen destroyed", not is_instance_valid(flyer))


func test_invincible_during_and_just_after() -> void:
	await start()
	var hp := player.health
	await use_ultimate()
	await frames(10)
	player.take_damage(1)
	check("no damage during the freeze", player.health == hp)
	await wait_for_unpause()
	await frames(10) # 恢复后约 0.17 秒
	player.take_damage(1)
	check("still invincible right after the freeze", player.health == hp)
	check("shield does not blink the player", player.get_node("Visual").visible)
	await frames(30) # 0.5 秒已过
	player.take_damage(1)
	check("can be hurt again afterwards", player.health == hp - 1)


func test_limited_uses() -> void:
	await start()
	for i in 2:
		await use_ultimate()
		await wait_for_unpause()
		await frames(2)
	check("two uses spent", player.ultimate_ammo() == 0)
	check("two activations", count(&"ultimate_start") == 2)
	await use_ultimate()
	await frames(2)
	check("third press does nothing", not tree.paused and count(&"ultimate_start") == 2)
	var pips: Array = main.get_node("HUD/UltimateRow").get_children()
	check("HUD: both pips dimmed", pips[0].color == pips[1].color and pips[0].color != player.ultimate_weapon.hud_color)
	# 死后重载本关：新的一条命，次数补满
	await start()
	check("refilled on a new life", player.ultimate_ammo() == 2)


func test_usable_lying_down_and_in_air() -> void:
	await start()
	Input.action_press("crouch")
	Input.action_press("move_right")
	await frames(10)
	check("setup: crawling", player.is_crouching)
	await use_ultimate()
	check("works while crawling", tree.paused)
	await wait_for_unpause()
	release_all_input()
	await frames(20)
	Input.action_press("jump")
	await frames(8)
	check("setup: airborne", not player.is_on_floor())
	await use_ultimate()
	check("works in the air", tree.paused)
	var y := player.global_position.y
	await frames(30)
	check("frozen in mid-air", player.global_position.y == y)
	await wait_for_unpause()


func test_sounds_play_during_the_freeze() -> void:
	await start()
	var played := []
	var on_played := func(event: StringName, _stream: AudioStream) -> void: played.append(event)
	Sfx.sound_played.connect(on_played)
	await use_ultimate()
	await frames(2)
	check("start sound plays while paused", played.has(&"ultimate_start"))
	check("Sfx keeps running during pause", Sfx.can_process())
	await wait_for_unpause()
	await frames(2)
	Sfx.sound_played.disconnect(on_played)
	check("blast sound plays", played.has(&"ultimate_blast"))
