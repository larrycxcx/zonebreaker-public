class_name EnemyDropper
extends EnemyChaser
## 2-A Worker：吊在屏幕上方不动，玩家走到下面就松手落下来，**落地之后就是一个普通的冲撞兵**（D 那套）。
##
## 关卡里把它摆在画面顶边以上（y < 0），玩家一路走过来什么也看不见，
## 走到它下面那一刻它砸下来——这是这一关的「伏击」。
## 掉下来那一下**不算追击**（还在空中，外观播空中那一帧）；落地之后基类接管，和 D 一模一样。
##
## 松手之前它完全不动：不受重力、不巡逻、不追击。但**打得中**——
## 玩家如果发现了它，抢先打掉是应该允许的（和 Boss 待机时被打中就出场是同一条道理）。

@export_group("Drop")
## 玩家的水平距离进到这里面就松手。默认比半个屏幕窄，所以是走到脚下才掉。
@export var drop_range := 120.0
## 被打中就直接松手（不然玩家只能站在原地打一个永远不还手的靶子）。
@export var drops_when_hit := true

## 松手了没有。松过就再也回不去。
var has_dropped := false


func _physics_process(delta: float) -> void:
	if not has_dropped:
		# 完全不动：连重力都不给，否则它会自己飘下来
		velocity = Vector2.ZERO
		if _someone_walked_under():
			has_dropped = true
		return
	super(delta)


func take_damage(amount: int, source_position := Vector2.INF, from: Node = null) -> void:
	if drops_when_hit:
		has_dropped = true
	super(amount, source_position, from)


func _someone_walked_under() -> bool:
	for player in players_by_distance():
		if absf(player.global_position.x - global_position.x) <= drop_range:
			return true
	return false
