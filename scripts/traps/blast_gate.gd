class_name BlastGate
extends StaticBody2D
## 第二关的机关「闸门」：一扇 64 高的门，**关着是墙、开着能过，关门那一下夹到人就扣血**。
##
## 节点原点是这一帧画面（32×64）的左上角，底边落在地面上；门上面由关卡摆一截通到画面顶的实心墙
## （`level_build.py` 的 `gates`）——门才 64 高、跳一下有 87，不封顶的话直接跳过去，这门就没意义了。
##
## - **关着**（第 0、1、7 帧）：碰撞体打开，挡人、挡敌人、挡子弹（world 层，和墙一样）。
## - **开着**（第 2~6 帧）：碰撞体关掉。开到最大时只剩顶上底下几像素的边，那是画面，不碰人。
## - **关门**（第 6、7 帧）：这时人还在门里就挨一下，并且被推出门外——
##   关上那一刻还在里面的直接挪到最近的一边，**不会卡在墙里**。
## 只伤玩家。节奏错开用 `phase`。

@export var skin_key := &"trap_gate"
@export var phase := 0.0
@export var damage := 50
## 关着歇多久 → 开 → 开着多久 → 关。
@export var durations: Array[float] = [1.6, 0.08, 0.08, 0.08, 1.4, 0.08, 0.08, 0.08]
## 夹到人时往外推多猛。
@export var push := Vector2(220, -160)

const SIZE := Vector2(32, 64)
## 哪几帧是关着的（实心）、哪几帧在关门（夹人）。
const SHUT := [0, 1, 7]
const CLOSING := [6, 7]
## 每一帧门板占了哪几段（帧内的行），量自 `Entry.png`：开的时候上下两半往两头缩。
const PANELS := [[Vector2i(0, 63)], [Vector2i(0, 63)], [Vector2i(0, 25), Vector2i(37, 63)],
	[Vector2i(0, 6), Vector2i(57, 63)], [Vector2i(0, 3), Vector2i(60, 63)],
	[Vector2i(0, 6), Vector2i(57, 63)], [Vector2i(0, 25), Vector2i(37, 63)], [Vector2i(0, 63)]]

var frame := 0
var _time := 0.0
var _visual: Node

@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_visual = Skins.build_appearance(self, skin_key)
	frame = TrapTimeline.frame_at(0.0, durations, phase)
	_apply()


func _physics_process(delta: float) -> void:
	_time += delta
	var now := TrapTimeline.frame_at(_time, durations, phase)
	if now == frame:
		return
	frame = now
	_apply()
	if frame in CLOSING:
		_squeeze()


func is_shut() -> bool:
	return frame in SHUT


## 门所在的那一条（世界坐标）。
func column() -> Rect2:
	return Rect2(global_position, SIZE)


func _apply() -> void:
	# 改碰撞体要等物理这一步走完（不然在物理回调里改会报错）
	_shape.set_deferred(&"disabled", not is_shut())
	if _visual != null and _visual.has_method(&"show_frame"):
		_visual.call(&"show_frame", frame)


## 门正在合上：还在门里的人挨一下、被推出去。合死那一刻还在里面的直接挪到最近的一边。
func _squeeze() -> void:
	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Player
		if player == null or not (player.is_alive() or player.is_downed()):
			continue
		var box := player.hit_box()
		if not column().intersects(box):
			continue
		var middle := global_position.x + SIZE.x / 2.0
		var side := 1.0 if player.global_position.x >= middle else -1.0
		if player.is_alive():
			player.take_damage(roundi(damage * Stage.damage_scale()), Vector2(middle, box.get_center().y), self)
			player.shove(Vector2(push.x * side, push.y))
		if is_shut():
			var half := box.size.x / 2.0 + 1.0
			player.global_position.x = global_position.x - half if side < 0.0 else global_position.x + SIZE.x + half


## 占位色块画什么（本地坐标）。
func art_rects(at_frame: int) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for span: Vector2i in PANELS[at_frame]:
		out.append(Rect2(0.0, span.x, SIZE.x, span.y - span.x + 1))
	return out
