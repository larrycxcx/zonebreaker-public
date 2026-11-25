class_name EnemyDropper
extends EnemyChaser
## 2-A Worker: hangs still above the screen and drops when the player walks underneath; **once landed it is an ordinary charger** (D's behaviour).
##
## The level places it above the top of the view (y < 0), so the player sees nothing on the way in,
## and it crashes down the moment they walk under it — this stage's "ambush".
## The drop itself **is not chasing** (it is still in the air, the appearance shows the air frame); once landed the base class takes over, exactly like D.
##
## Until it lets go it does not move at all: no gravity, no patrol, no chase. But **it can be hit** —
## if the player spots it, shooting it first should be allowed (the same idea as a boss appearing when hit while idle).

@export_group("Drop")
## It lets go when the player's horizontal distance comes within this. By default narrower than half a screen, so it drops only when you are right under it.
@export var drop_range := 120.0
## Getting hit makes it let go at once (otherwise the player could only stand and shoot a target that never fights back).
@export var drops_when_hit := true

## Whether it has let go. Once it has, there is no going back.
var has_dropped := false


func _physics_process(delta: float) -> void:
	if not has_dropped:
		# Completely still: not even gravity, or it would float down by itself
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
