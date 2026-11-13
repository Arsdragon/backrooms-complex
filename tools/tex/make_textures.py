"""Процедурные бесшовные текстуры Комплекса (уровень 0 и его зоны) и предметов.

    python tools/tex/make_textures.py [имя ...]   → tex/<имя>.png (+ карты нормалей tex/<имя>_n.png)
    python tools/tex/make_textures.py --legacy    → ещё и старые текстуры парка/концовок/лиц (их ведут другие задачи)

Правила (проверка швов — tools/tex/check_seams.py, листы и калибровка — tools/tex/preview.py):
- всё периодично: шумы строятся в частотной области, узоры укладываются целым числом периодов,
  размытие — scipy.ndimage с mode="wrap" (PIL GaussianBlur ломает швы);
- узоры рисуются с суперсэмплингом (ss×ss точек на тексель) и мягкими краями, шумы ограничены по полосе:
  крупная деталь 1–20 см (видна в 480 строках), мелочь — малой амплитуды, без белого шума на тексель;
- координаты в метрах: x = u вправо, y = v вниз по строкам картинки. Стены: верх картинки = верх стены
  (шейдер берёт v = −Y мира); пол и потолок — мировые (x, z);
- карты нормалей: высота h в мм, n = normalize(−dh/du·s, −dh/dv·s, 1); касательная x = +u (вправо),
  y = +v (вниз, рост номера строки); rgb = n·0.5 + 0.5;
- альбедо откалиброваны под тёплый люминесцентный свет и Filmic: обои — сливочно-жёлтые, ковёр —
  средний коричневато-бежевый, потолок — почти белый (preview.py swatch).
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage as ndi

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "tex")
rng = np.random.default_rng(1990)   # только для старых генераторов (legacy): их порядок вызовов не менять
F32 = np.float32

# ----------------------------------------------------------------- цвета (sRGB 0..255)
C_WALL = (222, 194, 118)        # обои: сливочно-жёлтые
C_CARPET = (134, 108, 76)       # ковролин: коричневато-бежевый
C_CEIL = (232, 228, 214)        # плита потолка (с трещинками в среднем темнее)
C_TBAR = (238, 236, 228)        # профиль подвесной решётки: белая эмаль
C_BASE = (228, 216, 188)        # плинтус: крашеное дерево цвета слоновой кости


# ----------------------------------------------------------------- инструменты

def R(seed):
    return np.random.default_rng(seed)


def c3(c):
    return np.array(c, F32) / 255.0


def coords(w, h, size, ss=1):
    """Сетка центров пикселей в метрах: X вправо (u), Y вниз (v); ss — во сколько раз гуще"""
    x = (np.arange(w * ss, dtype=F32) + 0.5) * F32(size[0] / (w * ss))
    y = (np.arange(h * ss, dtype=F32) + 0.5) * F32(size[1] / (h * ss))
    return np.meshgrid(x, y)


def down(a, f):
    """Усреднение блоками f×f (сохраняет периодичность, даёт сглаживание суперсэмплинга)"""
    if f == 1:
        return a
    h, w = a.shape[0] // f, a.shape[1] // f
    return a.reshape(h, f, w, f, *a.shape[2:]).mean(axis=(1, 3))


def blur(a, s):
    sig = (s, s) + (0,) * (a.ndim - 2)
    return ndi.gaussian_filter(a, sig, mode="wrap")


def sstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def noise(w, h, size, seed, lam=(0.002, 1.0), beta=2.0, stretch=(1.0, 1.0)):
    """Периодический гауссов шум (среднее 0, σ 1). lam — диапазон длин волн в метрах (мягкие края полосы),
    beta — наклон спектра 1/f^beta, stretch — во сколько раз пятна вытянуты вдоль x и y."""
    f = np.fft.fft2(R(seed).standard_normal((h, w)))
    kx = np.fft.fftfreq(w, d=size[0] / w)[None, :] * stretch[0]
    ky = np.fft.fftfreq(h, d=size[1] / h)[:, None] * stretch[1]
    k = np.sqrt(kx * kx + ky * ky)
    k[0, 0] = 1e-9
    k1, k2 = 1.0 / lam[1], 1.0 / lam[0]
    amp = k ** (-beta / 2.0) * (1.0 - np.exp(-(k / k1) ** 2)) * np.exp(-(k / k2) ** 2)
    amp[0, 0] = 0.0
    o = np.real(np.fft.ifft2(f * amp))
    o = (o - o.mean()) / (o.std() + 1e-12)
    return o.astype(F32)


def noise1(n, length, seed, lam, beta=2.0):
    """Периодический одномерный шум (σ 1)"""
    f = np.fft.fft(R(seed).standard_normal(n))
    k = np.abs(np.fft.fftfreq(n, d=length / n))
    k[0] = 1e-9
    amp = k ** (-beta / 2.0) * (1.0 - np.exp(-(k * lam[1]) ** 2)) * np.exp(-(k * lam[0]) ** 2)
    amp[0] = 0.0
    o = np.real(np.fft.ifft(f * amp))
    return ((o - o.mean()) / (o.std() + 1e-12)).astype(F32)


def zero_lines(n, half_px, aa=0.8):
    """Линии вдоль нулей поля n почти постоянной ширины (полуширина в пикселях массива): 1 на линии"""
    gx = (np.roll(n, -1, 1) - np.roll(n, 1, 1)) * 0.5
    gy = (np.roll(n, -1, 0) - np.roll(n, 1, 0)) * 0.5
    d = np.abs(n) / (np.sqrt(gx * gx + gy * gy) + 1e-6)
    return sstep(half_px + aa, half_px - aa, d)


def sdist(n, px_size):
    """Приближённое знаковое расстояние (м) до нулевой линии поля n"""
    gx = (np.roll(n, -1, 1) - np.roll(n, 1, 1)) * 0.5
    gy = (np.roll(n, -1, 0) - np.roll(n, 1, 0)) * 0.5
    return n / (np.sqrt(gx * gx + gy * gy) + 1e-6) * px_size


def wrapd(a, period):
    """Знаковое расстояние до ближайшего кратного period (−period/2 .. period/2)"""
    return (a + period * 0.5) % period - period * 0.5


def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = np.clip(((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy), 0.0, 1.0)
    return np.hypot(px - ax - t * dx, py - ay - t * dy)


def cells(idx_x, idx_y, table):
    """Значение случайной таблицы по номеру ячейки (с переносом)"""
    return table[idx_y % table.shape[0], idx_x % table.shape[1]]


def strokes(w, h, items, ss=2, wrap=True):
    """Штрихи (царапины, следы, трещины) с переносом через края. items: (точки в пикселях итоговой
    текстуры, толщина в пикселях, яркость 0..1). Возвращает маску 0..1 размера h×w."""
    W, H = w * ss, h * ss
    im = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(im)
    for pts, width, val in items:
        p = [(x * ss, y * ss) for x, y in pts]
        xs = [q[0] for q in p]
        ys = [q[1] for q in p]
        pad = width * ss + 2
        offs = [(ox, oy) for ox in ((-W, 0, W) if wrap else (0,)) for oy in ((-H, 0, H) if wrap else (0,))]
        for ox, oy in offs:
            if max(xs) + ox < -pad or min(xs) + ox > W + pad or max(ys) + oy < -pad or min(ys) + oy > H + pad:
                continue
            d.line([(x + ox, y + oy) for x, y in p], fill=int(val * 255), width=max(1, int(round(width * ss))), joint="curve")
    a = np.asarray(im).astype(F32) / 255.0
    return down(a, ss)


def walk(r, x, y, n, step, ang, curl):
    pts = [(x, y)]
    for _ in range(n):
        ang += r.normal(0.0, curl)
        x += np.cos(ang) * step
        y += np.sin(ang) * step
        pts.append((x, y))
    return pts


def paint(c, lum):
    """Цвет c (sRGB 0..255 или массив 0..1) × яркость lum"""
    c = c3(c) if isinstance(c, tuple) else c
    return c[None, None, :] * lum[..., None] if c.ndim == 1 else c * lum[..., None]


def mixc(a, b, t):
    t = t[..., None]
    return a * (1.0 - t) + b * t


def save(name, arr):
    a = np.clip(np.asarray(arr, np.float64), 0.0, 1.0)
    img = Image.fromarray(np.round(a * 255.0).astype(np.uint8))
    img.save(os.path.join(OUT, name + ".png"))
    print("   %-22s %dx%d" % (name, img.width, img.height))


def save_normal(name, h, size, gain=1.0, wrap_v=True):
    """Карта нормалей из высоты h (мм) для текстуры размером size (м). Касательная x = +u, y = +v (вниз)."""
    hh, ww = h.shape
    du = size[0] * 1000.0 / ww
    dv = size[1] * 1000.0 / hh
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) / (2.0 * du)
    if wrap_v:
        gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) / (2.0 * dv)
    else:
        gy = np.gradient(h, dv, axis=0)
    n = np.dstack([-gx * gain, -gy * gain, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    save(name + "_n", n * 0.5 + 0.5)


def weathered(col, size, seed, amount=0.14, grime=(122, 108, 84), mott=1.0, fox=1.0):
    """Равномерное старение для «грязных» вариантов. Их подмешивает мировая маска, поэтому никаких
    крупных отдельных пятен (они повторялись бы с периодом текстуры): цвет уходит к серо-бурой грязи
    (темнее и тусклее, а не «желтее»), мягкая пятнистость 1.5–40 см (±25 % от доли), редкие мелкие
    крапинки (бумага «ржавеет»), гуще местами."""
    H, W = col.shape[:2]
    m = noise(W, H, size, seed, lam=(0.06, 0.4), beta=2.0)
    m2 = noise(W, H, size, seed + 1, lam=(0.015, 0.08), beta=1.5)
    a = np.clip(amount * (1.0 + mott * (0.18 * m + 0.08 * m2)), 0.0, 1.0)
    d = mixc(col, paint(grime, np.ones((H, W), F32)), a)
    clus = sstep(0.3, 1.5, noise(W, H, size, seed + 2, lam=(0.08, 0.4), beta=2.0))
    spots = sstep(2.5, 3.3, noise(W, H, size, seed + 3, lam=(0.0026, 0.007), beta=0.0)) * clus
    return age(d, spots * 0.5 * fox, (0.86, 0.78, 0.64))


def age(col, k, warm=(1.0, 0.96, 0.86)):
    """Старение: темнее и желтее/коричневее на долю k (массив или число)"""
    w = np.array(warm, F32)
    k = np.asarray(k, F32)
    kk = k[..., None] if k.ndim else k
    return col * (1.0 - kk * (1.0 - w[None, None, :]))


# ----------------------------------------------------------------- Комплекс: обои

def wallpaper_yellow():
    """Однотонно-жёлтые обои Комплекса. Повтор 1.2 × 1.2 м (две полосы рулона по 0.6 м, стыки x = 0 и 0.6).
    Рисунок: колонки через 10 см — полоса тона, тонкие линии по краям и цепочка шевронов «^» с ромбиками
    (шаг 6 см). Стыки полос — в чистом поле между колонками; у второй полосы чуть другой тон и рисунок
    сдвинут на 1.5 мм (так бывает на настоящей стене). Грязный вариант — старение и следы влаги без крупных
    пятен (крупное даёт мировая карта wall_grime)."""
    N, S, SS = 1024, 1.2, 3
    X, Y = coords(N, N, (S, S), SS)
    roll = (X >= 0.6).astype(F32)
    yy = Y + roll * 0.0015
    acx = np.abs((X % 0.1) - 0.05)                      # от оси колонки, м
    cy = (yy % 0.06) - 0.03
    ink = sstep(0.00215, 0.00165, seg_dist(acx, cy, 0.0, -0.0055, 0.0115, 0.0045))   # шеврон, штрих ~3.8 мм
    cy2 = ((yy + 0.03) % 0.06) - 0.03
    ink = np.maximum(ink, sstep(0.0047, 0.0039, acx + np.abs(cy2) * 0.75))           # ромбик
    ink = np.maximum(ink, 0.7 * sstep(0.00105, 0.0006, np.abs(acx - 0.0235)))        # линии по краям полосы
    band = sstep(0.0245, 0.0225, acx)
    del acx, cy, cy2, yy, X, Y, roll
    ink = down(ink, SS)
    band = down(band, SS)

    x, y = coords(N, N, (S, S))
    roll = (x >= 0.6).astype(F32)
    fib = noise(N, N, (S, S), 11, lam=(0.0022, 0.008), beta=1.0, stretch=(1.0, 2.5))
    mot = noise(N, N, (S, S), 12, lam=(0.02, 0.3), beta=2.0)
    dens = noise(N, N, (S, S), 13, lam=(0.04, 0.4), beta=2.0)
    sd = np.minimum(x % 0.6, 0.6 - x % 0.6)            # до стыка полос, м
    seam = np.exp(-(sd / 0.0007) ** 2)
    lip = np.exp(-((sd - 0.0022) / 0.0014) ** 2)
    ink = ink * (1.0 + 0.1 * dens)
    lum = 1.0 - band * 0.035 - ink * 0.11 + fib * 0.011 + mot * 0.013 + roll * 0.012 - seam * 0.09 + lip * 0.022
    col = paint(C_WALL, lum)
    col = col * (1.0 - ink[..., None] * np.array([0.0, 0.012, 0.06], F32)[None, None, :])  # краска чуть насыщеннее
    col = col * (1.0 + roll[..., None] * np.array([0.0, -0.004, -0.012], F32)[None, None, :])
    save("wall_yellow", col)

    # рельеф: тиснение «лён», выпуклая краска рисунка, коробление бумаги от клея, приподнятые кромки стыка
    linen = noise(N, N, (S, S), 14, lam=(0.0025, 0.006), beta=0.5)
    cockle = noise(N, N, (S, S), 15, lam=(0.03, 0.2), beta=2.0)
    h = linen * 0.022 + ink * 0.025 + cockle * 0.12 + lip * 0.06 - seam * 0.05
    save_normal("wall_yellow", h, (S, S), gain=3.0)

    # грязный вариант: равномерное старение (крупные пятна и потёки — мировая карта wall_grime)
    glue = np.exp(-(sd / 0.006) ** 2) * (0.6 + 0.4 * sstep(-1.0, 1.0, noise(N, N, (S, S), 19, lam=(0.01, 0.1), beta=2.0)))
    fade = sstep(-0.5, 1.5, noise(N, N, (S, S), 20, lam=(0.05, 0.4), beta=2.0))
    lum2 = lum + ink * 0.11 * 0.3 * fade                   # рисунок местами выцвел
    d = paint(C_WALL, lum2)
    d = d * (1.0 - ink[..., None] * np.array([0.0, 0.012, 0.06], F32)[None, None, :])
    d = weathered(d, (S, S), 16, amount=0.13, grime=(128, 110, 76), mott=1.0, fox=1.0)
    d = age(d, glue * 0.6, (0.9, 0.84, 0.7))
    save("wall_yellow_dirty", d)


def _paper(N, S, seed):
    fib = noise(N, N, (S, S), seed, lam=(0.0022, 0.008), beta=1.0, stretch=(1.0, 2.5))
    mot = noise(N, N, (S, S), seed + 1, lam=(0.02, 0.3), beta=2.0)
    return fib, mot


def wallpaper_old():
    """«Старое крыло»: выцветшие полосатые обои 60-х (повтор 1.2 м, полосы 10 см, рулоны по 0.6 м)"""
    N, S, SS = 1024, 1.2, 3
    X, Y = coords(N, N, (S, S), SS)
    px = X % 0.1
    wide = sstep(0.0005, 0.0, np.abs(wrapd(px - 0.05, 0.1)) - 0.031)            # широкая светлая полоса 6.2 см
    pin = sstep(0.0011, 0.0005, np.abs(np.abs(wrapd(px - 0.05, 0.1)) - 0.034))   # тонкие линии рядом
    pin2 = sstep(0.0009, 0.0004, np.abs(wrapd(px, 0.1)))                          # линия посередине тёмной
    dots = sstep(0.0016, 0.0011, np.hypot(wrapd(px, 0.1), wrapd(Y, 0.02)))       # горошек по тёмной полосе
    del X, Y, px
    wide, pin, pin2, dots = (down(a, SS) for a in (wide, pin, pin2, dots))
    x, y = coords(N, N, (S, S))
    fib, mot = _paper(N, S, 21)
    sd = np.minimum(x % 0.6, 0.6 - x % 0.6)
    seam = np.exp(-(sd / 0.0008) ** 2)
    lip = np.exp(-((sd - 0.0025) / 0.0016) ** 2)
    base = mixc(paint((150, 126, 92), np.ones_like(x)), paint((176, 154, 112), np.ones_like(x)), wide)
    ink = np.maximum(pin * 0.8, np.maximum(pin2 * 0.6, dots * 0.5))
    lum = 1.0 - ink * 0.13 + fib * 0.016 + mot * 0.02 - seam * 0.12 + lip * 0.03
    col = base * lum[..., None]
    fade = sstep(-1.5, 1.5, noise(N, N, (S, S), 23, lam=(0.05, 0.4), beta=2.0))
    col = col * (1.0 + 0.03 * fade[..., None])
    save("wall_old", col)
    h = noise(N, N, (S, S), 24, lam=(0.001, 0.004), beta=0.6) * 0.03 + noise(N, N, (S, S), 25, lam=(0.03, 0.2)) * 0.18 \
        + lip * 0.09 - seam * 0.06 + ink * 0.01
    save_normal("wall_old", h, (S, S), gain=3.0)
    glue = np.exp(-(sd / 0.008) ** 2)
    d = weathered(col, (S, S), 26, amount=0.17, grime=(110, 92, 66), mott=1.3, fox=1.4)
    d = age(d, glue * 0.8, (0.82, 0.75, 0.62))
    save("wall_old_dirty", d)


def wallpaper_house():
    """Жилые комнаты: обои с мелкими цветочками (полураппорт 10 × 10 см, повтор 1.2 м, рулоны по 0.6 м)"""
    N, S, SS = 1024, 1.2, 3
    X, Y = coords(N, N, (S, S), SS)
    P = 0.1
    col_i = np.floor(X / P)
    yy = Y + (col_i % 2) * (P * 0.5)                     # полураппорт по столбцам
    lx = (X % P) - P * 0.5
    ly = (yy % P) - P * 0.5
    del X, Y, yy, col_i
    # цветок: 5 лепестков вокруг центра (точки в локальной системе)
    r = np.hypot(lx, ly)
    a = np.arctan2(ly, lx) + 0.3
    petal_r = 0.0122 * (0.55 + 0.45 * np.abs(np.cos(a * 2.5)))
    flower = sstep(0.0006, -0.0004, r - petal_r)
    centre = sstep(0.003, 0.0021, r)
    # листики: два эллипса под углом
    def leaf(cx, cy, ang, L, W):
        ca, sa = np.cos(ang), np.sin(ang)
        u = (lx - cx) * ca + (ly - cy) * sa
        v = -(lx - cx) * sa + (ly - cy) * ca
        return sstep(1.05, 0.95, (u / L) ** 2 + (v / W) ** 2)
    leaves = np.maximum(leaf(0.016, 0.012, 0.7, 0.0085, 0.0034), leaf(-0.015, 0.014, 2.5, 0.0075, 0.003))
    stem = sstep(0.0008, 0.0004, seg_dist(lx, ly, 0.0, 0.006, 0.004, 0.028))
    # россыпь точек между цветами (сдвинуто на пол-ячейки)
    lx2 = wrapd(lx + P * 0.5, P)
    ly2 = wrapd(ly + P * 0.5, P)
    dots = sstep(0.0019, 0.0013, np.minimum(np.hypot(lx2 - 0.012, ly2), np.hypot(lx2 + 0.01, ly2 - 0.01)))
    del lx, ly, lx2, ly2, r, a, petal_r
    flower, centre, leaves, stem, dots = (down(q, SS) for q in (flower, centre, leaves, stem, dots))
    x, y = coords(N, N, (S, S))
    fib, mot = _paper(N, S, 31)
    sd = np.minimum(x % 0.6, 0.6 - x % 0.6)
    seam = np.exp(-(sd / 0.0007) ** 2)
    lip = np.exp(-((sd - 0.0022) / 0.0014) ** 2)
    bg = paint((204, 192, 160), 1.0 + fib * 0.012 + mot * 0.015 - seam * 0.1 + lip * 0.02)
    col = mixc(bg, paint((172, 122, 116), np.ones_like(x)), flower * 0.85)
    col = mixc(col, paint((190, 158, 86), np.ones_like(x)), centre * 0.9)
    col = mixc(col, paint((128, 138, 100), np.ones_like(x)), np.maximum(leaves, stem) * 0.85)
    col = mixc(col, paint((176, 150, 130), np.ones_like(x)), dots * 0.6)
    save("wall_house", col)
    ink = np.maximum(np.maximum(flower, leaves), np.maximum(centre, dots))
    h = noise(N, N, (S, S), 33, lam=(0.0009, 0.0035), beta=0.5) * 0.02 + ink * 0.03 \
        + noise(N, N, (S, S), 34, lam=(0.03, 0.2)) * 0.12 + lip * 0.06 - seam * 0.05
    save_normal("wall_house", h, (S, S), gain=3.0)
    d = weathered(col, (S, S), 35, amount=0.16, grime=(150, 126, 82), mott=1.0, fox=1.0)   # табачная желтизна
    d = age(d, np.exp(-(sd / 0.006) ** 2) * 0.7, (0.86, 0.8, 0.66))
    save("wall_house_dirty", d)


def wall_paint():
    """Крашеный гипсокартон (магазин): «апельсиновая корка» от валика, полосы валика 23 см, шов листов
    на x = 0 (листы 1.2 м) и шляпки саморезов по стойкам. Повтор 1.2 м."""
    N, S = 1024, 1.2
    x, y = coords(N, N, (S, S))
    peel = noise(N, N, (S, S), 401, lam=(0.0018, 0.007), beta=1.0)
    roller = noise(N, N, (S, S), 402, lam=(0.05, 0.3), beta=1.5, stretch=(1.0, 6.0))
    mot = noise(N, N, (S, S), 403, lam=(0.03, 0.3), beta=2.0)
    jd = np.abs(wrapd(x, 1.2))
    joint = sstep(0.14, 0.06, jd)                          # шпаклёванная лента шириной ~25 см
    screws = np.zeros_like(x)
    r = R(404)
    for sx in (0.2, 0.6, 1.0):
        for sy in (0.15, 0.45, 0.75, 1.05):
            if r.random() < 0.65:
                dx = wrapd(x - sx - r.normal(0, 0.003), S)
                dy = wrapd(y - sy - r.normal(0, 0.01), S)
                screws = np.maximum(screws, sstep(0.0065, 0.004, np.hypot(dx, dy)))
    lum = 1.0 + peel * 0.008 + roller * 0.012 + mot * 0.012 + joint * 0.008 - screws * 0.03
    col = paint((216, 210, 192), lum)
    save("wall_paint", col)
    h = peel * 0.07 * (1.0 - joint * 0.6) + roller * 0.05 + noise(N, N, (S, S), 405, lam=(0.05, 0.4)) * 0.2 - screws * 0.25
    save_normal("wall_paint", h, (S, S), gain=3.0)
    # грязный: руки, потёртости, серость
    sm = sstep(0.5, 2.2, noise(N, N, (S, S), 406, lam=(0.02, 0.15), beta=2.0)) * sstep(-0.2, 1.0, noise(N, N, (S, S), 407, lam=(0.1, 0.5)))
    items = []
    rr = R(408)
    for _ in range(26):
        x0, y0 = rr.uniform(0, N), rr.uniform(0, N)
        items.append((walk(rr, x0, y0, 6, rr.uniform(3, 9), rr.normal(0, 0.4), 0.15), rr.uniform(1.0, 2.5), rr.uniform(0.3, 0.8)))
    sc = blur(strokes(N, N, items), 0.6)
    d = weathered(col, (S, S), 409, amount=0.12, grime=(140, 132, 116), mott=1.0, fox=0.3)
    d = age(d, sm * 0.5, (0.9, 0.88, 0.84))
    d = d * (1.0 - sc[..., None] * 0.18)
    save("wall_paint_dirty", d)


def wall_school():
    """Класс: крашеные бетонные блоки 40×20 см вперевязку, низ 1.2 м — зелёная масляная краска, полоса,
    верх — беж. Текстура покрывает ВСЮ стену: 1.2 м × 3.2 м (1024×2048), низ картинки = пол."""
    W, H, Sx, Sy = 1024, 2048, 1.2, 3.2
    x, y = coords(W, H, (Sx, Sy))
    hf = Sy - y                                            # высота над полом, м
    course = np.floor(hf / 0.2)
    bx = wrapd(x + (course % 2) * 0.2, 0.4)                # до вертикального шва
    by = wrapd(hf, 0.2)
    jd = np.minimum(np.abs(bx), np.abs(by))                # до ближайшего шва, м
    joint = sstep(0.0062, 0.0035, jd)
    concave = np.clip(1.0 - jd / 0.006, 0.0, 1.0) ** 2
    pore = sstep(2.3, 3.0, noise(W, H, (Sx, Sy), 501, lam=(0.0015, 0.005), beta=0.0))
    tex = noise(W, H, (Sx, Sy), 502, lam=(0.0015, 0.008), beta=0.8)
    mot = noise(W, H, (Sx, Sy), 503, lam=(0.03, 0.3), beta=2.0)
    low = sstep(1.205, 1.195, hf)
    stripe = sstep(0.004, 0.0, np.abs(hf - 1.215) - 0.015) # тёмная полоса 3 см над панелью
    green, beige, dark = c3((92, 124, 100)), c3((216, 206, 174)), c3((54, 74, 60))
    col = mixc(paint(beige, np.ones_like(x)), paint(green, np.ones_like(x)), low)
    col = mixc(col, paint(dark, np.ones_like(x)), stripe)
    lum = 1.0 + tex * 0.012 + mot * 0.015 - pore * 0.12 - concave * 0.16
    col = col * lum[..., None]
    # поцарапанный низ: сколы краски (из-под зелёной — старый беж) и следы обуви
    rr = R(504)
    items = []
    for _ in range(40):
        x0 = rr.uniform(0, W)
        y0 = H - rr.uniform(4, 0.42 * H / Sy * 1.0) / 1.0
        items.append((walk(rr, x0, y0, 5, rr.uniform(2, 7), rr.normal(0, 0.3), 0.2), rr.uniform(1.0, 3.0), rr.uniform(0.3, 0.9)))
    kick = blur(strokes(W, H, items), 0.7) * sstep(0.5, 0.05, hf)
    chips = sstep(2.4, 3.0, noise(W, H, (Sx, Sy), 505, lam=(0.003, 0.012), beta=0.5)) * sstep(1.0, 0.1, hf)
    col = mixc(col, paint((176, 170, 150), np.ones_like(x)), chips * 0.8)
    col = col * (1.0 - kick[..., None] * 0.35)
    save("wall_school", col)
    h = tex * 0.08 - pore * 0.5 - concave * 3.0 - chips * 0.12 + noise(W, H, (Sx, Sy), 506, lam=(0.05, 0.4)) * 0.2
    save_normal("wall_school", h, (Sx, Sy), gain=1.6, wrap_v=False)
    d = weathered(col, (Sx, Sy), 507, amount=0.1, grime=(110, 104, 88), mott=1.0, fox=0.2)
    d = mixc(d, paint((96, 90, 78), np.ones_like(x)), sstep(0.5, 0.0, hf) * 0.12)       # низ грязнее
    d = d * (1.0 - joint[..., None] * 0.08)
    save("wall_school_dirty", d)


def wall_under():
    """Под отклеенными обоями: картон гипсокартона, разводы клея, клочки белой подложки. Повтор 1.2 м."""
    N, S = 1024, 1.2
    x, y = coords(N, N, (S, S))
    mot = noise(N, N, (S, S), 601, lam=(0.02, 0.3), beta=2.0)
    fib = noise(N, N, (S, S), 602, lam=(0.0024, 0.008), beta=1.0, stretch=(1.0, 2.5))
    # мазки клея широкой кистью (диагональные, полупрозрачные)
    r = R(603)
    items = []
    for _ in range(30):
        x0, y0 = r.uniform(0, N), r.uniform(0, N)
        ang = r.normal(-0.9, 0.35) if r.random() < 0.6 else r.normal(0.8, 0.3)
        items.append((walk(r, x0, y0, 4, r.uniform(40, 110), ang, 0.12), r.uniform(40, 90), r.uniform(0.25, 0.7)))
    glue = blur(strokes(N, N, items, ss=1), 6.0)
    streak = noise(N, N, (S, S), 604, lam=(0.003, 0.02), beta=1.0, stretch=(3.0, 1.0))
    glue = glue * (0.75 + 0.25 * sstep(-1.0, 1.0, streak))
    # клочки обоев с рваным краем: часть — белая подложка, часть — жёлтая лицевая сторона
    low = noise(N, N, (S, S), 605, lam=(0.04, 0.35), beta=2.2)
    rag = noise(N, N, (S, S), 606, lam=(0.0025, 0.02), beta=1.0)
    q = low + 0.07 * rag
    rem = sstep(1.66, 1.7, q)                               # белая подложка — рваная кромка клочка
    face = sstep(1.76, 1.8, q)                              # внутри клочка — жёлтая лицевая сторона
    mildew = sstep(2.3, 3.0, noise(N, N, (S, S), 608, lam=(0.0026, 0.008), beta=0.0)) * sstep(0.5, 1.5, noise(N, N, (S, S), 609, lam=(0.06, 0.3)))
    col = paint((146, 134, 108), 1.0 + mot * 0.04 + fib * 0.02)
    col = age(col, glue, (0.86, 0.8, 0.68))
    col = mixc(col, paint((206, 198, 176), 1.0 + fib * 0.02), rem * 0.9)
    col = mixc(col, paint(C_WALL, 0.96 + fib * 0.02), face * 0.9)
    col = col * (1.0 - mildew[..., None] * 0.5)
    save("wall_under", col)
    h = fib * 0.03 + rem * 0.12 + face * 0.04 + glue * 0.05 + mot * 0.1
    save_normal("wall_under", h, (S, S), gain=3.0)


# ----------------------------------------------------------------- Комплекс: ковролин

def _loops(N, S, rows, ss, seed):
    """Петлевой ворс, ряды вдоль v. Высота петель 0..1 (разрешение N·ss), номера ряда и петли."""
    X, Y = coords(N, N, (S, S), ss)
    p = S / rows
    u = X / p
    iu = np.floor(u).astype(np.int32) % rows
    st = R(seed).random(rows).astype(F32)
    vv = Y / p + st[iu]
    iv = np.floor(vv).astype(np.int32) % rows
    fu = u - np.floor(u)
    fv = vv - np.floor(vv)
    h = (np.sin(np.pi * fu) ** 1.1) * (np.sin(np.pi * fv) ** 0.9)
    return h.astype(F32), iu, iv


def _carpet_field(N, S, rows, ss, seed, pal, heather=0.85):
    """Цвет и высота петлевого ковра: цвет пряжи у каждой петли (меланж из трёх оттенков, вдоль ряда
    чуть плавнее), «дорожки» тафтинга — слабая разница яркости рядов, затенение между петлями."""
    h, iu, iv = _loops(N, S, rows, ss, seed)
    r = R(seed + 1)
    yarn = noise(rows, rows, (S, S), seed + 2, lam=(0.01, 0.04), beta=1.2, stretch=(1.0, 1.6))
    t = 0.45 * yarn + heather * r.standard_normal((rows, rows)).astype(F32)
    tl = t[iv, iu]
    rh = (0.8 + 0.4 * r.random((rows, rows)).astype(F32))[iv, iu]
    tr = ndi.gaussian_filter1d(r.standard_normal(rows), 1.5, mode="wrap")
    tr = (tr / tr.std()).astype(F32)[iu]
    main, dark, light = (c3(c) for c in pal)
    col = mixc(paint(main, np.ones_like(h)), paint(dark, np.ones_like(h)), sstep(-0.75, -1.35, tl))
    col = mixc(col, paint(light, np.ones_like(h)), sstep(0.85, 1.45, tl))
    hh = h * rh
    shade = (0.6 + 0.4 * np.clip(hh, 0, 1) ** 0.6) * (1.0 + 0.018 * tr)     # щели между петлями тёмные — цвета соседних петель не стыкуются «квадратами»
    col = col * shade[..., None]
    return down(col, ss), down(hh, ss)


def carpet():
    """Влажный петлевой ковролин Комплекса: повтор 1.2 м (1024), ряды петель 4.7 мм вдоль v, меланж,
    дорожки тафтинга, пятнистость 1–25 см (ничего крупнее трети повтора — нет «сетки пятен»).
    carpet_wet — промокший и примятый, carpet_old — серо-синие ковровые плитки 0.6 м «вразбежку»."""
    N, S, SS, rows = 1024, 1.2, 2, 256
    col, hh = _carpet_field(N, S, rows, SS, 41, (C_CARPET, (104, 83, 60), (158, 131, 96)))
    m1 = noise(N, N, (S, S), 44, lam=(0.03, 0.25), beta=2.0)
    m2 = noise(N, N, (S, S), 45, lam=(0.008, 0.03), beta=1.0)
    crush = noise(N, N, (S, S), 46, lam=(0.02, 0.2), beta=2.0, stretch=(1.4, 1.0))
    lum = 1.0 + m1 * 0.045 + m2 * 0.022 + crush * 0.025
    c = col * lum[..., None]
    save("carpet", c)
    h = hh * 1.6 + crush * 0.25 + m1 * 0.15
    save_normal("carpet", h, (S, S), gain=0.9)
    # мокрый: темнее, насыщеннее, ворс слипся (петли менее различимы), комки
    clump = noise(N, N, (S, S), 47, lam=(0.006, 0.03), beta=1.0)
    w = mixc(c, blur(c, 1.2), np.full(c.shape[:2], 0.55, F32))
    w = w * (1.0 + clump * 0.04)[..., None]
    w = np.clip(w, 0, 1) ** 1.08 * np.array([0.72, 0.69, 0.66], F32)[None, None, :]
    save("carpet_wet", w)

    # старый офисный: ковровые плитки 0.6 м, соседние повёрнуты на 90° (шахматка оттенка), серо-синий твид
    colo, ho = _carpet_field(N, S, rows, SS, 51, ((100, 102, 112), (76, 78, 88), (134, 134, 138)), heather=0.95)
    x, y = coords(N, N, (S, S))
    par = ((np.floor(x / 0.6) + np.floor(y / 0.6)) % 2).astype(bool)
    colo = np.where(par[..., None], np.transpose(colo, (1, 0, 2)), colo)
    ho = np.where(par, ho.T, ho)
    gap = np.exp(-(np.minimum(np.abs(wrapd(x, 0.6)), np.abs(wrapd(y, 0.6))) / 0.0009) ** 2)
    fl = sstep(2.4, 3.0, noise(N, N, (S, S), 52, lam=(0.0026, 0.006), beta=0.0))      # рыжие и бирюзовые крапинки
    fl2 = sstep(2.4, 3.0, noise(N, N, (S, S), 53, lam=(0.0026, 0.006), beta=0.0))
    tone = np.where(par, 1.025, 0.975).astype(F32)
    lum = tone * (1.0 + noise(N, N, (S, S), 54, lam=(0.03, 0.25)) * 0.045) * (1.0 - gap * 0.35)
    co = colo * lum[..., None]
    co = mixc(co, paint((128, 92, 64), np.ones_like(x)), fl * 0.5)
    co = mixc(co, paint((70, 104, 104), np.ones_like(x)), fl2 * 0.5)
    grime = sstep(-0.5, 2.0, noise(N, N, (S, S), 55, lam=(0.04, 0.3)))
    co = age(co, grime * 0.6, (0.9, 0.88, 0.84))
    save("carpet_old", co)
    save_normal("carpet_old", ho * 1.4 - gap * 0.6 + noise(N, N, (S, S), 56, lam=(0.02, 0.2)) * 0.2, (S, S), gain=0.9)


# ----------------------------------------------------------------- Комплекс: потолок и светильник

def ceiling():
    """Подвесной потолок: четыре минераловатные плиты 0.6 × 0.6 м на повтор 1.2 м (линии решётки на
    u, v = 0 и 0.5), профиль T 24 мм белой эмали, с одной стороны профиля — тёмная щель-тень,
    с другой — светлая кромка. Плиты «с трещинками» (fissured), каждая своя: тон, густота трещин, прогиб."""
    N, S, SS = 1024, 1.2, 2
    X, Y = coords(N, N, (S, S), SS)
    px = S / (N * SS)
    sx = wrapd(X, 0.6)
    sy = wrapd(Y, 0.6)
    ti = (np.floor(X / 0.6) % 2).astype(np.int32)
    tj = (np.floor(Y / 0.6) % 2).astype(np.int32)
    r = R(61)
    dens_t = r.uniform(-0.12, 0.12, (2, 2)).astype(F32)
    # трещинки: нули полосового шума, оставлены обрывки (маска), ширина «гуляет»
    n1 = noise(N * SS, N * SS, (S, S), 62, lam=(0.004, 0.022), beta=1.0)
    keep = noise(N * SS, N * SS, (S, S), 63, lam=(0.005, 0.03), beta=1.0) + dens_t[tj, ti] * 2.0
    wid = 1.0 + 0.45 * noise(N * SS, N * SS, (S, S), 64, lam=(0.01, 0.05), beta=1.0)
    fiss = zero_lines(n1, 1.3 * wid, 0.8) * sstep(0.1, 0.7, keep)
    pin = sstep(2.5, 3.1, noise(N * SS, N * SS, (S, S), 65, lam=(0.0012, 0.004), beta=0.0))
    del n1, keep, wid
    # профиль решётки и щели
    ax, ay = np.abs(sx), np.abs(sy)
    bar = np.maximum(sstep(0.0124, 0.0116, ax), sstep(0.0124, 0.0116, ay))
    # тень с одной стороны (+x у вертикальных, +y у горизонтальных), светлая кромка с другой
    shx = sstep(0.0185, 0.0122, sx) * sstep(0.0115, 0.0125, sx)
    shy = sstep(0.0185, 0.0122, sy) * sstep(0.0115, 0.0125, sy)
    hix = sstep(-0.0165, -0.0125, sx) * sstep(-0.0115, -0.0125, sx)
    hiy = sstep(-0.0165, -0.0125, sy) * sstep(-0.0115, -0.0125, sy)
    shadow = np.maximum(shx * (1 - sstep(0.0124, 0.0116, ay)), shy * (1 - sstep(0.0124, 0.0116, ax)))
    hilite = np.maximum(hix * (1 - sstep(0.0124, 0.0116, ay)), hiy * (1 - sstep(0.0124, 0.0116, ax)))
    # стыки: поперечины упираются в главные профили (y = 0) и короткие — в длинные (x = 0, 0.6)
    joint = sstep(0.0005, 0.0002, np.abs(ay - 0.0118)) * sstep(0.0124, 0.0116, ax) * (np.abs(Y - 0.6) > 0.1)
    joint = np.maximum(joint, sstep(0.0005, 0.0002, np.abs(ax - 0.0118)) * sstep(0.0124, 0.0116, ay) * (np.abs(Y - 0.6) < 0.1))
    # плоская грань профиля и закатанные края
    edge = np.minimum(np.where(ax < 0.0125, 0.0125 - ax, 1.0), np.where(ay < 0.0125, 0.0125 - ay, 1.0))
    roll_e = np.clip(1.0 - edge / 0.0016, 0.0, 1.0)
    del X, Y
    fiss, pin, bar, shadow, hilite, joint, roll_e = (down(a, SS) for a in (fiss, pin, bar, shadow, hilite, joint, roll_e))
    sx, sy = down(sx, SS), down(sy, SS)
    ti, tj = ti[::SS, ::SS], tj[::SS, ::SS]

    x, y = coords(N, N, (S, S))
    tone_t = r.uniform(-0.007, 0.007, (2, 2)).astype(F32)
    warm_t = r.uniform(-0.004, 0.004, (2, 2)).astype(F32)
    mot = noise(N, N, (S, S), 66, lam=(0.01, 0.12), beta=1.5)
    mot2 = noise(N, N, (S, S), 67, lam=(0.003, 0.012), beta=0.8)
    cx = 1.0 - np.abs(sx) / 0.3                            # 0 в центре плиты, 1 у профиля
    cy_ = 1.0 - np.abs(sy) / 0.3
    sag = (1.0 - cx ** 2) * (1.0 - cy_ ** 2)                # 1 в центре плиты
    cut = sstep(0.018, 0.0125, np.minimum(np.abs(sx), np.abs(sy))) * (1 - bar)   # срез плиты у профиля
    tile_l = (1.0 + tone_t[tj, ti] + mot * 0.018 + mot2 * 0.012 - fiss * 0.28 - pin * 0.2 - sag * 0.012 - cut * 0.06)
    tile = paint(C_CEIL, tile_l)
    tile = tile * (1.0 + warm_t[tj, ti][..., None] * np.array([0.6, 0.0, -1.0], F32)[None, None, :])
    streak = noise(N, N, (S, S), 68, lam=(0.004, 0.05), beta=1.5, stretch=(1.0, 1.0)) * 0.012
    tb = paint(C_TBAR, 1.0 + streak - roll_e * 0.07 - joint * 0.35)
    col = mixc(tile, tb, bar)
    col = col * (1.0 - shadow * 0.5)[..., None] * (1.0 + hilite * 0.05)[..., None]
    save("ceiling_tile", col)
    h = (-fiss * 1.1 - pin * 0.8 + mot2 * 0.06 + mot * 0.08 - sag * 0.6) * (1 - bar) \
        + bar * (1.2 - roll_e * 0.9) - shadow * 2.0
    save_normal("ceiling_tile", h, (S, S), gain=1.5)

    # грязный: пожелтевшие плиты, пыль в трещинах и у профилей, ржавые точки на профилях
    dust = sstep(0.05, 0.012, np.minimum(np.abs(sx), np.abs(sy))) * (1 - bar)
    rust = sstep(2.2, 2.9, noise(N, N, (S, S), 70, lam=(0.0025, 0.008), beta=0.3)) * bar
    tile_d = paint(C_CEIL, tile_l - fiss * 0.06)
    tile_d = weathered(tile_d, (S, S), 69, amount=0.11, grime=(150, 138, 112), mott=0.8, fox=0.3)
    tile_d = age(tile_d, dust * 0.7, (0.9, 0.88, 0.84))
    tbd = age(tb, 1.0, (0.95, 0.94, 0.9))
    tbd = mixc(tbd, paint((128, 84, 50), np.ones_like(x)), rust * 0.7)
    cd = mixc(tile_d, tbd, bar)
    cd = cd * (1.0 - shadow * 0.55)[..., None] * (1.0 + hilite * 0.04)[..., None]
    save("ceiling_tile_dirty", cd)


def fixture():
    """Растровый светильник 2×4 ft (0.6 × 1.2 м): u поперёк (512 px), v вдоль (1024 px).
    Рамка 25 мм белой эмали (закатанные кромки, швы на углах, прорези защёлок), призматический
    рассеиватель K12 (пирамидки 6.5 мм), за ним три трубки T12 — светлые полосы, тёмные концы у цоколей.
    АЛЬФА = маска свечения: 1 рассеиватель, 0 рамка (импорт с fix_alpha_border=false)."""
    W, H, Sx, Sy, SS = 512, 1024, 0.6, 1.2, 4
    X, Y = coords(W, H, (Sx, Sy), SS)
    dx = np.minimum(X, Sx - X)
    dy = np.minimum(Y, Sy - Y)
    d = np.minimum(dx, dy)
    FR = 0.025
    lens = sstep(FR - 0.0003, FR + 0.0003, d)
    # рамка: закатанный наружный край, плоская полка, скос к рассеивателю, швы на углах
    mitre = sstep(0.0006, 0.0002, np.abs(dx - dy)) * (d < FR)
    latch = ((np.abs(Y - 0.3) < 0.012) | (np.abs(Y - 0.9) < 0.012)) & (np.abs(X - 0.0125) < 0.0032)
    flum = 0.95 - 0.12 * sstep(0.003, 0.0, d) - 0.18 * sstep(FR - 0.005, FR, d) - 0.3 * mitre - 0.45 * latch
    # призмы: 4 грани у каждой пирамидки
    p = 0.0065
    fu = ((X - FR) / p) % 1.0 - 0.5
    fv = ((Y - FR) / p) % 1.0 - 0.5
    au, av = np.abs(fu), np.abs(fv)
    # грань, смотрящая на ближайшую трубку, светлее (преломляет её свет), противоположная — темнее
    tc = 0.15 + 0.15 * np.clip(np.round((X - 0.15) / 0.15), 0, 2)
    side = -np.sign(X - tc)
    facet = np.where(au > av, np.where(fu * side > 0, 1.0, 0.7), np.where(fv > 0, 0.86, 0.8))
    ridge = sstep(0.06, 0.0, np.abs(au - av)) * 0.12 + sstep(0.08, 0.0, 0.5 - np.maximum(au, av)) * 0.1
    prism = down((facet + ridge).astype(F32), SS)
    del tc, side
    lens, flum = down(lens, SS), down(flum.astype(F32), SS)
    del X, Y, dx, dy, d, fu, fv, au, av, facet, ridge, mitre, latch
    x, y = coords(W, H, (Sx, Sy))
    dd = np.minimum(np.minimum(x, Sx - x), np.minimum(y, Sy - y))
    tubes = np.zeros_like(x)
    glow = np.zeros_like(x)
    for k, tu in enumerate((0.15, 0.3, 0.45)):
        tubes += np.exp(-((x - tu) / 0.024) ** 2)
        glow += np.exp(-((x - tu) / 0.085) ** 2)
    ends = sstep(0.035, 0.1, y) * sstep(Sy - 0.035, Sy - 0.1, y)
    blacken = 1.0 - 0.35 * np.exp(-((x - 0.3) / 0.03) ** 2) * np.exp(-((y - 0.11) / 0.03) ** 2)
    light = (0.55 + 0.23 * glow / glow.max() + 0.22 * tubes) * (0.82 + 0.18 * ends) * blacken
    lip = np.exp(-np.maximum(dd - FR, 0.0) / 0.005)       # тень под кромкой рамки
    dust = noise(W, H, (Sx, Sy), 71, lam=(0.01, 0.1), beta=1.5)
    llum = light * (0.5 + 0.5 * prism) * (1.0 - 0.3 * lip) * (1.0 + dust * 0.02)
    # мёртвые мошки
    r = R(72)
    bugs = np.zeros_like(x)
    for _ in range(9):
        bx, by = r.uniform(0.06, 0.54), r.uniform(0.08, 1.12)
        ang = r.uniform(0, np.pi)
        u = (x - bx) * np.cos(ang) + (y - by) * np.sin(ang)
        v = -(x - bx) * np.sin(ang) + (y - by) * np.cos(ang)
        sz = r.uniform(0.7, 1.4)
        bugs = np.maximum(bugs, sstep(1.2, 0.8, (u / (0.0028 * sz)) ** 2 + (v / (0.0012 * sz)) ** 2))
        bugs = np.maximum(bugs, 0.45 * sstep(1.2, 0.8, ((u + 0.0005) / (0.0022 * sz)) ** 2 + ((np.abs(v) - 0.0016 * sz) / (0.0012 * sz)) ** 2))
    llum = llum * (1.0 - bugs * 0.7)
    lcol = paint((255, 251, 242), llum)
    yel = np.exp(-np.maximum(dd - FR, 0.0) / 0.06)          # пожелтевший у краёв акрил
    lcol = lcol * (1.0 - yel[..., None] * np.array([0.0, 0.02, 0.07], F32)[None, None, :])
    fcol = paint((236, 234, 228), flum)
    col = mixc(fcol, lcol, lens)
    save("fixture", np.dstack([col, lens]))


def baseboard():
    """Плинтус: полоса 1.2 × 0.1 м (1024×128), верх картинки = верх доски. Крашеное дерево цвета слоновой
    кости: скруглённый верх (блик), канавка-валик, плоская доска; к полу — пыль и грязь, следы обуви
    и пылесоса, сколы краски. Верхняя строка — цвет верхней грани (шейдер кладёт её на «крышку»)."""
    W, H, Sx, Sy, SS = 1024, 128, 1.2, 0.1, 2
    x, y = coords(W, H, (Sx, Sy))
    ym = y * 1000.0                                        # мм от верха
    # профиль толщины, мм: скругление R5 сверху, канавка на 9 мм, плоская доска 12 мм
    th = np.where(ym < 5.0, 7.0 + np.sqrt(np.clip(25.0 - (5.0 - ym) ** 2, 0, None)), 12.0)
    th = th - 0.9 * np.exp(-((ym - 9.0) / 1.0) ** 2)
    grain = noise(W, H, (Sx, Sy), 81, lam=(0.002, 0.03), beta=1.5, stretch=(10.0, 1.0))
    brush = noise(W, H, (Sx, Sy), 82, lam=(0.0008, 0.004), beta=0.5, stretch=(8.0, 1.0))
    mot = noise(W, H, (Sx, Sy), 83, lam=(0.02, 0.3), beta=2.0)
    lipl = np.exp(-((ym - 2.2) / 1.6) ** 2) * 0.07                      # блик на скруглении
    groove = np.exp(-((ym - 9.4) / 0.9) ** 2) * 0.22                     # тень в канавке
    dirt = sstep(70.0, 100.0, ym) * (0.6 + 0.4 * sstep(-1.0, 1.0, noise(W, H, (Sx, Sy), 84, lam=(0.02, 0.2))))
    topd = np.exp(-(ym / 1.2) ** 2) * 0.06                               # пыль на верхней грани
    lum = 1.0 + lipl - groove + grain * 0.012 + brush * 0.008 + mot * 0.015 - topd
    col = paint(C_BASE, lum)
    col = age(col, dirt * 0.55, (0.86, 0.82, 0.74))
    # следы обуви и пылесоса: тёмные горизонтальные мазки
    r = R(85)
    items = []
    for _ in range(18):
        x0 = r.uniform(0, W)
        y0 = r.uniform(0.045, 0.094) * H / Sy
        L = r.uniform(18, 140)
        n = 4
        sl = r.normal(0, 0.03)
        items.append(([(x0 + L * i / n, y0 + sl * L * i / n + r.normal(0, 0.25)) for i in range(n + 1)],
                      r.uniform(1.0, 3.0), r.uniform(0.25, 0.7)))
    sc = ndi.gaussian_filter(strokes(W, H, items), (0.7, 2.5), mode="wrap")
    col = col * (1.0 - sc[..., None] * np.array([0.42, 0.42, 0.4], F32)[None, None, :])
    chips = sstep(2.6, 3.2, noise(W, H, (Sx, Sy), 86, lam=(0.0015, 0.005), beta=0.0)) * (sstep(6.0, 1.5, ym) + sstep(85.0, 98.0, ym))
    col = mixc(col, paint((150, 118, 82), np.ones_like(x)), np.clip(chips, 0, 1) * 0.8)
    save("baseboard", col)
    h = th + grain * 0.04 + brush * 0.015 - chips * 0.2
    save_normal("baseboard", h.astype(F32), (Sx, Sy), gain=1.0, wrap_v=False)


# ----------------------------------------------------------------- бетон, плитка, линолеум, дерево

def concrete():
    """Бетон монолитный (стены/потолок): повтор 2.4 м (1024). Щиты опалубки 1.2 × 2.4 м (швы-гребешки на
    u = 0.25, 0.75 и v = 0.5 — не на краю повтора), отпечаток фанеры, раковины, конусы стяжек через 0.6 м (часть заделана).
    concrete_dirty — потёки ржавчины от стяжек, высолы, сырость.
    concrete_floor(+_dirty) — затёртая стяжка: следы затирочной машины, нарезанные швы, волосяные трещины."""
    N, S = 1024, 2.4
    x, y = coords(N, N, (S, S))
    px = S / N
    paste = noise(N, N, (S, S), 91, lam=(0.01, 0.6), beta=2.2)
    sand = noise(N, N, (S, S), 92, lam=(0.003, 0.012), beta=0.5)
    clusters = sstep(-0.3, 1.0, noise(N, N, (S, S), 93, lam=(0.1, 0.6)))
    bug = sstep(2.5, 3.2, noise(N, N, (S, S), 94, lam=(0.003, 0.009), beta=0.0)) * clusters
    ply = noise(N, N, (S, S), 95, lam=(0.004, 0.08), beta=1.5, stretch=(1.0, 12.0))
    pi_ = (np.floor((x + 0.6) / 1.2)).astype(np.int32) % 2         # щиты 1.2 м, швы на x = 0.6 и 1.8, y = 1.2
    r = R(96)
    ptone = r.uniform(-0.035, 0.035, 2).astype(F32)[pi_]
    sxd = np.abs(wrapd(x - 0.6, 1.2))
    syd = np.abs(wrapd(y - 1.2, 2.4))
    fin = np.exp(-(np.minimum(sxd, syd) / 0.0018) ** 2)
    fin_sh = np.exp(-((np.minimum(sxd, syd) - 0.004) / 0.003) ** 2)
    # стяжки
    tie = np.zeros_like(x)
    ring = np.zeros_like(x)
    patch = np.zeros_like(x)
    rust_src = []
    for i in range(4):
        for j in range(4):
            cx, cy = 0.3 + 0.6 * i, 0.3 + 0.6 * j
            dd = np.hypot(wrapd(x - cx, S), wrapd(y - cy, S))
            if r.random() < 0.35:
                patch = np.maximum(patch, sstep(0.017, 0.013, dd))
            else:
                tie = np.maximum(tie, sstep(0.0125, 0.0095, dd))
                ring = np.maximum(ring, np.exp(-((dd - 0.013) / 0.002) ** 2))
                rust_src.append((cx, cy))
    lum = 1.0 + paste * 0.06 + sand * 0.025 + ply * 0.014 + ptone - bug * 0.4 - fin_sh * 0.08 + fin * 0.05 \
        - tie * 0.55 - ring * 0.12 + patch * 0.06
    col = paint((152, 150, 144), lum)
    save("concrete", col)
    h = sand * 0.08 + paste * 0.25 + ply * 0.12 - bug * 2.0 + fin * 1.0 - tie * 6.0 + patch * 0.3
    save_normal("concrete", h, (S, S), gain=1.0)
    # грязный
    rs = np.zeros_like(x)
    for cx, cy in rust_src:
        L = r.uniform(0.15, 0.6)
        dyy = (y - cy) % S
        wob = 0.004 * np.sin(dyy * 30.0 + cx * 7)
        prof = np.exp(-((wrapd(x - cx + wob, S)) / (0.006 + dyy * 0.02)) ** 2)
        rs = np.maximum(rs, prof * sstep(0.0, 0.01, dyy) * sstep(L, 0.0, dyy))
    efl = sstep(0.8, 2.2, noise(N, N, (S, S), 97, lam=(0.03, 0.4), beta=2.0)) * sstep(-0.5, 1.0, noise(N, N, (S, S), 98, lam=(0.005, 0.03), beta=1.0))
    damp = sstep(0.0, 1.8, noise(N, N, (S, S), 99, lam=(0.05, 0.6), beta=2.2))
    d = age(col, damp * 0.9, (0.8, 0.79, 0.76))
    d = age(d, rs * 0.85, (0.78, 0.58, 0.4))
    d = mixc(d, paint((214, 212, 204), np.ones_like(x)), efl * 0.55)
    save("concrete_dirty", d)

    # пол
    trow = np.zeros_like(x)
    for _ in range(22):
        cx, cy, rad = r.uniform(0, S), r.uniform(0, S), r.uniform(0.15, 0.45)
        a0 = r.uniform(0, 2 * np.pi)
        dx_, dy_ = wrapd(x - cx, S), wrapd(y - cy, S)
        dd = np.hypot(dx_, dy_)
        ang = np.arctan2(dy_, dx_)
        win = np.clip(np.cos(ang - a0), 0, 1) ** 2
        trow += np.exp(-((dd - rad) / 0.035) ** 2) * win * r.uniform(-1, 1)
    jd = np.minimum(np.abs(wrapd(x - 1.2, S)), np.abs(wrapd(y - 1.2, S)))   # нарезанные швы посередине повтора
    cw = 0.0022 * (1.0 + 0.4 * noise(N, N, (S, S), 100, lam=(0.005, 0.05), beta=1.0))
    joint = sstep(cw + 0.0012, cw - 0.0004, jd)
    crack = zero_lines(noise(N, N, (S, S), 101, lam=(0.2, 1.2), beta=2.0) + 0.05 * noise(N, N, (S, S), 108, lam=(0.015, 0.05), beta=1.0), 0.65, 0.5) \
        * sstep(0.4, 1.0, noise(N, N, (S, S), 102, lam=(0.3, 1.2)))
    agg = sstep(2.4, 3.0, noise(N, N, (S, S), 103, lam=(0.003, 0.008), beta=0.0))
    agg2 = sstep(2.4, 3.0, noise(N, N, (S, S), 104, lam=(0.003, 0.008), beta=0.0))
    fl = 1.0 + paste * 0.05 + sand * 0.018 + trow * 0.025 - joint * 0.55 - crack * 0.25 + agg * 0.06 - agg2 * 0.07
    fcol = paint((150, 146, 138), fl)
    save("concrete_floor", fcol)
    hf = paste * 0.15 + sand * 0.04 + trow * 0.05 - joint * 4.0 - crack * 0.4
    save_normal("concrete_floor", hf, (S, S), gain=1.0)
    oil = sstep(0.6, 3.0, noise(N, N, (S, S), 105, lam=(0.08, 0.6), beta=2.4))
    grime = noise(N, N, (S, S), 107, lam=(0.03, 0.3))
    fd = age(fcol, 0.7 + 0.25 * grime, (0.88, 0.86, 0.82))
    fd = age(fd, oil * 0.6, (0.7, 0.68, 0.64))
    fd = fd * (1.0 - joint[..., None] * 0.2)
    save("concrete_floor_dirty", fd)


def tiles():
    """Кафель 15 × 15 см (8 × 8 на повтор 1.2 м), шов 3 мм. Подушка глазури у кромок, волна глазури,
    тон каждой плитки свой, редкие сколы углов. tile_dirty — тёмные заплесневелые швы, налёт."""
    N, S, SS = 1024, 1.2, 2
    X, Y = coords(N, N, (S, S), SS)
    gx, gy = np.abs(wrapd(X, 0.15)), np.abs(wrapd(Y, 0.15))
    gd = np.minimum(gx, gy)
    grout = sstep(0.0019, 0.0013, gd)
    pillow = np.clip(1.0 - np.exp(-np.maximum(gd - 0.0015, 0) / 0.0018), 0, 1)
    del X, Y, gx, gy
    grout, pillow, gd = down(grout, SS), down(pillow, SS), down(gd, SS)
    x, y = coords(N, N, (S, S))
    ix, iy = np.floor(x / 0.15).astype(np.int32), np.floor(y / 0.15).astype(np.int32)
    r = R(111)
    tv = cells(ix, iy, r.normal(0, 1, (8, 8)).astype(F32))
    tw = cells(ix, iy, r.normal(0, 1, (8, 8)).astype(F32))
    wave = noise(N, N, (S, S), 112, lam=(0.02, 0.12), beta=2.0)
    spec = noise(N, N, (S, S), 113, lam=(0.002, 0.008), beta=0.6)
    # сколы на углах части плиток
    chip = np.zeros_like(x)
    for _ in range(5):
        cx, cy = (r.integers(0, 8)) * 0.15, (r.integers(0, 8)) * 0.15
        dd = np.hypot(wrapd(x - cx + r.choice([-1, 1]) * 0.003, S), wrapd(y - cy + r.choice([-1, 1]) * 0.003, S))
        chip = np.maximum(chip, sstep(0.006, 0.004, dd) * (1 - grout))
    glaze = paint((222, 224, 216), 1.0 + tv * 0.018 + wave * 0.008 + spec * 0.006 - (1 - pillow) * 0.05)
    glaze = glaze * (1.0 + tw[..., None] * np.array([0.004, 0.0, -0.006], F32)[None, None, :])
    glaze = mixc(glaze, paint((178, 172, 160), np.ones_like(x)), chip)
    gcol = paint((156, 152, 142), 1.0 + noise(N, N, (S, S), 114, lam=(0.002, 0.02), beta=1.0) * 0.05)
    col = mixc(glaze, gcol, grout)
    save("tile", col)
    tilt = cells(ix, iy, r.normal(0, 1, (8, 8)).astype(F32)) * (x % 0.15 - 0.075) + cells(ix, iy, r.normal(0, 1, (8, 8)).astype(F32)) * (y % 0.15 - 0.075)
    h = pillow * 1.2 - grout * 1.5 + wave * 0.05 + tilt * 1.5 - chip * 0.8
    save_normal("tile", h, (S, S), gain=1.2)
    mild = sstep(0.0, 2.0, noise(N, N, (S, S), 115, lam=(0.01, 0.15), beta=1.5))
    halo = sstep(0.006, 0.0015, gd) * (1 - grout)
    d = mixc(col, paint((112, 104, 88), 1.0 - mild * 0.25), grout * 0.75)
    d = age(d, halo * 0.5, (0.88, 0.86, 0.78))
    d = weathered(d, (S, S), 116, amount=0.1, grime=(130, 124, 104), mott=1.0, fox=0.5)
    save("tile_dirty", d)


def linoleum():
    """Виниловая плитка VCT 30 × 30 см шахматкой (4 × 4 на 1.2 м): мраморная крошка (направление
    чередуется), швы с натёком мастики, следы каблуков. linoleum_dirty — пожелтевшая мастика, грязь."""
    N, S = 1024, 1.2
    x, y = coords(N, N, (S, S))
    ix, iy = np.floor(x / 0.3).astype(np.int32), np.floor(y / 0.3).astype(np.int32)
    chk = ((ix + iy) % 2).astype(F32)
    rot = ((ix * 3 + iy) % 2).astype(bool)
    m1 = noise(N, N, (S, S), 121, lam=(0.004, 0.04), beta=1.6, stretch=(1.0, 2.5))
    m2 = noise(N, N, (S, S), 122, lam=(0.004, 0.04), beta=1.6, stretch=(2.5, 1.0))
    marb = np.where(rot, m1, m2)
    flk = sstep(1.9, 2.5, noise(N, N, (S, S), 123, lam=(0.0026, 0.007), beta=0.0))
    flk2 = sstep(1.9, 2.5, noise(N, N, (S, S), 124, lam=(0.0026, 0.007), beta=0.0))
    r = R(125)
    tv = cells(ix, iy, r.normal(0, 1, (4, 4)).astype(F32))
    sd = np.minimum(np.abs(wrapd(x, 0.3)), np.abs(wrapd(y, 0.3)))
    seam = np.exp(-(sd / 0.0006) ** 2)
    wax = np.exp(-(sd / 0.003) ** 2)
    light, dark = c3((192, 184, 162)), c3((126, 120, 106))
    base = mixc(paint(light, np.ones_like(x)), paint(dark, np.ones_like(x)), chk)
    chips = noise(N, N, (S, S), 120, lam=(0.003, 0.012), beta=0.8)
    lum = 1.0 + marb * 0.032 + chips * 0.028 + tv * 0.015 + flk * 0.1 - flk2 * 0.1 - seam * 0.35 - wax * 0.05
    col = base * lum[..., None]
    items = []
    for _ in range(36):
        x0, y0 = r.uniform(0, N), r.uniform(0, N)
        items.append((walk(r, x0, y0, 5, r.uniform(2, 6), r.uniform(0, 2 * np.pi), 0.35), r.uniform(1.0, 2.2), r.uniform(0.3, 0.9)))
    heel = blur(strokes(N, N, items), 0.6)
    haze = sstep(-1.0, 2.0, noise(N, N, (S, S), 126, lam=(0.05, 0.4), beta=2.0))
    col = col * (1.0 - heel[..., None] * 0.45) * (1.0 + haze[..., None] * 0.025)
    save("linoleum", col)
    tilt = cells(ix, iy, r.normal(0, 1, (4, 4)).astype(F32)) * (x % 0.3 - 0.15) + cells(ix, iy, r.normal(0, 1, (4, 4)).astype(F32)) * (y % 0.3 - 0.15)
    h = -seam * 0.3 + tilt * 0.4 + noise(N, N, (S, S), 127, lam=(0.01, 0.1), beta=2.0) * 0.04
    save_normal("linoleum", h, (S, S), gain=2.0)
    grime = sstep(-0.5, 2.0, noise(N, N, (S, S), 128, lam=(0.03, 0.3)))
    d = weathered(col, (S, S), 129, amount=0.14, grime=(104, 94, 74), mott=1.2, fox=0.4)
    d = age(d, wax * 0.9 + grime * 0.3, (0.82, 0.78, 0.68))
    save("linoleum_dirty", d)


def wood_floor():
    """Паркетная доска: планки 7.5 см (64 px) вдоль v, длины 0.6/1.2 м вразбежку (повтор 1.2 м), волокна
    и годовые слои, тон планки, усушка швов, лак и вытертые дорожки."""
    N, S = 1024, 1.2
    x, y = coords(N, N, (S, S))
    nb = 16
    ib = np.floor(x / (S / nb)).astype(np.int32) % nb
    r = R(131)
    off = r.uniform(0, 1.2, nb).astype(F32)
    ln = r.choice([0.6, 1.2], nb).astype(F32)
    yb = (y + off[ib])
    nseg = np.round(S / ln).astype(np.int32)              # досок на повтор в этом ряду
    seg = np.floor(yb / ln[ib]).astype(np.int32) % nseg[ib]
    bid = (ib * 7 + seg * 3) % 64
    tone = r.normal(0, 1, 64).astype(F32)[bid]
    hue = r.normal(0, 1, 64).astype(F32)[bid]
    shift = (r.integers(0, N, 64))[bid]
    g1 = noise(N, N, (S, S), 132, lam=(0.002, 0.05), beta=1.6, stretch=(1.0, 14.0))
    g2 = noise(N, N, (S, S), 133, lam=(0.006, 0.08), beta=2.0, stretch=(1.0, 20.0))
    rows_i = np.arange(N)[:, None]
    gi = (rows_i + shift) % N
    cols_i = np.broadcast_to(np.arange(N)[None, :], (N, N))
    g1 = g1[gi, cols_i]
    g2 = g2[gi, cols_i]
    rings = zero_lines(g2, 0.7, 0.6)
    ex = np.abs(wrapd(x, S / nb))
    ey = np.abs(wrapd(yb, ln[ib]))
    side = np.exp(-(ex / 0.0006) ** 2)
    endj = np.exp(-(ey / 0.0006) ** 2)
    wear = sstep(-0.5, 1.8, noise(N, N, (S, S), 134, lam=(0.08, 0.4), beta=2.0))
    lum = 1.0 + tone * 0.09 + g1 * 0.05 - rings * 0.14 - side * 0.45 - endj * 0.4 + wear * 0.05
    col = paint((132, 98, 68), lum)
    col = col * (1.0 + hue[..., None] * np.array([0.025, 0.0, -0.035], F32)[None, None, :])
    save("wood_floor", col)
    cup = (ex / (S / nb * 0.5)) ** 2 * 0.15
    h = g1 * 0.03 - rings * 0.04 - side * 0.6 - endj * 0.6 + cup
    save_normal("wood_floor", h, (S, S), gain=1.5)


def plaster():
    """Гладкая окрашенная штукатурка/гипсокартон (потолок дома, стенки в концовках). Повтор 1.2 м."""
    N, S = 1024, 1.2
    x, y = coords(N, N, (S, S))
    trowel = noise(N, N, (S, S), 141, lam=(0.03, 0.4), beta=2.0, stretch=(1.6, 1.0))
    fine = noise(N, N, (S, S), 142, lam=(0.0015, 0.006), beta=0.8)
    crack = zero_lines(noise(N, N, (S, S), 143, lam=(0.1, 0.6), beta=2.0) + 0.12 * noise(N, N, (S, S), 145, lam=(0.004, 0.02), beta=1.0), 0.5, 0.5) \
        * sstep(1.0, 1.6, noise(N, N, (S, S), 144, lam=(0.2, 0.6)))
    col = paint((214, 208, 194), 1.0 + trowel * 0.015 + fine * 0.006 - crack * 0.15)
    save("plaster", col)
    save_normal("plaster", trowel * 0.12 + fine * 0.03 - crack * 0.25, (S, S), gain=2.0)


# ----------------------------------------------------------------- большие карты износа (в мировых координатах)

def wall_grime():
    """Маски износа стен 2048×1024 = 4.8 м × 3.2 м, по горизонтали бесшовная, верх = потолок.
    R — сырые пятна с тёмной каймой (чаще у потолка и у пола), G — потёки от потолка вниз,
    B — подсос влаги от пола (5–40 см, неровная кромка). Значения 0..1, без резких порогов."""
    W, H, Sx, Sy = 2048, 1024, 4.8, 3.2
    # шум на удвоенной высоте и верхняя половина — нет переноса сверху вниз
    def nz(seed, lam, beta=2.0, stretch=(1.0, 1.0)):
        return noise(W, 2 * H, (Sx, 2 * Sy), seed, lam, beta, stretch)[:H]
    x, y = coords(W, H, (Sx, Sy))
    hf = Sy - y
    px = Sx / W
    gs = nz(201, (0.2, 1.6), 3.4, (1.0, 0.7)) + 1.3 * np.exp(-y / 0.6) + 0.8 * np.exp(-hf / 0.45) - 1.75
    grad = np.sqrt(((np.roll(gs, -1, 1) - np.roll(gs, 1, 1)) * 0.5 / px) ** 2
                   + ((np.roll(gs, -1, 0) - np.roll(gs, 1, 0)) * 0.5 / (Sy / H)) ** 2)
    dist = gs / (grad + 1e-3) + 0.006 * nz(202, (0.03, 0.15), 2.0)      # до кромки пятна, м (кромка волнистая)
    inner = sstep(0.0, 0.15, dist) * 0.36 * (0.85 + 0.15 * nz(208, (0.03, 0.2), 2.0))
    tw = 0.75 + 0.25 * nz(209, (0.02, 0.1), 1.5)                          # кайма то гуще, то бледнее
    tide = (np.exp(-((dist - 0.006) / 0.008) ** 2) * 0.55 + np.exp(-((dist - 0.055) / 0.009) ** 2) * 0.14) * tw
    Rm = np.clip(inner + tide * sstep(-0.02, 0.0, dist), 0, 1)
    # потёки
    r = R(203)
    G = np.zeros((H, W), F32)
    for _ in range(24):
        x0 = r.uniform(0, Sx)
        L = r.uniform(0.12, 1.1) if r.random() < 0.75 else r.uniform(1.1, 2.9)
        w = r.uniform(0.005, 0.022)
        a = r.uniform(0.3, 0.9)
        y0 = 0.0 if r.random() < 0.8 else r.uniform(0.2, 1.2)
        ph = r.uniform(0, 6.3)
        rows = (y >= y0) & (y <= y0 + L)
        t = np.clip((y - y0) / L, 0, 1)
        xc = x0 + 0.006 * np.sin((y - y0) * 9.0 + ph) + 0.003 * np.sin((y - y0) * 31.0 + ph * 2)
        wd = w * (1.35 - 0.7 * t)
        prof = np.exp(-(wrapd(x - xc, Sx) / wd) ** 2)
        along = (1.0 - t) ** 0.7 * sstep(0.0, 0.03, y - y0) * (0.8 + 0.2 * np.sin((y - y0) * 57.0 + ph))
        G = np.maximum(G, np.where(rows, prof * along * a, 0.0))
    G = blur(G, 0.8)
    # подсос от пола
    hw = 0.05 + 0.33 * np.clip(0.5 + 0.5 * noise1(W, Sx, 204, (0.6, 4.0), 2.6) / 1.1, 0, 1) ** 1.3
    hw = hw + 0.004 * noise1(W, Sx, 205, (0.03, 0.12), 2.0) + 0.012 * noise1(W, Sx, 207, (0.12, 0.5), 2.0)
    hw = hw[None, :]
    wet = sstep(hw + 0.006, hw - 0.04, hf) * (0.3 + 0.08 * nz(206, (0.02, 0.15), 1.5))
    tl = np.exp(-((hf - hw) / 0.009) ** 2) * 0.7 + np.exp(-((hf - hw * 0.62) / 0.007) ** 2) * 0.15
    B = np.clip(wet + tl, 0, 1)
    save("wall_grime", np.dstack([Rm, G, B]))


def ceil_stains():
    """Потолочные протечки 1024² = 9.6 м (16 × 16 плит 0.6 м), бесшовно. Брать с тем же сдвигом, что и
    ceiling_tile: uv = (x + 0.3, z) / 9.6 — тогда разрывы пятен на краях плит лягут на профили.
    R — кольцевые пятна с тёмными кольцами (у каждой плиты своя впитываемость), G — бурые провисшие плиты."""
    N, S = 1024, 9.6
    x, y = coords(N, N, (S, S))
    r = R(211)
    sx, sy = np.abs(wrapd(x, 0.6)), np.abs(wrapd(y, 0.6))
    gridm = sstep(0.008, 0.016, np.minimum(sx, sy))         # на профилях пятен нет
    ti, tj = np.floor(x / 0.6).astype(np.int32), np.floor(y / 0.6).astype(np.int32)
    absorb = cells(ti, tj, r.uniform(0.55, 1.0, (16, 16)).astype(F32))
    warp = noise(N, N, (S, S), 212, lam=(0.03, 0.3), beta=2.0)
    Rm = np.zeros_like(x)
    for k in range(16):
        cx, cy = r.uniform(0, S), r.uniform(0, S)
        rad = r.uniform(0.1, 0.3) if k > 2 else r.uniform(0.35, 0.6)
        d = np.hypot(wrapd(x - cx, S), wrapd(y - cy, S)) / rad
        d = d * (1.0 + 0.16 * warp)
        rw = 0.016 / rad
        s = sstep(1.0, 0.82, d) * 0.3
        s = s + np.exp(-((d - 1.0) / rw) ** 2) * 0.8
        s = s + np.exp(-((d - 0.78) / rw) ** 2) * 0.4 + np.exp(-((d - 0.55) / rw) ** 2) * 0.25
        Rm = np.maximum(Rm, np.clip(s, 0, 1))
    Rm = Rm * absorb * gridm
    sag = cells(ti, tj, (r.random((16, 16)) < 0.07).astype(F32) * r.uniform(0.35, 0.9, (16, 16)).astype(F32))
    inside = (1.0 - (1.0 - sx / 0.3) ** 2) * (1.0 - (1.0 - sy / 0.3) ** 2)
    blot = sstep(-1.2, 1.2, noise(N, N, (S, S), 214, lam=(0.05, 0.3), beta=2.0))
    G = sag * (0.2 + 0.8 * inside ** 0.7) * (0.45 + 0.55 * blot) + 0.22 * sstep(0.5, 2.2, noise(N, N, (S, S), 213, lam=(0.3, 2.5), beta=2.4))
    G = np.clip(G, 0, 1) * gridm
    save("ceil_stains", np.dstack([Rm, G, np.zeros_like(x)]))


def carpet_damp():
    """Ковёр в мировых координатах 1024² = 9.6 м, бесшовно: R — тёмные сырые разводы,
    G — вытоптанные дорожки (светлее, ворс примят)."""
    N, S = 1024, 9.6
    x, y = coords(N, N, (S, S))
    f = noise(N, N, (S, S), 221, lam=(0.2, 3.0), beta=2.6) + 0.12 * noise(N, N, (S, S), 222, lam=(0.04, 0.2), beta=1.5)
    Rm = sstep(0.1, 2.1, f) ** 1.2
    r = R(223)
    G = np.zeros_like(x)
    for k in range(6):
        along_x = k % 2 == 0
        a, b = (x, y) if along_x else (y, x)
        c0 = r.uniform(0, S)
        amp = r.uniform(0.15, 0.6)
        kk = r.integers(1, 3)
        ph = r.uniform(0, 6.3)
        w = r.uniform(0.3, 0.55) * (1.0 + 0.3 * np.sin(2 * np.pi * 3 * a / S + ph * 2))
        cc = c0 + amp * np.sin(2 * np.pi * kk * a / S + ph) + 0.12 * np.sin(2 * np.pi * 5 * a / S + ph * 3)
        G = np.maximum(G, np.exp(-(wrapd(b - cc, S) / w) ** 2) * r.uniform(0.45, 1.0))
    G = G * (0.75 + 0.25 * sstep(-1.5, 1.5, noise(N, N, (S, S), 224, lam=(0.3, 2.0))))
    save("carpet_damp", np.dstack([Rm, G, np.zeros_like(x)]))


def noise_tex():
    """Служебный шум 512² (R, G, B — независимые маски), бесшовный, импортируется без сжатия.
    Тот же смысл каналов, что и раньше: R — 1/f^2.4, G — 1/f^3 (плавнее), B — полоса 4..16 периодов."""
    n = 512
    def pn(beta, seed):
        w = R(seed).standard_normal((n, n))
        f = np.fft.fft2(w)
        k = np.sqrt(np.fft.fftfreq(n)[:, None] ** 2 + np.fft.fftfreq(n)[None, :] ** 2)
        k[0, 0] = 1.0
        f *= 1.0 / (k ** (beta / 2.0))
        f[0, 0] = 0
        o = np.real(np.fft.ifft2(f))
        return (o - o.min()) / (o.max() - o.min())
    def bd(lo, hi, seed):
        w = R(seed).standard_normal((n, n))
        f = np.fft.fft2(w)
        k = np.sqrt((np.fft.fftfreq(n)[:, None] * n) ** 2 + (np.fft.fftfreq(n)[None, :] * n) ** 2)
        f *= (sstep(lo - 1.0, lo, k) * sstep(hi + 2.0, hi, k))
        o = np.real(np.fft.ifft2(f))
        return (o - o.min()) / (o.max() - o.min())
    save("noise", np.dstack([pn(2.4, 111), pn(3.0, 112), bd(4, 16, 113)]))


# ----------------------------------------------------------------- предметы (UV предмета, «1 м» условно)

def metal():
    """Металл/пластик предметов (умножается на цвет предмета, среднее ~0.75): шлифовка, царапины,
    грязь в пятнах, затёртости."""
    N, S = 1024, 1.0
    brushed = noise(N, N, (S, S), 151, lam=(0.002, 0.08), beta=1.2, stretch=(14.0, 1.0))
    grime = sstep(-0.3, 2.0, noise(N, N, (S, S), 152, lam=(0.03, 0.3), beta=2.0))
    mot = noise(N, N, (S, S), 153, lam=(0.01, 0.2), beta=2.0)
    r = R(154)
    items = []
    for _ in range(140):
        x0, y0 = r.uniform(0, N), r.uniform(0, N)
        ang = r.uniform(0, np.pi) if r.random() < 0.6 else r.normal(0, 0.15)
        n = r.integers(2, 6)
        items.append((walk(r, x0, y0, n, r.uniform(6, 30), ang, 0.05), r.uniform(0.6, 1.4), r.uniform(0.3, 1.0)))
    scr = strokes(N, N, items)
    wear = sstep(1.0, 2.2, noise(N, N, (S, S), 155, lam=(0.01, 0.1), beta=1.5))
    lum = 0.76 + brushed * 0.025 + mot * 0.03 - grime * 0.12 + scr * 0.12 + wear * 0.08
    rust = sstep(2.0, 2.8, noise(N, N, (S, S), 156, lam=(0.003, 0.02), beta=1.0)) * grime
    col = np.dstack([lum, lum, lum])
    col = mixc(col, paint((120, 84, 58), np.ones_like(lum)), rust * 0.5)
    save("metal", col)
    h = brushed * 0.01 - scr * 0.03 + noise(N, N, (S, S), 157, lam=(0.05, 0.4), beta=2.0) * 0.3 - rust * 0.05
    save_normal("metal", h, (S, S), gain=2.0)


def fabric():
    """Ткань предметов и одежды (умножается на цвет, среднее ~0.85): саржа 2/2 (128 нитей на повтор),
    неровная пряжа, катышки, вытертые и засаленные места."""
    N, S, SS = 1024, 1.0, 2
    X, Y = coords(N, N, (S, S), SS)
    th = 128
    u, v = X / S * th, Y / S * th
    iu, iv = np.floor(u).astype(np.int32), np.floor(v).astype(np.int32)
    fu, fv = u - iu, v - iv
    over = ((iu + iv) // 2 % 2).astype(bool)                 # саржа: диагональ
    warp_h = np.sin(np.pi * fu) ** 0.8 * (0.75 + 0.25 * np.cos(np.pi * (fv - 0.5)))
    weft_h = np.sin(np.pi * fv) ** 0.8 * (0.75 + 0.25 * np.cos(np.pi * (fu - 0.5)))
    h = np.where(over, warp_h, weft_h).astype(F32)
    del X, Y, u, v, fu, fv, warp_h, weft_h
    h = down(h, SS)
    over = down(over.astype(F32), SS)
    slub_u = noise1(th, S, 161, (0.01, 0.2), 1.0)
    slub_v = noise1(th, S, 162, (0.01, 0.2), 1.0)
    x, y = coords(N, N, (S, S))
    iu1 = (np.floor(x / S * th).astype(np.int32)) % th
    iv1 = (np.floor(y / S * th).astype(np.int32)) % th
    slub = over * slub_u[iu1] + (1 - over) * slub_v[iv1]
    pill = sstep(2.3, 2.9, noise(N, N, (S, S), 163, lam=(0.002, 0.006), beta=0.0))
    worn = sstep(0.0, 2.0, noise(N, N, (S, S), 164, lam=(0.04, 0.3), beta=2.0))
    stain = sstep(1.0, 2.4, noise(N, N, (S, S), 165, lam=(0.02, 0.2), beta=2.0))
    lum = 0.85 * (0.86 + 0.14 * h) * (1.0 + slub * 0.03) + pill * 0.05 + worn * 0.04 - stain * 0.08
    save("fabric", np.dstack([lum, lum, lum]))
    save_normal("fabric", h * 0.25 + pill * 0.1 + noise(N, N, (S, S), 166, lam=(0.03, 0.3)) * 0.2, (S, S), gain=1.5)


def wood():
    """Дерево предметов (умножается на цвет; средний тон как у прежней): волокна вдоль v, годовые слои,
    сучок, царапины и грязь."""
    N, S = 1024, 1.0
    x, y = coords(N, N, (S, S))
    warpx = noise(N, N, (S, S), 171, lam=(0.05, 0.4), beta=2.0) * 0.02
    g = noise(N, N, (S, S), 172, lam=(0.003, 0.1), beta=1.6, stretch=(1.0, 12.0))
    ringsf = noise(N, N, (S, S), 173, lam=(0.01, 0.12), beta=2.2, stretch=(1.0, 10.0))
    rings = zero_lines(ringsf + warpx * 10, 0.8, 0.7)
    knot = np.zeros_like(x)
    for cx, cy in ((0.3, 0.25), (0.72, 0.7)):
        d = np.hypot(wrapd(x - cx, S) * 1.0, wrapd(y - cy, S) * 0.45)
        knot = np.maximum(knot, sstep(0.025, 0.012, d))
    r = R(174)
    items = []
    for _ in range(50):
        x0, y0 = r.uniform(0, N), r.uniform(0, N)
        items.append((walk(r, x0, y0, 3, r.uniform(8, 25), r.uniform(0, np.pi), 0.1), r.uniform(0.6, 1.4), r.uniform(0.3, 1.0)))
    scr = strokes(N, N, items)
    grime = sstep(-0.3, 2.0, noise(N, N, (S, S), 175, lam=(0.03, 0.3)))
    lum = 0.93 + g * 0.08 - rings * 0.16 - knot * 0.35 + scr * 0.08 - grime * 0.1
    col = paint((140, 98, 60), lum)
    save("wood", col)
    save_normal("wood", g * 0.04 - rings * 0.05 - scr * 0.04 + knot * 0.1, (S, S), gain=1.5)


def paper():
    """Бумага записок и коробок: волокна, лёгкая волнистость, пожелтение и редкие пятна (не мешают тексту)."""
    N, S = 512, 0.5
    fib = noise(N, N, (S, S), 181, lam=(0.001, 0.006), beta=1.0, stretch=(1.0, 2.0))
    mot = noise(N, N, (S, S), 182, lam=(0.01, 0.15), beta=2.0)
    st = sstep(1.2, 2.6, noise(N, N, (S, S), 183, lam=(0.02, 0.15), beta=2.0))
    fox = sstep(2.4, 3.0, noise(N, N, (S, S), 184, lam=(0.0015, 0.006), beta=0.0))
    col = paint((228, 220, 198), 1.0 + fib * 0.015 + mot * 0.02)
    col = age(col, st * 0.6, (0.9, 0.86, 0.76))
    col = age(col, fox * 0.7, (0.8, 0.7, 0.55))
    save("paper", col)


def mold():
    """Чёрная плесень — пятно с альфой (не тайлится): колонии точек гуще к центру, серо-зелёный ореол"""
    n = 512
    x, y = coords(n, n, (1.0, 1.0))
    xc, yc = x - 0.5, y - 0.5
    rr = np.hypot(xc, yc)
    ang_n = noise(n, n, (1.0, 1.0), 191, lam=(0.05, 0.4), beta=2.0)
    edge = 0.36 + 0.07 * ang_n
    env = sstep(edge, edge - 0.18, rr)
    col_n = noise(n, n, (1.0, 1.0), 192, lam=(0.006, 0.05), beta=1.2)
    dots = sstep(1.6, 2.3, noise(n, n, (1.0, 1.0), 193, lam=(0.004, 0.015), beta=0.3))
    core = sstep(-0.2, 0.8, col_n + env * 1.5 - 0.8)
    a = np.clip(core * env * 1.1 + dots * sstep(edge + 0.06, edge - 0.1, rr) * 0.85, 0, 1)
    halo = sstep(edge + 0.04, edge - 0.25, rr) * 0.22 * sstep(-1.0, 1.0, col_n)
    a = np.clip(np.maximum(a, halo), 0, 1) * sstep(0.49, 0.45, rr)
    base = np.dstack([np.full_like(x, 0.05), np.full_like(x, 0.058), np.full_like(x, 0.045)])
    base = mixc(base, paint((70, 78, 58), np.ones_like(x)), np.clip(halo * 3.0 - core, 0, 1))
    save("mold", np.dstack([base, a]))


def fiber():
    """Волокна (Сущность, стекловата в концовке): тянутся вдоль v, серые, среднее ~0.5"""
    N, S = 512, 1.0
    f = noise(N, N, (S, S), 195, lam=(0.004, 0.1), beta=1.5, stretch=(1.0, 12.0))
    strands = zero_lines(noise(N, N, (S, S), 196, lam=(0.006, 0.05), beta=1.0, stretch=(1.0, 8.0)), 0.8, 0.7)
    g = noise(N, N, (S, S), 197, lam=(0.01, 0.2), beta=2.0)
    lum = np.clip(0.5 + f * 0.13 + strands * 0.18 + g * 0.06, 0, 1)
    save("fiber", lum)
    save_normal("fiber", f * 0.2 + strands * 0.25, (S, S), gain=2.0)


def hazard():
    """Сигнальная разметка: жёлто-чёрные полосы 45° (512×128, ровно 4 периода по u и 1 по v),
    сглаженные края, сколы краски до серого металла, грязь, царапины."""
    W, H, SS = 512, 128, 4
    X, Y = coords(W, H, (W, H), SS)                       # в пикселях
    s = ((X + Y) / 64.0) % 2.0
    stripe = sstep(0.0, 0.02, s) * sstep(1.0, 0.98, s)       # жёлтая половина периода
    stripe = down(stripe.astype(F32), SS)
    del X, Y, s
    size = (1.0, 0.25)
    chips = sstep(1.6, 2.3, noise(W, H, size, 198, lam=(0.004, 0.03), beta=1.0))
    grime = sstep(-0.5, 2.0, noise(W, H, size, 199, lam=(0.02, 0.2), beta=2.0))
    yel = paint((214, 170, 30), np.ones((H, W), F32))
    blk = paint((28, 25, 22), np.ones((H, W), F32))
    col = mixc(blk, yel, stripe)
    col = mixc(col, paint((120, 118, 112), np.ones((H, W), F32)), chips * 0.85)
    col = age(col, grime * 0.7, (0.74, 0.7, 0.62))
    r = R(200)
    items = [(walk(r, r.uniform(0, W), r.uniform(0, H), 2, r.uniform(5, 20), r.uniform(0, np.pi), 0.1), 0.8, r.uniform(0.3, 0.8)) for _ in range(30)]
    col = col * (1.0 - strokes(W, H, items)[..., None] * 0.25)
    save("hazard", col)
    save_normal("hazard", -chips * 0.15 + grime * 0.02, size, gain=2.0)


# ----------------------------------------------------------------- старые генераторы (парк, концовки, лица)
# Их результаты лежат в репозитории и принадлежат другим задачам; по умолчанию не перегенерируются.

def save_old(name, arr):
    """Сохранение как в прежней версии скрипта (усечение, а не округление) — старые текстуры бит в бит"""
    arr = np.clip(arr, 0, 1)
    Image.fromarray((arr * 255).astype(np.uint8)).save(os.path.join(OUT, name + ".png"))
    print("  ", name)


def legacy_rng():
    """Глобальный rng в том же состоянии, что был у прежнего скрипта перед лицами и парком (те же выборки:
    ковёр, потолок, бетон, плитка, плесень)"""
    global rng
    rng = np.random.default_rng(1990)
    for shape in ((512, 512), (512, 512), (512, 512), (8, 8), (256, 256)):
        rng.random(shape)


def pnoise(n, beta=2.0, seed=None, aniso=(1.0, 1.0)):
    """Периодический шум 1/f^beta, нормированный в 0..1"""
    r = np.random.default_rng(seed) if seed is not None else rng
    w = r.standard_normal((n, n))
    f = np.fft.fft2(w)
    ky = np.fft.fftfreq(n)[:, None] * aniso[1]
    kx = np.fft.fftfreq(n)[None, :] * aniso[0]
    k = np.sqrt(kx * kx + ky * ky)
    k[0, 0] = 1.0
    f *= 1.0 / (k ** (beta / 2.0))
    f[0, 0] = 0
    o = np.real(np.fft.ifft2(f))
    o -= o.min()
    o /= o.max() + 1e-9
    return o


def band(n, lo, hi, seed=None):
    """Периодический шум в полосе частот (пятна заданного размера)"""
    r = np.random.default_rng(seed) if seed is not None else rng
    w = r.standard_normal((n, n))
    f = np.fft.fft2(w)
    ky = np.fft.fftfreq(n)[:, None] * n
    kx = np.fft.fftfreq(n)[None, :] * n
    k = np.sqrt(kx * kx + ky * ky)
    f *= ((k >= lo) & (k <= hi)).astype(float)
    o = np.real(np.fft.ifft2(f))
    o -= o.min()
    o /= o.max() + 1e-9
    return o


def rgb(c):
    return np.array(c, dtype=float) / 255.0


def colorize(mask, a, b):
    return a[None, None, :] * (1 - mask[..., None]) + b[None, None, :] * mask[..., None]


def faces():
    """Лицо (на квадрат 256) и «смазанное» лицо копии"""
    n = 256
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    skin = (214, 176, 150, 255)
    d.ellipse([28, 8, 228, 248], fill=skin)
    # глазницы, глаза, брови, нос, рот
    for ex in (88, 168):
        d.ellipse([ex - 26, 92, ex + 26, 122], fill=(190, 150, 128, 255))
        d.ellipse([ex - 14, 100, ex + 14, 116], fill=(236, 232, 222, 255))
        d.ellipse([ex - 7, 101, ex + 7, 115], fill=(60, 44, 34, 255))
        d.rectangle([ex - 26, 80, ex + 26, 87], fill=(96, 70, 52, 255))
    d.polygon([(128, 112), (116, 166), (140, 168)], fill=(196, 152, 128, 255))
    d.ellipse([96, 188, 160, 204], fill=(156, 92, 84, 255))
    img = img.filter(ImageFilter.GaussianBlur(2.2))
    img.save(os.path.join(OUT, "face.png"))
    print("   face")
    a = np.array(img).astype(float) / 255.0
    sm = a.copy()
    # вертикальное размазывание вниз + горизонтальный сдвиг полос
    for k in range(1, 60):
        sh = np.roll(a, k, axis=0)
        sm = np.maximum(sm * 0.995, sh * (1.0 - k / 70.0))
    for r in range(n):
        if (r // 9) % 3 == 0:
            sm[r] = np.roll(sm[r], int(8 * np.sin(r * 0.3)), axis=0)
    sm[..., :3] = sm[..., :3] * 0.92 + 0.06
    Image.fromarray((np.clip(sm, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.5)).save(os.path.join(OUT, "face_smear.png"))
    print("   face_smear")
    # «пустое» лицо (гладкое)
    blank = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    db = ImageDraw.Draw(blank)
    db.ellipse([28, 8, 228, 248], fill=skin)
    for ex in (88, 168):
        db.ellipse([ex - 22, 96, ex + 22, 118], fill=(196, 160, 138, 255))
    blank.filter(ImageFilter.GaussianBlur(4)).save(os.path.join(OUT, "face_blank.png"))
    print("   face_blank")


def grass():
    n = 512
    fine = rng.random((n, n))
    fine = np.array(Image.fromarray((fine * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))) / 255.0
    mid = pnoise(n, 2.0, 181)
    big = pnoise(n, 3.0, 182)
    green = rgb((92, 116, 48))
    dry = rgb((150, 136, 70))
    col = colorize(np.clip((big - 0.45) * 2.0, 0, 1) * 0.6, green, dry)
    col *= (0.75 + (fine - 0.5) * 0.5 + (mid - 0.5) * 0.3)[..., None]
    save_old("grass", col)


def grass_tuft():
    n = 128
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rr = np.random.default_rng(301)
    for k in range(46):
        x0 = rr.uniform(8, n - 8)
        h = rr.uniform(0.35, 0.95) * n
        lean = rr.uniform(-18, 18)
        c = (int(rr.uniform(70, 130)), int(rr.uniform(105, 150)), int(rr.uniform(35, 60)), 255)
        w = rr.uniform(2.0, 4.0)
        pts = [(x0 - w, n), (x0 + lean, n - h), (x0 + w, n)]
        d.polygon(pts, fill=c)
    img.save(os.path.join(OUT, "grass_tuft.png"))
    print("   grass_tuft")


def path():
    n = 512
    g = pnoise(n, 2.2, 191)
    f = rng.random((n, n))
    f = np.array(Image.fromarray((f * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6))) / 255.0
    col = rgb((170, 164, 150))[None, None, :] * (0.85 + (g - 0.5) * 0.2 + (f - 0.5) * 0.25)[..., None]
    y, x = np.mgrid[0:n, 0:n] / n
    seam = (np.abs(y * 2 - np.round(y * 2)) * n / 2 < 1.2).astype(float)
    save_old("path", col * (1 - seam[..., None] * 0.3))
    # асфальт
    col2 = rgb((62, 62, 64))[None, None, :] * (0.85 + (g - 0.5) * 0.25 + (f - 0.5) * 0.4)[..., None]
    save_old("asphalt", col2)


def bark():
    n = 256
    f = pnoise(n, 1.6, 201, aniso=(0.7, 10.0))
    g = pnoise(n, 2.6, 202)
    col = rgb((86, 72, 58))[None, None, :] * (0.65 + f * 0.5 + (g - 0.5) * 0.2)[..., None]
    save_old("bark", col)


def leaves():
    n = 256
    m = band(n, 6, 40, 211)
    g = pnoise(n, 2.0, 212)
    a = np.clip((m - 0.38) * 4.0, 0, 1)
    col = colorize(g, rgb((52, 78, 34)), rgb((96, 122, 52)))
    col *= (0.7 + m * 0.5)[..., None]
    save_old("leaves", np.dstack([col, a]))


def water():
    n = 256
    save_old("water_n", pnoise(n, 2.6, 231))


def city_windows():
    """Фасад «Красного города»: сетка окон, часть светится красным"""
    w, h = 256, 512
    img = np.zeros((h, w, 3))
    img[:] = rgb((14, 10, 12))
    rr = np.random.default_rng(241)
    for j in range(16):
        for i in range(8):
            x0, y0 = i * 32 + 7, j * 32 + 8
            if rr.random() < 0.55:
                c = rgb((255, 46, 30)) * rr.uniform(0.6, 1.0)
            else:
                c = rgb((30, 18, 18))
            img[y0:y0 + 16, x0:x0 + 18] = c
    save_old("city_windows", img)


def suburb():
    """Вид сверху на пригород (для концовки «небо»): кварталы, крыши, улицы"""
    n = 1024
    rr = np.random.default_rng(251)
    img = Image.new("RGB", (n, n), (96, 110, 70))
    d = ImageDraw.Draw(img)
    for i in range(0, n, 128):
        d.rectangle([i, 0, i + 14, n], fill=(70, 70, 72))
        d.rectangle([0, i, n, i + 14], fill=(70, 70, 72))
    for bx in range(0, n, 128):
        for by in range(0, n, 128):
            for k in range(8):
                hx = bx + 20 + (k % 4) * 26
                hy = by + 22 + (k // 4) * 52
                roof = tuple(int(c) for c in rr.integers(70, 170, 3))
                d.rectangle([hx, hy, hx + 18, hy + 26], fill=roof)
                if rr.random() < 0.3:
                    d.ellipse([hx + 2, hy + 30, hx + 14, hy + 42], fill=(60, 110, 140))
    img = img.filter(ImageFilter.GaussianBlur(0.8))
    img.save(os.path.join(OUT, "suburb.png"))
    print("   suburb")


def async_logo():
    """Простая эмблема: кольцо и разрыв (своя, не копия реального логотипа)"""
    n = 256
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([20, 20, 236, 236], outline=(230, 232, 236, 255), width=18)
    d.rectangle([118, 0, 138, 256], fill=(0, 0, 0, 0))
    d.ellipse([92, 92, 164, 164], fill=(230, 232, 236, 255))
    img.save(os.path.join(OUT, "async_mark.png"))
    print("   async_mark")


# ----------------------------------------------------------------- запуск

COMPLEX = {
    "wall_yellow": wallpaper_yellow, "wall_old": wallpaper_old, "wall_house": wallpaper_house,
    "wall_paint": wall_paint, "wall_school": wall_school, "wall_under": wall_under,
    "carpet": carpet, "ceiling_tile": ceiling, "fixture": fixture, "baseboard": baseboard,
    "concrete": concrete, "tile": tiles, "linoleum": linoleum, "wood_floor": wood_floor, "plaster": plaster,
    "wall_grime": wall_grime, "ceil_stains": ceil_stains, "carpet_damp": carpet_damp, "noise": noise_tex,
    "metal": metal, "fabric": fabric, "wood": wood, "paper": paper, "mold": mold, "fiber": fiber, "hazard": hazard,
}
LEGACY = [faces, grass, grass_tuft, path, bark, leaves, water, city_windows, suburb, async_logo]


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    os.makedirs(OUT, exist_ok=True)
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    print("Текстуры →", OUT)
    for name, fn in COMPLEX.items():
        if args and name not in args:
            continue
        fn()
    if "--legacy" in sys.argv:
        legacy_rng()
        for fn in LEGACY:
            fn()


if __name__ == "__main__":
    main()
