class_name EnemyGrenadier
extends EnemyWalker
## Enemy F: a kind of patroller that **does not shoot, it only throws grenades**.
##
## The grenade rules are exactly the player's (the same `grenade.gd`: bounces once on landing, explodes on the next touch, 1.5 s fuse at most,
## radius 28 with 3 at the centre falling to 1 at the edge, blocked by solid things); the only difference is that it hits players, not enemies
## (`Grenade.target_layer`, so it cannot hurt its own side or itself).
##
## No chasing (patrolling comes from the base class), no jumping, no going prone. The throw is the same as the player throwing straight ahead on flat ground: it lands about 110px ahead.

@export_group("Grenades")
## Leave empty to never throw (then it just walks around).
@export var grenade_scene: PackedScene
## Minimum time between two throws.
@export var throw_interval := 2.5
## It only throws at a player straight ahead within this horizontal distance range: too close and it overshoots, too far and it falls short.
## But while it is on screen it throws however far away you are (the grenade lands halfway, blocking the way) — it cannot ignore a player who can see it.
@export var min_throw_distance := 80.0
@export var max_throw_distance := 300.0
## It does not throw when the player is more than throw_height_above higher or throw_height_below lower (the grenade is thrown level and cannot reach).
@export var throw_height_above := 80.0
@export var throw_height_below := 160.0
## Event reported on a throw; by default it shares the player's grenade sound.
@export var throw_event := &"grenade_throw"

## Default release point: the arc of stage 1 F's bat swing (relative to the body centre, facing right; x flipped when facing left).
const THROW_OFFSET := Vector2(16, -4)

## Where this kind lets go. Stage 3's cannon cart fires from the end of its barrel, not where a bat swings, so each kind sets its own.
@export var throw_offset := THROW_OFFSET

var _throw_timer := 0.0


func _physics_process(delta: float) -> void:
	# Patrolling, turning and contact damage all come from the base class; its bullet_scene is empty, so the base class shooting never fires.
	super(delta)
	_update_throw(delta)


## F does not shoot, so "engaged" means it can throw a grenade: within reach it stands and throws, otherwise it keeps patrolling closer.
func is_engaged(_target: Node2D) -> bool:
	return throw_target() != null


func _update_throw(delta: float) -> void:
	_throw_timer -= delta
	if grenade_scene == null or _throw_timer > 0.0 or throw_target() == null:
		return
	_throw_timer = throw_interval
	_throw()


## A player straight ahead at a suitable distance and height and in sight; otherwise null.
## Like a patroller's shooting it only targets straight ahead; turning is entirely up to the patrol.
func throw_target() -> Node2D:
	for player in players_by_distance():
		if _can_throw_at(player):
			return player
	return null


func _can_throw_at(player: Player) -> bool:
	var offset := player.global_position - global_position
	if signi(offset.x) != facing:
		return false
	var distance := absf(offset.x)
	if distance < min_throw_distance or (distance > max_throw_distance and not is_partly_on_screen()):
		return false
	if offset.y < -throw_height_above or offset.y > throw_height_below:
		return false
	return has_line_of_sight(player.body_center())


func _throw() -> void:
	launch_projectile(grenade_scene, throw_offset, Vector2(facing, 0))
	_visual.fire()
	GameEvents.report(throw_event, self)
