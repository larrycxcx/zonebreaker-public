class_name EnemyBrute
extends EnemyHammer
## 3-D 壮汉：**正面扛伤害**的近战。胸甲和两块护肩都在身前，所以**从正面打伤害减半**，
## 从背后打是全额。
##
## 它**不冲锋**（场景里把 `charge_speed` 设成和 `move_speed` 一样）：就是一堵慢慢压过来的墙，
## 走位全在玩家手上。打法有三条：绕到它背后、跳过去、或者**把手雷扔过它头顶**
## ——手雷是抛物线，越过它落在身后，那一下就是全额。
##
## 「走近了抡一下」整套都是 `EnemyHammer` 的（巡逻、转向、起手、伤害卡在砸到底那一帧），
## 这里只多「正面减伤」这一件事。

@export_group("Armour")
## 从正面挨打时伤害乘这个。1.0 = 没有护甲。
@export_range(0.0, 1.0) var front_armour := 0.5


## 从正面来的伤害减半。**来源不明的不减**（`Vector2.INF`，比如持续伤害、掉出关卡）——
## 护甲挡的是打过来的东西，不是所有伤害。
func take_damage(amount: int, source_position := Vector2.INF, from: Node = null) -> void:
	if is_from_the_front(source_position):
		amount = maxi(1, roundi(amount * front_armour))
	super(amount, source_position, from)


## 这一下是从它面朝的那一边来的吗。
func is_from_the_front(source_position: Vector2) -> bool:
	if source_position == Vector2.INF:
		return false
	var side := signi(source_position.x - global_position.x)
	return side != 0 and side == facing
