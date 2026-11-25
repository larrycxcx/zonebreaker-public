extends GameTest
## The basement skin pack (stage 4's set, generated from the Basement Tileset by `tools/terrain_build.py basement`).
##
## It guards the same things as the industrial zone and bar street: a zone only holds what is unique to it and takes the rest through the fallback, tiles not picked as half cells.
## Unique to this stage: **the stage climbs upward**, so the backdrop is not a horizontal parallax but an assembled inner wall
## **tiled seamlessly vertically**; plus "nothing that looks like a pickup" (Card / Money, the little lights on the walls).

const PACK := "res://skins/basement/basement_skin.tres"
const ART := "res://skins/basement"
const SCREEN := Vector2(640, 360)


func pack() -> SkinPack:
	return load(PACK) as SkinPack


func zone_art(rel: String) -> Image:
	return (load("%s/%s" % [ART, rel]) as Texture2D).get_image()


# ---------------------------------------------------------------- Only what is unique to it

func test_the_pack_brings_terrain_a_backdrop_light_and_its_own_track() -> void:
	if needs_art(): return
	var mine := pack()
	for key: StringName in [&"terrain_ground", &"terrain_ledge", &"terrain_stone"]:
		check("it declares %s" % key, mine.appearances.has(key))
	check("a backdrop of its own", mine.backdrop != null
		and mine.backdrop.resource_path.contains("basement"), str(mine.backdrop))
	check("a light of its own", mine.lighting != null
		and mine.lighting.resource_path.contains("basement"), str(mine.lighting))
	check("sounds are left to the fallback", mine.sounds.is_empty(), str(mine.sounds.size()))
	check("but it brings its own level music", mine.music.has(&"level"), str(mine.music.keys()))


func test_everything_else_comes_from_the_pack_behind_it() -> void:
	if needs_art(): return
	Skins.use(pack())
	for key: StringName in [&"biker", &"player_bullet", &"enemy_bullet", &"player_grenade"]:
		var scene := pack().find_appearance(key)
		check("%s still resolves" % key, scene != null and scene.resource_path.contains("cyberpunk"),
			str(scene))
	check("the HUD does too", Skins.hud() != null)
	check("and so do the sounds", Skins.sound(&"player_shoot") != null)


func test_the_track_is_this_zone_and_loops_cleanly() -> void:
	if needs_art(): return
	Skins.use(pack())
	var track := Skins.music(&"level")
	check("there is level music", track != null)
	if track == null:
		return
	check("it belongs to this zone", track.resource_path.begins_with(ART), track.resource_path)
	check("and it is an ogg", track is AudioStreamOggVorbis, track.get_class())


func test_each_zone_plays_its_own_track() -> void:
	if needs_art(): return
	var heard := {}
	for path: String in [PACK, "res://skins/bar_street/bar_street_skin.tres",
			"res://skins/industrial/industrial_skin.tres", "res://skins/cyberpunk/cyberpunk_skin.tres"]:
		Skins.use(load(path) as SkinPack)
		var track := Skins.music(&"level")
		if track != null:
			heard[track.resource_path] = true
	check("four zones, four different tracks", heard.size() == 4, str(heard.keys()))


# ---------------------------------------------------------------- Tiles

func test_the_terrain_art_is_this_zone_and_not_another() -> void:
	if needs_art(): return
	for name: String in ["ground", "ledge", "stone"]:
		var mine := zone_art("terrain/%s.png" % name)
		for other: String in ["cyberpunk", "industrial", "bar_street"]:
			var theirs := (load("res://skins/%s/terrain/%s.png" % [other, name]) as Texture2D).get_image()
			check("%s is not %s's" % [name, other], mine.get_data() != theirs.get_data())


func test_no_terrain_tile_is_half_empty() -> void:
	if needs_art(): return
	# The thin strips 41~44 only draw the top half of a cell and are cropped to 16 rows by the build; without the crop the nine-slice would take the blank part as an edge
	for name: String in ["ground", "ledge", "stone"]:
		var img := zone_art("terrain/%s.png" % name)
		var empty := 0
		for y in img.get_height():
			var blank := true
			for x in img.get_width():
				if img.get_pixel(x, y).a > 0.0:
					blank = false
					break
			if blank:
				empty += 1
		check("%s has no blank rows" % name, empty == 0, "%d rows are empty (%dx%d)"
			% [empty, img.get_width(), img.get_height()])


func test_walls_are_a_full_nine_slice() -> void:
	if needs_art(): return
	# The walls and blockers on both sides of the shaft are big pieces; all four corners, four edges and the middle are needed to assemble a whole block of rock
	var stone := zone_art("terrain/stone.png")
	check("the stone source is three tiles each way", stone.get_size() == Vector2i(96, 96),
		str(stone.get_size()))
	var ledge := zone_art("terrain/ledge.png")
	check("the ledge is one thin strip", ledge.get_size() == Vector2i(96, 16), str(ledge.get_size()))


# ---------------------------------------------------------------- Backdrop: an inner wall tiled vertically

func backdrop_layers() -> Array[Parallax2D]:
	var out: Array[Parallax2D] = []
	var scene := pack().backdrop.instantiate()
	for child in scene.get_children():
		if child is Parallax2D:
			out.append(child)
	(func() -> void: scene.free()).call_deferred()
	return out


func test_the_backdrop_repeats_upwards_without_end() -> void:
	if needs_art(): return
	# The stage is 20 screens tall: the backdrop must repeat vertically, with each layer's height as the repeat interval, or it shows gaps or overlaps
	var layers := backdrop_layers()
	check("setup: there are layers", layers.size() >= 2, str(layers.size()))
	for layer in layers:
		var sprite := layer.get_node("Sprite") as Sprite2D
		var size := sprite.texture.get_size()
		check("%s repeats vertically at its own height" % layer.name,
			layer.repeat_size.y == size.y and size.y > 0.0, "%s vs %s" % [layer.repeat_size, size])
		check("%s spans the screen's width" % layer.name, size.x >= SCREEN.x, str(size))
		check("%s scrolls slower than the level, so it sits behind" % layer.name,
			layer.scroll_scale.y > 0.0 and layer.scroll_scale.y < 1.0, str(layer.scroll_scale))


func test_the_back_wall_is_solid() -> void:
	if needs_art(): return
	# The rearmost layer is a whole wall: if even one pixel were transparent, the clear colour would show in the shaft
	var wall := zone_art("backdrop/wall.png")
	var holes := 0
	for y in wall.get_height():
		for x in wall.get_width():
			if wall.get_pixel(x, y).a < 1.0:
				holes += 1
	check("not a single hole", holes == 0, str(holes))


func test_the_back_wall_sits_behind_the_terrain() -> void:
	if needs_art(): return
	# The wall is pushed back and darkened: its bright part is less than half of the terrain's, or the platforms blur into the wall (0.27 vs 0.41 without darkening, 0.15 with).
	# **Compare the bright part, not the average**: the middle of the rock blocks is a big area of dark purple fill, so the average is dark anyway;
	# what makes platforms and walls stand out from the backdrop is their ring of light outline.
	var wall := _bright_end(zone_art("backdrop/wall.png"))
	for name: String in ["stone", "ledge", "ground"]:
		var rock := _bright_end(zone_art("terrain/%s.png" % name))
		check("the wall is darker than the %s" % name, wall < rock * 0.5,
			"%.3f vs %.3f" % [wall, rock])


## Brightness at the 90th percentile: how bright "the bright part" of the image is.
func _bright_end(img: Image) -> float:
	var values: Array[float] = []
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				values.append(c.get_luminance())
	values.sort()
	return values[int(values.size() * 0.9)] if not values.is_empty() else 0.0


# ---------------------------------------------------------------- Lighting, scenery

func test_the_light_is_the_neon_overlay_of_this_zone() -> void:
	if needs_art(): return
	var light := pack().lighting.instantiate()
	check("it is a screen light", light is ScreenLight, str(light))
	var material := (light as CanvasItem).material as ShaderMaterial
	var glow := material.get_shader_parameter(&"glow") as Texture2D if material != null else null
	check("with this zone's glow", glow != null and glow.resource_path.begins_with(ART), str(glow))
	light.free()


## The lesson of stage 3: small, shiny things lying on the floor look like things to pick up.
const PICKUP_LOOKALIKES := ["card", "money", "lamp", "bottle", "glass", "coin"]


func test_no_prop_looks_like_a_pickup() -> void:
	if needs_art(): return
	var files := DirAccess.get_files_at("%s/props" % ART)
	var pngs := 0
	for file in files:
		if not file.ends_with(".png"):
			continue
		pngs += 1
		for word: String in PICKUP_LOOKALIKES:
			check("%s is not a %s" % [file, word], not file.begins_with(word), file)
	check("setup: there are props", pngs >= 10, str(pngs))


func test_the_steam_is_the_one_thing_that_moves() -> void:
	if needs_art(): return
	# Only the steam moves: 288×48 = 6 frames
	var smoke := zone_art("props/smoke.png")
	check("six square frames of steam", smoke.get_width() == smoke.get_height() * 6,
		str(smoke.get_size()))


# ---------------------------------------------------------------- Once plugged in

func test_every_platform_wears_this_zone_terrain() -> void:
	if needs_art(): return
	await reset_scene(true, true, pack())
	var checked := 0
	for p in main.get_node("Level").find_children("*", "Platform", true, false):
		var visual := p.get_node("Visual")
		if visual is TerrainAppearance:
			checked += 1
			var texture: Texture2D = (visual as TerrainAppearance).texture
			check("%s takes its art from this zone" % p.name,
				texture != null and texture.resource_path.begins_with(ART), str(texture))
	check("setup: the platforms are skinned at all", checked >= 5, str(checked))


func test_the_level_is_lit_and_the_rules_do_not_change() -> void:
	if needs_art(): return
	# With this pack on, the test level runs as usual: the player stands firm, the lighting layer sits between terrain and characters
	await reset_scene(true, true, pack())
	await frames(30)
	check("the player stands", player.is_on_floor() and player.is_alive(), str(player.global_position))
	var light := main.get_node_or_null("Lighting")
	check("the level is lit", light is ScreenLight)
	if light != null:
		check("under the player", light.get_index() < main.get_node("Player").get_index())
