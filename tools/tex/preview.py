"""Просмотр текстур Комплекса: листы в мировом масштабе, освещение по карте нормалей, калибровка цвета.

    python tools/tex/preview.py <папка> [sheet|lit|wall|floor|ceil|swatch|all]

Свет и тонмаппинг повторяют игру: тёплый свет ламп (1, 0.965, 0.84), Filmic (white 3), насыщенность 1.12,
контраст 1.04 (complex.gd). Картинки пишутся в <папку> (не в репозиторий).
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TEX = os.path.join(ROOT, "tex")
LIGHT = np.array([1.0, 0.965, 0.84])

# имя: (метров на повтор по u, по v)
SCALE = {
    "wall_yellow": (1.2, 1.2), "wall_yellow_dirty": (1.2, 1.2), "wall_old": (1.2, 1.2), "wall_old_dirty": (1.2, 1.2),
    "wall_house": (1.2, 1.2), "wall_house_dirty": (1.2, 1.2), "wall_paint": (1.2, 1.2), "wall_paint_dirty": (1.2, 1.2),
    "wall_school": (1.2, 3.2), "wall_school_dirty": (1.2, 3.2), "wall_under": (1.2, 1.2),
    "carpet": (1.2, 1.2), "carpet_wet": (1.2, 1.2), "carpet_old": (1.2, 1.2),
    "ceiling_tile": (1.2, 1.2), "ceiling_tile_dirty": (1.2, 1.2), "fixture": (0.6, 1.2), "baseboard": (1.2, 0.1),
    "concrete": (2.4, 2.4), "concrete_dirty": (2.4, 2.4), "concrete_floor": (2.4, 2.4), "concrete_floor_dirty": (2.4, 2.4),
    "tile": (1.2, 1.2), "tile_dirty": (1.2, 1.2), "linoleum": (1.2, 1.2), "linoleum_dirty": (1.2, 1.2),
    "wood_floor": (1.2, 1.2), "plaster": (1.2, 1.2),
    "metal": (1.0, 1.0), "fabric": (1.0, 1.0), "wood": (1.0, 1.0), "paper": (0.5, 0.5), "fiber": (1.0, 1.0),
    "hazard": (1.0, 0.25), "mold": (1.0, 1.0),
}


def load(name, mode="RGB"):
    return np.asarray(Image.open(os.path.join(TEX, name + ".png")).convert(mode)).astype(np.float64) / 255.0


def s2l(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def l2s(c):
    c = np.clip(c, 0, None)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def filmic(x, w=3.0):
    A, B, C, D, E, F = 0.22 * 4, 0.30 * 2, 0.10, 0.20, 0.01, 0.30
    f = lambda c: ((c * (A * c + C * B) + D * E) / (c * (A * c + B) + D * F)) - E / F
    return f(x) / f(w)


_AGX_IN = np.array([[0.54490813676363087053, 0.14044005884001287035, 0.088827411851915368603],
                    [0.37377945959812267119, 0.75410959864013760045, 0.17887712465043811023],
                    [0.081384976686407536266, 0.10543358536857773485, 0.73224999956948382528]]).T
_AGX_OUT = np.array([[1.9645509602733325934, -0.29932243390911083839, -0.16436833806080403409],
                     [-0.85585845117807513559, 1.3264510741502356309, -0.23822464068860595117],
                     [-0.10886710826831608324, -0.027084020983874825605, 1.402665347143271889]]).T


def agx(lin):
    """AgX как в Godot 4.4+ (tonemap.glsl), результат — линейный sRGB"""
    c = np.maximum(lin, 2e-10) @ _AGX_IN.T
    lo, hi = -12.4739311883324, 4.02606881166759
    c = (np.clip(np.log2(c), lo, hi) - lo) / (hi - lo)
    x2 = c * c
    x4 = x2 * x2
    c = 15.5 * x4 * x2 - 40.14 * x4 * c + 31.96 * x4 - 6.868 * x2 * c + 0.4298 * x2 + 0.1191 * c - 0.00232
    c = np.clip(c, 0, None) ** 2.4
    return np.maximum(c @ _AGX_OUT.T, 0.0)


def tonemap_agx(lin):
    s = l2s(np.clip(agx(lin), 0, 1))
    s = 0.5 + (s - 0.5) * 1.04
    g = s.mean(-1, keepdims=True)
    return np.clip(g + (s - g) * 1.12, 0, 1)


def tonemap(lin):
    s = l2s(filmic(lin))
    s = 0.5 + (s - 0.5) * 1.04
    g = s.mean(-1, keepdims=True)
    return np.clip(g + (s - g) * 1.12, 0, 1)


def to_img(a):
    return Image.fromarray(np.round(np.clip(a, 0, 1) * 255).astype(np.uint8))


def prefilter(img, f, wrap_v=True):
    """Предфильтр как у мип-карт: уменьшить текстуру в f раз (с переносом по краям)"""
    if f <= 1.05:
        return img
    H, W = img.shape[:2]
    t = np.concatenate([img[:, -W // 4:], img, img[:, :W // 4]], 1)
    if wrap_v:
        t = np.concatenate([t[-H // 4:], t, t[:H // 4]], 0)
    nw, nh = max(2, int(round(t.shape[1] / f))), max(2, int(round(t.shape[0] / f)))
    s = np.asarray(to_img(t).resize((nw, nh), Image.BOX)).astype(np.float64) / 255.0
    w2 = max(1, int(round(W / f)))
    x0 = int(round((W // 4) / f))
    out = s[:, x0:x0 + w2]
    if wrap_v:
        h2 = max(1, int(round(H / f)))
        y0 = int(round((H // 4) / f))
        out = out[y0:y0 + h2]
    return out


def sample(img, u, v, wrap_v=True, px_per_rep=None):
    """Билинейная выборка img (H×W×C) по u, v (в повторах) с переносом; px_per_rep — сколько пикселей
    вывода на повтор по u (для предфильтра, иначе — алиасинг, которого в игре с мип-картами нет)"""
    if px_per_rep is not None:
        img = prefilter(img, img.shape[1] / px_per_rep, wrap_v)
    H, W = img.shape[:2]
    x = u * W - 0.5
    y = v * H - 0.5
    x0 = np.floor(x).astype(int)
    y0 = np.floor(y).astype(int)
    fx = (x - x0)[..., None]
    fy = (y - y0)[..., None]
    if wrap_v:
        y0m, y1m = y0 % H, (y0 + 1) % H
    else:
        y0m, y1m = np.clip(y0, 0, H - 1), np.clip(y0 + 1, 0, H - 1)
    x0m, x1m = x0 % W, (x0 + 1) % W
    a = img[y0m, x0m] * (1 - fx) + img[y0m, x1m] * fx
    b = img[y1m, x0m] * (1 - fx) + img[y1m, x1m] * fx
    return a * (1 - fy) + b * fy


def resample(img, out_w, out_h, reps_u, reps_v):
    """Плитка reps×reps, сжатая до out (с усреднением — как мип-карты)"""
    H, W = img.shape[:2]
    big = np.tile(img, (int(np.ceil(reps_v)), int(np.ceil(reps_u)), 1))
    big = big[:int(H * reps_v), :int(W * reps_u)]
    return np.asarray(to_img(big).resize((out_w, out_h), Image.LANCZOS)).astype(np.float64) / 255.0


def shade(alb, nrm, ldir, amb=0.25, gain=1.0, L=1.0):
    """Ламберт по карте нормалей (касательное пространство: x = u вправо, y = v вниз, z — наружу)"""
    n = nrm * 2.0 - 1.0
    n[..., 0] *= gain
    n[..., 1] *= gain
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    ld = np.array(ldir, float)
    ld /= np.linalg.norm(ld)
    lam = np.clip((n * ld).sum(-1), 0, None)[..., None]
    return tonemap(s2l(alb) * LIGHT * L * (amb + (1 - amb) * lam / max(ld[2], 0.2)))


def cmd_sheet(out):
    """Лист: каждая текстура 2×2 повтора (плюс сдвиг на полпериода — проверка стыков на глаз)"""
    names = [n for n in SCALE if os.path.exists(os.path.join(TEX, n + ".png"))]
    cell = 256
    cols = 6
    rows = (len(names) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cell, rows * (cell + 16)), (20, 20, 20))
    d = ImageDraw.Draw(sheet)
    for i, n in enumerate(names):
        img = load(n)
        su, sv = SCALE[n]
        ru, rv = 2.0, 2.0 * (su / sv) if sv < su else 2.0
        if n == "baseboard":
            ru, rv = 2.0, 2.0
        t = resample(img, cell, cell, ru, rv if n not in ("wall_school", "wall_school_dirty") else 1.0)
        x, y = (i % cols) * cell, (i // cols) * (cell + 16)
        sheet.paste(to_img(tonemap(s2l(t) * LIGHT * 1.0)), (x, y + 16))
        d.text((x + 4, y + 2), n, fill=(230, 230, 230))
    sheet.save(os.path.join(out, "tex_sheet.png"))


def cmd_lit(out):
    """Крупный план 0.6 × 0.6 м под скользящим светом сверху-слева: проверка карт нормалей"""
    names = [n for n in SCALE if os.path.exists(os.path.join(TEX, n + "_n.png"))]
    cell = 300
    cols = 5
    rows = (len(names) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cell, rows * (cell + 16)), (20, 20, 20))
    d = ImageDraw.Draw(sheet)
    for i, n in enumerate(names):
        su, sv = SCALE[n]
        alb, nrm = load(n), load(n + "_n")
        H, W = alb.shape[:2]
        cw = min(W, int(W * 0.6 / su))
        ch = min(H, int(H * 0.6 / sv))
        a = alb[:ch, :cw]
        nn = nrm[:ch, :cw]
        img = shade(a, nn, (-0.6, -0.6, 0.55), amb=0.15, L=1.4)
        im = to_img(img).resize((cell, cell), Image.LANCZOS)
        x, y = (i % cols) * cell, (i // cols) * (cell + 16)
        sheet.paste(im, (x, y + 16))
        d.text((x + 4, y + 2), n + " (light top-left)", fill=(230, 230, 230))
    sheet.save(os.path.join(out, "tex_lit.png"))


def lamp_light(px, pz, lamps, h):
    """Освещённость точки потолочными лампами (точечные, 1/r², косинус)"""
    L = np.zeros_like(px)
    for lx, lz in lamps:
        dx, dz = px - lx, pz - lz
        r2 = dx * dx + dz * dz + h * h
        L += h / np.sqrt(r2) / r2
    return L


def cmd_wall(out):
    """Стена 4.8 × 3.2 м (1 px = 4 мм): обои + плинтус + маска износа wall_grime, свет от ламп у стены"""
    Wm, Hm, ppm = 4.8, 3.2, 250
    W, H = int(Wm * ppm), int(Hm * ppm)
    x = (np.arange(W) + 0.5) / ppm
    y = (np.arange(H) + 0.5) / ppm               # вниз от потолка
    X, Y = np.meshgrid(x, y)
    for variant in ("wall_yellow", "wall_old", "wall_house", "wall_paint"):
        alb = load(variant)
        dirty = load(variant + "_dirty")
        nrm = load(variant + "_n")
        u = X / 1.2
        v = Y / 1.2                             # верх картинки = верх стены
        a = sample(alb, u, v, px_per_rep=1.2 * ppm)
        b = sample(dirty, u, v, px_per_rep=1.2 * ppm)
        n = sample(nrm, u, v, px_per_rep=1.2 * ppm)
        g = sample(load("wall_grime"), X / 4.8, Y / 3.2, wrap_v=False)
        noise = load("noise")
        nz = sample(noise, X * 0.06 + 0.3, Y * 0.03)
        dm = np.clip((nz[..., 0] * 0.7 + nz[..., 2] * 0.3 - 0.52) / 0.2, 0, 1)[..., None]
        col = a * (1 - dm) + b * dm
        damp = np.array([0.80, 0.75, 0.62])
        col = col * (1 - g[..., 0:1] * 0.35 * (1 - damp)) * (1 - g[..., 1:2] * (1 - np.array([0.78, 0.72, 0.6])) * 0.8)
        col = col * (1 - g[..., 2:3] * (1 - np.array([0.72, 0.66, 0.54])))
        # плинтус
        hb = Hm - Y
        base = hb < 0.1
        bb = sample(load("baseboard"), X / 1.2, (0.1 - hb) / 0.1, wrap_v=False, px_per_rep=1.2 * ppm)
        bn = sample(load("baseboard_n"), X / 1.2, (0.1 - hb) / 0.1, wrap_v=False, px_per_rep=1.2 * ppm)
        col = np.where(base[..., None], bb, col)
        n = np.where(base[..., None], bn, n)
        # свет: лампы в 1.2 м от стены, через 2.4 м, на высоте 3.2
        Lmap = np.zeros(X.shape)
        nn = n * 2 - 1
        nn /= np.linalg.norm(nn, axis=-1, keepdims=True)
        for lx in (0.0, 2.4, 4.8):
            dx = lx - X
            dy = -Y + 0.0                          # к потолку (вверх = −y картинки)
            dz = 1.2
            r = np.sqrt(dx * dx + dy * dy + dz * dz)
            ldir = np.stack([dx / r, dy / r, dz / r], -1)   # u вправо, v вниз → свет сверху: v отрицательна
            Lmap += np.clip((nn * ldir).sum(-1), 0, None) / (r * r) * 2.2
        Lmap = Lmap * (0.62 + 0.38 * np.clip((Hm - Y) / 0.7, 0, 1)) + 0.12
        img = tonemap(s2l(col) * LIGHT * Lmap[..., None])
        to_img(img).save(os.path.join(out, "wall_%s.png" % variant))


def cmd_floor(out):
    """Ковёр 6 × 4 м сверху (1 px = 5 мм) с картой carpet_damp, а также вид под углом (перспектива)"""
    for name in ("carpet", "carpet_old", "concrete_floor", "tile", "linoleum", "wood_floor"):
        Wm, Hm, ppm = 4.8, 3.2, 200
        W, H = int(Wm * ppm), int(Hm * ppm)
        X, Y = np.meshgrid((np.arange(W) + 0.5) / ppm, (np.arange(H) + 0.5) / ppm)
        su, sv = SCALE[name]
        a = sample(load(name), X / su, Y / sv, px_per_rep=su * ppm)
        n = sample(load(name + "_n"), X / su, Y / sv, px_per_rep=su * ppm)
        if name == "carpet":
            b = sample(load("carpet_wet"), X / su, Y / sv, px_per_rep=su * ppm)
            cd = sample(load("carpet_damp"), X / 9.6, Y / 9.6)
            a = a * (1 - cd[..., 0:1] * 0.6) + b * cd[..., 0:1] * 0.6
            a = a * (1 + cd[..., 1:2] * 0.08)
        nn = n * 2 - 1
        nn /= np.linalg.norm(nn, axis=-1, keepdims=True)
        Lmap = np.zeros(X.shape)
        for lx, lz in ((1.2, 1.2), (3.6, 1.2), (1.2, 3.6), (3.6, 3.6), (1.2, -1.2), (3.6, -1.2)):
            dx, dz, dy = lx - X, lz - Y, 3.2
            r = np.sqrt(dx * dx + dz * dz + dy * dy)
            ldir = np.stack([dx / r, dz / r, dy / r], -1)
            Lmap += np.clip((nn * ldir).sum(-1), 0, None) / (r * r) * 9.0
        img = tonemap(s2l(a) * LIGHT * (Lmap[..., None] + 0.1))
        to_img(img).save(os.path.join(out, "floor_%s.png" % name))


def cmd_ceil(out):
    """Потолок 4.8 × 4.8 м снизу: ceiling_tile со сдвигом u на 0.3 м, светильники 0.6 × 1.2 м в центре
    каждой клетки 2.4 м, пятна ceil_stains"""
    Wm, ppm = 4.8, 200
    W = int(Wm * ppm)
    X, Z = np.meshgrid((np.arange(W) + 0.5) / ppm, (np.arange(W) + 0.5) / ppm)
    a = sample(load("ceiling_tile"), (X + 0.3) / 1.2, Z / 1.2, px_per_rep=1.2 * ppm)
    b = sample(load("ceiling_tile_dirty"), (X + 0.3) / 1.2, Z / 1.2, px_per_rep=1.2 * ppm)
    n = sample(load("ceiling_tile_n"), (X + 0.3) / 1.2, Z / 1.2, px_per_rep=1.2 * ppm)
    st = sample(load("ceil_stains"), (X + 0.3) / 9.6, Z / 9.6)
    nz = sample(load("noise"), X * 0.06, Z * 0.06)
    dm = np.clip((nz[..., 0] - 0.5) / 0.2, 0, 1)[..., None]
    col = a * (1 - dm) + b * dm
    col = col * (1 - st[..., 0:1] * (1 - np.array([0.62, 0.5, 0.32]))) * (1 - st[..., 1:2] * (1 - np.array([0.85, 0.76, 0.58])))
    nn = n * 2 - 1
    nn /= np.linalg.norm(nn, axis=-1, keepdims=True)
    L = np.zeros(X.shape)
    lamps = [(1.2, 1.2), (3.6, 1.2), (1.2, 3.6), (3.6, 3.6)]
    for lx, lz in lamps:
        dx, dz = lx - X, lz - Z
        r = np.sqrt(dx * dx + dz * dz + 0.3 ** 2)
        ldir = np.stack([dx / r, dz / r, 0.3 / r], -1)
        L += np.clip((nn * ldir).sum(-1), 0, None) / (r * r) * 0.9
    L += 0.35
    img = tonemap(s2l(col) * LIGHT * L[..., None])
    fx = load("fixture", "RGBA")
    for lx, lz in lamps:
        u = (X - (lx - 0.3)) / 0.6
        v = (Z - (lz - 0.6)) / 1.2
        m = (u >= 0) & (u < 1) & (v >= 0) & (v < 1)
        s = sample(fx, np.clip(u, 0, 0.999), np.clip(v, 0, 0.999), wrap_v=False)
        em = tonemap(s2l(s[..., :3]) * LIGHT * 3.2)
        fr = tonemap(s2l(s[..., :3]) * LIGHT * 1.0)
        f = em * s[..., 3:4] + fr * (1 - s[..., 3:4])
        img = np.where(m[..., None], f, img)
    to_img(img).save(os.path.join(out, "ceil_view.png"))
    # «мёртвый» светильник крупно
    s = fx[..., :3]
    to_img(np.concatenate([tonemap(s2l(s) * LIGHT * 3.0), tonemap(s2l(s) * LIGHT * 0.84)], 1)).save(os.path.join(out, "fixture_onoff.png"))


def cmd_swatch(out):
    """Калибровка: средний цвет альбедо главных поверхностей при разной освещённости (Filmic и AgX)"""
    items = [("wall_yellow", "обои"), ("wall_yellow_dirty", "обои грязн."), ("carpet", "ковёр"), ("carpet_wet", "ковёр мокрый"),
             ("ceiling_tile", "потолок"), ("baseboard", "плинтус"), ("wall_old", "старые обои"), ("carpet_old", "старый ковёр"),
             ("wall_house", "обои дома"), ("wall_paint", "краска"), ("concrete", "бетон"), ("tile", "кафель")]
    levels = (0.35, 0.6, 1.0, 1.6, 2.4)
    cw, chh = 96, 46
    left = 200
    im = Image.new("RGB", (left + cw * len(levels) * 2 + 20, 48 + chh * len(items)), (24, 24, 24))
    d = ImageDraw.Draw(im)
    for t, (tname, fn) in enumerate((("Filmic (white 3)", tonemap), ("AgX", tonemap_agx))):
        x0 = left + t * (cw * len(levels) + 20)
        d.text((x0 + 4, 4), tname, fill=(255, 220, 120))
        for j, L in enumerate(levels):
            d.text((x0 + j * cw + 6, 24), "light x%.2f" % L, fill=(220, 220, 220))
        for i, (n, label) in enumerate(items):
            if not os.path.exists(os.path.join(TEX, n + ".png")):
                continue
            a = load(n)
            mean = s2l(a).reshape(-1, 3).mean(0)
            if t == 0:
                srgb = l2s(mean) * 255
                d.text((6, 48 + i * chh + 8), n, fill=(230, 230, 230))
                d.text((6, 48 + i * chh + 24), "albedo %d,%d,%d" % tuple(np.round(srgb)), fill=(160, 160, 160))
            for j, L in enumerate(levels):
                c = fn(mean * LIGHT * L) * 255
                d.rectangle([x0 + j * cw, 48 + i * chh, x0 + (j + 1) * cw - 4, 48 + (i + 1) * chh - 4], fill=tuple(int(v) for v in c))
                d.text((x0 + j * cw + 4, 48 + i * chh + 28), "%d,%d,%d" % tuple(int(v) for v in c), fill=(0, 0, 0) if c.mean() > 120 else (230, 230, 230))
    im.save(os.path.join(out, "swatch.png"))


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    what = sys.argv[2] if len(sys.argv) > 2 else "all"
    for k, fn in (("sheet", cmd_sheet), ("lit", cmd_lit), ("wall", cmd_wall), ("floor", cmd_floor), ("ceil", cmd_ceil), ("swatch", cmd_swatch)):
        if what in (k, "all"):
            fn(out)
            print("  ", k)


if __name__ == "__main__":
    main()
