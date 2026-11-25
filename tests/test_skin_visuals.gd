extends GameTest
## The visual side of skin packs: character visuals and effects can be swapped as a whole pack, and **only the look changes, not the rules**.
## The sound half is in test_audio.gd.

const STUB := "res://tests/stub_appearance.gd"


## Make a skin pack on the spot: what goes into appearances / effects is up to the arguments, everything else falls back to the default pack.
func make_skin(appearances := {}, effects := {}) -> SkinPack:
	var skin := SkinPack.new()
	skin.display_name = "Test skin"
	skin.fallback = Skins.default_skin()
	for key in appearances:
		skin.appearances[key] = appearances[key]
	for key in effects:
		skin.effects[key] = effects[key]
	return skin


## Pack a script into a scene (to use as a visual or effect).
func scene_of(script_path: String) -> PackedScene:
	var node := Node2D.new()
	node.set_script(load(script_path))
	var scene := PackedScene.new()
	scene.pack(node)
	node.free()
	return scene


func test_keys_cover_everyone() -> void:
	# Every character in the stage needs a skin key, and the keys must be in the list (art makers prepare by the list)
	await reset_scene(true)
	var actors: Array[Node] = [player]
	actors.append_array(enemies())
	# Each character's key has to match and cannot be left empty (left empty it falls back to the base class default walker, which you cannot tell on screen)
	var expected := {
		"Player": PlayerProgress.DEFAULT_LOOK, "WalkerA": &"1_a", "WalkerB": &"1_b", "WalkerC": &"1_c",
		"WalkerF": &"1_f", "Turret1": &"1_g", "Turret2": &"1_g",
		"FlyerE": &"1_e", "ChaserD": &"1_d", "BossMissile": &"1_boss",
	}
	for actor in actors:
		var key: StringName = actor.get(&"skin_key")
		check("%s uses the %s skin" % [actor.name, expected.get(String(actor.name), "?")],
			key == expected.get(String(actor.name)), str(key))


func test_the_key_list_is_a_readme_not_a_whitelist() -> void:
	if needs_art(): return
	# `APPEARANCE_KEYS` is documentation for art makers. **It must not be used as a whitelist**:
	# each of the 23 stages has its own enemies and bosses, new keys keep coming, and as a whitelist "add an enemy" would mean changing a constant, which DLC cannot do at all.
	# What needs guarding is the reverse: **every key filled in a pack has to really draw something**.
	var pack := load("res://skins/cyberpunk/cyberpunk_skin.tres") as SkinPack
	for key: StringName in pack.appearances:
		var scene: PackedScene = pack.appearances[key]
		check("%s brings a scene" % key, scene != null)
		var made := scene.instantiate() if scene != null else null
		check("%s's scene really is an Appearance" % key, made is Appearance, str(made))
		if made != null:
			made.free()
	# A key made up on the spot that is not in the list still installs — adding new enemies later does not mean coming back to change the constant
	var invented := SkinPack.new()
	invented.fallback = Skins.default_skin()
	invented.appearances = {&"zone_09_sniper": pack.appearances.get(&"1_a")}
	check("a key nobody listed still resolves", invented.find_appearance(&"zone_09_sniper") != null)


func test_default_skin_leaves_the_built_in_art_alone() -> void:
	await reset_scene(true)
	check("the default pack ships no appearance overrides", Skins.default_skin().appearances.is_empty())
	check("and no effect overrides", Skins.default_skin().effects.is_empty())
	check("so characters keep the art from their own scene", player.get_node("Visual") is Appearance)


func test_a_skin_replaces_a_character_s_appearance() -> void:
	# Switch to a pack that only provides the "player visual": the player is reskinned, enemies stay as they are
	await reset_scene(true, false, make_skin({PlayerProgress.DEFAULT_LOOK: scene_of(STUB)}))
	keep_only_enemies(["WalkerA"])
	await frames(5)
	var skinned: Node = player.get_node("Visual")
	check("the player got the skin's appearance", skinned.get_script().resource_path == STUB, str(skinned.get_script()))
	check("it is still called Visual and sits on the player", skinned.get_parent() == player)
	check("the enemy kept its own", main.get_node("Enemies/WalkerA/Visual").get_script().resource_path != STUB)
	# After reskinning it still plays, with the hit detection unchanged
	var muzzle := player._muzzle_position(Vector2.RIGHT) - player.global_position
	check("judgement points unchanged", muzzle == Player.LEVEL_MUZZLE, str(muzzle))
	Input.action_press("move_right")
	await frames(6)
	release_all_input()
	check("still moves", player.global_position.x > 64.0)
	check("and the logic drives it through the interface", (skinned.calls as Array).has("face"), str(skinned.calls))


func test_a_skin_replaces_an_effect() -> void:
	# Switch to a pack that only provides the "muzzle flash"
	await reset_scene(false, false, make_skin({}, {&"muzzle_flash": scene_of(STUB)}))
	player.global_position = Vector2(400, 304)
	player.velocity = Vector2.ZERO
	await frames(10)
	player._shoot(Vector2.RIGHT)
	await frames(1)
	var fx: Fx = main.get_node("Fx")
	var effects := fx.get_children()
	check("the flash came from the skin", not effects.is_empty() and effects[0].get_script().resource_path == STUB,
		str(effects.map(func(e): return e.get_script())))


func test_missing_entries_fall_back() -> void:
	# Anything not filled in the pack falls back: visuals to what the character scene brings, effects to the default scenes configured on Fx
	await reset_scene(false, false, make_skin())
	player.global_position = Vector2(400, 304)
	await frames(10)
	check("appearance falls back to the built-in one", player.get_node("Visual").get_script().resource_path.ends_with("appearance.gd"))
	player._shoot(Vector2.RIGHT)
	await frames(1)
	var fx: Fx = main.get_node("Fx")
	check("effects fall back to the Fx defaults", not fx.get_children().is_empty())


func test_a_broken_skin_does_not_break_the_game() -> void:
	# The skin pack filled a visual with a plain scene (no Appearance script on the root): fall back to the default visual, the game runs as usual
	var not_an_appearance := PackedScene.new()
	var node := Node2D.new()
	not_an_appearance.pack(node)
	node.free()
	await reset_scene(false, false, make_skin({PlayerProgress.DEFAULT_LOOK: not_an_appearance}))
	await frames(10)
	check("kept the built-in appearance", player.get_node("Visual") is Appearance)
	Input.action_press("move_right")
	await frames(6)
	release_all_input()
	check("and the game still runs", player.global_position.x > 64.0)


func test_appearances_fall_back_through_the_chain() -> void:
	# Pack A provides the player visual, pack B has nothing of its own with fallback pointing to A: using B has to get A's visual
	var pack_a := make_skin({PlayerProgress.DEFAULT_LOOK: scene_of(STUB)})
	var pack_b := make_skin()
	pack_b.fallback = pack_a
	await reset_scene(false, false, pack_b)
	await frames(5)
	check("the appearance came from the fallback pack", player.get_node("Visual").get_script().resource_path == STUB,
		str(player.get_node("Visual").get_script()))


func test_the_explosion_is_drawn_by_the_fx_layer() -> void:
	# The grenade does not draw its explosion, it only reports the event; the picture belongs to Fx (so it can be replaced by skin packs too)
	await reset_scene()
	player.global_position = Vector2(400, 304)
	player.velocity = Vector2.ZERO
	await frames(10)
	var grenade: Grenade = load("res://scenes/grenade.tscn").instantiate()
	main.add_child(grenade)
	grenade.global_position = Vector2(460, 300)
	await frames(2)
	var fx: Fx = main.get_node("Fx")
	for effect in fx.get_children():
		effect.free()
	# Deliberately changed to a radius different from the effect scene's default (56), otherwise "not scaled by radius" would not show
	grenade.blast_radius = 80.0
	var radius := grenade.blast_radius # It frees itself after exploding, so note it down first
	grenade.explode()
	await frames(2)
	var blasts := fx.get_children().filter(func(e): return e.get("radius") != null)
	check("an explosion effect appears", not blasts.is_empty(), str(fx.get_children()))
	if not blasts.is_empty():
		check("sized by the grenade's blast radius", blasts[0].radius == radius,
			"%s vs %s" % [blasts[0].radius, radius])
		check("drawn where it went off", blasts[0].global_position.distance_to(Vector2(460, 300)) < 4.0,
			str(blasts[0].global_position))



## The directories of third-party packs: only these packs themselves (and their visual scenes in `scenes/skins/`) may reference files in them directly.
const THIRD_PARTY_PACKS := ["res://skins/cyberpunk/", "res://skins/industrial/",
	"res://skins/bar_street/", "res://skins/basement/", "res://skins/lab/"]


func test_nothing_outside_the_packs_hard_links_their_art() -> void:
	# The public version strips out third-party art (`tools/export_public.py`). A `.tres` / `.tscn` that ext_resources
	# a missing file **fails to load entirely**: the rifle's `.tres` could not be read because its icon was missing, and the player did not even get a gun.
	# So outside the skin packs everything stores paths (`icon_path`, `skin_path`, `texture_path`, `atlas_path`) and only loads them when the file is there.
	var offenders: Array[String] = []
	var scanned := [0]
	_scan_for_hard_links("res://", offenders, scanned)
	check("setup: scanned the project's scenes and resources", scanned[0] > 60, str(scanned[0]))
	check("no scene or resource outside the packs hard-links their art", offenders.is_empty(),
		", ".join(offenders.slice(0, 5)))


func _scan_for_hard_links(dir: String, offenders: Array[String], scanned: Array) -> void:
	if dir in THIRD_PARTY_PACKS or dir == "res://scenes/skins/" or dir.begins_with("res://."):
		return
	for sub in DirAccess.get_directories_at(dir):
		_scan_for_hard_links(dir + sub + "/", offenders, scanned)
	for file in DirAccess.get_files_at(dir):
		if not (file.ends_with(".tscn") or file.ends_with(".tres")):
			continue
		# Previews from the pixel-map tool (`tools/map_paint.py preview`): generated locally, not in the repo (.gitignore)
		if dir + file == "res://scenes/map_preview.tscn":
			continue
		scanned[0] += 1
		for line in FileAccess.get_file_as_string(dir + file).split("\n"):
			if not line.begins_with("[ext_resource"):
				continue
			for pack: String in THIRD_PARTY_PACKS:
				if pack in line:
					offenders.append(dir + file)
