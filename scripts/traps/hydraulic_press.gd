class_name HydraulicPress
extends Node2D
## 第二关的机关「液压机」：从天花板吊下来的活塞，**砸下来就压到地面**，碰到扣血。
##
## 节点原点是这一帧画面（32×64）的左上角，摆的时候让底边落在地面上。
## **收着的时候锤头底边在第 31 行**，底下正好留出 32 像素——站着的人走得过去；
## 砸下来锤头到第 63 行，整条压到底，**趴下也躲不掉**。躲法只有一个：看准它收上去的空当冲过去。
## 一排几台错开节奏（`phase`），所以那个空当是一台接一台地开。
##
## 判定只看这一帧锤头和杆子占了哪儿（`HEAD`，按 `Hammer.png` 每一帧量出来的），
## 和外观无关：默认皮肤画色块、素材包画贴图，规则一样。**没有碰撞体**——它不挡人也不挡子弹，只是碰不得。
## 只伤玩家（敌人路过不管它）。

@export var skin_key := &"trap_press"
## 错开几秒（同一排的几台填不同的数）。
@export var phase := 0.0
@export var damage := 50
## 活塞杆从哪儿吊下来（世界坐标的 y）：天花板的底边。外观按它把杆子往上接，规则用不到。
@export var mount_y := 0.0
## 每一帧停多久：收着歇一会儿 → 很快砸下去 → 压着停一下 → 慢慢收回来。
@export var durations: Array[float] = [1.2, 0.05, 0.05, 0.1, 0.12, 0.12, 0.12, 0.12]

const SIZE := Vector2(32, 64)
## 每一帧锤头的上沿、下沿（帧内的行号）。量自 `Hammer.png`。
const HEAD := [Vector2i(10, 31), Vector2i(27, 53), Vector2i(44, 63), Vector2i(40, 62),
	Vector2i(42, 63), Vector2i(32, 53), Vector2i(22, 43), Vector2i(12, 33)]
## 杆子的左右（帧内的列）。锤头是满宽 32。
const ROD := Vector2i(7, 24)
## 判定比画面让 2 像素：收回去最后那一帧锤头底边在第 33 行，正好擦着站着的人的头顶——
## 画面上看是「已经收回去了」，这时候挨一下会觉得冤。
const GRACE := 2

var frame := 0
var _time := 0.0
var _visual: Node


func _ready() -> void:
	_visual = Skins.build_appearance(self, skin_key)
	if _visual != null and _visual.has_method(&"set_mount"):
		_visual.call(&"set_mount", mount_y - global_position.y)
	_show()


func _physics_process(delta: float) -> void:
	_time += delta
	var now := TrapTimeline.frame_at(_time, durations, phase)
	if now != frame:
		frame = now
		_show()
	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Player
		if player == null or not player.is_alive():
			continue
		if hits(player.hit_box()):
			player.take_damage(roundi(damage * Stage.damage_scale()), head_center(), self)


## 这一帧锤头和杆子占了哪些地方（世界坐标）。
func danger_rects() -> Array[Rect2]:
	var head: Vector2i = HEAD[frame]
	var bottom := float(head.y + 1 - GRACE)
	var out: Array[Rect2] = []
	out.append(Rect2(global_position + Vector2(ROD.x, 0.0), Vector2(ROD.y - ROD.x + 1, head.x)))
	out.append(Rect2(global_position + Vector2(0.0, head.x), Vector2(SIZE.x, bottom - head.x)))
	return out


func hits(box: Rect2) -> bool:
	for rect in danger_rects():
		if rect.intersects(box):
			return true
	return false


func head_center() -> Vector2:
	var head: Vector2i = HEAD[frame]
	return global_position + Vector2(SIZE.x / 2.0, (head.x + head.y) / 2.0)


## 锤头底边离地面还有多高（测试用：收着的时候站着的人过得去）。
func clearance() -> float:
	return SIZE.y - float(HEAD[frame].y + 1 - GRACE)


## 占位色块画什么（世界坐标转成本地）。
func art_rects(at_frame: int) -> Array[Rect2]:
	var keep := frame
	frame = at_frame
	var out: Array[Rect2] = []
	for rect in danger_rects():
		out.append(Rect2(rect.position - global_position, rect.size))
	frame = keep
	return out


func _show() -> void:
	if _visual != null and _visual.has_method(&"show_frame"):
		_visual.call(&"show_frame", frame)
