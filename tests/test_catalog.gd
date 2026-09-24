extends GameTest
## 三张内容清单（关卡、角色、商店货单）：**扫目录来的，不是代码里点名的**。
##
## 这关系到以后能不能做 DLC——Godot 的 DLC 是个 `.pck`，加载时把文件叠加进 `res://`，
## 所以主程序必须去目录里找内容，写死清单的话主程序根本不知道 DLC 加了什么。
##
## 这一组守的就是「真的在扫、而且扫对了」，外加三个当初差点踩进去的坑：
## 终极武器混进货单、按文件名排序把角色顺序打乱、目录不存在就崩。


# ---------------------------------------------------------------- 关卡

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
	# 测试关不在清单里：它是给测试用的，不该出现在正式流程里
	for level in Catalog.levels():
		check("the test level is not in the list", level.scene_path != "res://scenes/main.tscn",
			level.scene_path)


# ---------------------------------------------------------------- 角色

func test_the_character_list_comes_from_the_folder() -> void:
	var looks := Catalog.looks()
	check("all three characters are there", looks.size() >= 3, str(looks.size()))
	var keys: Array[StringName] = []
	for look in looks:
		keys.append(look.key)
	for wanted in [&"biker", &"punk", &"cyborg"]:
		check("%s is on the list" % wanted, keys.has(wanted), str(keys))


func test_the_character_order_is_not_alphabetical() -> void:
	# **这是个真会被看见的坑**：按文件名排是 biker / cyborg / punk，
	# 人物设置界面上后两个头像就对调了。所以排序看资源里的 `order`。
	var keys: Array[StringName] = SetupColumn.looks()
	check("the order on screen is the one we set", keys.slice(0, 3) == [&"biker", &"punk", &"cyborg"],
		str(keys))
	var sorted_names := keys.slice(0, 3).map(func(k: StringName) -> String: return String(k))
	sorted_names.sort()
	check("which really is not just the filenames sorted",
		sorted_names != keys.slice(0, 3).map(func(k: StringName) -> String: return String(k)),
		str(sorted_names))


func test_new_characters_start_with_different_looks() -> void:
	# 两个座位默认拿清单里的头两个，所以双人不会撞脸
	Progress.persist = false
	Progress.new_game()
	var one := Progress.fresh(0)
	var two := Progress.fresh(1)
	check("the two seats look different", one.look != two.look,
		"%s / %s" % [one.look, two.look])
	var keys: Array[StringName] = SetupColumn.looks()
	check("and both come off the list", keys.has(one.look) and keys.has(two.look), str(keys))


# ---------------------------------------------------------------- 商店货单

func test_only_priced_things_are_for_sale() -> void:
	# **终极武器就躺在 weapons/ 里**，而且没配装备位、没标价——天真地扫一遍，
	# 商店里会白送一把 MEGA BOMB 当枪使。货单只收标了价的。
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


# ---------------------------------------------------------------- 关卡强度

func test_a_level_scales_the_enemies_it_holds() -> void:
	# 23 关用同一批敌人，靠每关一组倍率拉开强度（`Stage`）。
	await reset_scene(true)
	var plain: Enemy = main.get_node("Enemies/WalkerA")
	var base_health := plain.max_health
	var base_contact := plain.contact_damage
	check("setup: no level set means no scaling", is_equal_approx(Stage.health_scale(), 1.0))
	var tough := LevelInfo.new()
	tough.enemy_health_scale = 3.0
	tough.enemy_damage_scale = 2.0
	# **强度要在加载之前定**：敌人在 `_ready` 里就按它缩放，所以走 `reset_scene` 的参数
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
	# 没有等级门槛的话，钱一多就能买到过强的东西，23 关的曲线就塌了
	for item in Catalog.gear_for_sale(5):
		check("%s is within reach at level 5" % item.display_name, item.min_level <= 5,
			str(item.min_level))
	check("asking for everything gives at least as much",
		Catalog.gear_for_sale().size() >= Catalog.gear_for_sale(5).size())


func test_a_level_brings_its_own_art() -> void:
	# **23 关各有各的场景、敌人、Boss、音乐**，所以「用哪套素材」是**关卡**的属性，
	# 不是项目设置里那一个全局包——共用一个包的话 23 关只能共用一张背景、一首曲子、一套地砖。
	var zone := load("res://skins/cyberpunk/cyberpunk_skin.tres") as SkinPack
	var level := LevelInfo.new()
	level.skin = zone
	Skins.use(Skins.default_skin())
	check("setup: on the default pack", Skins.current != zone)
	Stage.use(level)
	check("loading a level switches to its pack", Skins.current == zone, str(Skins.current))
	# 没配包的关卡不动当前那套（测试关就是这一档，所以老用例一条都没改）
	var plain := LevelInfo.new()
	Stage.use(plain)
	check("a level without its own pack leaves it alone", Skins.current == zone)
	Stage.clear()


func test_the_first_level_names_the_pack_it_wants() -> void:
	var first := Catalog.first_level()
	check("there is a first level", first != null)
	check("and it brings its own art", first != null and first.skin != null,
		"" if first == null else str(first.skin))


func test_the_difficulty_dials_start_neutral() -> void:
	# 正式关卡的倍率都是 1：每关敌人本来就不一样，血量伤害写在各自的敌人场景里。
	# 这三个数是留给**难度 DLC** 的——同一关同一批敌人，只把倍率调高。
	for level in Catalog.levels():
		var name := level.resource_path.get_file()
		check("%s does not scale health" % name, is_equal_approx(level.enemy_health_scale, 1.0),
			str(level.enemy_health_scale))
		check("%s does not scale damage" % name, is_equal_approx(level.enemy_damage_scale, 1.0),
			str(level.enemy_damage_scale))


# ---------------------------------------------------------------- 数字怎么写

func test_big_numbers_are_written_with_k() -> void:
	# 经验和金钱到后面都是五六位数，原样写会把一行字撑爆
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
	# 满级之后经验不再累计，`XP 0/0` 会让人以为是 bug
	await reset_scene()
	await frames(2)
	player.progress.level = player.progress.balance.max_level
	player.progress.progress_changed.emit()
	await frames(1)
	var label: Label = main.get_node("HUD/ProgressLabel")
	check("it says MAX instead of 0/0", label.text.contains("XP MAX"), label.text)


# ---------------------------------------------------------------- 目录不在也不能崩

func test_a_missing_folder_is_just_an_empty_shelf() -> void:
	# DLC 没装、或者哪个目录还没建：少几样东西是对的，崩掉不是
	var missing: Array[Resource] = Catalog._scan("res://there_is_no_such_folder")
	check("scanning nothing gives nothing", missing.is_empty(), str(missing.size()))


func test_the_scan_ignores_things_that_are_not_resources() -> void:
	# 目录里混着 `.import`、`.uid` 之类的东西，只认 `.tres` / `.res`
	var looks := Catalog._scan(Catalog.CHARACTERS)
	check("everything it found is a character", looks.size() == Catalog.looks().size(),
		"%d vs %d" % [looks.size(), Catalog.looks().size()])
	for item in looks:
		check("%s really is a CharacterLook" % item.resource_path.get_file(),
			item is CharacterLook, str(item))
