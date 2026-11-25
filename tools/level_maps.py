"""Grid maps (the kind `map_build.py` reads). A cell is 16 pixels, 23 rows tall; the legend is at the top of `map_build.py`.

A ruler for the columns (a digit every 10 cells), for lining up when copying:
          0         1         2         3
          0123456789012345678901234567890123456789
"""

# ---------------------------------------------------------------- The user's sketch (2026-10)
#
# The 5 points marked on the industrial zone promo art, turned into one screen:
# Spawn on the left of the upper layer. 1 = a solid block in the middle of the upper layer reaching from the top of the view down to the floor, **cannot be jumped over**.
# 2 = the upper floor breaks for 3 cells to its left, and walking on drops you to the middle layer.
# 4 = the ladder from the middle layer to the bottom layer. 3 = a diagonal-shooting 2-C on the right of the bottom layer; two presses hang over the right half of the middle layer,
# and that stretch of floor is one-way (=) — **the bottom layer enemy can shoot diagonally up through it, but people cannot jump up** (ground to middle floor 112, a jump 87).
# You can force your way through without going down to shoot it, but it is hard (the user decided: not forced).
# 5 = the ladder from the right end of the middle layer back up to the upper layer, with the exit on the right. Another 2-C guards the middle layer's exit.
DEMO_ENEMIES = {"c": "2_c"}
DEMO = [
	"................XXXXXXXXXX..............",  # 0   1: steel crates stacked to the top
	"................XXXXXXXXXX..............",  # 1
	"................XXXXXXXXXX..............",  # 2
	".....!!.....!!..XXXXXXXXXX..............",  # 3   two red and white chimneys
	".....!!.....!!..XXXXXXXXXX..............",  # 4
	".....!!.....!!..XXXXXXXXXX..............",  # 5
	"...@.!!.....!!..XXXXXXXXXX.............>",  # 6   spawn, exit (right, upper layer)
	"########...#########################HH##",  # 7   upper floor: the gap (2), the top of ladder 5
	"....................................HH..",  # 8   middle layer
	"......................P....P........HH..",  # 9   two presses
	"....................................HH..",  # 10
	"....................................HH..",  # 11
	"...............................c....HH..",  # 12  the guard at the middle layer's exit
	"~~~~~~~~~~~~~HH###================######",  # 13  middle floor: a conveyor on the left, the top of ladder 4, one-way under the presses
	"#####........HH....................#####",  # 14  bottom layer
	"#####........HH....................#####",  # 15
	"#####........HH....................#####",  # 16
	"#####........HH....................#####",  # 17
	"#####........HH....................#####",  # 18
	"#####........HH..............c.....#####",  # 19  3: the diagonal-shooting enemy
	"#####%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#####",  # 20  bottom layer ground: red warning stripes
	"#####%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#####",  # 21
	"#####%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#####",  # 22
]
## Props placed by name: (prop name, column, standing on which row). The rest are scattered automatically on indoor floors by `map_build.dress()`.
DEMO_PROPS = [
	("barrel", 14, 7),
	("screen", 2, 13), ("sign", 7, 13),
	("locker", 6, 20), ("locker", 8, 20), ("box", 17, 20), ("box_open", 19, 20), ("bucket", 33, 20),
]
## Decals (on walls) and railings (on floors). Pipes and number signs use coordinates in **32-pixel blocks** (a block = 2×2 cells), and only go indoors.
## pipes: a string of corners each, horizontal and vertical only; signs: (digit, block x, block y), drawn as a disc joint + digit;
## rails: (from column, to column, standing on row), a left end + middle + right end of 2 cells each.
DEMO_DECOR = {
	"pipes": [
		[(6, 4), (17, 4), (17, 5)],        # Middle layer: a horizontal pipe under the upper floor, turning down at the right end
		[(3, 8), (12, 8), (12, 7)],        # Bottom layer: a horizontal pipe, turning up at the right end
	],
	"signs": [(4, 9, 4), (3, 8, 8)],      # The "4" on the promo art's wall is in the middle layer, the "3" in the bottom layer
	"rails": [(26, 34, 7)],              # Right of the upper layer: a row of railings between block 1 and ladder 5
}
