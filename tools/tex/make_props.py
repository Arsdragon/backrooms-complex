"""Текстуры предметов: плесень и потёки на обоях, разводы протечек на потолке, листы бумаги, костюм химзащиты.

    python tools/tex/make_props.py [имя ...]   → tex/prop_*.png (+ карты нормалей prop_*_n.png)

- наклейки (prop_mold_*, prop_tide_*) — RGBA, к краю альфа 0 (шейдер decal: repeat_disable, цвет из текстуры);
  цвет — альбедо пятна в sRGB, плотность — альфа; разные силуэты, чтобы одно и то же пятно не повторялось;
- prop_paper_* — лист A4 (512×724, 2,4 px/мм): машинопись, бланк, распечатка на перфорированной ленте,
  сгибы и мятость запечены светом/тенью, края чуть пожелтели;
- prop_hazmat — костюм химзащиты на развёртке Rocketbox Fire_Male_01 (humans/…/m138_body_color.tga):
  ткань → жёлтый прорезиненный материал со складками исходника, светоотражающие полосы → сварные швы,
  надписи и нашивки стёрты, перчатки и сапоги — чёрная резина, на стыке с ними — серая лента;
  prop_hazmat_n — карта нормалей складок (x вдоль +u, y вдоль +v вниз, как у make_textures.py);
- бесшовные ткани: prop_cubicle(+_n) — твид офисных перегородок, prop_gingham — клетчатый плед для пикника,
  prop_sleepbag(+_n) — стёганый спальник; prop_cart_side — выцветшая наклейка «ICE CREAM» на борт тележки (RGBA).
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage as ndi

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "tex")
F32 = np.float32


def R(seed):
    return np.random.default_rng(seed)


def fbm(shape, seed, scales=(48, 20, 8, 3), amps=(1.0, 0.55, 0.3, 0.15)):
    """Плавный шум: сумма размытых белых шумов (не периодичный — для наклеек), среднее 0, СКО ~1"""
    rg = R(seed)
    acc = np.zeros(shape, F32)
    for s, a in zip(scales, amps):
        n = ndi.gaussian_filter(rg.standard_normal(shape).astype(F32), s)
        acc += a * n / (n.std() + 1e-6)
    return acc / (acc.std() + 1e-6)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def grid(n, m=None):
    m = m or n
    y, x = np.mgrid[0:m, 0:n].astype(F32)
    return (x + 0.5) / n * 2.0 - 1.0, (y + 0.5) / m * 2.0 - 1.0


def save_rgba(name, rgb, a):
    img = np.dstack([np.clip(rgb, 0, 255), np.clip(a * 255.0, 0, 255)]).astype(np.uint8)
    Image.fromarray(img, "RGBA").save(os.path.join(OUT, name + ".png"))
    print("tex/%s.png" % name)


def save_rgb(name, rgb):
    Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB").save(os.path.join(OUT, name + ".png"))
    print("tex/%s.png" % name)


def dots(shape, pts, rad, soft=0.8):
    """Мягкие кружки (колонии): pts — (x, y) в пикселях, rad — радиусы. Возвращает покрытие 0..1"""
    h, w = shape
    out = np.zeros(shape, F32)
    for (x, y), r in zip(pts, rad):
        x0, x1 = int(max(x - r - 3, 0)), int(min(x + r + 4, w))
        y0, y1 = int(max(y - r - 3, 0)), int(min(y + r + 4, h))
        if x1 <= x0 or y1 <= y0:
            continue
        yy, xx = np.mgrid[y0:y1, x0:x1].astype(F32)
        d = np.sqrt((xx - x) ** 2 + (yy - y) ** 2)
        c = np.clip((r - d) / soft + 0.5, 0.0, 1.0)
        out[y0:y1, x0:x1] = np.maximum(out[y0:y1, x0:x1], c)
    return out


def edge_fade(n, w=0.12):
    x, y = grid(n)
    return smooth(1.0, 1.0 - w, np.maximum(np.abs(x), np.abs(y)))


# ----------------------------------------------------------------- плесень и потёки на обоях

def mold(variant):
    n = 512
    x, y = grid(n)
    rg = R(100 + variant)
    if variant == 0:
        # чёрная колония: густые точки в середине, редкие к краю, вокруг — серо-бурый ореол
        lo = fbm((n, n), 11, (60, 24, 9), (1.0, 0.5, 0.25))
        r = np.sqrt((x * 1.05) ** 2 + (y * 0.95) ** 2) + lo * 0.22
        body = smooth(0.95, 0.25, r)
        dens = body ** 1.6
        pts, rad = [], []
        for _ in range(5200):
            px, py = rg.uniform(0, n, 2)
            if rg.random() < dens[int(py), int(px)] * 0.8:
                pts.append((px, py))
                rad.append(rg.uniform(0.6, 2.0) * (1.0 + 1.1 * dens[int(py), int(px)]))
        cov = dots((n, n), pts, rad, 1.3)
        cov = np.maximum(cov * 0.85, ndi.gaussian_filter(cov, 4) * 0.9)
        halo = smooth(0.95, 0.3, r) * (0.5 + 0.5 * smooth(-0.6, 0.8, fbm((n, n), 12, (14, 5), (1.0, 0.4))))
        a = np.clip(cov * 0.85 + halo * 0.38, 0, 1)
        k = cov[..., None]
        rgb = (1 - k) * np.array([92, 82, 58], F32) + k * np.array([26, 30, 22], F32)
    elif variant == 1:
        # серо-зелёный налёт: широкий, мягкий, пятнами, с крапинками
        lo = fbm((n, n), 21, (70, 30, 12), (1.0, 0.6, 0.3))
        r = np.sqrt(x ** 2 + y ** 2) * 1.05 + lo * 0.3
        body = smooth(0.95, 0.35, r)
        patch = smooth(-0.3, 0.9, fbm((n, n), 22, (16, 6), (1.0, 0.5)))
        pts = rg.uniform(0, n, (900, 2))
        keep = [p for p in pts if rg.random() < body[int(p[1]), int(p[0])] * 0.8]
        cov = dots((n, n), keep, rg.uniform(0.6, 2.2, len(keep)), 1.0)
        a = np.clip(body * (0.18 + 0.32 * patch) + cov * body * 0.6, 0, 1)
        k = np.clip(cov * 0.8 + patch * 0.3, 0, 1)[..., None]
        rgb = (1 - k) * np.array([118, 116, 84], F32) + k * np.array([46, 54, 40], F32)
    elif variant == 2:
        # потёк воды: бурая кромка-«прилив» по краю, светлая середина, внизу языки потёков, вверху — точки плесени
        lo = fbm((n, n), 31, (50, 20, 7), (1.0, 0.5, 0.25))
        # капля: шире сверху, языки вниз
        xx = x * (1.15 + 0.35 * np.clip(y, 0, 1))
        r = np.sqrt(xx ** 2 + (y * 0.85 + 0.1) ** 2) + lo * 0.18
        tongues = np.zeros_like(r)
        for _ in range(5):
            cx = rg.uniform(-0.5, 0.5)
            wdt = rg.uniform(0.03, 0.08)
            ln = rg.uniform(0.4, 0.95)
            tongues = np.maximum(tongues, smooth(wdt, 0.0, np.abs(x - cx - lo * 0.03)) * smooth(ln, ln - 0.3, y) * smooth(-0.1, 0.2, y))
        field = np.minimum(r, 1.0 - tongues * 0.55)
        level = 0.78
        inner = smooth(level, level - 0.12, field)
        rim = np.exp(-((field - level) / 0.018) ** 2) * (field > level - 0.05) + np.exp(-((field - level) / 0.05) ** 2) * 0.35
        ring2 = np.exp(-((field - level * 0.72) / 0.02) ** 2) * 0.45
        top = smooth(0.2, -0.6, y) * inner
        pts = rg.uniform(0, n, (600, 2))
        keep = [p for p in pts if rg.random() < top[int(p[1]), int(p[0])] * 0.5]
        cov = dots((n, n), keep, rg.uniform(0.7, 2.5, len(keep)), 1.0)
        a = np.clip(inner * 0.22 + rim * 0.62 + ring2 * inner * 0.5 + cov * 0.85, 0, 1)
        k = np.clip(rim + ring2, 0, 1)[..., None]
        rgb = (1 - k) * np.array([170, 138, 78], F32) + k * np.array([112, 78, 36], F32)
        c = cov[..., None]
        rgb = (1 - c) * rgb + c * np.array([34, 36, 28], F32)
    else:
        # пятна, расползшиеся по обоям: несколько мелких колоний на общем буром налёте
        lo = fbm((n, n), 41, (40, 16), (1.0, 0.5))
        r = np.sqrt((x * 0.9) ** 2 + (y * 1.1) ** 2) + lo * 0.25
        area = smooth(0.95, 0.5, r)
        cov = np.zeros((n, n), F32)
        for _ in range(9):
            cx, cy = rg.uniform(0.2, 0.8, 2) * n
            m = 120
            pts = rg.normal(0, rg.uniform(10, 34), (m, 2)) + (cx, cy)
            cov = np.maximum(cov, dots((n, n), pts, rg.uniform(0.6, 2.6, m), 1.0))
        cov *= area
        film = area * smooth(-0.2, 1.0, fbm((n, n), 42, (24, 8), (1.0, 0.4))) * 0.22
        a = np.clip(cov * 0.88 + ndi.gaussian_filter(cov, 4) * 0.5 + film, 0, 1)
        k = np.clip(cov + ndi.gaussian_filter(cov, 3) * 0.6, 0, 1)[..., None]
        rgb = (1 - k) * np.array([128, 108, 66], F32) + k * np.array([30, 33, 26], F32)
    a *= edge_fade(n)
    save_rgba("prop_mold_%s" % "abcd"[variant], rgb, a)


# ----------------------------------------------------------------- разводы протечки на потолке

def tide(variant):
    n = 512
    x, y = grid(n)
    rg = R(200 + variant)
    lo = fbm((n, n), 210 + variant, (90, 40, 16), (1.0, 0.4, 0.12))
    sx, sy = [(1.0, 1.0), (1.25, 0.85), (0.9, 1.15)][variant]
    r = np.sqrt((x * sx) ** 2 + (y * sy) ** 2) + lo * 0.14
    levels = [[0.86, 0.66, 0.42], [0.84, 0.58], [0.88, 0.74, 0.6, 0.34]][variant]
    a = np.zeros((n, n), F32)
    rim_all = np.zeros((n, n), F32)
    for i, lv in enumerate(levels):
        lv2 = lv + fbm((n, n), 220 + variant * 7 + i, (40, 14), (1.0, 0.3)) * 0.02
        d = r - lv2
        # кромка: снаружи резкая, внутрь расплывается
        rim = np.where(d > 0, np.exp(-(d / 0.010) ** 2), np.exp(-(d / 0.045) ** 2))
        w = 1.0 - i * 0.18
        rim_all = np.maximum(rim_all, rim * w)
    fill = smooth(levels[0], levels[0] - 0.25, r) * (0.55 + 0.45 * smooth(-0.8, 0.8, fbm((n, n), 230 + variant, (20, 7), (1.0, 0.4))))
    a = np.clip(fill * 0.2 + rim_all * 0.62, 0, 1)
    k = rim_all[..., None]
    rgb = (1 - k) * np.array([196, 168, 112], F32) + k * np.array([150, 110, 52], F32)
    a *= edge_fade(n, 0.08)
    save_rgba("prop_tide_%s" % "abc"[variant], rgb, a)


# ----------------------------------------------------------------- листы бумаги

WORDS = ("ASYNC FOUNDATION PERSONNEL MUST NOT ENTER ZONE BEYOND MARKER WITHOUT TETHER REPORT ALL ANOMALIES TO "
         "SUPERVISOR SECTION SUBJECT DATE RE MEMO STATION KV31 SAMPLE SURVEY THE OF AND TO IN FOR IS ON THAT BY "
         "THIS WITH ROOM CORRIDOR LIGHT LEVEL DOOR HALL PLEASE NOTE ACCESS DENIED PROCEDURE INVENTORY TOTAL "
         "QUANTITY ITEM DESCRIPTION SIGNED APPROVED REVIEW 1989 1990 JULY JUNE NO YES CHECK").split()


def _font(names, size):
    for nm in names:
        p = os.path.join(os.environ.get("WINDIR", "C:/Windows"), "Fonts", nm)
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def _line(rg, nwords):
    return " ".join(rg.choice(WORDS) for _ in range(nwords))


def paper(variant):
    w, h = 512, 724
    rg = R(300 + variant)
    base = np.array([236, 232, 216], F32)
    if variant == 2:
        base = np.array([232, 234, 222], F32)
    img = Image.new("RGB", (w, h), tuple(int(c) for c in base))
    d = ImageDraw.Draw(img)
    mono = _font(["cour.ttf", "lucon.ttf", "consola.ttf"], 13)
    monob = _font(["courbd.ttf", "cour.ttf"], 18)
    hand = _font(["segoepr.ttf", "Inkfree.ttf", "comic.ttf"], 22)
    ink = (52, 50, 54)
    if variant == 0:
        # машинописная служебная записка
        d.text((60, 60), "MEMORANDUM", font=monob, fill=ink)
        for i, lab in enumerate(["TO:", "FROM:", "DATE:", "RE:"]):
            d.text((60, 100 + i * 20), lab + "  " + _line(rg, rg.integers(2, 5)), font=mono, fill=ink)
        d.line((60, 188, 452, 188), fill=ink, width=2)
        y = 205
        for p in range(4):
            for _ in range(rg.integers(4, 8)):
                d.text((60, y), _line(rg, rg.integers(5, 8))[:52], font=mono, fill=ink)
                y += 17
            y += 14
        d.text((300, y + 20), _line(rg, 2).title(), font=hand, fill=(30, 40, 110))
    elif variant == 1:
        # бланк: таблица, графы, пометки ручкой
        d.text((60, 54), "INVENTORY / FORM 14-D", font=monob, fill=ink)
        x0, x1 = 50, 462
        y = 100
        cols = [x0, 120, 330, 400, x1]
        for r in range(26):
            d.line((x0, y, x1, y), fill=(110, 110, 120), width=1)
            if r > 0 and rg.random() < 0.75:
                d.text((cols[0] + 6, y + 3), str(r), font=mono, fill=ink)
                d.text((cols[1] + 6, y + 3), _line(rg, rg.integers(1, 3))[:22], font=mono, fill=ink)
                d.text((cols[2] + 6, y + 3), str(rg.integers(1, 40)), font=mono, fill=ink)
                if rg.random() < 0.5:
                    d.text((cols[3] + 8, y - 2), "v", font=hand, fill=(30, 40, 110))
            y += 22
        d.line((x0, y, x1, y), fill=(110, 110, 120), width=1)
        for cx in cols:
            d.line((cx, 100, cx, y), fill=(110, 110, 120), width=1)
        d.text((70, y + 30), _line(rg, 3).lower(), font=hand, fill=(30, 40, 110))
    elif variant == 2:
        # распечатка на ленте: зелёные полосы, перфорация по краям, матричный шрифт
        for k in range(0, h, 76):
            d.rectangle((38, k, w - 38, k + 37), fill=(200, 224, 198))
        for k in range(14, h, 30):
            for cx in (16, w - 16):
                d.ellipse((cx - 6, k - 6, cx + 6, k + 6), fill=(70, 66, 60))
        d.line((32, 0, 32, h), fill=(205, 200, 185), width=1)
        d.line((w - 32, 0, w - 32, h), fill=(205, 200, 185), width=1)
        y = 30
        while y < h - 30:
            if rg.random() < 0.85:
                s = "%05d " % rg.integers(0, 99999) + _line(rg, rg.integers(3, 6))
                d.text((52, y), s[:50], font=mono, fill=(60, 60, 70))
            y += 19
    else:
        # пустой лист с кольцом от кружки и бледной надписью от руки
        d.text((80, 110), _line(rg, 3).lower(), font=hand, fill=(40, 40, 50))
        d.text((90, 150), _line(rg, 2).lower(), font=hand, fill=(40, 40, 50))
        cx, cy, rr = 330, 470, 62
        for k in range(3):
            d.ellipse((cx - rr - k, cy - rr - k, cx + rr + k, cy + rr + k), outline=(170, 130, 80), width=2)
    a = np.asarray(img).astype(F32)
    # смазать печать: тонер/лента впитались в бумагу
    a = ndi.gaussian_filter(a, (0.6, 0.6, 0))
    yy, xx = np.mgrid[0:h, 0:w].astype(F32)
    # пожелтение к краям и пятна
    edge = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy))
    yel = smooth(30.0, 0.0, edge) * 0.5 + np.clip(fbm((h, w), 330 + variant, (60, 20), (1.0, 0.5)), 0, None) * 0.08
    a = a * (1.0 - yel[..., None] * np.array([0.04, 0.09, 0.22], F32))
    # сгибы: письмо сложено втрое (у ленты — по перфорации), плюс мятость
    shade = np.ones((h, w), F32)
    folds = [h / 3.0, 2.0 * h / 3.0] if variant != 2 else [h * 0.5]
    for fy in folds:
        dd = yy - fy - (xx - w / 2) * rg.uniform(-0.02, 0.02)
        shade -= 0.10 * np.exp(-(dd / 1.6) ** 2)
        shade += 0.035 * np.sign(dd) * np.exp(-np.abs(dd) / 30.0)
    if variant in (1, 3):
        # смятый лист: сеть мягких складок
        cr = fbm((h, w), 340 + variant, (34, 14, 6), (1.0, 0.5, 0.15))
        gy, gx = np.gradient(cr)
        shade += (gx * 0.6 - gy * 0.4) * 1.6
        ridge = np.abs(ndi.gaussian_filter(cr, 2))
        shade -= smooth(0.12, 0.0, ridge) * 0.05
    if variant == 3:
        # след подошвы
        # серый след подошвы: мягкое пятно грязи
        sole = smooth(1.0, 0.5, np.sqrt(((xx - 180) / 70.0) ** 2 + ((yy - 520) / 150.0) ** 2))
        shade -= sole * np.clip(0.5 + 0.5 * fbm((h, w), 351, (6, 2), (1.0, 0.5)), 0, 1) * 0.09
    a *= np.clip(shade, 0.7, 1.1)[..., None]
    save_rgb("prop_paper_%s" % "abcd"[variant], a)


# ----------------------------------------------------------------- костюм химзащиты

def hazmat():
    src = os.path.join(ROOT, "humans", "Fire_Male_01", "Textures", "m138_body_color.tga")
    if not os.path.exists(src):
        print("нет", src)
        return
    im = np.asarray(Image.open(src).convert("RGB")).astype(F32) / 255.0
    h, w = im.shape[:2]
    mx = im.max(axis=2)
    mn = im.min(axis=2)
    lum = im @ np.array([0.3, 0.59, 0.11], F32)
    sat = (mx - mn) / (mx + 1e-4)
    # фон развёртки (чистый чёрный) — не трогаем
    bg = mx < 0.012
    # светоотражающие полосы и вставки (светлые серые) и жёлтые канты
    silver = (lum > 0.33) & (sat < 0.32)
    yel = (im[..., 0] > 0.45) & (im[..., 1] > 0.33) & (im[..., 2] < 0.25)
    red = (im[..., 0] > 0.35) & (im[..., 0] > im[..., 1] * 1.6)
    stripe = silver | yel
    # надписи/нашивки: светлое тонкое (исчезает при размыкании) и красное
    thin = stripe & ~ndi.binary_opening(stripe, iterations=4)
    letters = ndi.binary_dilation(thin | red, iterations=3)
    stripe = stripe & ~letters
    # перчатки и сапоги: почти чёрное в нижней четверти развёртки
    yy, xx = np.mgrid[0:h, 0:w]
    # ткань костюма — синеватая (b > r), перчатки и сапоги — нейтрально-тёплые: отличаем по сглаженному цвету
    blur = np.stack([ndi.gaussian_filter(im[..., c], 3) for c in range(3)], -1)
    warm = (blur[..., 2] - blur[..., 0]) < -0.002
    dark = warm & (blur.max(axis=2) < 0.2) & ~bg & (yy > h * 0.7)
    dark = ndi.binary_closing(ndi.binary_opening(dark, iterations=3), iterations=6)
    lab, nl = ndi.label(dark)
    sizes = ndi.sum(dark, lab, range(1, nl + 1))
    keep = np.isin(lab, [i + 1 for i, sz in enumerate(sizes) if sz > 1500])
    rubber = ndi.binary_fill_holes(keep) & ~bg
    # «ткань» для оттенка: середина по окрестности без надписей
    fab = ~bg & ~stripe & ~letters & ~rubber
    lum_f = np.where(fab, lum, 0.0).astype(F32)
    wsum = ndi.gaussian_filter(fab.astype(F32), 18) + 1e-4
    base = ndi.gaussian_filter(lum_f, 18) / wsum
    lum2 = np.where(letters | stripe, base, lum)
    # складки: отношение к локальному среднему (мягко)
    detail = ndi.gaussian_filter(lum2, 1.2) / (ndi.gaussian_filter(lum2, 14) + 0.02)
    detail = np.clip(1.0 + (detail - 1.0) * 0.85, 0.55, 1.35)
    grime = np.clip(fbm((h, w), 501, (40, 12, 4), (1.0, 0.5, 0.3)), -2, 2)
    suit = np.array([0.84, 0.66, 0.12], F32)
    col = suit[None, None, :] * detail[..., None] * (1.0 - 0.06 * grime[..., None])
    # швы по краям бывших полос: тонкая тёмная линия
    edge = ndi.binary_dilation(stripe, iterations=2) & ~ndi.binary_erosion(stripe, iterations=2)
    seam = ndi.gaussian_filter(edge.astype(F32), 1.0)
    col *= (1.0 - 0.28 * seam)[..., None]
    # полоса тоже жёлтая, чуть глаже и светлее (сварная вставка)
    col = np.where(stripe[..., None], col * 1.06, col)
    # резина: тёмная, с бликами исходника
    rub = np.clip(lum / 0.08, 0.35, 1.6)[..., None] * np.array([0.05, 0.052, 0.045], F32)
    col = np.where(rubber[..., None], rub, col)
    # серая лента на стыке перчаток/сапог с костюмом
    tape = ndi.binary_dilation(rubber, iterations=10) & ~rubber & ~bg & (yy > h * 0.62)
    tape_c = np.array([0.42, 0.42, 0.4], F32)[None, None, :] * (0.9 + 0.1 * np.clip(detail, 0.8, 1.2))[..., None]
    col = np.where(tape[..., None], tape_c, col)
    col = np.where(bg[..., None], 0.0, col)
    # раздвинуть цвета за границы островов развёртки (мип-карты не тянут чёрный фон)
    inside = ~bg
    fill = col.copy()
    for _ in range(6):
        grown = np.stack([ndi.grey_dilation(np.where(inside, fill[..., c], -1.0), size=5) for c in range(3)], -1)
        fill = np.where(inside[..., None], fill, np.maximum(grown, 0.0))
        inside = ndi.binary_dilation(inside, iterations=2)
    save_rgb("prop_hazmat", np.clip(fill, 0, 1) ** (1.0) * 255.0)
    # карта нормалей складок: высота — сглаженная светлота (тёмные заломы — вниз), швы — углубление
    hgt = ndi.gaussian_filter(lum2, 1.6) - ndi.gaussian_filter(lum2, 10)
    hgt = hgt / (np.abs(hgt).max() + 1e-4) - seam * 0.25
    hgt = np.where(rubber, ndi.gaussian_filter(lum, 1.0) * 2.0, hgt)
    gy, gx = np.gradient(hgt * 18.0)
    nrm = np.dstack([-gx, -gy, np.ones_like(gx)])
    nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)
    save_rgb("prop_hazmat_n", (nrm * 0.5 + 0.5) * 255.0)


# ----------------------------------------------------------------- бесшовные ткани предметов

def fbm_wrap(shape, seed, scales=(48, 20, 8, 3), amps=(1.0, 0.55, 0.3, 0.15)):
    """Как fbm, но бесшовный (размытие с заворотом краёв) — для повторяющихся текстур"""
    rg = R(seed)
    acc = np.zeros(shape, F32)
    for s, a in zip(scales, amps):
        n = ndi.gaussian_filter(rg.standard_normal(shape).astype(F32), s, mode="wrap")
        acc += a * n / (n.std() + 1e-6)
    return acc / (acc.std() + 1e-6)


def save_normal(name, hgt, k):
    """Карта нормалей из высоты (x вдоль +u, y вдоль +v вниз), градиент с заворотом — бесшовно"""
    gx = (np.roll(hgt, -1, 1) - np.roll(hgt, 1, 1)) * 0.5 * k
    gy = (np.roll(hgt, -1, 0) - np.roll(hgt, 1, 0)) * 0.5 * k
    nrm = np.dstack([-gx, -gy, np.ones_like(gx)])
    nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)
    save_rgb(name, (nrm * 0.5 + 0.5) * 255.0)


def _weave(n, period, seed):
    """Полотняное переплетение: нити по x и y с периодом period px, перекрытия «вверх/вниз» в шахматку;
    толщина нитей гуляет (неровная пряжа). Возвращает (высота, доля нити по x 0..1)"""
    y, x = np.mgrid[0:n, 0:n].astype(F32)
    rg = R(seed)
    jx = ndi.gaussian_filter1d(rg.standard_normal(n).astype(F32), 6, mode="wrap") * 0.18
    jy = ndi.gaussian_filter1d(rg.standard_normal(n).astype(F32), 6, mode="wrap") * 0.18
    px = (x / period + jy[:, None] * 0.0) % 1.0
    py = (y / period) % 1.0
    tx = np.sin(np.pi * ((y / period) % 1.0)) ** 2 * (1.0 + jx[None, :] * 0.0 + jy[:, None])       # нить вдоль x
    ty = np.sin(np.pi * ((x / period) % 1.0)) ** 2 * (1.0 + jx[None, :])                           # нить вдоль y
    cx = np.floor(x / period).astype(np.int32)
    cy = np.floor(y / period).astype(np.int32)
    over = ((cx + cy) % 2 == 0)
    # сверху — та нить, что «над» в этой клетке; середина нити выше краёв
    bump_x = tx * (0.6 + 0.4 * np.sin(np.pi * px))
    bump_y = ty * (0.6 + 0.4 * np.sin(np.pi * py))
    hgt = np.where(over, np.maximum(bump_x, bump_y * 0.7), np.maximum(bump_y, bump_x * 0.7))
    which = np.where(over, (bump_x >= bump_y * 0.7), ~(bump_y >= bump_x * 0.7)).astype(F32)
    return hgt.astype(F32), which


def cubicle():
    """Сукно офисных перегородок (1990): серо-синее твидовое полотно — пёстрая пряжа (нити разных оттенков),
    мелкое переплетение, катышки и выгоревшие/затёртые пятна; светлая текстура, цвет даёт материал.
    512 px на 0,5 м (нить ~1,5 мм), бесшовно. prop_cubicle_n — рельеф переплетения"""
    n = 512
    hgt, which = _weave(n, 3.0, 701)
    rg = R(702)
    # пёстрая пряжа: каждая нить своего оттенка (по строке/столбцу), плюс крапинки
    rows = ndi.gaussian_filter1d(rg.standard_normal(n).astype(F32), 0.8, mode="wrap")
    cols = ndi.gaussian_filter1d(rg.standard_normal(n).astype(F32), 0.8, mode="wrap")
    yarn = np.where(which > 0.5, rows[:, None] + 0 * cols[None, :], cols[None, :] + 0 * rows[:, None])
    fleck = (rg.random((n, n)) < 0.012).astype(F32)
    fleck = ndi.gaussian_filter(fleck, 0.7, mode="wrap") * 3.0
    mott = fbm_wrap((n, n), 703, (60, 24, 9), (0.3, 0.6, 1.0))
    lum = 0.74 + 0.08 * yarn + 0.12 * (hgt - 0.5) + 0.012 * mott
    lum = lum - 0.12 * np.clip(fleck, 0, 1)
    # оттенок: чуть синее в тенях нитей, тёплые крапинки
    rgb = np.dstack([lum * 0.97, lum * 0.99, lum * 1.03])
    rgb[..., 0] += 0.05 * np.clip(fleck - 0.4, 0, 1)
    # затёртые пятна (руки, спинки стульев): светлее и глаже
    rub = np.clip(fbm_wrap((n, n), 704, (90, 40), (1.0, 0.5)) - 1.3, 0, 1)
    rgb = rgb * (1.0 + 0.03 * rub[..., None])
    save_rgb("prop_cubicle", np.clip(rgb, 0, 1) * 255.0)
    save_normal("prop_cubicle_n", ndi.gaussian_filter(hgt, 0.6, mode="wrap") * (1.0 - 0.5 * rub) + 0.02 * mott, 2.2)


def gingham():
    """Клетчатый плед для пикника: красно-белая «шотландка» — красные полосы по основе и утку, на пересечении
    тёмно-красный, где одна полоса — розово-красный (нити перемешаны), белое — небелёный хлопок.
    Плитка 512 px = 1 м, 8 клеток (12,5 см); видно саржевое переплетение, ворс, пятна от травы"""
    n = 512
    y, x = np.mgrid[0:n, 0:n].astype(F32)
    per = n / 8.0
    rg = R(711)
    jit = ndi.gaussian_filter(rg.standard_normal((n, n)).astype(F32), 2.0, mode="wrap") * 1.2
    sx = ((x + jit) % per) < per * 0.5
    sy = ((y + jit) % per) < per * 0.5
    red = np.array([0.66, 0.08, 0.07], F32)
    white = np.array([0.86, 0.83, 0.76], F32)
    mid = red * 0.62 + white * 0.38
    k = sx.astype(F32) + sy.astype(F32)
    col = np.where((k == 2)[..., None], red * 0.82, np.where((k == 1)[..., None], mid, white))
    # мягкая граница полос (нити переплетаются)
    col = np.dstack([ndi.gaussian_filter(col[..., c], 0.9, mode="wrap") for c in range(3)])
    # саржа: диагональные рубчики
    tw = 0.5 + 0.5 * np.sin((x + y) * 2.0 * np.pi / 4.0)
    hgt, _ = _weave(n, 2.5, 712)
    stain = np.clip(fbm_wrap((n, n), 713, (70, 30, 10), (1.0, 0.5, 0.3)) - 1.1, 0, 1)
    shade = 0.9 + 0.06 * tw + 0.08 * (hgt - 0.5) + 0.03 * fbm_wrap((n, n), 714, (20, 6), (1.0, 0.5))
    col = col * shade[..., None]
    col = col * (1.0 - 0.18 * stain[..., None]) + np.array([0.06, 0.08, 0.0], F32) * stain[..., None] * 0.5
    save_rgb("prop_gingham", np.clip(col, 0, 1) * 255.0)


def sleepbag():
    """Спальный мешок: синтетика тёмно-синего цвета, стёжка поперёк — валики по 12 см (тени швов запечены),
    мятые блики нейлона, пыль. 512 px = 0,5 м (по v — поперёк валиков). prop_sleepbag_n — валики и складки"""
    n = 512
    y, x = np.mgrid[0:n, 0:n].astype(F32)
    per = n / 4.0
    t = (y % per) / per
    puff = np.sin(np.pi * t) ** 0.6
    wr = fbm_wrap((n, n), 721, (40, 14, 5), (1.0, 0.5, 0.25))
    hgt = puff + 0.1 * wr
    seam = np.exp(-((t - 0.0) / 0.03) ** 2) + np.exp(-((t - 1.0) / 0.03) ** 2)
    base = np.array([0.16, 0.2, 0.36], F32)
    lum = 0.75 + 0.3 * puff + 0.08 * wr - 0.45 * seam
    dust = np.clip(fbm_wrap((n, n), 722, (60, 20), (1.0, 0.5)) - 0.9, 0, 1)
    col = base[None, None, :] * lum[..., None]
    col = col * (1.0 - 0.3 * dust[..., None]) + np.array([0.35, 0.32, 0.27], F32) * dust[..., None] * 0.3
    # строчка по шву
    st = ((x % 9.0) < 5.0).astype(F32) * np.exp(-((t - 0.0) / 0.012) ** 2 + 0.0)
    col = col * (1.0 - 0.25 * st[..., None])
    save_rgb("prop_sleepbag", np.clip(col, 0, 1) * 255.0)
    save_normal("prop_sleepbag_n", hgt, 18.0)


def cart_side():
    """Наклейка борта тележки мороженщика: «ICE CREAM» крупно, мороженое на палочке и рожок, тонкая рамка;
    краска выцвела и облупилась по краям (альфа рваная). RGBA 1024×320, борт 1,4 × 0,44 м"""
    w, h = 1024, 320
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    red = (178, 34, 30, 255)
    blue = (38, 74, 140, 255)
    txt = "ICE CREAM"
    # буквы — между картинками (поля по 150 px)
    sz = 132
    f = _font(["ariblk.ttf", "impact.ttf", "arialbd.ttf"], sz)
    while sz > 60 and d.textbbox((0, 0), txt, font=f)[2] > w - 330:
        sz -= 4
        f = _font(["ariblk.ttf", "impact.ttf", "arialbd.ttf"], sz)
    bb = d.textbbox((0, 0), txt, font=f)
    tw = bb[2] - bb[0]
    tx = (w - tw) // 2 - bb[0]
    ty = 150 - (bb[3] + bb[1]) // 2 - 20
    # тень-обводка синим, буквы красные
    for ox, oy in [(-5, 0), (5, 0), (0, -5), (0, 5), (4, 4), (-4, 4), (4, -4), (-4, -4), (7, 7)]:
        d.text((tx + ox, ty + oy), txt, font=f, fill=blue)
    d.text((tx, ty), txt, font=f, fill=red)
    f2 = _font(["arialbd.ttf", "arial.ttf"], 40)
    sub = "COLD  TREATS  -  BARS  -  CONES"
    bb2 = d.textbbox((0, 0), sub, font=f2)
    d.text(((w - (bb2[2] - bb2[0])) // 2 - bb2[0], 226), sub, font=f2, fill=blue)
    # эскимо слева и рожок справа
    def bar(cx):
        d.rounded_rectangle([cx - 34, 70, cx + 34, 190], 26, fill=(92, 52, 30, 255))
        d.rounded_rectangle([cx - 34, 70, cx + 34, 120], 26, fill=(240, 232, 214, 255))
        d.rectangle([cx - 8, 186, cx + 8, 236], fill=(214, 186, 132, 255))
    def cone(cx):
        # вафля: сетка линий только внутри треугольника (маска)
        lay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        dl = ImageDraw.Draw(lay)
        dl.rectangle([cx - 44, 116, cx + 44, 244], fill=(206, 156, 84, 255))
        for k in range(-6, 7):
            dl.line([(cx + k * 16 - 60, 116), (cx + k * 16 + 60, 244)], fill=(160, 112, 52, 255), width=3)
            dl.line([(cx + k * 16 + 60, 116), (cx + k * 16 - 60, 244)], fill=(160, 112, 52, 255), width=3)
        mk = Image.new("L", (w, h), 0)
        ImageDraw.Draw(mk).polygon([(cx - 40, 120), (cx + 40, 120), (cx, 240)], fill=255)
        img.paste(lay, (0, 0), mk)
        d.ellipse([cx - 46, 64, cx + 46, 140], fill=(238, 184, 196, 255))
        d.ellipse([cx - 30, 40, cx + 30, 96], fill=(246, 236, 220, 255))
    bar(78)
    cone(w - 78)
    d.rounded_rectangle([6, 6, w - 7, h - 7], 22, outline=blue, width=6)
    a = np.asarray(img).astype(F32) / 255.0
    rgb = a[..., :3]
    al = a[..., 3]
    # выцветание (солнце) и облупленная краска: дыры в альфе по шуму, гуще к краям и низу
    fade = np.clip(fbm((h, w), 731, (30, 10, 3), (1.0, 0.5, 0.3)), -2, 2)
    rgb = rgb * (0.86 + 0.05 * fade[..., None]) + 0.06
    yy, xx = np.mgrid[0:h, 0:w].astype(F32)
    edge = np.minimum(np.minimum(xx, w - 1 - xx) / w, np.minimum(yy, h - 1 - yy) / h * 3.2)
    chip = fbm((h, w), 732, (6, 2, 1), (1.0, 0.6, 0.4)) + smooth(0.08, 0.0, edge) * 1.4 + smooth(0.6, 1.0, yy / h) * 0.5
    al = al * (chip < 2.1).astype(F32)
    save_rgba("prop_cart_side", rgb * 255.0, al)


JOBS = {
    "mold": lambda: [mold(v) for v in range(4)],
    "tide": lambda: [tide(v) for v in range(3)],
    "paper": lambda: [paper(v) for v in range(4)],
    "hazmat": hazmat,
    "cubicle": cubicle,
    "gingham": gingham,
    "sleepbag": sleepbag,
    "cart_side": cart_side,
}

if __name__ == "__main__":
    names = sys.argv[1:] or list(JOBS.keys())
    for nm in names:
        JOBS[nm]()
