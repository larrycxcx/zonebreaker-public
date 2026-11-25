extends GameTest
## Main menu: how many players, each seat creates or loads, deleting saves, then into the stage.
##
## The menu is a scene of its own (the game starts in it), so this suite **does not use `reset_scene()`**,
## it instantiates `main_menu.tscn` itself; the old stage tests still load `main.tscn` directly, unaffected.

var menu: MainMenu


func open_menu() -> void:
	free_scene()
	tree.paused = false
	Progress.persist = false
	Progress.new_game()
	Session.set_player_count(1)
	# Pad bindings live in the InputMap, which is global state — whatever the previous case claimed has to be restored
	Session.reset_pads()
	Skins.use(Skins.default_skin())
	events.clear()
	if not GameEvents.event_happened.is_connected(_record_event):
		GameEvents.event_happened.connect(_record_event)
	menu = (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate()
	main = menu
	tree.root.add_child(menu)
	await frames(2)


## Press once in the menu (menus also take keys in physics frames, as in the game).
func press(action: StringName) -> void:
	await tap(action)


## **Use the keys of the seat this page listens to**. The pages saying PLAYER 2 only accept `p2_*` —
## pressing player 1's keys on player 2's page does nothing, and the case would get stuck there (which is exactly the rule being guarded).
func press_here(action: StringName) -> void:
	await tap(Session.action_for(action, maxi(0, menu._menu.listens_to)))


## Move the cursor to item row. **Capped by number of presses**: if it cannot get there, give up rather than hang the case —
## when something is wrong we want an assertion failure, not the 60-second watchdog (which would not even show which assertion was wrong).
func move_to(row: int) -> void:
	for i in 12:
		if menu._menu.index == row:
			return
		await press_here(&"aim_down")


## Go to item index, then confirm.
func choose(index: int) -> void:
	await move_to(index)
	await press_here(&"jump")


# ---------------------------------------------------------------- Flow

func test_the_title_asks_how_many_are_playing() -> void:
	await open_menu()
	check("it opens on the title", menu.page() == MainMenu.Page.TITLE)
	check("with three choices", menu._menu._items == ["1 PLAYER", "2 PLAYERS", "QUIT"], str(menu._menu._items))
	await choose(0)
	check("picking one player moves on", menu.page() == MainMenu.Page.SOURCE and Session.player_count == 1,
		"%d players" % Session.player_count)
	check("and it is the first seat's turn", menu.seat() == 0)


func test_two_players_each_get_a_turn() -> void:
	await open_menu()
	await choose(1)
	check("two players", Session.player_count == 2)
	check("the first seat picks first", menu.seat() == 0)
	await choose(0)                       # NEW
	check("then the second", menu.seat() == 1 and menu.page() == MainMenu.Page.SOURCE, str(menu.seat()))


func test_backing_out_walks_the_flow_backwards() -> void:
	await open_menu()
	await choose(1)
	await choose(0)                       # Player 1 chose NEW, now it is player 2's turn
	check("setup: on the second seat", menu.seat() == 1)
	# **Use the keys of the seat this page listens to**: player 2's page ignores player 1's B
	await press_here(&"cancel")
	check("backing out goes to the seat before", menu.seat() == 0 and menu.page() == MainMenu.Page.SOURCE)
	await press_here(&"cancel")
	check("and again to the title", menu.page() == MainMenu.Page.TITLE)


func test_a_new_character_takes_the_seat() -> void:
	await open_menu()
	var before := Progress.roster.size()
	await choose(0)                       # 1 PLAYER
	await choose(0)                       # NEW
	check("a character was made", Progress.roster.size() == before + 1, str(Progress.roster.size()))
	check("and it sits in the first seat", Progress.seat_of(Progress.of(0)) == 0)


func test_the_hint_names_a_key_that_actually_works() -> void:
	# The title used to say "ENTER OR A TO START", but Enter was never bound — menu confirm goes through `jump`.
	# Whatever key a hint names has to really work.
	await open_menu()
	var hint := ""
	for child in menu._body.get_children():
		if child is Label and (child as Label).text.ends_with("TO START"):
			hint = (child as Label).text
	check("the title says how to start", hint != "", hint)
	var named := hint.split(" ")[0]
	var bound := false
	for event in InputMap.action_get_events(&"jump"):
		var key := event as InputEventKey
		if key != null and OS.get_keycode_string(key.physical_keycode).to_upper() == named:
			bound = true
	check("and %s really is bound to confirm" % named, bound, hint)


func test_the_menu_switches_the_music_over_to_its_own_slot() -> void:
	# The main menu belongs to the `intro` purpose. **The pack has no such track right now** (the old one did not fit and was removed until a replacement turns up),
	# so the menu is silent; put a track in the pack later and it will play — this test holds either way.
	await open_menu()
	check("the menu took over the music slot", Music.current == &"intro", str(Music.current))
	var track := Skins.music(&"intro")
	if track == null:
		check("no track in the pack, so it stays quiet", Music.playing_stream() == null,
			str(Music.playing_stream()))
	else:
		check("the pack's track is the one playing", Music.playing_stream() == track)


# ---------------------------------------------------------------- Save list

func test_the_list_shows_what_is_in_the_roster() -> void:
	await open_menu()
	var mine := Progress.create("RYU")
	mine.add_xp(Progress.balance.xp_to_next(1))
	mine.played_seconds = 3600.0 + 14.0 * 60.0
	Progress.create("NOVA")
	await choose(0)                       # 1 PLAYER
	await choose(1)                       # LOAD
	check("the list is up", menu.page() == MainMenu.Page.LOAD_LIST)
	var names := menu.listed().map(func(p: PlayerProgress) -> String: return p.character_name)
	check("both characters are on it", names.has("RYU") and names.has("NOVA"), str(names))
	check("playtime reads as hours and minutes", MainMenu.played_text(3600.0 + 14.0 * 60.0) == "1H 14M",
		MainMenu.played_text(3600.0 + 14.0 * 60.0))


func test_loading_seats_the_character_you_picked() -> void:
	await open_menu()
	var mine := Progress.create("RYU")
	mine.add_money(99)
	await choose(0)
	await choose(1)
	var row := menu.listed().find(mine)
	check("setup: RYU is on the list", row >= 0)
	await choose(row)
	check("RYU took the seat", Progress.of(0) == mine and Progress.of(0).money == 99, str(Progress.of(0).money))


func test_the_other_player_cannot_take_the_same_character() -> void:
	await open_menu()
	var one := Progress.create("RYU")
	Progress.create("NOVA")
	await choose(1)                       # 2 PLAYERS
	await choose(1)                       # Player 1 LOAD
	await choose(menu.listed().find(one))
	check("setup: the second seat is choosing", menu.seat() == 1)
	await choose(1)                       # Player 2 LOAD
	var row := menu.listed().find(one)
	check("the one already playing is greyed out", menu._menu.greyed.has(row), str(menu._menu.greyed))


func test_deleting_a_character_asks_first() -> void:
	await open_menu()
	var doomed := Progress.create("RYU")
	Progress.create("NOVA")
	await choose(0)
	await choose(1)
	var row := menu.listed().find(doomed)
	await move_to(row)
	await press(&"menu_delete")
	check("it asks first", menu.page() == MainMenu.Page.CONFIRM)
	check("and the character is still there", Progress.roster.has(doomed))
	await choose(0)                       # NO
	check("saying no keeps it", Progress.roster.has(doomed) and menu.page() == MainMenu.Page.LOAD_LIST)
	await move_to(menu.listed().find(doomed))
	await press(&"menu_delete")
	await choose(1)                       # YES
	check("saying yes deletes it", not Progress.roster.has(doomed))
	check("and the list no longer shows it",
		not menu.listed().any(func(p: PlayerProgress) -> bool: return p == doomed))


## On the roster list page, all content has to fall inside the window frame.
func list_box() -> Rect2:
	var screen := Vector2(640, 360)
	return Rect2((screen.x - MainMenu.LIST_BOX.x) / 2.0, 46.0, MainMenu.LIST_BOX.x, MainMenu.LIST_BOX.y)


func test_the_list_stays_inside_the_window() -> void:
	await open_menu()
	for n in ["LONGESTNAME", "NOVA"]:
		var who := Progress.create(PlayerProgress.sanitize_name(n))
		who.played_seconds = 10.0 * 3600.0
		who.saved_at = "2026-09-23T09:35:00"
	await choose(0)
	await choose(1)
	var inside := list_box().grow(-MainMenu.LIST_EDGE)
	var widest := 0.0
	for child in menu._body.get_children():
		if child is Label and not (child as Label).text.is_empty():
			var label := child as Label
			var wide: float = label.get_theme_font("font").get_string_size(
				label.text, label.horizontal_alignment, -1, UiKit.TEXT_SIZE).x
			# Right-aligned things (the scroll marker) are measured from the right, the rest from the left
			var right: float = (label.position.x + label.size.x if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT
				else label.position.x + wide)
			if label.position.y >= inside.position.y:
				widest = maxf(widest, right)
	check("setup: something was measured", widest > 0.0)
	check("no row runs past the frame", widest <= inside.end.x, "%.0f > %.0f" % [widest, inside.end.x])
	var cursor: Rect2 = Rect2(menu._menu.position + menu._menu.highlight_box(0).position,
		menu._menu.highlight_box(0).size)
	check("and neither does the gold box", cursor.position.x >= inside.position.x - 0.5
		and cursor.end.x <= inside.end.x + 0.5, str(cursor))


func test_the_gold_box_is_drawn_over_the_window() -> void:
	await open_menu()
	Progress.create("RYU")
	await choose(0)
	await choose(1)
	# Windows are added per page, and added after the menu they cover its selection box — you cannot see where the cursor is
	check("the menu is the last thing drawn",
		menu._body.get_child(menu._body.get_child_count() - 1) == menu._menu,
		"item %d of %d" % [menu._menu.get_index(), menu._body.get_child_count()])


func test_a_long_roster_scrolls_instead_of_being_cut_off() -> void:
	await open_menu()
	var names: Array[String] = []
	for i in MainMenu.ROWS + 3:
		names.append("HERO%d" % i)
		Progress.create(names[i])
	await choose(0)
	await choose(1)
	check("every character is on the list", menu.listed().size() == names.size(), str(menu.listed().size()))
	check("but only a screenful is drawn", menu._menu.rows_shown() == MainMenu.ROWS,
		str(menu._menu.rows_shown()))
	check("starting at the top", menu._menu.first_row() == 0)
	for i in MainMenu.ROWS:
		await press(&"aim_down")
	check("walking past the last drawn row scrolls", menu._menu.first_row() > 0,
		str(menu._menu.first_row()))
	check("the one you are on is still drawn",
		menu._menu.index - menu._menu.first_row() < MainMenu.ROWS
		and menu._menu.index >= menu._menu.first_row(),
		"%d / %d" % [menu._menu.index, menu._menu.first_row()])
	# Walk all the way down: the last one is reachable too
	for i in names.size():
		await press(&"aim_down")
	check("and the last one can be reached", menu._menu.index == menu.listed().size() - 1
		or menu._menu.first_row() > 0, str(menu._menu.index))


func test_the_cursor_starts_on_a_row_that_can_be_picked() -> void:
	await open_menu()
	var one := Progress.create("RYU")
	Progress.create("NOVA")
	await choose(1)                       # 2 PLAYERS
	await choose(1)                       # Player 1 LOAD
	await choose(menu.listed().find(one))
	await choose(1)                       # Player 2 LOAD
	var taken := menu.listed().find(one)
	check("setup: the one already playing is greyed out", menu._menu.greyed.has(taken), str(menu._menu.greyed))
	if taken == 0:
		check("the cursor does not start on it", menu._menu.index != 0, str(menu._menu.index))
	check("and the gold box is visible", menu._menu._cursor.visible)


func test_one_press_does_not_fall_through_two_pages() -> void:
	# The B that leaves character setup puts up the NEW/LOAD page on the same frame. That page's menu **must not take it again**,
	# or one B would go back two pages, straight to the title.
	await reach_setup(1)
	await press(&"cancel")
	check("backing out of setup lands on the source page and stops there",
		menu.page() == MainMenu.Page.SOURCE, str(menu.page()))


# ---------------------------------------------------------------- Character setup

## Go as far as "NEW / LOAD chosen" and stop at character setup.
func reach_setup(players: int) -> void:
	await open_menu()
	await choose(players - 1)             # 1 PLAYER / 2 PLAYERS
	for i in players:
		await choose(0)                   # NEW
	await frames(2)


## Move a column to a row (in the UI that is pressing up / down; here the cursor is placed directly to save typing).
func at_row(column: SetupColumn, row: int) -> void:
	column.go_to_row(row)
	await frames(1)


## Put the cursor on one half of the last row (SHOP / ACCEPT sit side by side on one row, chosen with left / right).
func at_foot(column: SetupColumn, which: int) -> void:
	column.go_to_foot(which)
	await frames(1)


func test_the_setup_screen_comes_before_the_level() -> void:
	await reach_setup(1)
	check("setup is up", menu.setup() != null)
	check("with one column", menu.setup() != null and menu.setup().columns().size() == 1)
	check("and the level has not started", tree.current_scene == null, str(tree.current_scene))


func test_two_players_get_a_column_each() -> void:
	await reach_setup(2)
	check("two columns", menu.setup().columns().size() == 2)
	var looks := menu.setup().columns().map(func(c: SetupColumn) -> StringName: return c.progress.look)
	check("and they start on different characters", looks[0] != looks[1], str(looks))


func test_left_and_right_change_the_character() -> void:
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	await at_row(column, SetupColumn.Row.LOOK)
	var before := column.progress.look
	await press(&"move_right")
	check("the look changed", column.progress.look != before, "%s -> %s" % [before, column.progress.look])
	await press(&"move_left")
	check("and comes back", column.progress.look == before, str(column.progress.look))


func test_the_other_player_s_character_is_skipped() -> void:
	await reach_setup(2)
	var one: SetupColumn = menu.setup().columns()[0]
	var two: SetupColumn = menu.setup().columns()[1]
	await at_row(one, SetupColumn.Row.LOOK)
	for i in SetupColumn.looks().size() + 1:
		await press(&"move_right")
		check("never lands on what the other player wears", one.progress.look != two.progress.look,
			"%s / %s" % [one.progress.look, two.progress.look])


func test_body_text_uses_the_small_font_and_titles_the_big_one() -> void:
	if needs_art(): return
	# A bitmap font is only sharp at the one size it was made at, so body text and titles each use their own atlas instead of letting the engine scale.
	await open_menu()
	var title: Label = null
	var item: Label = menu._menu._labels[0]
	for child in menu._body.get_children():
		if child is Label and (child as Label).text == MainMenu.TITLE:
			title = child
	check("setup: the title is on screen", title != null)
	check("the title is drawn from the big glyphs",
		title.get_theme_font("font").resource_path == UiKit.FONT,
		title.get_theme_font("font").resource_path)
	check("and the menu items from the small ones",
		item.get_theme_font("font").resource_path == UiKit.FONT_SMALL,
		item.get_theme_font("font").resource_path)
	check("which really are smaller", UiKit.TEXT_SIZE < 14, str(UiKit.TEXT_SIZE))
	var small: Font = load(UiKit.FONT_SMALL)
	var big: Font = load(UiKit.FONT)
	check("a line of text takes less room than it used to",
		small.get_string_size("CASH 1250", HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.TEXT_SIZE).x
		< big.get_string_size("CASH 1250", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x)


func test_the_column_says_what_level_the_character_is() -> void:
	await open_menu()
	var mine := Progress.create("RYU")
	mine.add_xp(Progress.balance.xp_to_next(1) + Progress.balance.xp_to_next(2))
	check("setup: RYU levelled up", mine.level >= 3, str(mine.level))
	await choose(0)                       # 1 PLAYER
	await choose(1)                       # LOAD
	await choose(menu.listed().find(mine))
	await frames(2)
	var column: SetupColumn = menu.setup().columns()[0]
	check("the level is written beside the faces", column._level.text == "LEVEL %d" % mine.level,
		column._level.text)
	var faces := column._portraits[SetupColumn.looks().size() - 1]
	check("and it sits to their right", column._level.position.x >= faces.position.x + faces.size.x,
		"%.0f vs %.0f" % [column._level.position.x, faces.position.x + faces.size.x])
	check("with room for the words", column._level.position.x + column._level.get_theme_font("font")
		.get_string_size(column._level.text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.TEXT_SIZE).x
		<= SetupColumn.WIDTH - 26.0, column._level.text)


func test_points_go_in_and_out_with_left_and_right() -> void:
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	var points := column.progress.points
	check("setup: a new character has points", points > 0, str(points))
	await at_row(column, SetupColumn.Row.STAT)          # The first stat
	await press(&"move_right")
	check("right puts one point in", column.progress.points == points - 1, str(column.progress.points))
	check("and it landed on life", column.progress.allocated.get(Balance.LIFE, 0) == 1,
		str(column.progress.allocated))
	await press(&"move_right")
	check("again for a second", column.progress.allocated.get(Balance.LIFE, 0) == 2,
		str(column.progress.allocated))
	await press(&"move_left")
	check("left takes one back out", column.progress.allocated.get(Balance.LIFE, 0) == 1
		and column.progress.points == points - 1, str(column.progress.allocated))


func test_points_stop_at_none_left_and_at_the_starting_value() -> void:
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	await at_row(column, SetupColumn.Row.STAT)
	# Keep adding until the points run out
	for i in column.progress.points + 3:
		await press(&"move_right")
	check("it stops when the points run out", column.progress.points == 0, str(column.progress.points))
	var spent: int = column.progress.allocated.get(Balance.LIFE, 0)
	check("setup: they all went into life", spent > 0, str(spent))
	# Take them all back until none are spent
	for i in spent + 3:
		await press(&"move_left")
	check("and it stops again at the starting value", not column.progress.allocated.has(Balance.LIFE),
		str(column.progress.allocated))
	check("with every point back in hand", column.progress.points == spent, str(column.progress.points))


func test_a_point_always_reads_as_plus_one() -> void:
	# Each point adds a different amount (life +10, attack +1, defence / speed +5); if the gold column showed the real amounts,
	# the same press of right would pop up different numbers for the three stats and players would think they pressed the wrong key. It shows **points put in**.
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	for i in Balance.STATS.size():
		await at_row(column, SetupColumn.Row.STAT + i)
		await press(&"move_right")
		check("one point in %s reads as +1" % Balance.STATS[i],
			column._stat_rows[i]["bonus"].text == "+1", column._stat_rows[i]["bonus"].text)
	await at_row(column, SetupColumn.Row.STAT)
	await press(&"move_right")
	check("two points read as +2", column._stat_rows[0]["bonus"].text == "+2",
		column._stat_rows[0]["bonus"].text)
	check("and the value beside it is still the real one",
		column._stat_rows[0]["value"].text == str(roundi(column.progress.stat(Balance.LIFE))),
		column._stat_rows[0]["value"].text)
	await press(&"move_left")
	await press(&"move_left")
	check("taking them all back leaves nothing", column._stat_rows[0]["bonus"].text == "",
		column._stat_rows[0]["bonus"].text)


func test_the_arrows_only_show_on_the_stat_you_are_on() -> void:
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	await at_row(column, SetupColumn.Row.STAT)
	check("the row you are on offers to add", column._stat_rows[0]["more"].visible)
	check("but not to take away yet", not column._stat_rows[0]["less"].visible)
	check("and the next row shows nothing", not column._stat_rows[1]["more"].visible)
	await press(&"move_right")
	check("once a point is in, taking it back is offered", column._stat_rows[0]["less"].visible)


func test_the_gold_box_follows_the_row_you_are_on() -> void:
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	await at_row(column, SetupColumn.Row.NAME)
	var on_name := column._menu.highlight_box(column.row())
	check("the box sits on the name", column._menu._cursor.position.is_equal_approx(on_name.position),
		"%s vs %s" % [column._menu._cursor.position, on_name.position])
	await at_row(column, SetupColumn.Row.STAT)
	var on_stat := column._menu.highlight_box(column.row())
	check("moving down really picks another block", not on_stat.position.is_equal_approx(on_name.position))
	check("and the box moved with it", column._menu._cursor.position.is_equal_approx(on_stat.position),
		"%s vs %s" % [column._menu._cursor.position, on_stat.position])


func test_the_gold_box_frames_the_gear_slot_you_are_on() -> void:
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	await at_row(column, SetupColumn.Row.GEAR)
	var first := column._menu._cursor.position
	check("it frames the first slot", first.is_equal_approx(column.slot_rect(0).grow(2.0).position),
		str(first))
	await press(&"move_right")
	check("moving a slot over moves the box", not column._menu._cursor.position.is_equal_approx(first))
	check("onto that slot", column._menu._cursor.position.is_equal_approx(
		column.slot_rect(column.slot).grow(2.0).position), str(column._menu._cursor.position))


func test_the_look_you_picked_is_not_marked_in_gold() -> void:
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	await at_row(column, SetupColumn.Row.LOOK)
	var mark: ColorRect = column._portraits[column.look_index()]
	check("the picked face is marked", mark.color == UiKit.GREEN, str(mark.color))
	check("in a colour the cursor never uses", mark.color != UiKit.GOLD)


func test_only_the_row_you_are_on_is_lit_up() -> void:
	# Drawn pure white all the time, ACCEPT stood out more than the gold box — with the name faded when loaded from a save, it looked as if the cursor rested on ACCEPT.
	# **Walk with key presses, not go_to_row**: redrawing on row change is wired up separately, and go_to_row refreshes by itself, so that path would not catch it.
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	check("setup: starting on the name", column.row() == SetupColumn.Row.NAME)
	check("accept is not lit up yet", column._accept.get_theme_color("font_color") == UiKit.DIM,
		str(column._accept.get_theme_color("font_color")))
	for i in SetupColumn.Row.FOOT:
		await press(&"aim_down")
	check("setup: walked down to the bottom row", column.row() == SetupColumn.Row.FOOT, str(column.row()))
	# **Coming down you land on SHOP first** (the left one); ACCEPT needs a press of "right"
	check("the left half lights up first",
		column._shop.get_theme_color("font_color") == UiKit.WHITE
		and column._accept.get_theme_color("font_color") == UiKit.DIM,
		"%s / %s" % [column._shop.get_theme_color("font_color"),
			column._accept.get_theme_color("font_color")])
	await press(&"move_right")
	check("and the right half takes over when you nudge across",
		column._accept.get_theme_color("font_color") == UiKit.WHITE
		and column._shop.get_theme_color("font_color") == UiKit.DIM,
		"%s / %s" % [column._shop.get_theme_color("font_color"),
			column._accept.get_theme_color("font_color")])


func test_shop_and_accept_sit_on_one_row_and_are_picked_left_and_right() -> void:
	# They are **drawn on the same line**, one left and one right. As two rows, two blocks clearly side by side on screen would be switched with up / down,
	# going exactly against this column's rule "up / down changes rows, left / right chooses within a row" (2026-09 playtest feedback).
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	check("they really are drawn on the same line",
		is_equal_approx(column._shop.position.y, column._accept.position.y),
		"%.0f / %.0f" % [column._shop.position.y, column._accept.position.y])
	for i in SetupColumn.Row.FOOT:
		await press(&"aim_down")
	check("setup: on the bottom row, left half", column.row() == SetupColumn.Row.FOOT
		and column.foot() == SetupColumn.Foot.SHOP, "%d / %d" % [column.row(), column.foot()])
	await press(&"move_right")
	check("right moves across, not down", column.row() == SetupColumn.Row.FOOT
		and column.foot() == SetupColumn.Foot.ACCEPT, "%d / %d" % [column.row(), column.foot()])
	await press(&"move_left")
	check("and left comes back", column.foot() == SetupColumn.Foot.SHOP, str(column.foot()))
	# **There is no "other row" between them**: this row is the last row, and up / down cannot squeeze in between the two
	check("the bottom row is the last one",
		SetupColumn.ROW_COUNT == SetupColumn.Row.FOOT + 1,
		"%d rows, the last row is %d" % [SetupColumn.ROW_COUNT, SetupColumn.Row.FOOT])


func test_the_cursor_box_follows_which_half_you_are_on() -> void:
	# The gold box frames **the content itself**, so moving left / right has to move the box to the other half
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	for i in SetupColumn.Row.FOOT:
		await press(&"aim_down")
	var on_shop := column.menu_list().row_boxes[SetupColumn.Row.FOOT]
	check("the box is over the left half",
		on_shop.get_center().x < column._accept.position.x, str(on_shop))
	await press(&"move_right")
	var on_accept := column.menu_list().row_boxes[SetupColumn.Row.FOOT]
	check("and moves over the right half when you do",
		on_accept.get_center().x > on_shop.get_center().x, "%s -> %s" % [on_shop, on_accept])


func test_shop_opens_from_the_left_half_and_accept_from_the_right() -> void:
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	await at_foot(column, SetupColumn.Foot.SHOP)
	await press(&"jump")
	check("A on the left half opens the shop", menu.setup().shop() != null)
	menu.setup()._close_shop()
	await frames(2)
	await at_foot(column, SetupColumn.Foot.ACCEPT)
	await press(&"jump")
	# **Alone, pressing ACCEPT turns the whole page to stage select**, and the column is torn down on the spot, so it checks the page
	check("A on the right half readies up instead",
		menu.page() == MainMenu.Page.STAGE, str(menu.page()))


func test_the_stat_arrows_follow_the_keys_too() -> void:
	# As above: walk with key presses to confirm row changes really redraw (the `go_to_row` path would hide a missing signal connection)
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	await press(&"aim_down")              # NAME -> LOOK
	await press(&"aim_down")              # LOOK -> the first stat
	check("setup: on the first stat", column.row() == SetupColumn.Row.STAT, str(column.row()))
	check("its arrow showed up", column._stat_rows[0]["more"].visible)
	await press(&"aim_down")
	check("and moves off with the cursor", not column._stat_rows[0]["more"].visible)
	check("onto the next one", column._stat_rows[1]["more"].visible)


func test_the_gear_icon_sits_inside_its_slot() -> void:
	if needs_art(): return
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	var slot := column.slot_rect(Equipment.Slot.GUN)
	var icon: TextureRect = column._slot_icons[Equipment.Slot.GUN]
	check("setup: there is a gun to show", icon.texture != null)
	var size: Vector2 = icon.texture.get_size()
	check("the icon is inside the frame", icon.position.x > slot.position.x
		and icon.position.y > slot.position.y
		and icon.position.x + size.x < slot.end.x
		and icon.position.y + size.y < slot.end.y,
		"%s %s vs %s" % [icon.position, size, slot])


## The rows of an image that really have something drawn (counted from the texture, so this test follows a new image).
func ink_rows(texture: Texture2D) -> Vector2:
	var image := texture.get_image()
	var top := -1.0
	var bottom := -1.0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				if top < 0.0:
					top = y
				bottom = y
				break
	return Vector2(top, bottom)


func test_the_stat_rows_leave_room_for_their_icons() -> void:
	if needs_art(): return
	# Row spacing is decided by **the icon**, not the text: the text is only 10px tall, but the drawing in a stat icon is 20px.
	# Too close together, the icons of neighbouring rows overlap, and the gold selection box covers the neighbour's icon too.
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	var boxes: Array[Rect2] = []
	for i in Balance.STATS.size():
		var icon: TextureRect = column._stat_rows[i]["icon"]
		var rows := ink_rows(icon.texture)
		var top: float = icon.position.y + rows.x
		var bottom: float = icon.position.y + rows.y
		var box := column._menu.highlight_box(SetupColumn.Row.STAT + i)
		boxes.append(box)
		check("row %d's box holds its whole icon" % i, box.position.y <= top and box.end.y >= bottom,
			"icon %.0f..%.0f vs box %.0f..%.0f" % [top, bottom, box.position.y, box.end.y])
	for i in boxes.size() - 1:
		check("row %d's box does not reach into the next one" % i,
			boxes[i].end.y <= boxes[i + 1].position.y,
			"%.0f > %.0f" % [boxes[i].end.y, boxes[i + 1].position.y])


func test_the_gear_row_walks_the_slots() -> void:
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	await at_row(column, SetupColumn.Row.GEAR)
	check("it starts on the gun", column.slot == Equipment.Slot.GUN)
	await press(&"move_right")
	check("right moves to the next slot", column.slot == Equipment.Slot.GRENADE, str(column.slot))
	await press(&"move_left")
	await press(&"move_left")
	check("and it wraps around", column.slot == Equipment.Slot.TRINKET, str(column.slot))


func test_a_loaded_character_starts_on_accept() -> void:
	# Loading a save usually means "as it is, let's go", so the cursor starts right on ACCEPT and one press is enough.
	await open_menu()
	var mine := Progress.create("RYU")
	await choose(0)                       # 1 PLAYER
	await choose(1)                       # LOAD
	await choose(menu.listed().find(mine))
	await frames(2)
	var column: SetupColumn = menu.setup().columns()[0]
	check("the cursor waits on accept", column.row() == SetupColumn.Row.FOOT
		and column.foot() == SetupColumn.Foot.ACCEPT,
		"row %d / %d" % [column.row(), column.foot()])
	check("and it is the lit-up row", column._accept.get_theme_color("font_color") == UiKit.WHITE,
		str(column._accept.get_theme_color("font_color")))
	await press(&"jump")
	# **Once pressed the column is gone** (the whole setup screen is replaced by stage select), so it checks the page, not `column.confirmed`
	check("so one press is enough to finish setting up",
		menu.page() == MainMenu.Page.STAGE, str(menu.page()))
	if is_instance_valid(menu):
		menu.free()
	tree.unload_current_scene()
	main = null
	menu = null


func test_a_new_character_starts_at_the_top_of_the_column() -> void:
	# A new character has nothing filled in yet; it starts on the name row
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	check("the cursor is on the first row", column.row() == SetupColumn.Row.NAME, str(column.row()))


func test_a_loaded_character_cannot_be_renamed() -> void:
	await open_menu()
	var mine := Progress.create("RYU")
	await choose(0)                       # 1 PLAYER
	await choose(1)                       # LOAD
	await choose(menu.listed().find(mine))
	await frames(2)
	check("setup is up", menu.setup() != null)
	check("and the name is locked", not menu.setup().columns()[0].can_rename)


# ---------------------------------------------------------------- Renaming

func test_typing_a_name_on_the_letter_grid() -> void:
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	# Typing continues from the existing name (small edits are possible), so shorten the name a bit before testing
	column.progress.character_name = "X"
	await at_row(column, SetupColumn.Row.NAME)
	await press(&"jump")
	check("the letter grid is up", column.grid() != null)
	check("and the column stops listening", column.busy())
	# The cursor starts on A: A, one right is B, one row further down is H (6 per row)
	await press(&"jump")
	await press(&"move_right")
	await press(&"jump")
	await press(&"aim_down")
	await press(&"jump")
	check("the letters land in order", column.grid().text == "XABH", column.grid().text)
	# The backspace cell is in the middle of the last row
	column.grid()._cursor = column.grid()._cells.find(LetterGrid.BACK)
	await press(&"jump")
	check("and delete takes one off", column.grid().text == "XAB", column.grid().text)
	await press(&"cancel")
	check("backing out closes the grid", column.grid() == null and not column.busy())
	check("and keeps what was typed", column.progress.character_name == "XAB", column.progress.character_name)


func test_a_name_that_is_taken_is_refused() -> void:
	await open_menu()
	Progress.create("AB")
	await choose(0)
	await choose(0)
	await frames(2)
	var column: SetupColumn = menu.setup().columns()[0]
	column.progress.character_name = "A"
	var before := column.progress.character_name
	await at_row(column, SetupColumn.Row.NAME)
	await press(&"jump")
	await press(&"move_right")
	await press(&"jump")                      # Type AB, which someone already uses
	check("setup: typed a name somebody already has", column.grid().text == "AB", column.grid().text)
	await press(&"cancel")
	check("the old name stays", column.progress.character_name == before, column.progress.character_name)


func test_a_loaded_name_cannot_be_typed_over() -> void:
	await open_menu()
	var mine := Progress.create("RYU")
	await choose(0)
	await choose(1)
	await choose(menu.listed().find(mine))
	await frames(2)
	var column: SetupColumn = menu.setup().columns()[0]
	await at_row(column, SetupColumn.Row.NAME)
	await press(&"jump")
	check("no grid for a loaded character", column.grid() == null)


## **Playing alone, character setup must not accept only player 1's keys**.
## The menus on the pages before have `listens_to` at -1 (anyone's press counts); character setup is the first page of the whole menu that filters input by player,
## so the same pad that worked fine on the earlier pages went completely dead on this one — which is what happens with the pad in the second slot
## (an earlier slot held by a ghost device that was not cleanly unplugged is common). The same goes for ↑ on the keyboard: alone it is both player 1's jump
## and player 2's "up", and accepting only player 1's set would turn it from "move up" into "confirm" on this page.
func test_playing_alone_is_not_tied_to_one_controller() -> void:
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	await at_row(column, SetupColumn.Row.GEAR)
	await tap(&"p2_aim_down")
	check("the other seat's keys still move the cursor", column.row() == SetupColumn.Row.FOOT,
		str(column.row()))
	await tap(&"p2_jump")
	check("and still choose", menu.setup().shop() != null)
	await tap(&"p2_cancel")
	await frames(2)
	check("and still back out", menu.setup().shop() == null)


## In co-op it is the other way round: each seat only accepts its own set, or the two players would drag each other's cursors around.
func test_two_players_stay_on_their_own_controllers() -> void:
	await reach_setup(2)
	var one: SetupColumn = menu.setup().columns()[0]
	var two: SetupColumn = menu.setup().columns()[1]
	await at_row(one, SetupColumn.Row.GEAR)
	await at_row(two, SetupColumn.Row.GEAR)
	await tap(&"p2_aim_down")
	check("player two moved", two.row() == SetupColumn.Row.FOOT, str(two.row()))
	check("player one did not", one.row() == SetupColumn.Row.GEAR, str(one.row()))


# ---------------------------------------------------------------- Gear boxes / shop entrance

func test_the_gear_row_only_shows_what_you_are_wearing() -> void:
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	await at_row(column, SetupColumn.Row.GEAR)
	check("setup: the gun slot has the rifle", column.progress.gear(Equipment.Slot.GUN) != null)
	await press(&"jump")
	# **Read-only**: gear can only be changed on the shop's bag page; pressing A here should do nothing
	check("A does not open anything", not column.busy() and menu.setup().shop() == null)
	check("and the rifle is still on", column.progress.gear(Equipment.Slot.GUN) != null)
	for i in Equipment.Slot.HEAD:
		await press(&"move_right")
	check("left and right still walk the slots", column.slot == Equipment.Slot.HEAD, str(column.slot))


func test_the_shop_row_opens_the_shop() -> void:
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	await at_foot(column, SetupColumn.Foot.SHOP)
	await press(&"jump")
	var shop := menu.setup().shop()
	check("the shop opens", shop != null and shop.columns().size() == 1)
	check("and the setup column stops listening", not column.is_visible_in_tree())
	await press(&"cancel")
	await frames(2)
	check("backing out closes it again", menu.setup().shop() == null)
	check("and the setup column is back", column.is_visible_in_tree())
	# The B that leaves the shop **must not** be taken again by the setup screen (that would back out of the whole page)
	check("without falling out of setup", menu.page() == MainMenu.Page.SETUP,
		str(menu.page()))


func test_both_players_shop_side_by_side() -> void:
	await reach_setup(2)
	var one: SetupColumn = menu.setup().columns()[0]
	await at_foot(one, SetupColumn.Foot.SHOP)
	await press(&"jump")
	var shop := menu.setup().shop()
	check("one player asking opens both columns", shop != null and shop.columns().size() == 2)
	await press(&"cancel")
	await frames(2)
	check("and one player leaving is not enough", menu.setup().shop() != null)
	check("that column waits for the other", shop.columns()[0].done and not shop.columns()[1].done)
	await tap(&"p2_cancel")
	await frames(2)
	check("both leaving closes the shop", menu.setup().shop() == null)


func test_everyone_has_to_accept_before_the_level_starts() -> void:
	await reach_setup(2)
	var one: SetupColumn = menu.setup().columns()[0]
	var two: SetupColumn = menu.setup().columns()[1]
	await at_foot(one, SetupColumn.Foot.ACCEPT)
	await press(&"jump")
	check("the first player is ready", one.confirmed)
	check("but the level waits", tree.current_scene == null, str(tree.current_scene))
	await at_foot(two, SetupColumn.Foot.ACCEPT)
	await tap(&"p2_jump")
	await frames(2)
	check("once both are ready setting up is done",
		menu.page() == MainMenu.Page.STAGE, str(menu.page()))
	await choose(0)
	for i in 30:
		await tree.physics_frame
		if tree.current_scene != null:
			break
	check("and picking a stage starts it", tree.current_scene != null
		and tree.current_scene.scene_file_path != "", str(tree.current_scene))
	if is_instance_valid(menu):
		menu.free()
	tree.unload_current_scene()
	main = null
	menu = null


func test_backing_out_of_ready_and_then_out_of_setup() -> void:
	# **This one has to be tested in co-op**: alone, one press of ACCEPT turns the page to stage select and the column is torn down on the spot,
	# and the two steps "cancel ACCEPT, then leave setup" can only be reached while "the other player is not ready yet".
	await reach_setup(2)
	var one: SetupColumn = menu.setup().columns()[0]
	await at_foot(one, SetupColumn.Foot.ACCEPT)
	await press(&"jump")
	check("setup: ready, and still on the setup screen because the other one is not",
		one.confirmed and menu.page() == MainMenu.Page.SETUP)
	await press(&"cancel")
	check("backing out cancels ready first", not one.confirmed and menu.setup() != null)
	await press(&"cancel")
	check("and again leaves the setup screen",
		menu.setup() == null and menu.page() == MainMenu.Page.SOURCE)


func test_backing_out_of_the_stage_list_returns_to_setup() -> void:
	# Stage select is the page after setup; B goes back to it and characters can still be changed
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	await at_foot(column, SetupColumn.Foot.ACCEPT)
	await press(&"jump")
	check("setup: it moved on to the stage list", menu.page() == MainMenu.Page.STAGE,
		str(menu.page()))
	await press(&"cancel")
	check("backing out comes back to the setup screen",
		menu.page() == MainMenu.Page.SETUP and menu.setup() != null, str(menu.page()))
	check("and nothing was started", tree.current_scene == null, str(tree.current_scene))


func test_every_stage_is_listed_while_the_unlock_switch_is_on() -> void:
	# The project setting `game/unlock_all_levels`: when on, stage select lists every stage regardless of progress.
	# While making stages you need to jump to any stage to try it — **turn it off before release**.
	check("the switch is on while levels are being built",
		ProjectSettings.get_setting("game/unlock_all_levels", false), "remember to turn it off before release")
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	await at_foot(column, SetupColumn.Foot.ACCEPT)
	await press(&"jump")
	check("setup: the stage list is up", menu.page() == MainMenu.Page.STAGE)
	var listed := menu._unlocked()
	check("a brand new character can still pick any stage",
		listed.size() == Catalog.levels().size(),
		"%d / %d, the character only unlocked %d stages"
			% [listed.size(), Catalog.levels().size(), Progress.of(0).reached])
	check("setup: this character really has not unlocked them all",
		Progress.of(0).reached < Catalog.levels().size(), str(Progress.of(0).reached))


func test_finishing_the_last_seat_starts_the_level() -> void:
	await reach_setup(1)
	var column: SetupColumn = menu.setup().columns()[0]
	await at_foot(column, SetupColumn.Foot.ACCEPT)
	await press(&"jump")
	check("setting up is done", menu.page() == MainMenu.Page.STAGE, str(menu.page()))
	await choose(0)
	for i in 30:
		await tree.physics_frame
		if tree.current_scene != null:
			break
	# Identify by **scene file**, not root node name: the real stages are level_N.tscn, only the test level is main.tscn
	check("the level is loaded", tree.current_scene != null
		and tree.current_scene.scene_file_path == Catalog.levels()[0].scene_path,
		str(tree.current_scene))
	# Teardown has to clean up two things; missing either one wrecks the cases that follow:
	# 1. **The menu node itself** — it was add_child'ed to root by hand, and `change_scene_to_file` only replaces current_scene,
	# leaving it alone. Left there it keeps taking keys every frame, and the next case pressing A would be taken as a menu confirm.
	# 2. **current_scene** — only free()ing it leaves the SceneTree remembering a node that is gone; when a player later dies,
	# `main.gd` calls `reload_current_scene()` on it and the coroutine dies on the spot, showing up as a pile of mysterious "event not reported".
	if is_instance_valid(menu):
		menu.free()
	tree.unload_current_scene()
	main = null
	menu = null


func test_the_shop_does_not_print_two_hints_on_top_of_each_other() -> void:
	# The setup screen's bottom line `A CHOOSE  B BACK` and the shop's line `A CHOOSE … B LEAVE` are at **the same y**,
	# and two centred lines on top of each other blur into a mess (found in a 2026-09 playtest screenshot; headless tests cannot measure overlapping positions,
	# so what it guards is "only one line shows while the shop is open").
	await reach_setup(2)
	var setup := menu.setup()
	var hints := _visible_hints(setup)
	check("setup: the setup screen has its own hint", hints.size() == 1, str(hints))
	setup._open_shop()
	await frames(2)
	check("the shop is open", setup.shop() != null)
	hints = _visible_hints(setup)
	check("and only one hint is showing", hints.size() == 1, str(hints))
	check("the one that belongs to the shop",
		hints.size() == 1 and hints[0].contains("LEAVE"), str(hints))
	setup._close_shop()
	await frames(2)
	hints = _visible_hints(setup)
	check("closing it brings the other one back",
		hints.size() == 1 and hints[0].contains("BACK"), str(hints))


## The hint lines **visible** on screen now (one for setup, one for the shop, both against the bottom of the view).
func _visible_hints(setup: SetupScreen) -> Array[String]:
	var out: Array[String] = []
	for node in setup.find_children("*", "Label", true, false):
		var label := node as Label
		if label.is_visible_in_tree() and label.text.contains("A CHOOSE"):
			out.append(label.text)
	return out


func test_a_seat_can_only_be_filled_by_its_own_controller() -> void:
	# **The "pads swapped" report from playtesting**: player 1 loaded a save, entered character setup and found they were player 2.
	# The cause: the pages saying PLAYER 1 **accepted anyone's press** — the person holding pad 2 chose a character into seat 1,
	# and once in setup (where that column only listens to pad 1) they could only operate player 2's column.
	# Deleting saves already went by seat; what was missing was the navigation half.
	await open_menu()
	await choose(1)                       # 2 PLAYERS
	check("setup: it is the first seat's turn", menu.seat() == 0 and menu.page() == MainMenu.Page.SOURCE)
	var at: int = menu._menu.index
	await tap(&"p2_aim_down")
	check("the second pad cannot move the first seat's cursor", menu._menu.index == at,
		"%d -> %d" % [at, menu._menu.index])
	await tap(&"p2_jump")
	check("nor choose for it", menu.seat() == 0 and menu.page() == MainMenu.Page.SOURCE,
		"seat %d, page %d" % [menu.seat(), menu.page()])
	await press(&"jump")                  # Player 1 presses NEW themselves
	check("the first pad does", menu.seat() == 1 and menu.page() == MainMenu.Page.SOURCE)
	# Player 2's turn now, the other way round
	at = menu._menu.index
	await tap(&"aim_down")
	check("and now the first pad cannot move the second seat's cursor", menu._menu.index == at,
		"%d -> %d" % [at, menu._menu.index])
	await tap(&"p2_jump")
	check("while the second pad can", menu.page() == MainMenu.Page.SETUP, str(menu.page()))


func test_the_shared_pages_still_take_anybody() -> void:
	# "How many players" and "which stage" are decided by everyone together and should not be split by seat
	# (at that point nobody has a seat yet / both play the same stage), for the same reason as the death screen.
	await open_menu()
	check("setup: on the title", menu.page() == MainMenu.Page.TITLE)
	var at: int = menu._menu.index
	await tap(&"p2_aim_down")
	check("the second pad moves the title cursor too", menu._menu.index != at,
		"%d -> %d" % [at, menu._menu.index])
	check("the title listens to everyone", menu._menu.listens_to == -1,
		str(menu._menu.listens_to))


func test_playing_alone_is_never_locked_out_by_which_slot_the_pad_is_in() -> void:
	# Alone, anyone's press counts (the rule lives in `Session.just_pressed()`): the pad in the second slot is common,
	# and filtering by seat would leave a lone player with a page that does not respond.
	await open_menu()
	await choose(0)                       # 1 PLAYER
	check("setup: one player, first seat", Session.player_count == 1 and menu.seat() == 0)
	var at: int = menu._menu.index
	await tap(&"p2_aim_down")
	check("a pad in the second slot still drives the menu", menu._menu.index != at,
		"%d -> %d" % [at, menu._menu.index])


# ---------------------------------------------------------------- Which pad is which player

func test_the_pad_that_starts_the_game_becomes_player_one() -> void:
	# **Godot hands out device numbers in plug-in order**, which has nothing to do with the player's idea of "pad 1":
	# an earlier slot held by a ghost device that was not cleanly unplugged is common, and the pad in hand becomes device 1.
	# With a hard-coded "seat 0 ↔ device 0", everything works for them on the title screen (anyone's press counts),
	# but the page saying PLAYER 1 no longer responds, while the other pad does (reported in the 2026-09 playtest).
	await open_menu()
	check("setup: it starts on the project's own wiring",
		Session.pad_of(0) == 0 and Session.pad_of(1) == 1,
		"%d / %d" % [Session.pad_of(0), Session.pad_of(1)])
	Session.claim_pads(1)
	check("the pad that pressed becomes the first seat's", Session.pad_of(0) == 1,
		str(Session.pad_of(0)))
	check("and the first seat's buttons now listen to it",
		_pad_devices(&"jump") == [1], str(_pad_devices(&"jump")))
	# **Not a single keyboard key may be touched**: their `device` is -1 (any device),
	# and changing them to one pad's number would tie the keyboard to that one device
	check("while the keyboard keys are untouched",
		_key_devices(&"jump") == [-1], str(_key_devices(&"jump")))


func test_claiming_a_pad_does_not_disturb_the_keyboard() -> void:
	await open_menu()
	var before := _has_key_event(&"move_left") and _has_key_event(&"p2_move_left")
	Session.claim_pads(1)
	check("setup: both seats had keyboard keys", before)
	check("and they still do", _has_key_event(&"move_left") and _has_key_event(&"p2_move_left"))
	check("still on any device", _key_devices(&"move_left") == [-1]
		and _key_devices(&"p2_move_left") == [-1],
		"%s / %s" % [_key_devices(&"move_left"), _key_devices(&"p2_move_left")])


func test_a_keyboard_start_leaves_the_pads_alone() -> void:
	# A game started from the keyboard (`last_pad` still -1) must not scramble the pad bindings
	await open_menu()
	Session.claim_pads(-1)
	check("nothing moved", Session.pad_of(0) == 0 and Session.pad_of(1) == 1,
		"%d / %d" % [Session.pad_of(0), Session.pad_of(1)])


func test_the_title_hands_out_the_pads() -> void:
	# Claim the pads at the moment the number of players is chosen on the title screen — the first moment "who pressed it" means something
	await open_menu()
	Session.last_pad = 1
	await choose(0)                       # 1 PLAYER
	check("leaving the title claims the pad that was pressing", Session.pad_of(0) == 1,
		str(Session.pad_of(0)))


func test_resetting_puts_the_pads_back() -> void:
	# The InputMap is global state and has to be restored after every case (called in `GameTest.reset_scene()`)
	await open_menu()
	Session.claim_pads(1)
	check("setup: it moved", Session.pad_of(0) == 1)
	Session.reset_pads()
	check("reset puts it back", Session.pad_of(0) == 0 and Session.pad_of(1) == 1,
		"%d / %d" % [Session.pad_of(0), Session.pad_of(1)])
	check("and the buttons follow", _pad_devices(&"jump") == [0], str(_pad_devices(&"jump")))


## Which pads the pad events on this action are bound to (sorted, duplicates removed).
func _pad_devices(action: StringName) -> Array[int]:
	var out: Array[int] = []
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			if not out.has(event.device):
				out.append(event.device)
	out.sort()
	return out


## Which devices the keyboard events on this action are bound to (normally all -1 = any device).
func _key_devices(action: StringName) -> Array[int]:
	var out: Array[int] = []
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and not out.has(event.device):
			out.append(event.device)
	out.sort()
	return out


## Does this action still have keyboard keys?
func _has_key_event(action: StringName) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return true
	return false


func test_two_seats_never_share_one_pad() -> void:
	# Only one pad plugged in and two players chosen: player 1 claimed it, and if player 2 were still bound to the same one,
	# one person moving would move both characters. On claiming, it **swaps** with the seat that held it before.
	await open_menu()
	check("setup: the seats start on different pads", Session.pad_of(0) != Session.pad_of(1),
		"%d / %d" % [Session.pad_of(0), Session.pad_of(1)])
	Session.claim_pads(1)                 # Player 1 claimed the pad that belonged to player 2
	check("they still have one each", Session.pad_of(0) != Session.pad_of(1),
		"%d / %d" % [Session.pad_of(0), Session.pad_of(1)])
	check("and they simply swapped", Session.pad_of(0) == 1 and Session.pad_of(1) == 0,
		"%d / %d" % [Session.pad_of(0), Session.pad_of(1)])
	check("the buttons followed", _pad_devices(&"jump") == [1]
		and _pad_devices(&"p2_jump") == [0],
		"%s / %s" % [_pad_devices(&"jump"), _pad_devices(&"p2_jump")])


func test_both_pads_can_still_pause_after_claiming() -> void:
	# `pause` **is deliberately bound to the Start button of two pads** (both players can pause).
	# Rebinding everything by seat would squash it to one pad — after claiming only one player could pause.
	await open_menu()
	check("setup: both pads start out able to pause", _pad_devices(&"pause") == [0, 1],
		str(_pad_devices(&"pause")))
	Session.claim_pads(1)
	check("after claiming, two pads can still pause", _pad_devices(&"pause").size() == 2,
		"%s, seats %d / %d" % [_pad_devices(&"pause"), Session.pad_of(0), Session.pad_of(1)])
	for seat in 2:
		check("seat %d's pad is among them" % seat,
			_pad_devices(&"pause").has(Session.pad_of(seat)), str(_pad_devices(&"pause")))
	check("and the keyboard still pauses", _has_key_event(&"pause"))


func test_the_game_name_fits_inside_the_title_plate() -> void:
	if needs_art(): return
	# Named ZONE BREAKER in 2026-11: 12 characters at 28px are about 295 wide, and the art's original plate (285 wide, the panel inset 16 on each side) could not hold them,
	# so the text stuck out on both sides (seen in a screenshot). The plate was widened by `ui_build.py`; if a future name is too long, this speaks up first.
	await open_menu()
	var title: Label = null
	var plate: TextureRect = null
	for child in menu._body.get_children():
		if child is Label and (child as Label).text == MainMenu.TITLE:
			title = child
		if child is TextureRect and (child as TextureRect).texture != null \
				and (child as TextureRect).texture.resource_path.ends_with("title_plate.png"):
			plate = child
	check("setup: the title and its plate are on screen", title != null and plate != null)
	var wide: float = title.get_theme_font("font").get_string_size(
		MainMenu.TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.TITLE_SIZE).x
	var room: float = plate.texture.get_width() - 32.0
	check("the name fits inside the plate's frame", wide <= room, "%.0f wide, %.0f of room" % [wide, room])
	var screen := 640.0
	check("and the plate is centred under it",
		absf(plate.position.x + plate.texture.get_width() / 2.0 - screen / 2.0) < 1.0, str(plate.position.x))
