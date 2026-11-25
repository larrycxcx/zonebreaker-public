class_name SkillsScreen
extends Control
## Skill screen: one column per player present, showing the character name, level, remaining skill points and the four stats; one press adds a point.
##
## In co-op **both columns show at once**, each driven by its own pad (each column only listens to its own player's input).
## Stat values show "what it is now", with a `+how much was added` after the ones with points in them.
## The UI is always English upper case (the pack's font has no Chinese glyphs, see CLAUDE.md).

## Both players pressed back (or the single player did).
signal closed

const COLUMN_WIDTH := 300.0
const ROW_HEIGHT := 26.0
## How stat names are written in the UI.
const STAT_LABELS := {&"life": "LIFE", &"attack": "ATTACK", &"defense": "DEFENSE", &"speed": "SPEED"}

var _columns: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Lay out a column for each of these players.
func build(players: Array[Player]) -> void:
	for child in get_children():
		child.queue_free()
	_columns.clear()
	var screen := size if size.x > 0.0 else Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 640),
		ProjectSettings.get_setting("display/window/size/viewport_height", 360))
	var gap := 16.0
	var total := COLUMN_WIDTH * players.size() + gap * (players.size() - 1)
	var left := (screen.x - total) / 2.0
	for i in players.size():
		_columns.append(_build_column(players[i], Vector2(left + i * (COLUMN_WIDTH + gap), 40.0)))
	add_child(UiKit.label("A SPEND    B BACK", Rect2(0, screen.y - 36.0, screen.x, 20.0),
		UiKit.DIM, UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_CENTER))


func _build_column(who: Player, at: Vector2) -> Dictionary:
	var stats: Array[StringName] = Balance.STATS
	var height := 76.0 + ROW_HEIGHT * stats.size() + 28.0
	add_child(UiKit.window(Rect2(at, Vector2(COLUMN_WIDTH, height))))
	var inner := at + Vector2(28.0, 22.0)
	var wide := COLUMN_WIDTH - 56.0
	add_child(UiKit.label(who.progress.character_name, Rect2(inner, Vector2(wide, 22.0)),
		UiKit.CYAN, UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_CENTER))
	var head := UiKit.label("", Rect2(inner + Vector2(0, 24.0), Vector2(wide, 20.0)),
		UiKit.GOLD, UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(head)
	var rows := []
	for i in stats.size():
		var top := inner + Vector2(0, 52.0 + i * ROW_HEIGHT)
		var colour: Color = UiKit.STAT_COLORS.get(stats[i], UiKit.WHITE)
		add_child(UiKit.picture("%s/stat_%s.png" % [UiKit.DIR, stats[i]], top + Vector2(12.0, -4.0), colour))
		var name_label := UiKit.label(STAT_LABELS[stats[i]], Rect2(top + Vector2(48.0, 0), Vector2(90.0, 20.0)), UiKit.DIM)
		var value_label := UiKit.label("", Rect2(top + Vector2(130.0, 0), Vector2(60.0, 20.0)),
			colour, UiKit.TEXT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT)
		var bonus_label := UiKit.label("", Rect2(top + Vector2(196.0, 0), Vector2(48.0, 20.0)), UiKit.GOLD)
		for node in [name_label, value_label, bonus_label]:
			add_child(node)
		rows.append({"name": name_label, "value": value_label, "bonus": bonus_label})
	var menu := MenuList.new()
	menu.listens_to = who.player_index
	menu.wide_highlight = true
	add_child(menu)
	menu.build(_blank_rows(stats.size()), wide)
	menu.position = inner + Vector2(-6.0, 52.0)
	menu.chosen.connect(_on_chosen.bind(who))
	menu.cancelled.connect(_on_cancelled.bind(who))
	var column := {"who": who, "head": head, "rows": rows, "menu": menu, "done": false}
	_refresh(column)
	return column


## The menu items themselves show no text (stat names are drawn separately); it is only borrowed to take keys and draw the cursor.
func _blank_rows(count: int) -> Array[String]:
	var rows: Array[String] = []
	for i in count:
		rows.append("")
	return rows


func _on_chosen(row: int, who: Player) -> void:
	if who.progress.spend_point(Balance.STATS[row]):
		for column in _columns:
			if column["who"] == who:
				_refresh(column)


## `MenuList.cancelled` has no argument, so this only takes the player bound in.
func _on_cancelled(who: Player) -> void:
	for column in _columns:
		if column["who"] == who:
			column["done"] = true
	if _columns.all(func(column: Dictionary) -> bool: return column["done"]):
		closed.emit()


func _refresh(column: Dictionary) -> void:
	var progress: PlayerProgress = column["who"].progress
	column["head"].text = "LEVEL %d    POINTS %d" % [progress.level, progress.points]
	column["head"].add_theme_color_override("font_color", UiKit.GOLD if progress.points > 0 else UiKit.DIM)
	for i in Balance.STATS.size():
		var stat: StringName = Balance.STATS[i]
		# The gold column shows **how many points were put in**, not how much the stat grew: each point adds a different amount
		# (life +10, attack +1, defence / speed +5), and writing the real amounts would make players think they pressed different keys.
		var spent: int = progress.allocated.get(stat, 0)
		column["rows"][i]["value"].text = str(roundi(progress.stat(stat)))
		column["rows"][i]["bonus"].text = "+%d" % spent if spent > 0 else ""
