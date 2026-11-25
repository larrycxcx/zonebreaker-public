class_name StatusEffect
extends Resource
## A status effect (resource file): poison, burn, paralysis and the like. Data only; timing and damage on a character are handled by `StatusEffects`.
## Adding a new status later = creating another resource like this, no code needed.
##
## How it gets onto a character: a weapon carries it (`Weapon.status`), and the bullets / grenades it fires apply it to whatever they hit;
## enemy bullets work the same way (`status` on the projectile scene).
## Resistance: the gear's `Equipment.resist[id]` (players) or `resist[id]` in the enemy scene, 0..1 —
## **duration × (1 - resistance)**, 1 = fully immune. Damage per tick does not change.

## Status name (resistance tables, the HUD and sounds identify it by this), e.g. &"poison" / &"burn" / &"paralysis".
@export var id := &""
## Duration (seconds).
@export var duration := 3.0
## How often damage is dealt and how much each time (0 = no damage, e.g. paralysis).
## Damage over time **does not go through ordinary hits**: no invincibility frames, no knockback, ignores defence (resistance is the defence against it).
@export var tick_interval := 0.5
@export var tick_damage := 0
## Movement speed multiplier while it is on (1 = no slowdown).
@export_range(0.0, 1.0) var move_scale := 1.0
## Whether the character can act (move, fire) while it is on. Paralysis is false.
@export var can_act := true
