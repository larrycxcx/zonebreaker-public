class_name EnemyBomber
extends EnemyChaser
## 2-F Alarmobot：小履带机器人，发现玩家就拉响警报冲过来，贴身**自爆**。
##
## 冲的那一段全是 D 那套（追击、翻墙、跳崖、记住最后看见的位置），这里只多两件事：
## 冲得比 D 快，以及贴到跟前之后点火、炸掉自己。
##
## **点火之后就停住不动了**：一直贴着追的话玩家根本躲不掉，站定引信那零点几秒就是留给玩家跑开的。
## 引信走完照常爆——人跑开了就白炸一下，这是玩家应得的。爆炸的画面由 `Fx` 按 `explosion` 事件画，
## 大小取 `blast_radius`（和手雷、终极武器同一套）。

@export_group("Self destruct")
## 玩家进到这个距离（直线）就点火。
@export var fuse_range := 36.0
## 点火到爆炸隔多久。
@export var fuse_time := 0.6
## 爆炸半径和伤害。**中心到玩家之间被实心物体挡住就不受伤**，和手雷同一条规则。
@export var blast_radius := 48.0
@export var blast_damage := 60

## 点火了没有，以及还剩多久炸。
var _lit := false
var _fuse_left := 0.0


func _physics_process(delta: float) -> void:
	if _lit:
		# 点火之后站着不动，只受重力——给玩家留出跑开的那零点几秒
		velocity.x = 0.0
		_apply_gravity(delta)
		move_and_slide()
		_fuse_left -= delta
		if _fuse_left <= 0.0:
			_detonate()
		return
	super(delta)
	if _close_enough():
		_light_the_fuse()


func is_lit() -> bool:
	return _lit


func _close_enough() -> bool:
	for player in players_by_distance():
		if player.global_position.distance_to(global_position) <= fuse_range:
			return true
	return false


func _light_the_fuse() -> void:
	_lit = true
	_fuse_left = fuse_time
	_visual.fire()


## 炸：范围内、且中间没被实心物体挡住的玩家挨打，然后自己没了。
func _detonate() -> void:
	var at := body_center()
	var space := get_world_2d().direct_space_state
	for player in players_by_distance():
		var to := player.body_center()
		if at.distance_to(to) > blast_radius or not Sight.is_clear(space, at, to):
			continue
		player.take_damage(roundi(blast_damage * Stage.damage_scale()), at, self)
	GameEvents.report(&"explosion", self)
	die()
