class_name ExplosiveBarrel
extends StaticBody2D
## 油桶（2026-10 用户要的机关）：摆在敌人旁边，**开枪打中就炸**，炸到附近的敌人——**也炸到玩家自己**。
##
## - 挂在 **enemy 层**（不挡路：玩家和敌人的 mask 里都没有这一层），所以**玩家的子弹和手雷打得到它，
##   敌人的子弹打不到**——不会被敌人自己打爆。玩家的 Hurtbox 只认 `Enemy`，碰到它不扣血。
## - 一枪就炸。爆炸用手雷那一套（`Blast`：半径内、中间没被实心挡住的才炸得到，中心 `max_damage`
##   往边缘线性降到 `min_damage`），**敌人和玩家都炸**——引爆时得离远点。画面由 `Fx` 按 `explosion` 事件画。
## - 旁边的油桶也在 enemy 层上，会被一起炸到——**能连锁**。
## - 炸死的敌人记在**开枪的那个玩家**头上（`take_damage` 的第三个参数一路传下去）。
## 节点原点在**桶身正中**（和敌人一样：`Blast` 按原点量距离、看视线，原点贴着地面的话射线会擦着地板被挡掉）。

@export var skin_key := &"trap_barrel"
@export var blast_radius := 56.0
@export var max_damage := 80
@export var min_damage := 30

## 判定框按贴图里桶身那一块（18×22，上面 4 行是空的）
const SIZE := Vector2(18, 22)
const ENEMY_LAYER := 8
const PLAYER_LAYER := 2

var exploded := false
var _shooter: Node = null


func _ready() -> void:
	collision_layer = ENEMY_LAYER
	collision_mask = 0
	Skins.build_appearance(self, skin_key)


func take_damage(_amount: int, _source_position := Vector2.INF, from: Node = null) -> void:
	if exploded:
		return
	exploded = true
	_shooter = from
	# 炸开那一下就别再挡子弹了（同一帧后面的子弹穿过去，不会撞在一个已经没了的桶上）
	collision_layer = 0
	# 物理回调里不能再查形状（`Blast.victims` 要查），挪到这一帧末尾
	_explode.call_deferred()


func body_center() -> Vector2:
	return global_position


func _explode() -> void:
	var at := body_center()
	GameEvents.report(&"explosion", self)
	var space := get_world_2d().direct_space_state
	for victim in Blast.victims(space, at, blast_radius, ENEMY_LAYER | PLAYER_LAYER):
		if victim == self:
			continue
		var hurt := Blast.damage_at(at.distance_to(victim.global_position), blast_radius, max_damage, min_damage)
		# 链式：别的油桶也是 take_damage，传的还是开枪的那个人
		victim.take_damage(roundi(hurt * Stage.damage_scale()), at, _shooter if _shooter != null else self)
	queue_free()


## 占位外观（`TrapBlocks`）画的形状：一个红桶。
func art_rects(_frame: int) -> Array[Rect2]:
	return [Rect2(-SIZE / 2.0, SIZE)]
