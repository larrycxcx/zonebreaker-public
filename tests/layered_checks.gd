extends "res://tests/level_checks.gd"
## Shared checks for **layered stages** (grid maps built by `tools/map_build.py`): stages 1 and 2 both inherit this set.
##
## The direction-independent ones (enemies standing on something, no damage on arrival, nobody walking off a ledge, scenery without collision, no duplicate names,
## the stage running on its own, the boss at the end) are inherited from the horizontal stage set (`level_checks.gd`). The geometry checks specific to horizontal stages are **overridden one by one** here:
## a pit in a layered stage cannot necessarily be jumped (you take the platforms above), a wall cannot necessarily be climbed (you take a ladder) — that is the design.
## Subclasses override `level_path()` / `level_stage()` / `zone()`, then add this stage's own checks, running the forced detours with **the real rules**.


## Which skin pack's atlas this stage's tiles come from (`skins/<zone>/tiles/atlas.png`).
func zone() -> String:
	return ""


const CELL := 16.0
const SEGMENT := 80 * 16.0
const MIDDLE_FLOOR := 208.0


## Left x of column col in segment seg (counting from 1).
func col_x(seg: int, col: int) -> float:
	return (seg - 1) * SEGMENT + col * CELL


func feet() -> float:
	return player.global_position.y + 16.0


## Open the stage and clear all enemies: the checks below only test terrain and traps, and stray bullets would spoil the results.
func open_empty() -> void:
	await open_level()
	keep_only_enemies([])
	await frames(2)


func solid_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for node in terrain():
		var slab := node as Platform
		if not slab.one_way:
			out.append(Rect2(slab.position, slab.size))
	return out


# ---------------------------------------------------------------- Overridden: layered stage terrain

## Terrain blocks, **excluding the invisible cover on top of ladders** (it hangs under the ladder node, its origin is the ladder top, it is not a floating platform).
func terrain() -> Array:
	return super.terrain().filter(func(node: Node) -> bool: return not node.get_parent() is Ladder)


## Surfaces to stand on: the tops of **all** platforms (layered stages have solid floors, not just the ground and one-way platforms). The side walls do not count.
func surfaces() -> Array:
	var found := []
	for node in terrain():
		var slab := node as Platform
		if slab.position.y <= 0.0:
			continue
		found.append([slab.position.x, slab.position.x + slab.size.x, slab.position.y])
	return found


## The ground is merged from cells: a conveyor is its own block, joined end to end with the ground either side — the seams are not pits.
func pits() -> Array[Vector2]:
	var found: Array[Vector2] = []
	for pit in super.pits():
		if pit.y - pit.x > 1.0:
			found.append(pit)
	return found


## At least how many pits this stage has (without first confirming there are pits, the check below would compare thin air).
func min_pits() -> int:
	return 3


func test_it_really_has_pits() -> void:
	await open_level()
	check("the ground is broken up", pits().size() >= min_pits(), str(pits().size()))


func test_every_pit_can_be_jumped() -> void:
	# A pit in a layered stage **cannot necessarily be jumped** (the settling pit is 12 cells wide) — if it cannot, a string of girders overhead has to bridge it,
	# with jumpable gaps between the pieces. A pit with neither is a dead end.
	var reach := await jump_distance()
	check("setup: a jump really covers some ground", reach > 80.0, "%.0f" % reach)
	await open_level()
	var bridged := 0
	for pit in pits():
		if pit.y - pit.x <= reach:
			continue
		var overhead := []
		for face in surfaces():
			if face[2] < GROUND_Y and face[1] > pit.x and face[0] < pit.y:
				overhead.append(face)
		overhead.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var cursor := pit.x
		for face in overhead:
			if face[0] - cursor <= reach and face[1] > cursor:
				cursor = face[1]
		bridged += 1
		# Last piece: jump / drop from the end of the girders to the far side
		check("the wide pit at %.0f has walkways over it" % pit.x, pit.y - cursor <= reach,
			"covered up to %.0f of %.0f..%.0f" % [cursor, pit.x, pit.y])
	check("setup: some pits are too wide to jump", bridged >= 2, str(bridged))


func test_nothing_is_higher_than_a_jump() -> void:
	# Layered stages have plenty of places higher than a jump (a floor height of 96, which is the design), so this check becomes:
	# **every ladder connects to a surface at both ends**, **every floating platform has a way up** (reachable by a jump from below, a ladder top above it,
	# a surface at the same height within one jump to the side, or a surface overhead to drop down from).
	var top := await jump_height()
	var reach := await jump_distance()
	await open_level()
	var faces := surfaces()
	var ladders := tree.get_nodes_in_group(Ladder.GROUP)
	check("setup: the level has ladders", ladders.size() >= 6, str(ladders.size()))
	for node in ladders:
		var ladder := node as Ladder
		var x := ladder.global_position.x
		var top_ok := false
		var bottom_ok := false
		for face in faces:
			if face[0] < x and x < face[1] and absf(face[2] - (ladder.global_position.y + ladder.height)) < 1.0:
				bottom_ok = true
			if face[0] <= x + 16.0 and x - 16.0 <= face[1] and absf(face[2] - ladder.global_position.y) < 1.0:
				top_ok = true
		check("%s stands on a floor" % ladder.name, bottom_ok)
		check("%s comes out onto a floor" % ladder.name, top_ok)
	for node in terrain():
		var slab := node as Platform
		if not slab.one_way:
			continue
		var y := slab.position.y
		var left := slab.position.x
		var right := slab.position.x + slab.size.x
		var way := false
		for face in faces:
			var near: bool = face[1] >= left - 120.0 and face[0] <= right + 120.0
			if near and face[2] > y and face[2] - y <= top:
				way = true          # A jump from below
			if absf(face[2] - y) < 1.0 and face[0] != left \
					and (absf(face[0] - right) <= reach or absf(left - face[1]) <= reach):
				way = true          # Same height, within reach
			if face[2] < y and face[0] < right + reach and face[1] > left - reach:
				way = true          # A surface overhead or diagonally above: drop down, or jump down onto it
		for lnode in ladders:
			var ladder := lnode as Ladder
			if absf(ladder.global_position.y - y) < 1.0 and left - 32.0 <= ladder.global_position.x \
					and ladder.global_position.x <= right + 32.0:
				way = true          # A ladder top above it or right next to it
		check("%s can be reached" % slab.name, way, "%.0f..%.0f at %.0f" % [left, right, y])


func test_the_crawl_passages_still_need_crouching() -> void:
	# This stage has no crawl passages. What it guards is the opposite: **under a floor there is either no gap (0) or room for a person to stand** —
	# a gap of 1~39 that people cannot squeeze through and that half blocks bullets is obviously a drawing mistake.
	await open_level()
	var faces := surfaces()
	var checked := 0
	for node in terrain():
		var slab := node as Platform
		if slab.one_way or slab.position.y <= 0.0:
			continue
		var bottom := slab.position.y + slab.size.y
		if bottom >= GROUND_Y:
			continue
		var below := INF
		for face in faces:
			if face[2] >= bottom and face[0] < slab.position.x + slab.size.x and face[1] > slab.position.x:
				below = minf(below, face[2] - bottom)
		if below == INF:
			continue
		checked += 1
		check("%s leaves no half-height slot under it" % slab.name, below < 0.5 or below >= 40.0,
			"%.0f" % below)
	check("setup: there are floors over other floors", checked >= 20, str(checked))


## Stacks of crates: crates in the same column touching vertically (one crate height apart) form a stack. The key is that column's x.
## **Grouping by column alone is not enough**: in a shaft, crates of two segments may share a column (stage 4), and grouping by column would merge two stacks floors apart.
func crate_stacks() -> Dictionary:
	var crates: Array = main.get_node("Traps").get_children().filter(
		func(n: Node) -> bool: return n is BreakableCrate)
	crates.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return a.position.x < b.position.x or (a.position.x == b.position.x and a.position.y < b.position.y))
	var stacks := {}
	var current: Array = []
	for crate: BreakableCrate in crates:
		var last: BreakableCrate = null if current.is_empty() else current[-1]
		if last != null and (last.position.x != crate.position.x
				or absf(crate.position.y - last.position.y - crate.size.y) > 0.5):
			stacks["%d@%d" % [int(last.position.x), int(last.position.y)]] = current
			current = []
		current.append(crate)
	if not current.is_empty():
		stacks["%d@%d" % [int(current[-1].position.x), int(current[-1].position.y)]] = current
	return stacks


func test_the_blocked_routes_really_block_and_really_have_a_way_over() -> void:
	# The horizontal stages' "blockers" are **crates stacked to the ceiling** in this stage: you only get through by breaking them. Between a full stack and the ceiling
	# there must not be room for a person (32), or you would not even need to shoot.
	await open_level()
	var sealed := 0
	var stacks := crate_stacks()
	for key: String in stacks:
		var stack: Array = stacks[key]
		var x: float = (stack[0] as BreakableCrate).position.x
		var top := INF
		var bottom := -INF
		for crate: BreakableCrate in stack:
			top = minf(top, crate.position.y)
			bottom = maxf(bottom, crate.position.y + crate.size.y)
		var ceiling := -INF
		for rect in solid_rects():
			if rect.position.x < x + 32.0 and rect.end.x > x and rect.end.y <= top + 0.5:
				ceiling = maxf(ceiling, rect.end.y)
		# By stacked height, not number: three crates are 72, two gas capsules 96 — both too high to jump, both have to be broken
		if bottom - top >= 72.0:
			sealed += 1
			check("the stack at %s reaches the ceiling" % key, top - ceiling < 32.0,
				"%.0f left over it" % (top - ceiling))
	check("setup: some corridors are sealed with crates", sealed >= 2, str(sealed))


func test_no_enemy_is_stuck_in_a_crawl_passage() -> void:
	# In layered-stage terms: **no enemy's body is buried in something solid** (that is what one row off looks like)
	await open_level()
	var solids := solid_rects()
	for node in main.get_node("Enemies").get_children():
		var enemy := node as Enemy
		if enemy == null or hangs_in_the_air(enemy):
			continue
		var body := Rect2(enemy.position.x - 11.0, enemy_feet(enemy) - 31.0, 22.0, 30.0)
		for rect in solids:
			check("%s is not inside the floor" % enemy.name, not body.intersects(rect),
				"%s vs %s" % [body, rect])



# ---------------------------------------------------------------- What every layered stage should have

func test_the_tiles_come_from_this_zones_atlas() -> void:
	if needs_art(): return
	# The visuals come from the tiles (`TileArt`); the collision platforms are hidden
	await open_level()
	for layer in ["FrontTiles", "BackTiles"]:
		var art := main.get_node(layer) as TileArt
		check("%s draws %s tiles" % [layer, zone()], art != null and art.atlas != null
			and art.atlas.resource_path.begins_with("res://skins/%s/" % zone()))
	var shown := 0
	for node in terrain():
		if (node as Platform).visible and (node as Platform).position.y > 0.0:
			shown += 1
	check("and the collision platforms are hidden", shown == 0, str(shown))


func test_every_barrel_stands_next_to_an_enemy() -> void:
	# What the user asked for was "next to enemies, one shot and it blows up" — a barrel standing in an empty spot is just exploding decoration
	await open_level()
	var barrels := 0
	for node in main.get_node("Traps").get_children():
		var barrel := node as ExplosiveBarrel
		if barrel == null:
			continue
		barrels += 1
		var nearest := INF
		for enemy in enemies():
			var e := enemy as Enemy
			if hangs_in_the_air(e) or absf(e.position.y - barrel.position.y) > 24.0:
				continue
			nearest = minf(nearest, absf(e.position.x - barrel.position.x))
		check("%s has an enemy right beside it" % barrel.name, nearest <= 72.0, "%.0f" % nearest)
	check("setup: the level has barrels", barrels >= 10, str(barrels))
