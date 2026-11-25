extends GameTest
## The shop: tabs, buying, selling, equipping, level requirements, and each player using their own controls in co-op.
##
## **Not in a stage**: the shop is a screen outside stages, so `ShopScreen` is hung straight on root here,
## with a stand-in player that only has `player_index` and `progress` (the same approach as the character setup screen).
## Remember to `free()` it at the end — `free_scene()` does not collect nodes hung on by hand, and left there they keep taking keys in later suites
## (that is where the cross-suite pollution in the CLAUDE.md pitfalls came from).

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


## Walk to item index on the shelf (pressing down; if it cannot get there, give up rather than hang the case).
func go_to(at: int, index := 0) -> void:
	for i in 20:
		if column(index).menu_list().index == at:
			return
		await press(&"aim_down")


## Turn to the tab with this name.
func open_tab(name: String, index := 0) -> void:
	for i in ShopColumn.TABS.size():
		if ShopColumn.TABS[column(index).tab]["name"] == name:
			return
		await press(&"switch_weapon" if index == 0 else &"p2_switch_weapon")


## Which item on the shelf has this name (-1 if none).
func find_item(name: String, index := 0) -> int:
	var shelf := column(index).shelf()
	for i in shelf.size():
		if shelf[i].display_name == name:
			return i
	return -1


# ---------------------------------------------------------------- Tabs

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


# ---------------------------------------------------------------- Buying

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


# ---------------------------------------------------------------- Level requirements

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


# ---------------------------------------------------------------- Equipping and selling

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
	await press(&"jump")                      # Equip it
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


## Free things (the starting rifle and grenade have no price) cannot be sold — the price would be 0, and letting them sell would set a trap for the player:
## one press of X turns their only gun into zero cash.
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


## YES / NO in the confirm box have to fall inside its own window (with an arbitrary height NO drops out of the box).
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


## The "now → after" line in the details box: what each stat becomes when picking this piece of gear.
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


# ---------------------------------------------------------------- Done browsing

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
	# The A pressed on coming back **must not** also buy something off the shelf (it is the press that closed the layer on top)
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


# ---------------------------------------------------------------- Layout

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
			# **It measures the position relative to this column**: the text is packed in several layers of containers (window, shelf, details box),
			# and `position` alone is relative to its parent — all small numbers that guard nothing
			var left: float = label.global_position.x - column().global_position.x
			var right := left + label.size.x
			if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT:
				right = left + font.get_string_size(label.text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.TEXT_SIZE).x
			if right > worst:
				worst = right
				culprit = label.text
	# The window is 300 wide with a 32 nine-slice frame; text (including the row of tabs) has to fall **inside** the frame
	check("nothing pokes out of the frame", worst <= ShopColumn.WIDTH - UiKit.PANEL_MARGIN,
		"%s reaches %.1f" % [culprit, worst])
	await close_shop()


func _labels(node: Node) -> Array[Label]:
	var found: Array[Label] = []
	for child in node.get_children():
		if child is Label and not String((child as Label).text).is_empty():
			found.append(child)
		found.append_array(_labels(child))
	return found


# ---------------------------------------------------------------- Weapon numbers

func test_a_weapon_reads_out_what_it_actually_does() -> void:
	# A weapon's strength is all in `power` and `cooldown`; if the screen did not show them,
	# two guns in the shop would differ only in name and price (playtest feedback).
	var me := Progress.of(0)
	var rifle := load("res://weapons/rifle.tres") as Weapon
	var numbers := me.weapon_numbers(rifle)
	check("it says what one shot does", numbers.has(&"damage"), str(numbers))
	check("and how fast it goes off", numbers.has(&"rate"), str(numbers))
	# Calculated the same way the weapon slot really fires: projectile damage × power × attack multiplier
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
	# The same gun differs in different characters' hands: attack goes into damage, speed into fire rate
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
	# A grenade's damage is two numbers, max at the centre and min at the edge. It shows **the most one hit can do**, matching the bullet column
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
	# Damage is read by **making a projectile, reading it and throwing it away**. `instantiate()` does not run `_ready`,
	# so it does not join the `grenades` group or ask the skin pack for a visual — and one left outside the tree would be a leak.
	var me := Progress.of(0)
	var before := tree.get_nodes_in_group(Grenade.GROUP).size()
	for i in 20:
		me.weapon_numbers(load("res://weapons/grenade.tres") as Weapon)
	check("no stray grenades in the group",
		tree.get_nodes_in_group(Grenade.GROUP).size() == before,
		"%d -> %d" % [before, tree.get_nodes_in_group(Grenade.GROUP).size()])


func test_unlimited_ammo_is_left_off_the_list() -> void:
	# `max_ammo` is -1, and copied as is the screen shows a line "AMMO -1" (only noticed in a screenshot).
	# The rifle and grenade are both unlimited; this line should be kept for limited ammo like the ultimate.
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


# ---------------------------------------------------------------- Armour numbers

## Walk to the first item on the shelf that **is not a weapon** (the armour pages).
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
	# Stats have caps. A max-level player switching helmets sees all four lines "unchanged",
	# and with "do not draw what did not change" the details box would be completely empty, looking as if the gear does nothing (2026-09 playtest feedback).
	await open_shop()
	var me := Progress.of(0)
	for stat: StringName in Balance.STATS:
		me.allocated[stat] = 999       # At the cap
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


## What text the details box shows now (one Label per line).
func _card_labels() -> Array[String]:
	var out: Array[String] = []
	for node in column()._card.find_children("*", "Label", true, false):
		out.append((node as Label).text)
	return out
