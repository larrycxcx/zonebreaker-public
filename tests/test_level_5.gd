extends "res://tests/layered_checks.gd"
## The fifth real stage (`scenes/level_5.tscn`, lab) — a layered grid map (`tools/level5_map.py`, with the tiles `THEMES["lab"]`).
## Checks shared by layered stages are in `layered_checks.gd`; this only covers **what is unique to this stage**:
## the emitters hanging upside down from ceilings, the mid-level boss room (doors), the biopod's open ground, and running a few forced detours with the real rules.

const LEVEL_INFO := "res://levels/level_5.tres"


func level_path() -> String:
	return "res://scenes/level_5.tscn"


func level_stage() -> LevelInfo:
	return load(LEVEL_INFO) as LevelInfo


func zone() -> String:
	return "lab"


## The stage boss (the one whose death clears the stage). The mid-level boss is a `Boss` too, but its `ends_level` is off.
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


## This stage has two pits that cannot be jumped (the settling pit, the one after the spike field); elsewhere walls and gas capsules force the detours.
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


## The base class version picks "the last boss"; this stage has a mid-level boss too, so pick the one whose death clears the stage.
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
	# 5-F hangs upside down without moving: the top of its mount (MOUNT above the origin) touches the bottom of something solid exactly
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
	# Walking underneath you must not run into it: its body's bottom must be at least a standing person's height above the floor below
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


# ---------------------------------------------------------------- The mid-level boss room

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
	# The walls on both sides go all the way up to the top of the view: there is no way around over the roof
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
	# Walking back: no way out
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


# ---------------------------------------------------------------- The biopod's open ground

func test_the_pod_has_open_ground_to_sweep() -> void:
	# The sweeping laser presses all the way down to a standing player's chest: walls would block it (and its sight), and with pits on the floor there would be nowhere to stand once it has swept
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


# ---------------------------------------------------------------- Forced detours, run with the real rules

func push_right(frames_held := 150, jumping := true) -> void:
	Input.action_press(&"move_right")
	if jumping:
		Input.action_press(&"jump")
	await frames(frames_held)
	release_all_input()


func test_the_first_building_is_a_dead_end_downstairs() -> void:
	# Segment 1: the lab building's ground floor ends at a wall (the gas capsule store is behind it); take the ladder to the first floor
	await open_empty()
	player.global_position = Vector2(col_x(1, 60), GROUND_Y - 16.0)
	await frames(3)
	await push_right()
	check("walking and jumping right gets you nowhere", player.global_position.x < col_x(1, 70),
		"x %.0f" % player.global_position.x)


func test_the_settling_pit_cannot_be_jumped_from_the_ground() -> void:
	# Segment 4: the ground breaks for 32 cells, a running jump does not get across; the only way is to climb up and step across the floating platforms
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
	# Segment 9: in the corridor 3 cells tall a single gas capsule fills the way; you only get through by breaking it
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
	# In co-op one player went in and the other is still outside: the door has to wait until both are in, or it would lock the partner out
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
