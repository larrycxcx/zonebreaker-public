# Drawing your own levels: pixel maps painted by colour

**One pixel = one cell in the game (16×16)**. The image must be **exactly 23 pixels tall** (one screen); the width is up to you but must be **even** (a screen is 40 pixels wide).
Any tool that can paint single pixels works (Aseprite, the Photoshop pencil, Windows Paint). **Turn anti-aliasing off** and save as PNG.

## Getting started

```bash
python tools/map_paint.py template          # art_src/maps/template.png: two screens wide, with ground, spawn point and exit already drawn
python tools/map_paint.py palette           # art_src/maps/palette.png: every colour in one strip, for the eyedropper
python tools/map_paint.py export 1 burrow art_src/maps/my_burrow.png   # or start from an existing segment
```

Existing segment names: stage 1 `park terraces burrow chasm fortress trench islands crossfire tunnel boss_room`,
stage 2 `yard gantry ambush press_hall settling alarm heights crossfire narrow boss_room`,
stage 3 `street awnings cellar drains brutes long_street rooftops hotel alley boss_room`.
`example_burrow.png` is the "burrow" segment of stage 1, exported — use it for reference.

## When you are done

```bash
python tools/map_paint.py check   art_src/maps/my_part.png --level 1   # prints it as text and runs the path-finding self-check
python tools/map_paint.py preview art_src/maps/my_part.png --level 1   # screenshots it with that stage's art, one image per screen
```

- `--level` decides **whose tiles, art and enemies are used** (enemy colours a~g mean different enemies in each stage, see below).
- `check` runs **the same self-check as the real stages**: from the spawn point, walking, jumping, dropping and climbing ladders — can you reach the exit / boss?
  Do the ladders connect to floors at both ends, is there a ceiling above each press, is each gate sealed above, does every enemy stand on something,
  does a charging enemy's path end in a pit... Anything that fails is listed line by line.
- If the image has **no spawn point or exit** (e.g. a segment exported from the middle of a stage), they are added at the lowest standable spot on the far left and far right,
  and the "no enemies on the first screen" rule is not checked.
- `preview` screenshots go to `art_src/maps/preview/` (not in the repo, regenerate any time). `check` runs first; nothing is captured if it fails.

## Colours

| Char | Colour | What it is |
|---|---|---|
| `.` | #FFFFFF | Empty (transparent counts as empty) |
| `#` | #000000 | Solid: ground / floor / wall (the zone's main material) |
| `%` | #808080 | Solid: second material (warning stripes / stone bricks / shutters) |
| `X` | #804000 | Solid: cover block (steel crate / boulder), draw it 2×2 |
| `=` | #0000FF | One-way platform: jump up through it from below, down + jump to drop through |
| `:` | #0080FF | One-way platform, second look (girder / stone ledge / wooden floor) |
| `H` | #FFFF00 | Ladder: 2 cells wide, from the upper floor (included) down to the lower floor (excluded) |
| `~` | #00FFFF | Conveyor belt moving right (only the industrial zone has art for it) |
| `-` | #008080 | Conveyor belt moving left |
| `P` | #FF00FF | Hydraulic press: fill all 2×4 (hangs from a ceiling, needs a floor under it) |
| `G` | #800080 | Blast gate: fill all 2×4 (must be sealed all the way up to a ceiling) |
| `K` | #FF8000 | Breakable crate: 2 cells wide, as many crates as cells stacked |
| `O` | #FF0000 | Explosive barrel: one cell |
| `!` | #C0C0C0 | Upright pipe / stone pillar in the background (decoration, does not block) |
| `@` | #00FF00 | Spawn point (feet on the cell below) |
| `>` | #008000 | Exit (feet on the cell below; required when there is no boss) |
| `B` | #FF80C0 | Boss |
| `a` | #FFA0A0 | Enemy a |
| `b` | #A0A0FF | Enemy b |
| `c` | #A0FFA0 | Enemy c |
| `d` | #FFFFA0 | Enemy d |
| `e` | #A0FFFF | Enemy e |
| `f` | #FFA0FF | Enemy f |
| `g` | #FFC878 | Enemy g |

Being off by a value or two is fine (paint programs sometimes do that when saving); anything further off is reported with the offending pixels listed.

**Who enemies a~g are in each stage:**

| | Stage 1 (green zone) | Stage 2 (industrial) | Stage 3 (bar street) |
|---|---|---|---|
| a | Patroller (level shots only) | Hangs up top, drops and charges | Knifeman (winds up, then lunges) |
| b | Burst gunner (shoots diagonally) | Charger | Gunman (shoots diagonally) |
| c | Long-range gunner (goes prone, shoots diagonally) | Gunman (shoots diagonally) | Swordsman (leaping slash) |
| d | Skater (charges) | Hammer man | Brute (blocks from the front) |
| e | Drone (zaps downward, flies) | Helicopter (drops bombs, flies) | Shark bot (shoots along the floor) |
| f | Grenade thrower | Suicide bot | Cannon cart (lobs grenades) |
| g | Turret (shoots diagonally) | — | — |

## Rules of thumb while drawing

- **Draw an enemy one cell above the cell it stands on** (an enemy on the ground goes on row 19, the ground is row 20); flyers go in the cell they hover in.
- Usual three layers: **upper floor on row 7, middle on row 13, ground on row 20**. Two floors 6 or more rows apart **cannot be jumped between** — only a ladder or a gap to drop through connects them. That is the skeleton of every detour.
- One jump goes **at most 4 rows up and 6 columns across**; a pit wider than 6 columns cannot be jumped.
- A charging enemy's path (each stage's "charger / lunger / leaper / brute / skater / suicide bot") **must not end in a pit** at either end;
  if one has to stand by a pit, build a 2-cell-high lip on the pit's edge.
- Just draw the cells: **decorations such as trees, bars and crates are scattered automatically**.

## Putting it into a real stage

Add a segment in `tools/level1_map.py` (or 2, 3):

```python
def my_part():
	cv = from_png("art_src/maps/my_part.png")
	cv.prop("tree_big", 10, 20)      # named decorations, pipes and railings go here (optional)
	return cv
```

Then add `my_part` to `SEGMENTS` and run `python tools/level_build.py 1` to build the stage.
