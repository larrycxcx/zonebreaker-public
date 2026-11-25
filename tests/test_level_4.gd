extends "res://tests/layered_checks.gd"
## The fourth real stage (`scenes/level_4.tscn`, basement) — **climbing upward**, **a vertical grid map** since 2026-10
## (`tools/level4_map.py`, 40 × 450 cells; `map_build.py` checks paths, picks tiles and writes the scene, with the tiles `THEMES["basement"]`).
##
## It inherits the layered stage set (`layered_checks.gd`): the direction-independent checks (scenery, duplicate names, no damage on arrival, nobody walking off a ledge,
## ladders connected at both ends, floating platforms reachable, no half-height gaps under floors, full crate stacks sealing, enemies not buried in walls, tiles from this zone,
## enemies next to barrels) are picked up as they are. The horizontal-only ones are **overridden one by one** as vertical ones here: one screen wide and 20 tall, side walls all the way down,
## the boss area reachable climbing from the ground (**counting ladders** this time), no enemies on the first screen. The second half runs a few forced detours with the real rules.
##
## The rulers are **measured** as in horizontal stages (`jump_height()`), so if the player's jump changes, this speaks up at once.

const LEVEL_INFO := "res://levels/level_4.tres"
const WIDTH := 640.0
const HEIGHT := 7200.0
const SCREEN_H := 360.0
## How far sideways a jump up may land (with half a margin left).
const REACH_X := 48.0
## Height of a segment (cells): ten segments, two screens each.
const SEG_ROWS := 45
## Thickness of the side rock walls (2 cells).
const WALL_W := 32.0
## How wide a person is: after part of the take-off / landing stretch is blocked, the gap left must be at least this wide
const BODY_W := 24.0


func level_path() -> String:
	return "res://scenes/level_4.tscn"


func level_stage() -> LevelInfo:
	return load(LEVEL_INFO) as LevelInfo


func zone() -> String:
	return "basement"


## Top y of row row in segment seg (counting from the bottom, 1 is the spawn segment).
func seg_y(seg: int, row: int) -> float:
	return ((10 - seg) * SEG_ROWS + row) * CELL


## Surfaces to stand on: [left, right, top, solid or not, name, bottom]. The side walls do not count (they cannot be stood on, they are the boundary).
func faces() -> Array:
	var out := []
	for node in terrain():
		var slab := node as Platform
		if slab.name.begins_with("Wall") or slab.position.y <= 0.0:
			continue
		# In the grid map the side rock walls get cut into pieces by floors running across (a whole solid row merges into one block); those pieces are not surfaces to stand on
		if slab.position.x + slab.size.x <= WALL_W or slab.position.x >= WIDTH - WALL_W:
			continue
		out.append([slab.position.x, slab.position.x + slab.size.x, slab.position.y,
			not slab.one_way, String(slab.name), slab.position.y + slab.size.y])
	return out


func gap_x(a: Array, b: Array) -> float:
	return maxf(0.0, maxf(a[0], b[0]) - minf(a[1], b[1]))


## Can you jump from low up to high: no more than one jump higher, not too far sideways, nothing solid in the way.
func reachable_up(low: Array, high: Array, all: Array, jump: float) -> bool:
	var step: float = low[2] - high[2]
	if step <= 0.0 or step > jump - 12.0 or gap_x(low, high) > REACH_X:
		return false
	# The stretch where take-off and landing overlap horizontally (or the point where they touch if they do not overlap). Subtract the part of that stretch blocked by something solid above,
	# and if **the gap left still fits a person** (`BODY_W`) the jump works. Requiring the whole surface to be clear above would make the wall in the middle of the shaft
	# and the stack of containers in the freight lift shaft count every platform spanning both sides as "cannot be jumped onto"
	var left := maxf(low[0], high[0])
	var right := maxf(minf(low[1], high[1]), left + BODY_W)
	var blocked: Array = []
	for other: Array in all:
		if not other[3] or other[4] == high[4] or other[4] == low[4]:
			continue
		if other[1] <= left or other[0] >= right:
			continue
		if other[5] > high[2] - 40.0 and other[2] < low[2]:
			blocked.append([maxf(other[0], left), minf(other[1], right)])
	blocked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var cursor := left
	for span: Array in blocked:
		if span[0] - cursor >= BODY_W:
			return true
		cursor = maxf(cursor, span[1])
	return right - cursor >= BODY_W


# ---------------------------------------------------------------- The shape of the stage (overriding the horizontal ones)

func test_the_level_is_ten_times_the_test_one() -> void:
	# Vertical: one screen wide, 20 screens tall, the camera only scrolls up, and you start at the very bottom
	await open_level()
	var camera := main.get_node("Camera2D") as CameraRig
	check("one screen wide", camera.limit_right - camera.limit_left == int(WIDTH),
		"%d..%d" % [camera.limit_left, camera.limit_right])
	check("twenty screens tall", camera.limit_bottom - camera.limit_top == int(HEIGHT),
		"%d..%d" % [camera.limit_top, camera.limit_bottom])
	check("the screen only climbs", camera.only_up)
	check("the player starts at the bottom", player.global_position.y > HEIGHT - SCREEN_H,
		str(player.global_position))
	check("falling out is judged below the bottom of the level", main.fall_y > HEIGHT, str(main.fall_y))


func test_it_really_has_pits() -> void:
	# A vertical stage has no pits (falling off the bottom of the view is the pit). Instead: both sides of the shaft are one continuous wall with no gap to slip out
	await open_level()
	for side: String in ["WallLeft", "WallRight"]:
		var wall := main.get_node("Level/" + side) as Platform
		check("%s runs the full height" % side, wall != null and wall.position.y <= 0.0
			and wall.position.y + wall.size.y >= HEIGHT, str(wall))


func test_every_pit_can_be_jumped() -> void:
	# "Passable" in a vertical stage = **you can climb from the ground all the way to the boss area floor**: jumping up (no more than one jump higher, not too far sideways,
	# nothing solid in the way), walking down, **climbing ladders** (the surface under a ladder connects to the one at its top). Every one-way ledge has to be reachable.
	var jump := await jump_height()
	check("setup: the jump has some height", jump > 60.0, "%.0f" % jump)
	await open_level()
	var all := faces()
	var ladders := tree.get_nodes_in_group(Ladder.GROUP)
	check("setup: there are ledges and ladders", all.size() > 100 and ladders.size() >= 10,
		"%d / %d" % [all.size(), ladders.size()])
	var start: Array = all.filter(func(f: Array) -> bool: return f[2] >= HEIGHT - 60.0)
	var seen := {}
	var frontier: Array = []
	for f: Array in start:
		seen[f[4]] = true
		frontier.append(f)
	while not frontier.is_empty():
		var here: Array = frontier.pop_back()
		for face: Array in all:
			if seen.has(face[4]):
				continue
			var down: bool = face[2] > here[2] and gap_x(here, face) <= REACH_X
			var climb := false
			for node in ladders:
				var ladder := node as Ladder
				var x := ladder.global_position.x
				var foot := ladder.global_position.y + ladder.height
				if here[0] <= x and x <= here[1] and absf(here[2] - foot) < 1.0 \
						and face[0] - 32.0 <= x and x <= face[1] + 32.0 and absf(face[2] - ladder.global_position.y) < 1.0:
					climb = true
			if down or climb or reachable_up(here, face, all, jump):
				seen[face[4]] = true
				frontier.append(face)
	var lost: Array = all.filter(func(f: Array) -> bool: return not f[3] and not seen.has(f[4]))
	check("every ledge can be climbed to from the floor", lost.is_empty(),
		str(lost.map(func(f: Array) -> String: return f[4]).slice(0, 8)))
	check("including the arena floor at the top", seen.has(arena_floor()[4]), arena_floor()[4])


func arena_floor() -> Array:
	# The widest surface in the top screen
	var best := []
	for face: Array in faces():
		if face[2] < SCREEN_H and (best.is_empty() or face[1] - face[0] > best[1] - best[0]):
			best = face
	return best


func test_the_player_gets_a_moment_before_the_first_enemy() -> void:
	# Vertical: no enemies on the spawn screen (the bottom screen)
	await open_level()
	var lowest := -INF
	for enemy in enemies():
		lowest = maxf(lowest, enemy.position.y)
	check("setup: there are enemies further up", lowest > -INF)
	check("but none on the opening screen", lowest < HEIGHT - SCREEN_H,
		"the lowest one is at y %.0f" % lowest)


func test_the_boss_waits_at_the_far_end() -> void:
	# Vertical: the boss is on **the top screen**, which has a whole floor and no other enemies
	await open_level()
	var boss: Boss = null
	for node in enemies():
		if node is Boss:
			boss = node
	check("there is a boss", boss is BossSkull, str(boss))
	if boss == null:
		return
	check("up in the last screen", boss.position.y < SCREEN_H, str(boss.position))
	var floor_ := arena_floor()
	check("there is an arena floor at the top", not floor_.is_empty())
	if floor_.is_empty():
		return
	check("it spans the shaft", floor_[1] - floor_[0] >= 500.0, "%.0f" % (floor_[1] - floor_[0]))
	# At its lowest the laser lines up exactly with a player standing on the floor
	var low := boss.position.y + BossSkull.BEAM_ORIGIN.y
	check("at its lowest its beam meets a player on the floor", absf(low - (floor_[2] - 16.0)) <= 1.0,
		"%.0f vs %.0f" % [low, floor_[2] - 16.0])
	for enemy in enemies():
		if enemy is Boss:
			continue
		check("%s is not in the arena" % enemy.name, enemy.position.y > SCREEN_H, str(enemy.position))


func test_the_crawl_passages_still_need_crouching() -> void:
	# The layered set's version only looks above the ground line (horizontal stages), while every block in the shaft is "below the ground line", so measure again by the same rule here:
	# under a solid block there is either no gap or room for a person (no gaps of 1~39)
	await open_level()
	var all := faces()
	var checked := 0
	for block: Array in all:
		if not block[3] or block[2] >= HEIGHT - 60.0:
			continue
		var below := INF
		for face: Array in all:
			if face != block and face[2] >= block[5] and face[0] < block[1] and face[1] > block[0]:
				below = minf(below, face[2] - block[5])
		if below == INF:
			continue
		checked += 1
		check("%s leaves no half-height slot under it" % block[4], below < 0.5 or below >= 40.0, "%.0f" % below)
	check("setup: there are floors over other floors", checked >= 20, str(checked))


# ---------------------------------------------------------------- Unique to this stage

func test_it_is_the_fourth_stage_in_the_catalog() -> void:
	if needs_art(): return
	var info := load(LEVEL_INFO) as LevelInfo
	check("it points at this scene", info.scene_path == level_path(), info.scene_path)
	check("and it brings the basement pack", info.skin != null
		and info.skin.resource_path.contains("basement"), str(info.skin))
	var levels := Catalog.levels()
	check("the catalog picks it up as the fourth one",
		levels.size() >= 4 and levels[3].scene_path == level_path(),
		"" if levels.size() < 4 else levels[3].scene_path)


func test_this_stage_brings_its_own_cast() -> void:
	await open_level()
	var kinds := {}
	for enemy in enemies():
		kinds[enemy.skin_key] = int(kinds.get(enemy.skin_key, 0)) + 1
	var wrong: Array[String] = []
	for key: StringName in kinds:
		if not String(key).begins_with("4_"):
			wrong.append(String(key))
	check("every enemy here belongs to stage 4", wrong.is_empty(), str(wrong))
	check("and all six types show up", kinds.size() >= 6, str(kinds.keys()))


func test_the_drones_hug_the_walls() -> void:
	# Flyers hug the side walls: they do not move sideways, and placed in the middle they would block the way up
	await open_level()
	var found := 0
	for enemy in enemies():
		if enemy is EnemyHoverGun:
			found += 1
			var x: float = enemy.position.x
			check("%s is by a wall" % enemy.name, x < 128.0 or x > WIDTH - 128.0, "x %.0f" % x)
	check("setup: there are drones", found >= 5, str(found))


func test_climbing_then_dropping_out_costs_a_fall_and_lands_you_on_screen() -> void:
	# Run the vertical rules on the real stage: climb halfway, the view follows; fall off the bottom of the view and lose health, then get brought back into view.
	# Clear the enemies first: otherwise the health lost might be from a hit, and what is measured would not be "falling into a pit"
	await open_level()
	for enemy in enemies():
		enemy.free()
	# Halfway: the string of platforms on the left of segment 5 (the freight lift shaft), with no crates or traps around
	player.global_position = Vector2(8.5 * CELL, seg_y(5, 35) - 16.0)
	player.velocity = Vector2.ZERO
	await frames(15)
	var stood := player.global_position
	var view := camera_rig().view_rect()
	check("the screen followed you up", view.has_point(stood), "%s in %s" % [stood, view])
	var full := player.health
	player.global_position = Vector2(stood.x, view.end.y + 60.0)
	await frames(3)
	check("dropping out of the bottom is a fall", player.health < full, "%d -> %d" % [full, player.health])
	check("and you land back on screen", camera_rig().view_rect().has_point(player.global_position),
		str(player.global_position))


func test_enemies_you_climb_past_are_cleared_without_pay() -> void:
	await open_level()
	var before := enemies().size()
	var xp := player.progress.xp
	var money := player.progress.money
	var high: Array = faces().filter(func(f: Array) -> bool:
		return not f[3] and f[2] < HEIGHT / 2.0 and f[2] > HEIGHT / 2.0 - 200.0)[0]
	player.global_position = Vector2((high[0] + high[1]) / 2.0, high[2] - 16.0)
	player.velocity = Vector2.ZERO
	await frames(10)
	check("the ones far below are gone", enemies().size() < before, "%d -> %d" % [before, enemies().size()])
	check("and nobody was paid for them", player.progress.xp == xp and player.progress.money == money,
		"xp %d -> %d" % [xp, player.progress.xp])


func test_the_boss_stays_on_screen_while_you_stand_on_the_arena_floor() -> void:
	# Seen in a screenshot: with the camera centred on the player, a boss floating high left the view while the player stood on the boss area floor
	await open_level()
	var boss: BossSkull = null
	for node in enemies():
		if node is BossSkull:
			boss = node
		else:
			node.free()
	check("setup: there is the skull", boss != null)
	if boss == null:
		return
	var floor_ := arena_floor()
	player.global_position = Vector2(200, floor_[2] - 16.0)
	player.velocity = Vector2.ZERO
	await frames(10)
	var view := camera_rig().view_rect()
	var box := (boss.get_node("CollisionShape2D").shape as RectangleShape2D).size
	var highest := boss._home.y - boss.rise - box.y / 2.0
	check("its highest point is on screen", highest >= view.position.y,
		"Boss highest %.0f, top of view %.0f" % [highest, view.position.y])
	check("and so is its lowest", boss._home.y + box.y / 2.0 <= view.end.y)
	# Every layer lines up: it can float as high as a player on the top platform
	var top_center := INF
	for face: Array in faces():
		if face[2] < SCREEN_H:
			top_center = minf(top_center, face[2] - 16.0)
	check("it can rise to line up with the highest ledge",
		boss._home.y - boss.rise + BossSkull.BEAM_ORIGIN.y <= top_center,
		"reaches up to %.0f, top-layer player at %.0f" % [boss._home.y - boss.rise + BossSkull.BEAM_ORIGIN.y, top_center])


# ---------------------------------------------------------------- Forced detours, run with the real rules

## Hold up / down to climb a ladder: **first wait until it really grabs the ladder** (at most half a second), then wait until it reaches the end and lets go.
## Waiting a fixed few frames before checking "still climbing" occasionally ran a beat slow in a full run and took "not grabbed yet" for "done climbing" (hit in a full run).
func climb(direction: StringName) -> void:
	await frames(10)
	Input.action_press(direction)
	for i in 30:
		await tree.physics_frame
		if player.is_climbing():
			break
	for i in 240:
		await tree.physics_frame
		if not player.is_climbing():
			break
	release_all_input()
	await frames(5)


func put_player(x: float, feet_y: float) -> void:
	player.global_position = Vector2(x, feet_y - 16.0)
	player.velocity = Vector2.ZERO
	snap_camera()
	await frames(3)


func test_the_sump_ceiling_is_climbed_not_jumped() -> void:
	# Segment 1: a whole **solid** floor overhead, reachable only by the ladder on the right.
	# Jump straight up from right under the floor (full-speed take-off): if it were one-way, you would pass up through it from below
	# Placed horizontally right above the platform on row 26: bounced back it lands on that (dropping only 40). Placed elsewhere it would fall below the bottom of the view
	# — the camera only scrolls up, this jump carried the view up, and falling means "falling into a pit"; a few of those and you are dead
	await open_empty()
	await put_player(29.5 * CELL, seg_y(1, 26))
	player.global_position = Vector2(29.5 * CELL, seg_y(1, 22) + 24.0)
	player.velocity = Vector2(0, -560)
	await frames(40)
	check("a jump from right under the slab bounces off it", player.global_position.y > seg_y(1, 22),
		"y %.0f, slab bottom %.0f" % [player.global_position.y, seg_y(1, 22)])
	check("and lands back on the ledge, alive", player.is_alive() and absf(feet() - seg_y(1, 26)) < 1.0,
		"feet %.1f hp %d" % [feet(), player.health])


func test_the_sump_ladder_goes_up_through_the_slab() -> void:
	# Separate from the previous case, each with a clean scene
	await open_empty()
	await put_player(33 * CELL, seg_y(1, 26))
	await climb(&"aim_up")
	check("the ladder takes you onto the slab", absf(feet() - seg_y(1, 20)) < 1.0, "feet %.1f" % feet())


func press_jump_held(n: int) -> void:
	Input.action_press(&"jump")
	await frames(n)
	release_all_input()
	await frames(20)


func test_the_boiler_room_ladder_is_walled_off_with_crates() -> void:
	# Segment 3: a whole stack of crates in front of the ladder on the right inside the building; you only reach it by breaking them
	await open_empty()
	var stack: Array = []
	for node in main.get_node("Traps").get_children():
		var crate := node as BreakableCrate
		if crate != null and absf(crate.position.x - 30 * CELL) < 1.0 and crate.position.y > seg_y(3, 28) \
				and crate.position.y < seg_y(3, 36):
			stack.append(crate)
	check("setup: the stack is there", stack.size() == 4, str(stack.size()))
	await put_player(24 * CELL, seg_y(3, 36))
	Input.action_press(&"move_right")
	Input.action_press(&"jump")
	await frames(120)
	release_all_input()
	check("you cannot get past the stack", player.global_position.x < 30 * CELL,
		"x %.0f" % player.global_position.x)
	for crate: BreakableCrate in stack:
		for i in crate.toughness:
			crate.take_damage(SHOT, Vector2.INF, player)
	await frames(5)
	Input.action_press(&"move_right")
	await frames(60)
	release_all_input()
	check("shot apart, the ladder is in reach", player.global_position.x > 33 * CELL,
		"x %.0f" % player.global_position.x)


func test_the_lift_shaft_only_goes_up_on_the_left() -> void:
	# Segment 5: a big stack of containers in the middle, the gap on the right sealed at the bottom, and walking right along the entry platform runs into the containers
	await open_empty()
	await put_player(6 * CELL, seg_y(5, 42))
	Input.action_press(&"move_right")
	await frames(90)
	release_all_input()
	check("the container stack stops you", player.global_position.x < 12 * CELL,
		"x %.0f" % player.global_position.x)

