"""从 gui 素材包生成界面用的资源，输出到 skins/cyberpunk/ui/。

    python tools/ui_build.py

生成四样东西：

1. **位图字体**（`font.png` + `font.fnt`）：素材包的字模是一个字一张 14×14 的 png
   （`10 Font/images/1_01..1_63`，白底 + 黑色笔画），这里把**笔画**抠出来拼成一张图集，
   再写一个 AngelCode BMFont 的 `.fnt`，Godot 直接当 FontFile 导入，界面上就能照常用 Label 了。
   抠出来的字是白的，界面里用 `modulate` 染色。
2. **窗口九宫格**（`panel.png`）：`1 Frames` 左上角那 3×3 块拼成一张 96×96，
   NinePatchRect 的 patch margin 全填 32。
3. **属性图标**（`stat_life.png` 等四张）：`9 Other/3 Skill icons` 里挑的四个，白色剪影，界面里染色。
4. **小配件**：加点的 `plus.png`、菜单光标 `cursor.png`。

界面一律英文大写：字模只有 A–Z、0–9 和一些符号，没有汉字（见 CLAUDE.md）。
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import skin_build as sb

GUI = os.path.join(HERE, "..", "art_in", "default", "gui")
OUT = os.path.join(HERE, "..", "skins", "cyberpunk", "ui")

# 字模文件的顺序：1_01..1_26 是 A..Z，1_27..1_36 是 0..9，后面是符号。
# 符号那一段是照着图一个个认出来的（`tools/ui_build.py --glyphs` 可以再印一遍对照）。
LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
SYMBOLS = ".,'+-=:\"#|\/()[]{}!<>?"
CELL = 14
## 字与字之间留几像素。
TRACKING = 1
## 空格多宽。
SPACE = 5
## 一行多高（字模 14 高，上下各留一点）。
LINE_HEIGHT = 16
## 基线：字模底边往上几像素。Label 按基线排版，所有字等高所以就是字模高度。
BASE = 14


def glyph_files():
    """字符 → 字模文件名。"""
    table = {}
    for i, ch in enumerate(LETTERS):
        table[ch] = "1_%02d.png" % (i + 1)
    for i, ch in enumerate(SYMBOLS):
        table[ch] = "1_%02d.png" % (len(LETTERS) + i + 1)
    return table


def ink_of(path):
    """抠出笔画：字模是白底黑字，留下黑的、涂成白色，白底扔掉。返回 (像素, 左, 右)。"""
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


def build_font(write):
    table = glyph_files()
    glyphs = []
    for ch in sorted(table):
        art, left, right = ink_of(os.path.join(GUI, "10 Font", "images", table[ch]))
        glyphs.append((ch, art, left, right - left + 1))
    total = sum(g[3] + 1 for g in glyphs)
    atlas = sb.blank(total, CELL)
    lines = []
    x = 0
    for ch, art, left, wide in glyphs:
        for y in range(CELL):
            for sx in range(wide):
                atlas[y][x + sx] = art[y][left + sx]
        lines.append('char id=%d x=%d y=0 width=%d height=%d xoffset=0 yoffset=0 xadvance=%d page=0 chnl=15'
            % (ord(ch), x, wide, CELL, wide + TRACKING))
        x += wide + 1
    lines.append('char id=32 x=0 y=0 width=0 height=0 xoffset=0 yoffset=0 xadvance=%d page=0 chnl=15' % SPACE)
    header = [
        'info face="CyberpunkPixel" size=%d bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=1,1' % CELL,
        'common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0' % (LINE_HEIGHT, BASE, total, CELL),
        'page id=0 file="font.png"',
        'chars count=%d' % len(lines),
    ]
    if write:
        sb.write_png(os.path.join(OUT, "font.png"), atlas)
        with open(os.path.join(OUT, "font.fnt"), "w", newline="\n") as f:
            f.write("\n".join(header + lines) + "\n")
    print("  font.png  %d×%d，%d 个字" % (total, CELL, len(lines)))


def build_panel(write):
    """`1 Frames` 左上角 3×3（Frame_01..03 / 10..12 / 19..21）拼成一张 96×96 的九宫格。"""
    TILE = 32
    out = sb.blank(TILE * 3, TILE * 3)
    for row in range(3):
        for col in range(3):
            number = 1 + row * 9 + col
            _, _, art = sb.read_png(os.path.join(GUI, "1 Frames", "Frame_%02d.png" % number))
            sb.blit(out, art, col * TILE, row * TILE, "panel")
    if write:
        sb.write_png(os.path.join(OUT, "panel.png"), out)
    print("  panel.png  96×96（九宫格边 32）")


## 四个属性用哪个图标（`9 Other/3 Skill icons` 里的编号）。都是白色剪影，界面里染色。
STAT_ICONS = {"life": 16, "attack": 15, "defense": 18, "speed": 2}


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
    # 菜单光标：自己画一个朝右的小三角，7×7
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
        sys.exit("找不到 gui 素材包 %s（它不在仓库里，要自己解压进去）" % os.path.normpath(GUI))
    if write and not os.path.isdir(OUT):
        os.makedirs(OUT)
    print("界面素材：")
    build_font(write)
    build_panel(write)
    build_bits(write)
    print("\n好了。" + ("" if write else "（--check：没有写文件）"))


if __name__ == "__main__":
    main()
