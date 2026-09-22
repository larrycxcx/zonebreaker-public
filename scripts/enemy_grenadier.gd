class_name EnemyGrenadier
extends EnemyWalker
## 敌人 F：巡逻兵的一种，但**不开枪，只扔手雷**。
##
## 手雷的规则和玩家的完全一样（同一个 `grenade.gd`：落地弹一下、再碰到就炸、1.5 秒保底、
## 半径 28 中心 3 点往边缘降到 1 点、实心物体挡爆炸），区别只有一个——它打玩家、不打敌人
## （`Grenade.target_layer`，所以不会炸到自己人，也不会炸到自己）。
##
## 不追击（巡逻靠基类）、不跳跃、不趴下。扔的姿势就是玩家平地朝正前方扔：落点在前方约 110px。

@export_group("Grenades")
## 留空表示不扔（那样它就只会走来走去）。
@export var grenade_scene: PackedScene
## 两次扔之间至少隔多久。
@export var throw_interval := 2.5
## 玩家在正前方这个水平距离区间内才扔：太近会扔过头，太远够不着。
## 但自己在屏幕里时，再远也扔（手雷会落在半路，当封路用）——玩家看得见它的时候它不能没反应。
@export var min_throw_distance := 80.0
@export var max_throw_distance := 300.0
## 玩家比自己高过 throw_height_above、或低过 throw_height_below 就不扔（手雷是平抛的，够不着）。
@export var throw_height_above := 80.0
@export var throw_height_below := 160.0
## 扔出去时报告的事件名，默认和玩家扔手雷共用一个声音。
@export var throw_event := &"grenade_throw"

## 出手点（相对身体中心，朝右时；朝左 x 取反）。
const THROW_OFFSET := Vector2(16, -4)

var _throw_timer := 0.0


func _physics_process(delta: float) -> void:
	# 巡逻、转身、接触伤害都走基类；它的 bullet_scene 是空的，所以基类那套射击不会开火。
	super(delta)
	_update_throw(delta)


func _update_throw(delta: float) -> void:
	_throw_timer -= delta
	if grenade_scene == null or _throw_timer > 0.0 or throw_target() == null:
		return
	_throw_timer = throw_interval
	_throw()


## 正前方、距离和高度都合适、并且看得见的玩家；否则返回 null。
## 和巡逻兵开枪一样只打正前方，转向完全由巡逻决定。
func throw_target() -> Node2D:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return null
	var offset := player.global_position - global_position
	if signi(offset.x) != facing:
		return null
	var distance := absf(offset.x)
	if distance < min_throw_distance or (distance > max_throw_distance and not is_partly_on_screen()):
		return null
	if offset.y < -throw_height_above or offset.y > throw_height_below:
		return null
	return player if has_line_of_sight(player.body_center()) else null


## 手雷挂在自己的父节点下，这样它死了手雷还会照常飞完、照常爆炸。
func _throw() -> void:
	var grenade := grenade_scene.instantiate() as Node2D
	# launch 要在加入场景树之前调（和玩家的武器槽一样的约定）。
	grenade.call(&"launch", Vector2(facing, 0))
	get_parent().add_child(grenade)
	grenade.global_position = global_position + Vector2(THROW_OFFSET.x * facing, THROW_OFFSET.y)
	_visual.fire()
	GameEvents.report(throw_event, self)
