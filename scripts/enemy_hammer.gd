class_name EnemyHammer
extends EnemyWalker
## 2-D Hammer: a tracked robot, a kind of patroller that **does not shoot** — it walks up and swings a hammer.
##
## Same approach as F's grenades only: patrol, turning and contact damage all come from the base class; `bullet_scene` is empty so the base class shooting never fires,
## and it only handles "stand still and swing when in reach".
##
## **Damage lands on the frame the swing hits bottom** (`HIT_FRAME`), not when the swing starts:
## if the player lost health while the hammer was still raised in the art, they could not read from the motion when to dodge.
## It stands still while swinging, so the way out is to step out of the hammer's reach, or jump over it.

@export_group("Charge")
## When it sees the player it **turns and charges** (a patroller normally only fires straight ahead and never turns back).
## Slower than the player's walk (180), for the same reason as D: walking away outpaces it, so it can only push you to fight while backing off.
@export var charge_speed := 140.0
## It stops chasing beyond this height difference (it only swings on flat ground and cannot climb onto platforms).
@export var charge_height := 48.0

@export_group("Hammer")
## It swings when the player is straight ahead within this horizontal distance.
@export var smash_range := 44.0
## Beyond this height difference it cannot reach (the hammer sweeps sideways).
@export var smash_height := 28.0
## Minimum time between two swings.
@export var smash_interval := 1.8
@export var smash_damage := 42
## Where the hammer head lands (relative to the body centre, facing right; x flipped when facing left).
@export var smash_offset := Vector2(28, 8)
## Players within this radius of the hammer head get hit.
@export var smash_radius := 22.0
@export var smash_event := &"hammer_smash"
## How hard a hit flings the player away (facing right; x flipped when facing left). 0 = no extra fling, just the player's own small knockback.
## The skull-shirt brawler 4-F in the basement relies on this: low damage, but one swing of the arm throws you off the platform —
## in a vertical stage the fall is what really hurts (dropping off the screen costs health and the climb).
@export var smash_knockback := Vector2.ZERO

## The frame on which the swing hits the ground, and how many frames per second one-shot clips run.
## **Must match `EnemySpriteAppearance.ONCE_FPS`**: the moment the hammer hits the ground on screen is the moment the damage lands.
const HIT_FRAME := 5
const SWING_FPS := 12.0
## Time from the start of the swing to the hit (for the default frame).
const HIT_DELAY := HIT_FRAME / SWING_FPS

## The frame on which this kind hits. The default is the hammer man's (`HIT_FRAME`); kinds with different art set their own —
## the basement 4-F's arm reaches furthest on frame 5 (index 4) and is already coming back on frame 6.
@export var hit_frame := HIT_FRAME

## Who it is charging at, null if nobody.
var _hunted: Node2D = null

var _smash_timer := 0.0
## Time left in the swing until it lands; <= 0 means not swinging.
var _swing_left := 0.0


func _physics_process(delta: float) -> void:
	# **It does not switch target or turn while swinging**: if it kept turning to follow you mid-swing, dodging after the wind-up would be pointless
	_hunted = null if is_swinging() else hunt_target()
	if _hunted != null:
		var ahead := signi(_hunted.global_position.x - global_position.x)
		if ahead != 0 and ahead != facing:
			facing = ahead
			_apply_facing()
	super(delta)
	_update_smash(delta)


## How fast it walks this frame: fast while charging, still leisurely while patrolling.
func walk_speed() -> float:
	return charge_speed if _hunted != null else move_speed


## While charging it does not turn around by the patrol rules — at that point it is facing the player.
func patrolling() -> bool:
	return _hunted == null


## Who it is charging at (for tests).
func is_charging() -> bool:
	return _hunted != null


## A player in reach, in sight and at about the same height. **Front or back alike** — it turns around to charge.
## "In reach" uses `within_reach`, so it always reacts to a player on screen (see "vision parity" in CLAUDE.md).
func hunt_target() -> Node2D:
	for player in players_by_distance():
		var offset := player.global_position - global_position
		if not within_reach(absf(offset.x)) or absf(offset.y) > charge_height:
			continue
		if has_line_of_sight(player.body_center()):
			return player
	return null


## Within reach it stands and swings, otherwise it keeps patrolling closer (same idea as F: it has no gun, so the base class "engaged" check does not apply).
func is_engaged(_target: Node2D) -> bool:
	return _swing_left > 0.0 or smash_target() != null


## Time from the start of the swing to the hit.
func hit_delay() -> float:
	return hit_frame / SWING_FPS


func is_swinging() -> bool:
	return _swing_left > 0.0


func _update_smash(delta: float) -> void:
	_smash_timer -= delta
	if _swing_left > 0.0:
		_swing_left -= delta
		if _swing_left <= 0.0:
			_land_the_blow()
		return
	if _smash_timer > 0.0 or smash_target() == null:
		return
	_smash_timer = smash_interval
	_swing_left = hit_delay()
	_visual.fire()
	GameEvents.report(smash_event, self)


## A player straight ahead, in reach and in sight; otherwise null. Like a patroller's shooting, straight ahead only.
func smash_target() -> Node2D:
	for player in players_by_distance():
		var offset := player.global_position - global_position
		if signi(offset.x) != facing and not is_zero_approx(offset.x):
			continue
		if absf(offset.x) > smash_range or absf(offset.y) > smash_height:
			continue
		if has_line_of_sight(player.body_center()):
			return player
	return null


## The hammer lands: only those still standing around the hammer head get hit — dodging after the wind-up works.
func _land_the_blow() -> void:
	var at := smash_point()
	for player in players_by_distance():
		if player.body_center().distance_to(at) <= smash_radius:
			# No fling while invincible: no hit taken, no flying
			var landed := not player.is_invincible()
			player.take_damage(roundi(smash_damage * Stage.damage_scale()), at, self)
			if landed and smash_knockback != Vector2.ZERO:
				player.shove(Vector2(smash_knockback.x * facing, smash_knockback.y))


func smash_point() -> Vector2:
	return body_center() + Vector2(smash_offset.x * facing, smash_offset.y)
