extends GameTest
## 商店：标签页、买、卖、穿、等级门槛，以及双人各按各的。
##
## **不进关卡**：商店是关卡之外的界面，这里直接把 `ShopScreen` 挂到 root 上、
## 配一个只带 `player_index` 和 `progress` 的替身玩家（和人物设置界面那边一个做法）。
## 走完记得 `free()` 掉——手动挂上去的节点 `free_scene()` 收不走，留着会在后面的组里继续收键
## （CLAUDE.md 「踩过的坑」里那条跨组污染就是这么来的）。

var shop: ShopScreen
var stand_ins: Array[Player] = []


func open_shop(seats := 1) -> void:
	close_shop()
	release_all_input()
	tree.paused = false
	Progress.persist = false
	Progress.new_game()
	Session.set_player_count(seats)
	shop = ShopScreen.new()
	main = shop
	tree.root.add_child(shop)
	var players: Array = []
	for i in seats:
		var stand_in := Player.new()
		stand_in.player_index = i
		stand_in.progress = Progress.of(i)
		stand_ins.append(stand_in)
		players.append(stand_in)
	shop.build(players)
	await frames(2)


func close_shop() -> void:
	if is_instance_valid(shop):
		shop.free()
	shop = null
	main = null
	for stand_in in stand_ins:
		if is_instance_valid(stand_in):
			stand_in.free()
	stand_ins.clear()


func column(index := 0) -> ShopColumn:
	return shop.columns()[index]


func press(action: StringName) -> void:
	await tap(action)


## 走到货架上第 index 件（按下走，走不到就算了，别把用例卡死）。
func go_to(at: int, index := 0) -> void:
	for i in 20:
		if column(index).menu_list().index == at:
			return
		await press(&"aim_down")


## 翻到叫这个名字的那一页。
func open_tab(name: String, index := 0) -> void:
	for i in ShopColumn.TABS.size():
		if ShopColumn.TABS[column(index).tab]["name"] == name:
			return
		await press(&"switch_weapon" if index == 0 else &"p2_switch_weapon")


## 货架上叫这个名字的是第几件（没有就是 -1）。
func find_item(name: String, index := 0) -> int:
	var shelf := column(index).shelf()
	for i in shelf.size():
		if shelf[i].display_name == name:
			return i
	return -1


# ---------------------------------------------------------------- 标签页

func test_it_opens_on_your_bag() -> void:
	await open_shop()
	check("the first tab is the inventory", column().in_bag() and column().tab == 0)
	check("and it lists what you own", column().shelf().size() == Progress.of(0).owned.size(),
		"%d / %d" % [column().shelf().size(), Progress.of(0).owned.size()])
	await close_shop()


func test_the_shoulder_buttons_walk_the_tabs() -> void:
	await open_shop()
	await press(&"switch_weapon")             # RB
	check("RB moves on one tab", column().tab == 1, str(column().tab))
	await press(&"sprint")                    # LB
	check("LB moves back", column().tab == 0, str(column().tab))
	await press(&"sprint")
	check("and it wraps round to the last one", column().tab == ShopColumn.TABS.size() - 1,
		str(column().tab))
	await close_shop()


func test_each_tab_only_stocks_its_own_slot() -> void:
	await open_shop()
	await open_tab("HEAD")
	var slots := {}
	for item in column().shelf():
		slots[item.slot] = true
	check("the head tab is all helmets", slots.keys() == [Equipment.Slot.HEAD], str(slots.keys()))
	check("and it is not empty", column().shelf().size() > 0)
	await close_shop()


# ---------------------------------------------------------------- 买

func test_buying_asks_first() -> void:
	await open_shop()
	var progress := Progress.of(0)
	progress.money = 100000
	await open_tab("HEAD")
	await frames(1)
	var item := column().shelf()[0]
	await go_to(0)
	await press(&"jump")
	check("it asks before taking your money", column().ask_menu() != null)
	check("and has not bought anything yet", not progress.owned.has(item))
	await press(&"cancel")
	check("backing out closes the question", column().ask_menu() == null)
	check("and still nothing is bought", not progress.owned.has(item))
	await press(&"jump")
	await press(&"jump")                      # YES
	check("saying yes buys it", progress.owned.has(item), str(item.display_name))
	check("and takes the money", progress.money == 100000 - item.price, str(progress.money))
	await close_shop()


func test_you_cannot_buy_what_you_cannot_afford() -> void:
	await open_shop()
	var progress := Progress.of(0)
	progress.money = 0
	await open_tab("HEAD")
	await go_to(0)
	await press(&"jump")
	check("with no cash it does not even ask", column().ask_menu() == null)
	check("and nothing is bought", progress.owned.is_empty() or not progress.owned.has(column().shelf()[0]))
	await close_shop()


func test_a_bought_item_shows_as_owned_and_cannot_be_bought_twice() -> void:
	await open_shop()
	var progress := Progress.of(0)
	progress.money = 100000
	await open_tab("HEAD")
	var item := column().shelf()[0]
	await go_to(0)
	await press(&"jump")
	await press(&"jump")
	var left := progress.money
	check("it is in the bag", progress.owned.has(item))
	check("and still on the shelf marked owned", column().shelf().has(item))
	await go_to(column().shelf().find(item))
	await press(&"jump")
	check("buying it again does not even ask", column().ask_menu() == null)
	check("and the money is untouched", progress.money == left, str(progress.money))
	await close_shop()


# ---------------------------------------------------------------- 等级门槛

func test_high_level_gear_is_on_the_shelf_but_cannot_be_worn() -> void:
	await open_shop()
	var progress := Progress.of(0)
	progress.money = 100000
	progress.level = 1
	await open_tab("HEAD")
	var shelf := column().shelf()
	var locked: Equipment = null
	for item in shelf:
		if item.min_level > 1:
			locked = item
			break
	check("there is something above your level on show", locked != null)
	if locked == null:
		await close_shop()
		return
	await go_to(shelf.find(locked))
	await press(&"jump")
	await press(&"jump")
	check("you can still buy it", progress.owned.has(locked))
	await open_tab("BAG")
	await go_to(column().shelf().find(locked))
	await press(&"jump")
	check("but it will not go on", progress.gear(locked.slot) != locked)
	progress.level = locked.min_level
	await press(&"jump")
	check("and once you are high enough it does", progress.gear(locked.slot) == locked)
	await close_shop()


# ---------------------------------------------------------------- 穿和卖

func test_equipping_from_the_bag_needs_no_confirmation() -> void:
	await open_shop()
	var progress := Progress.of(0)
	progress.money = 100000
	progress.level = 30
	await open_tab("BODY")
	var vest := column().shelf()[0]
	await go_to(0)
	await press(&"jump")
	await press(&"jump")
	var life_before := progress.stat(&"life")
	await open_tab("BAG")
	await go_to(column().shelf().find(vest))
	await press(&"jump")
	check("no question is asked", column().ask_menu() == null)
	check("it goes straight on", progress.gear(vest.slot) == vest)
	check("and the stat moves", progress.stat(&"life") > life_before,
		"%d -> %d" % [life_before, progress.stat(&"life")])
	await close_shop()


func test_selling_pays_half_and_takes_it_off_you() -> void:
	await open_shop()
	var progress := Progress.of(0)
	progress.money = 100000
	progress.level = 30
	await open_tab("BODY")
	var vest := column().shelf()[0]
	await go_to(0)
	await press(&"jump")
	await press(&"jump")
	await open_tab("BAG")
	await go_to(column().shelf().find(vest))
	await press(&"jump")                      # 穿上
	check("wearing it first", progress.gear(vest.slot) == vest)
	var purse := progress.money
	await press(&"menu_delete")               # X
	check("selling asks first too", column().ask_menu() != null)
	await press(&"jump")                      # YES
	check("it is gone from the bag", not progress.owned.has(vest))
	check("and off your body", progress.gear(vest.slot) != vest)
	check("half price back", progress.money == purse + vest.price / 2,
		"%d -> %d" % [purse, progress.money])
	await close_shop()


## 白给的东西（初始的步枪和手雷没标价）卖不掉——卖价是 0，让它卖得掉等于送玩家一个坑：
## 一按 X 就把自己唯一一把枪换成零块钱。
func test_the_free_starting_gear_cannot_be_sold() -> void:
	await open_shop()
	var progress := Progress.of(0)
	var rifle := progress.gear(Equipment.Slot.GUN)
	check("setup: it came free", rifle != null and rifle.price == 0, str(rifle))
	await go_to(column().shelf().find(rifle))
	await press(&"menu_delete")
	check("X does not even ask", column().ask_menu() == null)
	check("and it is still yours", progress.owned.has(rifle))
	check("the sell column says nothing, not zero",
		not _texts(column()).has("0"), str(_texts(column())))
	await close_shop()


## 确认框里的 YES / NO 得落在它自己的窗口里（随手写个高度的话 NO 会掉到框外面）。
func test_the_question_fits_in_its_box() -> void:
	await open_shop()
	Progress.of(0).money = 100000
	await open_tab("HEAD")
	await go_to(0)
	await press(&"jump")
	var ask := column().ask_menu()
	check("setup: it is asking", ask != null)
	if ask == null:
		await close_shop()
		return
	var box: Control = column()._ask
	var bottom := ask.position.y + ask.size.y
	check("the last choice is inside the frame", bottom <= box.position.y + box.size.y,
		"%.0f vs %.0f" % [bottom, box.position.y + box.size.y])
	check("and the whole box is inside the column",
		box.position.y >= 0.0 and box.position.y + box.size.y <= ShopColumn.HEIGHT,
		"%.0f..%.0f" % [box.position.y, box.position.y + box.size.y])
	await close_shop()


func test_x_does_nothing_on_the_shop_shelves() -> void:
	await open_shop()
	var progress := Progress.of(0)
	progress.money = 100000
	await open_tab("HEAD")
	await go_to(0)
	await press(&"menu_delete")
	check("you cannot sell the shop's own stock", column().ask_menu() == null)
	check("and the money is untouched", progress.money == 100000, str(progress.money))
	await close_shop()


## 详情框里那行「现在 → 之后」：挑这件装备会让哪个属性变成多少。
func test_the_card_compares_now_with_after() -> void:
	await open_shop()
	var progress := Progress.of(0)
	progress.money = 100000
	progress.level = 30
	await open_tab("BODY")
	var vest := column().shelf()[0]
	await go_to(0)
	await frames(1)
	var life: float = vest.bonuses.get(&"life", 0.0)
	check("setup: the vest really adds life", life > 0.0, str(life))
	var words := _texts(column())
	check("it shows what you have now", words.has(str(roundi(progress.stat(&"life")))), str(words))
	check("and what you would have", words.has(str(roundi(progress.stat(&"life") + life))), str(words))
	check("and the difference", words.has("+%d" % roundi(life)), str(words))
	await close_shop()


func _texts(node: Node) -> Array[String]:
	var found: Array[String] = []
	for child in node.get_children():
		if child is Label:
			found.append((child as Label).text)
		found.append_array(_texts(child))
	return found


# ---------------------------------------------------------------- 逛完了

func test_one_player_leaves_straight_away() -> void:
	await open_shop()
	var left := [false]
	shop.finished.connect(func() -> void: left[0] = true)
	await press(&"cancel")
	check("backing out is the way out", left[0])
	await close_shop()


func test_two_players_wait_for_each_other() -> void:
	await open_shop(2)
	var left := [false]
	shop.finished.connect(func() -> void: left[0] = true)
	await press(&"cancel")
	check("one leaving is not enough", not left[0])
	check("that column says it is done", column(0).done)
	check("the other one carries on", not column(1).done)
	Progress.of(0).money = 100000
	await open_tab("HEAD", 0)
	await press(&"cancel")
	await press(&"jump")
	check("and BACK TO SHOP brings it back", not column(0).done)
	# 回来那一下 A **不该**顺手在货架上买一件（盖在上面的那层就是用它关掉的）
	check("without buying anything on the way", Progress.of(0).owned.size() == 2,
		str(Progress.of(0).owned.size()))
	await press(&"cancel")
	await tap(&"p2_cancel")
	check("both done leaves", left[0])
	await close_shop()


func test_each_column_only_hears_its_own_player() -> void:
	await open_shop(2)
	await press(&"switch_weapon")
	check("player one turned the page", column(0).tab == 1, str(column(0).tab))
	check("player two stayed put", column(1).tab == 0, str(column(1).tab))
	await tap(&"p2_switch_weapon")
	check("and player two turns their own", column(1).tab == 1, str(column(1).tab))
	check("without moving player one again", column(0).tab == 1, str(column(0).tab))
	await close_shop()


func test_the_two_purses_are_separate() -> void:
	await open_shop(2)
	Progress.of(0).money = 100000
	Progress.of(1).money = 100000
	await open_tab("HEAD", 0)
	var item := column(0).shelf()[0]
	await go_to(0, 0)
	await press(&"jump")
	await press(&"jump")
	check("player one bought it", Progress.of(0).owned.has(item))
	check("player two did not", not Progress.of(1).owned.has(item))
	check("and player two's cash is untouched", Progress.of(1).money == 100000,
		str(Progress.of(1).money))
	await close_shop()


# ---------------------------------------------------------------- 排版

func test_the_rows_stay_inside_the_window() -> void:
	await open_shop()
	Progress.of(0).money = 100000
	var font := UiKit.font()
	var worst := 0.0
	var culprit := ""
	for tab in ShopColumn.TABS.size():
		column().show_tab(tab)
		await frames(1)
		for label in _labels(column()):
			# **量的是相对这一栏的位置**：字被塞在好几层容器里（窗口、货架、详情框），
			# 光看 `position` 量的是相对它爹的，全是小数字，什么也守不住
			var left: float = label.global_position.x - column().global_position.x
			var right := left + label.size.x
			if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT:
				right = left + font.get_string_size(label.text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.TEXT_SIZE).x
			if right > worst:
				worst = right
				culprit = label.text
	# 窗口 300 宽、九宫格边框 32，字（连标签页那一排）都得落在边框**里面**
	check("nothing pokes out of the frame", worst <= ShopColumn.WIDTH - UiKit.PANEL_MARGIN,
		"%s 到 %.1f" % [culprit, worst])
	await close_shop()


func _labels(node: Node) -> Array[Label]:
	var found: Array[Label] = []
	for child in node.get_children():
		if child is Label and not String((child as Label).text).is_empty():
			found.append(child)
		found.append_array(_labels(child))
	return found


# ---------------------------------------------------------------- 武器属性

func test_a_weapon_reads_out_what_it_actually_does() -> void:
	# 武器的强弱全在 `power` 和 `cooldown` 里，界面上不写的话，
	# 商店里两把枪看着只差一个名字和一个价钱（试玩反馈）。
	var me := Progress.of(0)
	var rifle := load("res://weapons/rifle.tres") as Weapon
	var numbers := me.weapon_numbers(rifle)
	check("it says what one shot does", numbers.has(&"damage"), str(numbers))
	check("and how fast it goes off", numbers.has(&"rate"), str(numbers))
	# 照着武器槽真正发射时那一套算：发射物的伤害 × power × 攻击倍率
	var shot := rifle.projectile.instantiate()
	var base := float(shot.get(&"damage"))
	shot.free()
	var want := maxf(1.0, roundf(base * rifle.power * Balance.damage_scale(me.stat(Balance.ATTACK))))
	check("the damage matches what the gun will really deal", numbers[&"damage"] == want,
		"%s vs %s" % [numbers[&"damage"], want])
	check("the rate matches its cooldown",
		is_equal_approx(numbers[&"rate"], 1.0 / (rifle.cooldown
			* Balance.cooldown_scale(me.stat(Balance.SPEED)))), str(numbers[&"rate"]))


func test_the_numbers_follow_the_character_not_the_gun() -> void:
	# 同一把枪在不同角色手里是不一样的：攻击力算进伤害、速度算进射速
	var me := Progress.of(0)
	var rifle := load("res://weapons/rifle.tres") as Weapon
	var weak := me.weapon_numbers(rifle)
	me.allocated[Balance.ATTACK] = 10
	me.allocated[Balance.SPEED] = 10
	var strong := me.weapon_numbers(rifle)
	check("more attack means more damage per shot", strong[&"damage"] > weak[&"damage"],
		"%s -> %s" % [weak[&"damage"], strong[&"damage"]])
	check("more speed means more shots per second", strong[&"rate"] > weak[&"rate"],
		"%.2f -> %.2f" % [weak[&"rate"], strong[&"rate"]])
	me.allocated.clear()


func test_a_grenade_reads_out_its_centre_hit() -> void:
	# 手雷的伤害是中心 max、边缘 min 两个数。写的是**一次打满能打多少**，和子弹那一列对得上
	var me := Progress.of(0)
	var grenade := load("res://weapons/grenade.tres") as Weapon
	var numbers := me.weapon_numbers(grenade)
	var shot := grenade.projectile.instantiate()
	var centre := float(shot.get(&"max_damage"))
	shot.free()
	check("it reads the centre of the blast", numbers.has(&"damage")
		and numbers[&"damage"] == maxf(1.0, roundf(centre * grenade.power
			* Balance.damage_scale(me.stat(Balance.ATTACK)))), str(numbers))


func test_reading_a_weapon_does_not_leave_anything_behind() -> void:
	# 读伤害是**现造一个发射物出来读完就扔**。`instantiate()` 不跑 `_ready`，
	# 所以它不会挂进 `grenades` 分组、不会去问皮肤包要外观——漏一个在树外面就是个泄漏。
	var me := Progress.of(0)
	var before := tree.get_nodes_in_group(Grenade.GROUP).size()
	for i in 20:
		me.weapon_numbers(load("res://weapons/grenade.tres") as Weapon)
	check("no stray grenades in the group",
		tree.get_nodes_in_group(Grenade.GROUP).size() == before,
		"%d -> %d" % [before, tree.get_nodes_in_group(Grenade.GROUP).size()])


func test_unlimited_ammo_is_left_off_the_list() -> void:
	# `max_ammo` 是 -1，照抄出来界面上就是一行「AMMO -1」（截图才看出来的）。
	# 步枪和手雷都是无限的，这一行只该给终极武器那种有限弹药的留着。
	var me := Progress.of(0)
	for path: String in ["res://weapons/rifle.tres", "res://weapons/grenade.tres"]:
		var weapon := load(path) as Weapon
		check("setup: %s really is unlimited" % weapon.display_name, weapon.max_ammo < 0)
		check("so %s says nothing about ammo" % weapon.display_name,
			not me.weapon_numbers(weapon).has(&"ammo"), str(me.weapon_numbers(weapon)))
	var ultimate := load("res://weapons/ultimate.tres") as Weapon
	check("setup: the ultimate really is limited", ultimate.max_ammo >= 0, str(ultimate.max_ammo))
	check("and it does say how many it holds",
		me.weapon_numbers(ultimate).get(&"ammo", -1.0) == float(ultimate.max_ammo),
		str(me.weapon_numbers(ultimate)))


# ---------------------------------------------------------------- 防具的数字

## 走到货架上第一件**不是武器**的东西（防具那几页）。
func open_armour_tab() -> Equipment:
	for tab in range(2, ShopColumn.TABS.size()):
		column().show_tab(tab)
		await frames(2)
		if column().picked() != null:
			return column().picked()
	return null


func test_armour_says_what_it_gives() -> void:
	await open_shop()
	var item := await open_armour_tab()
	check("setup: there is armour on the shelves", item != null)
	if item == null:
		return
	check("setup: it really has bonuses", not item.bonuses.is_empty(), str(item.bonuses))
	var labels := _card_labels()
	for stat: StringName in item.bonuses:
		check("the card says what %s does to %s" % [item.display_name, stat],
			labels.has(String(stat).substr(0, 3).to_upper()), str(labels))
	close_shop()


func test_a_maxed_out_character_still_sees_what_the_armour_gives() -> void:
	# 属性有上限。满级玩家换一顶头盔四行全都「没变」，
	# 「没变就不画」的话详情框整个空着，看着像这件装备什么用都没有（2026-09 试玩反馈）。
	await open_shop()
	var me := Progress.of(0)
	for stat: StringName in Balance.STATS:
		me.allocated[stat] = 999       # 顶到上限
	var item := await open_armour_tab()
	check("setup: there is armour on the shelves", item != null)
	if item == null:
		return
	var capped := true
	var after: Dictionary = me.stat_preview(item, true)
	for stat: StringName in item.bonuses:
		capped = capped and is_equal_approx(me.stat(stat), after.get(stat, 0.0))
	check("setup: this character really is capped on everything it gives", capped,
		"%s / %s" % [item.bonuses, after])
	var labels := _card_labels()
	for stat: StringName in item.bonuses:
		check("the card still lists %s" % stat,
			labels.has(String(stat).substr(0, 3).to_upper()), str(labels))
	check("and marks it as maxed out", labels.has("MAX"), str(labels))
	me.allocated.clear()
	close_shop()


## 详情框里现在写着哪些字（一行一个 Label）。
func _card_labels() -> Array[String]:
	var out: Array[String] = []
	for node in column()._card.find_children("*", "Label", true, false):
		out.append((node as Label).text)
	return out
