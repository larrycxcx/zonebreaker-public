"""从 gui 素材包生成界面用的资源，输出到 skins/cyberpunk/ui/。

    python tools/ui_build.py

生成四样东西：

1. **位图字体**（`font.png` + `font.fnt` 标题用、`font_small.*` 正文用）：素材包的字模是一个字一张 14×14 的 png
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
## 正文那套小一号的：14 高的字模在 640×360 上太占地方（一行字比角色的脑袋还高），
## 按最近邻缩到 10 高再拼一张。**不让引擎去缩**——位图字体只有做出来的那个尺寸是清楚的，
## 非整数倍缩放会糊。标题照旧用 14 那套放大整数倍。
SMALL = 10
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


def shrink(art, left, wide, cell):
    """把一个字模按最近邻缩到 cell 高（横向同比例）。取每个目标像素中心对应的源像素，
    所以 3px 粗的笔画缩完是 2px，不会断。"""
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
    """拼一张字模图集 + 一个 AngelCode `.fnt`。`cell` 是字高，14 是素材原尺寸，
    小一号的那套按最近邻缩过（见 `SMALL`）。"""
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
    print("  %s.png  %d×%d，%d 个字" % (name, total, cell, len(lines)))


def build_panel(write):
    """`1 Frames` 左上角 3×3（Frame_01..03 / 10..12 / 19..21）拼成一张 96×96 的九宫格，
    另外把正中间那一格单独存一份（`panel_fill.png`）——窗口要先用它铺满整块、再把边框盖上去，
    不然边框图的内沿和中间那格之间会露出一圈缝。"""
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
    print("  panel.png  96×96（九宫格边 32）")
    print("  panel_fill.png  32×32（中间那格，铺底用）")


## 四个属性用哪个图标（`9 Other/3 Skill icons` 里的编号）。都是白色剪影，界面里染色。
STAT_ICONS = {"life": 16, "attack": 15, "defense": 18, "speed": 2}


## 标题牌加宽多少、从哪一列加：素材 285 宽，里面那格装不下 28px 的「ZONE BREAKER」（约 295 宽，2026-11 定名后）。
## 第 126..169 列上下每一行都一模一样（牌子上那一段没有花纹），把其中一列重复插进去，牌子就变宽了、花纹不动。
## 字是位图字体，只有 14 / 28 两档是清楚的，所以改牌子不改字。
TITLE_WIDEN = 56
TITLE_PLAIN_COLUMN = 147


def build_title(write):
    """主菜单上那块标题牌（`5 Logo/Logo1`，285×115，游戏名写在里面那格），中间加宽 `TITLE_WIDEN`。"""
    _, _, art = sb.read_png(os.path.join(GUI, "5 Logo", "Logo1.png"))
    for row in art:
        assert row[126:170] == [row[126]] * 44, "标题牌第 126..169 列不再是同一列了，换素材了？"
    art = [row[:TITLE_PLAIN_COLUMN] + [row[TITLE_PLAIN_COLUMN]] * TITLE_WIDEN + row[TITLE_PLAIN_COLUMN:]
           for row in art]
    if write:
        sb.write_png(os.path.join(OUT, "title_plate.png"), art)
    print("  title_plate.png  %d×%d" % (len(art[0]), len(art)))


## 装备图标：键就是装备资源的文件名（`weapons/rifle.tres` → `rifle`），
## 值是素材里哪一张（`2 Guns/Icon15_NN` 是枪，`armor/Icon24_NN` 是防具）。
GEAR_ICONS = {
    "rifle": "2 Guns/Icon15_01.png",
    "grenade": "2 Guns/Icon15_26.png",
    # 商店里卖的枪（`tools/gear_build.py` 的 WEAPONS 表按名字引用这些）
    "rifle_mk2": "2 Guns/Icon15_07.png",
    "plasma_rifle": "2 Guns/Icon15_19.png",
    "cluster_bomb": "2 Guns/Icon15_31.png",
}
## 防具图标：`armor/Icon24_NN.png` **每套 5 件，头/身/腿/脚/手**，一套一个配色。
## 键要和 `gear_build.py` 里 `gear_<档位>_<部位>` 的拼法对上。
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
    build_font(write, SMALL, "font_small")
    build_panel(write)
    build_title(write)
    build_gear(write)
    build_bits(write)
    print("\n好了。" + ("" if write else "（--check：没有写文件）"))


if __name__ == "__main__":
    main()
