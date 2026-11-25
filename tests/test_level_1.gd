extends "res://tests/layered_checks.gd"
## The first real stage (`scenes/level_1.tscn`, green zone) — **a layered grid map** since 2026-10
## (drawn in `tools/level1_map.py`, path-checked and written by `tools/map_build.py`, with the green zone tiles `THEMES["green"]`).
## Checks shared by layered stages are in `layered_checks.gd`; this only covers **what is unique to this stage**, and the second half runs the forced detours with the real rules.

const LEVEL_INFO := "res://levels/level_1.tres"


func level_path() -> String:
	return "res://scenes/level_1.tscn"


func level_stage() -> LevelInfo:
	return load(LEVEL_INFO) as LevelInfo


func zone() -> String:
	return "cyberpunk"


## This stage's ground only breaks in two places (the chasm, the floating islands); every other "low spot" is a cave — not a pit
func min_pits() -> int:
	return 2


func boss() -> Boss:
	for node in main.get_node("Enemies").get_children():
		if node is Boss:
			return node
	return null


# ---------------------------------------------------------------- This stage's own

func test_it_is_the_first_stage_in_the_catalog() -> void:
	if needs_art(): return
	var info := load(LEVEL_INFO) as LevelInfo
	check("it points at this scene", info.scene_path == level_path(), info.scene_path)
	check("and brings the green zone pack", info.skin != null
		and info.skin.resource_path.contains("cyberpunk"), str(info.skin))
	var levels := Catalog.levels()
	check("the catalog lists it first", not levels.is_empty() and levels[0].scene_path == level_path(),
		"" if levels.is_empty() else levels[0].scene_path)


func test_this_stage_brings_its_own_cast() -> void:
	await open_level()
	var kinds := {}
	for enemy in enemies():
		kinds[enemy.skin_key] = int(kinds.get(enemy.skin_key, 0)) + 1
	var wrong: Array[String] = []
	for key: StringName in kinds:
		if not String(key).begins_with("1_"):
			wrong.append(String(key))
	check("every enemy here belongs to stage 1", wrong.is_empty(), str(wrong))
	check("and all seven types plus the boss show up", kinds.size() >= 8, str(kinds.keys()))


func test_crates_and_barrels_wear_the_pack_art() -> void:
	if needs_art(): return
	# The cyberpunk pack (green zone) did not have these two before, and placeholder blocks among the pixel art were obvious at a glance
	await open_level()
	var crates := 0
	var barrels := 0
	for node in main.get_node("Traps").get_children():
		if node is BreakableCrate or node is ExplosiveBarrel:
			var visual := (node as Node).get_node("Visual")
			check("%s is drawn from the pack" % node.name, visual is CrateSpriteAppearance, str(visual))
			if node is BreakableCrate:
				crates += 1
			else:
				barrels += 1
	check("setup: there are crates and barrels", crates >= 6 and barrels >= 6, "%d / %d" % [crates, barrels])


func test_the_boss_arena_is_flat_open_ground() -> void:
	# Boss A stands on the ground, moves within 160 of its spawn point and jumps: that ground can have no pits and no walls blocking sight
	# (its sight comes from its body centre, and with a wall in the way it does nothing); overhead there must be platforms for the player to dodge the fan
	await open_level()
	var b := boss()
	check("there is a boss", b != null)
	if b == null:
		return
	check("it stands on the ground", absf(enemy_feet(b) - GROUND_Y) < 1.0, "%.1f" % enemy_feet(b))
	for pit in pits():
		check("no pit near it (%.0f..%.0f)" % [pit.x, pit.y], pit.y < b.position.x - 480.0
			or pit.x > b.position.x + 480.0)
	for rect in solid_rects():
		if rect.end.y <= GROUND_Y - 0.5 and rect.position.y > 0.0 \
				and rect.end.x > b.position.x - 400.0 and rect.position.x < b.position.x + 400.0:
			check("nothing solid stands in its arena", false, str(rect))
	var above := 0
	for face in surfaces():
		if face[2] < GROUND_Y and face[1] > b.position.x - 400.0 and face[0] < b.position.x + 400.0:
			above += 1
	check("there are platforms above the arena", above >= 4, str(above))


# ---------------------------------------------------------------- Forced detours, run with the real rules

func climb(direction: StringName) -> void:
	Input.action_press(direction)
	for i in 180:
		await tree.physics_frame
		if i > 5 and not player.is_climbing():
			break
	release_all_input()
	await frames(5)


func test_the_rock_in_the_park_is_climbed_not_jumped() -> void:
	# Segment 1: the stone hill runs from row 8 all the way to the ground (higher than a jump); the only way up is the ladder on the left
	await open_empty()
	player.global_position = Vector2(col_x(1, 40), GROUND_Y - 16.0)
	await frames(3)
	Input.action_press(&"move_right")
	Input.action_press(&"jump")
	await frames(150)
	release_all_input()
	check("walking and jumping into it gets you nowhere", player.global_position.x < col_x(1, 48),
		"x %.0f" % player.global_position.x)
	player.global_position = Vector2(col_x(1, 47), GROUND_Y - 16.0)
	await frames(3)
	await climb(&"aim_up")
	check("the ladder takes you to the top of the rock", absf(feet() - 8 * CELL) < 1.0, "feet %.1f" % feet())


func test_the_burrow_mouth_is_sealed_and_the_hilltop_ends_at_a_cliff() -> void:
	# Segment 3: the cave mouth is sealed with stone, so climb the hill first; the hilltop is blocked by a cliff, so drop into the cave through the opening in the ground
	await open_empty()
	player.global_position = Vector2(col_x(3, 0) - 40.0, GROUND_Y - 16.0)
	await frames(3)
	Input.action_press(&"move_right")
	await frames(90)
	release_all_input()
	check("the cave mouth is walled up", player.global_position.x < col_x(3, 3),
		"x %.0f" % player.global_position.x)
	player.global_position = Vector2(col_x(3, 44), MIDDLE_FLOOR - 16.0)
	await frames(3)
	Input.action_press(&"move_right")
	Input.action_press(&"jump")
	await frames(150)
	release_all_input()
	check("the cliff on the hilltop stops you", player.global_position.x < col_x(3, 48),
		"x %.0f" % player.global_position.x)
	player.global_position = Vector2(col_x(3, 41), MIDDLE_FLOOR - 16.0)
	await frames(60)
	check("the gap in the hilltop drops you into the cave", absf(feet() - GROUND_Y) < 1.0,
		"feet %.1f" % feet())


func test_the_chasm_cannot_be_jumped_from_the_ground() -> void:
	# Segment 4: the ground breaks for 48 cells, not even a running jump gets across; climb the ladder to the string of platforms
	await open_empty()
	player.global_position = Vector2(col_x(4, 6), GROUND_Y - 16.0)
	await frames(3)
	var hp := player.health
	Input.action_press(&"sprint")
	Input.action_press(&"move_right")
	await frames(30)
	Input.action_press(&"jump")
	await frames(90)
	release_all_input()
	await frames(30)
	check("a running jump ends in the chasm", player.health < hp or player.global_position.x < col_x(4, 64),
		"x %.0f hp %d" % [player.global_position.x, player.health])


func test_the_tunnel_is_sealed_with_crates() -> void:
	# Segment 9: two stacks of crates block the tunnel; you only get through by breaking them
	await open_empty()
	var stack: Array = []
	for node in main.get_node("Traps").get_children():
		var crate := node as BreakableCrate
		if crate != null and absf(crate.position.x - col_x(9, 26)) < 1.0:
			stack.append(crate)
	check("setup: the stack is there", stack.size() == 3, str(stack.size()))
	player.global_position = Vector2(col_x(9, 20), GROUND_Y - 16.0)
	await frames(3)
	Input.action_press(&"move_right")
	Input.action_press(&"jump")
	await frames(120)
	release_all_input()
	check("you cannot get past the stack", player.global_position.x < col_x(9, 26),
		"x %.0f" % player.global_position.x)
	for crate: BreakableCrate in stack:
		for i in crate.toughness:
			crate.take_damage(SHOT, Vector2.INF, player)
	await frames(5)
	Input.action_press(&"move_right")
	await frames(60)
	release_all_input()
	check("shot apart, the way is open", player.global_position.x > col_x(9, 30),
		"x %.0f" % player.global_position.x)
