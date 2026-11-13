"""Проверка бесшовности текстур Комплекса (после tools/tex/make_textures.py).

    python tools/tex/check_seams.py [--shift <папка>]

Для каждой оси сравнивается скачок на стыке (последний → первый столбец/строка) с разницей соседних
столбцов/строк внутри картинки — по самим пикселям и по блокам 8 px (ловит и резкий шов, и разрыв плавных
пятен). Стык не должен выделяться: FAIL, если он на 25 % больше допустимого (см. axis_score) и вдвое больше
типичного. --shift сохраняет картинки, сдвинутые на полпериода (стык — посередине, видно глазом).
Код выхода 1, если есть FAIL.
"""
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TEX = os.path.join(ROOT, "tex")

# имя: оси, по которым текстура повторяется ("uv" — обе, "u" — только по горизонтали)
TEXTURES = {
    "wall_yellow": "uv", "wall_yellow_dirty": "uv", "wall_old": "uv", "wall_old_dirty": "uv",
    "wall_house": "uv", "wall_house_dirty": "uv", "wall_paint": "uv", "wall_paint_dirty": "uv",
    "wall_school": "u", "wall_school_dirty": "u", "wall_under": "uv",
    "carpet": "uv", "carpet_wet": "uv", "carpet_old": "uv", "ceiling_tile": "uv", "ceiling_tile_dirty": "uv",
    "baseboard": "u", "concrete": "uv", "concrete_dirty": "uv", "concrete_floor": "uv", "concrete_floor_dirty": "uv",
    "tile": "uv", "tile_dirty": "uv", "linoleum": "uv", "linoleum_dirty": "uv", "wood_floor": "uv", "plaster": "uv",
    "wall_grime": "u", "ceil_stains": "uv", "carpet_damp": "uv", "noise": "uv",
    "metal": "uv", "fabric": "uv", "wood": "uv", "paper": "uv", "fiber": "uv", "hazard": "uv",
}
NORMALS = ["wall_yellow", "wall_old", "wall_house", "wall_paint", "wall_school", "wall_under", "carpet", "carpet_old",
           "ceiling_tile", "baseboard", "concrete", "concrete_floor", "tile", "linoleum", "wood_floor", "plaster",
           "metal", "fabric", "wood", "fiber", "hazard"]


def axis_score(a, axis, block=1):
    """(скачок на стыке, медиана внутренних скачков, допустимый скачок) вдоль оси axis (1 — по u).
    Допустимый — наибольшее из: 99.5-й перцентиль внутренних скачков; скачки рядом со стыком (если на
    стыке задуман шов/паз, соседние столбцы тоже резко меняются); скачки в точках W·k/m — там, где
    раскладка повторяется внутри текстуры (стыки рулонов, швы плиток, клетка линолеума)."""
    if axis == 0:
        a = np.swapaxes(a, 0, 1)
    if block > 1:
        w = a.shape[1] // block
        a = a[:, :w * block].reshape(a.shape[0], w, block, -1).mean(2)
    d = np.abs(np.diff(a, axis=1)).mean(axis=(0, 2))       # d[j]: столбец j → j+1
    wrap = np.abs(a[:, 0] - a[:, -1]).mean()
    W = a.shape[1]
    ref = max(np.percentile(d, 99.5), d[0], d[-1])
    for m in range(2, 25):
        if W / m < 8:
            break
        for k in range(1, m):
            j = int(round(W * k / m))
            ref = max(ref, d[max(0, j - 2):min(len(d), j + 1)].max())
    return wrap, np.median(d), ref


def check(name, axes):
    path = os.path.join(TEX, name + ".png")
    if not os.path.exists(path):
        return None, "нет файла"
    a = np.asarray(Image.open(path).convert("RGBA")).astype(np.float64) / 255.0
    worst = 0.0
    notes = []
    ok = True
    for ax_name, axis in (("u", 1), ("v", 0)):
        if ax_name not in axes:
            continue
        for block in (1, 8):
            wrap, med, ref = axis_score(a, axis, block)
            worst = max(worst, wrap / (ref + 1e-6))
            bad = wrap > ref * 1.25 + 1e-4 and wrap > med * 2.0
            if bad:
                ok = False
                notes.append("%s/%d: стык %.4f, медиана %.4f, допустимо %.4f" % (ax_name, block, wrap, med, ref))
    return ok, ("стык/допуск ≤ %.2f" % worst) if ok else "; ".join(notes)


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    shift_dir = None
    if "--shift" in sys.argv:
        shift_dir = sys.argv[sys.argv.index("--shift") + 1]
        os.makedirs(shift_dir, exist_ok=True)
    items = list(TEXTURES.items()) + [(n + "_n", TEXTURES[n]) for n in NORMALS]
    fails = 0
    for name, axes in items:
        ok, msg = check(name, axes)
        if ok is None:
            print("  ??   %-22s %s" % (name, msg))
            fails += 1
            continue
        print("  %s %-22s %s" % ("ok  " if ok else "FAIL", name, msg))
        fails += 0 if ok else 1
        if shift_dir:
            im = np.asarray(Image.open(os.path.join(TEX, name + ".png")))
            if "u" in axes:
                im = np.roll(im, im.shape[1] // 2, 1)
            if "v" in axes:
                im = np.roll(im, im.shape[0] // 2, 0)
            Image.fromarray(im).save(os.path.join(shift_dir, name + "_shift.png"))
    print("FAIL: %d" % fails if fails else "все текстуры бесшовны")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
