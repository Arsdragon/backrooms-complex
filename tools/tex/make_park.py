"""Процедурные текстуры парка (вступление: Сан-Хосе, 14.07.1990, ~16:12).

    python tools/tex/make_park.py [имя …]   → tex/park_*.png

Газон, сухой газон, земля под деревьями, асфальт дорожек, бетон площади, песок площадки, кора, листва (кластеры
листьев с альфой), пальмы, облака, макрошум, дальняя полоса деревьев/крыш, холмы, фасады. Всё бесшовное
(шумы периодические, штрихи у края рисуются с переносом). Только numpy + PIL.
"""
import os
import sys
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "tex")


# ----------------------------------------------------------------- общие функции

def pnoise(n, beta=2.0, seed=0, aniso=(1.0, 1.0), m=None):
    """Периодический шум 1/f^beta (n×m), нормированный в 0..1"""
    m = m or n
    r = np.random.default_rng(seed)
    w = r.standard_normal((n, m))
    f = np.fft.fft2(w)
    ky = np.fft.fftfreq(n)[:, None] * aniso[1]
    kx = np.fft.fftfreq(m)[None, :] * aniso[0]
    k = np.sqrt(kx * kx + ky * ky)
    k[0, 0] = 1.0
    f *= 1.0 / (k ** (beta / 2.0))
    f[0, 0] = 0
    o = np.real(np.fft.ifft2(f))
    o -= o.min()
    o /= o.max() + 1e-9
    return o


def band(n, lo, hi, seed=0, m=None):
    """Периодический шум в полосе частот (пятна заданного размера, в периодах на текстуру)"""
    m = m or n
    r = np.random.default_rng(seed)
    w = r.standard_normal((n, m))
    f = np.fft.fft2(w)
    ky = np.fft.fftfreq(n)[:, None] * n
    kx = np.fft.fftfreq(m)[None, :] * m
    k = np.sqrt(kx * kx + ky * ky)
    f *= np.exp(-((np.log(k + 1e-6) - math.log(math.sqrt(lo * hi))) ** 2) / (2 * (math.log(hi / lo) * 0.5 + 0.2) ** 2))
    f[0, 0] = 0
    o = np.real(np.fft.ifft2(f))
    o -= o.min()
    o /= o.max() + 1e-9
    return o


def blur(a, s):
    """Периодическое гауссово размытие (s — сигма в пикселях), для 2D и 3D массивов"""
    if s <= 0:
        return a
    n, m = a.shape[0], a.shape[1]
    ky = np.fft.fftfreq(n)[:, None]
    kx = np.fft.fftfreq(m)[None, :]
    g = np.exp(-2 * (math.pi ** 2) * (s ** 2) * (kx * kx + ky * ky))
    if a.ndim == 2:
        return np.real(np.fft.ifft2(np.fft.fft2(a) * g))
    return np.dstack([np.real(np.fft.ifft2(np.fft.fft2(a[..., c]) * g)) for c in range(a.shape[2])])


def rgb(c):
    return np.array(c, dtype=float) / 255.0


def lerp(a, b, t):
    return a + (b - a) * t


def save(name, arr, mode=None):
    arr = np.clip(arr, 0, 1)
    img = Image.fromarray((arr * 255 + 0.5).astype(np.uint8))
    img.save(os.path.join(OUT, name + ".png"))
    print("  ", name, img.size)


def bleed(col, a, it=10):
    """Цвет под прозрачными пикселями — из соседних непрозрачных (иначе на мип-уровнях тёмная кайма)"""
    w = (a > 0.02).astype(float)
    c = col * w[..., None]
    acc_c = c.copy()
    acc_w = w.copy()
    s = 1.0
    for _ in range(it):
        acc_c = blur(acc_c, s)
        acc_w = blur(acc_w, s)
        s *= 1.6
    fill = acc_c / np.maximum(acc_w, 1e-4)[..., None]
    return col * w[..., None] + fill * (1 - w[..., None])


class Canvas:
    """RGBA-холст PIL с суперсэмплингом и переносом через край (для бесшовных текстур)"""

    def __init__(self, w, h, ss=1, wrap=(True, True), bg=(0, 0, 0, 0)):
        self.w, self.h, self.ss, self.wrap = w, h, ss, wrap
        self.img = Image.new("RGBA", (w * ss, h * ss), bg)
        self.d = ImageDraw.Draw(self.img)

    def _offs(self, pts, margin):
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        ox = [0]
        oy = [0]
        if self.wrap[0]:
            if min(xs) < margin:
                ox.append(self.w)
            if max(xs) > self.w - margin:
                ox.append(-self.w)
        if self.wrap[1]:
            if min(ys) < margin:
                oy.append(self.h)
            if max(ys) > self.h - margin:
                oy.append(-self.h)
        return [(a, b) for a in ox for b in oy]

    def poly(self, pts, fill):
        s = self.ss
        for dx, dy in self._offs(pts, 2):
            self.d.polygon([((x + dx) * s, (y + dy) * s) for x, y in pts], fill=fill)

    def line(self, pts, fill, width):
        s = self.ss
        for dx, dy in self._offs(pts, width + 2):
            self.d.line([((x + dx) * s, (y + dy) * s) for x, y in pts], fill=fill, width=max(1, int(round(width * s))), joint="curve")

    def ellipse(self, cx, cy, rx, ry, fill):
        s = self.ss
        for dx, dy in self._offs([(cx - rx, cy - ry), (cx + rx, cy + ry)], 2):
            self.d.ellipse([(cx - rx + dx) * s, (cy - ry + dy) * s, (cx + rx + dx) * s, (cy + ry + dy) * s], fill=fill)

    def array(self):
        img = self.img
        if self.ss > 1:
            img = img.resize((self.w, self.h), Image.LANCZOS)
        return np.asarray(img).astype(float) / 255.0


def col255(c, a=1.0):
    c = np.clip(c, 0, 1)
    return (int(c[0] * 255), int(c[1] * 255), int(c[2] * 255), int(a * 255))


# ----------------------------------------------------------------- газон

def _lawn(name, seed, pal, soil, n_blades, dry_mix, clover=0.0):
    """Газон сверху: слой «войлока» (сухая трава и земля) и тысячи коротких травинок поверх, светлее к верхним слоям"""
    n = 1024
    rr = np.random.default_rng(seed)
    g1 = pnoise(n, 2.4, seed + 1)
    g2 = band(n, 20, 60, seed + 2)
    base = soil[None, None, :] * (0.75 + (g1 - 0.5) * 0.5 + (g2 - 0.5) * 0.25)[..., None]
    cv = Canvas(n, n, 1)
    clump = band(n, 6, 18, seed + 3)
    for layer in range(3):
        k = [0.45, 0.35, 0.2][layer]
        cnt = int(n_blades * k)
        bright = [0.62, 0.82, 1.0][layer]
        for _ in range(cnt):
            x, y = rr.uniform(0, n), rr.uniform(0, n)
            cl = clump[int(y) % n, int(x) % n]
            ln = rr.uniform(7, 22) * (0.8 + cl * 0.5)
            a = rr.uniform(0, math.tau)
            w = rr.uniform(1.4, 3.0)
            dry = rr.random() < dry_mix * (1.3 - cl * 0.6)
            c = pal[1] if dry else pal[0]
            c = c * rr.uniform(0.78, 1.18) * bright
            c = lerp(c, c * np.array([1.08, 1.0, 0.8]), rr.random() * 0.5)
            dx, dy = math.cos(a), math.sin(a)
            px, py = -dy * w * 0.5, dx * w * 0.5
            # травинка: широкое основание, острый кончик, лёгкий изгиб
            bend = rr.uniform(-0.25, 0.25)
            mx, my = x + dx * ln * 0.5 + px * bend * 6, y + dy * ln * 0.5 + py * bend * 6
            pts = [(x - px, y - py), (mx - px * 0.6, my - py * 0.6), (x + dx * ln, y + dy * ln), (mx + px * 0.6, my + py * 0.6), (x + px, y + py)]
            cv.poly(pts, col255(c))
        if clover > 0 and layer == 1:
            for _ in range(int(900 * clover)):
                x, y = rr.uniform(0, n), rr.uniform(0, n)
                if clump[int(y) % n, int(x) % n] < 0.55:
                    continue
                for j in range(3):
                    a = j * math.tau / 3 + rr.uniform(-0.3, 0.3)
                    r = rr.uniform(3.0, 4.5)
                    c = pal[0] * rr.uniform(0.85, 1.05) * np.array([0.85, 1.0, 0.9])
                    cv.ellipse(x + math.cos(a) * r, y + math.sin(a) * r, r, r, col255(c))
    top = cv.array()
    a = top[..., 3:4]
    col = base * (1 - a) + top[..., :3] * a
    # мелкая тень между травинками: где нет верхнего слоя — темнее
    col *= (0.82 + 0.18 * blur(a[..., 0], 1.2))[..., None]
    col = blur(col, 0.45)
    save(name, col)


def lawn():
    _lawn("park_grass", 7001, [rgb((84, 112, 40)), rgb((150, 140, 76))], rgb((70, 62, 38)), 150000, 0.07, clover=1.0)


def lawn_dry():
    _lawn("park_grass_dry", 7011, [rgb((112, 116, 52)), rgb((176, 152, 92))], rgb((104, 88, 60)), 110000, 0.55)


# ----------------------------------------------------------------- земля, асфальт, бетон, песок

def dirt():
    """Сухая утоптанная земля под деревьями: суглинок, камешки, опавшие листья, веточки, редкая трава"""
    n = 1024
    rr = np.random.default_rng(7021)
    g1 = pnoise(n, 2.2, 7022)
    g2 = band(n, 30, 120, 7023)
    g3 = band(n, 3, 8, 7024)
    soil = lerp(rgb((122, 104, 82)), rgb((148, 128, 102)), g3[..., None])
    col = soil * (0.82 + (g1 - 0.5) * 0.35 + (g2 - 0.5) * 0.3)[..., None]
    cv = Canvas(n, n, 2)
    # камешки
    for _ in range(2600):
        x, y = rr.uniform(0, n), rr.uniform(0, n)
        r = rr.uniform(1.0, 4.5) * (1.0 if rr.random() < 0.9 else 2.0)
        c = rgb((150, 140, 124)) * rr.uniform(0.6, 1.2)
        cv.ellipse(x + 0.8, y + 1.0, r, r * 0.8, col255(c * 0.45, 0.6))
        cv.ellipse(x, y, r, r * 0.8, col255(c))
    # опавшие листья (дуб, платан) и веточки
    for _ in range(520):
        x, y = rr.uniform(0, n), rr.uniform(0, n)
        ln = rr.uniform(10, 26)
        a = rr.uniform(0, math.tau)
        c = [rgb((120, 92, 56)), rgb((150, 120, 70)), rgb((96, 80, 60)), rgb((140, 132, 96))][rr.integers(0, 4)] * rr.uniform(0.8, 1.15)
        dx, dy = math.cos(a), math.sin(a)
        px, py = -dy, dx
        wd = ln * rr.uniform(0.3, 0.45)
        pts = [(x, y)]
        for t in np.linspace(0.15, 0.85, 5):
            wv = math.sin(t * math.pi) * wd * (1.0 + 0.15 * math.sin(t * 25))
            pts.append((x + dx * ln * t + px * wv, y + dy * ln * t + py * wv))
        pts.append((x + dx * ln, y + dy * ln))
        for t in np.linspace(0.85, 0.15, 5):
            wv = math.sin(t * math.pi) * wd * (1.0 + 0.15 * math.sin(t * 25))
            pts.append((x + dx * ln * t - px * wv, y + dy * ln * t - py * wv))
        cv.poly([(p[0] + 1.2, p[1] + 1.5) for p in pts], col255(c * 0.3, 0.45))
        cv.poly(pts, col255(c))
    for _ in range(160):
        x, y = rr.uniform(0, n), rr.uniform(0, n)
        pts = [(x, y)]
        a = rr.uniform(0, math.tau)
        for _k in range(rr.integers(3, 7)):
            a += rr.uniform(-0.5, 0.5)
            ln = rr.uniform(6, 16)
            x, y = x + math.cos(a) * ln, y + math.sin(a) * ln
            pts.append((x, y))
        cv.line(pts, col255(rgb((70, 52, 36)) * rr.uniform(0.8, 1.3)), rr.uniform(1.2, 2.6))
    for _ in range(2500):
        x, y = rr.uniform(0, n), rr.uniform(0, n)
        if g2[int(y) % n, int(x) % n] < 0.55:
            continue
        a = rr.uniform(0, math.tau)
        ln = rr.uniform(6, 16)
        cv.line([(x, y), (x + math.cos(a) * ln, y + math.sin(a) * ln)], col255(rgb((96, 112, 52)) * rr.uniform(0.7, 1.2)), 1.6)
    top = cv.array()
    a = top[..., 3:4]
    col = col * (1 - a) + top[..., :3] * a
    save("park_dirt", blur(col, 0.4))


def asphalt():
    """Старый выгоревший асфальт дорожек: светлый щебень, трещины, заливка трещин гудроном, пятна"""
    n = 1024
    rr = np.random.default_rng(7031)
    g1 = pnoise(n, 2.6, 7032)
    g2 = band(n, 8, 30, 7033)
    sp = rr.random((n, n))
    sp2 = blur(rr.random((n, n)), 0.7)
    col = np.ones((n, n, 3)) * rgb((112, 110, 104))[None, None, :] * (0.9 + (g1 - 0.5) * 0.25 + (g2 - 0.5) * 0.12)[..., None]
    # щебень: светлые и тёмные зёрна
    light = (sp > 0.93).astype(float)
    light = np.clip(blur(light, 0.6) * 2.2, 0, 1)
    dark = (sp2 < 0.32).astype(float) * 0.5
    col = col * (1 - dark[..., None] * 0.35)
    col = lerp(col, rgb((176, 170, 158))[None, None, :] * (0.85 + rr.random((n, n)) * 0.3)[..., None], light[..., None] * 0.75)
    cv = Canvas(n, n, 2)
    # заливка трещин (широкие тёмные «змеи»)
    for _ in range(4):
        x, y = rr.uniform(0, n), rr.uniform(0, n)
        a = rr.uniform(0, math.tau)
        pts = [(x, y)]
        for _k in range(rr.integers(8, 18)):
            a += rr.uniform(-0.6, 0.6)
            ln = rr.uniform(10, 28)
            x, y = x + math.cos(a) * ln, y + math.sin(a) * ln
            pts.append((x, y))
        cv.line(pts, col255(rgb((52, 50, 48)), 0.7), rr.uniform(3, 6))
    # тонкие трещины
    for _ in range(36):
        x, y = rr.uniform(0, n), rr.uniform(0, n)
        a = rr.uniform(0, math.tau)
        pts = [(x, y)]
        for _k in range(rr.integers(4, 14)):
            a += rr.uniform(-0.9, 0.9)
            ln = rr.uniform(6, 22)
            x, y = x + math.cos(a) * ln, y + math.sin(a) * ln
            pts.append((x, y))
        cv.line(pts, col255(rgb((56, 54, 52)), 0.75), rr.uniform(0.8, 1.8))
    top = cv.array()
    a = top[..., 3:4]
    col = col * (1 - a) + top[..., :3] * a
    # масляные и тёмные пятна, светлые потёртости
    st = np.clip((band(n, 4, 12, 7034) - 0.62) * 4.0, 0, 1)
    col *= (1 - st * 0.22)[..., None]
    wear = np.clip((band(n, 3, 9, 7035) - 0.6) * 3.0, 0, 1)
    col = lerp(col, col * 1.12, wear[..., None])
    save("park_asphalt", blur(col, 0.35))


def concrete():
    """Бетон площади: следы щётки, пятна жвачки, потёки"""
    n = 1024
    rr = np.random.default_rng(7041)
    g1 = pnoise(n, 2.4, 7042)
    brush = pnoise(n, 1.2, 7043, aniso=(0.08, 3.0))
    fine = blur(rr.random((n, n)), 0.6)
    col = np.ones((n, n, 3)) * rgb((170, 164, 150))[None, None, :]
    col *= (0.9 + (g1 - 0.5) * 0.18 + (brush - 0.5) * 0.12 + (fine - 0.5) * 0.12)[..., None]
    cv = Canvas(n, n, 2)
    for _ in range(220):
        x, y = rr.uniform(0, n), rr.uniform(0, n)
        r = rr.uniform(2.5, 6.0)
        cv.ellipse(x, y, r, r * rr.uniform(0.7, 1.0), col255(rgb((70, 68, 64)) * rr.uniform(0.8, 1.3), rr.uniform(0.35, 0.8)))
    for _ in range(900):
        x, y = rr.uniform(0, n), rr.uniform(0, n)
        r = rr.uniform(0.8, 2.0)
        cv.ellipse(x, y, r, r, col255(rgb((96, 92, 84)), 0.6))
    top = cv.array()
    a = top[..., 3:4]
    col = col * (1 - a) + top[..., :3] * a
    st = np.clip((band(n, 3, 10, 7044) - 0.6) * 3.0, 0, 1)
    col = lerp(col, col * np.array([0.86, 0.84, 0.8]), st[..., None] * 0.6)
    save("park_concrete", blur(col, 0.35))


def sand():
    """Песок детской площадки: зерно, следы, разворошённые бугорки"""
    n = 512
    rr = np.random.default_rng(7051)
    g1 = pnoise(n, 2.2, 7052)
    g2 = band(n, 6, 20, 7053)
    fine = blur(rr.random((n, n)), 0.55)
    col = np.ones((n, n, 3)) * rgb((190, 170, 136))[None, None, :]
    col *= (0.88 + (g1 - 0.5) * 0.2 + (g2 - 0.5) * 0.2 + (fine - 0.5) * 0.3)[..., None]
    pebble = (rr.random((n, n)) > 0.985).astype(float)
    col = lerp(col, col * 0.7, blur(pebble, 0.5)[..., None] * 1.5)
    save("park_sand", col)


# ----------------------------------------------------------------- кора

def bark():
    """Кора лиственных деревьев: вертикальные борозды, серо-коричневая, с пятнами лишайника"""
    n = 512
    rr = np.random.default_rng(7061)
    f = pnoise(n, 1.7, 7062, aniso=(1.0, 12.0))
    f2 = pnoise(n, 2.2, 7063, aniso=(1.0, 4.0))
    g = pnoise(n, 2.6, 7064)
    ridge = np.clip((f - 0.35) * 2.2, 0, 1) ** 0.8
    col = lerp(rgb((40, 32, 26))[None, None, :], rgb((122, 108, 92))[None, None, :], ridge[..., None])
    col *= (0.85 + (f2 - 0.5) * 0.4 + (g - 0.5) * 0.25)[..., None]
    lich = np.clip((band(n, 6, 20, 7065) - 0.68) * 5.0, 0, 1) * ridge
    col = lerp(col, rgb((140, 146, 116))[None, None, :], lich[..., None] * 0.55)
    save("park_bark", col)


def bark_euc():
    """Кора эвкалипта: гладкая светлая, с отслаивающимися серо-коричневыми лоскутами"""
    n = 512
    g = pnoise(n, 2.4, 7071, aniso=(1.0, 3.0))
    p = band(n, 3, 10, 7072, )
    p = blur(p, 1.0)
    patch = np.clip((pnoise(n, 2.0, 7073, aniso=(1.0, 4.0)) - 0.52) * 9.0, 0, 1)
    streak = pnoise(n, 1.4, 7074, aniso=(1.0, 14.0))
    smooth = lerp(rgb((206, 196, 172))[None, None, :], rgb((176, 172, 160))[None, None, :], g[..., None])
    peel = lerp(rgb((128, 104, 80))[None, None, :], rgb((150, 130, 110))[None, None, :], streak[..., None])
    col = lerp(smooth, peel, patch[..., None])
    # тень по краю лоскута
    edge = np.clip(blur(patch, 1.5) - patch, 0, 1)
    col *= (1 - edge * 1.2)[..., None]
    col *= (0.92 + (streak - 0.5) * 0.18)[..., None]
    save("park_bark_euc", col)


def palm_trunk():
    """Ствол вашингтонии: серо-бурый, кольцевые рубцы от старых листьев, волокна"""
    w, h = 256, 512
    rr = np.random.default_rng(7081)
    fib = pnoise(h, 1.5, 7082, aniso=(14.0, 1.0), m=w)
    g = pnoise(h, 2.4, 7083, m=w)
    wob = pnoise(h, 2.0, 7084, m=w)
    amp_n = pnoise(h, 1.6, 7085, m=w)
    yy = np.arange(h)[:, None].astype(float) + (wob - 0.5) * 9.0
    # рубцы от старых листьев: неровный шаг (2–6 см), разная глубина, по кругу то ярче, то почти нет;
    # тонкая тёмная бороздка и светлый валик над ней — без «зебры»
    rings = np.zeros((h, w))
    ridge = np.zeros((h, w))
    y0 = 0.0
    while y0 < h:
        a = rr.uniform(0.25, 1.0)
        d = (yy - y0 + h * 0.5) % h - h * 0.5
        rings += a * np.exp(-(d / rr.uniform(0.9, 1.8)) ** 2)
        ridge += a * np.exp(-((d + 2.5) / 2.2) ** 2)
        y0 += rr.uniform(6.0, 19.0)
    vis = 0.35 + 0.65 * amp_n
    # продольные трещины волокон
    crack = np.clip((pnoise(h, 1.3, 7086, aniso=(20.0, 1.0), m=w) - 0.62) * 4.0, 0, 1)
    col = np.ones((h, w, 3)) * rgb((132, 122, 108))[None, None, :]
    col *= (0.86 + (fib - 0.5) * 0.28 + (g - 0.5) * 0.26)[..., None]
    col *= (1 - np.clip(rings, 0, 1) * 0.22 * vis + np.clip(ridge, 0, 1) * 0.06 * vis - crack * 0.18)[..., None]
    # серые выветренные пятна
    grey = np.clip((band(h, 2, 6, 7087, m=w) - 0.55) * 3.0, 0, 1)
    col = lerp(col, col.mean(axis=2, keepdims=True) * 1.08, grey[..., None] * 0.5)
    save("park_palm_trunk", col)


# ----------------------------------------------------------------- листва

def _leaf_shape(cx, cy, ang, ln, wd, tipk=1.0, pts_n=9, serr=0.0, rr=None):
    """Контур листа: от черешка (cx, cy) в направлении ang"""
    dx, dy = math.cos(ang), math.sin(ang)
    px, py = -dy, dx
    left, right = [], []
    for i in range(1, pts_n):
        t = i / pts_n
        wv = (math.sin(t * math.pi) ** (0.8 * tipk)) * (1.0 - t * 0.25) * wd * 0.5
        if serr > 0 and rr is not None:
            wv *= 1.0 + serr * (0.5 - rr.random())
        bx, by = cx + dx * ln * t, cy + dy * ln * t
        left.append((bx + px * wv, by + py * wv))
        right.append((bx - px * wv, by - py * wv))
    return [(cx, cy)] + left + [(cx + dx * ln, cy + dy * ln)] + right[::-1]


def _cluster(cv, ox, oy, size, rr, kind):
    """Кластер листьев в ячейке атласа (ox, oy, size): веточка с листьями, листья по всей кроне карточки"""
    cx, cy = ox + size * 0.5, oy + size * 0.5
    if kind == "broad":
        pal = [rgb((58, 86, 30)), rgb((74, 102, 36)), rgb((92, 116, 44)), rgb((48, 72, 28)), rgb((104, 122, 52))]
        n_twig, n_leaf, lmin, lmax, wk = 9, 34, 0.075, 0.105, 0.5
    elif kind == "oak":
        pal = [rgb((40, 60, 24)), rgb((52, 72, 28)), rgb((62, 82, 34)), rgb((34, 50, 22)), rgb((74, 90, 40))]
        n_twig, n_leaf, lmin, lmax, wk = 11, 52, 0.045, 0.065, 0.62
    else:  # euc
        pal = [rgb((92, 106, 80)), rgb((104, 118, 88)), rgb((80, 96, 72)), rgb((118, 126, 96)), rgb((96, 104, 70))]
        n_twig, n_leaf, lmin, lmax, wk = 4, 18, 0.16, 0.26, 0.18
    # веточки расходятся из нижней части ячейки (у эвкалипта — свисают сверху)
    twigs = []
    for t in range(n_twig):
        if kind == "euc":
            sx, sy = cx + rr.uniform(-0.3, 0.3) * size, oy + size * 0.06
            a = math.pi * 0.5 + rr.uniform(-0.55, 0.55)
        else:
            # веточки расходятся во все стороны из точки чуть ниже центра — кластер круглый, без «ножки»
            sx, sy = cx + rr.uniform(-0.04, 0.04) * size, cy + size * 0.08
            a = t * math.tau / n_twig + rr.uniform(-0.4, 0.4)
        pts = [(sx, sy)]
        ln = size * (rr.uniform(0.55, 0.8) if kind == "euc" else rr.uniform(0.34, 0.44)) / 6
        for _k in range(6):
            a += rr.uniform(-0.18, 0.18)
            sx, sy = sx + math.cos(a) * ln, sy + math.sin(a) * ln
            pts.append((sx, sy))
        twigs.append(pts)
        tw = rgb((70, 52, 36)) if kind != "euc" else rgb((120, 70, 52))
        cv.line(pts, col255(tw), size * 0.008)
    # листья вдоль веточек; огибающая — эллипс, чтобы карточка не читалась квадратом
    for pts in twigs:
        for i in range(n_leaf):
            t = rr.uniform(0.15, 1.0)
            k = t * (len(pts) - 1)
            j = min(int(k), len(pts) - 2)
            f = k - j
            bx = pts[j][0] + (pts[j + 1][0] - pts[j][0]) * f
            by = pts[j][1] + (pts[j + 1][1] - pts[j][1]) * f
            ta = math.atan2(pts[j + 1][1] - pts[j][1], pts[j + 1][0] - pts[j][0])
            side = 1 if i % 2 == 0 else -1
            if kind == "euc":
                ang = math.pi * 0.5 + rr.uniform(-0.5, 0.5) + side * 0.25
            else:
                ang = ta + side * rr.uniform(0.5, 1.3)
            ln = size * rr.uniform(lmin, lmax)
            wd = ln * wk * rr.uniform(0.85, 1.15)
            ex = bx + math.cos(ang) * ln * 0.5 - cx
            ey = by + math.sin(ang) * ln * 0.5 - cy
            if (ex / (size * 0.47)) ** 2 + (ey / (size * 0.47)) ** 2 > 1.0:
                continue
            c = pal[rr.integers(0, len(pal))] * rr.uniform(0.85, 1.15)
            shape = _leaf_shape(bx, by, ang, ln, wd, 1.0 if kind != "euc" else 0.7, 11, 0.12 if kind == "oak" else 0.0, rr)
            cv.poly(shape, col255(c))
            # средняя жилка и светлая половинка листа
            half = [shape[0]] + shape[1:len(shape) // 2 + 1]
            cv.poly(half, col255(c * 1.1))
            cv.line([(bx, by), (bx + math.cos(ang) * ln * 0.85, by + math.sin(ang) * ln * 0.85)], col255(c * 1.25, 0.8), max(1.0, size * 0.003))


def _atlas(name, kind, seed, cells=2, size=512):
    rr = np.random.default_rng(seed)
    n = cells * size
    cv = Canvas(n, n, 2, wrap=(False, False))
    for j in range(cells):
        for i in range(cells):
            _cluster(cv, i * size, j * size, size, rr, kind)
    arr = cv.array()
    col, a = arr[..., :3], arr[..., 3]
    # мягкое затенение к центру кластера (листья внутри получают меньше света)
    yy, xx = np.mgrid[0:n, 0:n]
    u = (xx % size) / size - 0.5
    v = (yy % size) / size - 0.5
    r = np.sqrt(u * u + v * v) * 2
    col *= (0.78 + 0.22 * np.clip(r, 0, 1))[..., None]
    col = bleed(col, a)
    save(name, np.dstack([col, a]))


def leaves_broad():
    _atlas("park_leaf_broad", "broad", 7101)


def leaves_oak():
    _atlas("park_leaf_oak", "oak", 7111)


def leaves_euc():
    _atlas("park_leaf_euc", "euc", 7121)


def palm_fan():
    """Веерный лист вашингтонии: черешок снизу по центру, сплошная складчатая пластина до ~половины радиуса,
    дальше — отдельные узкие сегменты с просветами, кончики расходятся и загибаются, на них нити.
    Сплошным веер быть не должен: вдали (мип-уровни) он заливался в круглый «лист кувшинки»"""
    n = 512
    rr = np.random.default_rng(7131)
    cv = Canvas(n, n, 2, wrap=(False, False))
    cx, cy = n * 0.5, n * 0.64
    segs = 46
    span = math.radians(230) / segs
    for i in range(segs):
        t = i / (segs - 1)
        a = -math.pi * 0.5 + (t - 0.5) * math.radians(230)
        a2 = a + span
        r0 = n * 0.05
        r1 = n * rr.uniform(0.33, 0.37) * (0.85 + 0.15 * math.sin(t * math.pi))
        c = rgb((86, 108, 46)) * (1.12 if i % 2 == 0 else 0.86) * rr.uniform(0.9, 1.08)
        mid = (a + a2) * 0.5
        # сплошная часть пластины
        rs = r1 * rr.uniform(0.44, 0.56)
        cv.poly([(cx + math.cos(a) * r0, cy + math.sin(a) * r0), (cx + math.cos(a) * rs, cy + math.sin(a) * rs),
            (cx + math.cos(a2) * rs, cy + math.sin(a2) * rs), (cx + math.cos(a2) * r0, cy + math.sin(a2) * r0)], col255(c))
        # свободный сегмент: уже своей доли веера, сужается к острию, изогнут (у краёв веера — сильнее, «вниз»)
        bend = (t - 0.5) * 0.35 + rr.uniform(-0.1, 0.1)
        w0 = span * rr.uniform(0.68, 0.82)
        left, right = [], []
        steps = 6
        for k in range(steps + 1):
            u = k / steps
            r = rs * 0.97 + (r1 - rs * 0.97) * u
            ang = mid + bend * u * u * 0.6
            hw = w0 * 0.5 * (1.0 - u) ** 0.55
            left.append((cx + math.cos(ang - hw) * r, cy + math.sin(ang - hw) * r))
            right.append((cx + math.cos(ang + hw) * r, cy + math.sin(ang + hw) * r))
        cv.poly(left + right[::-1], col255(c))
        # свисающие нити на кончиках
        tip = left[-1]
        ta = mid + bend * 0.6
        for s in (-1, 1):
            ex = tip[0] + math.cos(ta + s * 0.12) * n * 0.05
            ey = tip[1] + math.sin(ta + s * 0.12) * n * 0.05 + n * 0.02
            cv.line([tip, (ex, ey)], col255(c * rgb((255, 230, 190)) * 0.95), 1.5)
    cv.line([(cx, cy), (cx, n)], col255(rgb((110, 112, 70))), n * 0.03)
    cv.ellipse(cx, cy, n * 0.06, n * 0.055, col255(rgb((96, 100, 52))))
    arr = cv.array()
    col, a = arr[..., :3], arr[..., 3]
    save("park_palm_fan", np.dstack([bleed(col, a), a]))


def palm_skirt():
    """«Юбка» сухих листьев под кроной вашингтонии: свисающие соломенные пряди, рваный низ"""
    w, h = 512, 512
    rr = np.random.default_rng(7141)
    cv = Canvas(w, h, 2, wrap=(True, False))
    for layer in range(3):
        for _ in range(380):
            x = rr.uniform(0, w)
            ln = h * rr.uniform(0.5, 0.97) if layer < 2 else h * rr.uniform(0.3, 0.8)
            c = [rgb((112, 94, 72)), rgb((92, 78, 62)), rgb((132, 114, 88)), rgb((76, 66, 56)), rgb((104, 100, 92))][rr.integers(0, 5)]
            c = c * rr.uniform(0.8, 1.1) * [0.7, 0.85, 1.0][layer]
            wd = rr.uniform(4, 12)
            sway = rr.uniform(-12, 12)
            pts = [(x - wd * 0.5, 0), (x + wd * 0.5, 0), (x + sway + wd * 0.2, ln), (x + sway - wd * 0.3, ln * 0.97)]
            cv.poly(pts, col255(c))
            cv.line([(x, 0), (x + sway, ln)], col255(c * 0.75), 1.2)
    arr = cv.array()
    col, a = arr[..., :3], arr[..., 3]
    y = np.arange(h)[:, None] / h
    col *= (0.55 + 0.45 * (1 - y))[..., None] * 0 + (0.75 + 0.25 * y)[..., None]
    save("park_palm_skirt", np.dstack([bleed(col, a), a]))


# ----------------------------------------------------------------- небо и даль

def clouds():
    """Облака: R — кучевые формы, G — детали, B — перистые полосы. В шейдере неба порог задаёт облачность"""
    n = 1024
    big = pnoise(n, 3.0, 7151)
    mid = band(n, 8, 24, 7152)
    det = band(n, 24, 90, 7153)
    cir = pnoise(n, 2.4, 7154, aniso=(0.6, 1.6))
    r = np.clip(big * 0.65 + mid * 0.35, 0, 1)
    save("park_clouds", np.dstack([r, det, cir]))


def macro():
    """Макрошум для земли и травы: R — крупные пятна (десятки метров), G — средние, B — мелкие"""
    n = 512
    save("park_noise", np.dstack([pnoise(n, 3.2, 7161), band(n, 10, 30, 7162), band(n, 40, 120, 7163)]))


def _crown(cv, rr, x, base, top, r, dark, light, n=70):
    """Крона дерева на дальнем плане: несколько комков листвы из сотен мелких пятен (рваный край),
    светлее сверху (солнце) и снаружи, тёмная середина; ствол снизу"""
    cy = base - top + r
    cv.poly([(x - r * 0.07, base), (x - r * 0.04, cy + r * 0.3), (x + r * 0.04, cy + r * 0.3), (x + r * 0.07, base)], col255(rgb((52, 46, 40))))
    lumps = [(x + rr.uniform(-0.45, 0.45) * r, cy + rr.uniform(-0.4, 0.35) * r, r * rr.uniform(0.45, 0.7)) for _ in range(rr.integers(4, 8))]
    lumps.append((x, cy, r * 0.7))
    for lx, ly, lr in lumps:
        for _ in range(int(n * 2.2 * (lr / r) ** 2) + 12):
            a = rr.uniform(0, math.tau)
            d = math.sqrt(rr.random()) * lr
            bx, by = lx + math.cos(a) * d, ly + math.sin(a) * d * 0.85
            br = rr.uniform(0.035, 0.09) * r
            out = d / lr
            lit = np.clip(0.55 - (by - (cy - r)) / (2 * r) * 0.55 + out * 0.25 + rr.uniform(-0.15, 0.15), 0.05, 1.0)
            cv.ellipse(bx, by, br, br * 0.85, col255(lerp(dark, light, lit)))


def street():
    """Квартал за парком: одноэтажные дома (штукатурка, низкие крыши), гаражи, заборы, кусты, деревья за домами,
    столбы с проводами. RGBA, бесшовно по горизонтали; высота текстуры 28 м, ширина 112 м, низ — уровень улицы"""
    w, h = 2048, 512
    rr = np.random.default_rng(7175)
    cv = Canvas(w, h, 2, wrap=(True, False))
    px_m = h / 28.0
    g0 = h - 1
    # деревья за домами
    x = 0.0
    while x < w:
        r = rr.uniform(3.0, 6.5) * px_m
        _crown(cv, rr, x, g0, rr.uniform(8, 16) * px_m, r, rgb((38, 50, 34)), rgb((92, 104, 66)), 60)
        x += r * rr.uniform(0.9, 2.2)
    # пара пальм и сосна над крышами
    for _ in range(3):
        px = rr.uniform(0, w)
        ph = rr.uniform(16, 22) * px_m
        tx = px + rr.uniform(-6, 6)
        cv.line([(px, g0), (tx, g0 - ph)], col255(rgb((96, 86, 72))), 5)
        # юбка сухих листьев и голова из вееров: на конце черешка — веер из расходящихся сегментов с
        # провисшими кончиками (не круглые «листья кувшинки»). Мелочи — из своего генератора: остальной
        # квартал (дома, заборы) рисуется теми же случайными числами, что и раньше
        fr = np.random.default_rng(int(px * 7.0) + 7190)
        cv.poly([(tx - 0.42 * px_m, g0 - ph + 0.2 * px_m), (tx + 0.42 * px_m, g0 - ph + 0.2 * px_m), (tx + 0.5 * px_m, g0 - ph + 1.8 * px_m), (tx - 0.5 * px_m, g0 - ph + 1.8 * px_m)], col255(rgb((96, 84, 66))))
        # рваный низ юбки: свисающие пряди разной длины
        for k in range(14):
            sx = tx + (k / 13.0 - 0.5) * 1.0 * px_m
            cv.line([(sx, g0 - ph + 1.6 * px_m), (sx + fr.uniform(-0.1, 0.1) * px_m, g0 - ph + fr.uniform(1.9, 2.8) * px_m)], col255(rgb((96, 84, 66)) * fr.uniform(0.75, 1.15)), 1.6)
        for j in range(24):
            a = -math.pi * 0.5 + rr.uniform(-2.2, 2.2)
            ln = rr.uniform(1.4, 2.2) * px_m
            ex, ey = tx + math.cos(a) * ln, g0 - ph + math.sin(a) * ln * 0.7 + ln * 0.25
            fc = rgb((80, 98, 54)) * rr.uniform(0.85, 1.15)
            cv.line([(tx, g0 - ph), (ex, ey)], col255(rgb((84, 92, 56))), 2)
            fa = math.atan2(ey - (g0 - ph), ex - tx)
            for k in range(11):
                sa = fa + (k / 10.0 - 0.5) * 2.0 + fr.uniform(-0.08, 0.08)
                sl = fr.uniform(0.55, 0.95) * px_m
                mx, my = ex + math.cos(sa) * sl * 0.6, ey + math.sin(sa) * sl * 0.6
                tx2, ty2 = ex + math.cos(sa) * sl, ey + math.sin(sa) * sl + sl * 0.35
                cv.line([(ex, ey), (mx, my), (tx2, ty2)], col255(fc * fr.uniform(0.8, 1.15)), 1.3)
    # дома
    x = rr.uniform(0, 4) * px_m
    walls = [rgb((222, 212, 188)), rgb((206, 196, 172)), rgb((214, 196, 150)), rgb((178, 186, 170)), rgb((196, 170, 140)), rgb((168, 118, 96)), rgb((200, 204, 190)), rgb((190, 196, 200)), rgb((226, 220, 204))]
    roofs = [rgb((92, 80, 70)), rgb((70, 66, 64)), rgb((110, 92, 76)), rgb((84, 84, 80))]
    while x < w - 10 * px_m:
        hw = rr.uniform(11, 16) * px_m
        wh = rr.uniform(2.6, 3.0) * px_m
        rh = rr.uniform(1.0, 1.7) * px_m
        wc = walls[rr.integers(0, len(walls))] * rr.uniform(0.84, 0.96)
        rc = roofs[rr.integers(0, len(roofs))] * rr.uniform(0.9, 1.1)
        top = g0 - wh
        cv.d.rectangle([x * 2, top * 2, (x + hw) * 2, g0 * 2], fill=col255(wc))
        # тень под свесом крыши
        cv.d.rectangle([x * 2, top * 2, (x + hw) * 2, (top + 0.35 * px_m) * 2], fill=col255(wc * 0.62))
        ov = 0.6 * px_m
        cv.poly([(x - ov, top + 2), (x + hw * 0.18, top - rh), (x + hw * 0.82, top - rh), (x + hw + ov, top + 2)], col255(rc))
        # гараж и окна
        gx = x + (hw * 0.62 if rr.random() < 0.5 else hw * 0.08)
        gw = 4.8 * px_m
        cv.d.rectangle([gx * 2, (g0 - 2.1 * px_m) * 2, (gx + gw) * 2, g0 * 2], fill=col255(wc * 0.9))
        for k in range(5):
            yy = g0 - 2.1 * px_m + k * 0.42 * px_m
            cv.line([(gx, yy), (gx + gw, yy)], col255(wc * 0.7), 1)
        # входная дверь под козырьком: тень крыльца, ступенька
        dx0 = x + (hw * 0.38 if gx > x + hw * 0.5 else hw * 0.7)
        dc = [rgb((92, 60, 40)), rgb((70, 76, 64)), rgb((150, 140, 120)), rgb((120, 40, 34))][rr.integers(0, 4)]
        cv.d.rectangle([(dx0 - 0.9 * px_m) * 2, (g0 - 2.5 * px_m) * 2, (dx0 + 1.9 * px_m) * 2, g0 * 2], fill=col255(wc * 0.72))
        cv.d.rectangle([dx0 * 2, (g0 - 2.1 * px_m) * 2, (dx0 + 0.95 * px_m) * 2, (g0 - 0.15 * px_m) * 2], fill=col255(dc))
        cv.d.rectangle([(dx0 - 0.3 * px_m) * 2, (g0 - 0.15 * px_m) * 2, (dx0 + 1.3 * px_m) * 2, g0 * 2], fill=col255(rgb((150, 146, 138))))
        shut = rr.random() < 0.45
        sc = [rgb((52, 64, 52)), rgb((70, 52, 40)), rgb((60, 66, 80))][rr.integers(0, 3)]
        wx = x + 0.8 * px_m
        while wx < x + hw - 1.6 * px_m:
            if not (gx - 1.0 * px_m < wx < gx + gw) and not (dx0 - 1.6 * px_m < wx < dx0 + 1.4 * px_m):
                ww = rr.uniform(1.2, 2.2) * px_m
                y0w, y1w = g0 - 2.05 * px_m, g0 - 0.95 * px_m
                cv.d.rectangle([wx * 2, y0w * 2, (wx + ww) * 2, y1w * 2], fill=col255(rgb((228, 224, 214))))
                cv.d.rectangle([(wx + 2) * 2, (y0w + 2) * 2, (wx + ww - 2) * 2, (y1w - 2) * 2], fill=col255(rgb((40, 44, 48))))
                # отражение неба в верхней половине стекла, переплёт, подоконник
                cv.d.rectangle([(wx + 2) * 2, (y0w + 2) * 2, (wx + ww - 2) * 2, ((y0w + y1w) * 0.5) * 2], fill=col255(rgb((86, 94, 104))))
                cv.line([(wx + ww * 0.5, y0w), (wx + ww * 0.5, y1w)], col255(rgb((228, 224, 214))), 1.5)
                cv.d.rectangle([(wx - 2) * 2, y1w * 2, (wx + ww + 2) * 2, (y1w + 3) * 2], fill=col255(wc * 0.8))
                if shut:
                    cv.d.rectangle([(wx - 0.45 * px_m) * 2, y0w * 2, (wx - 2) * 2, y1w * 2], fill=col255(sc))
                    cv.d.rectangle([(wx + ww + 2) * 2, y0w * 2, (wx + ww + 0.45 * px_m) * 2, y1w * 2], fill=col255(sc))
            wx += rr.uniform(2.4, 3.6) * px_m
        # кусты у стены
        for _ in range(int(hw / px_m)):
            bx = x + rr.uniform(0, hw)
            br = rr.uniform(0.5, 1.1) * px_m
            cv.ellipse(bx, g0 - br * 0.6, br, br * 0.8, col255(rgb((52, 70, 38)) * rr.uniform(0.8, 1.25)))
        x += hw + rr.uniform(3, 9) * px_m
    # деревянные заборы между домами и деревья перед ними
    for _ in range(8):
        fx = rr.uniform(0, w)
        fw = rr.uniform(4, 8) * px_m
        fc = rgb((120, 92, 66)) * rr.uniform(0.8, 1.1)
        cv.d.rectangle([fx * 2, (g0 - 1.8 * px_m) * 2, (fx + fw) * 2, g0 * 2], fill=col255(fc))
        k = fx
        while k < fx + fw:
            cv.line([(k, g0 - 1.8 * px_m), (k, g0)], col255(fc * 0.75), 1)
            k += 0.15 * px_m * 2
    for _ in range(9):
        _crown(cv, rr, rr.uniform(0, w), g0, rr.uniform(6, 10) * px_m, rr.uniform(2.2, 3.6) * px_m, rgb((44, 58, 36)), rgb((104, 118, 70)), 50)
    # столбы и провода
    poles = sorted(rr.uniform(0, w) for _ in range(5))
    pc = col255(rgb((70, 60, 50)))
    for px in poles:
        ph = 10.5 * px_m
        cv.line([(px, g0), (px, g0 - ph)], pc, 4)
        cv.line([(px - 1.0 * px_m, g0 - ph + 8), (px + 1.0 * px_m, g0 - ph + 8)], pc, 3)
    for i in range(len(poles)):
        a, b = poles[i], poles[(i + 1) % len(poles)] + (w if i == len(poles) - 1 else 0)
        for dy, dx in ((6, -1.0), (6, 1.0), (22, 0.0)):
            pts = []
            for t in np.linspace(0, 1, 24):
                xx = a + (b - a) * t + dx * px_m * (1 - abs(t - 0.5) * 2) * 0
                yy = g0 - 10.5 * px_m + dy + math.sin(t * math.pi) * 0.9 * px_m
                pts.append((xx + dx * px_m, yy))
            cv.line(pts, col255(rgb((40, 38, 36)), 0.85), 1.2)
    arr = cv.array()
    col, a = arr[..., :3], arr[..., 3]
    g = pnoise(h, 2.0, 7176, m=w)
    col *= (0.92 + (g - 0.5) * 0.16)[..., None]
    a[:4, :] = 0.0
    save("park_street", np.dstack([bleed(col, a, 6), a]))


def treeline():
    """Дальняя полоса деревьев с крышами и столбами: RGBA, бесшовно по горизонтали. Высота текстуры ~ 28 м"""
    w, h = 2048, 512
    rr = np.random.default_rng(7171)
    cv = Canvas(w, h, 1, wrap=(True, False))
    px_m = h / 28.0
    ground = h - 2
    # крыши и столбы за деревьями
    x = 0.0
    while x < w:
        hw = rr.uniform(8, 14) * px_m
        hh = rr.uniform(3.0, 5.0) * px_m
        if rr.random() < 0.55:
            roof = col255(rgb((96, 84, 76)) * rr.uniform(0.7, 1.2))
            cv.poly([(x, ground - hh), (x + hw * 0.5, ground - hh - rr.uniform(1.2, 2.2) * px_m), (x + hw, ground - hh), (x + hw, ground), (x, ground)], roof)
        x += hw + rr.uniform(2, 10) * px_m
    for k in range(9):
        px = rr.uniform(0, w)
        ph = rr.uniform(9, 11) * px_m
        cv.line([(px, ground), (px, ground - ph)], col255(rgb((60, 52, 44))), 3)
        cv.line([(px - 0.9 * px_m, ground - ph + 6), (px + 0.9 * px_m, ground - ph + 6)], col255(rgb((60, 52, 44))), 2)
    # кроны: перекрывающиеся «облака» листвы, светлее сверху
    crowns = []
    x = 0.0
    while x < w:
        r = rr.uniform(3.0, 7.5) * px_m
        top = rr.uniform(7, 18) * px_m
        crowns.append((x, top, r))
        x += r * rr.uniform(0.6, 1.3)
    for x, top, r in sorted(crowns, key=lambda c: -c[1]):
        _crown(cv, rr, x, ground, top, r, rgb((40, 52, 34)), rgb((96, 108, 64)), 60)
    # редкие пальмы над линией деревьев
    for k in range(5):
        px = rr.uniform(0, w)
        ph = rr.uniform(18, 25) * px_m
        cv.line([(px, ground), (px + rr.uniform(-4, 4), ground - ph)], col255(rgb((80, 72, 60))), 4)
        for j in range(14):
            a = -math.pi * 0.5 + rr.uniform(-1.6, 1.6)
            ln = rr.uniform(1.6, 2.6) * px_m
            cv.line([(px, ground - ph), (px + math.cos(a) * ln, ground - ph + math.sin(a) * ln * 0.6 + ln * 0.3)], col255(rgb((70, 84, 50))), 5)
    # низ — тёмная полоса кустов и тени
    for _ in range(400):
        bx = rr.uniform(0, w)
        br = rr.uniform(0.8, 2.0) * px_m
        cv.ellipse(bx, ground - br * 0.5, br, br * 0.8, col255(rgb((38, 46, 30)) * rr.uniform(0.8, 1.2)))
    # низ полосы — сплошные кусты и тень, чтобы сквозь основание не просвечивало небо
    cv.d.rectangle([0, ground - int(3.0 * px_m), w, h], fill=col255(rgb((40, 46, 32))))
    for _ in range(520):
        bx = rr.uniform(0, w)
        br = rr.uniform(1.2, 3.4) * px_m
        by = ground - rr.uniform(2.5, 4.5) * px_m
        lit = rr.uniform(0.75, 1.15)
        cv.ellipse(bx, by, br, br * 0.75, col255(rgb((46, 56, 36)) * lit))
    arr = cv.array()
    col, a = arr[..., :3], arr[..., 3]
    a[:4, :] = 0.0
    g = pnoise(h, 2.0, 7172, m=w)
    col *= (0.85 + (g - 0.5) * 0.3)[..., None]
    save("park_treeline", np.dstack([bleed(col, a, 6), a]))


def hills():
    """Летние холмы вокруг долины Санта-Клара: выгоревшая золотистая трава, тёмные дубы в ложбинах. RGBA, бесшовно по X"""
    w, h = 2048, 256
    rr = np.random.default_rng(7181)
    x = np.arange(w)
    def ridge(seed, amp, base):
        r = np.random.default_rng(seed).standard_normal(w)
        f = np.fft.fft(r)
        k = np.abs(np.fft.fftfreq(w) * w)
        k[0] = 1
        f *= 1.0 / k ** 1.75
        f *= np.exp(-(k / 160.0) ** 2)
        f[0] = 0
        o = np.real(np.fft.ifft(f))
        o = (o - o.min()) / (o.max() - o.min())
        return base - o * amp
    yy = np.arange(h)[:, None]
    r1 = ridge(7182, h * 0.75, h * 0.98)   # дальний хребет (выше)
    r2 = ridge(7183, h * 0.4, h * 1.0)     # ближние предгорья
    a1 = (yy >= r1[None, :]).astype(float)
    a2 = (yy >= r2[None, :]).astype(float)
    g = pnoise(h, 2.2, 7184, m=w)
    slope1 = np.gradient(r1)[None, :]
    gold = rgb((176, 150, 104))
    far = np.ones((h, w, 3)) * gold[None, None, :] * (0.9 + (g - 0.5) * 0.2)[..., None]
    far *= (1.0 + np.clip(blur(np.repeat(slope1, h, 0), 3.0) * 0.06, -0.15, 0.15))[..., None]
    near = np.ones((h, w, 3)) * rgb((164, 136, 88))[None, None, :] * (0.88 + (g - 0.5) * 0.3)[..., None]
    slope2 = np.gradient(r2)[None, :]
    near *= (1.0 + np.clip(blur(np.repeat(slope2, h, 0), 3.0) * 0.08, -0.2, 0.2))[..., None]
    # дубы: тёмные пятнышки, гуще в ложбинах (по шуму)
    oak = (rr.random((h, w)) > 0.985).astype(float) * (band(h, 6, 20, 7185, m=w) > 0.55)
    oak = np.clip(blur(oak, 0.9) * 4.0, 0, 1)
    near = lerp(near, rgb((70, 76, 50))[None, None, :], oak[..., None] * 0.8)
    oak2 = (rr.random((h, w)) > 0.99).astype(float) * (band(h, 6, 20, 7186, m=w) > 0.6)
    far = lerp(far, rgb((110, 112, 86))[None, None, :], np.clip(blur(oak2, 0.8) * 4, 0, 1)[..., None] * 0.6)
    col = far * (1 - a2[..., None]) + near * a2[..., None]
    a = np.maximum(a1, a2)
    a = np.clip(blur(a, 0.7), 0, 1)
    save("park_hills", np.dstack([bleed(col, a, 5), a]))


def facades():
    """Фасады дальних зданий центра (атлас 2×2): ленточные окна, сетка окон, тёмное стекло, кирпич"""
    n = 512
    s = n // 2
    img = np.zeros((n, n, 3))
    rr = np.random.default_rng(7191)
    yy, xx = np.mgrid[0:s, 0:s]
    # 0: бетон и ленточные окна (70-е)
    c0 = np.ones((s, s, 3)) * rgb((178, 170, 154))[None, None, :]
    band_ = ((yy % 16) < 7)
    c0[band_] = rgb((60, 70, 80))
    c0[band_ & ((xx % 32) == 0)] = rgb((140, 136, 128))
    img[:s, :s] = c0
    # 1: сетка окон на бежевом
    c1 = np.ones((s, s, 3)) * rgb((196, 182, 156))[None, None, :]
    win = ((yy % 16) >= 5) & ((yy % 16) < 13) & ((xx % 12) >= 3) & ((xx % 12) < 10)
    c1[win] = rgb((56, 62, 68))
    img[:s, s:] = c1
    # 2: тёмно-синее стекло с импостами
    c2 = np.ones((s, s, 3)) * rgb((52, 70, 88))[None, None, :]
    c2 *= (0.85 + 0.3 * pnoise(s, 2.0, 7192)[..., None])
    c2[(xx % 16) == 0] = rgb((120, 124, 128))
    c2[(yy % 16) == 0] = rgb((100, 104, 108))
    img[s:, :s] = c2
    # 3: кирпично-бурый с окнами
    c3 = np.ones((s, s, 3)) * rgb((140, 100, 80))[None, None, :]
    win3 = ((yy % 16) >= 4) & ((yy % 16) < 12) & ((xx % 10) >= 2) & ((xx % 10) < 8)
    c3[win3] = rgb((48, 52, 56))
    img[s:, s:] = c3
    # окна неодинаковые: где-то шторы (светлее), где-то тёмные; межэтажные пояса
    win_var = np.repeat(np.repeat(rr.random((n // 8, n // 6 + 1)), 8, 0), 6, 1)[:n, :n]
    dark = (img.sum(axis=2) < 0.75)
    img[dark] *= (0.75 + 0.6 * win_var[dark])[..., None]
    img *= (0.92 + 0.16 * pnoise(n, 2.0, 7193))[..., None]
    save("park_facade", img)


def _font(names, size):
    from PIL import ImageFont
    for nm in names:
        try:
            return ImageFont.truetype(nm, size)
        except OSError:
            pass
    return ImageFont.load_default()


def _words(rr, n):
    syl = ["the", "an", "ci", "ty", "coun", "cil", "vote", "on", "new", "plan", "for", "wa", "ter", "rates", "said",
           "mon", "day", "of", "fi", "cials", "in", "san", "jo", "se", "and", "state", "bud", "get", "heat", "wave",
           "high", "school", "teach", "ers", "re", "port", "will", "be", "sum", "mer", "tem", "per", "a", "tures"]
    out = []
    for _ in range(n):
        out.append("".join(syl[rr.integers(0, len(syl))] for _ in range(rr.integers(1, 4))))
    return out


def _page(rr, w, h, front, ink, paper):
    """Полоса газеты: шапка или колонтитул, заголовки, фото (растр), колонки текста, рекламные блоки"""
    img = Image.new("RGB", (w, h), paper)
    d = ImageDraw.Draw(img)
    serif = ["times.ttf", "DejaVuSerif.ttf"]
    serif_b = ["timesbd.ttf", "DejaVuSerif-Bold.ttf"]
    body = _font(serif, 11)
    m = 22
    y = m
    if front:
        d.text((w // 2, y), "The Valley Herald", fill=ink, font=_font(["georgiab.ttf"] + serif_b, 50), anchor="mt")
        y += 60
        d.line([(m, y), (w - m, y)], fill=ink, width=3)
        d.text((m, y + 4), "SATURDAY, JULY 14, 1990", fill=ink, font=_font(serif, 12))
        d.text((w - m, y + 4), "25 CENTS", fill=ink, font=_font(serif, 12), anchor="ra")
        y += 22
        d.line([(m, y), (w - m, y)], fill=ink, width=1)
        y += 10
        hs = 40
        while d.textlength("HEAT WAVE GRIPS VALLEY", font=_font(serif_b, hs)) > w - 2 * m and hs > 12:
            hs -= 2
        d.text((w // 2, y), "HEAT WAVE GRIPS VALLEY", fill=ink, font=_font(serif_b, hs), anchor="mt")
        y += 50
        d.text((w // 2, y), "Record 104 degrees in San Jose; power use peaks", fill=ink, font=_font(serif, 18), anchor="mt")
        y += 30
    else:
        d.text((m, y), "B4  THE VALLEY HERALD", fill=ink, font=_font(serif_b, 13))
        d.text((w - m, y), "SATURDAY, JULY 14, 1990", fill=ink, font=_font(serif, 12), anchor="ra")
        y += 18
        d.line([(m, y), (w - m, y)], fill=ink, width=2)
        y += 10
    cols = 4
    cw = (w - 2 * m - (cols - 1) * 10) // cols
    # блоки: фото и реклама занимают несколько колонок
    blocks = []
    if front:
        blocks.append((0, y, 3, y + 210, "photo"))
    else:
        blocks.append((2, y + rr.integers(80, 200), 2, 0, "ad"))
        blocks.append((0, h - m - 170, 2, h - m, "ad2"))
    for c0, y0, span, y1, kind in blocks:
        x0 = m + c0 * (cw + 10)
        x1 = x0 + span * cw + (span - 1) * 10
        if kind == "photo":
            yy, xx = np.mgrid[0:y1 - y0, 0:x1 - x0]
            g = pnoise(256, 2.2, int(rr.integers(1, 9999)))
            g = np.array(Image.fromarray((g * 255).astype(np.uint8)).resize((x1 - x0, y1 - y0))) / 255.0
            g = np.clip((g - 0.5) * 1.3 + 0.55 + (yy / (y1 - y0) - 0.5) * 0.25, 0, 1)
            bayer = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0
            ph = np.where(g > bayer[yy % 4, xx % 4], 0.84, 0.2)
            ph = (ph * 255).astype(np.uint8)
            img.paste(Image.fromarray(np.dstack([ph, ph, ph])), (x0, y0))
            d.rectangle([x0, y0, x1, y1], outline=ink, width=1)
            d.text((x0, y1 + 4), "Children cool off at a fountain in Plaza Park.", fill=ink, font=_font(serif, 11))
        else:
            yy1 = y1 if y1 else y0 + 170
            d.rectangle([x0, y0, x1, yy1], outline=ink, width=3)
            t = "SALE" if kind == "ad" else "USED CARS"
            d.text(((x0 + x1) // 2, y0 + 16), t, fill=ink, font=_font(serif_b, 34), anchor="mt")
            d.text(((x0 + x1) // 2, y0 + 64), "THIS WEEKEND ONLY", fill=ink, font=_font(serif_b, 16), anchor="mt")
            d.text(((x0 + x1) // 2, y0 + 92), "1990 models  $8,995", fill=ink, font=_font(serif, 16), anchor="mt")
    # колонки текста с подзаголовками, в обход блоков
    for c in range(cols):
        x0 = m + c * (cw + 10)
        yy = y
        while yy < h - m - 12:
            hit = None
            for c0, y0, span, y1, kind in blocks:
                ye = (y1 if y1 else y0 + 170) + (22 if kind == "photo" else 8)
                if c0 <= c < c0 + span and y0 - 12 <= yy <= ye:
                    hit = ye
            if hit is not None:
                yy = hit + 6
                continue
            if rr.random() < 0.035:
                sub = ""
                for wd in _words(rr, 4):
                    if d.textlength((sub + " " + wd).title(), font=_font(serif_b, 16)) > cw:
                        break
                    sub = (sub + " " + wd).strip()
                d.text((x0, yy + 4), sub.title(), fill=ink, font=_font(serif_b, 16))
                yy += 26
                continue
            line = ""
            for wd in _words(rr, 12):
                if d.textlength(line + " " + wd, font=body) > cw:
                    break
                line = (line + " " + wd).strip()
            d.text((x0, yy), line, fill=ink, font=body)
            yy += 13
    return np.asarray(img).astype(float) / 255.0


def newspaper():
    """Развёрнутая газета (1990): верх — внешний разворот (слева последняя полоса, справа первая с шапкой),
    низ — внутренний разворот. Каждый разворот 1024×744 (0,58 × 0,42 м), между ними поле"""
    rr = np.random.default_rng(7201)
    paper = (226, 221, 204)
    ink = (34, 34, 38)
    pw, ph = 512, 744
    outer = np.hstack([_page(rr, pw, ph, False, ink, paper), _page(rr, pw, ph, True, ink, paper)])
    inner = np.hstack([_page(rr, pw, ph, False, ink, paper), _page(rr, pw, ph, False, ink, paper)])
    img = np.ones((1536, 1024, 3)) * rgb(paper)[None, None, :]
    img[0:744] = outer
    img[792:1536] = inner
    # сгиб посередине и пожелтевшие края, лёгкая неровность бумаги
    x = np.arange(1024)[None, :]
    img *= (1.0 - 0.12 * np.exp(-((x - 512) / 5.0) ** 2))[..., None]
    g = pnoise(512, 2.0, 7202)
    g = np.array(Image.fromarray((g * 255).astype(np.uint8)).resize((1024, 1536))) / 255.0
    img *= (0.95 + (g - 0.5) * 0.08)[..., None]
    save("park_newspaper", blur(img, 0.4))


ALL = {
    "newspaper": newspaper,
    "grass": lawn, "grass_dry": lawn_dry, "dirt": dirt, "asphalt": asphalt, "concrete": concrete, "sand": sand,
    "bark": bark, "bark_euc": bark_euc, "palm_trunk": palm_trunk,
    "leaf_broad": leaves_broad, "leaf_oak": leaves_oak, "leaf_euc": leaves_euc, "palm_fan": palm_fan, "palm_skirt": palm_skirt,
    "clouds": clouds, "noise": macro, "treeline": treeline, "street": street, "hills": hills, "facade": facades,
}


def main():
    os.makedirs(OUT, exist_ok=True)
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    want = sys.argv[1:] or list(ALL.keys())
    print("Текстуры парка →", OUT)
    for k in want:
        ALL[k]()


if __name__ == "__main__":
    main()
