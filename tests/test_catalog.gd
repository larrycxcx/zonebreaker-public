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
