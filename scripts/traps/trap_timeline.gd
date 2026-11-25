class_name TrapTimeline
extends RefCounted
## Timeline for traps (hydraulic press, blast gate): 8 frames, with how long each holds in a table, looping.
##
## **The rules and the picture use the same frame number**: the hit check uses this frame's shape (a table measured from the art), and the look only draws this frame,
## so switching skins (placeholder blocks ↔ art sprites) does not change the rules at all.
## `phase` staggers several side by side — a row of presses slamming down together would just be a wall; staggered, it becomes "time it and dash through the gap".


## Which frame it is at `time` seconds (plus the stagger `phase`).
static func frame_at(time: float, durations: Array[float], phase: float) -> int:
	var total := 0.0
	for d in durations:
		total += d
	var t := fposmod(time + phase, total)
	for i in durations.size():
		if t < durations[i]:
			return i
		t -= durations[i]
	return durations.size() - 1
