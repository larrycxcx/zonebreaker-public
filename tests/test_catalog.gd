extends GameTest
## The three content lists (stages, characters, shop stock): **found by scanning directories, not named in code**.
##
## This matters for DLC later — a Godot DLC is a `.pck` whose files are overlaid onto `res://` when loaded,
## so the main program has to look for content in directories; with hard-coded lists it would never know what a DLC added.
##
## This suite guards "it really scans, and scans correctly", plus three pitfalls we nearly fell into:
## the ultimate slipping into the shop stock, sorting by file name scrambling the character order, and crashing when a directory does not exist.


# ---------------------------------------------------------------- Stages

func test_the_level_list_comes_from_the_folder() -> void:
	var levels := Catalog.levels()
	check("there is at least one level", levels.size() >= 1, str(levels.size()))
	for level in levels:
		check("%s points at a scene that exists" % level.resource_path.get_file(),
			ResourceLoader.exists(level.scene_path), level.scene_path)
		check("%s has a name for the menu" % level.resource_path.get_file(),
			not level.display_name.is_empty())


func test_the_menu_starts_the_first_level_from_the_list() -> void:
	var first := Catalog.first_level()
	check("there is a first level", first != null)
	check("and the menu starts that one", MainMenu.level_scene() == first.scene_path,
		"%s vs %s" % [MainMenu.level_scene(), "" if first == null else first.scene_path])
	# The test level is not in the list: it is for tests and must not show up in the real flow
	for level in Catalog.levels():
		check("the test level is not in the list", level.scene_path != "res://scenes/main.tscn",
			level.scene_path)


# ---------------------------------------------------------------- Characters

func test_the_character_list_comes_from_the_folder() -> void:
	var looks := Catalog.looks()
	check("all three characters are there", looks.size() >= 3, str(looks.size()))
	var keys: Array[StringName] = []
	for look in looks:
		keys.append(look.key)
	for wanted in [&"biker", &"punk", &"cyborg"]:
		check("%s is on the list" % wanted, keys.has(wanted), str(keys))


func test_the_character_order_is_not_alphabetical() -> void:
	# **This pitfall would really be visible**: sorted by file name it is biker / cyborg / punk,
	# and the last two portraits in character setup would swap places. So sorting goes by the resource's `order`.
	var keys: Array[StringName] = SetupColumn.looks()
	check("the order on screen is the one we set", keys.slice(0, 3) == [&"biker", &"punk", &"cyborg"],
		str(keys))
	var sorted_names := keys.slice(0, 3).map(func(k: StringName) -> String: return String(k))
	sorted_names.sort()
	check("which really is not just the filenames sorted",
		sorted_names != keys.slice(0, 3).map(func(k: StringName) -> String: return String(k)),
		str(sorted_names))


func test_new_characters_start_with_different_looks() -> void:
	# The two seats get the first two entries of the list by default, so two players never look the same
	Progress.persist = false
	Progress.new_game()
	var one := Progress.fresh(0)
	var two := Progress.fresh(1)
	check("the two seats look different", one.look != two.look,
		"%s / %s" % [one.look, two.look])
	var keys: Array[StringName] = SetupColumn.looks()
	check("and both come off the list", keys.has(one.look) and keys.has(two.look), str(keys))


# ---------------------------------------------------------------- Shop stock

func test_only_priced_things_are_for_sale() -> void:
	# **The ultimate lies right there in weapons/**, with no gear slot and no price — a naive scan
	# would have the shop give away a MEGA BOMB to use as a gun. The stock only takes priced items.
	for item in Catalog.gear_for_sale():
		check("%s has a price" % item.display_name, item.price > 0, str(item.price))
	var names := Catalog.gear_for_sale().map(func(e: Equipment) -> String: return e.display_name)
	check("the mega bomb is not in the shop", not names.has("MEGA BOMB"), str(names))
	check("and neither is the starting rifle", not names.has("RIFLE"), str(names))


func test_the_shop_list_is_sorted_by_price() -> void:
	var shelf := Catalog.gear_for_sale()
	var last := -1
	for item in shelf:
		check("%s costs at least as much as the one before" % item.display_name, item.price >= last,
			"%d after %d" % [item.price, last])
		last = item.price


# ---------------------------------------------------------------- Stage strength

func test_a_level_scales_the_enemies_it_holds() -> void:
	# The 23 stages use the same enemies, with one set of multipliers per stage setting the difficulty (`Stage`).
	await reset_scene(true)
	var plain: Enemy = main.get_node("Enemies/WalkerA")
	var base_health := plain.max_health
	var base_contact := plain.contact_damage
	check("setup: no level set means no scaling", is_equal_approx(Stage.health_scale(), 1.0))
	var tough := LevelInfo.new()
	tough.enemy_health_scale = 3.0
	tough.enemy_damage_scale = 2.0
	# **The strength has to be set before loading**: enemies scale by it in `_ready`, so it goes through `reset_scene`'s parameter
	await reset_scene(true, false, null, 1, "res://scenes/main.tscn", tough)
	var scaled: Enemy = main.get_node("Enemies/WalkerA")
	check("its health went up with the level", scaled.max_health == base_health * 3,
		"%d vs %d" % [scaled.max_health, base_health])
	check("it starts at that health", scaled.health == scaled.max_health)
	check("and it hits harder too", scaled.contact_damage == base_contact * 2,
		"%d vs %d" % [scaled.contact_damage, base_contact])


func test_a_level_scales_what_the_enemies_are_worth() -> void:
	var rich := LevelInfo.new()
	rich.reward_scale = 4.0
	await reset_scene(true, false, null, 1, "res://scenes/main.tscn", rich)
	var me := player.progress
	var money := me.money
	var enemy: Enemy = main.get_node("Enemies/WalkerA")
	var worth := enemy.money_reward
	enemy.die()
	await frames(2)
	check("the pay packet is scaled too", me.money - money == worth * 4,
		"%d for a %d enemy" % [me.money - money, worth])


func test_the_shop_only_stocks_what_your_level_allows() -> void:
	# Without level requirements, enough money would buy gear far too strong and the curve over 23 stages would collapse
	for item in Catalog.gear_for_sale(5):
		check("%s is within reach at level 5" % item.display_name, item.min_level <= 5,
			str(item.min_level))
	check("asking for everything gives at least as much",
		Catalog.gear_for_sale().size() >= Catalog.gear_for_sale(5).size())


func test_a_level_brings_its_own_art() -> void:
	if needs_art(): return
	# **Each of the 23 stages has its own scenes, enemies, boss and music**, so "which art set" is a property of **the stage**,
	# not one global pack in the project settings — sharing one pack would mean 23 stages sharing one backdrop, one track and one set of tiles.
	var zone := load("res://skins/cyberpunk/cyberpunk_skin.tres") as SkinPack
	var level := LevelInfo.new()
	level.skin = zone
	Skins.use(Skins.default_skin())
	check("setup: on the default pack", Skins.current != zone)
	Stage.use(level)
	check("loading a level switches to its pack", Skins.current == zone, str(Skins.current))
	# A stage without a pack leaves the current one alone (the test level works like this, so none of the old cases changed)
	var plain := LevelInfo.new()
	Stage.use(plain)
	check("a level without its own pack leaves it alone", Skins.current == zone)
	Stage.clear()


func test_the_first_level_names_the_pack_it_wants() -> void:
	if needs_art(): return
	var first := Catalog.first_level()
	check("there is a first level", first != null)
	check("and it brings its own art", first != null and first.skin != null,
		"" if first == null else str(first.skin))


func test_the_difficulty_dials_start_neutral() -> void:
	# The multipliers of the real stages are all 1: every stage has its own enemies anyway, with health and damage in each enemy scene.
	# These three numbers are kept for **difficulty DLC** — same stage, same enemies, just higher multipliers.
	for level in Catalog.levels():
		var name := level.resource_path.get_file()
		check("%s does not scale health" % name, is_equal_approx(level.enemy_health_scale, 1.0),
			str(level.enemy_health_scale))
		check("%s does not scale damage" % name, is_equal_approx(level.enemy_damage_scale, 1.0),
			str(level.enemy_damage_scale))


# ---------------------------------------------------------------- How numbers are written

func test_big_numbers_are_written_with_k() -> void:
	# XP and money reach five or six digits later on, and written out they would burst the line
	check("under a thousand stays as it is", UiKit.number(858) == "858", UiKit.number(858))
	check("a round thousand loses the decimal", UiKit.number(1000) == "1K", UiKit.number(1000))
	check("1200 reads as 1.2K", UiKit.number(1200) == "1.2K", UiKit.number(1200))
	check("and 1250 rounds up to 1.3K", UiKit.number(1250) == "1.3K", UiKit.number(1250))
	check("past ten thousand it rounds off", UiKit.number(12500) == "13K", UiKit.number(12500))
	check("and six figures too", UiKit.number(153993) == "154K", UiKit.number(153993))
	check("zero is still zero", UiKit.number(0) == "0", UiKit.number(0))


func test_the_hud_writes_money_the_short_way() -> void:
	await reset_scene()
	await frames(2)
	player.progress.add_money(12500)
	await frames(1)
	var label: Label = main.get_node("HUD/ProgressLabel")
	check("the HUD uses the short form", label.text.contains("13K"), label.text)
	check("and not the long one", not label.text.contains("12500"), label.text)


func test_at_max_level_the_bar_says_so() -> void:
	# At max level XP no longer accumulates; `XP 0/0` would look like a bug
	await reset_scene()
	await frames(2)
	player.progress.level = player.progress.balance.max_level
	player.progress.progress_changed.emit()
	await frames(1)
	var label: Label = main.get_node("HUD/ProgressLabel")
	check("it says MAX instead of 0/0", label.text.contains("XP MAX"), label.text)


# ---------------------------------------------------------------- A missing directory must not crash

func test_a_missing_folder_is_just_an_empty_shelf() -> void:
	# A DLC not installed, or a directory not created yet: missing a few things is right, crashing is not
	var missing: Array[Resource] = Catalog._scan("res://there_is_no_such_folder")
	check("scanning nothing gives nothing", missing.is_empty(), str(missing.size()))


func test_the_scan_ignores_things_that_are_not_resources() -> void:
	# The directory mixes in things like `.import` and `.uid`; only `.tres` / `.res` count
	var looks := Catalog._scan(Catalog.CHARACTERS)
	check("everything it found is a character", looks.size() == Catalog.looks().size(),
		"%d vs %d" % [looks.size(), Catalog.looks().size()])
	for item in looks:
		check("%s really is a CharacterLook" % item.resource_path.get_file(),
			item is CharacterLook, str(item))
