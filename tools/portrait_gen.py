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
}

PORTRAITS = {
    "boss_a": [
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
