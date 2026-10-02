class_name SkullMinion
extends Enemy
## 地下室 Boss 召唤出来的小骷髅：**慢慢飞向玩家**，碰到扣血（接触伤害走玩家 Hurtbox 那一套），两枪打掉。
##
## 比玩家走路慢得多（`speed` 60 对 180）：它不是来追人的，是来**占地方的**——
## 玩家躲激光要换层，小骷髅飘在哪一层，哪一层就不好待。所以 Boss 那边限着场上最多几个。
## 不受重力、穿过单向平台；被实心的东西挡住就贴着滑（`move_and_slide`）。

@export var speed := 60.0

var _bob := 0.0


func _ready() -> void:
	super()
	gravity = 0.0


func _physics_process(delta: float) -> void:
	_bob += delta
	var target := find_target()
	if target != null:
		var to := (target as Player).body_center() - global_position
		velocity = to.normalized() * speed if to.length() > 1.0 else Vector2.ZERO
		var side := signi(to.x)
		if side != 0 and side != facing:
			facing = side
			_apply_visual_facing()
	else:
		velocity = Vector2(0.0, 8.0 * sin(_bob * 4.0))
	move_and_slide()
	_report_motion(target != null)


## 看见就追：在画面里或者够得着就算，不看视线（它是穿墙飘的幽灵骷髅……其实只穿单向平台）。
func can_target(player: Player) -> bool:
	return within_reach(global_position.distance_to(player.global_position))
