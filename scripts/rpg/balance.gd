class_name Balance
extends Resource
## The progression table (resource file `progression/balance.tres`): starting stats, how much a skill point adds, points per level, XP needed to level up.
## Data only; the run-time level, XP, money, points spent and gear live in `Progress` (autoload). To rebalance edit this file, not the code.
##
## The four stats (the keys are these names):
## - `life`: max health.
## - `attack`: the base of the damage multiplier, **10 = unchanged** (projectile damage × attack / 10), each extra point adds 10% damage.
## - `defense`: damage taken × 100 / (100 + defense), rounded up, at least 1.
## - `speed`: a percentage, **100 = unchanged**. It covers two things: weapon cooldown × 100 / speed (guns and grenades, not the ultimate),
## and sprint stamina use × 100 / speed (speed 150 = you can run half as long again).
##
## **The starting values must make a level 1 player without gear feel exactly as before the rework**: 120 health, 40 per enemy hit (still dead in 3),
## attack 10, speed 100 (damage, cooldowns and sprint length unchanged). The old tests rely on this to keep guarding the feel.

const LIFE := &"life"
const ATTACK := &"attack"
const DEFENSE := &"defense"
const SPEED := &"speed"
## All stats, in the order shown in the HUD / skill screen.
const STATS: Array[StringName] = [LIFE, ATTACK, DEFENSE, SPEED]
## The "unchanged" values of attack and speed.
const ATTACK_BASE := 10.0
const SPEED_BASE := 100.0

## Stats at level 1 without gear.
@export var base: Dictionary[StringName, float] = {LIFE: 120.0, ATTACK: 10.0, DEFENSE: 0.0, SPEED: 100.0}
## How much each skill point adds.
@export var per_point: Dictionary[StringName, float] = {LIFE: 10.0, ATTACK: 1.0, DEFENSE: 5.0, SPEED: 5.0}
## Stat caps (points and gear together never exceed them). **All four need a cap**, otherwise gear bonuses mean nothing —
## defence could stack to 400 (damage divided by 5) and life into the thousands, and the shop could not be priced.
## Maxing all four takes 88 points, but a level 30 character only has 63, so **you have to choose**.
@export var cap: Dictionary[StringName, float] = {
	LIFE: 400.0,      # 28 points
	ATTACK: 30.0,     # 20 points
	DEFENSE: 100.0,   # 20 points (damage halved)
	SPEED: 200.0,     # 20 points (cooldowns halved, sprint twice as long)
}
## Skill points per level. **2 points**: finishing the 23 stages once reaches about level 23 = 49 points, enough for only 56% of the maximum.
@export var points_per_level := 2
## Points given when a character is created, so the player can tweak something right away. Level 1 stats are unaffected — unspent points add nothing.
@export var starting_points := 5
## Level cap. One run through the 23 stages reaches about level 23; 23 → 30 takes grinding.
@export var max_level := 30
## Level curve: `xp_to_next(L) = xp_first_level × L^xp_power`.
## **A power, not an exponential**: the old curve `100 × 1.5^(L-1)` needed 740,000 XP at level 23 and could not last to stage 23.
@export var xp_first_level := 140
@export var xp_power := 1.55


## XP needed from level to the next. Not needed at max level (returns 0, which is how `add_xp` stops).
func xp_to_next(level: int) -> int:
	if level >= max_level:
		return 0
	return roundi(xp_first_level * pow(level, xp_power))


## Attack → damage multiplier; speed → cooldown multiplier (sprint stamina use is multiplied by it too).
static func damage_scale(attack: float) -> float:
	return attack / ATTACK_BASE


static func cooldown_scale(speed: float) -> float:
	return SPEED_BASE / maxf(speed, 1.0)


## Health actually lost after defence.
static func damage_taken(amount: int, defense: float) -> int:
	if amount <= 0:
		return 0
	return maxi(1, ceili(amount * 100.0 / (100.0 + maxf(defense, 0.0))))
