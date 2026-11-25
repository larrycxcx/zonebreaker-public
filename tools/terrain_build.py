"""Generates the cyberpunk skin pack's platform art and backdrop from the terrain art pack, output to skins/cyberpunk/terrain/ and skins/cyberpunk/backdrop/.

    python tools/terrain_build.py            # regenerate everything
    python tools/terrain_build.py --check    # only check, without writing files

Art source: CraftPix's Green Zone Tileset (art_in/default/green-zone-tileset/, not in the repo, same licence as the other art packs).
Each tile is 32×32, all in the single atlas Tileset.png (12 columns × 8 rows).

**Terrain does not switch to TileMap**: stages are still built from platform.tscn, with colliders and rules untouched; only the look is drawn
as a "nine-slice" by platform size — the four corners as is, the four edges and the middle **tiled** (not stretched, so pixels do not blur). How it is cut is written in each visual scene
(`TerrainAppearance`'s left / right / top / bottom / hang); this only assembles the tiles used into one source image:
- ground: the turf ground. Only the middle column is taken (the turf top with the soil right below it); the ground spans the whole stage,
  and the rounded ends would show at the edges of the stage, so they are not used; ground thicker than 32px gets more soil below.
- ledge: the floating one-way platform. The row with a grassy top and a ragged hanging bottom edge (left / middle / right). The platform is only 16px thick,
  so the look takes the top 10 rows of grass + the bottom 12 rows (with the hanging bits), the hanging part dangling 6px below the hitbox.
- stone: walls and the top blocks of low tunnels. One whole stone brick with an outline on all four sides. **The bottom edge is flat**: a low tunnel only has 30px of headroom,
  and hanging bits would make people think they cannot get through.

The backdrop (`2 Background/Day`) has five layers, all 576×324: 1 sky, 2 distant buildings, 3 distant trees, 4 a strip of ground edge, 5 nearby trees.
The daytime set is used: the night set is grey and dark, and black-outlined characters and bullets are hard to see against it. Parallax and tiling are done by the `backdrop` scene.
**The backdrop has to recede**: the nearby trees were originally (55,68,110), almost the same as the dark blue of the stone terrain (34,42,92), so walls and low tunnel tops would melt into the backdrop —
things that block the way and bullets have to stand out at a glance. So each layer is mixed a little towards the sky colour at the horizon (`HAZE`, more for further layers, keeping the depth),
and the sky layer stays as is.
"""
import os
import sys

import skin_build as sb

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, "..", "art_in", "default")
SKINS = os.path.join(HERE, "..", "skins")
TILE = 32

## **One set of terrain art = one "zone"**. To add a stage, add an entry to this table and run `python tools/terrain_build.py industrial`.
## Tiles can be taken two ways, whichever way the art pack provides them:
## `atlas` one big atlas, with (row, column) in `terrain`;
## `tiles` one file per tile (a template with `%d`), with numbers in `terrain`.
## The three keys of `terrain` are what gameplay recognises (`skin_key` in `platform.gd`) and cannot be renamed:
## `ground` the ground (spanning the stage, the second row tiled downward), `ledge` floating one-way platforms (one row of three tiles: left, middle, right), `stone` walls and blocks.
ZONES = {
	"cyberpunk": {
		"pack": "green-zone-tileset",
		"out": "cyberpunk",
		"atlas": "Tileset.png",
		"terrain": {"ground": [[(0, 1)], [(1, 1)]], "ledge": [[(4, 0), (4, 1), (4, 2)]], "stone": [[(2, 5)]]},
		# The atlas used by layered stages (2026-10) to pick tiles cell by cell: `Tileset.png` is just `1 Tiles/Tile_01..96` laid out in 12 columns,
		# laid out again as is (number = row × 12 + column + 1, the same rule as the industrial one)
		"tiles": "1 Tiles/Tile_%02d.png",
		"tile_atlas": {"count": 96, "columns": 12},
		"backdrop_dir": "2 Background/Day",
		"backdrop": {"sky": "1", "buildings": "2", "trees_far": "3", "ground_line": "4", "trees_near": "5"},
		# Ladder (2026-10): the middle section tiles vertically without seams. `Ladder2` is missing a rung, so it is unused. Zones without ladder art use this one via fallback
		"ladder": {"middle": "3 Objects/Other/Ladder1.png"},
		"haze": {"sky": 0.0, "buildings": 0.3, "trees_far": 0.4, "ground_line": 0.25, "trees_near": 0.25},
		"props": {
			"tree_small": ("3 Objects/Other/Tree1.png", 1),
			"tree_big": ("3 Objects/Other/Tree2.png", 1),
			"bench": ("3 Objects/Benches/1.png", 1),
			"bench2": ("3 Objects/Benches/2.png", 1),
			"bin": ("3 Objects/Other/Garbage_Can1.png", 1),
			"box": ("3 Objects/Other/Box.png", 1),
			"fence": ("3 Objects/Fence/1.png", 1),
			"bush_big": ("3 Objects/Bushes/1.png", 1),
			"bush_wide": ("3 Objects/Bushes/17.png", 1),
			"bush_flat": ("3 Objects/Bushes/13.png", 1),
			"rock_small": ("3 Objects/Stones/2.png", 1),
			"rock": ("3 Objects/Stones/4.png", 1),
			"rock_big": ("3 Objects/Stones/6.png", 1),
			"grass_tuft": ("3 Objects/Grass/1.png", 1),
			"grass_blade": ("3 Objects/Grass/6.png", 1),
			"fountain": ("4 Animated objects/Fountain.png", 4),
		},
	},
	# Stage 3: bar street. The tiles are 100 separate files, and **this set is a "street facade", not a terrain pack** —
	# brick walls, windows, shutters, awnings, with no ready-made "turf ground". So the picks are:
	# ground = the brick wall with a wooden beam top (02) on plain brick (05); ledges = **awnings** (07/08/09 left, middle, right,
	# jumping on the shops' awnings in the street suits the stage's theme); walls and blocks = the shutter (59),
	# whose grey-blue stands apart from the brown brick ground, and a "pulled-down shutter" itself means "no way through".
	# The backdrop uses **Night**, plus the lighting layer that comes with the art pack (`Overlay_illumination.png`) —
	# the Night layers are grey on purpose, **left for the lighting layer to colour**, and the pink / cyan neon of the promo art comes from stacking the two.
	# (The first version only looked at Night itself, found it grey and switched to Day, which did not look like the art pack at all.)
	# People and bullets are drawn above the lighting layer (see `ScreenLight`) and are not tinted, so they stay clear.
	"bar_street": {
		"pack": "bar-street-tileset",
		"out": "bar_street",
		"tiles": "1 Tiles/Tiles_%02d.png",
		# The atlas used by layered stages (2026-10) to pick tiles cell by cell: 100 tiles in 10 columns (number = row × 10 + column + 1)
		"tile_atlas": {"count": 100, "columns": 10},
		"terrain": {"ground": [[2], [5]], "ledge": {"tiles": [[7, 8, 9]], "crop": 16},
			"stone": [[59]]},
		"backdrop_dir": "2 Background/Night",
		"backdrop": {"sky": "1", "far": "2", "mid": "3", "near": "4", "street": "5"},
		# No haze at night: near and far are already separated by grey levels, and mixing towards the sky colour would only flatten the light and dark the lighting layer colours
		"haze": {"sky": 0.0, "far": 0.0, "mid": 0.0, "near": 0.0, "street": 0.0},
		# The light map of the lighting layer. The original is 1800×1200 and blurry throughout; halved you cannot tell the difference, and it saves 3/4 in the repo
		"lighting": ("2 Background/Overlay_illumination.png", 2),
		"facades": "BAR_FACADES",
		"props": {
			"counter": ("3 Objects/Bar counter/1.png", 1),
			"counter2": ("3 Objects/Bar counter/4.png", 1),
			"cabinet": ("3 Objects/Bar cabinet/1.png", 1),
			"cabinet2": ("3 Objects/Bar cabinet/5.png", 1),
			"stool": ("3 Objects/Bar stool/1.png", 1),
			"stool2": ("3 Objects/Bar stool/4.png", 1),
			"sign": ("3 Objects/Signboards/1.png", 1),
			"sign2": ("3 Objects/Signboards/3.png", 1),
			"crate": ("3 Objects/Props/Prop_01.png", 1),
			"keg": ("3 Objects/Props/Prop_06.png", 1),
			"bin": ("3 Objects/Props/Prop_11.png", 1),
			# No bottles, glasses, flying banknotes or swinging signs: on the ground they look like pickups (see SCATTER_3 in level_build.py)
		},
	},
	# Stage 4: basement, **climbed vertically**. This set is real "solid rock" terrain: brick frames with a dark purple fill and light blue outline,
	# with a complete nine-slice (1/2/4, 11/12/14, 21/22/24), unlike bar street's street facade.
	# Ledges = the thin strips of 41~44 with **only the top half drawn** (cropped to 16 rows); the ground (shaft bottom) = frame top 2 on fill 12.
	# **The backdrop does not use the art's own set**: that is a 576×324 horizontal picture, and repeating it vertically shows.
	# Behind the shaft goes an assembled basement wall (`wall`, see `build_wall()`), tiling vertically without seams.
	# The lighting layer is the same image as bar street's (byte for byte), used the same way.
	"basement": {
		"pack": "basement-tileset",
		"out": "basement",
		"tiles": "1 Tiles/Tile_%02d.png",
		# The atlas used by grid maps (stage 4 switched to a vertical grid map in 2026-10) to pick tiles cell by cell: 70 tiles in 10 columns
		"tile_atlas": {"count": 70, "columns": 10},
		"terrain": {"ground": [[2], [12]], "ledge": {"tiles": [[41, 42, 44]], "crop": 16},
			"stone": [[1, 2, 4], [11, 12, 14], [21, 22, 24]]},
		"wall": {
			"cols": 20, "rows": 20, "seed": 20261002,
			# Brick walls are picked at random by weight: mostly whole bricks, a few cracked, even fewer broken
			"bricks": [(67, 70), (68, 18), (70, 8), (69, 4)],
			# Pushed back: the platforms, walls and people in front are what need to be seen clearly
			"shade": 0.55,
			# Vertical pipes / fences, a separate layer scrolling a bit faster than the brick wall, so they look in front of it
			"pipes": {"columns": [2, 7, 13, 17], "tiles": [65, 66, 65, 65], "shade": 0.75},
			# **The 16 small lights in the art are not used**: tried baked into the wall, shrunk on screen they were floating little cyan-green dots,
			# looking just like gems to pick up (the same problem as stage 3's bottles and glasses).
		},
		"lighting": ("2 Background/Overlay_illumination.png", 2),
		"props": {
			"pipe": ("3 Objects/1 Pipe/1.png", 1),
			"pipe_moss": ("3 Objects/1 Pipe/1_2.png", 1),
			"pipe_tall": ("3 Objects/1 Pipe/4.png", 1),
			"pipe_bend": ("3 Objects/1 Pipe/6.png", 1),
			"pipe_bend_moss": ("3 Objects/1 Pipe/6_2.png", 1),
			"box": ("3 Objects/2 Box/1.png", 1),
			"box_moss": ("3 Objects/2 Box/1_2.png", 1),
			"box_small": ("3 Objects/2 Box/2.png", 1),
			"crane": ("3 Objects/3 Decoration/1.png", 1),
			"unit": ("3 Objects/3 Decoration/2.png", 1),
			"fan": ("3 Objects/3 Decoration/3.png", 1),
			"container": ("3 Objects/3 Decoration/4.png", 1),
			"container_moss": ("3 Objects/3 Decoration/4_2.png", 1),
			"sign_carre": ("3 Objects/3 Decoration/5.png", 1),
			"sign_hotel": ("3 Objects/3 Decoration/6.png", 1),
			"sign_poker": ("3 Objects/3 Decoration/7.png", 1),
			"grate": ("3 Objects/3 Decoration/8.png", 1),
			"grate_moss": ("3 Objects/3 Decoration/8_2.png", 1),
			"grass": ("3 Objects/3 Decoration/Grass1.png", 1),
			"grass2": ("3 Objects/3 Decoration/Grass2.png", 1),
			# The only animated one is steam. No Card / Money: on the ground they look like pickups (the lesson of stage 3)
			"smoke": ("4 Animated objects/Smoke.png", 6),
		},
	},
	# Stage 5: lab (2026-11). The tiles are 100 separate files (`Tiles_01..100`), number = row × 10 + column + 1.
	# The first 60 are nine-slices of three materials (3 columns each): columns 1~3 teal diagonal-ridged steel plate, 4~6 the same with stains, 7~9 clean grey-blue wall panels,
	# each with a nine-slice in rows 1~3, whole crates in row 4 (31 / 37 X-braced), and one-brick-thick strips in row 6;
	# column 10 is dark background tiles (ridged, speckled, plain, dark red speckled); 61~100 are big background wall panels made of two tiles each (grey, purple, with transparency).
	# ground = steel plate top 2 on body 12; ledges = the top half of the one-brick-thick strips 51/52/53; walls and blocks = the grey-blue wall panel nine-slice.
	# The backdrop uses **Day**: six layers, 1 base colour, 2/3 distant factory buildings, 4 hanging machines, 5 nearby, 6 the big pillars in front.
	# The art pack **has no acid pool** (`Acid1/2` is an acid splash effect); the new trap is extending and retracting spikes (`Spikes`).
	"lab": {
		"pack": "lab-tileset",
		"out": "lab",
		"tiles": "1 Tiles/Tiles_%02d.png",
		"tile_atlas": {"count": 100, "columns": 10},
		"terrain": {"ground": [[2], [12]], "ledge": {"tiles": [[51, 52, 53]], "crop": 16},
			"stone": [[7, 8, 9], [17, 18, 19], [27, 28, 29]]},
		"backdrop_dir": "2 Background/Day",
		"backdrop": {"base": "1", "far": "2", "mid": "3", "machines": "4", "near": "5", "pillars": "6"},
		# Recede: the foreground steel plate is teal too, and without a little mixing the near layers would blur together with the terrain
		"haze": {"base": 0.0, "far": 0.15, "mid": 0.2, "machines": 0.25, "near": 0.3, "pillars": 0.35},
		# Spikes (6 frames × 32, retracted → extended → retracted)
		"traps": {"spikes": "4 Animated objects/Spikes.png"},
		# **Gas capsules = this stage's breakable obstacles** (the art's `Chest` is a supply box with a lid, with uneven frame widths, not something that breaks):
		# `Capsule2~4` intact (blue, blue-green, green), 5 cracked, 6 half shattered, 7 only a ring of shards left. All 50×48 with 39×48 of content on the left.
		# `Capsule1` has a pipe attached to its side and is not in the breakable set — it looks intact, and used as a prop players would try to shoot it
		"capsules": {"capsule_1": "3 Objects/Capsule2.png", "capsule_2": "3 Objects/Capsule3.png",
			"capsule_3": "3 Objects/Capsule4.png", "capsule_cracked": "3 Objects/Capsule5.png",
			"capsule_half": "3 Objects/Capsule6.png", "capsule_debris": "3 Objects/Capsule7.png"},
		# A few copied as is (not terrain, props or traps): the acid flask the scientists throw is the little green test tube in the art (4 tumbling frames)
		"copies": {"projectiles/acid_flask/spin.png": "4 Animated objects/Capsule.png",
			# The mid-boss room's door (its closed look; opening, it retracts into the ceiling): the door post with the red warning light
			"traps/arena_door.png": "3 Objects/Door3.png"},
		# Acid splash (when a scientist's acid flask lands): 72×72 per frame, 6 frames
		"effects": {"acid_splash": "4 Animated objects/Acid2.png", "acid_drip": "4 Animated objects/Acid1.png"},
		"props": {
			# Only **the fully shattered** capsule (7) is used as a prop: intact, cracked and half shattered are all stages that still block the way,
			# and used as props players could not tell which can be broken and which can already be walked through (things that look the same must follow the same rules)
			"capsule_shards": ("3 Objects/Capsule7.png", 1),
			"chair": ("3 Objects/Chair1.png", 1),
			"chair2": ("3 Objects/Chair3.png", 1),
			"door": ("3 Objects/Door1.png", 1),
			"door2": ("3 Objects/Door2.png", 1),
			"monitor": ("3 Objects/Monitor1.png", 1),
			"monitor2": ("3 Objects/Monitor4.png", 1),
			"monitor3": ("3 Objects/Monitor7.png", 1),
			"table": ("3 Objects/Table1.png", 1),
			"table2": ("3 Objects/Table2.png", 1),
			"grass": ("3 Objects/Grass1.png", 1),
			"grass2": ("3 Objects/Grass4.png", 1),
			"web": ("3 Objects/Web1.png", 1),
			"web2": ("3 Objects/Web4.png", 1),
			"tube": ("3 Objects/Tube_01.png", 1),
			"tube_valve": ("3 Objects/Tube_06.png", 1),
			# Animated: generators, valves, scanners, cameras. No Card / Money (they look like pickups)
			"generator": ("4 Animated objects/Generator.png", 4),
			"valve": ("4 Animated objects/Valve.png", 4),
			"scanner": ("4 Animated objects/Scanner.png", 6),
			"camera": ("4 Animated objects/Camera.png", 6),
		},
	},
	# Stage 2: industrial zone. The tiles are 81 separate files, number = row × 9 + column + 1.
	# **Backdrop layer 1 is the base colour, not the sky**: layer 2 is the sky (only drawn down to the horizon at y=247),
	# and below the horizon layer 1's haze shows, so neither layer is hazed.
	"industrial": {
		"pack": "industrial-zone-tileset",
		"out": "industrial",
		"tiles": "1 Tiles/IndustrialTile_%02d.png",
		# The three thin strips only have the top half drawn; crop away the blank rows below, or the nine-slice would treat the blank as an edge too
		"terrain": {"ground": [[5], [14]], "ledge": {"tiles": [[77, 78, 79]], "crop": 16}, "stone": [[36]]},
		"backdrop_dir": "2 Background",
		"backdrop": {"base": "1", "sky": "2", "far": "3", "mid": "4", "near": "5"},
		# **Traps** (added in 2026-10): the hydraulic press (`Hammer.png`, a piston hanging from above) and the blast gate (`Entry.png`).
		# Both are 8 frames × 32×64, output as is; the press also takes row 2 of frame 0 as the piston rod, tiled vertically up to the ceiling.
		"traps": {"press": "4 Animated objects/Hammer.png", "gate": "4 Animated objects/Entry.png",
			# Breakable crate (2026-10): 8 frames, intact → more broken with each hit → falling apart
			"chest": "4 Animated objects/Chest.png"},
		# Tiles for layered stages (2026-10): the 81 tiles laid out as is by number into one 9×9 atlas, taken by number by `TileArt`.
		# Which tile each cell uses is picked by shape in `map_build.py`, not here
		"tile_atlas": {"count": 81, "columns": 9},
		# Ladder: `Ladder1` is the middle section, `Ladder3` the stretch of rail sticking out above the floor (drawn on top of the ladder)
		"ladder": {"middle": "3 Objects/Ladder1.png", "top": "3 Objects/Ladder3.png"},
		"trap_rods": {"press_rod": ("4 Animated objects/Hammer.png", 2)},
		"haze": {"base": 0.0, "sky": 0.0, "far": 0.62, "mid": 0.5, "near": 0.38},
		"props": {
			"barrel": ("3 Objects/Barrel1.png", 1),
			"barrel_rust": ("3 Objects/Barrel3.png", 1),
			"box": ("3 Objects/Box1.png", 1),
			"box_open": ("3 Objects/Box3.png", 1),
			"crate": ("3 Objects/Box7.png", 1),
			"board": ("3 Objects/Board1.png", 1),
			"fence": ("3 Objects/Fence1.png", 1),
			"fence_end": ("3 Objects/Fence3.png", 1),
			# The middle section of railings (Fence1 left end, Fence2 middle, Fence3 right end, 32 wide each): layered stages put a row together along floor edges
			"fence_mid": ("3 Objects/Fence2.png", 1),
			# The digits of number signs on walls (32×36), laid on the purple disc joints — the "4" and "3" on the promo art's wall
			"digit_0": ("3 Objects/0.png", 1), "digit_1": ("3 Objects/1.png", 1),
			"digit_2": ("3 Objects/2.png", 1), "digit_3": ("3 Objects/3.png", 1),
			"digit_4": ("3 Objects/4.png", 1), "digit_5": ("3 Objects/5.png", 1),
			"digit_6": ("3 Objects/6.png", 1), "digit_7": ("3 Objects/7.png", 1),
			"digit_8": ("3 Objects/8.png", 1), "digit_9": ("3 Objects/9.png", 1),
			"warning": ("3 Objects/Pointer1.png", 1),
			"ladder": ("3 Objects/Ladder1.png", 1),
			"locker": ("3 Objects/Locker1.png", 1),
			"extinguisher": ("3 Objects/Fire-extinguisher1.png", 1),
			"bench": ("3 Objects/Bench.png", 1),
			"bucket": ("3 Objects/Bucket.png", 1),
			"sign": ("3 Objects/Pointer1.png", 1),
			"flag": ("3 Objects/Flag.png", 1),
			"screen": ("4 Animated objects/Screen1.png", 4),
			"conveyor": ("4 Animated objects/Transporter1.png", 4),
		},
	},
}
# ---------------------------------------------------------------- Bar street building fronts
#
# The row of buildings along the street in the promo art (brick walls, windows, shutters, awnings) **is not provided finished in the art pack**, only the tiles to build them (numbers 51~100
# and the blue striped awning at the top right). Here they are assembled by recipe into whole buildings, output as props (`props/facade_N.png`),
# and placed furthest back along the ground when the stage is generated (`facades` in `level_build.py`) — **display only**, by the same rules as other props.
#
# A recipe goes top to bottom one cell per tile, cells separated by spaces, `+` stacks on top (window + boards, brick wall + drainpipe).
# The letters are in `FACADE_TILES`, `.` is empty (for uneven rooflines). The bottom row touches the ground.
#
# **Buildings only use the grey wavy-edged awnings, not the blue striped ones**: the blue striped ones are the ledges you can stand on in the stage (`ledge`),
# and a row of identical ones on the building fronts would leave players unable to tell which ones hold (obvious at a glance in the first version's screenshots).
# Likewise the whole building front is **darkened a step** (`FACADE_SHADE`), so it recedes behind the things you can stand on and that block bullets.
FACADE_SHADE = 0.75
FACADE_TILES = {
	"P": 76,                      # Rooftop parapet (joins itself)
	"B": 60, "c": 70, "k": 80, "x": 90, "z": 100,   # Brick wall, the last four with cracks
	"W": 54, "C": 64, "T": 72, "D": 71, "S": 73, "N": 84, "E": 63,   # Windows: four panes / curtains / two panes / dark / with a sign / screen / dark hole
	"-": 51, "_": 53,             # The band between storeys / plain wall
	"A": 97, "a": 98,             # Arched shopfront (with a curtain)
	"U": 86, "u": 96, "O": 55, "o": 65,   # Shutter / door (two cells, top and bottom)
	"1": 81, "2": 82, "3": 83,    # Grey wavy-edged awning (left, middle, right)
	"b": 57, "d": 68,             # Boards nailed over a window
	"#": 77, "%": 88,             # Security bars
	"i": 89, "l": 79,             # Drainpipe
	"t": 91, "r": 93,             # Café table, chair
}

BAR_FACADES = {
	"facade_1": [                 # Café: awning, tables by the door
		"P P P P P",
		"B W B C B",
		"k B T B c",
		"- - - - -",
		"B+1 E+2 E+2 E+2 B+3",
		"B A a+t A B",
	],
	"facade_2": [                 # The tall one: a drainpipe down one side, some windows boarded up
		". P P P .",
		"P B B B P",
		"B+i W C+# W+b B",
		"B+i T B W x",
		"c+i W+d B C B",
		"- - - - -",
		"B+i U u U B",
	],
	"facade_3": [                 # The narrow little bar: grey awning
		"P P P",
		"B S B",
		"_ W _",
		"B+1 B+2 B+3",
		"B A B",
	],
	"facade_4": [                 # The closed shop: shutters, security bars
		"P P P P P P",
		"B D+% B D+# B z",
		"k B W+b B W k",
		"- - - - - -",
		"B U u U u B",
	],
	"facade_5": [                 # A shopfront on the ground floor, flats upstairs
		". . P P P P",
		"P P B C B B",
		"B W B T B+i x",
		"B C k W B+i B",
		"- - - - - -",
		"B+1 N+2 O+2 N+2 N+2 B+3",
		"B N o+r N A B",
	],
	"facade_6": [                 # A stretch of low wall, the gap between buildings
		"P P P P",
		"B c B+l k",
		"B T B+l W",
		"B+1 B+2 B+2 B+3",
		"B A a B",
	],
}


## The backdrop art is only 324 tall while the view is 360 — **there is nothing below the ground line**. Normally the ground covers it,
## but once a stage has pits, the clear colour shows through there, looking like a black brick.
## When generating, each layer's bottom row is repeated down to this height, so what you see in a pit is the backdrop continuing.
BACKDROP_HEIGHT = 360
# How much to mix towards the sky colour (0 = as is). Both art sets have the same sky colour.
HAZE_COLOR = (204, 226, 225)


def haze(pixels, amount):
	if amount <= 0.0:
		return pixels
	return [[tuple(int(round(c[i] + (HAZE_COLOR[i] - c[i]) * amount)) for i in range(3)) + (c[3],) if c[3] > 8 else c
		for c in row] for row in pixels]


def extend_down(pixels, height):
	"""Repeat the bottom row down to height. The art only reaches the horizon, and pits have to show the backdrop continuing."""
	if len(pixels) >= height:
		return pixels
	out = [list(row) for row in pixels]
	last = pixels[len(pixels) - 1]
	while len(out) < height:
		out.append(list(last))
	return out


def load_tile(zone, pack, atlas, spec):
	"""Take a tile. For atlases `spec` is (row, column), for one file per tile it is the number."""
	if atlas is not None:
		ty, tx = spec
		return sb.cut(atlas, tx * TILE, ty * TILE, TILE, TILE)
	_, _, pixels = sb.read_png(os.path.join(pack, *(zone["tiles"] % spec).split("/")))
	return pixels


def build_zone(key, write):
	zone = ZONES[key]
	pack = os.path.join(ART, zone["pack"])
	out = os.path.join(SKINS, zone["out"])
	if not os.path.isdir(pack):
		sys.exit("Cannot find the terrain art %s (it is not in the repo, unpack it in yourself)" % os.path.normpath(pack))
	atlas = None
	if "atlas" in zone:
		_, _, atlas = sb.read_png(os.path.join(pack, zone["atlas"]))
	print("== %s (%s) ==" % (key, zone["pack"]))
	print("Terrain:")
	for name, spec in zone["terrain"].items():
		rows = spec["tiles"] if isinstance(spec, dict) else spec
		art = sb.blank(TILE * len(rows[0]), TILE * len(rows))
		for r, row in enumerate(rows):
			for c, tile in enumerate(row):
				sb.blit(art, load_tile(zone, pack, atlas, tile), c * TILE, r * TILE, name)
		if isinstance(spec, dict) and "crop" in spec:
			art = art[: spec["crop"]]
		if write:
			sb.write_png(os.path.join(out, "terrain", name + ".png"), art)
		print("  terrain/%s.png  %dx%d" % (name, len(art[0]), len(art)))
	if "wall" in zone:
		print("Backdrop (the assembled inner wall):")
		for name, art in build_wall(zone, pack).items():
			if write:
				sb.write_png(os.path.join(out, "backdrop", name + ".png"), art)
			print("  backdrop/%s.png  %dx%d" % (name, len(art[0]), len(art)))
	if "backdrop" in zone:
		print("Backdrop:")
	for name, number in zone.get("backdrop", {}).items():
		source = os.path.join(pack, *zone["backdrop_dir"].split("/"), number + ".png")
		width, height, pixels = sb.read_png(source)
		art = extend_down(haze(pixels, zone["haze"][name]), BACKDROP_HEIGHT)
		if write:
			sb.write_png(os.path.join(out, "backdrop", name + ".png"), art)
		print("  backdrop/%s.png  %dx%d (art %dx%d, extended down to the bottom of the view)  hazed towards the sky by %d%%"
			% (name, len(art[0]), len(art), width, height, zone["haze"][name] * 100))
	if "lighting" in zone:
		rel, shrink = zone["lighting"]
		width, height, pixels = sb.read_png(os.path.join(pack, *rel.split("/")))
		art = [[pixels[y][x] for x in range(0, width, shrink)] for y in range(0, height, shrink)]
		if write:
			sb.write_png(os.path.join(out, "lighting", "glow.png"), art)
		print("Lighting:")
		print("  lighting/glow.png  %dx%d (art %dx%d)" % (len(art[0]), len(art), width, height))
	if "tile_atlas" in zone:
		spec = zone["tile_atlas"]
		count, columns = spec["count"], spec["columns"]
		rows = (count + columns - 1) // columns
		atlas = sb.blank(columns * TILE, rows * TILE)
		for n in range(1, count + 1):
			tile = load_tile(zone, pack, None, n)
			sb.blit(atlas, tile, ((n - 1) % columns) * TILE, ((n - 1) // columns) * TILE, "tile %d" % n)
		if write:
			sb.write_png(os.path.join(out, "tiles", "atlas.png"), atlas)
		print("Tile atlas:")
		print("  tiles/atlas.png  %dx%d (%d tiles)" % (columns * TILE, rows * TILE, count))
	if "ladder" in zone:
		print("Ladder:")
		# Cropped left and right to the columns of the middle section that actually have content (the industrial one is 32 wide with the rails only in the left 23, so drawn centred it would lean to one side),
		# and the rail on top is cropped to the same columns so the two line up
		_, _, mid = sb.read_png(os.path.join(pack, *zone["ladder"]["middle"].split("/")))
		cols = [x for x in range(len(mid[0])) if any(row[x][3] > 8 for row in mid)]
		left, right = cols[0], cols[-1] + 1
		for part, rel in zone["ladder"].items():
			width, height, pixels = sb.read_png(os.path.join(pack, *rel.split("/")))
			pixels = [row[left:right] for row in pixels]
			if part == "top":
				# The rail only has the lower stretch drawn: crop away the blank rows above so the bottom touches the floor
				rows = [y for y, row in enumerate(pixels) if any(c[3] > 8 for c in row)]
				pixels = pixels[rows[0]:]
			name = "ladder" if part == "middle" else "ladder_top"
			if write:
				sb.write_png(os.path.join(out, "terrain", name + ".png"), pixels)
			print("  terrain/%s.png  %dx%d" % (name, len(pixels[0]), len(pixels)))
	if "traps" in zone:
		print("Traps:")
		for name, rel in zone["traps"].items():
			width, height, pixels = sb.read_png(os.path.join(pack, *rel.split("/")))
			if write:
				sb.write_png(os.path.join(out, "traps", name + ".png"), pixels)
			print("  traps/%s.png  %dx%d (%d frames)" % (name, width, height, width // 32))
		for name, (rel, row) in zone.get("trap_rods", {}).items():
			_, _, pixels = sb.read_png(os.path.join(pack, *rel.split("/")))
			art = [pixels[row][0:32]]
			if write:
				sb.write_png(os.path.join(out, "traps", name + ".png"), art)
			print("  traps/%s.png  32x1" % name)
	for target, rel in zone.get("copies", {}).items():
		width, height, pixels = sb.read_png(os.path.join(pack, *rel.split("/")))
		if write:
			sb.write_png(os.path.join(out, *target.split("/")), pixels)
		print("  %s  %dx%d" % (target, width, height))
	for name, rel in zone.get("capsules", {}).items():
		width, height, pixels = sb.read_png(os.path.join(pack, *rel.split("/")))
		if write:
			sb.write_png(os.path.join(out, "traps", name + ".png"), pixels)
		print("  traps/%s.png  %dx%d" % (name, width, height))
	if "effects" in zone:
		print("Effects:")
		for name, rel in zone["effects"].items():
			width, height, pixels = sb.read_png(os.path.join(pack, *rel.split("/")))
			if write:
				sb.write_png(os.path.join(out, "effects", name + ".png"), pixels)
			print("  effects/%s.png  %dx%d (%d frames)" % (name, width, height, width // height))
	if "facades" in zone:
		print("Building fronts:")
		for name, recipe in globals()[zone["facades"]].items():
			art = facade(zone, pack, recipe)
			if write:
				sb.write_png(os.path.join(out, "props", name + ".png"), art)
			print("  props/%s.png  %dx%d" % (name, len(art[0]), len(art)))
	print("Props:")
	for name, (rel, frames) in sorted(zone["props"].items()):
		width, height, pixels = sb.read_png(os.path.join(pack, *rel.split("/")))
		if write:
			sb.write_png(os.path.join(out, "props", name + ".png"), pixels)
		print("  props/%s.png  %dx%d%s" % (name, width, height,
			"  %d frames" % frames if frames > 1 else ""))


def build_wall(zone, pack):
	"""Assemble the wall behind the shaft, returning {layer name: pixels}.

	The `wall` layer: brick walls with tiles picked at random by weight, darkened;
	the `pipes` layer: a few vertical pipes, the rest transparent.

	**Both layers have to tile vertically without seams** (Parallax2D repeats them vertically): one tile per cell, each independent,
	so joining the top and bottom edges of the image is the same as joining any two rows in the middle.
	A hand-written linear congruential generator with a fixed seed: the output goes into the repo, so another machine has to generate an identical file."""
	spec = zone["wall"]
	cols, rows = spec["cols"], spec["rows"]
	state = [spec["seed"]]

	def roll(n):
		state[0] = (state[0] * 1103515245 + 12345) & 0x7FFFFFFF
		return state[0] % n

	def shaded(px, amount):
		return [[tuple(int(round(p[i] * amount)) for i in range(3)) + (p[3],) for p in row] for row in px]

	bricks = spec["bricks"]
	total = sum(w for _, w in bricks)
	tiles = {}

	def tile(n):
		if n not in tiles:
			tiles[n] = load_tile(zone, pack, None, n)
		return tiles[n]

	wall = sb.blank(cols * TILE, rows * TILE)
	for r in range(rows):
		for c in range(cols):
			pick = roll(total)
			for number, weight in bricks:
				if pick < weight:
					sb.blit(wall, tile(number), c * TILE, r * TILE, "wall")
					break
				pick -= weight
	wall = shaded(wall, spec["shade"])

	pipes_spec = spec["pipes"]
	pipes = sb.blank(cols * TILE, rows * TILE)
	for c, number in zip(pipes_spec["columns"], pipes_spec["tiles"]):
		for r in range(rows):
			sb.blit(pipes, tile(number), c * TILE, r * TILE, "pipes")
	pipes = shaded(pipes, pipes_spec["shade"])
	return {"wall": wall, "pipes": pipes}


def facade(zone, pack, recipe):
	"""Assemble a building by recipe: one tile per cell, `+` stacks on top, `.` stays empty."""
	rows = [line.split() for line in recipe]
	wide = len(rows[0])
	for r, row in enumerate(rows):
		if len(row) != wide:
			sys.exit("Row %d of a facade recipe has %d cells while the other rows have %d" % (r + 1, len(row), wide))
	art = sb.blank(TILE * wide, TILE * len(rows))
	for r, row in enumerate(rows):
		for c, cell in enumerate(row):
			if cell == ".":
				continue
			for part in cell.split("+"):
				if part not in FACADE_TILES:
					sys.exit("Unknown letter in a facade recipe: %s" % part)
				tile = load_tile(zone, pack, None, FACADE_TILES[part])
				sb.blit(art, tile, c * TILE, r * TILE, "facade")
	return [[tuple(int(round(p[i] * FACADE_SHADE)) for i in range(3)) + (p[3],) for p in row] for row in art]


def main():
	write = "--check" not in sys.argv
	only = [a for a in sys.argv[1:] if not a.startswith("--")]
	for key in (only if only else ZONES):
		if key not in ZONES:
			sys.exit("No such zone: %s (available: %s)" % (key, ", ".join(ZONES)))
		build_zone(key, write)


if __name__ == "__main__":
	main()
