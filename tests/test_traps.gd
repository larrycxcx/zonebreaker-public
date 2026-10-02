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


func test_stage_2_has_a_press_hall_and_two_gates() -> void:
	await open_level_2()
	var presses := traps_of(HydraulicPress)
	var gates := traps_of(BlastGate)
	check("presses in a row", presses.size() >= 3, str(presses.size()))
	check("and two gates", gates.size() >= 2, str(gates.size()))
	var phases := {}
	for press: HydraulicPress in presses:
		phases[press.phase] = true
		check("%s sits on the ground" % press.name, absf(press.global_position.y + 64.0 - GROUND_Y) < 0.5)
	check("the presses are out of step with each other", phases.size() == presses.size(), str(phases.keys()))


func test_you_cannot_jump_over_a_gate_or_round_a_press() -> void:
	# 门和压机都只有 64 高、一跳有 87——上面那截墙 / 天花板要一直通到画面顶
	await open_level_2()
	var level := main.get_node("Level")
	for trap: Node2D in traps_of(HydraulicPress) + traps_of(BlastGate):
		var x := trap.global_position.x + 16.0
		var roof: Platform = null
		for node in level.get_children():
			var slab := node as Platform
			if slab != null and not slab.one_way and slab.position.x <= x and x <= slab.position.x + slab.size.x \
					and slab.position.y <= 0.0 and slab.position.y + slab.size.y >= trap.global_position.y - 0.5:
				roof = slab
		check("%s has a solid roof right down to it" % trap.name, roof != null)


func test_no_enemy_waits_inside_a_trap() -> void:
	await open_level_2()
	for trap: Node2D in traps_of(HydraulicPress) + traps_of(BlastGate):
		for enemy in enemies():
			var e := enemy as Enemy
			if e.global_position.y < 0.0:
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
