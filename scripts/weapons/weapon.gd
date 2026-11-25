class_name Weapon
extends Equipment
## A weapon's parameters (resource file, kept under weapons/). A character's weapon slot (WeaponSlot) holds it; changing weapons = changing this file.
## Data only; the run-time cooldown and remaining ammo live in WeaponSlot — the same resource file may be used by several characters at once.
## Weapons are gear too (`Equipment`): `slot` is GUN or GRENADE, and they can carry stat bonuses and a price.

## Projectile scene. Its root script must have launch(direction: Vector2), called before it joins the scene tree (bullets and grenades both have it).
@export var projectile: PackedScene
## Shortest time between two shots (seconds). The player's speed stat shortens it proportionally (see Balance.cooldown_scale).
@export var cooldown := 0.15
## Damage multiplier: damage in the projectile scene × power × the player's attack multiplier. Change this to make stronger and weaker guns from the same bullet.
@export var power := 1.0
## Status applied on hit (empty for none): filled into the projectile's `status` when firing, e.g. incendiary or poison rounds.
@export var status: StatusEffect
## Holding the fire button fires continuously (rifle); off means pressing again for every shot (grenade).
@export var automatic := true
## Ammo cap, -1 for unlimited.
@export var max_ammo := -1
## Event reported when firing; the skin pack looks up a sound by it (see SkinPack.SOUND_EVENTS).
@export var fire_event := &"player_shoot"
## What it looks like in the hand: the appearance layer picks the gun sprites by this key (in the cyberpunk pack rifle = rifle, launcher = grenade launcher).
## Only a name, unrelated to gameplay — muzzle positions, fire rate and projectile ignore it. If the pack has no sprites for the key the default gun is used; same when empty.
@export var look := &""
## Small colour block representing this weapon in the HUD (placeholder art, replaced by an icon in step 4).
@export var hud_color := Color(0.7, 0.7, 0.75)
