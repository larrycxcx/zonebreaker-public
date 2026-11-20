"""生成 Boss 头像的像素占位图（16×16 PNG），输出到 skins/default/portraits/。

    python tools/portrait_gen.py

只用标准库。每个头像是一张字符画：一个字符一个像素，颜色见 PALETTE。
改头像就改这里的字符画再重新生成，不要手改 png。第 4 步换正式美术时整个替换掉。
"""
import os
import struct
import zlib

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "skins", "default", "portraits")

PALETTE = {
    ".": (22, 18, 20, 255),     # 背景
    "#": (140, 84, 36, 255),    # 脸（和场景里 Boss A 身体同色）
    "d": (88, 50, 20, 255),     # 暗部
    "h": (77, 84, 92, 255),     # 头盔
    "H": (120, 128, 138, 255),  # 头盔高光
    "v": (255, 77, 51, 255),    # 护目镜
    "w": (240, 235, 220, 255),  # 牙
    "b": (44, 54, 92, 255),     # 铁球
    "B": (96, 112, 150, 255),   # 铁球高光
    "r": (214, 62, 46, 255),    # 红环 / 头冠
    "m": (138, 160, 186, 255),  # 机甲外壳
    "M": (186, 204, 224, 255),  # 外壳高光
    "t": (150, 110, 60, 255),   # 天线
}

PORTRAITS = {
    "1_boss": [
        "................",
        "....hhhhhhhh....",
        "...hHHhhhhhhh...",
        "..hHhhhhhhhhhh..",
        "..hhhhhhhhhhhh..",
        "..hhhhhhhhhhhh..",
        "..hvvvvvvvvvvh..",
        "..#vvvvvvvvvv#..",
        "..############..",
        "..###d####d###..",
        "..############..",
        "..##dddddddd##..",
        "..##dwdwdwdwd#..",
        "...##dddddd##...",
        "....########....",
        "................",
    ],
    # Boss 2「机械操作员」：一个带红环的铁球，顶上一撮红色头冠。
    "2_boss": [
        "................",
        "......r..r......",
        ".....rr..rr.....",
        "....bbrrrrbb....",
        "...bBBbbbbbbb...",
        "..bBBbbbbbbbbb..",
        "..bBbbbbbbbbbb..",
        ".rrrrrrrrrrrrrr.",
        ".rrrrrwwrrrrrrr.",
        "..bbbbwrbbbbbb..",
        "..bbbbwwbbbbbb..",
        "..bbbbbbbbbbbb..",
        "...bbbbbbbbbb...",
        "....bbbbbbbb....",
        "......bbbb......",
        "................",
    ],
    # Boss 3「独轮机甲」：方头方脑的机体，顶上一根天线。
    "3_boss": [
        "................",
        ".......t........",
        "......t.........",
        "....mMMMmm......",
        "...mMMMMmmm.....",
        "..mMMMmmmmmm....",
        "..mMMmmmmmmm....",
        "..mmmrrmmmmm....",
        "..mmmrrmmmmm....",
        "..mmmmmmmmmm....",
        "...mmmmmmmm.....",
        "....mmmmmm......",
        "....mm..mm......",
        "...mm....mm.....",
        "................",
        "................",
    ],
    # 第五关中段小 Boss「变异枪手」：红色的大头盔，一条护目镜。
    "5_mid": [
        "................",
        "......rrrr......",
        ".....rrrrrr.....",
        "....rrrrrrrr....",
        "....rrrrrrrr....",
        "....rvvvvvvr....",
        "....rvvvvvvr....",
        "....rrrrrrrr....",
        "...mmrrrrrrmm...",
        "..mmMmmmmmmMmm..",
        "..mmmmmmmmmmmm..",
        "..mmm......mmm..",
        "................",
        "................",
        "................",
        "................",
    ],
    # 第五关 Boss「生化舱」：一个绿色的舱体，中间一只眼。
    "5_boss": [
        "................",
        ".....mmmmmm.....",
        "....mMMmmmmm....",
        "...mmbbbbbbmm...",
        "...mbbBBBBbbm...",
        "...mbBvvvvBbm...",
        "...mbBvwwvBbm...",
        "...mbBvvvvBbm...",
        "...mbbBBBBbbm...",
        "...mmbbbbbbmm...",
        "....mmmmmmmm....",
        ".....m.mm.m.....",
        "................",
        "................",
        "................",
        "................",
    ],
    # Boss 4「骷髅头」：一个白骷髅，两只红眼。
    "4_boss": [
        "................",
        ".....wwwwww.....",
        "....wwwwwwww....",
        "...wwwwwwwwww...",
        "...wwwwwwwwww...",
        "...w..ww..www...",
        "...w.rww.rwww...",
        "...w..ww..www...",
        "...wwww.wwwww...",
        "....wwwwwwww....",
        ".....w.w.w.w....",
        ".....wwwwwww....",
        "......w.w.w.....",
        "................",
        "................",
        "................",
    ],
}


def write_png(path: str, rows: list[str]) -> None:
    height, width = len(rows), len(rows[0])
    raw = b"".join(b"\x00" + b"".join(bytes(PALETTE[c]) for c in row) for row in rows)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, rows in PORTRAITS.items():
        assert all(len(r) == 16 for r in rows) and len(rows) == 16, name
        path = os.path.join(OUT_DIR, name + ".png")
        write_png(path, rows)
        print(f"{name:20s} -> {os.path.relpath(path)}")


if __name__ == "__main__":
    main()
