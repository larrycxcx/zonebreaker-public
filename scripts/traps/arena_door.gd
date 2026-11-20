class_name ArenaDoor
extends StaticBody2D
## 第五关**小 Boss 房间的门**（2026-11 和用户定的：变异枪手在一间封住的房间里，打死它前面的门才开）。
## 节点原点是门的左上角，32×64（地图里 2×4 格，`[` 入口、`]` 出口），底边落在地板上；
## 门上面得是实心的一直到天花板（和闸门一样，格子地图自检查这条），不然跳过去了。
##
## - **入口门**（`exit_door` 关着）：一开始开着。房间里的小 Boss 出场了、**所有活着的玩家都已经进了门**
##   （在门的右边）就关上——人进去了才关，不会把人关在门里或者关在外面。
## - **出口门**（`exit_door` 开着）：一开始关着，**小 Boss 死了才开**。入口门也同时打开。
## 关着是墙（world 层：挡人、挡敌人、挡子弹），开着碰撞体关掉。开关门用 `move_time` 秒往天花板里缩 / 放下来，
## 规则只看「开没开」：放下来那一刻就是墙（有人站在门下面的话先把他推到房间里那一边）。
## 「哪个是这个房间的小 Boss」：`ends_level` 关着的 Boss，出场时报 `GameEvents.boss_appeared`。

@export var skin_key := &"arena_door"
@export var exit_door := false
@export var move_time := 0.4

const SIZE := Vector2(32, 64)

var is_open := true
var _ratio := 1.0
var _boss: Boss
var _visual: Node

@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_visual = Skins.build_appearance(self, skin_key)
	is_open = not exit_door
	_ratio = 1.0 if is_open else 0.0
	# 一开始就关着的（出口门）不用推人：这时候玩家节点还没准备好，也不会有人站在门下面
	_apply(false)
	GameEvents.boss_appeared.connect(_on_boss_appeared)


func _on_boss_appeared(boss: Node) -> void:
	var it := boss as Boss
	if it == null or it.ends_level or _boss != null:
		return
	_boss = it
	it.died.connect(_on_boss_died)


func _on_boss_died() -> void:
	set_open(true)


func _physics_process(delta: float) -> void:
	if not exit_door and is_open and _boss != null and is_instance_valid(_boss) and _boss.health > 0 \
			and _everyone_inside():
		set_open(false)
	var want := 1.0 if is_open else 0.0
	if not is_equal_approx(_ratio, want):
		_ratio = move_toward(_ratio, want, delta / move_time)
		_show()


## 所有活着的玩家都在门的右边（整个人过了门）。
func _everyone_inside() -> bool:
	var any := false
	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Player
		if player == null or not player.is_alive():
			continue
		any = true
		if player.hit_box().position.x < global_position.x + SIZE.x:
			return false
	return any


func set_open(open: bool) -> void:
	if open == is_open:
		return
	is_open = open
	_apply(true)


func box() -> Rect2:
	return Rect2(global_position, SIZE)


func _apply(push: bool) -> void:
	_shape.set_deferred(&"disabled", is_open)
	if not is_open and push:
		# 门放下来那一刻还站在门下面的：推到房间里那一边（入口门的右边、出口门的左边）
		for node in get_tree().get_nodes_in_group(&"player"):
			var player := node as Player
			if player != null and player.hit_box().intersects(box()):
				var half := player.hit_box().size.x / 2.0
				player.global_position.x = global_position.x + SIZE.x + half + 1.0 if not exit_door \
					else global_position.x - half - 1.0
	_show()


func _show() -> void:
	if _visual != null and _visual.has_method(&"show_open"):
		_visual.call(&"show_open", _ratio)


func open_ratio() -> float:
	return _ratio
