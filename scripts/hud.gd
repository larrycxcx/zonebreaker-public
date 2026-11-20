extends CanvasLayer
## HUD：左上角血条、体力条、当前武器、终极武器剩余次数、等级 / 经验 / 金钱，死亡时显示提示；
## Boss 出场时右上角显示它的头像和血条（血条从右往左减少，Boss 死了隐藏）。
##
## 这里只管「显示什么」。场景自带的是占位方块；当前素材包有 HUD 外观（`SkinPack.hud`，比如 SpriteHud）时，
## 同样的状态会转交给外观去画，占位方块照常更新（测试和逻辑都读它们）但不再画出来——和角色换皮肤同一个思路。

## 两个人共用、只由左边那套显示的部分（现在只有 Boss 血条）。右边那套既不显示也不跟着挪。
## **「GAME OVER」不在这儿**：那行字归 `DeathScreen` 写，见那边的说明。
const SHARED_PARTS := ["BossBar"]

const STAMINA_READY := Color(0.45, 0.85, 0.4)
## 体力低于能重新起跑的门槛时变色，提示玩家现在跑不动。
const STAMINA_TIRED := Color(0.85, 0.5, 0.25)

var _ultimate_pips: Array[ColorRect] = []
## 这套 HUD 显示第几号玩家（双人时左右各一套）。
@export var player_index := 0
## 摆在屏幕右边（2 号玩家那套）：场景是按左边画的，这里把每一块横向镜像过去。
@export var mirrored := false
## 显示两个人共用的那些（Boss 血条、死亡提示）。双人时只有左边那套显示，否则两套叠在一起。
@export var shows_shared := true

var _player: Player
## 右上角正在显示的 Boss。
var _boss: Boss
## 素材包的 HUD 外观；没有就是 null，只用占位方块。
var _look: Node

@onready var _health_bar: ColorRect = $HealthBar
@onready var _health_fill: ColorRect = $HealthBar/Fill
@onready var _progress_label: Label = $ProgressLabel
@onready var _stamina_bar: ColorRect = $StaminaBar
@onready var _stamina_fill: ColorRect = $StaminaBar/Fill
@onready var _weapon_icon: ColorRect = $WeaponIcon
@onready var _ultimate_row: HBoxContainer = $UltimateRow
@onready var _boss_bar: Control = $BossBar
@onready var _boss_portrait: TextureRect = $BossBar/Portrait
@onready var _boss_health: ColorRect = $BossBar/Health
@onready var _boss_fill: ColorRect = $BossBar/Health/Fill


func _ready() -> void:
	_boss_bar.hide()
	_use_pixel_font()
	_add_look()
	if mirrored:
		_mirror()
	if shows_shared:
		GameEvents.boss_appeared.connect(_on_boss_appeared)
	Progress.of(player_index).progress_changed.connect(_on_progress_changed)
	_on_progress_changed()
	var player: Player = null
	for node in get_tree().get_nodes_in_group(&"player"):
		if (node as Player).player_index == player_index:
			player = node as Player
	if player == null:
		return
	_player = player
	_add_status_line()
	player.status_changed.connect(_on_status_changed)
	player.health_changed.connect(_on_health_changed)
	player.stamina_changed.connect(_on_stamina_changed)
	player.weapon_switched.connect(_on_weapon_switched)
	player.ultimate_ammo_changed.connect(_on_ultimate_changed)
	# 直接读当前值，不依赖 Player._ready 里那次 emit 的先后顺序。
	_on_health_changed(player.health, player.max_health)
	_on_stamina_changed(player.stamina, player.max_stamina)
	_on_weapon_switched(player.current_weapon, player.current_slot().weapon)
	if player.ultimate_weapon != null:
		_on_ultimate_changed(player.ultimate_ammo(), player.ultimate_weapon.max_ammo)


## HUD 上的字和菜单用同一套位图字体（`UiKit`），不是 Godot 自带那套。
## 字体在场景里设不了——`.fnt` 要当 FontFile 加载，而且以后界面美术进 `SkinPack` 时这里只改一行。
func _use_pixel_font() -> void:
	_progress_label.add_theme_font_override("font", UiKit.font())
	# 关卡里的天空挺亮的，白字糊在上面看不清；金色和别的 HUD 零件也是一路的
	_progress_label.add_theme_color_override("font_color", UiKit.GOLD)
	_progress_label.add_theme_font_size_override("font_size", UiKit.TEXT_SIZE)
	# 背后垫一层暗影：HUD 的字是直接压在关卡画面上的，天空一亮笔画就糊成一团。
	# 位图字体描不了边（引擎的描边要字模自带轮廓数据），影子是把同一张图再画一遍，管用。
	_progress_label.add_theme_color_override("font_shadow_color", Color(0.04, 0.05, 0.11, 0.95))
	_progress_label.add_theme_constant_override("shadow_offset_x", 1)
	_progress_label.add_theme_constant_override("shadow_offset_y", 1)


## 素材包有 HUD 外观就装上，占位方块改成透明（不画，但照常更新）。
func _add_look() -> void:
	var scene := Skins.hud()
	if scene == null:
		return
	_look = scene.instantiate()
	_look.name = "Look"
	add_child(_look)
	for placeholder: CanvasItem in [_health_bar, _stamina_bar, _weapon_icon, _ultimate_row, _boss_bar]:
		placeholder.modulate.a = 0.0


## 把这套 HUD 整体挪到屏幕另一边（2 号玩家那套）。
## **整块一起挪、不逐个镜像**：素材包的 HUD 外观（SpriteHud）里血条、体力条是脚本按坐标画出来的，不是节点，
## 逐个镜像就得让 `hud.gd` 知道人家内部怎么摆——那是外观自己的事。整块挪则不用知道，挪它的根节点就行。
## 挪多远由场景自己说了算：左边那套离屏幕边多远，右边也留多远。
## 共用的那几块（Boss 血条、死亡提示）不挪，它们归左边那套管。
func _mirror() -> void:
	var width := float(ProjectSettings.get_setting("display/window/size/viewport_width", 640))
	var margin := _health_bar.offset_left
	var panel := 0.0
	for control in _movable():
		panel = maxf(panel, control.offset_right)
	var shift := width - margin - panel
	for control in _movable():
		control.offset_left += shift
		control.offset_right += shift
	if _look != null:
		(_look as Control).position.x += shift
	# 那行字（等级 / 经验 / 金钱）比别的宽得多，单独贴着右边、文字靠右
	var label_width := _progress_label.offset_right - _progress_label.offset_left
	_progress_label.offset_right = width - margin
	_progress_label.offset_left = _progress_label.offset_right - label_width
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ultimate_row.alignment = BoxContainer.ALIGNMENT_END


## 跟着挪的那几块：自己场景里除了共用部分和那行字之外的顶层控件（那行字单独安排）。
## **素材包的外观（`Look`）也要排除**：它下面几行单独挪一次，留在这里会被挪两次，
## 直接飞出屏幕——双人时 2 号的 HUD 因此整套都看不见（试玩才发现，老测试只断言了
## 「比左边那套靠右 200px」，飞到 1016 照样算通过）。
func _movable() -> Array[Control]:
	var found: Array[Control] = []
	for child in get_children():
		var control := child as Control
		if control == null or control == _progress_label or control == _look:
			continue
		if not SHARED_PARTS.has(String(control.name)):
			found.append(control)
	return found


## 异常状态那一行（2026-11 第五关的中毒）：进度那两行底下，绿字写着身上挂着什么。
## 位置照抄进度那行（双人右边那套也跟着贴右、靠右对齐），所以它在 `_mirror()` 之后才摆。
const STATUS_NAMES := {&"poison": "POISON"}
var _status_label: Label


func _add_status_line() -> void:
	var top := _progress_label.offset_bottom + 2.0
	_status_label = UiKit.label("", Rect2(_progress_label.offset_left, top,
		_progress_label.offset_right - _progress_label.offset_left, 12.0), UiKit.GREEN)
	_status_label.name = "StatusLabel"
	_status_label.horizontal_alignment = _progress_label.horizontal_alignment
	_status_label.add_theme_color_override("font_shadow_color", Color(0.04, 0.05, 0.11, 0.95))
	_status_label.add_theme_constant_override("shadow_offset_x", 1)
	_status_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_status_label)
	_refresh_status()


func _on_status_changed(_id: StringName, _active: bool) -> void:
	_refresh_status()


func _refresh_status() -> void:
	var names: Array[String] = []
	for id: StringName in STATUS_NAMES:
		if _player != null and _player.statuses.has(id):
			names.append(STATUS_NAMES[id])
	_status_label.text = "  ".join(names)


## 状态那一行（测试用）。
func status_label() -> Label:
	return _status_label


## 素材包的 HUD 外观（测试用），没有返回 null。
func look() -> Node:
	return _look


## 血量按比例显示（RPG 式的数值血量，一百多点，不再一点一格）。
func _on_health_changed(health: int, max_health: int) -> void:
	var ratio := clampf(float(health) / max_health, 0.0, 1.0) if max_health > 0 else 0.0
	_health_fill.size.x = roundf(_health_bar.size.x * ratio)
	if _look != null:
		_look.show_health(health, max_health)


func _on_stamina_changed(stamina: float, max_stamina: float) -> void:
	var ratio := stamina / max_stamina if max_stamina > 0.0 else 0.0
	_stamina_fill.size.x = roundf(_stamina_bar.size.x * ratio)
	_stamina_fill.color = STAMINA_TIRED if _player.is_exhausted() else STAMINA_READY
	if _look != null:
		_look.show_stamina(ratio, _player.is_exhausted())


func _on_weapon_switched(_index: int, weapon: Weapon) -> void:
	_weapon_icon.color = weapon.hud_color
	if _look != null:
		_look.show_weapon(weapon.look)


## 剩余的用武器自己的颜色，用掉的变暗。
func _on_ultimate_changed(ammo: int, max_ammo: int) -> void:
	while _ultimate_pips.size() < max_ammo:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(8, 8)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ultimate_row.add_child(pip)
		_ultimate_pips.append(pip)
	var full: Color = _player.ultimate_weapon.hud_color
	for i in _ultimate_pips.size():
		_ultimate_pips[i].color = full if i < ammo else full.darkened(0.75)
	if _look != null:
		_look.show_ultimate(ammo, max_ammo)


## 同时只显示一个 Boss：后出场的替换先出场的。
func _on_boss_appeared(boss: Node2D) -> void:
	if _boss != null and is_instance_valid(_boss):
		_boss.health_changed.disconnect(_on_boss_health_changed)
		_boss.died.disconnect(_on_boss_died)
	_boss = boss as Boss
	_boss.health_changed.connect(_on_boss_health_changed)
	_boss.died.connect(_on_boss_died)
	_boss_portrait.texture = _boss.hud_portrait()
	_boss_bar.show()
	if _look != null:
		_look.show_boss(_boss.hud_portrait())
	_on_boss_health_changed(_boss.health, _boss.max_health)


## 血条靠右对齐的头像，从右往左减少，所以填充条贴右边。
func _on_boss_health_changed(health: int, max_health: int) -> void:
	var ratio := float(health) / max_health if max_health > 0 else 0.0
	_boss_fill.size.x = roundf(_boss_health.size.x * ratio)
	_boss_fill.position.x = _boss_health.size.x - _boss_fill.size.x
	if _look != null:
		_look.show_boss_health(ratio)


func _on_boss_died() -> void:
	_boss = null
	_boss_bar.hide()
	if _look != null:
		_look.hide_boss()


## 等级、金钱一行，经验和没花的技能点一行。
## **分两行是宽度逼的**：挤成一行最宽要 414px，双人时左右两套会在屏幕中间撞上；
## 分两行之后 20 级时最宽 289px，两套各占半边（308px）还剩得下
## （`test_menus.gd` 按字模的实际字宽量着）。
## 再往上经验曲线（每级 ×1.5）会把数字撑到七位数、这一行就装不下了——
## 那是数值的事，真练得到那么高的时候一起调，别在这儿截字。
## **一律英文大写**：菜单和 HUD 用的是同一套规矩（素材包的字模没有汉字，见 CLAUDE.md）。
func _on_progress_changed() -> void:
	var me := Progress.of(player_index)
	# 满级之后经验不再累计（`xp_to_next` 返回 0），写 `XP 0/0` 会让人以为是 bug
	var second := "XP MAX" if me.is_max_level() else "XP %s/%s" % [
		UiKit.number(me.xp), UiKit.number(me.balance.xp_to_next(me.level))]
	if me.points > 0:
		second += "  +%d PTS" % me.points
	_progress_label.text = "LV %d  CASH %s\n%s" % [me.level, UiKit.number(me.money), second]
