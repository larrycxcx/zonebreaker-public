extends GameTest
## The cyberpunk skin pack's terrain and backdrop (generated from the Green Zone Tileset by tools/terrain_build.py).
##
## The terrain does not switch to TileMap: levels are still built from platform.tscn, with the look nine-sliced and tiled to the platform size (TerrainAppearance).
## What it guards: the nine-slice is cut correctly (fills the whole length, no scaling, outlines at both ends intact), every platform picks the right terrain, the picture and the hitbox agree
## (the standing surface is the top of the hitbox; only the bits under floating platforms hang down a few pixels; crawl passage roofs have flat bottoms so the clearance looks as it is),
## and **switching skins does not change the rules** — every platform's collision shape, the height of standing on platforms and whether crawl passages can be passed are exactly the same with blocks and sprites.
## The backdrop is display only, at the very bottom; the default pack has no backdrop.

const SKIN := "res://skins/cyberpunk/cyberpunk_skin.tres"


func skin() -> SkinPack:
	return load(SKIN) as SkinPack


func platforms() -> Array[Platform]:
	var out: Array[Platform] = []
	for node in main.get_node("Level").find_children("*", "Platform", true, false):
		out.append(node as Platform)
	return out


# ---------------------------------------------------------------- How the nine-slice is cut

func test_pieces_cover_the_length_without_scaling() -> void:
	# Every length has to work: laid out continuously from 0 to the end without overlaps, every source segment inside the source image (source and target segments the same length = cropped, never scaled)
	for case in [[96, 96, 32, 32], [112, 96, 32, 32], [128, 96, 32, 32], [16, 32, 3, 3], [8, 32, 3, 3],
			[40, 64, 32, 0], [1280, 32, 0, 0], [22, 32, 10, 12], [50, 32, 10, 3], [4, 32, 3, 3]]:
		var parts: Array = TerrainAppearance.pieces(case[0], case[1], case[2], case[3])
		var at := 0
		var ok := true
		for part in parts:
			ok = ok and part[0] == at and part[1] > 0 and part[2] >= 0 and part[2] + part[1] <= case[1]
			at += part[1]
		check("pieces %s tile the whole length" % [case], ok and at == case[0], str(parts))


func test_the_ends_keep_their_outline() -> void:
	# The head segment starts at the source's column 0 and the tail segment ends at its last column: the outlines and rounded corners at both ends of a platform are always drawn
	for case in [[112, 96, 32, 32], [8, 32, 3, 3], [22, 32, 10, 12]]:
		var parts: Array = TerrainAppearance.pieces(case[0], case[1], case[2], case[3])
		var last: Array = parts[-1]
		check("pieces %s start at the source's first column" % [case], parts[0][2] == 0, str(parts))
		check("pieces %s end at the source's last column" % [case], last[2] + last[1] == case[1], str(parts))


# ---------------------------------------------------------------- Once plugged in

func test_every_platform_wears_the_right_terrain() -> void:
	if needs_art(): return
	await reset_scene(true, true, skin())
	for p in platforms():
		var visual := p.get_node("Visual")
		check("%s is drawn by the skin" % p.name, visual is TerrainAppearance, str(visual))
		var want := &"terrain_ground" if p.name == "Ground" else (&"terrain_ledge" if p.one_way else &"terrain_stone")
		check("%s uses %s" % [p.name, want], p.terrain_key() == want, str(p.terrain_key()))
		if visual is TerrainAppearance:
			var look := visual as TerrainAppearance
			check("%s: the art is as wide as the platform" % p.name, look.drawn_size().x == roundi(p.size.x),
				"%s vs %s" % [look.drawn_size(), p.size])
			check("%s: the art starts at the platform's top-left (you stand on its top edge)" % p.name,
				look.position == Vector2.ZERO)
			check("%s: the art has no collision" % p.name,
				look.find_children("*", "CollisionObject2D", true, false).is_empty()
				and look.find_children("*", "CollisionShape2D", true, false).is_empty())


func test_only_ledges_hang_below_their_hitbox() -> void:
	await reset_scene(true, true, skin())
	for p in platforms():
		var look := p.get_node("Visual") as TerrainAppearance
		if look == null:
			continue
		var below := look.drawn_size().y - roundi(p.size.y)
		if p.one_way:
			# Bits hang under floating platforms: only a few pixels, so the platform does not look much thicker than its hit check
			check("%s hangs only a little below its hitbox" % p.name, below > 0 and below <= 6, "%dpx" % below)
		else:
			# Solid blocks have flat bottoms: the crawl passage's drawn clearance is the real one
			check("%s ends exactly at its hitbox" % p.name, below == 0, "%dpx" % below)


func test_walls_built_in_tests_get_the_terrain_too() -> void:
	if needs_art(): return
	await reset_scene(false, false, skin())
	var wall := add_wall(400, 40)
	await frames(1)
	var look := wall.get_node("Visual") as TerrainAppearance
	check("a wall added later is drawn as stone", look != null and wall.terrain_key() == &"terrain_stone", str(wall.get_node("Visual")))
	if look != null:
		check("and fits the wall", look.drawn_size() == Vector2i(8, 40), str(look.drawn_size()))


func test_the_default_pack_keeps_the_blocks() -> void:
	await reset_scene(true, true)
	for p in platforms():
		check("%s keeps its placeholder block" % p.name, not (p.get_node("Visual") is TerrainAppearance))
	check("and there is no backdrop", main.get_node_or_null("Backdrop") == null)


func test_the_backdrop_is_behind_everything_and_pure_display() -> void:
	if needs_art(): return
	await reset_scene(true, true, skin())
	var backdrop := main.get_node_or_null("Backdrop")
	check("the skin puts a backdrop in the level", backdrop != null)
	if backdrop == null:
		return
	check("drawn first, behind everything", backdrop.get_index() == 0, str(backdrop.get_index()))
	check("it has parallax layers", backdrop.find_children("*", "Parallax2D", true, false).size() >= 4)
	check("it has no collision",
		backdrop.find_children("*", "CollisionObject2D", true, false).is_empty()
		and backdrop.find_children("*", "CollisionShape2D", true, false).is_empty())


# ---------------------------------------------------------------- Switching skins does not change the rules

func measure(pack: SkinPack) -> Dictionary:
	await reset_scene(false, true, pack)
	var out := {}
	var shapes := []
	for p in platforms():
		var shape := p.get_node("CollisionShape2D") as CollisionShape2D
		shapes.append([String(p.name), p.global_position + shape.position, (shape.shape as RectangleShape2D).size, shape.one_way_collision])
	out["platforms"] = str(shapes)
	# Landing on a floating platform: the standing height
	player.global_position = Vector2(208, 200)
	player.velocity = Vector2.ZERO
	await frames(40)
	out["stands_on_ledge_at"] = snappedf(player.global_position.y, 0.01)
	out["on_floor"] = player.is_on_floor()
	# Crawling through the crawl passage prone: you can get from the left side to the right
	player.global_position = Vector2(560, 304)
	player.velocity = Vector2.ZERO
	await frames(5)
	Input.action_press("crouch")
	Input.action_press("move_right")
	await frames(150)
	release_all_input()
	out["crawled_to"] = snappedf(player.global_position.x, 1.0)
	return out


func test_the_terrain_skin_changes_nothing_about_the_rules() -> void:
	var blocks := await measure(Skins.default_skin())
	var sprites := await measure(skin())
	check("the player really stands on the ledge and crawls through in this test",
		blocks["on_floor"] and blocks["stands_on_ledge_at"] < 250.0 and blocks["crawled_to"] > 704.0, str(blocks))
	for key: String in blocks:
		check("%s is the same with either skin" % key, blocks[key] == sprites[key],
			"blocks %s, sprites %s" % [blocks[key], sprites[key]])
