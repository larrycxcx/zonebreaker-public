class_name MainMenu
extends Node2D
## Main menu: choose how many players, each creates or loads a character, then the stage starts.
##
## A little flow made of several pages (`Page`):
## title (1 PLAYER / 2 PLAYERS / QUIT) → **each seat in turn** chooses NEW or LOAD →
## LOAD picks one from the roster (the list shows name, level, play time and last save time, and can delete) →
## once everyone has chosen, `change_scene_to_file` enters the stage.
##
## Character setup (naming, picking a look, spending points, gear) is not built yet; choosing NEW just creates a default character on the spot and goes;
## once that step exists it goes between "NEW / LOAD chosen" and "entering the stage".
##
## The UI is always English upper case (the pack's font has no Chinese glyphs, see CLAUDE.md).

## Which stage to start from: the first stage found by **scanning the `levels/` directory** (see `Catalog`), not named in code.
## So adding a stage means dropping a `.tres` in there, and DLC goes the same way.
## (`scenes/main.tscn` is the test level, not in the list; tests load it directly.)
static func level_scene() -> String:
	var first := Catalog.first_level()
	return first.scene_path if first != null else ""
## The game's name, written in the panel of the title plate (decided in 2026-11; the window title / save folder follow `application/config/name`).
const TITLE := "ZONE BREAKER"
const SUBTITLE := "A RUN AND GUN"

enum Page {
	TITLE,      ## how many players
	SOURCE,     ## this seat creates or loads
	LOAD_LIST,  ## pick one from the roster
	CONFIRM,    ## really delete?
	SETUP,      ## character setup (one column per player, starts once everyone has confirmed)
	STAGE,      ## pick a stage among the unlocked ones (skipped when only one can be chosen)
}

## Rows shown per page of the roster list. With more saves than this it scrolls instead of cutting off the rest.
const ROWS := 6
## Width and height of the list's window.
const LIST_BOX := Vector2(480.0, 240.0)
## The nine-slice frame takes this many pixels on each side; text has to fall inside it, or the frame cuts it off.
const LIST_EDGE := 32.0
## Four columns: title, distance from the left edge of the content, width. **The end of the rightmost column has to fall inside the frame**
## (content left = window left + 40, so it can reach at most 480 - 40 - 32 = 408).
const LIST_COLUMNS := [["NAME", 0.0, 134.0], ["LV", 138.0, 40.0], ["PLAYED", 186.0, 84.0], ["SAVED", 278.0, 122.0]]

var _page := Page.TITLE
## Which seat is choosing now.
var _seat := 0
## Which characters the list shows now (indexes match the menu items).
var _listed: Array[PlayerProgress] = []
## The one to delete.
var _doomed: PlayerProgress
## Which seats were loaded from a save (their names cannot be changed).
var _loaded: Array[int] = []
var _setup: SetupScreen
## The text of the list rows (four per row); scrolling changes their content instead of laying out nodes again.
var _row_labels: Array[Array] = []
var _scroll_mark: Label

var _ui: CanvasLayer
var _body: Control
var _menu: MenuList
var _title: Label
var _hint: Label


func _ready() -> void:
	_add_backdrop()
	_ui = CanvasLayer.new()
	_ui.layer = 5
	add_child(_ui)
	# The backdrop is the daytime one and quite bright; darken it a layer so the menu text is readable
	var shade := UiKit.shade(0.34)
	_ui.add_child(shade)
	_body = Control.new()
	_body.set_anchors_preset(Control.PRESET_FULL_RECT)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_body)
	_menu = MenuList.new()
	_body.add_child(_menu)
	_menu.chosen.connect(_on_chosen)
	_menu.cancelled.connect(_on_cancelled)
	Music.play(&"intro")
	_show(Page.TITLE)


## The same backdrop as the stages (the skin pack's if it has one, otherwise the clear colour shows).
func _add_backdrop() -> void:
	var scene := Skins.backdrop()
	if scene == null:
		return
	var backdrop := scene.instantiate()
	backdrop.name = "Backdrop"
	add_child(backdrop)
	move_child(backdrop, 0)
	# The lighting layer comes along too (the bar street at night is all grey without it)
	var lighting := Skins.lighting()
	if lighting != null:
		var light := lighting.instantiate()
		light.name = "Lighting"
		add_child(light)
		move_child(light, 1)


func page() -> Page:
	return _page


func seat() -> int:
	return _seat


## The characters the list shows now (for tests).
func listed() -> Array[PlayerProgress]:
	return _listed


## The character setup page (for tests); null when not on that page.
func setup() -> SetupScreen:
	return _setup if _page == Page.SETUP and is_instance_valid(_setup) else null


func _physics_process(_delta: float) -> void:
	# **By this seat's own action** (in co-op player 1 has `menu_delete`, player 2 `p2_menu_delete`):
	# the two seats choose in turn, and deleting acts on whoever's page it is; it must not be triggered by the other pad. When playing alone anyone's press counts.
	if _page == Page.LOAD_LIST and not _listed.is_empty() and Session.just_pressed(&"menu_delete", _seat):
		_doomed = _listed[_menu.index]
		_show(Page.CONFIRM)


# ---------------------------------------------------------------- Drawing each page

## Whose keys each page listens to. **The pages that say PLAYER N only listen to that seat's own pad** —
## otherwise the person holding pad 2 could choose a character into seat 1, and on reaching character setup
## (where that column only listens to pad 1) they would turn into player 2 (the "pads swapped" report from the 2026-09 playtest).
## "How many players" and "which stage" are **decided by everyone together**, so they stay at -1 (anyone's press counts), for the same reason as the death screen.
## Deleting saves already goes by seat (`_physics_process`); this only completes the navigation half.
## When playing alone `Session.just_pressed()` accepts anyone's press, so these pages behave the same in single player.
const LISTENS := {
	Page.TITLE: -1,
	Page.SETUP: -1,
	Page.STAGE: -1,
}


func _show(page_: Page) -> void:
	_page = page_
	for child in _body.get_children():
		if child != _menu:
			child.queue_free()
	_menu.listens_to = LISTENS.get(page_, _seat)
	var screen := _screen()
	match page_:
		Page.TITLE:
			_draw_title(screen)
			_lay_out(["1 PLAYER", "2 PLAYERS", "QUIT"], screen, 186.0, "SPACE OR A TO START")
		Page.SOURCE:
			_heading("PLAYER %d" % (_seat + 1), screen)
			_lay_out(["NEW CHARACTER", "LOAD CHARACTER", "BACK"], screen, 150.0, "A CHOOSE    B BACK")
		Page.LOAD_LIST:
			_draw_list(screen)
		Page.CONFIRM:
			_heading("DELETE %s" % _doomed.character_name, screen)
			_lay_out(["NO", "YES"], screen, 170.0, "THIS CANNOT BE UNDONE")
		Page.SETUP:
			_menu.build([], 0.0)
			_setup = SetupScreen.new()
			_body.add_child(_setup)
			_setup.build(Session.player_count, _loaded)
			_setup.finished.connect(_after_setup)
			_setup.cancelled.connect(_back_to_source)
		Page.STAGE:
			_heading("SELECT STAGE", screen)
			var names: Array[String] = []
			for level in _unlocked():
				names.append("%d  %s" % [Catalog.index_of(level) + 1, level.display_name])
			_lay_out(names, screen, 130.0, "A CHOOSE    B BACK")
			# The cursor rests on the furthest stage = "carry on from last time"; move up to replay earlier ones
			_menu.index = maxi(0, names.size() - 1)
	# The menu is added in `_ready` and each page's windows are added later — **later additions are drawn on top**,
	# so without moving it the gold selection box would be covered by the window and you could not see where the cursor is.
	_body.move_child(_menu, -1)


func _screen() -> Vector2:
	return Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 640),
		ProjectSettings.get_setting("display/window/size/viewport_height", 360))


func _draw_title(screen: Vector2) -> void:
	var plate := UiKit.picture(UiKit.DIR + "/title_plate.png", Vector2.ZERO)
	if plate.texture != null:
		plate.position = Vector2((screen.x - plate.texture.get_width()) / 2.0, 14.0)
		_body.add_child(plate)
	else:
		plate.free()
	_body.add_child(UiKit.label(TITLE, Rect2(0, 40.0, screen.x, 34.0), UiKit.CYAN,
		UiKit.TITLE_SIZE, HORIZONTAL_ALIGNMENT_CENTER))
	_body.add_child(UiKit.label(SUBTITLE, Rect2(0, 98.0, screen.x, 20.0), Color(0.62, 0.68, 0.82),
		UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_CENTER))


func _heading(text: String, screen: Vector2) -> void:
	_title = UiKit.label(text, Rect2(0, 64.0, screen.x, 34.0), UiKit.CYAN,
		UiKit.TITLE_SIZE, HORIZONTAL_ALIGNMENT_CENTER)
	_body.add_child(_title)


func _lay_out(items: Array[String], screen: Vector2, top: float, hint: String) -> void:
	_menu.wide_highlight = false
	_menu.row_boxes = []
	_menu.greyed = []
	_menu.window_rows = 0
	_menu.build(items, screen.x)
	_menu.position = Vector2(0, top)
	_hint = UiKit.label(hint, Rect2(0, screen.y - 40.0, screen.x, 20.0), Color(0.74, 0.80, 0.92),
		UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_CENTER)
	_body.add_child(_hint)


## Roster list: one character per row, name / level / play time / last save. Ones already taken by the other seat are greyed out.
func _draw_list(screen: Vector2) -> void:
	_listed = Progress.by_recent()
	var box := Rect2((screen.x - LIST_BOX.x) / 2.0, 46.0, LIST_BOX.x, LIST_BOX.y)
	_body.add_child(UiKit.window(box))
	# The title has to fall **inside** the window: the nine-slice frame takes 32px, and text on the edge would be cut off by the frame
	_body.add_child(UiKit.label("PLAYER %d" % (_seat + 1), Rect2(box.position + Vector2(0, 30.0), Vector2(box.size.x, 22.0)),
		UiKit.CYAN, UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_CENTER))
	var left := box.position.x + 40.0
	var head := box.position.y + 60.0
	for column in LIST_COLUMNS:
		_body.add_child(UiKit.label(column[0], Rect2(Vector2(left + column[1], head), Vector2(column[2], 20.0)), UiKit.DIM))
	# How far it has scrolled (only written when there are more saves than fit on one screen). Placed at the right end of the title row, not squeezed into the SAVED column
	_scroll_mark = UiKit.label("", Rect2(box.position + Vector2(LIST_EDGE, 30.0),
		Vector2(box.size.x - LIST_EDGE * 2.0 - 8.0, 22.0)), UiKit.DIM,
		UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT)
	_body.add_child(_scroll_mark)
	var rows: Array[String] = []
	var taken: Array[int] = []
	for i in _listed.size():
		rows.append("")
		if Progress.seat_of(_listed[i]) >= 0 and Progress.seat_of(_listed[i]) != _seat:
			taken.append(i)
	_menu.wide_highlight = true
	_menu.row_boxes = []
	_menu.window_rows = ROWS
	# The selection box hugs the inner edge of the frame: left 32, width 480 - 32 × 2
	_menu.build(rows, box.size.x - LIST_EDGE * 2.0)
	_menu.position = Vector2(box.position.x + LIST_EDGE, head + 22.0)
	_menu.greyed = taken
	_row_labels.clear()
	for i in _menu.rows_shown():
		var y := head + 22.0 + i * MenuList.ROW_HEIGHT
		var line: Array[Label] = []
		for column in LIST_COLUMNS:
			var label := UiKit.label("", Rect2(Vector2(left + column[1], y), Vector2(column[2], 20.0)), UiKit.WHITE)
			_body.add_child(label)
			line.append(label)
		_row_labels.append(line)
	_fill_rows()
	if not _menu.moved.is_connected(_on_list_moved):
		_menu.moved.connect(_on_list_moved)
	_hint = UiKit.label("A LOAD    X DELETE    B BACK",
		Rect2(0, _screen().y - 40.0, _screen().x, 20.0), Color(0.74, 0.80, 0.92),
		UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_CENTER)
	_body.add_child(_hint)


func _on_list_moved(_index: int) -> void:
	if _page == Page.LOAD_LIST:
		_fill_rows()


## Write the characters currently scrolled into view into those rows. **The nodes are not laid out again, only the text changes** —
## rebuilding a pile of Labels while scrolling would make the page flicker on every press.
func _fill_rows() -> void:
	var first := _menu.first_row()
	for i in _row_labels.size():
		var at := first + i
		var line: Array = _row_labels[i]
		if at >= _listed.size():
			for label: Label in line:
				label.text = ""
			continue
		var profile := _listed[at]
		var texts := [profile.character_name, str(profile.level),
			played_text(profile.played_seconds), saved_text(profile.saved_at)]
		var tint := UiKit.DIM.darkened(0.35) if _menu.greyed.has(at) else UiKit.WHITE
		for j in line.size():
			var label: Label = line[j]
			label.text = texts[j]
			label.add_theme_color_override("font_color", tint)
	if _scroll_mark != null:
		_scroll_mark.text = ("%d/%d" % [_menu.index + 1, _listed.size()]
			if _listed.size() > _row_labels.size() else "")


## Play time, written as `2H 14M`.
static func played_text(seconds: float) -> String:
	var whole := int(seconds)
	return "%dH %02dM" % [whole / 3600, (whole % 3600) / 60]


## Date and time of the save, written as `09 21 22 40` (all separated by spaces — simplest and easiest on the eye).
static func saved_text(stamp: String) -> String:
	if stamp.length() < 16:
		return ""
	return "%s %s %s %s" % [stamp.substr(5, 2), stamp.substr(8, 2), stamp.substr(11, 2), stamp.substr(14, 2)]


# ---------------------------------------------------------------- What was chosen

func _on_chosen(index: int) -> void:
	match _page:
		Page.TITLE:
			if index == 2:
				get_tree().quit()
				return
			Session.set_player_count(index + 1)
			# **The pad that made this press is player 1**, the other connected ones follow in order.
			# Godot hands out device numbers in plug-in order, which has nothing to do with the player's idea of "pad 1".
			Session.claim_pads(Session.last_pad)
			_seat = 0
			_loaded.clear()
			_show(Page.SOURCE)
		Page.SOURCE:
			match index:
				0:
					Progress.take_seat(_seat, Progress.fresh(_seat))
					_loaded.erase(_seat)
					_next_seat()
				1:
					if Progress.roster.is_empty():
						return
					_show(Page.LOAD_LIST)
				2:
					_on_cancelled()
		Page.LOAD_LIST:
			Progress.take_seat(_seat, _listed[index])
			if not _loaded.has(_seat):
				_loaded.append(_seat)
			_next_seat()
		Page.CONFIRM:
			if index == 1:
				Progress.remove(_doomed)
			_doomed = null
			_show(Page.LOAD_LIST)
		Page.STAGE:
			var picked := _unlocked()
			if index < picked.size():
				start_game(picked[index])


func _on_cancelled() -> void:
	match _page:
		Page.TITLE:
			pass
		Page.SOURCE:
			if _seat == 0:
				_show(Page.TITLE)
			else:
				_seat -= 1
				_show(Page.SOURCE)
		Page.LOAD_LIST:
			_show(Page.SOURCE)
		Page.CONFIRM:
			_doomed = null
			_show(Page.LOAD_LIST)
		Page.SETUP:
			pass
		Page.STAGE:
			_show(Page.SETUP)


## A switch in the project settings: when on, **every stage can be chosen**, however far you have got.
## While making stages you need to jump to any stage to try it; otherwise every tweak to stage 5 would mean playing through the first four.
## **Remember to turn it off before release** — while it is on there is no "play through the stages one by one".
const UNLOCK_ALL := "game/unlock_all_levels"


## The unlocked stages. **In co-op take the higher of the two players**: when a veteran plays with a newcomer the friend can come along further,
## without replaying a dozen stages with the new character (on a clear both players' progress moves on, see `main.gd._unlock_next()`).
func _unlocked() -> Array[LevelInfo]:
	var all := Catalog.levels()
	if ProjectSettings.get_setting(UNLOCK_ALL, false):
		return all
	var reached := 1
	for index in Session.player_count:
		reached = maxi(reached, Progress.of(index).reached)
	return all.slice(0, clampi(reached, 1, all.size()))


## Characters are all set up: with only one stage unlocked start right away, ask only when there is a choice.
func _after_setup() -> void:
	if _unlocked().size() <= 1:
		start_game(Catalog.first_level())
		return
	_show(Page.STAGE)


## Back from character setup: return to the first seat to choose NEW / LOAD again.
func _back_to_source() -> void:
	_seat = 0
	_show(Page.SOURCE)


## This seat has chosen: if someone has not chosen yet it is their turn, otherwise on to character setup.
func _next_seat() -> void:
	_seat += 1
	if _seat < Session.player_count:
		_show(Page.SOURCE)
	else:
		_show(Page.SETUP)


## Start playing. **Before the stage loads**, settle "which stage is being played":
## enemies and platforms ask this stage's skin pack for their look and scale their strength by its multipliers in their own `_ready`.
func start_game(level: LevelInfo = null) -> void:
	var going: LevelInfo = level if level != null else Catalog.first_level()
	Stage.use(going)
	Progress.save_game()
	if going != null:
		get_tree().change_scene_to_file(going.scene_path)
