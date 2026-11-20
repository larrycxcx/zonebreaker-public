class_name SpikeTrap
extends Node2D
## 第五关（实验室）的机关「地刺」：地板上一块薄底座，**按节奏伸出三根刺**，伸着的时候碰到扣血。
##
## 节点原点是这一帧画面（32×32）的左上角。底座（帧里第 28~31 行）**嵌进地板表面那 4 行**，
## 所以摆的时候让帧的底边落在「地板表面 + 4」：刺从地板表面长出来，人照常站在地板上。
## 素材 `Spikes.png` 6 帧：0 刺尖刚冒头、1 全收、2 弹出、3 伸到最高、4 往回收、5 露出一小截。
## **平时停在第 5 帧（露出一小截）**：远远就看得见这儿有地刺（2026-11 用户：「默认时应该看到露出地面的部分」），
## 那一截不到伤人的高度，站上去不扣血。**预警是「先缩回去」**：要扎人之前刺先缩进地面（0 → 1），
## 然后猛地弹出（2）、停在最高（3）、往回收（4）、又露头（5）。「刺突然不见了」就是信号，像蓄力。
## 几块并排的错开节奏（`phase`），空当一块接一块地开——和液压机同一个思路。
##
## 判定只看这一帧刺伸到多高（`TIPS`，按贴图每帧量的），和外观无关。**没有碰撞体**：
## 底座太薄，人照常踩在下面的地板上；刺不挡人不挡子弹，只是碰不得。只伤玩家。

@export var skin_key := &"trap_spikes"
@export var phase := 0.0
@export var damage := 40
## 时间轴：每一步停多久，对应 `ORDER` 里的帧。露头歇得久、缩回去（预警）留够反应时间、伸着停一会儿。
@export var durations: Array[float] = [1.4, 0.08, 0.35, 0.06, 0.5, 0.08]

const SIZE := Vector2(32, 32)
## 时间轴上第几步画素材的第几帧：露头歇着 → 往下缩 → 全缩进去（预警）→ 弹出 → 最高 → 往回收。
const ORDER := [5, 0, 1, 2, 3, 4]
## 歇着的那一帧（露出一小截）和预警那一帧（全缩进去）。
const REST := 5
const WARN := 1
## 每一帧刺尖在第几行（帧内）。冒头（0）、全收（1）、露头（5）都不到伤人的高度。
const TIPS := [27, 28, 13, 12, 17, 22]
## 地板表面在帧里的第几行（刺从这里长出来）。
const SURFACE := 28
## 伸出多高以上才伤人：平时露着的那一截（第 5 帧，6 像素）只是告诉你这儿有刺，踩上去不该扣血。
const HARMFUL := 8
## 刺占的横向范围（帧内的列）：三根刺在 x 4..27。
const SPAN := Vector2i(4, 27)

var frame := REST
var _time := 0.0
var _visual: Node


func _ready() -> void:
	_visual = Skins.build_appearance(self, skin_key)
	_show()


func _physics_process(delta: float) -> void:
	_time += delta
	var now: int = ORDER[TrapTimeline.frame_at(_time, durations, phase)]
	if now != frame:
		frame = now
		_show()
	if not is_armed():
		return
	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Player
		if player == null or not player.is_alive():
			continue
		if danger_rect().intersects(player.hit_box()):
			player.take_damage(roundi(damage * Stage.damage_scale()), danger_rect().get_center(), self)


## 刺伸出地板多高（像素）。
func height() -> float:
	return float(SURFACE - TIPS[frame])


## 这一帧伤不伤人。
func is_armed() -> bool:
	return height() >= HARMFUL


## 刺占的地方（世界坐标）。没伸出来时是一条 0 高的线。
func danger_rect() -> Rect2:
	var top := float(TIPS[frame])
	return Rect2(global_position + Vector2(SPAN.x, top), Vector2(SPAN.y - SPAN.x + 1, SURFACE - top))


## 占位色块画什么：底座一条 + 伸出来的刺。
func art_rects(at_frame: int) -> Array[Rect2]:
	var top := float(TIPS[at_frame])
	return [Rect2(0.0, SURFACE, SIZE.x, SIZE.y - SURFACE),
		Rect2(SPAN.x, top, SPAN.y - SPAN.x + 1, SURFACE - top)]


func _show() -> void:
	if _visual != null and _visual.has_method(&"show_frame"):
		_visual.call(&"show_frame", frame)
