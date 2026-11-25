class_name Stage
extends RefCounted
## "Which stage is being played" — enemies scale their strength by it, rewards scale by it.
##
## The 23 stages use **the same enemies**, with one set of multipliers per stage setting the difficulty (the three scales in `LevelInfo`),
## instead of a new set of enemy scenes per stage. That makes difficulty DLC cheap too: the same scenes with another set of `LevelInfo` multipliers.
##
## **A static variable, not an autoload**: it is only data, with no signals and nothing in the scene tree.
## Set by `MainMenu` (or tests) before a stage loads; unset means null and every multiplier is 1 —
## which is what the test level (`main.tscn`) runs at, so none of the old tests had to change.

## The stage being played. null = not set (the test level, or loading a scene directly while debugging).
static var current: LevelInfo


## Switch stage (call **before the stage loads**). If the stage has a skin pack, switch to it too:
## tiles, backdrop, music and enemy sprites all come from the pack, and enemies and platforms ask the pack for their look in their own `_ready`,
## so it has to be switched before the scene is instantiated. Without a pack nothing changes (the one from the project settings stays).
static func use(level: LevelInfo) -> void:
	current = level
	if level != null and level.skin != null:
		Skins.use(level.skin)


## Back to "no stage": every multiplier is 1.
static func clear() -> void:
	current = null


static func health_scale() -> float:
	return current.enemy_health_scale if current != null else 1.0


static func damage_scale() -> float:
	return current.enemy_damage_scale if current != null else 1.0


static func reward_scale() -> float:
	return current.reward_scale if current != null else 1.0
