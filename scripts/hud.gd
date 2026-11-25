extends CanvasLayer
## HUD: health bar, stamina bar, current weapon, ultimate charges left, level / XP / money in the top left, with a message on death;
## when a boss appears its portrait and health bar show at the top right (the bar shrinks right to left and hides when the boss dies).
##
## This only decides "what to show". The scene comes with placeholder blocks; when the current skin pack has a HUD appearance (`SkinPack.hud`, e.g. SpriteHud),
## the same state is handed to the appearance to draw, and the placeholder blocks keep updating (tests and logic read them) but are no longer drawn — the same idea as character skins.

## Parts shared by both players and shown only by the left HUD (only the boss bar now). The right HUD neither shows nor moves them.
## **"GAME OVER" is not here**: that line belongs to `DeathScreen`; see the note there.
const SHARED_PARTS := ["BossBar"]

const STAMINA_READY := Color(0.45, 0.85, 0.4)
## The bar changes colour when stamina is below the threshold for running again, telling the player they cannot run right now.
const STAMINA_TIRED := Color(0.85, 0.5, 0.25)

var _ultimate_pips: Array[ColorRect] = []
## Which player this HUD shows (one on each side in co-op).
@export var player_index := 0
## Placed on the right side of the screen (player 2's): the scene is drawn for the left, and every part is mirrored horizontally here.
@export var mirrored := false
## Show the parts shared by both players (boss bar, death message). In co-op only the left HUD shows them, otherwise the two would overlap.
@export var shows_shared := true

var _player: Player
## The boss currently shown at the top right.
var _boss: Boss
## The skin pack's HUD appearance; null if there is none, then only the placeholder blocks are used.
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
	# Read the current values directly instead of relying on the order of the emit in Player._ready.
	_on_health_changed(player.health, player.max_health)
	_on_stamina_changed(player.stamina, player.max_stamina)
	_on_weapon_switched(player.current_weapon, player.current_slot().weapon)
	if player.ultimate_weapon != null:
		_on_ultimate_changed(player.ultimate_ammo(), player.ultimate_weapon.max_ammo)


## HUD text uses the same bitmap font as the menus (`UiKit`), not Godot's built-in one.
## The font cannot be set in the scene — the `.fnt` has to be loaded as a FontFile, and when UI art moves into `SkinPack` only one line changes here.
func _use_pixel_font() -> void:
	_progress_label.add_theme_font_override("font", UiKit.font())
	# The sky in the stages is quite bright and white text blurs into it; gold also matches the other HUD parts
	_progress_label.add_theme_color_override("font_color", UiKit.GOLD)
	_progress_label.add_theme_font_size_override("font_size", UiKit.TEXT_SIZE)
	# A dark shadow behind the text: HUD text sits right on top of the level, and against a bright sky the strokes blur together.
	# A bitmap font cannot be outlined (the engine's outline needs outline data in the glyphs); the shadow draws the same image again, which works.
	_progress_label.add_theme_color_override("font_shadow_color", Color(0.04, 0.05, 0.11, 0.95))
	_progress_label.add_theme_constant_override("shadow_offset_x", 1)
	_progress_label.add_theme_constant_override("shadow_offset_y", 1)


## If the skin pack has a HUD appearance, install it and make the placeholder blocks transparent (not drawn, but still updated).
func _add_look() -> void:
	var scene := Skins.hud()
	if scene == null:
		return
	_look = scene.instantiate()
	_look.name = "Look"
	add_child(_look)
	for placeholder: CanvasItem in [_health_bar, _stamina_bar, _weapon_icon, _ultimate_row, _boss_bar]:
		placeholder.modulate.a = 0.0


## Move this whole HUD to the other side of the screen (player 2's).
## **Move it as one piece, do not mirror the parts one by one**: in the pack's HUD appearance (SpriteHud) the health and stamina bars are drawn by script from coordinates, not nodes;
## mirroring them one by one would make `hud.gd` know how the appearance lays itself out — that is the appearance's business. Moving it as a whole needs none of that, just its root node.
## How far to move is up to the scene: as far from the right edge as the left HUD is from the left edge.
## The shared parts (boss bar, death message) do not move; they belong to the left HUD.
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
	# That line of text (level / XP / money) is much wider than anything else, so it is pinned to the right on its own and right-aligned
	var label_width := _progress_label.offset_right - _progress_label.offset_left
	_progress_label.offset_right = width - margin
	_progress_label.offset_left = _progress_label.offset_right - label_width
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ultimate_row.alignment = BoxContainer.ALIGNMENT_END


## The parts that move along: the top-level controls of this scene except the shared parts and that line of text (which is placed separately).
## **The pack's appearance (`Look`) must be excluded as well**: it is moved once on its own a few lines below; left in here it would be moved twice
## and fly right off the screen — in co-op player 2's whole HUD was invisible because of this (found in playtesting; the old test only asserted
## "200px to the right of the left HUD", and ending up at 1016 still passed).
func _movable() -> Array[Control]:
	var found: Array[Control] = []
	for child in get_children():
		var control := child as Control
		if control == null or control == _progress_label or control == _look:
			continue
		if not SHARED_PARTS.has(String(control.name)):
			found.append(control)
	return found


## The status line (2026-11, stage 5 poison): under the two progress lines, green text saying what you are afflicted with.
## Its position copies the progress line (the right HUD in co-op is pinned right and right-aligned too), so it is placed after `_mirror()`.
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


## The status line (for tests).
func status_label() -> Label:
	return _status_label


## The skin pack's HUD appearance (for tests), null if there is none.
func look() -> Node:
	return _look


## Health is shown as a proportion (RPG-style health of a hundred-odd points, no longer one cell per point).
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


## Remaining charges in the weapon's own colour, used ones darkened.
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


## Only one boss is shown at a time: one that appears later replaces the earlier one.
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


## The bar sits right next to the portrait and shrinks right to left, so the fill is pinned to the right.
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


## Level and money on one line, XP and unspent skill points on another.
## **Two lines because of width**: squeezed into one it is up to 414px wide, and in co-op the two HUDs would collide in the middle of the screen;
## on two lines it is at most 289px at level 20, which fits in each half (308px)
## (`test_menus.gd` measures it with the font's real glyph widths).
## Further up the XP curve (×1.5 per level) the numbers grow to seven digits and the line no longer fits —
## that is a balance matter, to be adjusted together if anyone really gets that high; do not truncate the text here.
## **Always English upper case**: the menus and the HUD follow the same rule (the pack's font has no Chinese glyphs, see CLAUDE.md).
func _on_progress_changed() -> void:
	var me := Progress.of(player_index)
	# At max level XP no longer accumulates (`xp_to_next` returns 0); `XP 0/0` would look like a bug
	var second := "XP MAX" if me.is_max_level() else "XP %s/%s" % [
		UiKit.number(me.xp), UiKit.number(me.balance.xp_to_next(me.level))]
	if me.points > 0:
		second += "  +%d PTS" % me.points
	_progress_label.text = "LV %d  CASH %s\n%s" % [me.level, UiKit.number(me.money), second]
