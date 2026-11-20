class_name StagedSpriteAppearance
extends Appearance
## 分阶段换图的可破坏物（第五关的毒气罐）：**每打掉一截换一张更破的图**，玩家看得出还差几下。
## 和箱子那套（`CrateSpriteAppearance`，越打越暗、打烂播散架）不一样，这里的素材本身就画了每个破损阶段：
## 完好（几种颜色，按位置固定挑一种）→ 打裂 → 碎一半 → 只剩一圈碎片（打烂之后一直停在这张，碰撞已经撤了）。
## 玩法只调 `show_damage(打到几成, 打烂了没有)`，和别的机关一样不碰贴图。

## 完好时的几种样子（随机挑一种，按节点位置算，换台机器也一样）。
@export var intact: Array[Texture2D] = []
## 打裂、碎一半（按打到几成依次换）。
@export var cracked: Array[Texture2D] = []
## 打烂之后留在地上的碎片。
@export var debris: Texture2D
## 贴图左上角相对节点原点画在哪（素材比判定框宽一点，往左让一半）。
@export var at := Vector2.ZERO
## 挨打时横着抖几像素
const SHAKE := 1.0

var _stage := 0.0
var _broken := false
var _shake := 0.0
var _pick := 0


func _ready() -> void:
	var anchor := global_position
	_pick = absi(int(anchor.x) * 7 + int(anchor.y) * 13) % maxi(1, intact.size())


func show_damage(stage: float, broken: bool) -> void:
	if stage > _stage:
		_shake = 0.12
	_stage = stage
	_broken = broken
	queue_redraw()


func _process(delta: float) -> void:
	if _shake > 0.0:
		_shake -= delta
		position.x = SHAKE if int(_shake * 60.0) % 2 == 0 and _shake > 0.0 else 0.0


## 现在画哪张：0..1 的破损程度均分给「完好 + 每一张裂的」，打烂了是碎片。
func current() -> Texture2D:
	if _broken:
		return debris
	var steps := 1 + cracked.size()
	var step := mini(int(_stage * steps), steps - 1)
	if step == 0:
		return intact[_pick] if not intact.is_empty() else null
	return cracked[step - 1]


func _draw() -> void:
	var texture := current()
	if texture != null:
		draw_texture(texture, at)
