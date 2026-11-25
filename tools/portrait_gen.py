"""Generates pixel placeholder images for boss portraits (16×16 PNG), output to skins/default/portraits/.

    python tools/portrait_gen.py

Standard library only. Each portrait is a character picture: one character per pixel, colours in PALETTE.
To change a portrait, change the character picture here and regenerate; do not edit the png by hand. Replaced entirely when the real art comes in step 4.
"""
import os
import struct
import zlib

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "skins", "default", "portraits")

PALETTE = {
    ".": (22, 18, 20, 255),     # background
    "#": (140, 84, 36, 255),    # face (the same colour as Boss A's body in the scene)
    "d": (88, 50, 20, 255),     # shadow
    "h": (77, 84, 92, 255),     # helmet
    "H": (120, 128, 138, 255),  # helmet highlight
    "v": (255, 77, 51, 255),    # goggles
    "w": (240, 235, 220, 255),  # teeth
    "b": (44, 54, 92, 255),     # iron ball
    "B": (96, 112, 150, 255),   # iron ball highlight
    "r": (214, 62, 46, 255),    # red ring / crown
    "m": (138, 160, 186, 255),  # mech shell
    "M": (186, 204, 224, 255),  # shell highlight
    "t": (150, 110, 60, 255),   # antenna
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
    # Boss 2 "machine operator": an iron ball with a red ring and a tuft of red crown on top.
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
    # Boss 3 "unicycle mech": a boxy body with an antenna on top.
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
    # Stage 5's mid-level boss "mutant gunner": a big red helmet with a strip of goggles.
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
    # Stage 5's boss "biopod": a green pod with one eye in the middle.
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
    # Boss 4 "skull": a white skull with two red eyes.
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
