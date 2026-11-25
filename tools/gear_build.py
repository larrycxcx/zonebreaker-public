"""Generates the gear resources sold in the shop, output to armor/ and weapons/.

    python tools/gear_build.py

**Why a script generates them**: a piece of gear is a little bit of data (price, level requirement, stat bonuses),
and prices and bonuses are **worked out together** — priced at `60 × required level^1.9`, bonuses rising by tier,
and spread over twenty `.tres` files by hand they would never line up. Here one table shows everything; to rebalance, change this table and rerun.
The same approach as `level_build.py` and `skin_build.py`: rules live in the script, the output goes into the repo.

Icons come from `art_in/default/armor/Icon24_NN.png` (**5 pieces per set, head/body/legs/feet/hands**, one colour scheme per set)
and `2 Guns/Icon15_NN.png`, cut out into `skins/cyberpunk/ui/` by `tools/ui_build.py`.

There are no trinkets (TRINKET) in this batch — the art pack has no suitable icons, so that page stays empty for now.
"""
import os
import sys

sys.stdout.reconfigure(encoding="utf-8")

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
ICONS = "res://skins/cyberpunk/ui"

## Pricing: `60 × required level^1.9` (see "Where the numbers come from" in CLAUDE.md).
## Throughout, "three or four pieces affordable at any time"; the top tier in all eight slots = 174% of a first playthrough's income, so a first playthrough cannot equip it all.
def price_at(level):
	return int(round(60 * level ** 1.9 / 10.0)) * 10


## Three armour tiers: one colour scheme and one required level per tier.
## Bonuses are set against the stat caps (life 400 / attack 30 / defence 100 / speed 200):
## a full top-tier set = defence +36, life +130, speed +36, attack +5, clearly stronger but far from the cap,
## leaving the rest to skill points and later tiers.
ARMOR_TIERS = [
	("SCRAP", 1, 3, {                     # Tier one: the blue and gold set, level 3
		"HEAD": {"defense": 5.0},
		"BODY": {"life": 30.0},
		"LEGS": {"defense": 3.0, "speed": 3.0},
		"FEET": {"speed": 8.0},
		"HANDS": {"attack": 1.0},
	}),
	("COMBAT", 2, 8, {                    # Tier two: the red and pink set, level 8
		"HEAD": {"defense": 12.0},
		"BODY": {"life": 70.0},
		"LEGS": {"defense": 8.0, "speed": 6.0},
		"FEET": {"speed": 16.0},
		"HANDS": {"attack": 3.0},
	}),
	("TITAN", 3, 14, {                    # Tier three: the purple set, level 14
		"HEAD": {"defense": 22.0},
		"BODY": {"life": 130.0, "speed": -6.0},   # Heavy armour slows you down: a trade-off, not a freebie
		"LEGS": {"defense": 14.0, "speed": 10.0},
		"FEET": {"speed": 26.0},
		"HANDS": {"attack": 5.0},
	}),
]
## Slot → (Equipment.Slot index, position in the set, name on screen)
PARTS = [
	("HEAD", 2, 0, "HELM"),
	("BODY", 3, 1, "VEST"),
	("LEGS", 4, 2, "PANTS"),
	("FEET", 5, 3, "BOOTS"),
	("HANDS", 6, 4, "GLOVES"),
]

## Guns and grenades: **reuse the existing projectiles**, just harder hitting and faster.
## New projectiles need art and scenes, which is another matter; `power` and `cooldown` are enough to set the tiers apart.
WEAPONS = [
	# (file name, display name, required level, projectile, cooldown, automatic, power, look, slot, icon)
	("rifle_mk2", "RIFLE MK2", 5, "res://scenes/bullet.tscn", 0.13, True, 1.5,
		"rifle", 0, "gear_rifle_mk2"),
	("plasma_rifle", "PLASMA RIFLE", 12, "res://scenes/bullet.tscn", 0.11, True, 2.4,
		"rifle", 0, "gear_plasma_rifle"),
	("cluster_bomb", "CLUSTER BOMB", 9, "res://scenes/grenade.tscn", 0.45, False, 1.8,
		"launcher", 1, "gear_cluster_bomb"),
]


def write(path, text):
	full = os.path.join(ROOT, path)
	os.makedirs(os.path.dirname(full), exist_ok=True)
	with open(full, "w", newline="\n", encoding="utf-8") as f:
		f.write(text)


def bonus_block(bonuses):
	inner = ", ".join('&"%s": %.1f' % (k, v) for k, v in bonuses.items())
	return "bonuses = Dictionary[StringName, float]({%s})" % inner


def build_armor():
	made = []
	for name, tier, level, parts in ARMOR_TIERS:
		for part, slot, offset, label in PARTS:
			icon = "gear_%s_%s" % (name.lower(), part.lower())
			body = "\n".join([
				'[gd_resource type="Resource" script_class="Equipment" format=3]',
				"",
				'[ext_resource type="Script" path="res://scripts/rpg/equipment.gd" id="1"]',
				"",
				"[resource]",
				'script = ExtResource("1")',
				'display_name = "%s %s"' % (name, label),
				"slot = %d" % slot,
				"price = %d" % price_at(level),
				"min_level = %d" % level,
				bonus_block(parts[part]),
				'icon_path = "%s/%s.png"' % (ICONS, icon),
				"",
			])
			file = "armor/%s_%s.tres" % (name.lower(), part.lower())
			write(file, body)
			made.append((file, price_at(level), level))
	return made


def build_weapons():
	made = []
	for file, label, level, projectile, cooldown, automatic, power, look, slot, icon in WEAPONS:
		lines = [
			'[gd_resource type="Resource" script_class="Weapon" format=3]',
			"",
			'[ext_resource type="Script" path="res://scripts/weapons/weapon.gd" id="1"]',
			'[ext_resource type="PackedScene" path="%s" id="2"]' % projectile,
			"",
			"[resource]",
			'script = ExtResource("1")',
			'display_name = "%s"' % label,
			'projectile = ExtResource("2")',
			"cooldown = %s" % cooldown,
			"automatic = %s" % ("true" if automatic else "false"),
			"max_ammo = -1",
			'fire_event = &"%s"' % ("player_shoot" if slot == 0 else "grenade_throw"),
			'look = &"%s"' % look,
			"slot = %d" % slot,
			"power = %s" % power,
			"price = %d" % price_at(level),
			"min_level = %d" % level,
			'icon_path = "%s/%s.png"' % (ICONS, icon),
			"",
		]
		if slot == 1:
			lines.insert(-2, "hud_color = Color(0.45, 0.65, 0.3, 1)")
		path = "weapons/%s.tres" % file
		write(path, "\n".join(lines))
		made.append((path, price_at(level), level))
	return made


def main():
	rows = build_armor() + build_weapons()
	rows.sort(key=lambda r: r[1])
	print("Shop stock: %d items" % len(rows))
	for path, price, level in rows:
		print("  %-34s %6d   %d min level" % (path, price, level))


if __name__ == "__main__":
	main()
