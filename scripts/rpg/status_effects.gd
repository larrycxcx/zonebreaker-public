class_name StatusEffects
extends RefCounted
## The statuses currently on one character: timing, damage at intervals, removal when time is up. Players and enemies each have one (`statuses`);
## the character calls `tick(delta)` every physics frame, and damage is handed back to the character through the `on_damage` callback (players and enemies lose health differently).
##
## Getting the same status again: **the duration is refreshed** (the longer of the remaining and the new time); damage does not stack.
## The character supplies the resistance before applying it (`apply(effect, resist)`): duration × (1 - resistance), 1 = immune, never applied at all.

## A status was applied / removed (the appearance and HUD hook into this later).
signal changed(id: StringName, active: bool)

## Called on every damage tick: func(amount: int) -> void.
var on_damage: Callable

## id → {effect, left, next_tick}
var _active := {}
## Timing tolerance: summing frame times accumulates floating-point error, and the last tick of "1 second, one tick every 0.25 s" lands exactly at the end; without some slack it would be missed.
const EPSILON := 0.0001


## Apply a status; returns whether it was applied (not when fully immune or the duration is 0).
func apply(effect: StatusEffect, resist := 0.0) -> bool:
	if effect == null or effect.id == &"":
		return false
	var duration := effect.duration * (1.0 - clampf(resist, 0.0, 1.0))
	if duration <= 0.0:
		return false
	var fresh := not _active.has(effect.id)
	if fresh:
		_active[effect.id] = {"effect": effect, "left": duration, "next_tick": effect.tick_interval}
		changed.emit(effect.id, true)
	else:
		_active[effect.id]["left"] = maxf(_active[effect.id]["left"], duration)
	return true


func tick(delta: float) -> void:
	for id: StringName in _active.keys():
		var entry: Dictionary = _active[id]
		var effect: StatusEffect = entry["effect"]
		var left: float = entry["left"] - delta
		if effect.tick_damage > 0 and effect.tick_interval > 0.0:
			var next: float = entry["next_tick"] - delta
			while next <= EPSILON and left > -effect.tick_interval:
				if on_damage.is_valid():
					on_damage.call(effect.tick_damage)
				next += effect.tick_interval
			entry["next_tick"] = next
		entry["left"] = left
		if left <= EPSILON and _active.has(id):
			_active.erase(id)
			changed.emit(id, false)


## Is this status on right now?
func has(id: StringName) -> bool:
	return _active.has(id)


## Time left on this status (0 if it is not on).
func time_left(id: StringName) -> float:
	return _active[id]["left"] if _active.has(id) else 0.0


## All statuses combined: the movement speed multiplier and whether the character can act.
func move_scale() -> float:
	var scale := 1.0
	for entry: Dictionary in _active.values():
		scale *= (entry["effect"] as StatusEffect).move_scale
	return scale


func can_act() -> bool:
	for entry: Dictionary in _active.values():
		if not (entry["effect"] as StatusEffect).can_act:
			return false
	return true


## Remove everything. **Clear first, then emit**: listeners (the HUD's status line) look back with `has()` when they get the signal,
## and the other way round they would still find the status on, so the POISON line never went away (hit while writing the poison tests).
func clear() -> void:
	var ids := _active.keys()
	_active.clear()
	for id: StringName in ids:
		changed.emit(id, false)
