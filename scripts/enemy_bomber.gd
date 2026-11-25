class_name EnemyBomber
extends EnemyChaser
## 2-F Alarmobot: a small tracked robot that sounds an alarm when it spots the player, charges in and **blows itself up** up close.
##
## The charging part is all D (chasing, climbing walls, jumping off ledges, remembering where it last saw you); this only adds two things:
## it charges faster than D, and once it is right next to you it lights its fuse and blows itself up.
##
## **Once lit, it stops moving**: if it kept chasing you could never get away; the fraction of a second on the fuse is the player's window to run.
## When the fuse runs out it blows up anyway — if the player got away it wastes itself, as they deserve. The explosion is drawn by `Fx` from the `explosion` event,
## sized by `blast_radius` (the same as grenades and the ultimate).

@export_group("Self destruct")
## The layer it blows up (players are layer 2). Same meaning as a grenade's `target_layer`.
@export_flags_2d_physics var target_layer := 2
## It lights the fuse when the player comes within this distance (straight line).
@export var fuse_range := 36.0
## Time from lighting the fuse to the explosion.
@export var fuse_time := 0.6
## **The explosion is exactly the grenade's** (`Blast`): `blast_max_damage` at the centre, `blast_min_damage` at the edge, linear in between,
## and nothing gets through solid objects. Same radius as the grenade too — it is "a grenade itself".
## So the way to dodge is **to get away**, not to tank it: the fuse is long enough to leave the radius (the player walks at 180, 108px in 0.6 seconds).
@export var blast_radius := 56.0
@export var blast_max_damage := 126
@export var blast_min_damage := 42

## Whether the fuse is lit, and how long until it blows.
var _lit := false
var _fuse_left := 0.0


func _physics_process(delta: float) -> void:
	if _lit:
		# Once lit it stands still under gravity only — giving the player that fraction of a second to run
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


## Blow up: the same as a grenade (`Blast`), then it is gone.
## **`target_layer` is the player layer**, so it cannot hurt its own side or other enemies.
func _detonate() -> void:
	var at := body_center()
	for victim in Blast.victims(get_world_2d().direct_space_state, at, blast_radius, target_layer):
		var hurt := Blast.damage_at(at.distance_to(victim.global_position),
			blast_radius, blast_max_damage, blast_min_damage)
		victim.take_damage(roundi(hurt * Stage.damage_scale()), at, self)
	GameEvents.report(&"explosion", self)
	die()
