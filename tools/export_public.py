"""Export the public version: copy the files in the repo, **leaving out the third-party art** (the CraftPix art packs).

    python tools/export_public.py <output directory>

Why there is a public version: every pack under `skins/` except `default/` is generated from third-party art packs,
whose licence does not allow redistribution, so they cannot appear in a public repo. The game code is prepared for this —
when art is missing it falls back to placeholders (block characters, plain-colour terrain, the engine's built-in font; `UiKit` / `Skins` / `TileArt` / `Prop`
each check whether the file is there), with the rules unchanged; test cases that depend on the art skip themselves (`GameTest.needs_art()`).

It copies the files git tracks + new files not tracked yet but not ignored (the working tree versions),
so there is no need to commit before exporting. The output directory is emptied first.
The public repo's **history** is handled separately (`git filter-repo --invert-paths`, with the path list being `EXCLUDED` below).
"""
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

## Paths (prefixes) left out of the public version. **Remember to add an entry here when adding a new art pack.**
EXCLUDED = [
    "skins/cyberpunk/",
    "skins/industrial/",
    "skins/bar_street/",
    "skins/basement/",
    "skins/lab/",
    # The visual scenes of the packs above: only the packs reference them, and without the packs they are a pile of scenes with broken links
    "scenes/skins/",
    # Made by erasing the arms on CraftPix's original art (not drawn from scratch), so they count as derivatives of third-party art.
    # The rest of art_src (prone, crawling, maps) was drawn by us and stays.
    "art_src/punk_idle.png",
    "art_src/punk_run.png",
    "art_src/cyborg_idle.png",
    "art_src/cyborg_run.png",
    # The AI assistant's project notes (never in the repo anyway, this is extra insurance)
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
        sys.exit("The output directory must not be inside the repo: %s" % out)
    if os.path.exists(out):
        # Keep the .git in the output directory (the public repo's working tree), empty the rest
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
            continue        # Deleted but not committed yet
        target = os.path.join(out, path)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copy2(source, target)
        kept += 1
    print("exported %d files to %s (left out %d)" % (kept, out, skipped))


if __name__ == "__main__":
    main()
