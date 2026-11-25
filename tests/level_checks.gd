extends GameTest
## **Checks shared by all real stages** (a base class, not run on its own). It used to be stage 1's set; when stage 1 became a layered grid map in 2026-10
## it moved into a base class: the horizontal stage (stage 3) and the vertical stage (stage 4) inherit it directly, the layered stages (1, 2) through `layered_checks.gd`.
##
## This set reads **the generated scene**, not the table in the build script — the script checks itself too,
## but if someone edits a `.tscn` by hand, or the player's jump changes one day, only measuring the scene shows it.
##
## The jumpable distance is **measured**: on the test level's flat ground, hold jump + right and measure how far you travel from take-off to landing.
## No formula, so whichever of the player's gravity, jump strength or walking speed changes, this speaks up.

const GROUND_Y := 320.0
## Standing at 32 tall you cannot get through, standing shots at 21~25 above the floor do: the crawl passage clearance sits in between (see CLAUDE.md).
const CRAWL_CLEAR := 30.0


## Which stage. **Subclasses override these two methods** and pick up the whole set of geometry checks below (pits jumpable, walls climbable, blockers with a high route,
## crawl clearance, no enemy floating, scenery without collision, no duplicate names...) — rewriting them for every stage is how things really get missed.
func level_path() -> String:
	return ""


## The art set for this stage (`levels/*.tres`). Returning null runs with the default pack (the geometry checks do not depend on the skin).
func level_stage() -> LevelInfo:
	return null


func open_level() -> void:
	var stage := level_stage()
	await reset_scene(true, true, stage.skin if stage != null else null, 1, level_path(), stage)


## Whether this enemy is **deliberately** placed in mid-air: flyers, floating bosses,
## and ones hanging above the top of the view waiting to drop (stage 2's 2-A). For these, "nothing under the feet" is correct.
func hangs_in_the_air(enemy: Enemy) -> bool:
	return enemy is EnemyFlyer 		or enemy.motion_mode == CharacterBody2D.MOTION_MODE_FLOATING 		or enemy.position.y < 0.0


## Every terrain block in the level (under `Level`, including the upright walls in `Level/Walls`).
func terrain() -> Array:
	var found := []
	for child in main.get_node("Level").get_children():
		if child is Platform:
			found.append(child)
		else:
			for grandchild in child.get_children():
				if grandchild is Platform:
					found.append(grandchild)
	return found


## The stretches of ground, sorted by their left end: (left, right).
func ground_runs() -> Array[Vector2]:
	var runs: Array[Vector2] = []
	for node in terrain():
		var slab := node as Platform
		if not slab.one_way and absf(slab.position.y - GROUND_Y) < 1.0:
			runs.append(Vector2(slab.position.x, slab.position.x + slab.size.x))
	runs.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	return runs


## Where the ground breaks: (right end of the left bank, left end of the right bank).
func pits() -> Array[Vector2]:
	var found: Array[Vector2] = []
	var runs := ground_runs()
	for i in runs.size() - 1:
		found.append(Vector2(runs[i].y, runs[i + 1].x))
	return found


## A solid block hanging in mid-air = **a crawl passage roof**: its bottom does not reach the ground, leaving a gap underneath.
## Upright walls and blockers stand on the ground (their bottom reaches the ground line) and do not count.
func crawl_passages() -> Array:
	var found := []
	for node in terrain():
		var slab := node as Platform
		if slab.one_way or slab.position.y <= 0.0:
			continue
		if absf(slab.position.y - GROUND_Y) < 1.0:           # The ground itself
			continue
		if slab.position.y + slab.size.y < GROUND_Y - 1.0:   # There is still a gap underneath
			found.append(slab)
	return found


## Solid blocks standing on the ground: upright walls (16 wide, jumpable) and **blockers** (higher than a jump, the path underneath is closed).
func standing_solids() -> Array:
	var found := []
	for node in terrain():
		var slab := node as Platform
		if slab.one_way or slab.position.y <= 0.0:
			continue
		if absf(slab.position.y - GROUND_Y) < 1.0:
			continue
		if slab.position.y + slab.size.y >= GROUND_Y - 1.0:
			found.append(slab)
	return found


## Surfaces to stand on: (left, right, top). The ground counts by stretch, each one-way platform separately.
func surfaces() -> Array:
	var found := []
	for node in terrain():
		var slab := node as Platform
		if slab.one_way or absf(slab.position.y - GROUND_Y) < 1.0:
			found.append([slab.position.x, slab.position.x + slab.size.x, slab.position.y])
	return found


## How many jumps a pit takes: with platforms in the pit, jump onto them from the left bank, then on to the right bank. Returns how far each jump is.
func hops_across(pit: Vector2) -> Array[float]:
	var edges: Array[float] = [pit.x]
	for node in terrain():
		var slab := node as Platform
		if slab.one_way and slab.position.x >= pit.x and slab.position.x + slab.size.x <= pit.y:
			edges.append(slab.position.x)
			edges.append(slab.position.x + slab.size.x)
	edges.append(pit.y)
	edges.sort()
	var hops: Array[float] = []
	for i in range(0, edges.size() - 1, 2):
		hops.append(edges[i + 1] - edges[i])
	return hops


## Hold jump on flat ground and jump forward, measuring how far you travel from take-off to landing — i.e. how wide a pit you can clear.
func jump_distance() -> float:
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(5)
	Input.action_press("move_right")
	await frames(20)                      # Speed up to full speed first
	Input.action_press("jump")            # **Hold it**: releasing early is a short jump, only half as high
	var start := 0.0
	var airborne := false
	for i in 120:
		await tree.physics_frame
		if not airborne and not player.is_on_floor():
			airborne = true
			start = player.global_position.x
		elif airborne and player.is_on_floor():
			break
	release_all_input()
	return player.global_position.x - start


# ---------------------------------------------------------------- The shape of the stage

func test_the_level_is_ten_times_the_test_one() -> void:
	await open_level()
	var camera: Camera2D = main.get_node("Camera2D")
	check("the camera lets you walk twenty screens", camera.limit_right == 12800,
		str(camera.limit_right))
	var runs := ground_runs()
	check("setup: there is ground", not runs.is_empty())
	check("and the ground reaches the far wall", runs[runs.size() - 1].y >= 12800.0 - 1.0,
		str(runs[runs.size() - 1].y))
	check("the player starts at the near end", main.get_node("Player").position.x < 640.0,
		str(main.get_node("Player").position.x))


func test_it_really_has_pits() -> void:
	# Without first confirming there are pits, the "every pit can be jumped" check below would compare thin air
	await open_level()
	check("the ground is broken up", pits().size() >= 4, str(pits().size()))


func test_every_pit_can_be_jumped() -> void:
	var reach := await jump_distance()
	check("setup: a jump really covers some ground", reach > 80.0, "%.0f" % reach)
	await open_level()
	for pit in pits():
		for hop in hops_across(pit):
			check("the pit at %.0f can be cleared" % pit.x, hop <= reach,
				"%.0f wide, a jump covers %.0f" % [hop, reach])


func test_nothing_is_higher_than_a_jump() -> void:
	var reach := await jump_distance()
	await open_level()
	# Upright walls: the rule in CLAUDE.md is at least 12 below the jump height. Deriving the jump height from the measured horizontal distance is not right,
	# so measure a vertical jump directly.
	var top := await jump_height()
	check("setup: the jump has some height", top > 60.0, "%.0f" % top)
	await open_level()
	for node in main.get_node("Level/Walls").get_children():
		var wall := node as Platform
		check("%s can be jumped" % wall.name, wall.size.y <= top - 12.0,
			"%.0f tall, the jump reaches %.0f" % [wall.size.y, top])
	# Floating platforms: each needs a reachable surface within 120px below it, otherwise it cannot be climbed
	for node in terrain():
		var slab := node as Platform
		if not slab.one_way:
			continue
		var best := INF
		for face in surfaces():
			var other: float = face[2]
			if other <= slab.position.y:
				continue
			if face[1] < slab.position.x - 120.0 or face[0] > slab.position.x + slab.size.x + 120.0:
				continue
			best = minf(best, other - slab.position.y)
		check("%s can be reached" % slab.name, best <= top,
			"%.0f up, the jump reaches %.0f" % [best, top])


## Hold jump on flat ground and measure how high you get.
func jump_height() -> float:
	await reset_scene()
	player.global_position = Vector2(200, 304)
	await frames(5)
	var floor_y := player.global_position.y
	Input.action_press("jump")
	var top := floor_y
	for i in 60:
		await tree.physics_frame
		top = minf(top, player.global_position.y)
		if player.is_on_floor() and i > 5:
			break
	release_all_input()
	return floor_y - top


func test_the_crawl_passages_still_need_crouching() -> void:
	await open_level()
	var passages := crawl_passages()
	check("setup: there are crawl passages", passages.size() >= 4, str(passages.size()))
	for node in passages:
		var slab := node as Platform
		var clear := GROUND_Y - (slab.position.y + slab.size.y)
		check("%s leaves exactly the crawl gap" % slab.name, absf(clear - CRAWL_CLEAR) < 0.5,
			"%.0f" % clear)


func test_the_blocked_routes_really_block_and_really_have_a_way_over() -> void:
	# "Blocked below, you have to go over the top" is one of the stage's backbones: the block itself must be higher than a jump,
	# and there must be a floating platform reaching right over it, otherwise it is a dead end.
	var top := await jump_height()
	await open_level()
	var blocks := []
	for node in standing_solids():
		var slab := node as Platform
		if slab.size.y > top:
			blocks.append(slab)
	check("setup: the level blocks the low road somewhere", blocks.size() >= 3, str(blocks.size()))
	for node in blocks:
		var slab := node as Platform
		var covered := false
		for face in surfaces():
			if face[2] <= slab.position.y - 16.0 and face[0] <= slab.position.x 					and face[1] >= slab.position.x + slab.size.x:
				covered = true
		check("%s has a ledge going over it" % slab.name, covered,
			"block %.0f..%.0f, top %.0f" % [slab.position.x, slab.position.x + slab.size.x,
				slab.position.y])


## y of an enemy's feet: half a hitbox height below the hitbox centre (bosses have taller boxes than ordinary enemies, so each by its own shape).
func enemy_feet(enemy: Enemy) -> float:
	var box: CollisionShape2D = enemy.get_node("CollisionShape2D")
	return enemy.position.y + (box.shape as RectangleShape2D).size.y / 2.0 + box.position.y


# ---------------------------------------------------------------- What is placed in it

func test_every_enemy_stands_on_something() -> void:
	await open_level()
	var checked := 0
	for node in main.get_node("Enemies").get_children():
		var enemy := node as Enemy
		if enemy == null or hangs_in_the_air(enemy):
			continue
		var feet: float = enemy_feet(enemy)
		var standing := false
		for face in surfaces():
			if face[0] - 8.0 <= enemy.position.x and enemy.position.x <= face[1] + 8.0 \
					and absf(face[2] - feet) < 2.0:
				standing = true
		checked += 1
		check("%s has ground under it" % enemy.name, standing,
			"feet at %.0f, x %.0f" % [feet, enemy.position.x])
	check("setup: there are enemies to check", checked >= 20, str(checked))


func test_the_player_gets_a_moment_before_the_first_enemy() -> void:
	# **If the player is being hit the moment they arrive, they do not even get to look around** (found in playtesting).
	# The camera starts clamped to the left of the stage, so the view is x 0..640, and an enemy **counts as in reach as soon as part of it is on screen**
	# ("vision parity", see CLAUDE.md), so the first screen has to be empty.
	await open_level()
	var camera: Camera2D = main.get_node("Camera2D")
	var first_screen := float(ProjectSettings.get_setting("display/window/size/viewport_width", 640))
	check("setup: the camera starts pinned to the left edge", camera.limit_left == 0)
	var nearest := INF
	for node in main.get_node("Enemies").get_children():
		var enemy := node as Enemy
		if enemy != null:
			nearest = minf(nearest, enemy.position.x)
	check("setup: there are enemies further in", nearest < INF)
	check("but none of them on the opening screen", nearest > first_screen,
		"the first one is at %.0f" % nearest)


func test_nothing_shoots_the_player_on_arrival() -> void:
	# The previous check measured positions; this one really runs: standing still for two seconds should not lose a drop of health
	await open_level()
	await frames(2)
	var health := player.health
	await frames(120)
	check("the player is left alone at the start", player.health == health,
		"%d -> %d" % [health, player.health])
	check("and nothing is flying at them", bullets(16).is_empty(), str(bullets(16).size()))


func test_no_enemy_is_stuck_in_a_crawl_passage() -> void:
	# Enemies are 32 tall and crawl passages have 30 of clearance; placed inside one they are stuck forever (a pitfall noted in CLAUDE.md)
	await open_level()
	for node in main.get_node("Enemies").get_children():
		var enemy := node as Enemy
		if enemy == null or hangs_in_the_air(enemy):
			continue
		if absf(enemy_feet(enemy) - GROUND_Y) > 1.0:
			continue
		for slab_node in crawl_passages():
			var slab := slab_node as Platform
			check("%s is clear of %s" % [enemy.name, slab.name],
				enemy.position.x < slab.position.x - 24.0
				or enemy.position.x > slab.position.x + slab.size.x + 24.0,
				"enemy at %.0f, passage %.0f..%.0f"
					% [enemy.position.x, slab.position.x, slab.position.x + slab.size.x])


func test_the_boss_waits_at_the_far_end() -> void:
	await open_level()
	var boss: Boss = null
	for node in main.get_node("Enemies").get_children():
		if node is Boss:
			boss = node
	check("there is a boss", boss != null)
	check("and it is in the last stretch", boss != null and boss.position.x > 12800.0 - 1280.0,
		"" if boss == null else str(boss.position.x))


func test_nobody_walks_off_a_ledge_on_their_own() -> void:
	# Half the enemies are placed on floating platforms; if any walked off and fell to its death at the start, the stage would quietly empty.
	# Patrollers turn around at edges, but one placed wrong (half its body over the edge) still falls, so let it run for two seconds and see.
	await open_level()
	# **Count enemies, not children**: enemy bullets and grenades also hang under `Enemies` (see CLAUDE.md),
	# so counting children goes up with every shot and down again a moment later when the bullets are gone
	var before := enemies().size()
	check("setup: the level is full of enemies", before >= 80, str(before))
	await frames(120)
	var after := enemies().size()
	check("they are all still there", after >= before, "%d -> %d" % [before, after])


# ---------------------------------------------------------------- Scenery

func props() -> Array:
	var found := []
	for child in main.get_node("Props").get_children():
		found.append(child)
	return found


func test_the_scenery_is_pure_decoration() -> void:
	# The same rule as effects: **no colliders in scenery**, or one tree could block a person and swallow bullets.
	await open_level()
	check("setup: the level is dressed up", props().size() >= 100, str(props().size()))
	var bodies := 0
	var shapes := 0
	var stack := props().duplicate()
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is CollisionObject2D:
			bodies += 1
		if node is CollisionShape2D or node is CollisionPolygon2D:
			shapes += 1
		for child in node.get_children():
			stack.append(child)
	check("no collision bodies among the scenery", bodies == 0, str(bodies))
	check("and no collision shapes either", shapes == 0, str(shapes))


func test_the_scenery_is_drawn_behind_everything() -> void:
	# Drawing order is child order: scenery must come before terrain, enemies and players (= drawn behind them),
	# otherwise a tree would cover an enemy shooting at you.
	await open_level()
	var order := {}
	for child in main.get_children():
		order[child.name] = child.get_index()
	check("scenery comes before the terrain", order["Props"] < order["Level"],
		"%d vs %d" % [order["Props"], order["Level"]])
	check("and before the enemies and the player",
		order["Props"] < order["Enemies"] and order["Props"] < order["Player"])


func test_the_level_plays_the_same_without_any_scenery() -> void:
	# Purely decorative means: delete it all and the stage still runs
	await open_level()
	main.get_node("Props").free()
	await frames(60)
	check("the level runs on without it", player.is_alive() and main.get_node_or_null("Props") == null)


func test_the_fountain_actually_runs() -> void:
	if needs_art(): return
	await open_level()
	var animated: Prop = null
	for node in props():
		var prop := node as Prop
		if prop != null and prop.frames > 1:
			animated = prop
	check("there is something that moves", animated != null)
	if animated == null:
		return
	var first := animated.region_rect
	for i in 60:
		await tree.physics_frame
		if animated.region_rect != first:
			break
	check("and it really cycles its frames", animated.region_rect != first,
		"%s vs %s" % [animated.region_rect, first])


func test_nothing_in_the_level_shares_a_name() -> void:
	# Duplicate node names throw off the engine's child name table — freeing a batch of enemies prints a screenful of
	# "Children name does not match parent name in hashtable, this is a bug".
	# That is why the build script numbers every enemy.
	await open_level()
	for group in ["Enemies", "Level", "Props"]:
		var seen := {}
		for child in main.get_node(group).get_children():
			check("%s/%s appears once" % [group, child.name], not seen.has(child.name), str(child.name))
			seen[child.name] = true


func test_the_level_runs_on_its_own() -> void:
	# Load a whole stage and run it for two seconds: the spawn point is not stuck in terrain, and there are no script errors (the runner counts SCRIPT ERROR as a failure)
	await open_level()
	await frames(120)
	check("the player is still standing", player.is_alive(), str(player.health))
	check("and has not fallen out of the world", player.global_position.y < main.fall_y,
		str(player.global_position))
