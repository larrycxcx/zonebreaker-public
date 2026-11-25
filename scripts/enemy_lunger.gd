class_name EnemyLunger
extends EnemyWalker
## 3-A Knifeman: a kind of patroller that **does not shoot** — when it sees a player straight ahead it **freezes to wind up, then lunges forward to stab**.
##
## Unlike the melee enemies so far:
## - the chargers (D, 2-B) **close in at a steady speed** — walk away and you open a gap;
## - the hammer (2-D) **walks up, stops and swings** — step back after the wind-up and it misses;
## - this one is **a single burst**: the lunge is much faster than the player's walk, so running does not work;
## **the dodge is to jump away during the wind-up** (`lunge_windup` is that window for the player).
##
## Damage goes through the base class contact damage — the lunge hitting you is the stab, nothing extra is added.

## The two phases, winding up and lunging.
enum Dash { NONE, WINDUP, GO, REST }

@export_group("Lunge")
## It starts within this distance straight ahead.
@export var lunge_range := 120.0
## Beyond this height difference it cannot reach (it does not jump).
@export var lunge_height := 32.0
## **How long it freezes to wind up**. This is the player's time to jump away; make it shorter and it becomes undodgeable.
@export var lunge_windup := 0.45
## Lunge speed and duration. Much faster than the player's walk (180) — you cannot outrun it, only jump.
@export var lunge_speed := 300.0
@export var lunge_time := 0.3
## How long it rests after a lunge before trying again.
@export var lunge_rest := 1.2
## Reported when it starts; shares D's "spotted the player" sound (same meaning: it is coming for you).
@export var lunge_event := &"chaser_alert"

var _dash := Dash.NONE
var _left := 0.0


func _physics_process(delta: float) -> void:
	# **No need to handle facing here**: `lunge_target()` only accepts a player straight ahead, so the facing is already right when it starts;
	# after starting it lunges in that direction, and turning is entirely up to the patrol (like other patrollers).
	super(delta)
	_update_dash(delta)


## Lunging right now (asked by tests and the appearance).
func is_dashing() -> bool:
	return _dash == Dash.GO


func is_winding_up() -> bool:
	return _dash == Dash.WINDUP


## Stands still while winding up, full speed while lunging, otherwise patrols as usual.
func walk_speed() -> float:
	return lunge_speed if _dash == Dash.GO else move_speed


func patrolling() -> bool:
	return _dash == Dash.NONE


## It freezes during the wind-up (the base class zeroes the speed on this).
func is_engaged(_target: Node2D) -> bool:
	return _dash == Dash.WINDUP or _dash == Dash.REST


func _update_dash(delta: float) -> void:
	if _dash == Dash.NONE:
		if lunge_target() != null:
			_dash = Dash.WINDUP
			_left = lunge_windup
			GameEvents.report(lunge_event, self)
		return
	_left -= delta
	if _left > 0.0:
		return
	match _dash:
		Dash.WINDUP:
			_dash = Dash.GO
			_left = lunge_time
			_visual.fire()      # The stab
		Dash.GO:
			_dash = Dash.REST
			_left = lunge_rest
		Dash.REST:
			_dash = Dash.NONE


## A player straight ahead, in reach, at about the same height and in sight; otherwise null.
## "In reach" goes through `within_reach`, so it always reacts to a player on screen (see "vision parity" in CLAUDE.md).
func lunge_target() -> Node2D:
	for player in players_by_distance():
		var offset := player.global_position - global_position
		if signi(offset.x) != facing and not is_zero_approx(offset.x):
			continue
		if absf(offset.x) > lunge_range and not is_partly_on_screen():
			continue
		if absf(offset.x) > lunge_range * 2.0 or absf(offset.y) > lunge_height:
			continue
		if has_line_of_sight(player.body_center()):
			return player
	return null
