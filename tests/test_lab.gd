extends GameTest
## 实验室素材包（第五关那一套，`tools/terrain_build.py lab` 从 Lab Tileset 生成）。
##
## 和别的区守的是同一批：一个区只装自己独有的、其余顺着 fallback 拿，地砖别挑成半格的，
## 背景挡得住清屏色，像拾取物的东西不要。这一关独有的：可打爆的障碍是**毒气罐**（四个破损阶段，
## 素材的 `Chest` 是掀盖子的补给箱、用不上），新机关是地刺。
## **音乐暂时借地下室那首**（素材包没有），所以这里不守「每个区一首」，守的是「有曲子可放」。

const PACK := "res://skins/lab/lab_skin.tres"
const ART := "res://skins/lab"


func pack() -> SkinPack:
	return load(PACK) as SkinPack


func zone_art(rel: String) -> Image:
	return (load("%s/%s" % [ART, rel]) as Texture2D).get_image()


func test_the_pack_brings_terrain_a_backdrop_and_its_traps() -> void:
	if needs_art(): return
	var mine := pack()
	for key: StringName in [&"terrain_ground", &"terrain_ledge", &"terrain_stone", &"trap_capsule", &"trap_spikes"]:
		check("it declares %s" % key, mine.appearances.has(key))
	check("a backdrop of its own", mine.backdrop != null
		and mine.backdrop.resource_path.contains("lab"), str(mine.backdrop))
	check("sounds are left to the fallback", mine.sounds.is_empty(), str(mine.sounds.size()))
	check("there is level music to play", mine.music.has(&"level"), str(mine.music.keys()))


func test_everything_else_comes_from_the_pack_behind_it() -> void:
	if needs_art(): return
	Skins.use(pack())
	for key: StringName in [&"biker", &"player_bullet", &"enemy_bullet", &"trap_barrel", &"ladder"]:
		var scene := pack().find_appearance(key)
		check("%s still resolves" % key, scene != null, str(scene))
	check("the HUD does too", Skins.hud() != null)
	check("and so do the sounds", Skins.sound(&"player_shoot") != null)


func test_the_terrain_art_is_this_zone_and_not_another() -> void:
	if needs_art(): return
	for name: String in ["ground", "ledge", "stone"]:
		var mine := zone_art("terrain/%s.png" % name)
		for other: String in ["cyberpunk", "industrial", "bar_street", "basement"]:
			var theirs := (load("res://skins/%s/terrain/%s.png" % [other, name]) as Texture2D).get_image()
			check("%s is not %s's" % [name, other], mine.get_data() != theirs.get_data())


func test_no_terrain_tile_is_half_empty() -> void:
	if needs_art(): return
	# 整行透明的地砖会让九宫格把空白也当成边（工业区那张薄条踩过的坑）
	for name: String in ["ground", "ledge", "stone"]:
		var image := zone_art("terrain/%s.png" % name)
		var empty := 0
		for y in image.get_height():
			var seen := false
			for x in image.get_width():
				if image.get_pixel(x, y).a > 0.03:
					seen = true
					break
			if not seen:
				empty += 1
		check("%s has no empty rows" % name, empty == 0, str(empty))


func test_the_backdrop_reaches_the_bottom_of_the_screen() -> void:
	if needs_art(): return
	var base := zone_art("backdrop/base.png")
	check("the back layer is a screen tall", base.get_height() >= 360, str(base.get_height()))
	var holes := 0
	for x in base.get_width():
		if base.get_pixel(x, base.get_height() - 1).a < 0.99:
			holes += 1
	check("and its bottom row is solid (no clear colour showing in pits)", holes == 0, str(holes))


func test_the_capsule_looks_more_broken_with_every_stage() -> void:
	if needs_art(): return
	await reset_scene(false, false, pack())
	var capsule := (load("res://scenes/trap_capsule.tscn") as PackedScene).instantiate() as BreakableCrate
	main.add_child(capsule)
	capsule.global_position = Vector2(400, 320 - capsule.size.y)
	await frames(2)
	var look := capsule.get_node("Visual") as StagedSpriteAppearance
	check("setup: the pack draws the capsule in stages", look != null)
	if look == null:
		return
	var seen: Array[String] = [look.current().resource_path.get_file()]
	for i in capsule.toughness:
		capsule.take_damage(SHOT, Vector2.INF, player)
		var now := look.current().resource_path.get_file()
		if now != seen[-1]:
			seen.append(now)
	check("whole -> cracked -> half -> shards", seen.size() == 4 and seen[0].begins_with("capsule_")
		and seen[1] == "capsule_cracked.png" and seen[2] == "capsule_half.png" and seen[3] == "capsule_debris.png",
		str(seen))
	check("the shards are lower than the whole capsule", _art_height(look.debris) < _art_height(look.intact[0]),
		"%d vs %d" % [_art_height(look.debris), _art_height(look.intact[0])])


func _art_height(texture: Texture2D) -> int:
	var image := texture.get_image()
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.03:
				return image.get_height() - y
	return 0


func test_only_shattered_capsules_are_scenery() -> void:
	if needs_art(): return
	# 完好的、打裂的、碎一半的罐子都还挡路——装饰里只能有碎完的那张，不然玩家分不清哪个打得碎
	var props := DirAccess.get_files_at(ART + "/props")
	var capsules := Array(props).filter(func(f: String) -> bool:
		return f.begins_with("capsule") and f.ends_with(".png"))
	check("one capsule picture among the props", capsules == ["capsule_shards.png"], str(capsules))
	check("and it is the same picture as a shattered trap",
		zone_art("props/capsule_shards.png").get_data() == zone_art("traps/capsule_debris.png").get_data())


func test_nothing_lying_around_looks_like_a_pickup() -> void:
	if needs_art(): return
	for name in DirAccess.get_files_at(ART + "/props"):
		var lower := name.to_lower()
		check("no %s in the props" % name, not (lower.begins_with("card") or lower.begins_with("money")
			or lower.begins_with("chest")))
