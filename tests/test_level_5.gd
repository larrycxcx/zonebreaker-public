extends "res://tests/layered_checks.gd"
## 正式第五关（`scenes/level_5.tscn`，实验室）——分层的格子地图（`tools/level5_map.py`，砖用 `THEMES["lab"]`）。
## 分层关共用的检查在 `layered_checks.gd`；这里只写**这一关独有的**：
## 倒挂在天花板上的发射器、中段小 Boss 的房间（门）、生化舱那片空地，以及拿真规则跑几处必须绕的路。

const LEVEL_INFO := "res://levels/level_5.tres"


func level_path() -> String:
	return "res://scenes/level_5.tscn"


func level_stage() -> LevelInfo:
	return load(LEVEL_INFO) as LevelInfo


func zone() -> String:
	return "lab"


## 关底 Boss（打死了才通关的那个）。中段的小 Boss 也是 `Boss`，但它的 `ends_level` 关着。
func the_boss() -> Boss:
	for node in main.get_node("Enemies").get_children():
		if node is Boss and (node as Boss).ends_level:
			return node
	return null


func the_gunner() -> BossGunner:
	for node in main.get_node("Enemies").get_children():
		if node is BossGunner:
			return node
	return null


func doors() -> Array[ArenaDoor]:
	var out: Array[ArenaDoor] = []
	for node in main.get_node("Traps").get_children():
		if node is ArenaDoor:
			out.append(node)
	return out


## 这一关两道跳不过去的坑（沉降池、地刺阵后面那道），别的地方是墙和毒气罐在逼人绕路。
func min_pits() -> int:
	return 2


func test_it_is_the_fifth_stage_in_the_catalog() -> void:
	if needs_art(): return
	var info := load(LEVEL_INFO) as LevelInfo
	check("it points at this scene", info.scene_path == level_path(), info.scene_path)
	check("and it brings the lab pack", info.skin != null and info.skin.resource_path.contains("lab"), str(info.skin))
	var levels := Catalog.levels()
	check("the catalog picks it up as the fifth one", levels.size() >= 5 and levels[4].scene_path == level_path(),
		"" if levels.size() < 5 else levels[4].scene_path)


func test_this_stage_brings_its_own_cast() -> void:
	await open_level()
	var kinds := {}
	for enemy in enemies():
		kinds[enemy.skin_key] = int(kinds.get(enemy.skin_key, 0)) + 1
	var wrong: Array[String] = []
	for key: StringName in kinds:
		if not String(key).begins_with("5_"):
			wrong.append(String(key))
	check("every enemy here belongs to stage 5", wrong.is_empty(), str(wrong))
	for key in [&"5_a", &"5_b", &"5_c", &"5_d", &"5_e", &"5_f", &"5_midboss", &"5_boss"]:
		check("%s shows up" % key, kinds.has(key), str(kinds.keys()))
	check("one mid-level boss, one stage boss", kinds.get(&"5_midboss", 0) == 1 and kinds.get(&"5_boss", 0) == 1,
		str(kinds))


## 基类那条认「最后一个 Boss」；这一关中段还有个小 Boss，得认打死了才通关的那个。
func test_the_boss_waits_at_the_far_end() -> void:
	await open_level()
	var boss := the_boss()
	check("there is a stage boss", boss != null)
	check("and it is in the last stretch", boss != null and boss.position.x > 12800.0 - 1280.0,
		"" if boss == null else str(boss.position.x))
	var gunner := the_gunner()
	check("the mid-level boss sits in the middle of the stage", gunner != null
		and gunner.position.x > 12800.0 * 0.4 and gunner.position.x < 12800.0 * 0.7,
		"" if gunner == null else str(gunner.position.x))


func test_the_ceiling_emitters_hang_right_under_a_ceiling() -> void:
	# 5-F 一动不动地倒挂着：吊架顶边（原点往上 MOUNT）正好贴着一块实心的底边
	await open_level()
	var solids := solid_rects()
	var count := 0
	for enemy in enemies():
		if not enemy is EnemyCeilingEmitter:
			continue
		count += 1
		var top: float = enemy.position.y - EnemyCeilingEmitter.MOUNT
		var hung := false
		for rect in solids:
			if absf(rect.end.y - top) < 0.5 and rect.position.x <= enemy.position.x and enemy.position.x <= rect.end.x:
				hung = true
		check("%s hangs from a ceiling" % enemy.name, hung, "mount top %.0f at x %.0f" % [top, enemy.position.x])
	check("setup: there are emitters", count >= 8, str(count))
	await frames(60)
	for enemy in enemies():
		if enemy is EnemyCeilingEmitter:
			check("%s stays where it hangs" % enemy.name, absf(enemy.velocity.y) < 0.01)


func test_the_emitters_hang_high_enough_to_walk_under() -> void:
	# 人从底下走过去不能撞上它：它的身子底边离下面那层地面至少一个站着的人高
	await open_level()
	var faces := surfaces()
	for enemy in enemies():
		if not enemy is EnemyCeilingEmitter:
			continue
		var bottom: float = enemy.position.y + 12.0
		var floor_y := INF
		for face in faces:
			if face[0] <= enemy.position.x and enemy.position.x <= face[1] and face[2] > bottom:
				floor_y = minf(floor_y, face[2])
		check("%s leaves room to pass underneath" % enemy.name, floor_y - bottom >= 40.0,
			"%.0f" % (floor_y - bottom))


# ---------------------------------------------------------------- 小 Boss 的房间

func test_the_mid_boss_is_locked_in_a_room() -> void:
	await open_level()
	var found := doors()
	check("two doors", found.size() == 2, str(found.size()))
	if found.size() != 2:
		return
	var entry: ArenaDoor = found[0] if not found[0].exit_door else found[1]
	var exit: ArenaDoor = found[1] if entry == found[0] else found[0]
	check("one entry, one exit", not entry.exit_door and exit.exit_door)
	check("the entry starts open, the exit shut", entry.is_open and not exit.is_open)
	var gunner := the_gunner()
	check("the gunner is between them", gunner != null and entry.position.x < gunner.position.x
		and gunner.position.x < exit.position.x)
	check("and its whole roaming range fits in the room", gunner != null
		and gunner.position.x - gunner.roam_range > entry.position.x + ArenaDoor.SIZE.x
		and gunner.position.x + gunner.roam_range < exit.position.x)
	# 两边的墙一直通到画面顶：从房顶上绕不过去
	for door in [entry, exit]:
		var covered := 0.0
		for rect in solid_rects():
			if rect.position.x <= door.position.x and door.position.x + 32.0 <= rect.end.x \
					and rect.end.y <= door.position.y + 0.5:
				covered += rect.size.y
		check("%s has wall all the way up" % door.name, covered >= door.position.y - 0.5,
			"%.0f of %.0f" % [covered, door.position.y])


func test_walking_in_locks_you_in_and_killing_it_lets_you_out() -> void:
	await open_level()
	var gunner := the_gunner()
	keep_only_enemies([String(gunner.name)])
	var found := doors()
	var entry: ArenaDoor = found[0] if not found[0].exit_door else found[1]
	var exit: ArenaDoor = found[1] if entry == found[0] else found[0]
	player.grant_invincibility(60.0)
	player.global_position = Vector2(entry.position.x - 80.0, GROUND_Y - 16.0)
	snap_camera()
	await frames(10)
	check("you are still outside: the door stays open", entry.is_open)
	Input.action_press(&"move_right")
	for i in 200:
		await tree.physics_frame
		if not entry.is_open:
			break
	release_all_input()
	check("it has shown up by now", gunner.has_appeared)
	check("once you are in, the door shuts behind you", not entry.is_open)
	check("with you inside", player.global_position.x > entry.position.x + 32.0, "%.0f" % player.global_position.x)
	# 往回走：出不去
	Input.action_press(&"move_left")
	Input.action_press(&"jump")
	await frames(90)
	release_all_input()
	check("you cannot walk back out", player.global_position.x > entry.position.x + 32.0,
		"%.0f" % player.global_position.x)
	check("the exit stays shut while it lives", not exit.is_open)
	gunner.take_damage(gunner.health, Vector2.INF, player)
	await frames(40)
	check("killed: the exit opens", exit.is_open)
	check("but the stage is not over", not events.has(&"level_clear"), str(events))
	player.global_position = Vector2(exit.position.x - 40.0, GROUND_Y - 16.0)
	await frames(2)
	Input.action_press(&"move_right")
	await frames(60)
	release_all_input()
	check("and you walk out the far side", player.global_position.x > exit.position.x + 32.0,
		"%.0f" % player.global_position.x)


# ---------------------------------------------------------------- 生化舱那片空地

func test_the_pod_has_open_ground_to_sweep() -> void:
	# 横扫激光一路压到地面上站着的人胸口：墙会挡住它（也挡视线），地上有坑扫完人也没处站
	await open_level()
	var boss := the_boss() as BossPod
	check("the stage boss is the pod", boss != null)
	if boss == null:
		return
	var reach := boss.roam_range + 200.0
	for pit in pits():
		check("no pit in its arena (%.0f)" % pit.x, pit.y < boss.position.x - reach or pit.x > boss.position.x + reach)
	for rect in solid_rects():
		if rect.end.y <= GROUND_Y + 0.5 and rect.position.y > 0.0 \
				and rect.end.x > boss.position.x - reach and rect.position.x < boss.position.x + reach:
			check("nothing solid stands in the arena", false, "%s" % rect)
	check("it floats over the ground", boss.position.y < GROUND_Y - 100.0, "%.0f" % boss.position.y)


# ---------------------------------------------------------------- 必须绕的路，拿真规则跑一遍

func push_right(frames_held := 150, jumping := true) -> void:
	Input.action_press(&"move_right")
	if jumping:
		Input.action_press(&"jump")
	await frames(frames_held)
	release_all_input()


func test_the_first_building_is_a_dead_end_downstairs() -> void:
	# 第 1 段：实验楼一楼走到头是墙（墙后是毒气罐的仓库），顺梯子上二楼
	await open_empty()
	player.global_position = Vector2(col_x(1, 60), GROUND_Y - 16.0)
	await frames(3)
	await push_right()
	check("walking and jumping right gets you nowhere", player.global_position.x < col_x(1, 70),
		"x %.0f" % player.global_position.x)


func test_the_settling_pit_cannot_be_jumped_from_the_ground() -> void:
	# 第 4 段：地面断开 32 格，助跑跳过不去，只能爬上去踩悬着的台子
	await open_empty()
	player.global_position = Vector2(col_x(4, 12), GROUND_Y - 16.0)
	await frames(3)
	var hp := player.health
	Input.action_press(&"move_right")
	Input.action_press(&"sprint")
	await frames(30)
	Input.action_press(&"jump")
	await frames(90)
	release_all_input()
	await frames(30)
	check("you never make it across", player.global_position.x < col_x(4, 56) or player.health < hp,
		"x %.0f, hp %d -> %d" % [player.global_position.x, hp, player.health])


func test_the_isolation_corridor_is_sealed_by_capsules() -> void:
	# 第 9 段：3 格高的通道里一只毒气罐就把路堵满了，打碎才过得去
	await open_empty()
	player.global_position = Vector2(col_x(9, 20), GROUND_Y - 16.0)
	await frames(3)
	await push_right(120)
	check("the capsule stops you", player.global_position.x < col_x(9, 26), "x %.0f" % player.global_position.x)
	for node in main.get_node("Traps").get_children():
		if node is BreakableCrate and absf(node.position.x - col_x(9, 26)) < 1.0:
			for i in node.toughness:
				node.take_damage(10, Vector2.INF, player)
	await frames(80)
	await push_right(60, false)
	check("broken: you walk through", player.global_position.x > col_x(9, 28), "x %.0f" % player.global_position.x)


func test_in_co_op_the_door_waits_for_both_players() -> void:
	# 双人时一个人进去了、另一个还在门外：门得等两个人都进来才关，不然把队友关在外面
	var stage := level_stage()
	await reset_scene(true, true, stage.skin if stage != null else null, 2, level_path(), stage)
	var gunner := the_gunner()
	keep_only_enemies([String(gunner.name)])
	var found := doors()
	var entry: ArenaDoor = found[0] if not found[0].exit_door else found[1]
	player.grant_invincibility(60.0)
	player2.grant_invincibility(60.0)
	player.global_position = Vector2(entry.position.x + 120.0, GROUND_Y - 16.0)
	player2.global_position = Vector2(entry.position.x - 40.0, GROUND_Y - 16.0)
	snap_camera()
	gunner.appear()
	await frames(30)
	check("one player still outside: the door stays open", entry.is_open)
	player2.global_position = Vector2(entry.position.x + 80.0, GROUND_Y - 16.0)
	await frames(30)
	check("both inside: it shuts", not entry.is_open)
