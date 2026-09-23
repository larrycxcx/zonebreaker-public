class_name SkillsScreen
extends Control
## 加点界面：每个在场的玩家一栏，显示角色名、等级、剩余技能点和四个属性，按一下加一点。
##
## 双人时**两栏同时显示**，各按各的手柄（每栏只听自己那个玩家的输入）。
## 属性值显示「现在是多少」，加过点的后面跟一个 `+加了多少`。
## 界面一律英文大写（素材包的字模没有汉字，见 CLAUDE.md）。

## 两个玩家都按了返回（或者单人按了返回）。
signal closed

const COLUMN_WIDTH := 300.0
const ROW_HEIGHT := 26.0
## 属性名在界面上怎么写。
const STAT_LABELS := {&"life": "LIFE", &"attack": "ATTACK", &"defense": "DEFENSE", &"speed": "SPEED"}

var _columns: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 给这几个玩家各摆一栏。
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


## 菜单项本身不显示文字（属性名是单独画的），只借它来收键和画光标。
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


## `MenuList.cancelled` 不带参数，所以这里只收 bind 进来的那个玩家。
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
		# 金色那列写的是**投了几点**，不是属性涨了多少：每点加的量各不相同
		# （生命 +10、攻击 +1、防御速度 +5），照实写出来玩家会以为自己按了不一样的键。
		var spent: int = progress.allocated.get(stat, 0)
		column["rows"][i]["value"].text = str(roundi(progress.stat(stat)))
		column["rows"][i]["bonus"].text = "+%d" % spent if spent > 0 else ""
