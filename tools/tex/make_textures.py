"""Процедурные бесшовные текстуры для Комплекса, парка и концовок.

    python tools/tex/make_textures.py      → tex/*.png
Все шумы периодические (фильтрация в частотной области), поэтому текстуры тайлятся без швов.
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "tex")
rng = np.random.default_rng(1990)


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


def save(name, arr):
    arr = np.clip(arr, 0, 1)
    if arr.ndim == 2:
        img = Image.fromarray((arr * 255).astype(np.uint8))
    elif arr.shape[2] == 3:
        img = Image.fromarray((arr * 255).astype(np.uint8))
    else:
        img = Image.fromarray((arr * 255).astype(np.uint8))
    img.save(os.path.join(OUT, name + ".png"))
    print("  ", name)


def rgb(c):
    return np.array(c, dtype=float) / 255.0


def colorize(mask, a, b):
    return a[None, None, :] * (1 - mask[..., None]) + b[None, None, :] * mask[..., None]


def stains(n, amount, seed, size=(2, 9)):
    m = band(n, size[0], size[1], seed)
    return np.clip((m - (1.0 - amount)) / amount, 0, 1) ** 1.5


# ----------------------------------------------------------------- Комплекс

def wallpaper_yellow():
    """Однотонно-жёлтые обои с еле заметным вертикальным узором — главная текстура Комплекса.
    Текстура покрывает 0.8 × 0.8 м."""
    n = 512
    base = rgb((196, 178, 96))
    y, x = np.mgrid[0:n, 0:n] / n
    grain = pnoise(n, 2.6, 11) * 0.5 + pnoise(n, 1.0, 12) * 0.5
    # полосы по 4 см (20 полос на 0.8 м)
    stripes = (np.floor(x * 20) % 2)
    # шевроны внутри светлых полос
    cx = (x * 20) % 1.0
    cy = (y * 20) % 1.0
    chev = np.abs(cy - np.abs(cx - 0.5) * 0.6 - 0.35)
    chev = (chev < 0.06).astype(float) * stripes
    chev = np.array(Image.fromarray((chev * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))) / 255.0
    lum = 1.0 + stripes * 0.022 - chev * 0.045 + (grain - 0.5) * 0.06
    col = base[None, None, :] * lum[..., None]
    col *= (1.0 - 0.03 * (pnoise(n, 3.0, 13) - 0.5))[..., None]
    save("wall_yellow", col)
    # грязный вариант: подтёки, жёлтые пятна, плесневые разводы
    st = stains(n, 0.45, 14, (2, 7))
    drip = pnoise(n, 2.0, 15, aniso=(0.4, 6.0))
    drip = np.clip((drip - 0.55) * 3.0, 0, 1)
    dirty = col * (1.0 - st[..., None] * rgb((60, 70, 110))[None, None, :] * 0.9)
    dirty = dirty * (1.0 - drip[..., None] * 0.18)
    dirty = dirty * (0.92 + 0.08 * grain[..., None])
    save("wall_yellow_dirty", dirty)


def wallpaper_old():
    n = 512
    y, x = np.mgrid[0:n, 0:n] / n
    base = rgb((150, 128, 92))
    s = np.sin(x * np.pi * 2 * 12) * 0.5 + 0.5
    s2 = (np.floor(x * 24) % 3 == 0).astype(float)
    grain = pnoise(n, 2.4, 21)
    lum = 1.0 + (s - 0.5) * 0.05 - s2 * 0.06 + (grain - 0.5) * 0.08
    col = base[None, None, :] * lum[..., None]
    save("wall_old", col)
    st = stains(n, 0.5, 22, (2, 6))
    save("wall_old_dirty", col * (1.0 - st[..., None] * 0.35))


def wallpaper_house():
    n = 512
    y, x = np.mgrid[0:n, 0:n] / n
    base = rgb((168, 160, 128))
    img = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(img)
    for i in range(6):
        for j in range(6):
            cx = (i + 0.5 * (j % 2)) * n / 6
            cy = j * n / 6
            for k in range(5):
                a = k / 5 * 2 * np.pi
                px, py = cx + np.cos(a) * 12, cy + np.sin(a) * 12
                for ox in (-n, 0, n):
                    for oy in (-n, 0, n):
                        d.ellipse([px - 7 + ox, py - 7 + oy, px + 7 + ox, py + 7 + oy], fill=255)
    fl = np.array(img.filter(ImageFilter.GaussianBlur(1.2))) / 255.0
    grain = pnoise(n, 2.4, 31)
    col = colorize(fl * 0.6, base, rgb((150, 118, 112)))
    col *= (0.95 + 0.1 * grain)[..., None]
    save("wall_house", col)
    st = stains(n, 0.5, 32, (2, 6))
    save("wall_house_dirty", col * (1.0 - st[..., None] * 0.35))


def carpet():
    """Влажный ковролин: мелкий ворс, буро-жёлтый. Покрывает 1.5 × 1.5 м."""
    n = 512
    fine = rng.random((n, n))
    fine = np.array(Image.fromarray((fine * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6))) / 255.0
    mid = pnoise(n, 2.2, 41)
    big = pnoise(n, 3.2, 42)
    base = rgb((132, 112, 58))
    lum = 0.82 + (fine - 0.5) * 0.35 + (mid - 0.5) * 0.18 + (big - 0.5) * 0.12
    col = base[None, None, :] * lum[..., None]
    save("carpet", col)
    wet = stains(n, 0.55, 43, (1, 5))
    save("carpet_wet", col * (1.0 - wet[..., None] * 0.42) * np.array([0.97, 0.98, 1.0])[None, None, :])
    # старый офисный ковёр: серо-синий с узором
    y, x = np.mgrid[0:n, 0:n] / n
    pat = ((np.floor(x * 16) + np.floor(y * 16)) % 2) * 0.05
    b2 = rgb((92, 92, 96))
    col2 = b2[None, None, :] * (0.85 + (fine - 0.5) * 0.4 + pat + (mid - 0.5) * 0.2)[..., None]
    save("carpet_old", col2)


def ceiling():
    """Подвесной потолок: плиты 0.6×1.2 м (две плиты на 1.2×1.2 м), точечная фактура, металлическая решётка"""
    n = 512
    y, x = np.mgrid[0:n, 0:n] / n
    base = rgb((214, 210, 196))
    pits = rng.random((n, n))
    pits = (pits > 0.93).astype(float)
    pits = np.array(Image.fromarray((pits * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.7))) / 255.0
    fiss = pnoise(n, 1.4, 51)
    lum = 0.93 - pits * 0.25 + (fiss - 0.5) * 0.08 + (pnoise(n, 3.0, 52) - 0.5) * 0.06
    col = base[None, None, :] * lum[..., None]
    # решётка: линии по x каждые 0.6 м (каждые 256 px), по z каждые 1.2 м (край)
    gx = np.minimum(np.abs(x * 2 - np.round(x * 2)), 1.0) * n / 2
    gy = np.minimum(np.abs(y - np.round(y)), 1.0) * n
    grid = ((gx < 3.0) | (gy < 3.0)).astype(float)
    edge = ((gx < 6.0) | (gy < 6.0)).astype(float) - grid
    col = col * (1.0 - edge[..., None] * 0.12)
    col = col * (1 - grid[..., None]) + rgb((226, 224, 216))[None, None, :] * grid[..., None]
    save("ceiling_tile", col)
    st = stains(n, 0.35, 53, (1, 5))
    save("ceiling_tile_dirty", col * (1.0 - st[..., None] * rgb((70, 80, 120))[None, None, :] * 0.8))


def fixture():
    """Рассеиватель люминесцентного светильника (призматический) с рамкой; UV 0..1 на панель"""
    w, h = 128, 256
    y, x = np.mgrid[0:h, 0:w]
    pr = (np.sin(x * 1.2) * np.sin(y * 1.2)) * 0.5 + 0.5
    frame = ((x < 6) | (x > w - 7) | (y < 6) | (y > h - 7)).astype(float)
    # «трубки» за рассеивателем светлее
    tubes = np.exp(-((x - w * 0.3) ** 2) / 120.0) + np.exp(-((x - w * 0.7) ** 2) / 120.0)
    lum = 0.78 + pr * 0.08 + tubes * 0.16
    col = np.stack([lum, lum * 0.985, lum * 0.94], -1)
    col = col * (1 - frame[..., None]) + np.array([0.78, 0.78, 0.76])[None, None, :] * frame[..., None]
    a = np.ones((h, w))
    save("fixture", np.dstack([col, (1 - frame) * 1.0 + frame * 0.0]))


def baseboard():
    n = 256
    g = pnoise(n, 2.5, 61)
    col = rgb((205, 196, 170))[None, None, :] * (0.92 + (g - 0.5) * 0.12)[..., None]
    sc = stains(n, 0.3, 62, (3, 12))
    save("baseboard", col * (1.0 - sc[..., None] * 0.3))


def concrete():
    n = 512
    g = pnoise(n, 2.2, 71)
    f = rng.random((n, n))
    f = np.array(Image.fromarray((f * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.5))) / 255.0
    base = rgb((118, 116, 110))
    lum = 0.85 + (g - 0.5) * 0.3 + (f - 0.5) * 0.12
    # опалубочные швы
    y, x = np.mgrid[0:n, 0:n] / n
    seam = (np.abs(y * 2 - np.round(y * 2)) * n / 2 < 1.5).astype(float)
    col = base[None, None, :] * (lum - seam * 0.12)[..., None]
    save("concrete", col)
    st = stains(n, 0.5, 72, (2, 8))
    drip = np.clip((pnoise(n, 2.0, 73, aniso=(0.4, 6.0)) - 0.5) * 3, 0, 1)
    save("concrete_dirty", col * (1.0 - st[..., None] * 0.45) * (1.0 - drip[..., None] * 0.25))
    # пол бетонный
    save("concrete_floor", base[None, None, :] * (0.78 + (g - 0.5) * 0.35 + (f - 0.5) * 0.15)[..., None])


def tiles():
    n = 512
    y, x = np.mgrid[0:n, 0:n] / n
    # плитка 15 см, текстура 1.2 м → 8 плиток
    gx = np.abs(x * 8 - np.round(x * 8)) * n / 8
    gy = np.abs(y * 8 - np.round(y * 8)) * n / 8
    grout = ((gx < 2.0) | (gy < 2.0)).astype(float)
    g = pnoise(n, 2.5, 81)
    tile_var = rng.random((8, 8))
    tv = tile_var[(np.floor(y * 8) % 8).astype(int), (np.floor(x * 8) % 8).astype(int)]
    col = rgb((222, 224, 218))[None, None, :] * (0.92 + tv * 0.05 + (g - 0.5) * 0.05)[..., None]
    col = col * (1 - grout[..., None]) + rgb((140, 140, 130))[None, None, :] * grout[..., None]
    save("tile", col)
    st = stains(n, 0.4, 82, (2, 7))
    save("tile_dirty", col * (1.0 - st[..., None] * rgb((80, 90, 60))[None, None, :] * 0.7))


def wood_floor():
    n = 512
    y, x = np.mgrid[0:n, 0:n] / n
    plank = np.floor(x * 6)
    off = (plank * 0.37) % 1.0
    yy = (y + off) % 1.0
    joint = (np.abs(x * 6 - np.round(x * 6)) * n / 6 < 1.5) | (np.abs(yy * 2 - np.round(yy * 2)) * n / 2 < 1.2)
    grain = pnoise(n, 2.0, 91, aniso=(0.5, 8.0))
    col = rgb((120, 84, 52))[None, None, :] * (0.8 + (grain - 0.5) * 0.4 + (plank % 3) * 0.04)[..., None]
    col *= (1 - joint.astype(float) * 0.45)[..., None]
    save("wood_floor", col)


def plaster():
    n = 256
    g = pnoise(n, 2.4, 101)
    save("plaster", rgb((206, 200, 186))[None, None, :] * (0.93 + (g - 0.5) * 0.1)[..., None])


def noise_tex():
    n = 256
    a = pnoise(n, 2.4, 111)
    b = pnoise(n, 3.0, 112)
    c = band(n, 4, 16, 113)
    save("noise", np.dstack([a, b, c]))


def mold():
    """Чёрная плесень/бактерия: пятна с альфой"""
    n = 256
    y, x = np.mgrid[0:n, 0:n] / n - 0.5
    r = np.sqrt(x * x + y * y)
    m = band(n, 3, 30, 121) * 0.6 + pnoise(n, 1.6, 122) * 0.4
    a = np.clip((m - 0.35) * 3.0, 0, 1) * np.clip((0.5 - r) * 4, 0, 1)
    dots = (rng.random((n, n)) > 0.985) * np.clip((0.48 - r) * 3, 0, 1)
    a = np.clip(a + dots, 0, 1)
    col = np.dstack([np.full((n, n), 0.05), np.full((n, n), 0.055), np.full((n, n), 0.045)])
    save("mold", np.dstack([col, a]))


def fiber():
    """Волокна/лозы для Сущности (серый, растянут вдоль V)"""
    n = 256
    f = pnoise(n, 1.8, 131, aniso=(1.0, 12.0))
    f2 = pnoise(n, 2.5, 132)
    save("fiber", np.clip(f * 0.7 + f2 * 0.3, 0, 1))


def paper():
    n = 512
    g = pnoise(n, 2.2, 141)
    col = rgb((226, 218, 196))[None, None, :] * (0.94 + (g - 0.5) * 0.1)[..., None]
    st = stains(n, 0.25, 142, (1, 4))
    save("paper", col * (1.0 - st[..., None] * rgb((40, 60, 110))[None, None, :] * 0.5))


def hazard():
    w, h = 256, 64
    y, x = np.mgrid[0:h, 0:w]
    s = ((x + y) // 32) % 2
    col = np.where(s[..., None] == 0, rgb((214, 170, 30))[None, None, :], rgb((25, 22, 20))[None, None, :])
    g = pnoise(256, 2.0, 151)[:h, :w]
    save("hazard", col * (0.85 + 0.15 * g[..., None]))


def fabric():
    n = 256
    y, x = np.mgrid[0:n, 0:n]
    weave = (np.sin(x * 1.6) * np.sin(y * 1.6)) * 0.5 + 0.5
    g = pnoise(n, 2.4, 161)
    save("fabric", np.clip(0.8 + weave * 0.1 + (g - 0.5) * 0.2, 0, 1))


def metal():
    n = 256
    g = pnoise(n, 2.0, 171, aniso=(10.0, 0.6))
    g2 = pnoise(n, 2.8, 172)
    save("metal", np.clip(0.75 + (g - 0.5) * 0.15 + (g2 - 0.5) * 0.2, 0, 1))


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
    rows = np.arange(n)
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


# ----------------------------------------------------------------- парк и концовки

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
    save("grass", col)


def paints():
    """Крашеные стены магазина и школы, линолеум"""
    n = 512
    y, x = np.mgrid[0:n, 0:n] / n
    g = pnoise(n, 2.6, 401)
    f = pnoise(n, 1.4, 402)
    col = rgb((214, 208, 190))[None, None, :] * (0.95 + (g - 0.5) * 0.06 + (f - 0.5) * 0.03)[..., None]
    save("wall_paint", col)
    st = stains(n, 0.45, 403, (2, 7))
    drip = np.clip((pnoise(n, 2.0, 404, aniso=(0.4, 6.0)) - 0.55) * 3.0, 0, 1)
    save("wall_paint_dirty", col * (1.0 - st[..., None] * 0.35) * (1.0 - drip[..., None] * 0.2))
    # школа: снизу зелёная масляная краска, полоса, сверху беж (текстура = высота 2.4 м)
    low = rgb((96, 132, 104))
    up = rgb((214, 206, 176))
    yy = y
    band = (np.abs(yy - 0.5) < 0.012).astype(float)
    col2 = np.where((yy < 0.5)[..., None], low[None, None, :], up[None, None, :]) * (0.95 + (g - 0.5) * 0.08)[..., None]
    col2 = col2 * (1 - band[..., None]) + rgb((60, 70, 60))[None, None, :] * band[..., None]
    save("wall_school", col2)
    st2 = stains(n, 0.4, 405, (2, 6))
    save("wall_school_dirty", col2 * (1.0 - st2[..., None] * 0.3))
    # линолеум: плитки 30 см шахматкой (текстура 1.2 м)
    chk = ((np.floor(x * 4) + np.floor(y * 4)) % 2)
    gl = (np.abs(x * 4 - np.round(x * 4)) * n / 4 < 1.0) | (np.abs(y * 4 - np.round(y * 4)) * n / 4 < 1.0)
    col3 = np.where(chk[..., None] > 0.5, rgb((176, 170, 150))[None, None, :], rgb((120, 118, 108))[None, None, :])
    col3 = col3 * (0.92 + (g - 0.5) * 0.12)[..., None] * (1 - gl[..., None] * 0.25)
    save("linoleum", col3)
    st3 = stains(n, 0.4, 406, (1, 5))
    save("linoleum_dirty", col3 * (1.0 - st3[..., None] * 0.4))
    # обои с отслоением: тёмная основа под обоями
    save("wall_under", rgb((96, 86, 60))[None, None, :] * (0.8 + (g - 0.5) * 0.3)[..., None])


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
    save("path", col * (1 - seam[..., None] * 0.3))
    # асфальт
    col2 = rgb((62, 62, 64))[None, None, :] * (0.85 + (g - 0.5) * 0.25 + (f - 0.5) * 0.4)[..., None]
    save("asphalt", col2)


def bark():
    n = 256
    f = pnoise(n, 1.6, 201, aniso=(0.7, 10.0))
    g = pnoise(n, 2.6, 202)
    col = rgb((86, 72, 58))[None, None, :] * (0.65 + f * 0.5 + (g - 0.5) * 0.2)[..., None]
    save("bark", col)


def leaves():
    n = 256
    m = band(n, 6, 40, 211)
    g = pnoise(n, 2.0, 212)
    a = np.clip((m - 0.38) * 4.0, 0, 1)
    col = colorize(g, rgb((52, 78, 34)), rgb((96, 122, 52)))
    col *= (0.7 + m * 0.5)[..., None]
    save("leaves", np.dstack([col, a]))


def wood():
    n = 256
    f = pnoise(n, 1.8, 221, aniso=(0.5, 9.0))
    col = rgb((140, 98, 60))[None, None, :] * (0.7 + f * 0.45)[..., None]
    save("wood", col)


def water():
    n = 256
    save("water_n", pnoise(n, 2.6, 231))


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
    save("city_windows", img)


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


def main():
    os.makedirs(OUT, exist_ok=True)
    print("Текстуры →", OUT)
    wallpaper_yellow()
    wallpaper_old()
    wallpaper_house()
    carpet()
    ceiling()
    fixture()
    baseboard()
    concrete()
    tiles()
    wood_floor()
    plaster()
    noise_tex()
    mold()
    fiber()
    paper()
    hazard()
    fabric()
    metal()
    faces()
    grass()
    grass_tuft()
    paints()
    path()
    bark()
    leaves()
    wood()
    water()
    city_windows()
    suburb()
    async_logo()


if __name__ == "__main__":
    main()
