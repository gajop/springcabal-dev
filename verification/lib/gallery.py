#!/usr/bin/env python3
"""Golden comparison for verification/fixtures/gallery/gallery.lua captures.

    gallery.py compare ceg|anim CAPTURES GOLDEN REPORT
    gallery.py update  ceg|anim CAPTURES[,CAPTURES...] GOLDEN REPORT
    gallery.py parity  anim     WASM_CAPTURES LUA_CAPTURES REPORT
    gallery.py screenshots ceg|anim CAPTURES OUT_DIR -

The gallery box-filters every capture on the GPU and writes it as raw RGB
(`<shot>-64.raw` for comparison, `<shot>-128.raw` for contact sheets), so
this script reads plain bytes and never decodes a full-size image.

CEGs: particles use the engine's unseedable unsynced RNG, so a CEG never
renders the same twice.  Each capture is spawned several times; the average of
its (capture - background) images is compared with the golden average at 64x64
and pooled to 16x16.  The limit per capture comes from how far recording runs
differed from each other.  An effect that was visible must still appear.

Animations: every unit's piece matrices at each capture (poses.txt) are
reproducible and compared numerically; images are compared by RMSE with a
limit per image from the difference between recording runs.

Goldens: GOLDEN/metrics.json (or noise.json + poses.txt) plus an atlas PNG
holding every golden image as 64x64 (CEG mean differences) or 128x128
(animation) tiles, and JPEG contact sheets for people to look at.
"""

import json
import math
import os
import struct
import subprocess
import sys
import tempfile

CMP = 64                   # comparison size (pixels per side)
THUMB = 128                # contact sheet / animation image size
POOL = 4                   # pooled comparison: CMP / POOL = 16
DIFF_THRESHOLD = 24        # per-channel difference that counts as "effect"
VISIBLE = 0.002            # effect coverage below which a capture is empty

# CEG mean-difference limit: DIFF_FACTOR x the largest difference between a
# recording run and the golden of the other runs, never below DIFF_FLOOR
# (RMS in 0..255 units).
DIFF_FACTOR = 2.0
DIFF_FLOOR = 2.5

# Poses are reproducible to the logged precision (%.4f) with FixedRNGSeed.
POSE_TRANSLATION = 0.01    # elmos
POSE_ROTATION = 2e-3       # matrix elements (include the model's scale)
POSE_NOISE_FACTOR = 4.0    # shots whose poses drifted while recording
ANIM_RMSE = float(os.environ.get("GALLERY_ANIM_RMSE", "1.5"))   # percent, minimum limit
IMAGE_NOISE_FACTOR = 2.5   # image limit: this times the difference between recordings



# ----------------------------------------------------------------------------
# Raw images and atlases
# ----------------------------------------------------------------------------

def read_raw(path):
    """DevIL raw: uint32 width, height, depth, uint8 bpp, bpc, then RGB rows."""
    with open(path, "rb") as f:
        data = f.read()
    width, height, _ = struct.unpack("<III", data[:12])
    bpp = data[12]
    pixels = data[14:14 + width * height * bpp]
    if bpp == 4:
        pixels = bytes(b for i, b in enumerate(pixels) if i % 4 != 3)
    return width, pixels


def write_ppm(path, width, pixels):
    with open(path, "wb") as f:
        f.write(b"P6 %d %d 255\n" % (width, len(pixels) // (3 * width)))
        f.write(pixels)


def save_atlas(tiles, size, path):
    """Packs equally sized RGB tiles (bytes) into one PNG, row-major."""
    columns = max(1, math.ceil(math.sqrt(len(tiles))))
    rows = math.ceil(len(tiles) / columns)
    row_bytes = columns * size * 3
    canvas = bytearray(rows * size * row_bytes)
    for index, tile in enumerate(tiles):
        ty, tx = divmod(index, columns)
        for y in range(size):
            start = (ty * size + y) * row_bytes + tx * size * 3
            canvas[start:start + size * 3] = tile[y * size * 3:(y + 1) * size * 3]
    with tempfile.NamedTemporaryFile(suffix=".ppm") as tmp:
        write_ppm(tmp.name, columns * size, bytes(canvas))
        subprocess.run(["convert", tmp.name, path], check=True)
    return columns


def load_atlas(path, size, columns, count):
    data = subprocess.run(["convert", path, "-depth", "8", "rgb:-"],
                          check=True, capture_output=True).stdout
    row_bytes = columns * size * 3
    tiles = []
    for index in range(count):
        ty, tx = divmod(index, columns)
        tile = bytearray()
        for y in range(size):
            start = (ty * size + y) * row_bytes + tx * size * 3
            tile += data[start:start + size * 3]
        tiles.append(bytes(tile))
    return tiles


def contact_sheet(entries, path, columns=6):
    """entries: [(label, raw path)] -> labelled JPEG sheet."""
    if not entries:
        return
    with tempfile.TemporaryDirectory() as tmp:
        tiles = []
        for i, (label, raw) in enumerate(entries):
            width, pixels = read_raw(raw)
            ppm = os.path.join(tmp, f"{i:05d}.ppm")
            write_ppm(ppm, width, pixels)
            tiles += ["-label", label, ppm]
        subprocess.run(["montage", *tiles, "-tile", f"{columns}x", "-geometry", f"{THUMB}x{THUMB}+2+2",
                        "-pointsize", "9", "-quality", "80", path], check=True)


# ----------------------------------------------------------------------------
# Renderer bookkeeping
# ----------------------------------------------------------------------------

RENDERER_KEYS = ("backend", "gl_renderer", "gl_version")


def read_renderer(directory):
    """renderer.txt: `backend`, `gl_renderer` (GPU) and `gl_version` (driver)
    lines.  Goldens recorded before the GPU was stored hold only the backend."""
    path = os.path.join(directory, "renderer.txt")
    if not os.path.isfile(path):
        return {}
    lines = [line.strip() for line in open(path) if line.strip()]
    if len(lines) == 1 and " " not in lines[0]:
        return {"backend": lines[0]}
    return dict(line.split(" ", 1) if " " in line else (line, "") for line in lines)


def describe_renderer(info):
    return ", ".join(f"{key} '{info[key]}'" for key in RENDERER_KEYS if key in info) or "unknown"


def write_renderer(golden_dir, captures):
    info = read_renderer(captures)
    with open(os.path.join(golden_dir, "renderer.txt"), "w") as f:
        for key in RENDERER_KEYS:
            f.write(f"{key} {info.get(key, 'unknown')}\n")
    return describe_renderer(info)


def images_comparable(golden_dir, captures):
    """Pixels are only comparable between runs on the same backend, GPU and
    driver.  Returns (comparable, failure): on another renderer the images are
    not compared, and that is a failure unless VF_ALLOW_RENDERER_MISMATCH=1
    (poses and presence are still checked either way).  A driver or Mesa
    update would otherwise turn every pixel check off and still pass."""
    golden, current = read_renderer(golden_dir), read_renderer(captures)
    differing = [key for key in RENDERER_KEYS if key in golden and golden[key] != current.get(key)]
    if differing:
        reason = (f"the golden was rendered with {describe_renderer(golden)}, "
                  f"this run with {describe_renderer(current)} ({', '.join(differing)} "
                  f"{'differs' if len(differing) == 1 else 'differ'}).  "
                  "Re-record the goldens on this renderer (VF_UPDATE_GOLDENS=1), or run on the "
                  "golden's (VF_RENDERER)")
        if os.environ.get("VF_ALLOW_RENDERER_MISMATCH") == "1":
            print(f"  SKIP     image checks (VF_ALLOW_RENDERER_MISMATCH=1): {reason}")
            return False, None
        return False, f"image checks impossible: {reason}; VF_ALLOW_RENDERER_MISMATCH=1 skips them"
    if "gl_renderer" not in golden:
        print(f"  NOTE     the golden records only its backend ({golden.get('backend', 'none')}), "
              "not the GPU or driver; re-record to store them")
    return True, None


# ----------------------------------------------------------------------------
# CEGs
# ----------------------------------------------------------------------------

def ceg_samples(captures):
    """{"<ceg>/<zoom>/<frame>": [signed diff vector per repeat]} at CMP."""
    result = {}
    for ceg in sorted(os.listdir(captures)):
        cdir = os.path.join(captures, ceg)
        if not os.path.isdir(cdir):
            continue
        for zoom in sorted(os.listdir(cdir)):
            zdir = os.path.join(cdir, zoom)
            if not os.path.isdir(zdir):
                continue
            for rep in sorted(os.listdir(zdir)):
                rdir = os.path.join(zdir, rep)
                bg_path = os.path.join(rdir, f"bg-{CMP}.raw")
                if not os.path.isfile(bg_path):
                    continue
                _, bg = read_raw(bg_path)
                for shot in sorted(os.listdir(rdir)):
                    if not shot.endswith(f"-{CMP}.raw") or shot.startswith("bg-"):
                        continue
                    _, fg = read_raw(os.path.join(rdir, shot))
                    key = f"{ceg}/{zoom}/{shot[:-len(f'-{CMP}.raw')]}"
                    result.setdefault(key, []).append([f - b for f, b in zip(fg, bg)])
    return result


def coverage(diff):
    covered = 0
    for i in range(0, len(diff), 3):
        if max(abs(diff[i]), abs(diff[i + 1]), abs(diff[i + 2])) > DIFF_THRESHOLD:
            covered += 1
    return covered / (len(diff) // 3)


def mean_vector(vectors):
    n = len(vectors)
    return [sum(values) / n for values in zip(*vectors)]


def pooled(vector, grid=CMP, pool=POOL):
    out_grid = grid // pool
    out = [0.0] * (out_grid * out_grid * 3)
    scale = 1.0 / (pool * pool)
    for y in range(grid):
        base_out = (y // pool) * out_grid
        row = y * grid * 3
        for x in range(grid):
            o = (base_out + x // pool) * 3
            i = row + x * 3
            out[o] += vector[i] * scale
            out[o + 1] += vector[i + 1] * scale
            out[o + 2] += vector[i + 2] * scale
    return out


def rms(a, b):
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)) / len(a))


def encode_diff(vector):
    """Signed difference stored as 128 + diff/2 per channel."""
    return bytes(max(0, min(255, round(128 + v / 2))) for v in vector)


def decode_diff(tile):
    return [(b - 128) * 2 for b in tile]


def visible_fraction(samples):
    return sum(1 for d in samples if coverage(d) >= VISIBLE) / len(samples)


def ceg_sheet_entries(captures, zoom, only=None):
    entries = []
    for ceg in sorted(os.listdir(captures)):
        if only is not None and ceg not in only:
            continue
        rdir = os.path.join(captures, ceg, zoom, "r1")
        if not os.path.isdir(rdir):
            continue
        for shot in sorted(os.listdir(rdir)):
            if shot.endswith(f"-{THUMB}.raw"):
                entries.append((f"{ceg} {zoom} {shot[:-len(f'-{THUMB}.raw')]}", os.path.join(rdir, shot)))
    return entries


def run_ceg(mode, captures, golden_dir, report_dir):
    capture_dirs = captures.split(",")
    missing = [c for c in capture_dirs if not os.path.isdir(c)]
    if missing:
        print(f"  no CEG captures: {', '.join(missing)} does not exist", file=sys.stderr)
        return 1
    runs = [ceg_samples(c) for c in capture_dirs]
    current = runs[0]
    if not current:
        print("no CEG captures found", file=sys.stderr)
        return 1
    os.makedirs(report_dir, exist_ok=True)
    metrics_file = os.path.join(golden_dir, "metrics.json")
    atlas_file = os.path.join(golden_dir, "diffs.png")

    if mode == "update":
        keys = sorted(set.intersection(*(set(r) for r in runs)))
        golden, tiles = {"captures": {}, "order": keys}, []
        for key in keys:
            samples = [v for r in runs for v in r[key]]
            mean = mean_vector(samples)
            tiles.append(encode_diff(mean))
            entry = {"visible": round(visible_fraction(samples), 3),
                     "coverage": round(coverage(mean), 4)}
            noise = noise_p = 0.0
            if len(runs) > 1:
                # Each run's average against the golden of the other runs.
                for j, r in enumerate(runs):
                    others = mean_vector([v for k, o in enumerate(runs) if k != j for v in o[key]])
                    mine = mean_vector(r[key])
                    noise = max(noise, rms(mine, others))
                    noise_p = max(noise_p, rms(pooled(mine), pooled(others)))
            entry["diff_noise"], entry["diff_noise_pooled"] = round(noise, 3), round(noise_p, 3)
            golden["captures"][key] = entry
        os.makedirs(golden_dir, exist_ok=True)
        golden["atlas_columns"] = save_atlas(tiles, CMP, atlas_file)
        with open(metrics_file, "w") as f:
            json.dump(golden, f, indent=1, sort_keys=True)
        for zoom in ("near", "far"):
            contact_sheet(ceg_sheet_entries(capture_dirs[0], zoom), os.path.join(golden_dir, f"sheet-{zoom}.jpg"))
        renderer = write_renderer(golden_dir, capture_dirs[0])
        print(f"  UPDATED  {len(keys)} CEG captures from {len(runs)} runs ({renderer}) -> {golden_dir}")
        return 0

    if not os.path.isfile(metrics_file):
        print(f"  MISSING  {metrics_file} (run with VF_UPDATE_GOLDENS=1 to record it)")
        return 1
    with open(metrics_file) as f:
        golden = json.load(f)
    order, entries = golden["order"], golden["captures"]
    compare_images, renderer_failure = images_comparable(golden_dir, capture_dirs[0])
    refs = dict(zip(order, load_atlas(atlas_file, CMP, golden["atlas_columns"], len(order)))) \
        if compare_images else {}
    failures, rows = [], []
    if renderer_failure:
        failures.append(("renderer", renderer_failure))
    for key in sorted(set(entries) | set(current)):
        if key not in current:
            failures.append((key, "not captured any more"))
            continue
        if key not in entries:
            failures.append((key, "new capture with no golden"))
            continue
        entry, samples = entries[key], current[key]
        seen = visible_fraction(samples)
        if entry["visible"] >= 0.5 and seen == 0:
            failures.append((key, f"never visible (golden visible in {entry['visible']:.0%} of samples)"))
            rows.append((9.0, key, "never visible"))
            continue
        if entry["visible"] == 0 and seen > 0.5:
            failures.append((key, f"appeared in {seen:.0%} of repeats (golden never visible)"))
            rows.append((9.0, key, "appeared"))
            continue
        if not compare_images:
            continue
        mine, ref = mean_vector(samples), decode_diff(refs[key])
        limit = max(DIFF_FLOOR, DIFF_FACTOR * entry["diff_noise"])
        limit_p = max(DIFF_FLOOR, DIFF_FACTOR * entry["diff_noise_pooled"])
        distance, distance_p = rms(mine, ref), rms(pooled(mine), pooled(ref))
        score = max(distance / limit, distance_p / limit_p)
        detail = f"mean image {distance:.1f}/{limit:.1f}, pooled {distance_p:.1f}/{limit_p:.1f}"
        rows.append((score, key, detail))
        if score > 1:
            failures.append((key, f"looks different ({detail})"))
    rows.sort(reverse=True)
    with open(os.path.join(report_dir, "report.txt"), "w") as f:
        for score, key, detail in rows:
            f.write(f"{score:5.2f}  {key}  {detail}\n")
    print(f"  {len(rows)} CEG captures compared; closest to the limit:")
    for score, key, detail in rows[:3]:
        print(f"    {score:4.2f} of limit  {key}  ({detail})")
    for key, reason in failures:
        print(f"  FAIL     {key}: {reason}")
    if failures:
        failing = sorted({k.rsplit("/", 2)[0] for k, _ in failures})
        sheet = [e for zoom in ("near", "far") for e in ceg_sheet_entries(capture_dirs[0], zoom, failing)]
        contact_sheet(sheet, os.path.join(report_dir, "failing.jpg"))
        print(f"  failing captures: {report_dir}/failing.jpg (golden sheets: {golden_dir}/sheet-*.jpg)")
    print(f"  report: {report_dir}/report.txt")
    return 1 if failures else 0


# ----------------------------------------------------------------------------
# Animations
# ----------------------------------------------------------------------------

def read_poses(path):
    """{(unit, phase, frame, piece): [16 floats]}"""
    poses = {}
    if not os.path.isfile(path):
        return poses
    with open(path) as f:
        for line in f:
            fields = dict(part.split("=", 1) for part in line.split() if "=" in part)
            try:
                key = (fields["unit"], fields["phase"], int(fields["frame"]), fields["piece"])
                poses[key] = [float(v) for v in fields["m"].split(",")]
            except (KeyError, ValueError):
                continue
    return poses


def pose_diff(a, b):
    """(translation diff, rotation diff) between two column-major matrices."""
    trans = max(abs(a[i] - b[i]) for i in (12, 13, 14))
    rot = max(abs(a[i] - b[i]) for i in range(12) if i % 4 != 3)
    return trans, rot


def compare_poses(golden, current, label_a="golden", label_b="current"):
    """Returns (failures, per-(unit,phase,frame) worst diffs)."""
    failures, worst = [], {}
    for key in sorted(set(golden) | set(current)):
        shot = key[:3]
        if key not in current:
            failures.append((shot, f"piece {key[3]} missing in {label_b}"))
            continue
        if key not in golden:
            failures.append((shot, f"piece {key[3]} missing in {label_a}"))
            continue
        trans, rot = pose_diff(golden[key], current[key])
        w = worst.setdefault(shot, [0.0, 0.0, ""])
        if trans > w[0] or rot > w[1]:
            w[0], w[1] = max(w[0], trans), max(w[1], rot)
            w[2] = key[3]
    for shot, (trans, rot, piece) in sorted(worst.items()):
        if trans > POSE_TRANSLATION or rot > POSE_ROTATION:
            failures.append((shot, f"piece {piece} moved {trans:.3f} elmos / rotated {rot:.4f}"))
    return failures, worst


def anim_images(captures):
    """{"<unit>/<phase>-fNN": raw path} at THUMB size."""
    images = {}
    for unit in sorted(os.listdir(captures)):
        udir = os.path.join(captures, unit)
        if os.path.isdir(udir):
            for shot in sorted(os.listdir(udir)):
                if shot.endswith(f"-{THUMB}.raw"):
                    images[f"{unit}/{shot[:-len(f'-{THUMB}.raw')]}"] = os.path.join(udir, shot)
    return images


def rmse_percent(a, b):
    return rms(a, b) / 255 * 100


def run_anim(mode, captures, golden_dir, report_dir):
    capture_dirs = captures.split(",")
    if not os.path.isdir(capture_dirs[0]):
        print(f"  no animation captures: {capture_dirs[0]} does not exist", file=sys.stderr)
        return 1
    poses_file = os.path.join(capture_dirs[0], "poses.txt")
    current = read_poses(poses_file)
    images = anim_images(capture_dirs[0])
    if not current or not images:
        print("no animation captures found", file=sys.stderr)
        return 1
    os.makedirs(report_dir, exist_ok=True)
    noise_file = os.path.join(golden_dir, "noise.json")
    atlas_file = os.path.join(golden_dir, "images.png")

    if mode == "update":
        # Several recordings: poses should match exactly; images get a limit
        # from how far the recordings differ (unsynced effects, weather).
        noise = {"images": {}, "poses": {}, "order": sorted(images)}
        pixels = {name: read_raw(path)[1] for name, path in images.items()}
        for other_dir in capture_dirs[1:]:
            other = read_poses(os.path.join(other_dir, "poses.txt"))
            _, worst = compare_poses(current, other, "run 1", "run 2")
            for shot, (trans, rot, _) in worst.items():
                if trans > POSE_TRANSLATION or rot > POSE_ROTATION:
                    key = " ".join(map(str, shot))
                    prev = noise["poses"].get(key, [0, 0])
                    noise["poses"][key] = [max(prev[0], round(trans, 4)), max(prev[1], round(rot, 5))]
            for name, path in anim_images(other_dir).items():
                if name in pixels:
                    pct = rmse_percent(pixels[name], read_raw(path)[1])
                    noise["images"][name] = round(max(noise["images"].get(name, 0), pct), 3)
        os.makedirs(golden_dir, exist_ok=True)
        noise["atlas_columns"] = save_atlas([pixels[n] for n in noise["order"]], THUMB, atlas_file)
        with open(poses_file) as src, open(os.path.join(golden_dir, "poses.txt"), "w") as dst:
            dst.write(src.read())
        with open(noise_file, "w") as f:
            json.dump(noise, f, indent=1, sort_keys=True)
        contact_sheet([(name, images[name]) for name in noise["order"]], os.path.join(golden_dir, "sheet.jpg"))
        renderer = write_renderer(golden_dir, capture_dirs[0])
        units = {k[0] for k in current}
        print(f"  UPDATED  {len(units)} units, {len(images)} images, {len(current)} piece poses "
              f"from {len(capture_dirs)} runs ({renderer}) -> {golden_dir}")
        for shot, (trans, rot) in sorted(noise["poses"].items()):
            print(f"  NOTE     poses not reproducible: {shot} (drift {trans} elmos / {rot})")
        return 0

    golden = read_poses(os.path.join(golden_dir, "poses.txt"))
    if not golden or not os.path.isfile(noise_file):
        print(f"  MISSING  {golden_dir} (run with VF_UPDATE_GOLDENS=1 to record it)")
        return 1
    with open(noise_file) as f:
        noise = json.load(f)
    failures, worst = compare_poses(golden, current)
    kept = []
    for shot, reason in failures:
        drift = noise["poses"].get(" ".join(map(str, shot)))
        if drift and shot in worst:
            trans, rot, _ = worst[shot]
            if trans <= POSE_NOISE_FACTOR * max(drift[0], POSE_TRANSLATION) and \
                    rot <= POSE_NOISE_FACTOR * max(drift[1], POSE_ROTATION):
                continue
        kept.append((shot, reason))
    failures = kept
    image_rows = []
    compare_images, renderer_failure = images_comparable(golden_dir, capture_dirs[0])
    if renderer_failure:
        failures.append((("renderer",), renderer_failure))
    if compare_images:
        refs = dict(zip(noise["order"],
                        load_atlas(atlas_file, THUMB, noise["atlas_columns"], len(noise["order"]))))
        for name, path in images.items():
            if name not in refs:
                failures.append(((name,), "new image with no golden"))
                continue
            pct = rmse_percent(refs[name], read_raw(path)[1])
            limit = max(ANIM_RMSE, IMAGE_NOISE_FACTOR * noise["images"].get(name, 0))
            image_rows.append((pct / limit, pct, limit, name))
            if pct > limit:
                failures.append(((name,), f"image {pct:.1f}% off golden (limit {limit:.1f}%)"))
    image_rows.sort(reverse=True)
    with open(os.path.join(report_dir, "report.txt"), "w") as f:
        for shot, (trans, rot, piece) in sorted(worst.items()):
            f.write(f"pose {shot}  max {trans:.4f} elmos / {rot:.5f} (piece {piece})\n")
        for share, pct, limit, name in image_rows:
            f.write(f"image {share:4.2f} of limit  {pct:5.2f}% / {limit:.1f}%  {name}\n")
    max_t = max((w[0] for w in worst.values()), default=0)
    max_r = max((w[1] for w in worst.values()), default=0)
    print(f"  {len(worst)} poses compared: max {max_t:.4f} elmos / {max_r:.5f} rotation "
          f"(limits {POSE_TRANSLATION} / {POSE_ROTATION}; {len(noise['poses'])} shots with recorded drift)")
    if image_rows:
        share, pct, limit, name = image_rows[0]
        print(f"  {len(image_rows)} images compared: closest {share:.2f} of limit ({name}: {pct:.2f}% / {limit:.1f}%)")
    for shot, reason in failures:
        print(f"  FAIL     {' '.join(map(str, shot))}: {reason}")
    if failures:
        bad = {s[0].split("/")[0] for s, _ in failures}
        contact_sheet([(n, p) for n, p in images.items() if n.split("/")[0] in bad],
                      os.path.join(report_dir, "failing.jpg"))
        print(f"  failing units: {report_dir}/failing.jpg (golden sheet: {golden_dir}/sheet.jpg)")
    print(f"  report: {report_dir}/report.txt")
    return 1 if failures else 0


def run_parity(wasm_captures, lua_captures, report_dir):
    wasm = read_poses(os.path.join(wasm_captures, "poses.txt"))
    lua = read_poses(os.path.join(lua_captures, "poses.txt"))
    os.makedirs(report_dir, exist_ok=True)
    failures, worst = compare_poses(lua, wasm, "lua", "wasm")
    by_unit = {}
    for shot, (trans, rot, piece) in worst.items():
        u = by_unit.setdefault(shot[0], [0.0, 0.0, None])
        if trans > u[0] or rot > u[1]:
            by_unit[shot[0]] = [max(u[0], trans), max(u[1], rot), f"{shot[1]} f{shot[2]} {piece}"]
    missing = sorted({s[0] for s, reason in failures if "missing" in reason})
    with open(os.path.join(report_dir, "report.txt"), "w") as f:
        for shot, reason in failures:
            f.write(f"{' '.join(map(str, shot))}: {reason}\n")
    print(f"  WASM vs Lua unit poses ({len(by_unit)} units compared):")
    for unit, (trans, rot, where) in sorted(by_unit.items()):
        flag = "  " if trans <= POSE_TRANSLATION and rot <= POSE_ROTATION else "!!"
        print(f"   {flag} {unit:24s} max {trans:8.3f} elmos / {rot:.4f}  ({where})")
    if missing:
        print(f"   units with pieces present in only one version: {', '.join(missing)}")
    print(f"  {len(failures)} differing shots; details: {report_dir}/report.txt")
    return 0


def screenshots(kind, captures, out_dir):
    """Full-size views for people: one JPEG per CEG (near/far x early/late)
    or per unit (every captured phase), 256 px tiles.  Needs a recording run
    with gallery_full=1, which keeps each capture as <shot>.jpg."""
    import shutil
    if os.path.isdir(out_dir):
        shutil.rmtree(out_dir)
    os.makedirs(out_dir)
    written = 0
    for item in sorted(os.listdir(captures)):
        base = os.path.join(captures, item)
        if not os.path.isdir(base):
            continue
        tiles = []
        if kind == "ceg":
            for zoom in ("near", "far"):
                for shot in ("f02", "f12"):
                    path = os.path.join(base, zoom, "r1", f"{shot}.jpg")
                    if os.path.isfile(path):
                        tiles += ["-label", f"{zoom} {shot}", path]
            columns = 2
        else:
            for shot in sorted(os.listdir(base)):
                if shot.endswith(".jpg"):
                    tiles += ["-label", shot[:-4], os.path.join(base, shot)]
            columns = len(tiles) // 3 or 1
        if tiles:
            subprocess.run(["montage", *tiles, "-tile", f"{columns}x", "-geometry", "256x256+2+2",
                            "-pointsize", "11", "-title", item, "-quality", "78",
                            os.path.join(out_dir, f"{item}.jpg")], check=True)
            written += 1
    print(f"  UPDATED  {written} screenshots -> {out_dir}")
    return 0


def main(argv):
    if len(argv) != 5:
        print(__doc__, file=sys.stderr)
        return 2
    mode, kind, a, b, report = argv
    if mode == "screenshots":
        return screenshots(kind, a, b)
    if mode == "parity":
        return run_parity(a, b, report)
    if mode not in ("compare", "update") or kind not in ("ceg", "anim"):
        print(__doc__, file=sys.stderr)
        return 2
    return (run_ceg if kind == "ceg" else run_anim)(mode, a, b, report)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
