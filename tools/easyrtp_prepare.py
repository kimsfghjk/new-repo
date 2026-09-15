#!/usr/bin/env python3
"""Prepare the EasyRPG RTP asset bundle for this Godot project.

RPG Maker 2000/2003 assets carry no alpha channel: transparency is expressed as a
single flat "colour key" that the maker's engine removes at load time. Godot has no
such concept, so every keyed asset must be converted before it can be used.

This script:

  1. downloads the pinned upstream revision (or reuses a local cache),
  2. replaces each asset's key colour with real transparency,
  3. slices the character sheets into the single-character 72x128 images that
     GBM2K's Sprite2D (hframes=3, vframes=4) expects,
  4. generates a TileSet skeleton per chipset, pre-filled with the `coll_type`
     custom data layer that GBM2K's grid system reads (-1 = walkable),
  5. records a manifest so the outputs can be checked for drift.

Run through tools/prepare-easyrtp.ps1, or directly:

    python tools/easyrtp_prepare.py            # regenerate assets/
    python tools/easyrtp_prepare.py --check    # verify assets/ matches the manifest

Requires Python 3 and Pillow.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import urllib.parse
import urllib.request
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover - dependency gate
    sys.exit("Pillow is required: python -m pip install pillow")

# ---------------------------------------------------------------------------
# Upstream pin
# ---------------------------------------------------------------------------
UPSTREAM_REPO = "EasyRPG/RTP"
UPSTREAM_COMMIT = "993d88cbc78c658d348bbfa74a3b424d393d27e5"
RAW_BASE = f"https://raw.githubusercontent.com/{UPSTREAM_REPO}/{UPSTREAM_COMMIT}/"

REPO_ROOT = Path(__file__).resolve().parent.parent
ASSETS = REPO_ROOT / "assets"
ART = ASSETS / "art" / "easyrtp"
AUDIO = ASSETS / "audio" / "easyrtp"
MANIFEST = ASSETS / "easyrtp.manifest.json"

TILE = 16          # RPG Maker 2000/2003 chipset tile size
CHIP_COLS = 30     # 480 / 16
CHAR_W, CHAR_H = 72, 128   # one character cell: 3 frames x 4 directions of 24x32

# ---------------------------------------------------------------------------
# Conversion policy
#
# `convert` entries carry the key colour that must become transparent. The keys
# are not uniform across the bundle, so each one is listed explicitly. They were
# established by measurement, not by guessing:
#
#   * ChipSet/Dungeon.png  -> #FF678B  (this project's existing
#     third_party/gbm2k/.../tileset_dungeon.png is that very file with #FF678B
#     already keyed out: 100% of its transparent pixels map onto #FF678B)
#   * CharSet/*            -> #009392  (same proof against GBM2K's actor_man.png,
#     which is CharSet/Template.png cell 0,0; 100% match)
#   * Battle/*.png #187518, BattleWeapon/Weapon.png #85B0B6,
#     System2/System2*.png #FF9C00, Monster/Hornet.png #FF00FF,
#     Picture/Cloud.png #FF678B
#       -> flat backdrop behind sprite/UI art, confirmed by eye on a
#          checkerboard contact sheet (see docs/assets.md)
#
# Anything not listed under `convert` is copied verbatim: FaceSet, Panorama,
# Title, System and GameOver are full-canvas artwork whose dominant colour is
# art, not a key.
# ---------------------------------------------------------------------------
CONVERT: dict[str, str] = {
    "ChipSet/Dungeon.png": "#FF678B",
    "ChipSet/Exterior.png": "#FF678B",
    "ChipSet/Interior.png": "#FF678B",
    "ChipSet/Ship.png": "#FF678B",
    "ChipSet/World.png": "#FF678B",
    "ChipSet/retro_Dungeon.png": "#FF678B",
    "ChipSet/retro_Exterior.png": "#FE678A",
    "ChipSet/retro_World.png": "#E067BF",
    "CharSet/Actor1.png": "#009392",
    "CharSet/Actor2.png": "#009392",
    "CharSet/Actor3.png": "#009392",
    "CharSet/Actor4.png": "#009392",
    "CharSet/Animal.png": "#009392",
    "CharSet/Monster1.png": "#009392",
    "CharSet/Monster2.png": "#009392",
    "CharSet/Monster3.png": "#009392",
    "CharSet/Object1.png": "#FE678A",
    "CharSet/Object2.png": "#FF678B",
    "CharSet/People1.png": "#009392",
    "CharSet/People2.png": "#009392",
    "CharSet/People3.png": "#009392",
    "CharSet/People4.png": "#009392",
    "CharSet/People5.png": "#009392",
    "CharSet/Template.png": "#009392",
    "CharSet/Vehicles.png": "#009392",
    "Battle/Arrow.png": "#187518",
    "Battle/Blow.png": "#187518",
    "Battle/Sword1.png": "#187518",
    "BattleWeapon/Weapon.png": "#85B0B6",
    "Monster/Hornet.png": "#FF00FF",
    "Picture/Cloud.png": "#FF678B",
    "System2/System2A.png": "#FF9C00",
    "System2/System2B.png": "#FF9C00",
    "System2/System2C.png": "#FF9C00",
}

# Upstream directory -> destination directory under assets/
PASSTHROUGH_DIRS = {
    "FaceSet": "facesets",
    "Panorama": "panoramas",
    "Title": "titles",
    "System": "system",
    "GameOver": "gameover",
}

CHARSET_DIR = "CharSet"
CHIPSET_DIR = "ChipSet"


def parse_hex(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))  # type: ignore[return-value]


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 16), b""):
            digest.update(block)
    return digest.hexdigest()


def upstream_files() -> list[str]:
    """List every blob in the pinned revision."""
    url = (f"https://api.github.com/repos/{UPSTREAM_REPO}/git/trees/"
           f"{UPSTREAM_COMMIT}?recursive=1")
    request = urllib.request.Request(url, headers={"User-Agent": "easyrtp-prepare"})
    with urllib.request.urlopen(request, timeout=60) as response:
        payload = json.loads(response.read().decode("utf-8", "replace"))
    if payload.get("truncated"):
        raise SystemExit("upstream tree listing was truncated; refusing to guess")
    return sorted(entry["path"] for entry in payload["tree"] if entry["type"] == "blob")


def fetch(rel_path: str, cache_dir: Path) -> bytes:
    """Download one upstream file, memoised in the cache directory.

    Several upstream names contain spaces, so the path is URL-quoted. The cache
    write is atomic: an interrupted run must not leave a truncated file behind
    that later runs would happily reuse.
    """
    cached = cache_dir / rel_path.replace("/", "__")
    if cached.exists() and cached.stat().st_size > 0:
        return cached.read_bytes()
    url = RAW_BASE + urllib.parse.quote(rel_path)
    request = urllib.request.Request(url, headers={"User-Agent": "easyrtp-prepare"})
    with urllib.request.urlopen(request, timeout=120) as response:
        data = response.read()
    cache_dir.mkdir(parents=True, exist_ok=True)
    staging = cached.with_name(cached.name + ".part")
    staging.write_bytes(data)
    os.replace(staging, cached)
    return data


def load_image(rel_path: str, cache_dir: Path) -> Image.Image:
    cached = cache_dir / rel_path.replace("/", "__")
    fetch(rel_path, cache_dir)
    try:
        image = Image.open(cached)
        image.load()
    except Exception as exc:  # noqa: BLE001
        raise SystemExit(f"downloaded {rel_path} but it is not a usable PNG: {exc}")
    return image


def apply_key(image: Image.Image, key: str) -> tuple[Image.Image, int]:
    """Return the image with `key` turned into transparency, plus the pixel count."""
    rgba = image.convert("RGBA")
    target = parse_hex(key)
    pixels = rgba.load()
    width, height = rgba.size
    cleared = 0
    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            if a and (r, g, b) == target:
                pixels[x, y] = (0, 0, 0, 0)
                cleared += 1
    return rgba, cleared


def save_png(image: Image.Image, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    # No palette, no dithering: keep the source pixels exactly as authored.
    image.save(destination, "PNG", optimize=True)


def slice_charset(image: Image.Image) -> list[Image.Image]:
    """Split a 288x256 sheet into its eight 72x128 characters.

    RPG Maker 2000/2003 lays a character sheet out as 4 columns x 2 rows of
    character cells; each cell is 3 animation frames x 4 directions of 24x32.
    """
    cells = []
    for row in range(2):
        for col in range(4):
            box = (col * CHAR_W, row * CHAR_H, (col + 1) * CHAR_W, (row + 1) * CHAR_H)
            cells.append(image.crop(box))
    return cells


def dest_dir_for(rel_path: str) -> str:
    top = rel_path.split("/", 1)[0]
    if top == CHIPSET_DIR:
        return "chipsets"
    if top == CHARSET_DIR:
        return "characters"
    special = {
        "Battle": "battle",
        "BattleWeapon": "battle_weapons",
        "Monster": "monsters",
        "Picture": "pictures",
        "System2": "system2",
    }
    if top in special:
        return special[top]
    return PASSTHROUGH_DIRS[top]


def occupied_cells(image: Image.Image) -> list[tuple[int, int]]:
    """Every (col, row) whose 16x16 cell contains at least one visible pixel.

    Fully transparent cells are unused slots in the chipset format; registering
    them would only offer invisible tiles in the editor.
    """
    alpha = image.getchannel("A")
    cells = []
    for row in range(image.height // TILE):
        for col in range(image.width // TILE):
            box = (col * TILE, row * TILE, (col + 1) * TILE, (row + 1) * TILE)
            if alpha.crop(box).getextrema()[1] > 0:
                cells.append((col, row))
    return cells


def write_tileset(chipset: str, image: Image.Image, destination: Path) -> int:
    """Emit a TileSet skeleton wired for GBM2K's grid system.

    GBM2K's PawnGrid.initialize_cells() reads a custom data layer named
    `coll_type` and stores it as a tile source id in its own collision layer,
    where -1 means EMPTY (walkable) and 0/1/2 mean ACTOR/OBSTACLE/EVENT.
    An unset custom data entry reads back as 0, which would make every freshly
    painted tile block movement, so every tile is written with -1 explicitly.
    """
    cells = occupied_cells(image)
    texture_path = f"res://assets/art/easyrtp/chipsets/{chipset}.png"
    lines = [
        '[gd_resource type="TileSet" format=3]',
        '',
        f'[ext_resource type="Texture2D" path="{texture_path}" id="1_chipset"]',
        '',
        '[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_easyrtp"]',
        'texture = ExtResource("1_chipset")',
        f'texture_region_size = Vector2i({TILE}, {TILE})',
    ]
    for col, row in cells:
        lines.append(f"{col}:{row}/0 = 0")
        lines.append(f"{col}:{row}/0/custom_data_0 = -1")
    lines += [
        '',
        '[resource]',
        'custom_data_layer_0/name = "coll_type"',
        'custom_data_layer_0/type = 2',
        'sources/0 = SubResource("TileSetAtlasSource_easyrtp")',
        '',
    ]
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    return len(cells)


def safe_name(upstream_path: str) -> str:
    """Upstream names contain spaces (e.g. "Game Over.png"); keep them traceable
    but free of whitespace for command-line friendliness."""
    return Path(upstream_path).name.replace(" ", "_")


def record(manifest: dict, destination: Path, upstream: str, **extra: object) -> None:
    key = destination.relative_to(REPO_ROOT).as_posix()
    manifest["files"][key] = {
        "upstream": upstream,
        "sha256": sha256_of(destination),
        "bytes": destination.stat().st_size,
        **extra,
    }


def build(cache_dir: Path) -> int:
    files = upstream_files()
    manifest: dict = {
        "upstream_repo": UPSTREAM_REPO,
        "upstream_commit": UPSTREAM_COMMIT,
        "generated_by": "tools/easyrtp_prepare.py",
        "files": {},
        "skipped": [],
    }
    counts = {"chipset": 0, "tileset": 0, "charset_sheet": 0, "character": 0,
              "converted": 0, "copied": 0, "audio": 0, "skipped": 0}
    warnings: list[str] = []

    for rel in files:
        top = rel.split("/", 1)[0]

        if top == "Music":
            manifest["skipped"].append(
                {"upstream": rel, "reason": "MIDI; Godot cannot play it natively"})
            counts["skipped"] += 1
            continue

        if top == "Sound" and rel.lower().endswith(".wav"):
            destination = AUDIO / "sounds" / safe_name(rel)
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(fetch(rel, cache_dir))
            record(manifest, destination, rel)
            counts["audio"] += 1
            continue

        if not rel.lower().endswith(".png"):
            continue

        if top == CHARSET_DIR:
            if rel not in CONVERT:
                raise SystemExit(f"no conversion policy for {rel}")
            key = CONVERT[rel]
            rgba, cleared = apply_key(load_image(rel, cache_dir), key)
            if cleared == 0:
                raise SystemExit(f"{rel}: key {key} matched nothing - policy is stale")
            share = cleared / (rgba.width * rgba.height) * 100
            if share < 1.0:
                warnings.append(f"{rel}: key {key} covered only {share:.2f}%")
            stem = Path(rel).stem
            cells = slice_charset(rgba)
            for index, cell in enumerate(cells, start=1):
                destination = ART / "characters" / f"{stem}_{index}.png"
                save_png(cell, destination)
                record(manifest, destination, rel,
                       charset_cell={"index": index, "col": (index - 1) % 4,
                                     "row": (index - 1) // 4, "key": key})
                counts["character"] += 1
            counts["charset_sheet"] += 1
            print(f"  charset  {rel:28s} key {key}  cells={len(cells)}")
            continue

        destination = ART / dest_dir_for(rel) / safe_name(rel)

        if rel in CONVERT:
            key = CONVERT[rel]
            rgba, cleared = apply_key(load_image(rel, cache_dir), key)
            if cleared == 0:
                raise SystemExit(f"{rel}: key {key} matched nothing - policy is stale")
            share = cleared / (rgba.width * rgba.height) * 100
            if share < 1.0:
                warnings.append(f"{rel}: key {key} covered only {share:.2f}%")
            save_png(rgba, destination)
            record(manifest, destination, rel, key=key, keyed_pixels=cleared)
            counts["converted"] += 1
            extra = ""
            if top == CHIPSET_DIR:
                tileset = ART / "tilesets" / f"{Path(rel).stem}.tres"
                tiles = write_tileset(Path(rel).stem, rgba, tileset)
                record(manifest, tileset, rel, generated="tileset", tiles=tiles)
                counts["chipset"] += 1
                counts["tileset"] += 1
                extra = f"  tiles={tiles}"
            print(f"  convert  {rel:28s} key {key}  cleared={cleared}{extra}")
        else:
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(fetch(rel, cache_dir))
            record(manifest, destination, rel, copied=True)
            counts["copied"] += 1

    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n",
                        encoding="utf-8", newline="\n")
    print()
    print("=== summary ===")
    for name, value in counts.items():
        print(f"  {name:14s} {value}")
    if warnings:
        print()
        print("=== warnings ===")
        for line in warnings:
            print(f"  ! {line}")
    return 0


def check() -> int:
    """Verify the working tree still matches the manifest (drift detection)."""
    if not MANIFEST.exists():
        print("manifest missing; run the generator first")
        return 1
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    missing, drifted, ok = [], [], 0
    for relative, entry in sorted(manifest["files"].items()):
        path = REPO_ROOT / relative
        if not path.exists():
            missing.append(relative)
        elif sha256_of(path) != entry["sha256"]:
            drifted.append(relative)
        else:
            ok += 1
    total = len(manifest["files"])
    print(f"assets matched: {ok}/{total}")
    for label, items in (("missing", missing), ("modified", drifted)):
        if items:
            print(f"\n{label} ({len(items)}):")
            for item in items:
                print(f"  {item}")
    if missing or drifted:
        print("\nRe-run tools/prepare-easyrtp.ps1 to regenerate, or update the")
        print("conversion policy in tools/easyrtp_prepare.py if the change is intended.")
        return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Convert the pinned EasyRPG RTP revision into Godot-ready assets.")
    parser.add_argument("--check", action="store_true",
                        help="verify assets/ against the manifest instead of rebuilding")
    parser.add_argument(
        "--cache",
        default=os.environ.get("EASYRTP_CACHE",
                               str(Path(os.environ.get("TEMP", "/tmp")) / "easyrtp-upstream")),
        help="where downloaded upstream files are memoised")
    args = parser.parse_args()

    if args.check:
        return check()

    print(f"EasyRPG RTP -> assets  (pinned {UPSTREAM_REPO}@{UPSTREAM_COMMIT[:7]})")
    return build(Path(args.cache))


if __name__ == "__main__":
    raise SystemExit(main())