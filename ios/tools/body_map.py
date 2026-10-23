#!/usr/bin/env python3
"""Builds ios/FitStats/Views/Training/BodyMapPaths.swift from react-native-body-highlighter
(MIT, (c) 2022 ELABBASSI Hicham; https://github.com/HichamELBSI/react-native-body-highlighter).

    python3 ios/tools/body_map.py <package dir> ios/FitStats/Views/Training/BodyMapPaths.swift [preview.png]

<package dir> is the unpacked npm package (the folder with dist/assets/bodyFront.js). Each SVG path
is rewritten as absolute M/L/C/Z commands, moved into a 724 × 1448 box per figure (the back figure
sits at x 724–1448 in the package) and grouped by FitStats' muscle ids (lib/exercises.ts MUSCLES).
The package has one upper-back region; its lower, outer pieces are the lats.
"""
import math
import os
import re
import sys

# Package slug -> FitStats muscle id; None = drawn as body, not a muscle.
SLUGS = {
    "chest": "chest", "deltoids": "shoulders", "biceps": "biceps", "triceps": "triceps",
    "forearm": "forearms", "abs": "abs", "obliques": "obliques", "trapezius": "upper_back",
    "upper-back": "upper_back", "lower-back": "lower_back", "gluteal": "glutes",
    "quadriceps": "quads", "hamstring": "hamstrings", "adductors": "adductors", "calves": "calves",
    "tibialis": None, "neck": None, "head": None, "hair": None, "hands": None, "feet": None,
    "knees": None, "ankles": None,
}
FILES = [("male", "front", "bodyFront.js"), ("male", "back", "bodyBack.js"),
         ("female", "front", "bodyFemaleFront.js"), ("female", "back", "bodyFemaleBack.js")]
WIDTH = 724.0


def regions(js):
    """[(slug, [path, ...])] in the file's order."""
    out = []
    for m in re.finditer(r'slug: "([a-z-]+)"(.*?)\n    \}', js, re.S):
        out.append((m.group(1), re.findall(r'"([Mm][^"]+)"', m.group(2))))
    return out


NUMBER = re.compile(r"[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?")


def tokens(d):
    """Commands and numbers. An arc's two flags are single digits and may be written without
    separators ("a1.71 1.71 0 012.89 1.12" is rx 1.71, ry 1.71, angle 0, flags 0 and 1, x 2.89)."""
    out, i, cmd, arg = [], 0, None, 0
    while i < len(d):
        c = d[i]
        if c in " ,\t\n":
            i += 1
            continue
        if c.isalpha():
            cmd, arg = c, 0
            out.append(c)
            i += 1
            continue
        if cmd in ("A", "a") and arg % 7 in (3, 4):
            if c not in "01":
                raise ValueError(f"bad arc flag at {i}: {d[i:i + 20]}")
            out.append(c)
            i += 1
            arg += 1
            continue
        m = NUMBER.match(d, i)
        if not m:
            raise ValueError(f"bad path at {i}: {d[i:i + 20]}")
        out.append(m.group(0))
        i = m.end()
        arg += 1
    return out


def arc_to_cubics(x1, y1, rx, ry, phi, large, sweep, x2, y2):
    """SVG arc as cubic Béziers (the endpoint parameterisation of the SVG spec, F.6.5)."""
    if (x1, y1) == (x2, y2):
        return []
    if rx == 0 or ry == 0:
        return [(x1, y1, x2, y2, x2, y2)]
    rx, ry = abs(rx), abs(ry)
    p = math.radians(phi)
    cp, sp = math.cos(p), math.sin(p)
    dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
    x1p, y1p = cp * dx + sp * dy, -sp * dx + cp * dy
    lam = (x1p ** 2) / rx ** 2 + (y1p ** 2) / ry ** 2
    if lam > 1:
        rx, ry = rx * math.sqrt(lam), ry * math.sqrt(lam)
    num = rx ** 2 * ry ** 2 - rx ** 2 * y1p ** 2 - ry ** 2 * x1p ** 2
    den = rx ** 2 * y1p ** 2 + ry ** 2 * x1p ** 2
    coef = math.sqrt(max(0, num / den)) * (-1 if large == sweep else 1)
    cxp, cyp = coef * rx * y1p / ry, -coef * ry * x1p / rx
    cx = cp * cxp - sp * cyp + (x1 + x2) / 2
    cy = sp * cxp + cp * cyp + (y1 + y2) / 2

    def ang(ux, uy, vx, vy):
        a = math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        return a

    t1 = ang(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    dt = ang((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if not sweep and dt > 0:
        dt -= 2 * math.pi
    elif sweep and dt < 0:
        dt += 2 * math.pi
    n = max(1, math.ceil(abs(dt) / (math.pi / 2)))
    step = dt / n
    k = 4 / 3 * math.tan(step / 4)
    out = []
    t = t1
    for _ in range(n):
        c1, s1, c2, s2 = math.cos(t), math.sin(t), math.cos(t + step), math.sin(t + step)
        pts = [(c1 - k * s1, s1 + k * c1), (c2 + k * s2, s2 - k * c2), (c2, s2)]
        seg = []
        for ex, ey in pts:
            seg += [cx + rx * ex * cp - ry * ey * sp, cy + rx * ex * sp + ry * ey * cp]
        out.append(tuple(seg))
        t += step
    return out


def absolute(d):
    """The path as [("M", x, y) | ("L", x, y) | ("C", x1, y1, x2, y2, x, y) | ("Z",)]."""
    toks = tokens(d)
    out = []
    i = 0
    x = y = sx = sy = 0.0
    last_c = last_q = None
    cmd = None

    def num():
        nonlocal i
        v = float(toks[i])
        i += 1
        return v

    while i < len(toks):
        if toks[i].isalpha():
            cmd = toks[i]
            i += 1
        elif cmd is None:
            raise ValueError("number before a command")
        rel = cmd.islower()
        C = cmd.upper()
        ox, oy = (x, y) if rel else (0.0, 0.0)
        if C == "Z":
            out.append(("Z",))
            x, y = sx, sy
            last_c = last_q = None
            continue
        if C == "M":
            x, y = ox + num(), oy + num()
            sx, sy = x, y
            out.append(("M", x, y))
            cmd = "l" if rel else "L"
            last_c = last_q = None
        elif C == "L":
            x, y = ox + num(), oy + num()
            out.append(("L", x, y))
            last_c = last_q = None
        elif C == "H":
            x = ox + num()
            out.append(("L", x, y))
            last_c = last_q = None
        elif C == "V":
            y = oy + num()
            out.append(("L", x, y))
            last_c = last_q = None
        elif C in "CS":
            if C == "C":
                x1, y1 = ox + num(), oy + num()
            else:
                x1, y1 = (2 * x - last_c[0], 2 * y - last_c[1]) if last_c else (x, y)
            x2, y2, ex, ey = ox + num(), oy + num(), ox + num(), oy + num()
            out.append(("C", x1, y1, x2, y2, ex, ey))
            last_c, last_q = (x2, y2), None
            x, y = ex, ey
        elif C in "QT":
            if C == "Q":
                qx, qy = ox + num(), oy + num()
            else:
                qx, qy = (2 * x - last_q[0], 2 * y - last_q[1]) if last_q else (x, y)
            ex, ey = ox + num(), oy + num()
            # A quadratic as the cubic with the same shape.
            out.append(("C", x + 2 / 3 * (qx - x), y + 2 / 3 * (qy - y), ex + 2 / 3 * (qx - ex), ey + 2 / 3 * (qy - ey), ex, ey))
            last_q, last_c = (qx, qy), None
            x, y = ex, ey
        elif C == "A":
            rx, ry, phi = num(), num(), num()
            large, sweep = int(num()), int(num())
            ex, ey = ox + num(), oy + num()
            for seg in arc_to_cubics(x, y, rx, ry, phi, large, sweep, ex, ey):
                out.append(("C",) + seg)
            x, y = ex, ey
            last_c = last_q = None
        else:
            raise ValueError(f"unknown command {cmd}")
    return out


def shift(cmds, dx):
    return [(c[0],) + tuple(v - dx if k % 2 == 0 else v for k, v in enumerate(c[1:])) for c in cmds]


def points(cmds):
    """A polyline per subpath, for bounds and the preview."""
    polys, cur, x, y = [], [], 0, 0
    for c in cmds:
        if c[0] == "M":
            if cur:
                polys.append(cur)
            cur = [(c[1], c[2])]
            x, y = c[1], c[2]
        elif c[0] == "L":
            cur.append((c[1], c[2]))
            x, y = c[1], c[2]
        elif c[0] == "C":
            for t in [i / 8 for i in range(1, 9)]:
                mt = 1 - t
                px = mt ** 3 * x + 3 * mt * mt * t * c[1] + 3 * mt * t * t * c[3] + t ** 3 * c[5]
                py = mt ** 3 * y + 3 * mt * mt * t * c[2] + 3 * mt * t * t * c[4] + t ** 3 * c[6]
                cur.append((px, py))
            x, y = c[5], c[6]
    if cur:
        polys.append(cur)
    return polys


def compact(cmds):
    def f(v):
        s = f"{v:.1f}".rstrip("0").rstrip(".")
        return "0" if s == "-0" else s
    return " ".join(c[0] + (" " + " ".join(f(v) for v in c[1:]) if len(c) > 1 else "") for c in cmds)


def build(pkg):
    """{(body, side): [(muscle id or None, cmds)]}"""
    out = {}
    for body, side, name in FILES:
        js = open(os.path.join(pkg, "dist", "assets", name)).read()
        items = []
        for slug, paths in regions(js):
            if slug not in SLUGS:
                raise ValueError(f"unmapped slug {slug} in {name}")
            for d in paths:
                cmds = absolute(d)
                if side == "back":
                    cmds = shift(cmds, WIDTH)
                muscle = SLUGS[slug]
                if slug == "upper-back":
                    # Below the shoulder blades and out to the sides: the lats.
                    pts = [p for poly in points(cmds) for p in poly]
                    cy = sum(p[1] for p in pts) / len(pts)
                    cx = sum(p[0] for p in pts) / len(pts)
                    if cy > 400 or abs(cx - WIDTH / 2) > 95:
                        muscle = "lats"
                items.append((muscle, cmds))
        out[(body, side)] = items
    return out


def write_swift(data, path):
    lines = [
        "// Generated by ios/tools/body_map.py from react-native-body-highlighter 3.2.0 — do not edit.",
        "//",
        "// MIT License, Copyright (c) 2022 ELABBASSI Hicham",
        "// https://github.com/HichamELBSI/react-native-body-highlighter (full notice: ios/tools/BODY_MAP_LICENSE)",
        "//",
        "// Each figure is in a 724 × 1448 box. A region is a FitStats muscle id (or \"\" for the body",
        "// around the muscles) and its outline as absolute M/L/C/Z commands.",
        "",
        "enum BodyMapPaths {",
    ]
    for (body, side), items in data.items():
        lines.append(f"    static let {body}{side.capitalize()}: [(String, String)] = [")
        for muscle, cmds in items:
            lines.append(f'        ("{muscle or ""}", "{compact(cmds)}"),')
        lines.append("    ]")
    lines.append("}")
    open(path, "w").write("\n".join(lines) + "\n")


def preview(data, path):
    from PIL import Image, ImageDraw
    colors = {"chest": "#e55", "shoulders": "#e95", "biceps": "#ec5", "triceps": "#9c5", "forearms": "#5c9",
              "abs": "#5ce", "obliques": "#59e", "upper_back": "#95e", "lats": "#e5c", "lower_back": "#a66",
              "glutes": "#6a6", "quads": "#66a", "hamstrings": "#aa6", "adductors": "#6aa", "calves": "#c88"}
    scale = 0.4
    img = Image.new("RGB", (int(WIDTH * scale * 4), int(1448 * scale)), "#111")
    dr = ImageDraw.Draw(img)
    for n, key in enumerate(data):
        for muscle, cmds in data[key]:
            for poly in points(cmds):
                pts = [((x + n * WIDTH) * scale, y * scale) for x, y in poly]
                if len(pts) > 2:
                    dr.polygon(pts, fill=colors.get(muscle, "#444"), outline="#000")
    img.save(path)


if __name__ == "__main__":
    data = build(sys.argv[1])
    write_swift(data, sys.argv[2])
    if len(sys.argv) > 3:
        preview(data, sys.argv[3])
    for key, items in data.items():
        print(key, len(items), "regions", sorted({m for m, _ in items if m}))
