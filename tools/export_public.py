"""导出公开版：把仓库里的文件复制一份，**去掉第三方素材**（CraftPix 那几个素材包）。

    python tools/export_public.py <输出目录>

为什么要有公开版：`skins/` 下除了 `default/` 以外的包都是从第三方素材包生成的，
授权不允许再分发，所以不能出现在公开仓库里。游戏代码本身对此有准备——
素材缺了就退回占位版（方块角色、纯色地形、引擎自带字体，`UiKit` / `Skins` / `TileArt` / `Prop`
各自查文件在不在），规则一点不变；测试里依赖素材的用例会自己跳过（`GameTest.needs_art()`）。

复制的是 git 跟踪的文件 + 还没跟踪但没被忽略的新文件（工作区里的版本），
所以导出前不用先提交。输出目录会先清空。
公开仓库的**历史**另外处理（`git filter-repo --invert-paths`，路径清单就是下面的 `EXCLUDED`）。
"""
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

## 不进公开版的路径（前缀）。**加新的素材包时记得往这里加一条。**
EXCLUDED = [
    "skins/cyberpunk/",
    "skins/industrial/",
    "skins/bar_street/",
    "skins/basement/",
    # 上面那些包的外观场景：只有素材包会引用它们，包不在就是一堆断了链的场景
    "scenes/skins/",
    # 在 CraftPix 原画上擦掉胳膊做出来的（不是从零画的），算第三方素材的衍生品。
    # art_src 里其余的（趴姿、爬行、地图）是自己画的，留着。
    "art_src/punk_idle.png",
    "art_src/punk_run.png",
    "art_src/cyborg_idle.png",
    "art_src/cyborg_run.png",
    # AI 助手的项目说明（本来就不进仓库，这里再保险一次）
    "CLAUDE.md",
    "AGENTS.md",
]


def tracked_files():
    out = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=ROOT, check=True, capture_output=True).stdout
    return [p for p in out.decode("utf-8").split("\0") if p]


def excluded(path):
    return any(path == prefix.rstrip("/") or path.startswith(prefix) for prefix in EXCLUDED)


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(1)
    out = os.path.abspath(sys.argv[1])
    same_drive = os.path.splitdrive(out)[0].lower() == os.path.splitdrive(ROOT)[0].lower()
    if same_drive and os.path.commonpath([out, ROOT]) == ROOT:
        sys.exit("输出目录不能在仓库里面：%s" % out)
    if os.path.exists(out):
        # 保留输出目录里的 .git（公开仓库的工作区），其余清空
        for name in os.listdir(out):
            if name == ".git":
                continue
            target = os.path.join(out, name)
            shutil.rmtree(target) if os.path.isdir(target) else os.remove(target)
    os.makedirs(out, exist_ok=True)
    kept = skipped = 0
    for path in tracked_files():
        if excluded(path):
            skipped += 1
            continue
        source = os.path.join(ROOT, path)
        if not os.path.isfile(source):
            continue        # 已删除但还没提交的
        target = os.path.join(out, path)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copy2(source, target)
        kept += 1
    print("exported %d files to %s (left out %d)" % (kept, out, skipped))


if __name__ == "__main__":
    main()
