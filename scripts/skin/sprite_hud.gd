class_name SpriteHud
extends Control
## 精灵图版的 HUD 外观。HUD（hud.gd）照常算出血量、体力、武器、终极武器、Boss 血量，
## 素材包里有 HUD 外观就把这些转交给它来画，自己的占位方块只是不画了（测试和逻辑还读它们）。
## 和角色外观一样纯显示：不挡鼠标、没有碰撞，换不换都不影响规则。
##
## 贴图由 `tools/hud_build.py` 生成：血条、体力条都是一排「满的 4 块 + 空的 4 块」（左端、中段、右端、单独一格），
## 按格数拼起来，满到哪里就在哪里把满的那块裁开——血量、体力、Boss 血量都按比例。

## 血条一块多大；体力条一块多大。
const HEALTH_PIECE := Vector2i(32, 14)
const ENERGY_PIECE := Vector2i(16, 5)
## 每排里第几块是空槽（满的是 0~3，空的是 4~7；体力条还有 8~11 是跑不动的橙色）。
const EMPTY := 4
const TIRED := 8

@export var health_strip: Texture2D
@export var energy_strip: Texture2D
## 武器图标：`Weapon.look` → 贴图（直接用玩家手里那把枪的原图）。没有的就不显示。
@export var weapon_icons: Dictionary[StringName, Texture2D] = {}
## 终极武器的图标；留空就画金色小方块（等素材）。
@export var ultimate_icon: Texture2D
@export var ultimate_color := Color(1, 0.8, 0.25)

@export_group("Layout")
@export var health_at := Vector2(12, 12)
@export var health_segments := 3
@export var energy_at := Vector2(12, 30)
@export var energy_segments := 4
@export var ultimate_at := Vector2(58, 48)
@export var ultimate_step := 10.0
## Boss 那条血条摆在哪。**正上方居中，不是右上角**：右上角双人时是 2 号玩家的地盘，
## 摆那儿两套会叠在一起（占位 HUD 早就挪过来了，这套精灵图的忘了跟着挪）。
## 血条 4×32 = 128，加上中间 8px 和 40px 的头像框一共 176，(640 - 176) / 2 = 232。
@export var boss_bar_at := Vector2(232, 25)
@export var boss_segments := 4

## 现在显示的状态（测试读）。
var health := 0
var max_health := 0
var stamina_ratio := 0.0
var tired := false
var weapon_look := &""
var ultimate_ammo := 0
var ultimate_max := 0
var boss_ratio := 0.0

@onready var _weapon: TextureRect = $WeaponSlot/Icon
@onready var _boss_panel: Control = $BossPanel
@onready var _boss_portrait: TextureRect = $BossPanel/Portrait


func _ready() -> void:
	_boss_panel.hide()


func show_health(value: int, maximum: int) -> void:
	health = value
	max_health = maximum
	queue_redraw()


func show_stamina(ratio: float, is_tired: bool) -> void:
	stamina_ratio = clampf(ratio, 0.0, 1.0)
	tired = is_tired
	queue_redraw()


func show_weapon(look: StringName) -> void:
	weapon_look = look
	_weapon.texture = weapon_icons.get(look)


func show_ultimate(ammo: int, maximum: int) -> void:
	ultimate_ammo = ammo
	ultimate_max = maximum
	queue_redraw()


func show_boss(portrait: Texture2D) -> void:
	_boss_portrait.texture = portrait
	_boss_panel.show()
	queue_redraw()


func hide_boss() -> void:
	_boss_panel.hide()
	queue_redraw()


func show_boss_health(ratio: float) -> void:
	boss_ratio = clampf(ratio, 0.0, 1.0)
	queue_redraw()


func boss_visible() -> bool:
	return _boss_panel.visible


## 现在武器槽里显示的图（测试读）。
func weapon_texture() -> Texture2D:
	return _weapon.texture


## 一排 count 块里第 i 块用素材的第几块（满的那套）：左端 0、中段 1、右端 2，只有一块时用两头圆的 3。
static func piece(i: int, count: int) -> int:
	if count == 1:
		return 3
	if i == 0:
		return 0
	return 2 if i == count - 1 else 1


## 一排 count 块、每块 width 宽，[from, to) 这一段是满的：返回每块满的那部分 [块号, 块内起点, 宽]（没有满的块不在里面）。
static func filled(count: int, width: int, from: int, to: int) -> Array:
	var out := []
	for i in count:
		var start := maxi(from - i * width, 0)
		var end := mini(to - i * width, width)
		if end > start:
			out.append([i, start, end - start])
	return out


## 血条满了多少像素。
func health_fill() -> int:
	var ratio := clampf(float(health) / max_health, 0.0, 1.0) if max_health > 0 else 0.0
	return roundi(health_segments * HEALTH_PIECE.x * ratio)


## 体力条满了多少像素；Boss 血条满的那段从哪开始（它贴着右边、从右往左减少）。
func stamina_fill() -> int:
	return roundi(energy_segments * ENERGY_PIECE.x * stamina_ratio)


func boss_fill_from() -> int:
	var length := boss_segments * HEALTH_PIECE.x
	return length - roundi(length * boss_ratio)


func _draw() -> void:
	if health_strip != null and max_health > 0:
		_draw_bar(health_strip, HEALTH_PIECE, health_at, health_segments, 0, health_fill(), 0)
	if energy_strip != null:
		_draw_bar(energy_strip, ENERGY_PIECE, energy_at, energy_segments, 0, stamina_fill(), TIRED if tired else 0)
	for i in ultimate_max:
		var at := ultimate_at + Vector2(i * ultimate_step, 0)
		var shade := Color.WHITE if i < ultimate_ammo else Color(0.35, 0.35, 0.35)
		if ultimate_icon != null:
			draw_texture(ultimate_icon, at, shade)
		else:
			draw_rect(Rect2(at, Vector2(8, 8)), ultimate_color * shade)
	if _boss_panel.visible and health_strip != null:
		_draw_bar(health_strip, HEALTH_PIECE, boss_bar_at, boss_segments, boss_fill_from(), boss_segments * HEALTH_PIECE.x, 0)


## 先铺满空槽，再把 [from, to) 那一段换成满的（full 是满的那套从第几块开始：平时 0，跑不动 TIRED）。
func _draw_bar(strip: Texture2D, size: Vector2i, at: Vector2, count: int, from: int, to: int, full: int) -> void:
	for i in count:
		var p := piece(i, count)
		draw_texture_rect_region(strip, Rect2(at + Vector2(i * size.x, 0), size), Rect2((EMPTY + p) * size.x, 0, size.x, size.y))
	for part in filled(count, size.x, from, to):
		var p := piece(part[0], count)
		draw_texture_rect_region(strip, Rect2(at + Vector2(part[0] * size.x + part[1], 0), Vector2(part[2], size.y)),
			Rect2((full + p) * size.x + part[1], 0, part[2], size.y))
