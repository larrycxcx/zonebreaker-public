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
## 炸谁那一层（玩家是第 2 层）。和手雷的 `target_layer` 一个意思。
@export_flags_2d_physics var target_layer := 2
## 玩家进到这个距离（直线）就点火。
@export var fuse_range := 36.0
## 点火到爆炸隔多久。
@export var fuse_time := 0.6
## **爆炸和手雷完全是同一套**（`Blast`）：中心 `blast_max_damage`、边缘 `blast_min_damage` 线性衰减，
## 中间被实心物体挡住就炸不到。半径也和手雷一样——它本来就是「自己当一颗手雷」。
## 所以躲的办法是**离远点**，不是硬扛：引信那零点几秒足够跑出半径（玩家走路 180，0.6 秒 108px）。
@export var blast_radius := 56.0
@export var blast_max_damage := 126
@export var blast_min_damage := 42

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


## 炸：和手雷走同一套（`Blast`），然后自己没了。
## **`target_layer` 是玩家那一层**，所以炸不到自己人、也炸不到别的敌人。
func _detonate() -> void:
	var at := body_center()
	for victim in Blast.victims(get_world_2d().direct_space_state, at, blast_radius, target_layer):
		var hurt := Blast.damage_at(at.distance_to(victim.global_position),
			blast_radius, blast_max_damage, blast_min_damage)
		victim.take_damage(roundi(hurt * Stage.damage_scale()), at, self)
	GameEvents.report(&"explosion", self)
	die()
