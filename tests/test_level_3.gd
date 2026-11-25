extends "res://tests/layered_checks.gd"
## The third real stage (`scenes/level_3.tscn`, bar street) — **a layered grid map** since 2026-10
## (drawn in `tools/level3_map.py`, path-checked and written by `tools/map_build.py`, with the tiles `THEMES["bar"]`).
## Checks shared by layered stages are in `layered_checks.gd`; this only covers **what is unique to this stage**: the night scene (facades, lighting layer),
## the shark bot shooting along the floor, the open ground for the wheel mech, and running a few forced detours with the real rules.

const LEVEL_INFO := "res://levels/level_3.tres"


func level_path() -> String:
	return "res://scenes/level_3.tscn"


func level_stage() -> LevelInfo:
	return load(LEVEL_INFO) as LevelInfo


func zone() -> String:
	return "bar_street"


func the_boss() -> Boss:
	for node in main.get_node("Enemies").get_children():
		if node is Boss:
			return node
	return null


func test_it_is_the_third_stage_in_the_catalog() -> void:
	if needs_art(): return
	var info := load(LEVEL_INFO) as LevelInfo
	check("it points at this scene", info.scene_path == level_path(), info.scene_path)
	check("and it brings the bar street pack", info.skin != null
		and info.skin.resource_path.contains("bar_street"), str(info.skin))
	var levels := Catalog.levels()
	check("the catalog picks it up as the third one",
		levels.size() >= 3 and levels[2].scene_path == level_path(),
		"" if levels.size() < 3 else levels[2].scene_path)


func test_this_stage_brings_its_own_cast() -> void:
	await open_level()
	var kinds := {}
	for enemy in enemies():
		kinds[enemy.skin_key] = int(kinds.get(enemy.skin_key, 0)) + 1
	var wrong: Array[String] = []
	for key: StringName in kinds:
		if not String(key).begins_with("3_"):
			wrong.append(String(key))
	check("every enemy here belongs to stage 3", wrong.is_empty(), str(wrong))
	check("and all six types plus the boss show up", kinds.size() >= 7, str(kinds.keys()))


func test_the_low_shooters_sit_on_the_ground_not_in_it() -> void:
	# 3-E is only 12 tall with its feet 6 below the origin (others: 16). Placed at the others' height it would sink 10px into the floor,
	# and the "something under its feet" check only catches floating, not sinking — so really run it here; the floor must not push it
	await open_level()
	var sharks: Array[Enemy] = []
	for enemy in enemies():
		if enemy.skin_key == &"3_e":
			sharks.append(enemy)
	check("setup: there are sharks", sharks.size() >= 5, str(sharks.size()))
	var start := {}
	for shark in sharks:
		start[shark] = shark.position
	await frames(30)
	for shark in sharks:
		check("%s stays put" % shark.name, shark.position.distance_to(start[shark]) < 1.0,
			"%s -> %s" % [start[shark], shark.position])


func test_the_boss_has_clear_flat_ground_to_roll_on() -> void:
	# The wheel mech **stands on the ground**, and its charge is not limited by its ground (it rolls until time is up or it hits a wall):
	# about 334px in phase 2, plus its ground of 220, so it can roll anywhere within 550 of its spawn point.
	# A pit in that stretch and it rolls in to its death; a wall blocks its view of the player (and it does nothing).
	await open_level()
	var boss := the_boss()
	check("there is a boss", boss != null)
	if boss == null:
		return
	check("it stands on the ground", boss.motion_mode == CharacterBody2D.MOTION_MODE_GROUNDED)
	var reach := 600.0
	for pit in pits():
		check("no pit within its reach (%.0f)" % pit.x, pit.y < boss.position.x - reach
			or pit.x > boss.position.x + reach,
			"pit %.0f..%.0f, boss at %.0f" % [pit.x, pit.y, boss.position.x])
	for rect in solid_rects():
		if rect.end.y <= GROUND_Y + 0.5 and rect.position.y > 0.0 \
				and rect.end.x > boss.position.x - reach and rect.position.x < boss.position.x + reach:
			check("nothing solid stands in the arena", false, "%s, boss at %.0f" % [rect, boss.position.x])


# ---------------------------------------------------------------- Night scene: facades and lighting layer

func facades() -> Array[Prop]:
	var out: Array[Prop] = []
	for node in props():
		if (node as Prop).texture.resource_path.get_file().begins_with("facade_"):
			out.append(node)
	return out


func test_the_street_is_lined_with_buildings() -> void:
	if needs_art(): return
	# The row of buildings along the street in the promo art: the art pack only gave tiles, and the buildings are assembled by terrain_build.py
	await open_level()
	var found := facades()
	check("there are buildings along the street", found.size() >= 30, str(found.size()))
	for facade in found:
		check("%s comes from this zone" % facade.name,
			facade.texture.resource_path.begins_with("res://skins/bar_street/props/facade_"),
			facade.texture.resource_path)


func test_the_buildings_stand_behind_the_rest_of_the_scenery() -> void:
	if needs_art(): return
	# First placed, first drawn: buildings have to come before the bars, barrels and signs, or a building would cover them all
	await open_level()
	var last_facade := -1
	var first_other := 1 << 30
	for node in props():
		if (node as Prop).texture.resource_path.get_file().begins_with("facade_"):
			last_facade = maxi(last_facade, node.get_index())
		else:
			first_other = mini(first_other, node.get_index())
	check("every building is drawn before the small props", last_facade < first_other,
		"%d vs %d" % [last_facade, first_other])


func test_no_building_stands_over_a_pit() -> void:
	if needs_art(): return
	# The whole bottom edge of a building has to rest on one surface (the street, an arcade roof); hanging over a pit it looks like a floating building
	await open_level()
	var faces := surfaces()
	for facade in facades():
		var left := facade.position.x
		var right := left + facade.texture.get_width() / float(facade.frames)
		var on_ground := false
		for face in faces:
			if face[0] <= left + 0.5 and right <= face[1] + 0.5 and absf(face[2] - facade.position.y) < 0.5:
				on_ground = true
		check("%s stands on something along its whole width" % facade.name, on_ground,
			"%.0f..%.0f at %.0f" % [left, right, facade.position.y])


func test_no_building_is_drawn_over_an_indoor_wall() -> void:
	if needs_art(): return
	# Facades are drawn over the indoor wall layer: placed inside a building (where there is a floor overhead) they would cover the wall
	await open_level()
	var solids := solid_rects()
	for facade in facades():
		var middle := facade.position.x + facade.texture.get_width() / float(facade.frames) / 2.0
		var roofed := false
		for rect in solids:
			if rect.position.x <= middle and middle <= rect.end.x and rect.end.y <= facade.position.y - 32.0 \
					and rect.position.y > 0.0:
				roofed = true
		check("%s stands in the open" % facade.name, not roofed, "x %.0f" % middle)


func test_the_neon_light_falls_on_the_set_not_on_the_cast() -> void:
	if needs_art(): return
	# The lighting layer has to sit between terrain and characters: backdrop, buildings, scenery and terrain are tinted, characters and bullets keep their colours
	await open_level()
	var light := main.get_node_or_null("Lighting")
	check("the level is lit", light is ScreenLight, str(light))
	if light == null:
		return
	var at := light.get_index()
	check("over the scenery", main.get_node("Props").get_index() < at)
	check("over the tiles", main.get_node("FrontTiles").get_index() < at)
	check("over the terrain", main.get_node("Level").get_index() < at)
	check("under the enemies", at < main.get_node("Enemies").get_index())
	check("under the player", at < main.get_node("Player").get_index())
	check("under the effects", at < main.get_node("Fx").get_index())


func test_the_light_is_pure_decoration_and_covers_the_screen() -> void:
	if needs_art(): return
	await open_level()
	var light := main.get_node_or_null("Lighting") as ScreenLight
	check("setup: the level is lit", light != null)
	if light == null:
		return
	check("it never takes the mouse", light.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	var stack: Array[Node] = [light]
	var shapes := 0
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is CollisionObject2D or node is CollisionShape2D:
			shapes += 1
		stack.append_array(node.get_children())
	check("and has nothing to collide with", shapes == 0, str(shapes))
	player.global_position = Vector2(6400, 200)
	await frames(30)
	var viewport := light.get_viewport()
	var view := viewport.get_canvas_transform().affine_inverse() * viewport.get_visible_rect()
	var covered := Rect2(light.global_position, light.size)
	check("it follows the camera and covers the whole view", covered.encloses(view),
		"%s vs %s" % [covered, view])


func test_the_test_level_stays_unlit() -> void:
	await reset_scene()
	check("no lighting on the default pack", main.get_node_or_null("Lighting") == null)


# ---------------------------------------------------------------- No scenery that looks like a pickup

## 2026-10 playtest feedback: bottles, glasses, flying banknotes and floating cards lying on the floor look like things to pick up.
## The screenshots of the layered version showed two more: `bin` (actually a bull's skull) and `crate` (a knife lying flat), small things strewn all over the floor.
const PICKUP_LOOKALIKES := ["bottle", "glass", "money", "card", "bin", "crate"]


func test_nothing_lying_around_looks_like_a_pickup() -> void:
	if needs_art(): return
	await open_level()
	check("setup: the street is dressed", props().size() >= 100, str(props().size()))
	for node in props():
		var path := (node as Sprite2D).texture.resource_path.get_file()
		for word: String in PICKUP_LOOKALIKES:
			check("%s is not a %s" % [node.name, word], not path.begins_with(word), path)


## The base class checks "animated scenery really moves". The two animated pieces of this stage (banknotes, cards) are exactly the two that looked like pickups,
## and they are gone, so it guards the opposite: **no** animated scenery creeps in.
func test_the_fountain_actually_runs() -> void:
	await open_level()
	for node in props():
		check("%s stays still" % node.name, (node as Prop).frames <= 1, str((node as Prop).frames))


# ---------------------------------------------------------------- Forced detours, run with the real rules

func climb(direction: StringName) -> void:
	Input.action_press(direction)
	for i in 180:
		await tree.physics_frame
		if i > 5 and not player.is_climbing():
			break
	release_all_input()
	await frames(5)


func push_right(frames_held := 150, jumping := true) -> void:
	Input.action_press(&"move_right")
	if jumping:
		Input.action_press(&"jump")
	await frames(frames_held)
	release_all_input()


func test_the_first_bar_is_a_dead_end_downstairs() -> void:
	# Segment 1: the bar's ground floor ends at a wall; take the ladder to the first floor
	await open_empty()
	player.global_position = Vector2(col_x(1, 60), GROUND_Y - 16.0)
	await frames(3)
	await push_right()
	check("walking and jumping right gets you nowhere", player.global_position.x < col_x(1, 70),
		"x %.0f" % player.global_position.x)
	player.global_position = Vector2(col_x(1, 65), GROUND_Y - 16.0)
	await frames(3)
	await climb(&"aim_up")
	check("the ladder takes you upstairs", absf(feet() - MIDDLE_FLOOR) < 1.0, "feet %.1f" % feet())


func test_the_cellar_is_shuttered_from_the_street() -> void:
	# Segment 3: the street side of the cellar is a pulled-down shutter, no way in from the street; inside the bar walk right to the end and drop through the trapdoor into the cellar
	await open_empty()
	player.global_position = Vector2(col_x(3, 0) - 40.0, GROUND_Y - 16.0)
	await frames(3)
	await push_right(90, false)
	check("the shutter keeps you out", player.global_position.x < col_x(3, 3),
		"x %.0f" % player.global_position.x)
	player.global_position = Vector2(col_x(3, 44), MIDDLE_FLOOR - 16.0)
	await frames(3)
	await push_right()
	check("the bar ends at a wall", player.global_position.x < col_x(3, 48),
		"x %.0f" % player.global_position.x)
	player.global_position = Vector2(col_x(3, 41), MIDDLE_FLOOR - 16.0)
	await frames(60)
	check("the trapdoor drops you into the cellar", absf(feet() - GROUND_Y) < 1.0, "feet %.1f" % feet())


func test_the_street_ends_below_the_rooftops() -> void:
	# Segment 7: the street is a dead end here (the first building's wall comes down to the ground); climb the fire escape to the roofs
	await open_empty()
	player.global_position = Vector2(col_x(7, 3), GROUND_Y - 16.0)
	await frames(3)
	await push_right()
	check("the first building walls off the street", player.global_position.x < col_x(7, 10),
		"x %.0f" % player.global_position.x)
	player.global_position = Vector2(col_x(7, 9), GROUND_Y - 16.0)
	await frames(3)
	await climb(&"aim_up")
	check("the fire escape takes you to the roof", absf(feet() - 8 * CELL) < 1.0, "feet %.1f" % feet())


func test_the_alley_is_sealed_with_crates() -> void:
	# Segment 9: two stacks of crates block the back alley; you only get through by breaking them
	await open_empty()
	var stack: Array = []
	for node in main.get_node("Traps").get_children():
		var crate := node as BreakableCrate
		if crate != null and absf(crate.position.x - col_x(9, 26)) < 1.0:
			stack.append(crate)
	check("setup: the stack is there", stack.size() == 3, str(stack.size()))
	player.global_position = Vector2(col_x(9, 20), GROUND_Y - 16.0)
	await frames(3)
	await push_right(120)
	check("you cannot get past the stack", player.global_position.x < col_x(9, 26),
		"x %.0f" % player.global_position.x)
	for crate: BreakableCrate in stack:
		for i in crate.toughness:
			crate.take_damage(SHOT, Vector2.INF, player)
	await frames(5)
	await push_right(60, false)
	check("shot apart, the way is open", player.global_position.x > col_x(9, 30),
		"x %.0f" % player.global_position.x)
