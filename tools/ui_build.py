"""Generates the UI resources from the gui art pack, output to skins/cyberpunk/ui/.

    python tools/ui_build.py

It generates four things:

1. **Bitmap fonts** (`font.png` + `font.fnt` for titles, `font_small.*` for body text): the art pack's glyphs are one 14×14 png per character
   (`10 Font/images/1_01..1_63`, white background + black strokes); here the **strokes** are cut out and assembled into one atlas,
   then an AngelCode BMFont `.fnt` is written, which Godot imports directly as a FontFile, so the UI can use Labels as usual.
   The cut-out glyphs are white and tinted in the UI with `modulate`.
2. **Window nine-slice** (`panel.png`): the 3×3 pieces at the top left of `1 Frames` assembled into one 96×96,
   with every NinePatchRect patch margin set to 32.
3. **Stat icons** (the four like `stat_life.png`): four picked from `9 Other/3 Skill icons`, white silhouettes tinted in the UI.
4. **Small parts**: `plus.png` for spending points, the menu cursor `cursor.png`.

The UI is always in English capitals: the glyphs only have A–Z, 0–9 and some symbols, no Chinese characters (see CLAUDE.md).
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import skin_build as sb

GUI = os.path.join(HERE, "..", "art_in", "default", "gui")
OUT = os.path.join(HERE, "..", "skins", "cyberpunk", "ui")

# The order of the glyph files: 1_01..1_26 are A..Z, 1_27..1_36 are 0..9, and symbols follow.
# The symbols were identified one by one from the images (`tools/ui_build.py --glyphs` prints them again for comparison).
LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
SYMBOLS = ".,'+-=:\"#|\/()[]{}!<>?"
CELL = 14
## A smaller set for body text: 14-tall glyphs take too much room at 640×360 (a line of text is taller than a character's head),
## so they are shrunk to 10 tall by nearest neighbour and assembled into another atlas. **The engine is not left to scale them** — a bitmap font is only sharp at the size it was made,
## and non-integer scaling blurs. Titles still use the 14 set scaled up by whole numbers.
SMALL = 10
## How many pixels between characters.
TRACKING = 1
## How wide a space is.
SPACE = 5
## How tall a line is (the glyphs are 14 tall, with a little room above and below).
LINE_HEIGHT = 16
## Baseline: how many pixels above the glyph's bottom edge. Labels lay out by baseline, and all glyphs are the same height, so it is the glyph height.
BASE = 14


def glyph_files():
    """Character → glyph file name."""
    table = {}
    for i, ch in enumerate(LETTERS):
        table[ch] = "1_%02d.png" % (i + 1)
    for i, ch in enumerate(SYMBOLS):
        table[ch] = "1_%02d.png" % (len(LETTERS) + i + 1)
    return table


def ink_of(path):
    """Cut out the strokes: the glyphs are black on white, so keep the black, paint it white and throw away the white background. Returns (pixels, left, right)."""
    width, height, pixels = sb.read_png(path)
    out = sb.blank(width, height)
    xs = []
    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[y][x]
            if a > 8 and r + g + b < 384:
                out[y][x] = (255, 255, 255, 255)
                xs.append(x)
    if not xs:
        return out, 0, width - 1
    return out, min(xs), max(xs)


def shrink(art, left, wide, cell):
    """Shrink a glyph by nearest neighbour to cell tall (width in proportion). It takes the source pixel at each target pixel's centre,
    so 3px thick strokes become 2px after shrinking and do not break."""
    if cell == CELL:
        return [[art[y][left + x] for x in range(wide)] for y in range(CELL)], wide
    out_wide = max(1, round(wide * cell / float(CELL)))
    out = []
    for y in range(cell):
        sy = min(CELL - 1, int((y + 0.5) * CELL / cell))
        out.append([art[sy][left + min(wide - 1, int((x + 0.5) * wide / out_wide))]
            for x in range(out_wide)])
    return out, out_wide


def build_font(write, cell=CELL, name="font"):
    """Assemble a glyph atlas + an AngelCode `.fnt`. `cell` is the glyph height; 14 is the art's original size,
    and the smaller set is shrunk by nearest neighbour (see `SMALL`)."""
    table = glyph_files()
    glyphs = []
    for ch in sorted(table):
        art, left, right = ink_of(os.path.join(GUI, "10 Font", "images", table[ch]))
        small, wide = shrink(art, left, right - left + 1, cell)
        glyphs.append((ch, small, wide))
    total = sum(g[2] + 1 for g in glyphs)
    atlas = sb.blank(total, cell)
    lines = []
    x = 0
    scale = cell / float(CELL)
    for ch, art, wide in glyphs:
        for y in range(cell):
            for sx in range(wide):
                atlas[y][x + sx] = art[y][sx]
        lines.append('char id=%d x=%d y=0 width=%d height=%d xoffset=0 yoffset=0 xadvance=%d page=0 chnl=15'
            % (ord(ch), x, wide, cell, wide + TRACKING))
        x += wide + 1
    lines.append('char id=32 x=0 y=0 width=0 height=0 xoffset=0 yoffset=0 xadvance=%d page=0 chnl=15'
        % max(2, round(SPACE * scale)))
    header = [
        'info face="CyberpunkPixel%d" size=%d bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=1,1' % (cell, cell),
        'common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0'
            % (max(cell + 1, round(LINE_HEIGHT * scale)), cell, total, cell),
        'page id=0 file="%s.png"' % name,
        'chars count=%d' % len(lines),
    ]
    if write:
        sb.write_png(os.path.join(OUT, "%s.png" % name), atlas)
        with open(os.path.join(OUT, "%s.fnt" % name), "w", newline="\n") as f:
            f.write("\n".join(header + lines) + "\n")
    print("  %s.png  %d×%d, %d glyphs" % (name, total, cell, len(lines)))


def build_panel(write):
    """The 3×3 at the top left of `1 Frames` (Frame_01..03 / 10..12 / 19..21) assembled into one 96×96 nine-slice,
    and the middle cell saved separately (`panel_fill.png`) — windows first tile it over the whole area, then lay the frame on top,
    or a gap would show between the inner edge of the frame image and the middle cell."""
    TILE = 32
    out = sb.blank(TILE * 3, TILE * 3)
    for row in range(3):
        for col in range(3):
            number = 1 + row * 9 + col
            _, _, art = sb.read_png(os.path.join(GUI, "1 Frames", "Frame_%02d.png" % number))
            sb.blit(out, art, col * TILE, row * TILE, "panel")
    _, _, middle = sb.read_png(os.path.join(GUI, "1 Frames", "Frame_11.png"))
    if write:
        sb.write_png(os.path.join(OUT, "panel.png"), out)
        sb.write_png(os.path.join(OUT, "panel_fill.png"), middle)
    print("  panel.png  96×96 (nine-slice edge 32)")
    print("  panel_fill.png  32×32 (the middle cell, used as backing)")


## Which icon each of the four stats uses (the numbers in `9 Other/3 Skill icons`). All white silhouettes, tinted in the UI.
STAT_ICONS = {"life": 16, "attack": 15, "defense": 18, "speed": 2}


## How much to widen the title plate and from which column: the art is 285 wide, and its inner panel cannot hold "ZONE BREAKER" at 28px (about 295 wide, after the 2026-11 naming).
## Columns 126..169 are identical in every row (that stretch of the plate has no ornament), so repeating one of them makes the plate wider without moving the ornament.
## The text is a bitmap font, only sharp at the two sizes 14 / 28, so the plate changes, not the text.
TITLE_WIDEN = 56
TITLE_PLAIN_COLUMN = 147


def build_title(write):
    """The title plate on the main menu (`5 Logo/Logo1`, 285×115, the game's name written in the inner panel), widened in the middle by `TITLE_WIDEN`."""
    _, _, art = sb.read_png(os.path.join(GUI, "5 Logo", "Logo1.png"))
    for row in art:
        assert row[126:170] == [row[126]] * 44, "Columns 126..169 of the title plate are no longer one repeated column; did the art change?"
    art = [row[:TITLE_PLAIN_COLUMN] + [row[TITLE_PLAIN_COLUMN]] * TITLE_WIDEN + row[TITLE_PLAIN_COLUMN:]
           for row in art]
    if write:
        sb.write_png(os.path.join(OUT, "title_plate.png"), art)
    print("  title_plate.png  %d×%d" % (len(art[0]), len(art)))


## Gear icons: the key is the gear resource's file name (`weapons/rifle.tres` → `rifle`),
## the value is which image in the art (`2 Guns/Icon15_NN` are guns, `armor/Icon24_NN` armour).
GEAR_ICONS = {
    "rifle": "2 Guns/Icon15_01.png",
    "grenade": "2 Guns/Icon15_26.png",
    # Guns sold in the shop (the WEAPONS table in `tools/gear_build.py` refers to these by name)
    "rifle_mk2": "2 Guns/Icon15_07.png",
    "plasma_rifle": "2 Guns/Icon15_19.png",
    "cluster_bomb": "2 Guns/Icon15_31.png",
}
## Armour icons: `armor/Icon24_NN.png` **5 pieces per set, head/body/legs/feet/hands**, one colour scheme per set.
## The keys have to match how `gear_<tier>_<slot>` is spelled in `gear_build.py`.
ARMOR_SETS = [("scrap", 1), ("combat", 2), ("titan", 3)]
ARMOR_PARTS = ["head", "body", "legs", "feet", "hands"]
for _name, _set in ARMOR_SETS:
    for _i, _part in enumerate(ARMOR_PARTS):
        GEAR_ICONS["%s_%s" % (_name, _part)] = "armor/Icon24_%02d.png" % ((_set - 1) * 5 + _i + 1)


def build_gear(write):
    for name, path in GEAR_ICONS.items():
        _, _, art = sb.read_png(os.path.join(HERE, "..", "art_in", "default", path))
        if write:
            sb.write_png(os.path.join(OUT, "gear_%s.png" % name), art)
        print("  gear_%s.png" % name)


def build_bits(write):
    for name, number in STAT_ICONS.items():
        _, _, art = sb.read_png(os.path.join(GUI, "9 Other", "3 Skill icons", "Skillicon7_%02d.png" % number))
        if write:
            sb.write_png(os.path.join(OUT, "stat_%s.png" % name), art)
        print("  stat_%s.png" % name)
    _, _, plus = sb.read_png(os.path.join(GUI, "7 Numbers", "plus.png"))
    if write:
        sb.write_png(os.path.join(OUT, "plus.png"), plus)
    print("  plus.png")
    # Menu cursor: a small right-pointing triangle drawn by us, 7×7
    cursor = sb.blank(7, 7)
    for i in range(4):
        for j in range(2 * (4 - i) - 1):
            cursor[3 - (4 - i) + 1 + j][i] = (255, 255, 255, 255)
    if write:
        sb.write_png(os.path.join(OUT, "cursor.png"), cursor)
    print("  cursor.png")


def main():
    write = "--check" not in sys.argv
    if not os.path.isdir(GUI):
        sys.exit("Cannot find the gui art pack %s (it is not in the repo, unpack it in yourself)" % os.path.normpath(GUI))
    if write and not os.path.isdir(OUT):
        os.makedirs(OUT)
    print("UI assets:")
    build_font(write)
    build_font(write, SMALL, "font_small")
    build_panel(write)
    build_title(write)
    build_gear(write)
    build_bits(write)
    print("\nDone." + ("" if write else " (--check: no files written)"))


if __name__ == "__main__":
    main()
