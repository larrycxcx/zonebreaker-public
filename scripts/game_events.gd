extends Node
## Game event bus (the autoload singleton GameEvents).
## Gameplay code only reports "what happened" here (GameEvents.report(&"jump", self)) and does not care how it sounds or looks;
## the sound player Sfx listens to it, and step 3's hit effects and screen shake can hook in here too.
## Event names are listed in SkinPack.SOUND_EVENTS.

signal event_happened(event: StringName, source: Node)
## A boss appeared (entered the screen for the first time). The HUD shows its portrait and health bar from this; a boss may be spawned mid-level, so it goes through the bus.
signal boss_appeared(boss: Node2D)


func report(event: StringName, source: Node = null) -> void:
	event_happened.emit(event, source)
