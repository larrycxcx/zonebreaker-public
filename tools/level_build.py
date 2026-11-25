"""Generates the real stage scenes (scenes/level_N.tscn).

    python tools/level_build.py          # all stages
    python tools/level_build.py 2        # only generate stage 2
    python tools/level_build.py demo     # the screen of the user's sketch (scenes/map_demo.tscn)
    python tools/level_build.py --check  # only self-check, without writing files

**Why a script generates them**: a real stage is 12800 wide = 20 screens, and hand-writing hundreds of nodes makes iterating impossible —
tweaking the pacing would mean rearranging a whole screen. The same approach as `skin_build.py`: rules and numbers live in the script, the output goes into the repo.

**Kinds of stages** (since 2026-10):
**All the stages are grid maps**: drawn in `level1_map.py` … `level4_map.py`, with `map_build.py` finding paths for the self-check, choosing tiles and writing scenes
(see "Ladders and layered stages" in CLAUDE.md). Stage 4 is one **vertical** shaft (40 × 450 cells).
The two old generators (the horizontal "segment table" and the vertical `vlevel_build.py`) were both deleted when the stages switched to grid maps.

What is left here: a few shared rulers, each stage's enemy table, the `STAGES` master table, and the file header and platform nodes used to write scenes.
"""
import os
import sys

sys.stdout.reconfigure(encoding="utf-8")

HERE = os.path.dirname(os.path.abspath(__file__))
SCENES = os.path.join(HERE, "..", "scenes")

# ---------------------------------------------------------------- Shared rulers

## The y of the ground's top edge.
GROUND_Y = 320.0
## How tall the view is. Used for the camera's limit_bottom.
SCREEN_H = 360.0
## The y of enemies / players standing on the ground: the hitbox is 32 tall with the origin in the middle, so 16 above the ground's top edge.
STAND = 16.0
## Boss A's hitbox is 48 tall with the origin in the middle → 24 above the top edge.
BOSS_STAND = 24.0

## The height above the top of the view where the 2-A dropping from the sky hangs, falling only when the player walks underneath.
HANG_Y = -40.0

## Trap scenes (stage 2's hydraulic press and blast gate).
PRESS_SCENE = "res://scenes/trap_press.tscn"
GATE_SCENE = "res://scenes/trap_gate.tscn"

## What enemies are called in the stage: key `1_a` → `1-A`, `1_boss` → `1-Boss`.
## **The number includes the stage**: each of the 23 stages has its own set of enemies, and the letter is only an index within that stage (it says nothing about how it fights),
## so stage 2's are `2-A`, `2-B`…; without the stage number the letters would soon run out.
def enemy_label(kind):
	level, _, rest = kind.partition("_")
	return "%s-%s" % (level, "Boss" if rest == "boss" else rest.upper())


## Enemy type → scene path. The keys are the names written in the maps / segment tables.
ENEMIES_1 = {
	"1_a": "res://scenes/enemy_1_a.tscn",
	"1_b": "res://scenes/enemy_1_b.tscn",
	"1_c": "res://scenes/enemy_1_c.tscn",
	"1_f": "res://scenes/enemy_1_f.tscn",
	"1_g": "res://scenes/enemy_1_g.tscn",
	"1_d": "res://scenes/enemy_1_d.tscn",
	"1_e": "res://scenes/enemy_1_e.tscn",
	"1_boss": "res://scenes/boss_1.tscn",
}

## Props: name → how many frames side by side (1 = still). **Display only, no collision** (`scripts/prop.gd`).
PROP_FRAMES_1 = {"fountain": 4}


# ---------------------------------------------------------------- Stage 2 (industrial zone)
#
# A layered grid map (`level2_map.py`); only its enemy table and animated props are kept here.

PROP_FRAMES_2 = {"screen": 4, "conveyor": 4}

ENEMIES_2 = {
	"2_a": "res://scenes/enemy_2_a.tscn",
	"2_b": "res://scenes/enemy_2_b.tscn",
	"2_c": "res://scenes/enemy_2_c.tscn",
	"2_d": "res://scenes/enemy_2_d.tscn",
	"2_e": "res://scenes/enemy_2_e.tscn",
	"2_f": "res://scenes/enemy_2_f.tscn",
	"2_boss": "res://scenes/boss_2.tscn",
}


# ---------------------------------------------------------------- Stage 3 (bar street)
#
# A layered grid map (`level3_map.py`). This stage has **no flyers** and **no animated props**:
# bottles, glasses, flying banknotes and swinging signs lying on the ground look like pickups (2026-10 playtest feedback), so none of them.

PROP_FRAMES_3 = {}

ENEMIES_3 = {
	"3_a": "res://scenes/enemy_3_a.tscn",
	"3_b": "res://scenes/enemy_3_b.tscn",
	"3_c": "res://scenes/enemy_3_c.tscn",
	"3_d": "res://scenes/enemy_3_d.tscn",
	"3_e": "res://scenes/enemy_3_e.tscn",
	"3_f": "res://scenes/enemy_3_f.tscn",
	"3_boss": "res://scenes/boss_3.tscn",
}

## How many pixels below the origin the feet are, written only for **those that differ**: 3-E lies on the ground and is only 12 tall (hitbox 28×12),
## and the unicycle mech's hitbox is 56 tall. Placed by `STAND` / `BOSS_STAND`, one would sink into the ground and the other float in mid-air.
STAND_3 = {"3_e": 6.0, "3_boss": 28.0}

SECTIONS_3 = [
	("Sidewalk", {                                # Street corner: meet 3-B, and the first ground-hugging 3-E
		"props": [("counter", 300, GROUND_Y), ("sign2", 620, GROUND_Y),
			("counter2", 940, GROUND_Y)],
		"ledges": [(260, 256, 96), (420, 208, 96), (640, 256, 112), (860, 208, 96),
			(1060, 248, 96)],
		"enemies": [("3_b", 840, GROUND_Y), ("3_a", 960, GROUND_Y), ("3_b", 880, 208),
			("3_e", 1020, GROUND_Y), ("3_b", 1100, 248), ("3_a", 1220, GROUND_Y)],
	}),
	("Awnings", {                                 # Climbing up the awnings, the leaping 3-C pounces from above
		"ledges": [(100, 264, 96), (260, 216, 96), (420, 168, 128), (620, 160, 240),
			(900, 216, 96), (1080, 256, 112)],
		"walls": [(180, 40)],
		"gaps": [(1000, 88)],
		"blocks": [(660, 64, 112)],
		"enemies": [("3_b", 150, GROUND_Y), ("3_c", 300, 216), ("3_b", 480, 168),
			("3_d", 560, GROUND_Y), ("3_c", 700, 160), ("3_e", 780, GROUND_Y),
			("3_b", 820, 160), ("3_b", 950, 216), ("3_b", 1140, 256),
			("3_a", 1150, GROUND_Y)],
	}),
	("Cellar", {                                  # A low tunnel + a blocked lower level: a brute stands at the exit
		"crawl": [(200, 200), (800, 180)],
		"blocks": [(520, 64, 112)],
		"ledges": [(340, 248, 80), (400, 208, 64), (440, 160, 240), (720, 248, 96),
			(1000, 200, 96), (1160, 256, 96)],
		"enemies": [("3_d", 460, GROUND_Y), ("3_b", 500, 160), ("3_e", 700, GROUND_Y),
			("3_b", 760, 248), ("3_d", 1040, GROUND_Y), ("3_c", 1040, 200),
			("3_a", 1200, GROUND_Y), ("3_b", 1200, 256)],
	}),
	("Gutters", {                                 # Pit area: 3-E guards the pit edge, so you have to jump its bullets and the pit
		"gaps": [(300, 96), (620, 88), (940, 100)],
		"ledges": [(180, 248, 96), (460, 264, 96), (760, 248, 112), (1080, 256, 96)],
		"enemies": [("3_b", 200, 248), ("3_e", 500, GROUND_Y), ("3_c", 500, 264),
			("3_d", 800, GROUND_Y), ("3_b", 800, 248), ("3_e", 880, GROUND_Y),
			("3_f", 1060, GROUND_Y), ("3_b", 1120, 256), ("3_a", 1240, GROUND_Y)],
	}),
	("Bouncers", {                                # The brutes' turf: you cannot beat them head-on, you have to go around
		"props": [("counter2", 400, GROUND_Y), ("sign2", 1000, GROUND_Y)],
		"ledges": [(220, 256, 96), (460, 256, 80), (560, 208, 112), (900, 256, 96),
			(1020, 256, 80), (1120, 208, 96)],
		"walls": [(740, 56)],
		"enemies": [("3_d", 180, GROUND_Y), ("3_b", 260, 256), ("3_a", 620, GROUND_Y),
			("3_b", 600, 208), ("3_d", 860, GROUND_Y), ("3_b", 940, 256),
			("3_f", 1060, GROUND_Y), ("3_d", 1180, GROUND_Y), ("3_c", 1160, 208)],
	}),
	("Carts", {                                   # Cannon carts on the long straight road, with a high road above
		"props": [("cabinet", 300, GROUND_Y)],
		"ledges": [(160, 256, 96), (340, 208, 96), (480, 160, 256), (820, 256, 96),
			(980, 208, 96), (1140, 256, 96)],
		"blocks": [(560, 64, 120)],
		"walls": [(1080, 48)],
		"enemies": [("3_f", 260, GROUND_Y), ("3_b", 380, 208), ("3_f", 420, GROUND_Y),
			("3_b", 520, 160), ("3_b", 700, 160), ("3_f", 760, GROUND_Y),
			("3_e", 900, GROUND_Y), ("3_c", 1020, 208), ("3_b", 1160, 256),
			("3_f", 1200, GROUND_Y)],
	}),
	("Rooftops", {                                # Crossing the pits on awnings all the way, with 3-Cs leaping between the awnings
		"gaps": [(360, 92), (820, 96)],
		"ledges": [(180, 264, 96), (320, 216, 112), (520, 264, 96), (700, 216, 112),
			(900, 264, 96), (1080, 216, 112)],
		"enemies": [("3_b", 200, 264), ("3_c", 360, 216), ("3_b", 560, 264),
			("3_e", 640, GROUND_Y), ("3_c", 740, 216), ("3_b", 940, 264),
			("3_a", 1000, GROUND_Y), ("3_c", 1120, 216), ("3_b", 1200, GROUND_Y)],
	}),
	("Crossfire", {                               # Three-layer crossfire, with a ground-hugger below too
		"ledges": [(120, 264, 128), (340, 208, 128), (560, 152, 160), (820, 208, 128),
			(1040, 264, 128)],
		"gaps": [(700, 92)],
		"enemies": [("3_b", 160, 264), ("3_f", 260, GROUND_Y), ("3_b", 380, 208),
			("3_b", 600, 152), ("3_e", 640, GROUND_Y), ("3_b", 660, 152),
			("3_b", 860, 208), ("3_d", 980, GROUND_Y), ("3_b", 1080, 264),
			("3_a", 1200, GROUND_Y)],
	}),
	("BackAlley", {                               # Back alley: pits, a low tunnel, brutes and knifemen crowded together
		"crawl": [(160, 180), (660, 160)],
		"gaps": [(420, 96), (900, 100), (1090, 92)],
		"ledges": [(320, 248, 96), (520, 184, 96), (840, 248, 64), (1020, 248, 64)],
		"walls": [(1220, 40)],
		"blocks": [(540, 56, 112)],
		"enemies": [("3_d", 380, GROUND_Y), ("3_b", 360, 248), ("3_a", 620, GROUND_Y),
			("3_b", 560, 184), ("3_b", 860, 248), ("3_e", 870, GROUND_Y),
			("3_d", 1040, GROUND_Y), ("3_c", 1040, 248), ("3_b", 1250, GROUND_Y)],
	}),
	("BossArena", {                               # Boss area: **solid ground all over, no walls**, it rolls along the ground
		"props": [("counter", 260, GROUND_Y), ("cabinet2", 640, GROUND_Y)],
		"walls": [(40, 56)],
		"ledges": [(180, 248, 96), (360, 200, 96), (560, 248, 112),
			(820, 256, 96), (1120, 248, 96)],
		"enemies": [("3_d", 140, GROUND_Y), ("3_b", 220, 248), ("3_f", 420, GROUND_Y),
			("3_b", 400, 200), ("3_a", 620, GROUND_Y), ("3_b", 600, 248),
			("3_boss", 1000, GROUND_Y)],
	}),
]

# ---------------------------------------------------------------- Stage 4 (basement, climbed vertically)
#
# A vertical grid map (`level4_map.py`); only its enemy table, how high the short ones stand, and animated props are kept here.

ENEMIES_4 = {
	"4_a": "res://scenes/enemy_4_a.tscn",
	"4_b": "res://scenes/enemy_4_b.tscn",
	"4_c": "res://scenes/enemy_4_c.tscn",
	"4_d": "res://scenes/enemy_4_d.tscn",
	"4_e": "res://scenes/enemy_4_e.tscn",
	"4_f": "res://scenes/enemy_4_f.tscn",
	"4_boss": "res://scenes/boss_4.tscn",
}
## The spider turret is short (hitbox 22 tall), with the feet 11 below the origin.
STAND_4 = {"4_e": 11.0}
PROP_FRAMES_4 = {"smoke": 6}

# ---------------------------------------------------------------- Stage 5 (lab)
#
# A layered grid map (`level5_map.py`). Midway there is a mid-level boss room (doors `[` `]`, see `ArenaDoor`).

ENEMIES_5 = {
	"5_a": "res://scenes/enemy_5_a.tscn",
	"5_b": "res://scenes/enemy_5_b.tscn",
	"5_c": "res://scenes/enemy_5_c.tscn",
	"5_d": "res://scenes/enemy_5_d.tscn",
	"5_e": "res://scenes/enemy_5_e.tscn",
	"5_f": "res://scenes/enemy_5_f.tscn",
	"5_mid": "res://scenes/boss_5_mid.tscn",
	"5_boss": "res://scenes/boss_5.tscn",
}
## The mutant gunner's hitbox is 48 tall with the feet 24 below the origin (its name does not end in _boss, so it has to be named).
STAND_5 = {"5_mid": 24.0}
PROP_FRAMES_5 = {"generator": 4, "valve": 4, "scanner": 6, "camera": 6}

# ---------------------------------------------------------------- One stage = one entry
#
# To add a stage, add an entry to this table and run `python tools/level_build.py 2`.
# Stages **share nothing**: enemies, props and maps are each written separately — every one of the 23 stages has different enemies and art,
# and sharing one copy would only mean that "tuning stage 2's pacing" changes stage 1 too.
STAGES = {
	# All are **grid maps**: drawn in `levelN_map.py`, with `map_build.py` checking paths and writing the scene;
	# `theme` is that zone's tile set (`map_build.THEMES`)
	"1": {
		"out": "level_1.tscn", "root": "Level1", "prop_dir": "cyberpunk", "map": "level1_map",
		"theme": "green", "enemies": ENEMIES_1, "prop_frames": PROP_FRAMES_1,
	},
	"2": {
		"out": "level_2.tscn", "root": "Level2", "prop_dir": "industrial", "map": "level2_map",
		"theme": "industrial",
		"enemies": ENEMIES_2, "prop_frames": PROP_FRAMES_2,
	},
	"3": {
		"out": "level_3.tscn", "root": "Level3", "prop_dir": "bar_street", "map": "level3_map",
		"theme": "bar", "enemies": ENEMIES_3, "prop_frames": PROP_FRAMES_3, "stand": STAND_3,
	},
	# Stage 4 is a **vertical** grid map (switched from the old vertical segment table in 2026-10): one whole shaft, 450 rows tall
	"4": {
		"out": "level_4.tscn", "root": "Level4", "prop_dir": "basement", "map": "level4_map",
		"theme": "basement", "enemies": ENEMIES_4, "prop_frames": PROP_FRAMES_4, "stand": STAND_4,
	},
	"5": {
		"out": "level_5.tscn", "root": "Level5", "prop_dir": "lab", "map": "level5_map",
		"theme": "lab", "enemies": ENEMIES_5, "prop_frames": PROP_FRAMES_5, "stand": STAND_5,
	},
}


def use_stage(key):
	"""Load this stage's table of "how far each enemy type's feet are from the origin" into the globals (`stand_of()` reads it)."""
	global STAND_BY
	STAND_BY = STAGES[key].get("stand", {})


STAND_BY = {}


def stand_of(kind):
	"""How many pixels below the origin the feet are: by the table if named there, otherwise 24 for bosses and 16 for the rest."""
	if kind in STAND_BY:
		return STAND_BY[kind]
	return BOSS_STAND if kind.endswith("_boss") else STAND


# ---------------------------------------------------------------- Writing scenes

HEAD = """[gd_scene format=3]

[ext_resource type="PackedScene" path="res://scenes/platform.tscn" id="1"]
[ext_resource type="PackedScene" path="res://scenes/player.tscn" id="2"]
[ext_resource type="Script" path="res://scripts/main.gd" id="3"]
[ext_resource type="PackedScene" path="res://scenes/hud.tscn" id="6"]
[ext_resource type="Script" path="res://scripts/fx.gd" id="13"]
[ext_resource type="PackedScene" path="res://scenes/muzzle_flash.tscn" id="14"]
[ext_resource type="PackedScene" path="res://scenes/hit_spark.tscn" id="15"]
[ext_resource type="PackedScene" path="res://scenes/impact_spark.tscn" id="16"]
[ext_resource type="Script" path="res://scripts/camera_rig.gd" id="17"]
[ext_resource type="PackedScene" path="res://scenes/explosion.tscn" id="18"]
[ext_resource type="PackedScene" path="res://scenes/ui/pause_menu.tscn" id="19"]
[ext_resource type="PackedScene" path="res://scenes/ui/death_screen.tscn" id="20"]
[ext_resource type="PackedScene" path="res://scenes/ui/clear_screen.tscn" id="22"]
"""


def platform(name, parent, x, y, w, h, one_way=False, skin=None):
	lines = ['[node name="%s" parent="%s" instance=ExtResource("1")]' % (name, parent)]
	if skin:
		lines.append('skin_key = &"%s"' % skin)
	lines.append("position = Vector2(%g, %g)" % (x, y))
	lines.append("size = Vector2(%g, %g)" % (w, h))
	if one_way:
		lines.append("one_way = true")
	return "\n".join(lines) + "\n"


def build_map_demo(write):
	"""The screen of the user's sketch (`level_maps.DEMO`), generated into scenes/map_demo.tscn, not in the stage select list."""
	import level_maps
	import map_build as mb
	level = mb.MapLevel(level_maps.DEMO, level_maps.DEMO_ENEMIES, ENEMIES_2, lambda kind: STAND)
	problems = mb.check(level, safe_cols=0)   # The sketch is only one screen to begin with, with all the enemies on it
	if problems:
		print("The grid map failed its self-check:")
		for p in problems:
			print("  -", p)
		sys.exit(1)
	mb.build(level, os.path.join(SCENES, "map_demo.tscn"), "MapDemo", "industrial", write,
		PROP_FRAMES_2, level_maps.DEMO_PROPS, level_maps.DEMO_DECOR)
	print("The sketch segment: %d cells wide (%d pixels)" % (level.width, level.width * mb.CELL))
	print("  solid %d, one-way %d, ladders %d, presses %d, gates %d, enemies %d"
		% (len(level.solids), len(level.ledges), len(level.ladders), len(level.presses),
			len(level.gates), len(level.enemies)))
	if write:
		print("  writing scenes/map_demo.tscn")


def build_map_level(key, write):
	"""Layered grid maps (stage 1 `level1_map.py`, stage 2 `level2_map.py`) → scenes/level_N.tscn."""
	import importlib
	import map_build as mb
	import map_canvas
	stage = STAGES[key]
	plan = importlib.import_module(stage["map"])
	mb.use_theme(stage["theme"])
	rows, props, decor = plan.assemble()
	level = mb.MapLevel(rows, plan.LETTERS, stage["enemies"], stand_of, plan.FLOATING, plan.HANGING,
		getattr(plan, "FLOAT_AT", None))
	problems = mb.check(level, chasers=plan.CHASERS, min_enemies=plan.MIN_ENEMIES)
	if problems:
		map_canvas.dump(rows)
		print("The grid map failed its self-check:")
		for p in problems:
			print("  -", p)
		sys.exit(1)
	mb.build(level, os.path.join(SCENES, stage["out"]), stage["root"], stage["prop_dir"], write,
		stage["prop_frames"], props, decor)
	if level.vertical:
		print("Stage %s (vertical): %d × %d cells (%d screens tall)" % (key, level.width, level.height, level.height * 16 // 360))
	else:
		print("Stage %s (layered): %d cells wide (%d screens)" % (key, level.width, level.width // 40))
	print("  solid %d, one-way %d, ladders %d, presses %d, gates %d, crates %d, barrels %d, enemies %d, props %d"
		% (len(level.solids), len(level.ledges), len(level.ladders), len(level.presses),
			len(level.gates), len(level.crates), len(level.barrels), len(level.enemies), len(level.props)))
	if write:
		print("  writing scenes/%s" % stage["out"])


def main():
	write = "--check" not in sys.argv
	if "demo" in sys.argv:
		build_map_demo(write)
		return
	wanted = [a for a in sys.argv[1:] if not a.startswith("--")] or list(STAGES)
	for key in wanted:
		if key not in STAGES:
			sys.exit("There is no stage %s (available: %s)" % (key, ", ".join(STAGES)))
		use_stage(key)
		build_stage(key, write)


def build_stage(key, write):
	if not STAGES[key].get("map"):
		sys.exit("Stage %s has no grid map configured" % key)
	build_map_level(key, write)


if __name__ == "__main__":
	main()
