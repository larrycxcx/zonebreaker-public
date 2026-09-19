extends GameTest
## 武器结构：玩家的武器是一个资源文件（Weapon），运行时状态在武器槽（WeaponSlot）里。
## 这组用例确认「只换武器文件就能改变开火行为」——射速、连发/单发、弹药上限、音效事件都来自武器，不在玩家代码里。

const OPEN_X := 200.0


func start() -> void:
	await reset_scene()
	player.global_position = Vector2(OPEN_X, 152)
	player.velocity = Vector2.ZERO
	await frames(10)


## 一把只在测试里用的武器，发射普通子弹。
func make_weapon(cooldown: float, automatic := true, max_ammo := -1, fire_event := &"player_shoot") -> Weapon:
	var weapon := Weapon.new()
	weapon.projectile = load("res://scenes/bullet.tscn")
	weapon.cooldown = cooldown
	weapon.automatic = automatic
	weapon.max_ammo = max_ammo
	weapon.fire_event = fire_event
	return weapon


## 按住开火键若干帧，返回这段时间里开了几枪。
## 数的是开火事件，不是场上的子弹：子弹能飞 1.2 秒，前几次开的枪还在场上，按子弹数会重复算。
func hold_fire(frame_count: int, fire_event := &"player_shoot") -> int:
	var before := events.count(fire_event)
	Input.action_press("shoot")
	await frames(frame_count)
	Input.action_release("shoot")
	return events.count(fire_event) - before


func test_the_default_gun_is_the_rifle_resource() -> void:
	await start()
	var rifle := player.primary_weapon
	check("the primary weapon comes from weapons/rifle.tres", rifle != null and rifle.resource_path == "res://weapons/rifle.tres", rifle.resource_path if rifle else "none")
	check("it fires ordinary bullets", rifle.projectile.resource_path == "res://scenes/bullet.tscn")
	check("0.15s between shots, fully automatic", rifle.cooldown == 0.15 and rifle.automatic)
	check("unlimited ammo", rifle.max_ammo == -1 and player._primary.ammo == -1)
	check("reports player_shoot", rifle.fire_event == &"player_shoot")


func test_fire_rate_comes_from_the_weapon() -> void:
	await start()
	var rifle_shots := await hold_fire(60)
	await frames(80)
	player.equip_primary(make_weapon(0.5))
	var slow_shots := await hold_fire(60)
	check("the rifle fires ~7 times a second", rifle_shots >= 6 and rifle_shots <= 8, str(rifle_shots))
	check("a 0.5s weapon fires 2-3 times a second", slow_shots >= 2 and slow_shots <= 3, str(slow_shots))


func test_semi_automatic_weapons_need_a_press_per_shot() -> void:
	await start()
	player.equip_primary(make_weapon(0.05, false))
	var held := await hold_fire(60)
	check("holding fire shoots once", held == 1, str(held))
	await frames(5)
	var taps := 0
	for i in 3:
		taps += await hold_fire(3)
		await frames(5)
	check("each new press shoots again", taps == 3, str(taps))


func test_limited_ammo_runs_out() -> void:
	await start()
	var weapon := make_weapon(0.1, true, 2)
	var changes := []
	player._primary.ammo_changed.connect(func(ammo: int, max_ammo: int): changes.append([ammo, max_ammo]))
	player.equip_primary(weapon)
	var shots := await hold_fire(60)
	check("a 2-round weapon fires exactly twice", shots == 2, str(shots))
	check("ammo is empty", player._primary.ammo == 0 and not player._primary.is_ready())
	check("ammo_changed tracks it: full, then 1, then 0", changes == [[2, 2], [1, 2], [0, 2]], str(changes))
	player.equip_primary(weapon)
	check("equipping again refills it", player._primary.ammo == 2 and player._primary.is_ready())


func test_the_fire_event_comes_from_the_weapon() -> void:
	await start()
	player.equip_primary(make_weapon(0.15, true, -1, &"custom_fire"))
	await hold_fire(3)
	check("the weapon's own event is reported", events.has(&"custom_fire") and not events.has(&"player_shoot"), str(events))


func test_aiming_still_applies_to_any_weapon() -> void:
	await start()
	player.equip_primary(make_weapon(0.3))
	Input.action_press("aim_up")
	Input.action_press("move_right")
	await frames(2)
	player._primary.cooldown_left = 0.0
	Input.action_press("shoot")
	await frames(1)
	Input.action_release("shoot")
	var shots := bullets(4)
	check("a swapped-in weapon still follows the 8-way aim", shots.size() == 1 and shots[0].direction.x > 0.0 and shots[0].direction.y < 0.0, str(shots.map(func(b): return b.direction)))
